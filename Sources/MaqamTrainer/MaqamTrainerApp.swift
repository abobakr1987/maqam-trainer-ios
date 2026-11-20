import SwiftUI

@main
struct MaqamTrainerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Arabic-first UI: right-to-left layout and Arabic locale
                // for the whole app. Note names stay in English (A–G).
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        }
    }
}
