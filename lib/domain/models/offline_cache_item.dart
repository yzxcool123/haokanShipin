import 'playable.dart';

enum OfflineCacheStatus {
  queued,
  downloading,
  completed,
  failed,
}

class OfflineCacheItem {
  const OfflineCacheItem({
    required this.sourceKey,
    required this.vodId,
    required this.name,
    this.pic = '',
    this.sourceName = '',
    this.lineName = '',
    required this.episodeId,
    this.episodeTitle = '',
    this.localPath = '',
    this.coverPath = '',
    this.bytes = 0,
    this.status = OfflineCacheStatus.queued,
    this.progress = 0,
    this.error = '',
    required this.createdAtMs,
    this.completedAtMs = 0,
  });

  final String sourceKey;
  final String vodId;
  final String name;
  final String pic;
  final String sourceName;
  final String lineName;
  final String episodeId;
  final String episodeTitle;
  final String localPath;
  final String coverPath;
  final int bytes;
  final OfflineCacheStatus status;
  final double progress;
  final String error;
  final int createdAtMs;
  final int completedAtMs;

  /// 稳定缓存标识：源 + 影片 + 线路 + 分集。
  String get id => '$sourceKey|$vodId|$lineName|$episodeId';

  bool get isCompleted => status == OfflineCacheStatus.completed;

  bool get isActive =>
      status == OfflineCacheStatus.queued ||
      status == OfflineCacheStatus.downloading;

  bool get isFailed => status == OfflineCacheStatus.failed;

  bool get hasLocalFile => localPath.isNotEmpty;

  String get displayTitle => name.isNotEmpty ? name : episodeTitle;

  String get displayEpisode {
    final parts = [
      if (lineName.isNotEmpty) lineName,
      if (episodeTitle.isNotEmpty) episodeTitle,
    ];
    return parts.join(' · ');
  }

  factory OfflineCacheItem.fromJson(Map<String, dynamic> json) {
    return OfflineCacheItem(
      sourceKey: '${json['sourceKey'] ?? ''}',
      vodId: '${json['vodId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      pic: '${json['pic'] ?? ''}',
      sourceName: '${json['sourceName'] ?? ''}',
      lineName: '${json['lineName'] ?? ''}',
      episodeId: '${json['episodeId'] ?? ''}',
      episodeTitle: '${json['episodeTitle'] ?? ''}',
      localPath: '${json['localPath'] ?? ''}',
      coverPath: '${json['coverPath'] ?? ''}',
      bytes: _asInt(json['bytes']),
      status: offlineCacheStatusFromName('${json['status'] ?? ''}'),
      progress: _asDouble(json['progress']),
      error: '${json['error'] ?? ''}',
      createdAtMs: _asInt(json['createdAtMs']),
      completedAtMs: _asInt(json['completedAtMs']),
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceKey': sourceKey,
        'vodId': vodId,
        'name': name,
        'pic': pic,
        'sourceName': sourceName,
        'lineName': lineName,
        'episodeId': episodeId,
        'episodeTitle': episodeTitle,
        'localPath': localPath,
        'coverPath': coverPath,
        'bytes': bytes,
        'status': status.name,
        'progress': progress,
        'error': error,
        'createdAtMs': createdAtMs,
        'completedAtMs': completedAtMs,
      };

  Playable toPlayable({Duration startPosition = Duration.zero}) {
    final title = episodeTitle.isEmpty ? name : '$name $episodeTitle';
    return Playable(
      url: localPath,
      headers: const {},
      title: title,
      sourceKey: sourceKey,
      vodId: vodId,
      name: name,
      pic: pic,
      sourceName: sourceName,
      lineName: lineName,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
      startPosition: startPosition,
    );
  }

  OfflineCacheItem copyWith({
    String? sourceKey,
    String? vodId,
    String? name,
    String? pic,
    String? sourceName,
    String? lineName,
    String? episodeId,
    String? episodeTitle,
    String? localPath,
    String? coverPath,
    int? bytes,
    OfflineCacheStatus? status,
    double? progress,
    String? error,
    int? createdAtMs,
    int? completedAtMs,
    bool clearError = false,
  }) {
    return OfflineCacheItem(
      sourceKey: sourceKey ?? this.sourceKey,
      vodId: vodId ?? this.vodId,
      name: name ?? this.name,
      pic: pic ?? this.pic,
      sourceName: sourceName ?? this.sourceName,
      lineName: lineName ?? this.lineName,
      episodeId: episodeId ?? this.episodeId,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      localPath: localPath ?? this.localPath,
      coverPath: coverPath ?? this.coverPath,
      bytes: bytes ?? this.bytes,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: clearError ? '' : (error ?? this.error),
      createdAtMs: createdAtMs ?? this.createdAtMs,
      completedAtMs: completedAtMs ?? this.completedAtMs,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  static double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}

OfflineCacheStatus offlineCacheStatusFromName(String name) {
  for (final item in OfflineCacheStatus.values) {
    if (item.name == name) return item;
  }
  return OfflineCacheStatus.failed;
}
