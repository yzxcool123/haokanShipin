class FavoriteItem {
  const FavoriteItem({
    required this.sourceKey,
    required this.vodId,
    required this.name,
    this.pic = '',
    this.sourceName = '',
    this.remarks = '',
    required this.addedAtMs,
  });

  final String sourceKey;
  final String vodId;
  final String name;
  final String pic;
  final String sourceName;
  final String remarks;
  final int addedAtMs;

  String get key => '$sourceKey|$vodId';

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      sourceKey: '${json['sourceKey'] ?? ''}',
      vodId: '${json['vodId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      pic: '${json['pic'] ?? ''}',
      sourceName: '${json['sourceName'] ?? ''}',
      remarks: '${json['remarks'] ?? ''}',
      addedAtMs: _asInt(json['addedAtMs']),
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceKey': sourceKey,
        'vodId': vodId,
        'name': name,
        'pic': pic,
        'sourceName': sourceName,
        'remarks': remarks,
        'addedAtMs': addedAtMs,
      };

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}
