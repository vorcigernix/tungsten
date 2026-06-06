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
            browserModel.createTab()
        case .newIncognitoTab:
            browserModel.createIncognitoTab()
        case .newTorTab:
            browserModel.createTorTab()
        case .newWindow:
            context.openNormalWindow()
        case .newIncognitoWindow:
            context.openIncognitoWindow()
        case .closeCurrentTab:
            browserModel.closeSelectedTab()
        case .reopenLastClosedTab:
            browserModel.reopenLastClosedTab()
        case .pinOrUnpinCurrentTab:
            browserModel.toggleSelectedTabPin()
        case .copyCurrentURL:
            browserModel.copyActivePageURL()
        case .copyCurrentURLAsMarkdown:
            browserModel.copyActivePageURLAsMarkdown()
        case .focusAddressInput:
            browserModel.focusAddressInput()
        case .clearUnpinnedTabs:
            browserModel.clearUnpinnedTabs()
        case .selectTab1:
            browserModel.selectTab(atZeroBasedIndex: 0)
        case .selectTab2:
            browserModel.selectTab(atZeroBasedIndex: 1)
        case .selectTab3:
            browserModel.selectTab(atZeroBasedIndex: 2)
        case .selectTab4:
            browserModel.selectTab(atZeroBasedIndex: 3)
        case .selectTab5:
            browserModel.selectTab(atZeroBasedIndex: 4)
        case .selectTab6:
            browserModel.selectTab(atZeroBasedIndex: 5)
        case .selectTab7:
            browserModel.selectTab(atZeroBasedIndex: 6)
        case .selectTab8:
            browserModel.selectTab(atZeroBasedIndex: 7)
        case .selectTab9:
            browserModel.selectTab(atZeroBasedIndex: 8)
        case .selectRecentTab:
            browserModel.selectRecentTab()
        case .selectPreviousTab:
            browserModel.selectPreviousTab()
        case .selectNextTab:
            browserModel.selectNextTab()
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
