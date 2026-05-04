/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
CEF renderer/GPU/helper process entry point.
*/

#include "include/cef_app.h"
#include "wrapper/cef_library_loader.h"

class TungstenSubprocessApp final : public CefApp {
private:
    IMPLEMENT_REFCOUNTING(TungstenSubprocessApp);
};

int main(int argc, char *argv[]) {
    CefScopedLibraryLoader libraryLoader;
    if (!libraryLoader.LoadInHelper()) {
        return 1;
    }

    CefMainArgs mainArgs(argc, argv);
    CefRefPtr<TungstenSubprocessApp> app(new TungstenSubprocessApp());
    return CefExecuteProcess(mainArgs, app.get(), nullptr);
}
