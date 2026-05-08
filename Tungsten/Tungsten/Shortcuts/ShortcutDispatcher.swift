import Foundation

@MainActor
enum ShortcutDispatcher {
    static func dispatch(_ action: ShortcutAction, context: BrowserCommandContext) -> Bool {
        guard action.isAvailable else {
            return false
        }

        let browserModel = context.browserModel

        switch action.id {
        case .newTab:
            browserModel.createThread()
        case .newWindow:
            context.openNormalWindow()
        case .newIncognitoWindow:
            context.openIncognitoWindow()
        case .closeCurrentTab:
            browserModel.closeSelectedThread()
        case .reopenLastClosedTab:
            browserModel.reopenLastClosedThread()
        case .pinOrUnpinCurrentTab:
            browserModel.toggleSelectedThreadPin()
        case .copyCurrentURL:
            browserModel.copySelectedTabURL()
        case .copyCurrentURLAsMarkdown:
            browserModel.copySelectedTabURLAsMarkdown()
        case .focusAddressInput:
            browserModel.focusAddressInput()
        case .toggleSidebar:
            browserModel.toggleSidebar()
        case .clearUnpinnedTabs:
            browserModel.clearUnpinnedThreads()
        case .selectTab1:
            browserModel.selectThread(atZeroBasedIndex: 0)
        case .selectTab2:
            browserModel.selectThread(atZeroBasedIndex: 1)
        case .selectTab3:
            browserModel.selectThread(atZeroBasedIndex: 2)
        case .selectTab4:
            browserModel.selectThread(atZeroBasedIndex: 3)
        case .selectTab5:
            browserModel.selectThread(atZeroBasedIndex: 4)
        case .selectTab6:
            browserModel.selectThread(atZeroBasedIndex: 5)
        case .selectTab7:
            browserModel.selectThread(atZeroBasedIndex: 6)
        case .selectTab8:
            browserModel.selectThread(atZeroBasedIndex: 7)
        case .selectTab9:
            browserModel.selectThread(atZeroBasedIndex: 8)
        case .selectRecentTab:
            browserModel.selectRecentThread()
        case .selectPreviousTab:
            browserModel.selectPreviousThread()
        case .selectNextTab:
            browserModel.selectNextThread()
        case .goBack:
            browserModel.activePageSession?.goBack()
        case .goForward:
            browserModel.activePageSession?.goForward()
        case .reloadOrStopLoading:
            if browserModel.activePageSession?.isLoading == true {
                browserModel.activePageSession?.stopLoading()
            } else {
                browserModel.activePageSession?.reload()
            }
        case .viewHistory:
            browserModel.showHistory()
        case .zoomIn:
            browserModel.zoomIn()
        case .zoomOut:
            browserModel.zoomOut()
        case .resetZoom:
            browserModel.resetZoom()
        case .findInPage:
            browserModel.showFindInPage()
        }

        return true
    }
}
