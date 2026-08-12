import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var ownedMainWindow: NSWindow?

  override func applicationWillFinishLaunching(_ notification: Notification) {
    signal(SIGPIPE, SIG_IGN)
    if mainFlutterWindow == nil {
      let flutterViewController = FlutterViewController()
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "Git Desktop"
      window.center()
      window.contentViewController = flutterViewController
      RegisterGeneratedPlugins(registry: flutterViewController)
      mainFlutterWindow = window
      ownedMainWindow = window
    }
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
