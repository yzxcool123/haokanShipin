class WatchRecord {
  const WatchRecord({
    required this.sourceKey,
    required this.vodId,
    required this.name,
    this.pic = '',
    this.sourceName = '',
    this.lineName = '',
    this.episodeId = '',
    this.episodeTitle = '',
    this.positionMs = 0,
    this.durationMs = 0,
    required this.updatedAtMs,
  });

  final String sourceKey;
  final String vodId;
  final String name;
  final String pic;
  final String sourceName;
  final String lineName;
  final String episodeId;
  final String episodeTitle;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;

  String get key => '$sourceKey|$vodId';

  double get progress {
    if (durationMs <= 0) return 0;
    final value = positionMs / durationMs;
    if (value.isNaN || value.isInfinite) return 0;
    return value.clamp(0.0, 1.0);
  }

  bool get isFinished => durationMs > 0 && positionMs >= (durationMs * 0.95);

  bool get isInProgress => !isFinished && positionMs >= 5000;

  factory WatchRecord.fromJson(Map<String, dynamic> json) {
    return WatchRecord(
      sourceKey: '${json['sourceKey'] ?? ''}',
      vodId: '${json['vodId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      pic: '${json['pic'] ?? ''}',
      sourceName: '${json['sourceName'] ?? ''}',
      lineName: '${json['lineName'] ?? ''}',
      episodeId: '${json['episodeId'] ?? ''}',
      episodeTitle: '${json['episodeTitle'] ?? ''}',
      positionMs: _asInt(json['positionMs']),
      durationMs: _asInt(json['durationMs']),
      updatedAtMs: _asInt(json['updatedAtMs']),
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
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAtMs': updatedAtMs,
      };

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}
