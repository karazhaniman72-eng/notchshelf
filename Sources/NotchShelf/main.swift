import AppKit

let application = NSApplication.shared

// Layout check: draw the panel into an off-screen window, write one PNG per
// tab, and quit. Never touches the screen or anything on it.
if Snapshot.isRequested {
    application.setActivationPolicy(.prohibited)
    DispatchQueue.main.async { Snapshot.run() }
    application.run()
}

let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
