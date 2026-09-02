import SwiftUI

@main
struct LuminaApp: App {
    var body: some Scene {
        WindowGroup {
            CalendarWebView()
                .ignoresSafeArea()
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 680)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
