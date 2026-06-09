/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Objective-C facade for one CEF browser instance.
*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TungstenBrowserController;

typedef void (^TungstenPageContentCompletion)(NSString *_Nullable selectedText,
                                              NSString *_Nullable bodyText);
typedef void (^TungstenContextMenuSearchHandler)(NSString *selectedText);
typedef void (^TungstenPopupOpenHandler)(NSString *urlString);

@protocol TungstenBrowserControllerDelegate <NSObject>

- (void)browserController:(TungstenBrowserController *)controller didUpdateTitle:(NSString *)title;
- (void)browserController:(TungstenBrowserController *)controller didUpdateURL:(NSString *)urlString;
- (void)browserController:(TungstenBrowserController *)controller
        didUpdateLoading:(BOOL)isLoading
               canGoBack:(BOOL)canGoBack
            canGoForward:(BOOL)canGoForward;
- (void)browserController:(TungstenBrowserController *)controller
     didUpdateFaviconURLs:(NSArray<NSString *> *)faviconURLs;

@end

@interface TungstenBrowserController : NSObject

- (instancetype)initWithInitialURL:(NSString *)initialURL;
- (instancetype)initWithInitialURL:(NSString *)initialURL incognito:(BOOL)incognito;
- (instancetype)initWithInitialURL:(NSString *)initialURL
                       privacyMode:(NSString *)privacyMode
                      torProxyHost:(NSString *)torProxyHost
                      torProxyPort:(int32_t)torProxyPort NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<TungstenBrowserControllerDelegate> delegate;
@property (nonatomic, copy, nullable) void (^browserDidCloseHandler)(void);
@property (nonatomic, copy, nullable) TungstenContextMenuSearchHandler contextMenuSearchHandler;
@property (nonatomic, copy, nullable) TungstenPopupOpenHandler popupOpenHandler;
@property (nonatomic, copy) NSString *contextMenuSearchEngineName;
@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic) CGFloat cornerRadius;

- (void)navigateToURLString:(NSString *)urlString;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoom;
- (void)findText:(NSString *)searchText
         forward:(BOOL)forward
       matchCase:(BOOL)matchCase
        findNext:(BOOL)findNext NS_SWIFT_NAME(find(text:forward:matchCase:findNext:));
- (void)stopFindingWithClearSelection:(BOOL)clearSelection NS_SWIFT_NAME(stopFinding(clearSelection:));
- (void)extractPageContentWithCompletion:(TungstenPageContentCompletion)completion
    NS_SWIFT_NAME(extractPageContent(completion:));
- (void)closeBrowser;
- (void)closeBrowserForWindowClose;
- (void)layoutBrowserView;

@end

NS_ASSUME_NONNULL_END
