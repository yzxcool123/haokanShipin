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
    this.sourceKey = '',
    this.vodId = '',
    this.name = '',
    this.pic = '',
    this.sourceName = '',
    this.lineName = '',
    this.episodeId = '',
    this.episodeTitle = '',
    this.startPosition = Duration.zero,
  });

  final String url;
  final Map<String, String> headers;
  final String title;
  final String sourceKey;
  final String vodId;
  final String name;
  final String pic;
  final String sourceName;
  final String lineName;
  final String episodeId;
  final String episodeTitle;
  final Duration startPosition;

  bool get isHls => url.toLowerCase().contains('.m3u8');

  bool get isLocal {
    final value = url.trim();
    if (value.isEmpty) return false;
    if (value.startsWith('file:') || value.startsWith('/')) return true;
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'file';
  }

  bool get canTrackHistory => sourceKey.isNotEmpty && vodId.isNotEmpty;

  Playable copyWith({
    String? url,
    Map<String, String>? headers,
    String? title,
    String? sourceKey,
    String? vodId,
    String? name,
    String? pic,
    String? sourceName,
    String? lineName,
    String? episodeId,
    String? episodeTitle,
    Duration? startPosition,
  }) {
    return Playable(
      url: url ?? this.url,
      headers: headers ?? this.headers,
      title: title ?? this.title,
      sourceKey: sourceKey ?? this.sourceKey,
      vodId: vodId ?? this.vodId,
      name: name ?? this.name,
      pic: pic ?? this.pic,
      sourceName: sourceName ?? this.sourceName,
      lineName: lineName ?? this.lineName,
      episodeId: episodeId ?? this.episodeId,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      startPosition: startPosition ?? this.startPosition,
    );
  }
}

class PlayerSession {
  const PlayerSession({
    required this.playable,
    this.episodes = const [],
  });

  final Playable playable;

  /// Sibling episodes on the current play line. Empty or a single
  /// item means the player should stay in one-episode mode.
  final List<Episode> episodes;

  bool get canSwitchEpisodes => episodes.length > 1;

  int get initialIndex {
    if (episodes.isEmpty) return 0;
    final id = playable.episodeId;
    if (id.isEmpty) return 0;
    final index = episodes.indexWhere((episode) => episode.id == id);
    return index >= 0 ? index : 0;
  }
}
