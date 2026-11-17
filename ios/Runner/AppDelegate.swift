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
    DeviceStorageChannel.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

private enum DeviceStorageChannel {
  static let name = "haokan_shipin/device_storage"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "getStorageInfo" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let info = try collectStorageInfo()
          DispatchQueue.main.async { result(info) }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "storage_unavailable",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        }
      }
    }
  }

  private static func collectStorageInfo() throws -> [String: Any] {
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    let values = try home.resourceValues(forKeys: [
      .volumeTotalCapacityKey,
      .volumeAvailableCapacityForImportantUsageKey,
      .volumeAvailableCapacityKey,
    ])
    guard let total = values.volumeTotalCapacity, total > 0 else {
      throw DeviceStorageError.unavailable
    }
    let available: Int64
    if let important = values.volumeAvailableCapacityForImportantUsage, important >= 0 {
      available = important
    } else if let free = values.volumeAvailableCapacity, free >= 0 {
      available = Int64(free)
    } else {
      throw DeviceStorageError.unavailable
    }

    let appDataBytes = allocatedSize(of: home)
    let packageBytes = allocatedSize(of: Bundle.main.bundleURL)
    return [
      "totalBytes": Int64(total),
      "availableBytes": available,
      "appBytes": appDataBytes + packageBytes,
      "appDataBytes": appDataBytes,
      "packageBytes": packageBytes,
      "includesPackage": true,
    ]
  }

  private static func allocatedSize(of url: URL) -> Int64 {
    let keys: [URLResourceKey] = [
      .isRegularFileKey,
      .isDirectoryKey,
      .isSymbolicLinkKey,
      .totalFileAllocatedSizeKey,
      .fileAllocatedSizeKey,
    ]
    if let values = try? url.resourceValues(forKeys: Set(keys)),
       values.isRegularFile == true {
      return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: keys,
      options: [],
      errorHandler: { _, _ in true }
    )
    var total: Int64 = 0
    while let file = enumerator?.nextObject() as? URL {
      guard let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
      if values.isSymbolicLink == true { continue }
      if values.isRegularFile == true {
        total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
      }
    }
    return total
  }
}

private enum DeviceStorageError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "无法读取存储空间"
  }
}
