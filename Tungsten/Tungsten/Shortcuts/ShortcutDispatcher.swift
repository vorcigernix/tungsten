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
            browserModel.addTab()
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
            browserModel.copySelectedTabURL()
        case .copyCurrentURLAsMarkdown:
            browserModel.copySelectedTabURLAsMarkdown()
        case .focusAddressInput:
            browserModel.focusAddressInput()
        case .toggleSidebar:
            browserModel.toggleSidebar()
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
            browserModel.selectedTab?.goBack()
        case .goForward:
            browserModel.selectedTab?.goForward()
        case .reloadOrStopLoading:
            if browserModel.selectedTab?.isLoading == true {
                browserModel.selectedTab?.stopLoading()
            } else {
                browserModel.selectedTab?.reload()
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
