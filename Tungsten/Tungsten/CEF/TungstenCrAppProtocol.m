/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Implements Chromium's CrAppProtocol on NSApplication so SwiftUI's
AppKitApplication satisfies the protocol Chromium / CEF expect of the host
NSApp instance.

Background:
Chromium's IPC plumbing calls -[NSApp isHandlingSendEvent] (declared by
CrAppProtocol) to decide whether the main run loop is currently inside
-sendEvent:, and therefore whether it's safe to do reentrant work or whether
the work should be queued. cefclient and Chromium's own browser ship a
custom NSApplication subclass (CrApplication) that implements this.

In a SwiftUI app, NSApp is an instance of SwiftUI's private
SwiftUI.AppKitApplication, which does not implement the method. The first
single-window session works because the offending Chromium IPC path doesn't
get exercised during normal app teardown. As soon as a second window closes,
a renderer-disconnect IPC message lands in the browser process while the
parent NSApp is still alive, the message handler calls -isHandlingSendEvent
on NSApp, and the resulting NSInvalidArgumentException unwinds through CEF
frames compiled with -fno-exceptions and aborts the process.

Adding the method via a category on NSApplication routes the call through
inheritance and stops the crash. Returning NO unconditionally is a tiny lie
while -sendEvent: is on the stack, but Chromium only uses the flag to defer
opportunistic work, so the practical impact is negligible.
*/

#import <AppKit/AppKit.h>

@interface NSApplication (TungstenCrAppProtocol)
- (BOOL)isHandlingSendEvent;
@end

@implementation NSApplication (TungstenCrAppProtocol)

- (BOOL)isHandlingSendEvent {
    return NO;
}

@end
