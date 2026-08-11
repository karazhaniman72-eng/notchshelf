import AppKit
import SwiftUI

/// Renders the panel off screen and writes it to a PNG, one file per tab.
///
/// Built for checking layout without looking at anyone's screen: the app draws
/// its own interface into a window parked outside the display, photographs that
/// window, and quits. Nothing about the desktop is captured or read.
///
///     NotchShelf.app/Contents/MacOS/NotchShelf --snapshot /tmp/shots
enum Snapshot {

    static var isRequested: Bool { CommandLine.arguments.contains("--snapshot") }

    static func run() {
        let arguments = CommandLine.arguments
        let folder: URL
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            folder = URL(fileURLWithPath: arguments[index + 1])
        } else {
            folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notchshots")
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let model = AppModel()
        model.panel.notchSize = CGSize(width: 179, height: 32)
        model.panel.isExpanded = true

        // The width the panel actually opens at. It used to be 720 here, so
        // every layout was checked a hundred and twenty points wider than it
        // ever runs.
        // The whole window, lanes included: the gear hangs outside the slab
        // and would be cropped away by a picture the width of the black.
        let width: CGFloat = PanelController.windowWidth
        let panelHeight: CGFloat = PanelController.panelHeight
        let height = panelHeight + model.panel.notchSize.height

        // A real window, just parked where no display reaches: SwiftUI only
        // lays out for a window that thinks it is on screen.
        let window = NSWindow(contentRect: CGRect(x: -4000, y: -4000, width: width, height: height),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        // The paper the panel is photographed on. Black for the black panel and
        // white for the white one: a light panel shot against black comes back
        // with a black surround nobody will ever see on screen.
        window.backgroundColor = Skin.shared.isLight ? .white : .black
        window.appearance = NSAppearance(named: Skin.shared.isLight ? .aqua : .darkAqua)
        let hosting = NSHostingView(rootView: ContentView(model: model,
                                                          state: model.panel,
                                                          shelf: model.shelf,
                                                          clipboard: model.clipboard,
                                                          convert: model.convert,
                                                          translate: model.translate,
                                                          settings: model.settings,
                                                          panelHeight: panelHeight))
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.contentView = hosting
        window.orderFront(nil)

        var pending = Plan.all
        capture(next: &pending, model: model, hosting: hosting, folder: folder)
    }

    private struct Plan {
        let name: String
        /// Handed the whole model, not only the panel: a graph with no formula
        /// in it proves nothing about how a graph is drawn.
        let apply: (AppModel) -> Void

        static var all: [Plan] {
            var plans: [Plan] = []
            for tab in PanelTab.allCases {
                plans.append(Plan(name: tab.rawValue) { model in
                    let state = model.panel
                    state.tab = tab
                    state.shelfMode = .shelf
                    state.clipboardMode = .history
                    state.calcMode = .math
                    state.systemMode = .machine
                    state.showsMonth = false
                })
            }
            // The tools that live inside a tab need their own frame.
            for mode in ShelfMode.allCases where mode != .shelf {
                plans.append(Plan(name: "shelf-" + mode.rawValue) { model in
                    let state = model.panel
                    state.tab = .shelf
                    state.shelfMode = mode
                })
            }
            plans.append(Plan(name: "clipboard-passwords") { model in
                let state = model.panel
                state.tab = .clipboard
                state.clipboardMode = .passwords
            })
            // A calculator with nothing typed into it proves only that the keys
            // are drawn; this one proves the new ones count.
            plans.append(Plan(name: "calc-counted") { model in
                let state = model.panel
                state.tab = .calc
                state.calcMode = .math
                model.math.input = "int(x^2, 0, 1)"
            })
            plans.append(Plan(name: "calc-theorem") { model in
                let state = model.panel
                state.tab = .calc
                state.calcMode = .theorem
            })
            plans.append(Plan(name: "calc-plot") { model in
                let state = model.panel
                state.tab = .calc
                state.calcMode = .plot
                model.math.input = "x^2 - 4"
            })
            for mode in SystemMode.allCases where mode != .machine {
                plans.append(Plan(name: "system-" + mode.rawValue) { model in
                    let state = model.panel
                    state.tab = .system
                    state.systemMode = mode
                })
            }
            plans.append(Plan(name: "plans-month") { model in
                let state = model.panel
                state.tab = .plans
                state.showsMonth = true
            })
            return plans
        }
    }

    /// One frame per run loop turn: SwiftUI needs a beat to lay a new tab out
    /// before there is anything worth photographing.
    private static func capture(next pending: inout [Plan],
                                model: AppModel,
                                hosting: NSView,
                                folder: URL) {
        guard !pending.isEmpty else {
            print("snapshots written to \(folder.path)")
            exit(0)
        }
        let plan = pending.removeFirst()
        plan.apply(model)

        var remaining = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            let wanted = model.panel.desiredHeight + model.panel.notchSize.height
            // NSHostingView is flipped, so the top of the panel is y = 0.
            write(hosting,
                  cropTo: CGRect(x: 0, y: 0, width: hosting.bounds.width, height: wanted),
                  to: folder.appendingPathComponent(plan.name + ".png"))
            capture(next: &remaining, model: model, hosting: hosting, folder: folder)
        }
    }

    private static func write(_ view: NSView, cropTo rect: CGRect, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
        view.cacheDisplay(in: rect, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("wrote \(url.lastPathComponent)")
    }
}
