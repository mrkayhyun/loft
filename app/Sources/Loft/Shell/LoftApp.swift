import AppKit
import SwiftUI

@main
struct LoftApp: App {
    @State private var model = AppModel()

    init() {
        // Needed when launched as a bare executable (`swift run`) rather than
        // from the .app bundle, so the window can take focus.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Loft") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 660)
                .preferredColorScheme(.dark)
                .onAppear { NSApplication.shared.activate() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                ForEach(AppSection.allCases) { section in
                    Button(section.title) { model.section = section }
                        .keyboardShortcut(section.shortcut, modifiers: .command)
                }
            }
            CommandMenu("Clean") {
                Button("Smart Scan") { model.startSmartScan() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
