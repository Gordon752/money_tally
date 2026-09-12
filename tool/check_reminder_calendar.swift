// Run with: xcrun swift tool/check_reminder_calendar.swift
// Read-only diagnostic: creates triggers but never registers notifications.
// NSTimeZone.default affects only this process, not macOS timezone settings.
import Foundation
import UserNotifications

let originalZone = NSTimeZone.default
defer { NSTimeZone.default = originalZone }
let eastern = TimeZone(identifier: "America/New_York")!
let central = TimeZone(identifier: "America/Chicago")!

func trigger(zone: TimeZone?) -> UNCalendarNotificationTrigger {
  var components = DateComponents()
  components.year = 2099
  components.month = 9
  components.day = 17
  components.hour = 11
  components.minute = 40
  components.second = 0
  components.timeZone = zone
  return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
}

NSTimeZone.default = eastern
let floating = trigger(zone: nil)
let fixed = trigger(zone: eastern)
guard let floatingEastern = floating.nextTriggerDate(),
      let fixedEastern = fixed.nextTriggerDate() else {
  fatalError("Could not compute Eastern trigger dates")
}
NSTimeZone.default = central
guard let floatingCentral = floating.nextTriggerDate(),
      let fixedCentral = fixed.nextTriggerDate() else {
  fatalError("Could not compute Central trigger dates")
}
precondition(floating.dateComponents.timeZone == nil)
precondition(floatingCentral.timeIntervalSince(floatingEastern) == 3600,
             "Floating trigger must move one hour when local zone changes")
precondition(fixedCentral == fixedEastern,
             "Fixed Eastern trigger must keep the same instant")
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = central
precondition(calendar.component(.hour, from: fixedCentral) == 10)
precondition(calendar.component(.minute, from: fixedCentral) == 40)
print("PASS: existing floating trigger follows process-local timezone changes")
print("PASS: fixed 11:40 Eastern trigger remains 10:40 Central")
print("No notifications registered; no device timezone settings changed.")
