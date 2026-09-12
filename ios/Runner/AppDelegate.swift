import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.gordonbowles.moneytally.dailySync"
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      if let registrar = registry.registrar(
        forPlugin: "TrackmarkICloudBackupPlugin"
      ) {
        TrackmarkICloudBackupPlugin.register(with: registrar)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrackmarkReminderCalendar") {
      registerReminderCalendar(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "TrackmarkICloudBackupPlugin"
    ) {
      TrackmarkICloudBackupPlugin.register(with: registrar)
    }
  }

  private func registerReminderCalendar(messenger: FlutterBinaryMessenger) {

    let channel = FlutterMethodChannel(
      name: "trackmark/reminder_calendar", binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "useDeviceTimeZone",
            let args = call.arguments as? [String: Any],
            let id = args["id"] as? String,
            let year = args["year"] as? Int,
            let month = args["month"] as? Int,
            let day = args["day"] as? Int,
            let hour = args["hour"] as? Int,
            let minute = args["minute"] as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      let center = UNUserNotificationCenter.current()
      center.getPendingNotificationRequests { requests in
        guard let original = requests.first(where: { $0.identifier == id }) else {
          DispatchQueue.main.async {
            result(FlutterError(code: "missing_reminder", message: "The reminder was not registered.", details: nil))
          }
          return
        }
        // Intentionally omit calendar/timeZone: this is a local wall-clock
        // reminder, not an instant pinned to the zone at creation time.
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let replacement = UNNotificationRequest(identifier: id, content: original.content, trigger: trigger)
        center.add(replacement) { error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "reminder_registration", message: error.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
      }
    }
  }
}
