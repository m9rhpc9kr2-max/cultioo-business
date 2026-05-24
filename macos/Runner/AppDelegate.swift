import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      guard url.scheme == "cultioo-business" else { continue }
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else { continue }

      guard
        let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
      else { continue }

      let channel = FlutterMethodChannel(
        name: "cultioo_business/oauth_callback",
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.invokeMethod("onCode", arguments: ["code": code])
    }
  }
}
