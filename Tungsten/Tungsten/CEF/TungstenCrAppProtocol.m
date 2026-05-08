/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Implements Chromium's send-event app protocol on NSApplication so SwiftUI's
AppKitApplication satisfies the selectors Chromium / CEF expect of the host
NSApp instance.

Background:
Chromium calls -[NSApp isHandlingSendEvent] and
-[NSApp setHandlingSendEvent:] (declared by CrAppProtocol /
CrAppControlProtocol) to track whether the main run loop is currently inside
-sendEvent:, and therefore whether it's safe to do reentrant work or whether
the work should be queued. cefclient and Chromium's own browser ship a custom
NSApplication subclass (CrApplication) that implements this.

In a SwiftUI app, NSApp is an instance of SwiftUI's private
SwiftUI.AppKitApplication, which does not implement these methods. Some
Chromium IPC paths call -isHandlingSendEvent while processing browser teardown;
native context-menu dispatch calls -setHandlingSendEvent: via
CefScopedSendingEvent. Either missing selector raises NSInvalidArgumentException
inside CEF frames compiled with -fno-exceptions and aborts the process.

Adding the methods via a category on NSApplication routes the calls through
inheritance and stops the crash. CEF's context-menu path uses the setter via
CefScopedSendingEvent, so both selectors need to be present even if our app is
created by SwiftUI instead of a custom NSApplication subclass.
*/

#import <AppKit/AppKit.h>

static BOOL g_tungstenHandlingSendEvent = NO;

@interface NSApplication (TungstenCrAppProtocol)
- (BOOL)isHandlingSendEvent;
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent;
@end

@implementation NSApplication (TungstenCrAppProtocol)

- (BOOL)isHandlingSendEvent {
    return g_tungstenHandlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    g_tungstenHandlingSendEvent = handlingSendEvent;
}

@end
