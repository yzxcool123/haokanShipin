class Episode {
  const Episode({
    required this.id,
    required this.title,
    this.url,
  });

  /// 分集标识，例如 "1" 或站点自己的集数。
  final String id;
  final String title;
  final String? url;
}

class PlayLine {
  const PlayLine({required this.name, required this.episodes});

  final String name;
  final List<Episode> episodes;
}

class Playable {
  const Playable({
    required this.url,
    this.headers = const {},
    this.title = '',
  });

  final String url;
  final Map<String, String> headers;
  final String title;

  bool get isHls => url.toLowerCase().contains('.m3u8');
}
