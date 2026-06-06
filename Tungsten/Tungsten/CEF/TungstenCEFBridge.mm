/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Objective-C++ bridge between SwiftUI/AppKit and Chromium Embedded Framework.
*/

#import "TungstenCEFApp.h"
#import "TungstenBrowserController.h"
#import "../Performance/TungstenPerformanceLog.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <climits>
#include <memory>
#include <string>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/cef_request_handler.h"
#include "include/cef_request_context.h"
#include "include/cef_resource_request_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "wrapper/cef_library_loader.h"

@interface TungstenBrowserController ()
- (void)cefBrowserDidClose;
- (void)closeBrowserWithForce:(BOOL)forceClose;
- (void)completePageContentRequestWithPayload:(NSString *)payloadString;
- (void)logPerformanceEvent:(NSString *)event metadata:(NSDictionary<NSString *, id> *)metadata;
@end

namespace {

// External message pump for CEF on macOS.
//
// Chromium drives almost everything in the browser process — IPC, compositor
// frame submission, input dispatch, JS callbacks — through CefDoMessageLoopWork().
// We feed it from two places:
//
//   1. A CFRunLoopObserver fires before AppKit handles run-loop sources and
//      again before the main run loop sleeps. The BeforeSources tick matters
//      during live scrolling, when AppKit can keep the run loop busy with
//      event tracking and CEF's before-idle work otherwise arrives late.
//   2. A one-shot dispatch timer wakes us up at the exact delay CEF asks for in
//      OnScheduleMessagePumpWork(delay_ms). We honor the delay verbatim — no
//      artificial cap — so frame pacing tracks Chromium's own scheduler.
//
// CEF passes delay_ms == INT_MAX to mean "no scheduled work"; in that case we
// simply cancel any pending timer and rely on the BeforeWaiting observer to
// pick up late-arriving tasks.

bool g_messagePumpActive = false;
bool g_messagePumpReentry = false;
bool g_immediateMessagePumpWorkPending = false;
dispatch_source_t g_messagePumpTimer = nullptr;
CFRunLoopObserverRef g_beforeWaitingObserver = nullptr;

constexpr int64_t kCefNoScheduledWork = INT_MAX;
constexpr CFTimeInterval kSlowCefMessagePumpWork = 0.008;

extern "C" NSString *const TungstenLocalAIProviderDefaultsKey = @"Tungsten.LocalAIProvider.v1";
extern "C" NSString *const TungstenContentBlockingEnabledDefaultsKey = @"Tungsten.ContentBlockingEnabled.v1";

NSString *ShortPerformanceID(void) {
    return [NSUUID.UUID.UUIDString substringToIndex:8];
}

NSMutableDictionary<NSString *, id> *PerformanceURLMetadata(NSString *urlString) {
    NSMutableDictionary<NSString *, id> *metadata = [NSMutableDictionary dictionary];
    metadata[@"has_url"] = @(urlString.length > 0);
    metadata[@"url_length"] = @(urlString.length);

    NSURLComponents *components = [NSURLComponents componentsWithString:urlString ?: @""];
    metadata[@"scheme"] = components.scheme ?: @"nil";
    metadata[@"host"] = components.host ?: @"nil";
    return metadata;
}

std::string RendererPerformanceMarkerScript() {
    return R"JS(
(() => {
  const marker = 'TUNGSTEN_PERF_MARK:';
  const emitted = new Set();
  const emit = (name, extra = {}) => {
    if (emitted.has(name)) {
      return;
    }
    emitted.add(name);
    const navigation = performance.getEntriesByType('navigation')[0];
    const payload = {
      name,
      href: location.href,
      readyState: document.readyState,
      since_navigation_start_ms: Math.round(performance.now() * 100) / 100,
      ...extra
    };
    if (navigation) {
      payload.dom_content_loaded_event_end_ms =
        Math.round(navigation.domContentLoadedEventEnd * 100) / 100;
      payload.load_event_end_ms = Math.round(navigation.loadEventEnd * 100) / 100;
      payload.response_end_ms = Math.round(navigation.responseEnd * 100) / 100;
    }
    console.log(marker + JSON.stringify(payload));
  };

  const emitDOMContentLoaded = () => emit('DOMContentLoaded');
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', emitDOMContentLoaded, { once: true });
  } else {
    emitDOMContentLoaded();
  }

  window.addEventListener('load', () => emit('windowLoad'), { once: true });

  const emitPaint = entry => {
    if (entry && (entry.name === 'first-paint' || entry.name === 'first-contentful-paint')) {
      emit(entry.name, {
        paint_start_ms: Math.round(entry.startTime * 100) / 100
      });
    }
  };

  for (const entry of performance.getEntriesByType('paint')) {
    emitPaint(entry);
  }

  try {
    const observer = new PerformanceObserver(list => {
      for (const entry of list.getEntries()) {
        emitPaint(entry);
      }
    });
    observer.observe({ type: 'paint', buffered: true });
  } catch (_) {
    // Older renderers can lack buffered paint observation; existing entries
    // above still cover the common case.
  }
})()
)JS";
}

void LogRendererPerformanceMarker(TungstenBrowserController *controller,
                                  CefRefPtr<CefBrowser> browser,
                                  const std::string &payload) {
    NSString *payloadString = [NSString stringWithUTF8String:payload.c_str()];
    if (payloadString.length == 0) {
        [controller logPerformanceEvent:@"cef.renderer.mark" metadata:@{
            @"browser_id": @(browser->GetIdentifier()),
            @"parse_error": @"empty_payload"
        }];
        return;
    }

    NSData *data = [payloadString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *payloadDictionary = nil;
    if (data != nil) {
        id parsedPayload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([parsedPayload isKindOfClass:NSDictionary.class]) {
            payloadDictionary = parsedPayload;
        }
    }

    NSMutableDictionary<NSString *, id> *metadata = [NSMutableDictionary dictionary];
    metadata[@"browser_id"] = @(browser->GetIdentifier());
    if (payloadDictionary == nil) {
        metadata[@"parse_error"] = @"invalid_json";
        metadata[@"payload_length"] = @(payloadString.length);
        [controller logPerformanceEvent:@"cef.renderer.mark" metadata:metadata];
        return;
    }

    NSString *href = [payloadDictionary[@"href"] isKindOfClass:NSString.class] ?
        payloadDictionary[@"href"] : @"";
    [metadata addEntriesFromDictionary:PerformanceURLMetadata(href)];
    metadata[@"mark_name"] = [payloadDictionary[@"name"] isKindOfClass:NSString.class] ?
        payloadDictionary[@"name"] : @"unknown";
    metadata[@"ready_state"] = [payloadDictionary[@"readyState"] isKindOfClass:NSString.class] ?
        payloadDictionary[@"readyState"] : @"unknown";

    for (NSString *key in @[
        @"since_navigation_start_ms",
        @"dom_content_loaded_event_end_ms",
        @"load_event_end_ms",
        @"response_end_ms",
        @"paint_start_ms"
    ]) {
        id value = payloadDictionary[key];
        if ([value isKindOfClass:NSNumber.class]) {
            metadata[key] = value;
        }
    }

    [controller logPerformanceEvent:@"cef.renderer.mark" metadata:metadata];
}

std::string JoinFeatureList(const std::vector<std::string> &features) {
    std::string joined;
    for (const std::string &feature : features) {
        if (!joined.empty()) {
            joined += ",";
        }
        joined += feature;
    }
    return joined;
}

void PerformCefMessageLoopWork(void) {
    if (![[TungstenCEFApp shared] isInitialized]) {
        return;
    }

    if (g_messagePumpActive) {
        g_messagePumpReentry = true;
        return;
    }

    do {
        g_messagePumpReentry = false;
        g_messagePumpActive = true;
        CFTimeInterval pumpStart = TungstenPerformanceLogNow();
        // Note: an Objective-C exception thrown deep inside CEF unwinds
        // through Chromium frames compiled with -fno-exceptions and aborts
        // before any local @catch can see it. We log via
        // NSSetUncaughtExceptionHandler in AppDelegate instead.
        CefDoMessageLoopWork();
        CFTimeInterval pumpDuration = TungstenPerformanceLogNow() - pumpStart;
        if (pumpDuration > kSlowCefMessagePumpWork) {
            TungstenPerformanceLogDuration(@"cef.messagePump.workSlow", pumpStart, nil);
        }
        g_messagePumpActive = false;
    } while (g_messagePumpReentry);
}

void CancelCefMessagePumpTimer(void) {
    if (g_messagePumpTimer != nullptr) {
        dispatch_source_cancel(g_messagePumpTimer);
        g_messagePumpTimer = nullptr;
    }
}

void ScheduleCefMessageLoopWork(int64_t delayMs) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ScheduleCefMessageLoopWork(delayMs);
        });
        return;
    }

    if (![[TungstenCEFApp shared] isInitialized]) {
        return;
    }

    if (delayMs >= kCefNoScheduledWork) {
        // Nothing scheduled — let the BeforeWaiting observer handle any late work.
        CancelCefMessagePumpTimer();
        return;
    }

    if (delayMs <= 0) {
        CancelCefMessagePumpTimer();
        if (g_immediateMessagePumpWorkPending) {
            return;
        }
        g_immediateMessagePumpWorkPending = true;
        dispatch_async(dispatch_get_main_queue(), ^{
            g_immediateMessagePumpWorkPending = false;
            PerformCefMessageLoopWork();
        });
        return;
    }

    CancelCefMessagePumpTimer();

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0,
                                                     0,
                                                     dispatch_get_main_queue());
    int64_t nanos = delayMs * NSEC_PER_MSEC;
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, nanos),
                              DISPATCH_TIME_FOREVER,
                              static_cast<uint64_t>(NSEC_PER_MSEC));
    dispatch_source_set_event_handler(timer, ^{
        if (g_messagePumpTimer == timer) {
            g_messagePumpTimer = nullptr;
        }
        PerformCefMessageLoopWork();
    });
    g_messagePumpTimer = timer;
    dispatch_resume(timer);
}

void CefRunLoopPumpCallback(__unused CFRunLoopObserverRef observer,
                            __unused CFRunLoopActivity activity,
                            __unused void *info) {
    PerformCefMessageLoopWork();
}

void InstallCefRunLoopObserver(void) {
    if (g_beforeWaitingObserver != nullptr) {
        return;
    }
    CFRunLoopActivity activities = kCFRunLoopBeforeSources | kCFRunLoopBeforeWaiting;
    g_beforeWaitingObserver = CFRunLoopObserverCreate(kCFAllocatorDefault,
                                                      activities,
                                                      true,
                                                      0,
                                                      &CefRunLoopPumpCallback,
                                                      nullptr);
    CFRunLoopAddObserver(CFRunLoopGetMain(), g_beforeWaitingObserver, kCFRunLoopCommonModes);
}

void UninstallCefRunLoopObserver(void) {
    if (g_beforeWaitingObserver == nullptr) {
        return;
    }
    CFRunLoopRemoveObserver(CFRunLoopGetMain(), g_beforeWaitingObserver, kCFRunLoopCommonModes);
    CFRelease(g_beforeWaitingObserver);
    g_beforeWaitingObserver = nullptr;
}

NSString *TungstenApplicationSupportDirectory(void) {
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                    inDomains:NSUserDomainMask];
    NSURL *baseURL = urls.firstObject;
    NSURL *cacheURL = [baseURL URLByAppendingPathComponent:@"Tungsten/CEF" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:cacheURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    return cacheURL.path;
}

std::string ToString(NSString *value) {
    return value == nil ? std::string() : std::string(value.UTF8String);
}

NSString *ToNSString(const CefString &value) {
    return [NSString stringWithUTF8String:value.ToString().c_str()];
}

BOOL TungstenContentBlockingEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:TungstenContentBlockingEnabledDefaultsKey];
}

BOOL TungstenHostMatchesSuffix(NSString *host, NSString *suffix) {
    if (host.length == 0 || suffix.length == 0) {
        return NO;
    }
    return [host isEqualToString:suffix] || [host hasSuffix:[@"." stringByAppendingString:suffix]];
}

BOOL TungstenShouldBlockResource(NSString *urlString) {
    if (!TungstenContentBlockingEnabled() || urlString.length == 0) {
        return NO;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    NSString *scheme = components.scheme.lowercaseString ?: @"";
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }

    NSString *host = components.host.lowercaseString ?: @"";
    static NSArray<NSString *> *blockedHostSuffixes;
    static dispatch_once_t blockedHostSuffixesOnce;
    dispatch_once(&blockedHostSuffixesOnce, ^{
        blockedHostSuffixes = @[
            @"doubleclick.net",
            @"googlesyndication.com",
            @"googleadservices.com",
            @"googletagmanager.com",
            @"googletagservices.com",
            @"adservice.google.com",
            @"scorecardresearch.com",
            @"quantserve.com",
            @"adsystem.com",
            @"adnxs.com",
            @"taboola.com",
            @"outbrain.com",
            @"criteo.com",
            @"rubiconproject.com",
            @"pubmatic.com",
            @"openx.net",
            @"moatads.com",
            @"adsrvr.org",
            @"yieldmo.com",
            @"bidswitch.net",
            @"connect.facebook.net",
            @"facebook.net",
            @"bat.bing.com",
            @"hotjar.com",
            @"hotjar.io",
            @"segment.io",
            @"segment.com",
            @"mixpanel.com"
        ];
    });

    for (NSString *suffix in blockedHostSuffixes) {
        if (TungstenHostMatchesSuffix(host, suffix)) {
            return YES;
        }
    }

    NSString *lowerURL = urlString.lowercaseString ?: @"";
    static NSArray<NSString *> *blockedURLNeedles;
    static dispatch_once_t blockedURLNeedlesOnce;
    dispatch_once(&blockedURLNeedlesOnce, ^{
        blockedURLNeedles = @[
            @"/pagead/",
            @"/gampad/",
            @"/adserver/",
            @"/adsystem/",
            @"/prebid",
            @"/advertisement",
            @"/track/imp",
            @"/pixel?",
            @"/beacon?",
            @"?adurl=",
            @"&adurl=",
            @"utm_medium=paid",
            @"utm_source=ad"
        ];
    });

    for (NSString *needle in blockedURLNeedles) {
        if ([lowerURL containsString:needle]) {
            return YES;
        }
    }

    return NO;
}

NSAppearance *NonVibrantBrowserAppearanceForWindow(NSWindow *window) {
    NSAppearance *source = window.effectiveAppearance ?: NSApp.effectiveAppearance;
    NSAppearanceName match = [source bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameDarkAqua,
        NSAppearanceNameAqua
    ]];
    NSAppearanceName browserAppearanceName = [match isEqualToString:NSAppearanceNameDarkAqua]
        ? NSAppearanceNameDarkAqua
        : NSAppearanceNameAqua;
    return [NSAppearance appearanceNamed:browserAppearanceName];
}

void ApplyCEFSubviewCompositing(NSView *view, NSAppearance *appearance) {
    if (view == nil) {
        return;
    }

    view.appearance = appearance;
    view.wantsLayer = YES;

    CALayer *layer = view.layer;
    if (layer != nil) {
        layer.opaque = YES;
        layer.backgroundColor = NSColor.whiteColor.CGColor;
    }

    for (NSView *subview in view.subviews) {
        ApplyCEFSubviewCompositing(subview, appearance);
    }
}

class TungstenCefApp final : public CefApp, public CefBrowserProcessHandler {
public:
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
        return this;
    }

    void OnBeforeCommandLineProcessing(const CefString &process_type,
                                       CefRefPtr<CefCommandLine> command_line) override {
        std::vector<std::string> disabledFeatures = {
            "DialMediaRouteProvider",
            "MediaRouter",
            "Translate",
            "OptimizationHints",
            "AutofillServerCommunication"
        };

        std::vector<std::string> enabledFeatures = {
            "PlatformHEVCDecoderSupport",
            "VideoToolboxVp9Decoder",
            "VideoToolboxAv1Decoder",
            "UseMultiPlaneFormatForHardwareVideo",
            "CanvasOopRasterization",
            "ParallelDownloading"
        };

        // Features we explicitly turn off. We don't ship UI for any of these,
        // so paying their startup, memory, and background-traffic cost is pure
        // waste: Translate spawns a renderer worker for every page, MediaRouter
        // (Cast) keeps a discovery service alive, OptimizationHints chats with
        // a Google service, and AutofillServerCommunication uploads form
        // structure to Google's autofill backend.
        command_line->AppendSwitchWithValue(
            "disable-features",
            JoinFeatureList(disabledFeatures)
        );

        // Hardware-decode coverage on Apple Silicon: HEVC for Apple TV+/Disney+,
        // VP9 for the bulk of YouTube/Twitch, AV1 for newer YouTube streams
        // (M3+ has a hardware AV1 block; M1/M2 fall back gracefully).
        // UseMultiPlaneFormatForHardwareVideo keeps decoded frames as
        // multi-plane IOSurfaces all the way to the compositor — Apple
        // Silicon's unified memory makes that copy-elision a clean win.
        // CanvasOopRasterization moves canvas raster off the renderer main
        // thread; ParallelDownloading splits large downloads across streams.
        command_line->AppendSwitchWithValue(
            "enable-features",
            JoinFeatureList(enabledFeatures)
        );

        // Force ANGLE/Metal explicitly so we don't fall back to the OpenGL path
        // on the off chance Chromium misdetects.
        command_line->AppendSwitchWithValue("use-angle", "metal");

        command_line->AppendSwitch("enable-zero-copy");
        command_line->AppendSwitch("enable-gpu-rasterization");

        // Match the wide-gamut panel on every M1+ MacBook. Chromium's GPU
        // raster path (Metal ANGLE + Skia Graphite) inside our embedding
        // doesn't auto-detect the display profile correctly; without an
        // explicit value, sRGB pixels reach a P3 surface unconverted and
        // saturated colors read pale. Chrome wires this up via its own
        // NSWindow setup; CEF embedders have to be explicit.
        command_line->AppendSwitchWithValue("force-color-profile", "display-p3-d65");

        command_line->AppendSwitch("use-mock-keychain");
    }

    void OnScheduleMessagePumpWork(int64_t delay_ms) override {
        ScheduleCefMessageLoopWork(delay_ms);
    }

private:
    IMPLEMENT_REFCOUNTING(TungstenCefApp);
};

class TungstenBrowserClient final : public CefClient,
                                    public CefDisplayHandler,
                                    public CefLifeSpanHandler,
                                    public CefLoadHandler,
                                    public CefRequestHandler,
                                    public CefResourceRequestHandler {
public:
    explicit TungstenBrowserClient(__weak TungstenBrowserController *controller)
        : controller_(controller) {}

    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override {
        return this;
    }

    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override {
        return this;
    }

    CefRefPtr<CefLoadHandler> GetLoadHandler() override {
        return this;
    }

    CefRefPtr<CefRequestHandler> GetRequestHandler() override {
        return this;
    }

    CefRefPtr<CefBrowser> browser() const {
        return browser_;
    }

    CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(
        CefRefPtr<CefBrowser> browser,
        CefRefPtr<CefFrame> frame,
        CefRefPtr<CefRequest> request,
        bool is_navigation,
        bool is_download,
        const CefString &request_initiator,
        bool &disable_default_handling) override {
        if (!TungstenContentBlockingEnabled() || is_navigation || is_download) {
            return nullptr;
        }
        return this;
    }

    ReturnValue OnBeforeResourceLoad(CefRefPtr<CefBrowser> browser,
                                     CefRefPtr<CefFrame> frame,
                                     CefRefPtr<CefRequest> request,
                                     CefRefPtr<CefCallback> callback) override {
        if (!request || request->GetResourceType() == RT_MAIN_FRAME) {
            return RV_CONTINUE;
        }

        NSString *urlString = ToNSString(request->GetURL());
        if (TungstenShouldBlockResource(urlString)) {
            return RV_CANCEL;
        }
        return RV_CONTINUE;
    }

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        browser_ = browser;
        TungstenBrowserController *controller = controller_;
        [controller logPerformanceEvent:@"cef.browser.afterCreated" metadata:@{
            @"browser_id": @(browser->GetIdentifier())
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller layoutBrowserView];
        });
    }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        if (browser_ && browser_->IsSame(browser)) {
            browser_ = nullptr;
        }
        TungstenBrowserController *controller = controller_;
        [controller logPerformanceEvent:@"cef.browser.beforeClose" metadata:@{
            @"browser_id": @(browser->GetIdentifier())
        }];
        [controller cefBrowserDidClose];
    }

    bool DoClose(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();

        NSView *browserView = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
        [browserView removeFromSuperview];
        TungstenBrowserController *controller = controller_;
        [controller logPerformanceEvent:@"cef.browser.doClose" metadata:@{
            @"browser_id": @(browser->GetIdentifier())
        }];

        // This browser is hosted as a child view inside SwiftUI. Returning
        // false would make CEF send a default close event to the top-level
        // NSWindow, which is the wrong ownership boundary for closing a tab.
        return true;
    }

    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
        NSString *titleString = ToNSString(title);
        // Capture the controller strongly *before* dispatching. Reading the
        // controller_ ivar inside the block captures `this`, which can be freed
        // before the block runs on the main thread (e.g. the tab closes as a
        // title arrives) — a use-after-free that crashes in ___forwarding___.
        // Every sibling callback below already captures the controller locally.
        TungstenBrowserController *controller = controller_;
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller.delegate browserController:controller didUpdateTitle:titleString];
        });
    }

    void OnAddressChange(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefFrame> frame,
                         const CefString &url) override {
        if (!frame->IsMain()) {
            return;
        }

        NSString *urlString = ToNSString(url);
        TungstenBrowserController *controller = controller_;
        NSMutableDictionary<NSString *, id> *metadata = PerformanceURLMetadata(urlString);
        metadata[@"browser_id"] = @(browser->GetIdentifier());
        [controller logPerformanceEvent:@"cef.addressChange" metadata:metadata];
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller.delegate browserController:controller didUpdateURL:urlString];
        });
    }

    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                              bool isLoading,
                              bool canGoBack,
                              bool canGoForward) override {
        TungstenBrowserController *controller = controller_;
        NSString *urlString = @"";
        CefRefPtr<CefFrame> mainFrame = browser ? browser->GetMainFrame() : nullptr;
        if (mainFrame) {
            urlString = ToNSString(mainFrame->GetURL());
        }
        NSMutableDictionary<NSString *, id> *metadata = PerformanceURLMetadata(urlString);
        metadata[@"browser_id"] = @(browser->GetIdentifier());
        metadata[@"is_loading"] = @(isLoading);
        metadata[@"can_go_back"] = @(canGoBack);
        metadata[@"can_go_forward"] = @(canGoForward);
        [controller logPerformanceEvent:@"cef.load.state" metadata:metadata];

        dispatch_async(dispatch_get_main_queue(), ^{
            [controller.delegate browserController:controller
                                 didUpdateLoading:isLoading
                                        canGoBack:canGoBack
                                     canGoForward:canGoForward];
        });
    }

    void OnLoadStart(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     TransitionType transition_type) override {
        if (!frame->IsMain()) {
            return;
        }

        TungstenBrowserController *controller = controller_;
        NSString *urlString = ToNSString(frame->GetURL());
        NSMutableDictionary<NSString *, id> *metadata = PerformanceURLMetadata(urlString);
        metadata[@"browser_id"] = @(browser->GetIdentifier());
        metadata[@"transition_type"] = @((int)transition_type);
        [controller logPerformanceEvent:@"cef.load.start" metadata:metadata];
        frame->ExecuteJavaScript(RendererPerformanceMarkerScript(),
                                 "tungsten://internal/performance-markers",
                                 0);
    }

    void OnLoadEnd(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   int httpStatusCode) override {
        if (!frame->IsMain()) {
            return;
        }

        TungstenBrowserController *controller = controller_;
        NSString *urlString = ToNSString(frame->GetURL());
        NSMutableDictionary<NSString *, id> *metadata = PerformanceURLMetadata(urlString);
        metadata[@"browser_id"] = @(browser->GetIdentifier());
        metadata[@"http_status"] = @(httpStatusCode);
        [controller logPerformanceEvent:@"cef.load.end" metadata:metadata];
    }

    void OnLoadError(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     ErrorCode errorCode,
                     const CefString &errorText,
                     const CefString &failedUrl) override {
        if (!frame->IsMain()) {
            return;
        }

        TungstenBrowserController *controller = controller_;
        NSString *urlString = ToNSString(failedUrl);
        NSMutableDictionary<NSString *, id> *metadata = PerformanceURLMetadata(urlString);
        metadata[@"browser_id"] = @(browser->GetIdentifier());
        metadata[@"error_code"] = @((int)errorCode);
        metadata[@"error_text_length"] = @(ToNSString(errorText).length);
        [controller logPerformanceEvent:@"cef.load.error" metadata:metadata];
    }

    void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                            const std::vector<CefString> &iconUrls) override {
        NSMutableArray<NSString *> *urls = [NSMutableArray arrayWithCapacity:iconUrls.size()];
        for (const CefString &iconUrl : iconUrls) {
            NSString *converted = ToNSString(iconUrl);
            if (converted.length > 0) {
                [urls addObject:converted];
            }
        }
        TungstenBrowserController *controller = controller_;
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller.delegate browserController:controller didUpdateFaviconURLs:urls];
        });
    }

    bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                          cef_log_severity_t level,
                          const CefString &message,
                          const CefString &source,
                          int line) override {
        const std::string msg = message.ToString();
        static const std::string kPageTextMarker = "TUNGSTEN_PAGE_TEXT:";
        static const std::string kRendererPerfMarker = "TUNGSTEN_PERF_MARK:";
        if (msg.compare(0, kPageTextMarker.size(), kPageTextMarker) == 0) {
            NSString *payloadString = [NSString stringWithUTF8String:msg.substr(kPageTextMarker.size()).c_str()];
            TungstenBrowserController *controller = controller_;
            dispatch_async(dispatch_get_main_queue(), ^{
                [controller completePageContentRequestWithPayload:payloadString];
            });
            return true;  // suppress from DevTools console
        }
        if (msg.compare(0, kRendererPerfMarker.size(), kRendererPerfMarker) == 0) {
            std::string payload = msg.substr(kRendererPerfMarker.size());
            TungstenBrowserController *controller = controller_;
            dispatch_async(dispatch_get_main_queue(), ^{
                LogRendererPerformanceMarker(controller, browser, payload);
            });
            return true;
        }
        return false;
    }

private:
    __weak TungstenBrowserController *controller_;
    CefRefPtr<CefBrowser> browser_;

    IMPLEMENT_REFCOUNTING(TungstenBrowserClient);
};

} // namespace

@interface TungstenBrowserContainerView : NSView
@property (nonatomic, weak) TungstenBrowserController *controller;
@end

@implementation TungstenBrowserContainerView

- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

// Tag the host window as Display P3. Chromium produces P3 pixels
// (--force-color-profile=display-p3-d65); without explicit tagging at the
// AppKit layer, the WindowServer applies an sRGB→display conversion that
// inflates saturated channels. AppKit may also reset color tagging or
// desaturate inactive-window content, so we reapply on every key-state
// transition.
- (void)applyDisplayP3ColorSpace {
    if (self.window != nil) {
        self.window.colorSpace = [NSColorSpace displayP3ColorSpace];
    }
}

- (void)windowFocusOrBackingDidChange:(NSNotification *)note {
    [self applyDisplayP3ColorSpace];
    [self.controller layoutBrowserView];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self];

    NSWindow *window = self.window;
    if (window != nil) {
        [self applyDisplayP3ColorSpace];

        NSNotificationName names[] = {
            NSWindowDidBecomeKeyNotification,
            NSWindowDidResignKeyNotification,
            NSWindowDidBecomeMainNotification,
            NSWindowDidResignMainNotification,
            NSWindowDidChangeBackingPropertiesNotification,
            NSWindowDidChangeScreenNotification,
        };
        for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
            [center addObserver:self
                       selector:@selector(windowFocusOrBackingDidChange:)
                           name:names[i]
                         object:window];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.controller layoutBrowserView];
    });
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self.controller layoutBrowserView];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end

@implementation TungstenCEFApp {
    BOOL _initialized;
    BOOL _terminating;
    std::unique_ptr<CefScopedLibraryLoader> _libraryLoader;
    CefRefPtr<TungstenCefApp> _cefApp;
}

+ (instancetype)shared {
    static TungstenCEFApp *sharedApp = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedApp = [[TungstenCEFApp alloc] init];
    });
    return sharedApp;
}

- (BOOL)isInitialized {
    return _initialized;
}

- (BOOL)isTerminating {
    return _terminating;
}

- (void)prewarmCEF {
    if (_initialized || _terminating) {
        TungstenPerformanceLogEvent(@"cef.prewarm.skipped", @{
            @"initialized": @(_initialized),
            @"terminating": @(_terminating)
        });
        return;
    }

    CFTimeInterval prewarmStart = TungstenPerformanceLogNow();
    TungstenPerformanceLogEvent(@"cef.prewarm.start", nil);
    [self initializeCEF];
    TungstenPerformanceLogDuration(_initialized ? @"cef.prewarm.end" : @"cef.prewarm.failed",
                                   prewarmStart,
                                   @{@"initialized": @(_initialized)});
}

- (void)beginTermination {
    _terminating = YES;
}

- (void)initializeCEF {
    if (_initialized || _terminating) {
        TungstenPerformanceLogEvent(@"cef.initialize.skipped", @{
            @"initialized": @(_initialized),
            @"terminating": @(_terminating)
        });
        return;
    }

    CFTimeInterval initializeStart = TungstenPerformanceLogNow();
    TungstenPerformanceLogEvent(@"cef.initialize.start", nil);

    CFTimeInterval libraryLoadStart = TungstenPerformanceLogNow();
    _libraryLoader = std::make_unique<CefScopedLibraryLoader>();
    if (!_libraryLoader->LoadInMain()) {
        NSLog(@"Unable to load Chromium Embedded Framework.");
        TungstenPerformanceLogDuration(@"cef.libraryLoad.failed", libraryLoadStart, nil);
        TungstenPerformanceLogDuration(@"cef.initialize.failed", initializeStart, @{
            @"reason": @"library_load"
        });
        _libraryLoader.reset();
        return;
    }
    TungstenPerformanceLogDuration(@"cef.libraryLoad.end", libraryLoadStart, nil);

    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    std::vector<std::string> argumentStorage;
    std::vector<char *> argv;
    argumentStorage.reserve(arguments.count);
    argv.reserve(arguments.count);

    for (NSString *argument in arguments) {
        argumentStorage.push_back(ToString(argument));
    }

    for (std::string &argument : argumentStorage) {
        argv.push_back(argument.data());
    }

    CefMainArgs mainArgs(static_cast<int>(argv.size()), argv.data());
    _cefApp = new TungstenCefApp();

    CefSettings settings;
    settings.no_sandbox = true;
    settings.external_message_pump = true;
    settings.persist_session_cookies = true;
    settings.remote_debugging_port = 9222;

    NSString *cachePath = TungstenApplicationSupportDirectory();
    CefString(&settings.root_cache_path).FromString(ToString(cachePath));
    CefString(&settings.cache_path).FromString(ToString(cachePath));
    CefString(&settings.user_agent_product).FromASCII("Chrome/147.0.7727.118");

    NSString *helperPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
        @"Contents/Frameworks/Tungsten Helper.app/Contents/MacOS/Tungsten Helper"];
    CefString(&settings.browser_subprocess_path).FromString(ToString(helperPath));

    CFTimeInterval cefInitializeStart = TungstenPerformanceLogNow();
    if (!CefInitialize(mainArgs, settings, _cefApp.get(), nullptr)) {
        NSLog(@"Unable to initialize Chromium Embedded Framework.");
        TungstenPerformanceLogDuration(@"cef.cefInitialize.failed", cefInitializeStart, nil);
        TungstenPerformanceLogDuration(@"cef.initialize.failed", initializeStart, @{
            @"reason": @"cef_initialize"
        });
        _cefApp = nullptr;
        _libraryLoader.reset();
        return;
    }
    TungstenPerformanceLogDuration(@"cef.cefInitialize.end", cefInitializeStart, nil);

    _initialized = YES;
    InstallCefRunLoopObserver();
    ScheduleCefMessageLoopWork(0);
    TungstenPerformanceLogDuration(@"cef.initialize.end", initializeStart, nil);
}

- (void)shutdownCEF {
    if (!_initialized) {
        return;
    }

    UninstallCefRunLoopObserver();
    CancelCefMessagePumpTimer();
    g_immediateMessagePumpWorkPending = false;

    CefShutdown();
    _cefApp = nullptr;
    _libraryLoader.reset();
    _initialized = NO;
}

@end

@implementation TungstenBrowserController {
    NSString *_initialURL;
    NSString *_pendingURL;
    NSString *_performanceID;
    NSString *_privacyMode;
    NSString *_torProxyHost;
    int32_t _torProxyPort;
    BOOL _isIncognito;
    BOOL _didCreateBrowser;
    BOOL _isClosingBrowser;
    BOOL _didLogCreateWaitForWindow;
    BOOL _didLogCreateWaitForBounds;
    BOOL _didLogLayoutWaitingForBrowser;
    NSUInteger _layoutPassCount;
    CGFloat _cornerRadius;
    CefRefPtr<TungstenBrowserClient> _client;
    CefRefPtr<CefRequestContext> _requestContext;
    void *_closeRetainToken;
    NSMutableDictionary<NSString *, TungstenPageContentCompletion> *_pageContentCompletions;
}

@synthesize browserDidCloseHandler = _browserDidCloseHandler;

- (instancetype)initWithInitialURL:(NSString *)initialURL {
    return [self initWithInitialURL:initialURL incognito:NO];
}

- (instancetype)initWithInitialURL:(NSString *)initialURL incognito:(BOOL)incognito {
    return [self initWithInitialURL:initialURL
                        privacyMode:(incognito ? @"incognito" : @"normal")
                       torProxyHost:@"127.0.0.1"
                       torProxyPort:9150];
}

- (instancetype)initWithInitialURL:(NSString *)initialURL
                       privacyMode:(NSString *)privacyMode
                      torProxyHost:(NSString *)torProxyHost
                      torProxyPort:(int32_t)torProxyPort {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _initialURL = [initialURL copy];
    _pendingURL = [initialURL copy];
    _performanceID = ShortPerformanceID();
    _privacyMode = privacyMode.length > 0 ? [privacyMode copy] : @"normal";
    _isIncognito = ![_privacyMode isEqualToString:@"normal"];
    _torProxyHost = torProxyHost.length > 0 ? [torProxyHost copy] : @"127.0.0.1";
    _torProxyPort = torProxyPort > 0 ? torProxyPort : 9150;
    _pageContentCompletions = [NSMutableDictionary dictionary];

    NSMutableDictionary<NSString *, id> *metadata = PerformanceURLMetadata(_initialURL);
    metadata[@"controller"] = _performanceID;
    metadata[@"is_incognito"] = @(_isIncognito);
    metadata[@"privacy_mode"] = _privacyMode;
    TungstenPerformanceLogEvent(@"cef.controller.init", metadata);

    TungstenBrowserContainerView *containerView = [[TungstenBrowserContainerView alloc] initWithFrame:NSZeroRect];
    containerView.controller = self;
    _view = containerView;

    _client = new TungstenBrowserClient(self);

    return self;
}

- (BOOL)isTorPrivacyMode {
    return [_privacyMode isEqualToString:@"tor"];
}

- (void)setRequestContextPreference:(const std::string &)name
                              value:(CefRefPtr<CefValue>)value
                        description:(NSString *)description {
    if (!_requestContext || !value) {
        return;
    }

    CefString error;
    if (!_requestContext->SetPreference(name, value, error)) {
        [self logPerformanceEvent:@"cef.requestContext.preference.failed" metadata:@{
            @"preference": description ?: @"unknown",
            @"error": ToNSString(error) ?: @"unknown"
        }];
    }
}

- (void)configureTorRequestContextPreferences {
    if (!_requestContext) {
        return;
    }

    NSString *proxyServer = [NSString stringWithFormat:@"socks5://%@:%d", _torProxyHost, _torProxyPort];
    CefRefPtr<CefDictionaryValue> proxyDictionary = CefDictionaryValue::Create();
    proxyDictionary->SetString("mode", "fixed_servers");
    proxyDictionary->SetString("server", ToString(proxyServer));
    proxyDictionary->SetString("bypass_list", "<-loopback>");

    CefRefPtr<CefValue> proxyValue = CefValue::Create();
    proxyValue->SetDictionary(proxyDictionary);
    [self setRequestContextPreference:"proxy" value:proxyValue description:@"proxy"];

    CefRefPtr<CefValue> webRTCPolicy = CefValue::Create();
    webRTCPolicy->SetString("disable_non_proxied_udp");
    [self setRequestContextPreference:"webrtc.ip_handling_policy"
                                value:webRTCPolicy
                          description:@"webrtc.ip_handling_policy"];

    CefRefPtr<CefValue> webRTCMultipleRoutes = CefValue::Create();
    webRTCMultipleRoutes->SetBool(false);
    [self setRequestContextPreference:"webrtc.multiple_routes_enabled"
                                value:webRTCMultipleRoutes
                          description:@"webrtc.multiple_routes_enabled"];
}

- (void)logPerformanceEvent:(NSString *)event metadata:(NSDictionary<NSString *, id> *)metadata {
    NSMutableDictionary<NSString *, id> *combined =
        metadata ? [metadata mutableCopy] : [NSMutableDictionary dictionary];
    combined[@"controller"] = _performanceID ?: @"nil";
    TungstenPerformanceLogEvent(event, combined);
}

- (CGFloat)cornerRadius {
    return _cornerRadius;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    if (_cornerRadius == cornerRadius) {
        return;
    }
    _cornerRadius = cornerRadius;

    NSView *view = _view;
    view.wantsLayer = YES;
    view.layer.cornerRadius = cornerRadius;
    view.layer.masksToBounds = (cornerRadius > 0);
    if (@available(macOS 13.0, *)) {
        view.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (void)dealloc {
    // CEF browser close is asynchronous and can send AppKit close notifications
    // while SwiftUI is dismantling the NSView hierarchy. Releasing the
    // container view lets CEF observe normal child-view teardown.
    if (_closeRetainToken != nullptr) {
        CFRelease(_closeRetainToken);
        _closeRetainToken = nullptr;
    }
}

- (void)navigateToURLString:(NSString *)urlString {
    if (_isClosingBrowser) {
        [self logPerformanceEvent:@"cef.navigate.ignored" metadata:@{
            @"reason": @"closing"
        }];
        return;
    }

    _pendingURL = [urlString copy];

    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    NSMutableDictionary<NSString *, id> *metadata = PerformanceURLMetadata(urlString);
    metadata[@"has_browser"] = @(browser != nullptr);
    [self logPerformanceEvent:@"cef.navigate.request" metadata:metadata];

    if (browser) {
        std::string targetURL = ToString(urlString);
        CefRefPtr<CefFrame> mainFrame = browser->GetMainFrame();
        if (!mainFrame) {
            [self logPerformanceEvent:@"cef.navigate.ignored" metadata:@{
                @"reason": @"missing_main_frame"
            }];
            return;
        }

        if (mainFrame->GetURL().ToString() == targetURL) {
            [self logPerformanceEvent:@"cef.navigate.ignored" metadata:@{
                @"reason": @"same_url"
            }];
            return;
        }

        browser->StopLoad();
        mainFrame->LoadURL(targetURL);
    } else {
        [self logPerformanceEvent:@"cef.navigate.createBrowser" metadata:metadata];
        [self createBrowserIfNeeded];
    }
}

- (void)goBack {
    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser && browser->CanGoBack()) {
        browser->GoBack();
    }
}

- (void)goForward {
    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser && browser->CanGoForward()) {
        browser->GoForward();
    }
}

- (void)reload {
    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser) {
        browser->Reload();
    }
}

- (void)stopLoading {
    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser) {
        browser->StopLoad();
    }
}

- (void)zoomIn {
    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser) {
        browser->GetHost()->Zoom(CEF_ZOOM_COMMAND_IN);
    }
}

- (void)zoomOut {
    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser) {
        browser->GetHost()->Zoom(CEF_ZOOM_COMMAND_OUT);
    }
}

- (void)resetZoom {
    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser) {
        browser->GetHost()->Zoom(CEF_ZOOM_COMMAND_RESET);
    }
}

- (void)findText:(NSString *)searchText forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext {
    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser) {
        browser->GetHost()->Find(ToString(searchText), forward, matchCase, findNext);
    }
}

- (void)stopFindingWithClearSelection:(BOOL)clearSelection {
    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser) {
        browser->GetHost()->StopFinding(clearSelection);
    }
}

- (void)extractPageContentWithCompletion:(TungstenPageContentCompletion)completion {
    if (completion == nil || _isClosingBrowser) {
        if (completion != nil) {
            completion(nil, nil);
        }
        return;
    }

    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    CefRefPtr<CefFrame> frame = browser ? browser->GetMainFrame() : nullptr;
    if (!frame) {
        completion(nil, nil);
        return;
    }

    NSString *requestID = NSUUID.UUID.UUIDString;
    _pageContentCompletions[requestID] = [completion copy];

    NSString *script = [NSString stringWithFormat:
        @"(()=>{"
         "const id='%@';"
         "const cap=(value)=>{const text=String(value||'').trim();return text.length>40000?text.slice(0,40000):text};"
         "try{"
           "const selected=cap(window.getSelection?window.getSelection().toString():'');"
           "const body=cap((document.body&&document.body.innerText)||(document.documentElement&&document.documentElement.innerText)||'');"
           "console.log('TUNGSTEN_PAGE_TEXT:'+JSON.stringify({id,selectedText:selected,bodyText:body}));"
         "}catch(e){"
           "console.log('TUNGSTEN_PAGE_TEXT:'+JSON.stringify({id,selectedText:'',bodyText:''}));"
         "}"
        "})()",
        requestID
    ];

    frame->ExecuteJavaScript(ToString(script), "tungsten://internal/page-content", 0);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        TungstenPageContentCompletion pendingCompletion = _pageContentCompletions[requestID];
        if (pendingCompletion == nil) {
            return;
        }
        [_pageContentCompletions removeObjectForKey:requestID];
        pendingCompletion(nil, nil);
    });
}

- (void)completePageContentRequestWithPayload:(NSString *)payloadString {
    NSData *data = [payloadString dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return;
    }

    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![payload isKindOfClass:NSDictionary.class]) {
        return;
    }

    NSString *requestID = payload[@"id"];
    if (![requestID isKindOfClass:NSString.class]) {
        return;
    }

    TungstenPageContentCompletion completion = _pageContentCompletions[requestID];
    if (completion == nil) {
        return;
    }
    [_pageContentCompletions removeObjectForKey:requestID];

    NSString *selectedText = payload[@"selectedText"];
    NSString *bodyText = payload[@"bodyText"];
    completion(
        [selectedText isKindOfClass:NSString.class] ? selectedText : nil,
        [bodyText isKindOfClass:NSString.class] ? bodyText : nil
    );
}

- (void)layoutBrowserView {
    if (_isClosingBrowser) {
        return;
    }

    CFTimeInterval layoutStart = TungstenPerformanceLogNow();
    _layoutPassCount += 1;
    [self createBrowserIfNeeded];

    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (!browser) {
        if (!_didLogLayoutWaitingForBrowser) {
            _didLogLayoutWaitingForBrowser = YES;
            [self logPerformanceEvent:@"cef.browserView.waitingForBrowser" metadata:@{
                @"layout_pass": @(_layoutPassCount)
            }];
        }
        return;
    }
    _didLogLayoutWaitingForBrowser = NO;

    NSView *browserView = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    BOOL didAttachBrowserView = browserView.superview != self.view;
    if (browserView.superview != self.view) {
        [browserView removeFromSuperview];
        [self.view addSubview:browserView];
    }

    // Keep Chromium out of AppKit's vibrant/glass drawing path. The host
    // NSWindow is intentionally non-opaque for the frosted gutters; if the CEF
    // subtree inherits the vibrant window appearance, AppKit recomposites web
    // content when the window becomes inactive and the page looks faded. Use a
    // plain Aqua/DarkAqua appearance and opaque layers for the Chromium island.
    CFTimeInterval compositingStart = TungstenPerformanceLogNow();
    ApplyCEFSubviewCompositing(
        browserView,
        NonVibrantBrowserAppearanceForWindow(self.view.window)
    );
    CFTimeInterval compositingDuration = TungstenPerformanceLogNow() - compositingStart;

    browserView.frame = self.view.bounds;
    browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CFTimeInterval layoutDuration = TungstenPerformanceLogNow() - layoutStart;
    if (didAttachBrowserView || layoutDuration > 0.010) {
        [self logPerformanceEvent:@"cef.browserView.layout" metadata:@{
            @"attached": @(didAttachBrowserView),
            @"browser_id": @(browser->GetIdentifier()),
            @"compositing_ms": @(compositingDuration * 1000),
            @"duration_ms": @(layoutDuration * 1000),
            @"layout_pass": @(_layoutPassCount)
        }];
    }
}

- (void)createBrowserIfNeeded {
    if (_isClosingBrowser) {
        [self logPerformanceEvent:@"cef.browser.create.skipped" metadata:@{
            @"reason": @"closing"
        }];
        return;
    }

    if (_didCreateBrowser) {
        return;
    }

    if (self.view.window == nil) {
        if (!_didLogCreateWaitForWindow) {
            _didLogCreateWaitForWindow = YES;
            [self logPerformanceEvent:@"cef.browser.create.wait" metadata:@{
                @"reason": @"no_window"
            }];
        }
        return;
    }

    if ([[TungstenCEFApp shared] isTerminating]) {
        [self logPerformanceEvent:@"cef.browser.create.skipped" metadata:@{
            @"reason": @"cef_terminating"
        }];
        return;
    }

    if (self.view.bounds.size.width < 1 || self.view.bounds.size.height < 1) {
        if (!_didLogCreateWaitForBounds) {
            _didLogCreateWaitForBounds = YES;
            [self logPerformanceEvent:@"cef.browser.create.wait" metadata:@{
                @"reason": @"empty_bounds",
                @"view_height": @(self.view.bounds.size.height),
                @"view_width": @(self.view.bounds.size.width)
            }];
        }
        return;
    }
    _didLogCreateWaitForWindow = NO;
    _didLogCreateWaitForBounds = NO;

    CFTimeInterval createStart = TungstenPerformanceLogNow();
    NSMutableDictionary<NSString *, id> *metadata = PerformanceURLMetadata(_pendingURL ?: _initialURL);
    metadata[@"cef_initialized_before"] = @([[TungstenCEFApp shared] isInitialized]);
    metadata[@"privacy_mode"] = _privacyMode ?: @"normal";
    metadata[@"view_height"] = @(self.view.bounds.size.height);
    metadata[@"view_width"] = @(self.view.bounds.size.width);
    [self logPerformanceEvent:@"cef.browser.create.start" metadata:metadata];

    if (![[TungstenCEFApp shared] isInitialized]) {
        [[TungstenCEFApp shared] initializeCEF];
        if (![[TungstenCEFApp shared] isInitialized]) {
            [self logPerformanceEvent:@"cef.browser.create.failed" metadata:@{
                @"reason": @"cef_initialize_failed"
            }];
            return;
        }
    }

    _didCreateBrowser = YES;

    CefWindowInfo windowInfo;
    CefRect bounds(0, 0, self.view.bounds.size.width, self.view.bounds.size.height);
    windowInfo.SetAsChild((__bridge CefWindowHandle)self.view, bounds);
    windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;

    CefBrowserSettings browserSettings;
    // Opaque white. With window transparency on, the SwiftUI window background
    // is .regularMaterial (NSVisualEffectView), which desaturates when the
    // window is inactive. Without an opaque CEF surface, that desaturation
    // bleeds through and the rendered web content goes bland on focus loss.
    browserSettings.background_color = 0xFFFFFFFF;
    std::string url = ToString(_pendingURL ?: _initialURL);

    CefRefPtr<CefRequestContext> requestContext = nullptr;
    if (_isIncognito) {
        if (!_requestContext) {
            CefRequestContextSettings contextSettings;
            _requestContext = CefRequestContext::CreateContext(contextSettings, nullptr);
            if ([self isTorPrivacyMode]) {
                [self configureTorRequestContextPreferences];
            }
        }
        requestContext = _requestContext;
    }

    if (!CefBrowserHost::CreateBrowser(windowInfo, _client.get(), url, browserSettings, nullptr, requestContext)) {
        NSLog(@"Unable to create CEF browser for URL %@", _pendingURL ?: _initialURL);
        _didCreateBrowser = NO;
        TungstenPerformanceLogDuration(@"cef.browser.create.requestFailed", createStart, metadata);
        return;
    }

    TungstenPerformanceLogDuration(@"cef.browser.create.requested", createStart, metadata);
}

- (void)closeBrowser {
    [self closeBrowserWithForce:YES];
}

- (void)closeBrowserForWindowClose {
    [self closeBrowserWithForce:NO];
}

- (void)closeBrowserWithForce:(BOOL)forceClose {
    if (_isClosingBrowser) {
        return;
    }

    _isClosingBrowser = YES;
    self.delegate = nil;

    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    [self logPerformanceEvent:@"cef.browser.close.request" metadata:@{
        @"force": @(forceClose),
        @"has_browser": @(browser != nullptr)
    }];
    if (!browser) {
        _didCreateBrowser = NO;
        void (^handler)(void) = _browserDidCloseHandler;
        _browserDidCloseHandler = nil;
        if (handler) {
            handler();
        }
        return;
    }

    if (_closeRetainToken == nullptr) {
        _closeRetainToken = (__bridge_retained void *)self;
    }

    browser->GetHost()->CloseBrowser(forceClose);
}

- (void)cefBrowserDidClose {
    _didCreateBrowser = NO;
    [self logPerformanceEvent:@"cef.browser.didClose" metadata:nil];

    void (^handler)(void) = _browserDidCloseHandler;
    _browserDidCloseHandler = nil;
    if (handler) {
        handler();
    }

    if (_closeRetainToken != nullptr) {
        CFRelease(_closeRetainToken);
        _closeRetainToken = nullptr;
    }
}

@end
