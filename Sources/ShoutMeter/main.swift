import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--probe") {
    // Diagnostics: print live levels to stdout, no UI.
    let seconds = arguments.last.flatMap(Double.init) ?? 12
    Probe.run(seconds: seconds)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Menu bar only: no Dock icon, no main window.
application.setActivationPolicy(.accessory)
application.run()
