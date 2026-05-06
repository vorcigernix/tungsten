# Tungsten

## What this codebase does

Tungsten is a native macOS SwiftUI browser shell backed by Chromium
Embedded Framework. It is a small Xcode project, not a web service:
`Landmarks/Landmarks/Browser/*` owns tabs and the omnibox,
`Landmarks/Landmarks/CEF/TungstenCEFBridge.mm` embeds CEF through
Objective-C++, `CEFHelper/TungstenCEFHelperMain.mm` is the renderer/GPU
helper entry point, and `scripts/*cef*.sh` downloads/copies the CEF
runtime into the app bundle. Some `Landmarks` and Apple sample naming is
historical.

## Auth shape

There is no first-party account system, API auth, route middleware,
roles, sessions, or backend ACL layer in this repo.

Important trust primitives:
- `AddressResolver.navigationTarget(for:)` is the intended normalization
  path for user omnibox input before browser navigation.
- `BrowserModel.submitAddressBar()` hands normalized input to the active
  tab; bypassing this path changes the navigation trust boundary.
- `BrowserTab.navigate(to:)` and `TungstenBrowserController.navigateToURLString`
  are the native-to-CEF navigation handoff.
- CEF owns website auth/cookies; `persist_session_cookies` stores browser
  session state under `Application Support/Tungsten/CEF`.
- `FaviconLoader` uses an ephemeral `URLSession` for page-provided icon
  URLs and should not be treated as app authentication.

## Threat model

Primary attacker is a malicious web page, redirect target, favicon URL,
or copied omnibox string trying to cross from Chromium content into local
macOS/browser-shell capabilities. Highest-impact outcomes are local file
exposure via scheme handling, CEF remote debugging/session theft, native
bridge abuse if new CEF handlers are added, or runtime substitution in
the downloaded/copied CEF helper apps. There is no server-side attacker
model; scans should focus on browser embedding, local process, and build
supply-chain trust boundaries.

## Project-specific patterns to flag

- Navigation that reaches `LoadURL` or `CreateBrowser` without passing
  through `AddressResolver.navigationTarget(for:)`.
- New or broadened direct schemes in `AddressResolver.directNavigationSchemes`,
  especially `file`, `chrome`, `chrome-extension`, `devtools`, or
  `view-source`, without a user-gesture/origin policy.
- Production CEF settings that weaken isolation or expose state, such as
  `no_sandbox`, `remote_debugging_port`, `persist_session_cookies`, or
  `use-mock-keychain`, unless the finding explains the Tungsten impact.
- Any new CEF request, download, custom-scheme, message-router, or JS
  binding handler that exposes native filesystem, process, clipboard, or
  keychain behavior to rendered content.
- Changes to `setup-cef.sh` or `copy-cef-runtime.sh` that make the CEF
  archive URL, extracted path, helper binary, or code-signing target
  controllable beyond the current pinned version/architecture flow.

## Known false-positives

- This repo has no HTTP routes, controllers, RPC handlers, or cloud
  functions; SwiftUI buttons and CEF callbacks are local app entry points.
- `FaviconLoader` performs client-side image fetching for browser UI; it
  is not a backend fetch with server credentials.
- `CEFHelper/TungstenCEFHelperMain.mm`, the multiple `Tungsten Helper*.app`
  bundles, and `CefExecuteProcess` are required CEF subprocess plumbing.
- `copy-cef-runtime.sh` intentionally deletes and recreates CEF framework
  contents under Xcode build output paths.
- `Landmarks` names, Apple sample comments, and `SampleCode.xcconfig` are
  leftover project scaffolding, not a separate product or trust domain.
