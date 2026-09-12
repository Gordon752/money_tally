import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerReminderCalendar(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
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
