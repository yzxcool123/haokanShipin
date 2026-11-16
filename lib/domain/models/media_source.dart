class MediaSource {
  const MediaSource({
    required this.key,
    required this.name,
    required this.type,
    required this.api,
    this.searchable = true,
    this.custom = false,
  });

  final String key;
  final String name;
  final int type;
  final String api;
  final bool searchable;
  final bool custom;

  bool get isCms => type == 1;

  bool get isHuangguo =>
      type == 3 &&
      (key == 'huangguo_web' ||
          api.contains('huangguo_web_spider') ||
          api.contains('huangguo-parser'));

  bool get isSupported => isCms || isHuangguo;

  factory MediaSource.fromJson(
    Map<String, dynamic> json, {
    bool custom = false,
  }) {
    return MediaSource(
      key: '${json['key']}',
      name: '${json['name'] ?? json['key']}',
      type: int.tryParse('${json['type'] ?? 1}') ?? 1,
      api: '${json['api'] ?? ''}',
      searchable: json['searchable'] != 0 && json['searchable'] != false,
      custom: custom,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'type': type,
        'api': api,
        'searchable': searchable ? 1 : 0,
      };

  MediaSource copyWith({String? name, String? api}) {
    return MediaSource(
      key: key,
      name: name ?? this.name,
      type: type,
      api: api ?? this.api,
      searchable: searchable,
      custom: custom,
    );
  }
}
