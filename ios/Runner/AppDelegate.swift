import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // APNs diagnostics: firebase_messaging receives the device token only via
  // FlutterAppDelegate's plugin forwarding. These log whether iOS delivers
  // the token/failure to the app at all — if [apns] lines appear here while
  // the Dart-side probe still reports the APNs token ABSENT, the forwarding
  // bridge between this delegate and the plugin is what's broken.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NSLog("[apns] didRegisterForRemoteNotifications: %d bytes", deviceToken.count)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[apns] didFailToRegisterForRemoteNotifications: %@", String(describing: error))
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
