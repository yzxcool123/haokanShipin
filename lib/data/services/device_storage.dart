import 'package:flutter/services.dart';

class DeviceStorageException implements Exception {
  const DeviceStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 设备存储占用信息。容量与可用空间来自系统文件系统接口，
/// 应用占用优先统计沙箱数据，能拿到安装包体积时会一并计入。
class DeviceStorageInfo {
  const DeviceStorageInfo({
    required this.totalBytes,
    required this.availableBytes,
    required this.appBytes,
    required this.appDataBytes,
    required this.packageBytes,
    required this.includesPackage,
  });

  final int totalBytes;
  final int availableBytes;
  final int appBytes;
  final int appDataBytes;
  final int packageBytes;
  final bool includesPackage;

  int get usedBytes {
    final used = totalBytes - availableBytes;
    return used < 0 ? 0 : used;
  }

  String get appUsageLabel => includesPackage ? '本应用占用' : '应用数据占用';

  factory DeviceStorageInfo.fromMap(Map<Object?, Object?> map) {
    return DeviceStorageInfo(
      totalBytes: _asInt(map['totalBytes']),
      availableBytes: _asInt(map['availableBytes']),
      appBytes: _asInt(map['appBytes']),
      appDataBytes: _asInt(map['appDataBytes']),
      packageBytes: _asInt(map['packageBytes']),
      includesPackage: map['includesPackage'] == true,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class DeviceStorage {
  const DeviceStorage();

  static const _channel = MethodChannel('haokan_shipin/device_storage');

  Future<DeviceStorageInfo> query() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('getStorageInfo');
    if (raw == null) {
      throw const DeviceStorageException('无法读取存储空间');
    }
    final info = DeviceStorageInfo.fromMap(raw);
    if (info.totalBytes <= 0) {
      throw const DeviceStorageException('无法读取存储空间');
    }
    return info;
  }
}
