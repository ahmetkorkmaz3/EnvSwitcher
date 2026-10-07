import SwiftUI

struct MenuContent: View {
    var body: some View {
        Button("Çık") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
