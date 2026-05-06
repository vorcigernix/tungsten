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
#include "include/wrapper/cef_helpers.h"
#include "wrapper/cef_library_loader.h"

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

class TungstenCefApp final : public CefApp, public CefBrowserProcessHandler {
public:
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
        return this;
    }

    void OnBeforeCommandLineProcessing(const CefString &process_type,
                                       CefRefPtr<CefCommandLine> command_line) override {
        // Features we explicitly turn off. Keep in one comma-separated list because
        // Chromium merges multiple --disable-features= flags but it's cleaner to
        // pass a single value.
        command_line->AppendSwitchWithValue(
            "disable-features",
            "DialMediaRouteProvider"
        );

        // Features we want explicitly on. PlatformHEVCDecoderSupport unlocks
        // hardware HEVC decode on macOS (used by Apple TV+, Disney+, YouTube
        // HDR, etc.); CanvasOopRasterization moves canvas raster off the
        // renderer's main thread which helps animation-heavy pages.
        command_line->AppendSwitchWithValue(
            "enable-features",
            "PlatformHEVCDecoderSupport,CanvasOopRasterization"
        );

        // Force ANGLE/Metal explicitly so we don't fall back to the OpenGL path
        // on the off chance Chromium misdetects.
        command_line->AppendSwitchWithValue("use-angle", "metal");

        command_line->AppendSwitch("enable-zero-copy");
        command_line->AppendSwitch("enable-gpu-rasterization");

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

    // Probe the main frame's body background color when load finishes. The
    // JavaScript prints the color through console.log with a sentinel marker;
    // OnConsoleMessage filters it out. We use console.log instead of the
    // DevTools protocol because it's a single-line implementation.
    void OnLoadEnd(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   int httpStatusCode) override {
        if (!frame->IsMain()) {
            return;
        }
        const std::string js =
            "(()=>{try{const c=getComputedStyle(document.body).backgroundColor;"
            "console.log('TUNGSTEN_BG:'+c);}catch(e){}})()";
        frame->ExecuteJavaScript(js, "tungsten://internal/bg-probe", 0);
    }

    bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                          cef_log_severity_t level,
                          const CefString &message,
                          const CefString &source,
                          int line) override {
        const std::string msg = message.ToString();
        static const std::string kMarker = "TUNGSTEN_BG:";
        if (msg.compare(0, kMarker.size(), kMarker) != 0) {
            return false;
        }
        NSString *colorString = [NSString stringWithUTF8String:msg.substr(kMarker.size()).c_str()];
        dispatch_async(dispatch_get_main_queue(), ^{
            TungstenBrowserController *controller = controller_;
            [controller.delegate browserController:controller didUpdatePageBackgroundColorString:colorString];
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

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.controller layoutBrowserView];
    });
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self.controller layoutBrowserView];
}

@end

@implementation TungstenCEFApp {
    BOOL _initialized;
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

- (void)initializeCEF {
    if (_initialized) {
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
    BOOL _didCreateBrowser;
    CGFloat _cornerRadius;
    CefRefPtr<TungstenBrowserClient> _client;
}

- (instancetype)initWithInitialURL:(NSString *)initialURL {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _initialURL = [initialURL copy];
    _pendingURL = [initialURL copy];

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
    if (_client && _client->browser()) {
        _client->browser()->GetHost()->CloseBrowser(true);
    }
}

- (void)navigateToURLString:(NSString *)urlString {
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

- (void)layoutBrowserView {
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

    browserView.frame = self.view.bounds;
    browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)createBrowserIfNeeded {
    if (_didCreateBrowser || self.view.window == nil) {
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
    std::string url = ToString(_pendingURL ?: _initialURL);
    if (!CefBrowserHost::CreateBrowser(windowInfo, _client.get(), url, browserSettings, nullptr, nullptr)) {
        NSLog(@"Unable to create CEF browser for URL %@", _pendingURL ?: _initialURL);
        _didCreateBrowser = NO;
    }
}

@end
