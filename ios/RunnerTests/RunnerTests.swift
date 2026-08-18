import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testManagedBackupFileNameValidation() {
    XCTAssertTrue(
      TrackmarkICloudBackupStorage.isValidManagedBackupFileName(
        "trackmark_money_automatic_backup_2026-08-17_230000.json"
      )
    )
    XCTAssertTrue(
      TrackmarkICloudBackupStorage.isValidManagedBackupFileName(
        "trackmark_money_pre_restore_backup_2026-08-17_230000.json"
      )
    )
    XCTAssertFalse(
      TrackmarkICloudBackupStorage.isValidManagedBackupFileName(
        "unrelated_file.json"
      )
    )
    XCTAssertFalse(
      TrackmarkICloudBackupStorage.isValidManagedBackupFileName(
        "trackmark_money_../outside.json"
      )
    )
  }

  func testICloudAvailabilityReturnsKnownState() {
    let payload = TrackmarkICloudBackupStorage.shared.availability()
    guard let state = payload["state"] as? String else {
      return XCTFail("Availability did not return a state.")
    }
    XCTAssertTrue([
      "available",
      "unavailable",
      "containerUnavailable",
    ].contains(state))
  }

  func testLiveICloudTemporaryFileSmokeTest() throws {
    guard ProcessInfo.processInfo.environment["TRACKMARK_ICLOUD_SMOKE_TEST"] == "1" else {
      throw XCTSkip("Live iCloud smoke test is opt-in.")
    }
    let completed = expectation(description: "temporary iCloud file round trip")
    var smokeError: Error?
    TrackmarkICloudBackupStorage.shared.runSmokeTest { result in
      switch result {
      case .success(let payload):
        XCTAssertEqual(payload["success"] as? Bool, true)
        XCTAssertEqual(payload["deleted"] as? Bool, true)
      case .failure(let error):
        smokeError = error
      }
      completed.fulfill()
    }
    wait(for: [completed], timeout: 45)
    if let smokeError { throw smokeError }
  }
}
