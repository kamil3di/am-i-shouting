import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let model = MeterModel()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(model: model)
        model.requestPermissionAndStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
