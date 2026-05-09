/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Objective-C++ bridge between SwiftUI/AppKit and Chromium Embedded Framework.
*/

#import "TungstenCEFApp.h"
#import "TungstenBrowserController.h"

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
#include "include/cef_request_context.h"
#include "include/wrapper/cef_helpers.h"
#include "wrapper/cef_library_loader.h"

@interface TungstenBrowserController ()
- (void)cefBrowserDidClose;
- (void)closeBrowserWithForce:(BOOL)forceClose;
- (void)completePageContentRequestWithPayload:(NSString *)payloadString;
@end

namespace {

// External message pump for CEF on macOS.
//
// Chromium drives almost everything in the browser process — IPC, compositor
// frame submission, input dispatch, JS callbacks — through CefDoMessageLoopWork().
// We feed it from two places:
//
//   1. A CFRunLoopObserver fires right before the main run loop sleeps. This
//      drains any work Chromium has queued without polling and stays roughly
//      aligned with how AppKit pumps its own events.
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

extern "C" NSString *const TungstenLocalAIProviderDefaultsKey = @"Tungsten.LocalAIProvider.v1";

namespace {

NSString *const kLocalAIProviderGoogle = @"google";

const std::vector<std::string> kLocalAIChromiumFeatures = {
    "AIPromptAPI",
    "AIPromptAPIMultimodalInput",
    "OnDeviceModelPerformanceParams",
    "OptimizationGuideOnDeviceModel"
};

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

bool IsGoogleLocalAIEnabled() {
    NSString *storedProvider = [NSUserDefaults.standardUserDefaults stringForKey:TungstenLocalAIProviderDefaultsKey];
    return [storedProvider isEqualToString:kLocalAIProviderGoogle];
}

}  // namespace

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
        // Note: an Objective-C exception thrown deep inside CEF unwinds
        // through Chromium frames compiled with -fno-exceptions and aborts
        // before any local @catch can see it. We log via
        // NSSetUncaughtExceptionHandler in AppDelegate instead.
        CefDoMessageLoopWork();
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

void CefRunLoopBeforeWaitingCallback(__unused CFRunLoopObserverRef observer,
                                     __unused CFRunLoopActivity activity,
                                     __unused void *info) {
    PerformCefMessageLoopWork();
}

void InstallCefRunLoopObserver(void) {
    if (g_beforeWaitingObserver != nullptr) {
        return;
    }
    g_beforeWaitingObserver = CFRunLoopObserverCreate(kCFAllocatorDefault,
                                                      kCFRunLoopBeforeWaiting,
                                                      true,
                                                      0,
                                                      &CefRunLoopBeforeWaitingCallback,
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

        // Local AI: route Chromium's Gemini Nano prompt feature flags into
        // either the enable or disable list based on the user's setting.
        // Without an explicit decision the flags would float — this keeps the
        // behavior tied to Settings instead of chrome://flags.
        if (IsGoogleLocalAIEnabled()) {
            enabledFeatures.insert(enabledFeatures.end(),
                                   kLocalAIChromiumFeatures.begin(),
                                   kLocalAIChromiumFeatures.end());
        } else {
            disabledFeatures.insert(disabledFeatures.end(),
                                    kLocalAIChromiumFeatures.begin(),
                                    kLocalAIChromiumFeatures.end());
        }

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
                                    public CefLoadHandler {
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

    CefRefPtr<CefBrowser> browser() const {
        return browser_;
    }

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        browser_ = browser;
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller_ layoutBrowserView];
        });
    }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        if (browser_ && browser_->IsSame(browser)) {
            browser_ = nullptr;
        }
        TungstenBrowserController *controller = controller_;
        [controller cefBrowserDidClose];
    }

    bool DoClose(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();

        NSView *browserView = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
        [browserView removeFromSuperview];

        // This browser is hosted as a child view inside SwiftUI. Returning
        // false would make CEF send a default close event to the top-level
        // NSWindow, which is the wrong ownership boundary for closing a tab.
        return true;
    }

    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
        NSString *titleString = ToNSString(title);
        dispatch_async(dispatch_get_main_queue(), ^{
            TungstenBrowserController *controller = controller_;
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
        dispatch_async(dispatch_get_main_queue(), ^{
            TungstenBrowserController *controller = controller_;
            [controller.delegate browserController:controller didUpdateURL:urlString];
        });
    }

    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                              bool isLoading,
                              bool canGoBack,
                              bool canGoForward) override {
        dispatch_async(dispatch_get_main_queue(), ^{
            TungstenBrowserController *controller = controller_;
            [controller.delegate browserController:controller
                                 didUpdateLoading:isLoading
                                        canGoBack:canGoBack
                                     canGoForward:canGoForward];
        });
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
        dispatch_async(dispatch_get_main_queue(), ^{
            TungstenBrowserController *controller = controller_;
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
        if (msg.compare(0, kPageTextMarker.size(), kPageTextMarker) != 0) {
            return false;
        }
        NSString *payloadString = [NSString stringWithUTF8String:msg.substr(kPageTextMarker.size()).c_str()];
        dispatch_async(dispatch_get_main_queue(), ^{
            TungstenBrowserController *controller = controller_;
            [controller completePageContentRequestWithPayload:payloadString];
        });
        return true;  // suppress from DevTools console
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

- (void)beginTermination {
    _terminating = YES;
}

- (void)initializeCEF {
    if (_initialized || _terminating) {
        return;
    }

    _libraryLoader = std::make_unique<CefScopedLibraryLoader>();
    if (!_libraryLoader->LoadInMain()) {
        NSLog(@"Unable to load Chromium Embedded Framework.");
        _libraryLoader.reset();
        return;
    }

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

    if (!CefInitialize(mainArgs, settings, _cefApp.get(), nullptr)) {
        NSLog(@"Unable to initialize Chromium Embedded Framework.");
        _cefApp = nullptr;
        _libraryLoader.reset();
        return;
    }

    _initialized = YES;
    InstallCefRunLoopObserver();
    ScheduleCefMessageLoopWork(0);
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
    BOOL _isIncognito;
    BOOL _didCreateBrowser;
    BOOL _isClosingBrowser;
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
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _initialURL = [initialURL copy];
    _pendingURL = [initialURL copy];
    _isIncognito = incognito;
    _pageContentCompletions = [NSMutableDictionary dictionary];

    TungstenBrowserContainerView *containerView = [[TungstenBrowserContainerView alloc] initWithFrame:NSZeroRect];
    containerView.controller = self;
    _view = containerView;

    _client = new TungstenBrowserClient(self);

    return self;
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
        return;
    }

    _pendingURL = [urlString copy];

    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (browser) {
        std::string targetURL = ToString(urlString);
        CefRefPtr<CefFrame> mainFrame = browser->GetMainFrame();
        if (!mainFrame) {
            return;
        }

        if (mainFrame->GetURL().ToString() == targetURL) {
            return;
        }

        browser->StopLoad();
        mainFrame->LoadURL(targetURL);
    } else {
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

    [self createBrowserIfNeeded];

    CefRefPtr<CefBrowser> browser = _client ? _client->browser() : nullptr;
    if (!browser) {
        return;
    }

    NSView *browserView = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    if (browserView.superview != self.view) {
        [browserView removeFromSuperview];
        [self.view addSubview:browserView];
    }

    // Keep Chromium out of AppKit's vibrant/glass drawing path. The host
    // NSWindow is intentionally non-opaque for the frosted gutters; if the CEF
    // subtree inherits the vibrant window appearance, AppKit recomposites web
    // content when the window becomes inactive and the page looks faded. Use a
    // plain Aqua/DarkAqua appearance and opaque layers for the Chromium island.
    ApplyCEFSubviewCompositing(
        browserView,
        NonVibrantBrowserAppearanceForWindow(self.view.window)
    );

    browserView.frame = self.view.bounds;
    browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)createBrowserIfNeeded {
    if (_isClosingBrowser || _didCreateBrowser || self.view.window == nil ||
        [[TungstenCEFApp shared] isTerminating]) {
        return;
    }

    if (self.view.bounds.size.width < 1 || self.view.bounds.size.height < 1) {
        return;
    }

    if (![[TungstenCEFApp shared] isInitialized]) {
        [[TungstenCEFApp shared] initializeCEF];
        if (![[TungstenCEFApp shared] isInitialized]) {
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
        }
        requestContext = _requestContext;
    }

    if (!CefBrowserHost::CreateBrowser(windowInfo, _client.get(), url, browserSettings, nullptr, requestContext)) {
        NSLog(@"Unable to create CEF browser for URL %@", _pendingURL ?: _initialURL);
        _didCreateBrowser = NO;
    }
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
