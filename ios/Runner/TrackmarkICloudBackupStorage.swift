import Foundation
import Flutter

private enum TrackmarkICloudError: LocalizedError {
  case unavailable
  case containerUnavailable
  case invalidFileName
  case invalidArguments
  case unreadableFile
  case downloadTimedOut

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "iCloud Drive is unavailable or the device is not signed in to iCloud."
    case .containerUnavailable:
      return "Trackmark's iCloud container is unavailable."
    case .invalidFileName:
      return "The backup file name is invalid."
    case .invalidArguments:
      return "The iCloud backup request is invalid."
    case .unreadableFile:
      return "The iCloud backup is not available for reading."
    case .downloadTimedOut:
      return "The iCloud backup did not finish downloading in time."
    }
  }
}

private enum TrackmarkICloudState: String {
  case available
  case unavailable
  case containerUnavailable
  case waitingForUpload
  case uploaded
  case downloadRequired
  case downloading
  case error
}

final class TrackmarkICloudBackupStorage: NSObject {
  static let shared = TrackmarkICloudBackupStorage()
  static let containerIdentifier = "iCloud.com.gordonbowles.moneytally"

  private let fileManager: FileManager
  private let operationQueue = DispatchQueue(
    label: "com.gordonbowles.moneytally.icloud-backups",
    qos: .utility
  )
  private var identityObserver: NSObjectProtocol?
  private var identityGeneration = 0
  // NSMetadataQuery must remain strongly retained while it gathers results.
  // This dictionary is accessed only on the main queue.
  private var activeMetadataQueries = [UUID: NSMetadataQuery]()

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
    super.init()
    identityObserver = NotificationCenter.default.addObserver(
      forName: NSNotification.Name.NSUbiquityIdentityDidChange,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      // No physical container URLs are retained. Bumping this generation makes
      // the account transition explicit and every later operation resolves the
      // active container again.
      self?.identityGeneration += 1
    }
  }

  deinit {
    if let identityObserver {
      NotificationCenter.default.removeObserver(identityObserver)
    }
  }

  func availability() -> [String: Any] {
    guard fileManager.ubiquityIdentityToken != nil else {
      return statePayload(.unavailable)
    }
    guard fileManager.url(
      forUbiquityContainerIdentifier: Self.containerIdentifier
    ) != nil else {
      return statePayload(.containerUnavailable)
    }
    return statePayload(.available)
  }

  func resolveBackupContainer(
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    perform(completion) {
      let directory = try self.backupDirectory(create: true)
      return [
        "state": TrackmarkICloudState.available.rawValue,
        "displayName": "Trackmark Money/Backups",
        "identityGeneration": self.identityGeneration,
        "path": directory.path,
      ]
    }
  }

  func writeBackup(
    fileName: String,
    content: String,
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    perform(completion) {
      try self.validate(fileName: fileName)
      let directory = try self.backupDirectory(create: true)
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      var operationError: Error?
      var writtenURL: URL?

      coordinator.coordinate(
        writingItemAt: directory,
        options: [],
        error: &coordinationError
      ) { coordinatedDirectory in
        do {
          let destination = self.collisionSafeURL(
            for: fileName,
            in: coordinatedDirectory
          )
          let pending = coordinatedDirectory.appendingPathComponent(
            ".\(destination.lastPathComponent).pending-\(UUID().uuidString)"
          )
          guard let data = content.data(using: .utf8) else {
            throw TrackmarkICloudError.invalidArguments
          }
          try data.write(to: pending, options: [.atomic])
          do {
            try self.fileManager.moveItem(at: pending, to: destination)
          } catch {
            try? self.fileManager.removeItem(at: pending)
            throw error
          }
          writtenURL = destination
        } catch {
          operationError = error
        }
      }

      if let coordinationError { throw coordinationError }
      if let operationError { throw operationError }
      guard let writtenURL else { throw TrackmarkICloudError.unreadableFile }
      return try self.metadata(for: writtenURL)
    }
  }

  func readBackup(
    fileName: String,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    perform(completion) {
      let file = try self.fileURL(fileName: fileName)
      let status = try self.fileState(for: file)
      if status == .downloadRequired || status == .downloading {
        throw TrackmarkICloudError.unreadableFile
      }
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      var operationError: Error?
      var content: String?
      coordinator.coordinate(
        readingItemAt: file,
        options: [],
        error: &coordinationError
      ) { coordinatedURL in
        do {
          content = try String(contentsOf: coordinatedURL, encoding: .utf8)
        } catch {
          operationError = error
        }
      }
      if let coordinationError { throw coordinationError }
      if let operationError { throw operationError }
      guard let content else { throw TrackmarkICloudError.unreadableFile }
      return content
    }
  }

  func listBackups(
    completion: @escaping (Result<[[String: Any]], Error>) -> Void
  ) {
    perform(completion) {
      let directory = try self.backupDirectory(create: true)
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      var operationError: Error?
      var entries = [[String: Any]]()
      coordinator.coordinate(
        readingItemAt: directory,
        options: [],
        error: &coordinationError
      ) { coordinatedDirectory in
        do {
          let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey,
          ]
          let urls = try self.fileManager.contentsOfDirectory(
            at: coordinatedDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
          )
          entries = try urls.compactMap { url in
            guard Self.isValidManagedBackupFileName(url.lastPathComponent) else {
              return nil
            }
            return try self.metadata(for: url)
          }
        } catch {
          operationError = error
        }
      }
      if let coordinationError { throw coordinationError }
      if let operationError { throw operationError }

      // A directory listing is fast for local representations, while
      // NSMetadataQuery also discovers ubiquitous items that exist in iCloud
      // but have not been downloaded on this device. Merge by logical name.
      let metadataURLs = try self.queryUbiquitousBackupURLs(in: directory)
      var entriesByName = Dictionary(
        uniqueKeysWithValues: entries.map {
          (($0["fileName"] as? String) ?? "", $0)
        }
      )
      for url in metadataURLs where entriesByName[url.lastPathComponent] == nil {
        guard let item = try? self.metadata(for: url) else { continue }
        entriesByName[url.lastPathComponent] = item
      }
      entries = Array(entriesByName.values)
      return entries.sorted {
        (($0["modifiedAt"] as? Double) ?? 0) >
          (($1["modifiedAt"] as? Double) ?? 0)
      }
    }
  }

  func deleteBackup(
    fileName: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    perform(completion) {
      let file = try self.fileURL(fileName: fileName)
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      var operationError: Error?
      coordinator.coordinate(
        writingItemAt: file,
        options: .forDeleting,
        error: &coordinationError
      ) { coordinatedURL in
        do {
          try self.fileManager.removeItem(at: coordinatedURL)
        } catch {
          operationError = error
        }
      }
      if let coordinationError { throw coordinationError }
      if let operationError { throw operationError }
    }
  }

  func backupStatus(
    fileName: String,
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    perform(completion) {
      try self.metadata(for: self.fileURL(fileName: fileName))
    }
  }

  func downloadBackupIfNeeded(
    fileName: String,
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    perform(completion) {
      let file = try self.fileURL(fileName: fileName)
      var state = try self.fileState(for: file)
      if state == .downloadRequired {
        try self.fileManager.startDownloadingUbiquitousItem(at: file)
        state = .downloading
      }
      guard state == .downloading else {
        return try self.metadata(for: file)
      }

      let deadline = Date().addingTimeInterval(30)
      while Date() < deadline {
        Thread.sleep(forTimeInterval: 0.25)
        state = try self.fileState(for: file)
        if state != .downloading && state != .downloadRequired {
          return try self.metadata(for: file)
        }
      }
      throw TrackmarkICloudError.downloadTimedOut
    }
  }

  func runSmokeTest(
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    let fileName = "trackmark_money_automatic_backup_smoke_\(UUID().uuidString).json"
    writeBackup(fileName: fileName, content: "{\"trackmarkSmokeTest\":true}") {
      writeResult in
      switch writeResult {
      case .failure(let error):
        completion(.failure(error))
      case .success(let metadata):
        self.readBackup(fileName: metadata["fileName"] as? String ?? fileName) {
          readResult in
          switch readResult {
          case .failure(let error):
            completion(.failure(error))
          case .success(let content):
            guard content == "{\"trackmarkSmokeTest\":true}" else {
              completion(.failure(TrackmarkICloudError.unreadableFile))
              return
            }
            let actualName = metadata["fileName"] as? String ?? fileName
            self.deleteBackup(fileName: actualName) { deleteResult in
              switch deleteResult {
              case .failure(let error): completion(.failure(error))
              case .success:
                completion(.success([
                  "success": true,
                  "fileName": actualName,
                  "deleted": true,
                ]))
              }
            }
          }
        }
      }
    }
  }

  private func perform<T>(
    _ completion: @escaping (Result<T, Error>) -> Void,
    operation: @escaping () throws -> T
  ) {
    operationQueue.async {
      do {
        completion(.success(try operation()))
      } catch {
        completion(.failure(error))
      }
    }
  }

  private func backupDirectory(create: Bool) throws -> URL {
    guard fileManager.ubiquityIdentityToken != nil else {
      throw TrackmarkICloudError.unavailable
    }
    guard let container = fileManager.url(
      forUbiquityContainerIdentifier: Self.containerIdentifier
    ) else {
      throw TrackmarkICloudError.containerUnavailable
    }
    let directory = container
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent("Backups", isDirectory: true)
    if create {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    }
    return directory
  }

  private func fileURL(fileName: String) throws -> URL {
    try validate(fileName: fileName)
    let directory = try backupDirectory(create: true)
    let url = directory.appendingPathComponent(fileName, isDirectory: false)
    guard fileManager.fileExists(atPath: url.path) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return url
  }

  private func validate(fileName: String) throws {
    guard Self.isValidManagedBackupFileName(fileName),
          fileName == URL(fileURLWithPath: fileName).lastPathComponent,
          !fileName.contains("/"),
          !fileName.contains("\\") else {
      throw TrackmarkICloudError.invalidFileName
    }
  }

  static func isValidManagedBackupFileName(_ fileName: String) -> Bool {
    guard fileName.hasPrefix("trackmark_money_"),
          fileName.hasSuffix(".json"),
          fileName.range(
            of: "^[A-Za-z0-9._-]+\\.json$",
            options: .regularExpression
          ) != nil else {
      return false
    }
    return true
  }

  private func collisionSafeURL(for fileName: String, in directory: URL) -> URL {
    let requested = directory.appendingPathComponent(fileName)
    guard fileManager.fileExists(atPath: requested.path) else {
      return requested
    }
    let base = requested.deletingPathExtension().lastPathComponent
    let suffix = UUID().uuidString.prefix(8).lowercased()
    return directory.appendingPathComponent("\(base)_\(suffix).json")
  }

  private func queryUbiquitousBackupURLs(in directory: URL) throws -> [URL] {
    let semaphore = DispatchSemaphore(value: 0)
    let queryID = UUID()
    var urls = [URL]()
    var didFinish = false

    DispatchQueue.main.async {
      let query = NSMetadataQuery()
      query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
      query.predicate = NSPredicate(
        format: "%K BEGINSWITH %@ AND %K BEGINSWITH %@",
        NSMetadataItemPathKey,
        directory.path,
        NSMetadataItemFSNameKey,
        "trackmark_money_"
      )

      var observer: NSObjectProtocol?
      let finish: () -> Void = {
        guard !didFinish else { return }
        didFinish = true
        query.disableUpdates()
        query.stop()
        if let observer {
          NotificationCenter.default.removeObserver(observer)
        }
        self.activeMetadataQueries.removeValue(forKey: queryID)
        semaphore.signal()
      }

      observer = NotificationCenter.default.addObserver(
        forName: .NSMetadataQueryDidFinishGathering,
        object: query,
        queue: .main
      ) { _ in
        query.disableUpdates()
        urls = query.results.compactMap { result in
          (result as? NSMetadataItem)?.value(
            forAttribute: NSMetadataItemURLKey
          ) as? URL
        }.filter { Self.isValidManagedBackupFileName($0.lastPathComponent) }
        finish()
      }

      self.activeMetadataQueries[queryID] = query
      guard query.start() else {
        finish()
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        finish()
      }
    }

    guard semaphore.wait(timeout: .now() + 11) == .success else {
      throw CocoaError(.fileReadUnknown)
    }
    return urls
  }

  private func metadata(for url: URL) throws -> [String: Any] {
    let keys: Set<URLResourceKey> = [
      .contentModificationDateKey,
      .fileSizeKey,
      .isUbiquitousItemKey,
      .ubiquitousItemDownloadingStatusKey,
      .ubiquitousItemIsDownloadingKey,
      .ubiquitousItemIsUploadedKey,
      .ubiquitousItemIsUploadingKey,
      .ubiquitousItemUploadingErrorKey,
      .ubiquitousItemDownloadingErrorKey,
    ]
    let values = try url.resourceValues(forKeys: keys)
    let state = try fileState(for: url, values: values)
    var result: [String: Any] = [
      "fileName": url.lastPathComponent,
      "state": state.rawValue,
      "isDownloaded": values.ubiquitousItemDownloadingStatus != .notDownloaded,
      "isUploaded": values.ubiquitousItemIsUploaded ?? false,
      "isUploading": values.ubiquitousItemIsUploading ?? false,
      "size": values.fileSize ?? 0,
    ]
    if let modifiedAt = values.contentModificationDate {
      result["modifiedAt"] = modifiedAt.timeIntervalSince1970 * 1000
    }
    if let error = values.ubiquitousItemUploadingError ??
      values.ubiquitousItemDownloadingError {
      result["error"] = error.localizedDescription
    }
    return result
  }

  private func fileState(for url: URL) throws -> TrackmarkICloudState {
    let values = try url.resourceValues(forKeys: [
      .isUbiquitousItemKey,
      .ubiquitousItemDownloadingStatusKey,
      .ubiquitousItemIsDownloadingKey,
      .ubiquitousItemIsUploadedKey,
      .ubiquitousItemIsUploadingKey,
      .ubiquitousItemUploadingErrorKey,
      .ubiquitousItemDownloadingErrorKey,
    ])
    return try fileState(for: url, values: values)
  }

  private func fileState(
    for url: URL,
    values: URLResourceValues
  ) throws -> TrackmarkICloudState {
    if values.ubiquitousItemUploadingError != nil ||
      values.ubiquitousItemDownloadingError != nil {
      return .error
    }
    if values.ubiquitousItemIsDownloading == true {
      return .downloading
    }
    if values.isUbiquitousItem == true &&
      values.ubiquitousItemDownloadingStatus == .notDownloaded {
      return .downloadRequired
    }
    if values.ubiquitousItemIsUploaded == true {
      return .uploaded
    }
    if values.isUbiquitousItem == true || values.ubiquitousItemIsUploading == true {
      return .waitingForUpload
    }
    return .available
  }

  private func statePayload(_ state: TrackmarkICloudState) -> [String: Any] {
    ["state": state.rawValue]
  }
}

final class TrackmarkICloudBackupPlugin: NSObject, FlutterPlugin {
  private let storage: TrackmarkICloudBackupStorage

  init(storage: TrackmarkICloudBackupStorage = .shared) {
    self.storage = storage
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.gordonbowles.moneytally/icloud_backup_storage",
      binaryMessenger: registrar.messenger()
    )
    let instance = TrackmarkICloudBackupPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isICloudAvailable":
      result(storage.availability())
    case "resolveBackupContainer":
      bridge(storage.resolveBackupContainer, result: result)
    case "writeBackup":
      guard let arguments = call.arguments as? [String: Any],
            let fileName = arguments["fileName"] as? String,
            let content = arguments["content"] as? String else {
        send(error: TrackmarkICloudError.invalidArguments, result: result)
        return
      }
      storage.writeBackup(fileName: fileName, content: content) {
        self.finish($0, result: result)
      }
    case "listBackups":
      storage.listBackups { self.finish($0, result: result) }
    case "readBackup":
      withFileName(call, result: result) { fileName in
        self.storage.readBackup(fileName: fileName) {
          self.finish($0, result: result)
        }
      }
    case "deleteBackup":
      withFileName(call, result: result) { fileName in
        self.storage.deleteBackup(fileName: fileName) {
          self.finish($0.map { true }, result: result)
        }
      }
    case "downloadBackupIfNeeded":
      withFileName(call, result: result) { fileName in
        self.storage.downloadBackupIfNeeded(fileName: fileName) {
          self.finish($0, result: result)
        }
      }
    case "backupStatus":
      withFileName(call, result: result) { fileName in
        self.storage.backupStatus(fileName: fileName) {
          self.finish($0, result: result)
        }
      }
    case "runSmokeTest":
      storage.runSmokeTest { self.finish($0, result: result) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func withFileName(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult,
    operation: (String) -> Void
  ) {
    guard let arguments = call.arguments as? [String: Any],
          let fileName = arguments["fileName"] as? String else {
      send(error: TrackmarkICloudError.invalidArguments, result: result)
      return
    }
    operation(fileName)
  }

  private func bridge<T>(
    _ operation: (@escaping (Result<T, Error>) -> Void) -> Void,
    result: @escaping FlutterResult
  ) {
    operation { self.finish($0, result: result) }
  }

  private func finish<T>(
    _ operationResult: Result<T, Error>,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      switch operationResult {
      case .success(let value): result(value)
      case .failure(let error): self.send(error: error, result: result)
      }
    }
  }

  private func send(error: Error, result: @escaping FlutterResult) {
    let code: String
    switch error {
    case TrackmarkICloudError.unavailable: code = "icloud_unavailable"
    case TrackmarkICloudError.containerUnavailable: code = "container_unavailable"
    case TrackmarkICloudError.invalidFileName: code = "invalid_file_name"
    case TrackmarkICloudError.downloadTimedOut: code = "download_timeout"
    default: code = "icloud_storage_error"
    }
    result(FlutterError(
      code: code,
      message: error.localizedDescription,
      details: nil
    ))
  }
}
