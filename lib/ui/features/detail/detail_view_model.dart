import 'package:flutter/foundation.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/favorite_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/offline_cache_repository.dart';
import '../../../domain/models/offline_cache_item.dart';
import '../../../domain/models/playable.dart';
import '../../../domain/models/vod_detail.dart';

class DetailViewModel extends ChangeNotifier {
  DetailViewModel({
    required CatalogRepository catalogRepository,
    required HistoryRepository historyRepository,
    required FavoriteRepository favoriteRepository,
    required OfflineCacheRepository offlineCacheRepository,
    required this.sourceKey,
    required this.vodId,
  })  : _catalogRepository = catalogRepository,
        _historyRepository = historyRepository,
        _favoriteRepository = favoriteRepository,
        _offlineCacheRepository = offlineCacheRepository {
    _favoriteRepository.addListener(notifyListeners);
    _offlineCacheRepository.addListener(notifyListeners);
  }

  final CatalogRepository _catalogRepository;
  final HistoryRepository _historyRepository;
  final FavoriteRepository _favoriteRepository;
  final OfflineCacheRepository _offlineCacheRepository;
  final String sourceKey;
  final String vodId;

  VodDetail? detail;
  bool loading = true;
  String? error;
  int lineIndex = 0;

  PlayLine? get currentLine {
    final lines = detail?.lines ?? const [];
    if (lines.isEmpty) return null;
    if (lineIndex < 0 || lineIndex >= lines.length) return lines.first;
    return lines[lineIndex];
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      detail = await _catalogRepository.detail(vodId, sourceKey: sourceKey);
      lineIndex = _preferredLineIndex(detail?.lines ?? const []);
      final record = _historyRepository.find(sourceKey, vodId);
      if (record != null && record.lineName.isNotEmpty) {
        final index = (detail?.lines ?? const [])
            .indexWhere((line) => line.name == record.lineName);
        if (index >= 0) lineIndex = index;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void selectLine(int index) {
    lineIndex = index;
    notifyListeners();
  }

  Duration _startPosition(Episode episode) {
    final record = _historyRepository.find(sourceKey, vodId);
    if (record != null &&
        !record.isFinished &&
        record.episodeId == episode.id) {
      return Duration(milliseconds: record.positionMs);
    }
    return Duration.zero;
  }

  Future<Playable> play(Episode episode) async {
    final start = _startPosition(episode);
    final cached = cacheItemOf(episode);
    if (cached != null) {
      final local = _offlineCacheRepository.localPlayable(
        cached,
        startPosition: start,
      );
      if (local != null) return local;
    }
    final playable = await _catalogRepository.play(
      id: vodId,
      episode: episode,
      lineName: currentLine?.name,
      sourceKey: sourceKey,
    );
    final item = detail?.item;
    return playable.copyWith(
      sourceKey: sourceKey,
      vodId: vodId,
      name: item?.name ?? playable.name,
      pic: item?.pic ?? playable.pic,
      lineName: currentLine?.name ?? '',
      episodeId: episode.id,
      episodeTitle: episode.title,
      title: playable.title.isNotEmpty ? playable.title : episode.title,
      startPosition: start,
    );
  }

  OfflineCacheItem? cacheItemOf(Episode episode) {
    return _offlineCacheRepository.findEpisode(
      sourceKey: sourceKey,
      vodId: vodId,
      lineName: currentLine?.name ?? '',
      episodeId: episode.id,
    );
  }

  List<Episode> get uncachedEpisodes {
    final line = currentLine;
    if (line == null) return const [];
    return [
      for (final episode in line.episodes)
        if (!_offlineCacheRepository.isCompleted(
          sourceKey: sourceKey,
          vodId: vodId,
          lineName: line.name,
          episodeId: episode.id,
        ))
          episode,
    ];
  }

  Future<void> cacheEpisode(Episode episode) {
    final item = detail?.item;
    return _offlineCacheRepository.cacheEpisode(
      sourceKey: sourceKey,
      vodId: vodId,
      name: item?.name ?? '',
      pic: item?.pic ?? '',
      lineName: currentLine?.name ?? '',
      episode: episode,
    );
  }

  Future<int> cacheCurrentLine() {
    final line = currentLine;
    final item = detail?.item;
    if (line == null || item == null) return Future.value(0);
    return _offlineCacheRepository.cacheEpisodes(
      sourceKey: sourceKey,
      vodId: vodId,
      name: item.name,
      pic: item.pic,
      lineName: line.name,
      episodes: uncachedEpisodes,
    );
  }

  Future<void> cancelCache(Episode episode) {
    final item = cacheItemOf(episode);
    if (item == null) return Future.value();
    return _offlineCacheRepository.cancel(item.id);
  }

  Future<void> retryCache(Episode episode) {
    final item = cacheItemOf(episode);
    if (item == null) return cacheEpisode(episode);
    return _offlineCacheRepository.retry(item.id);
  }

  int _preferredLineIndex(List<PlayLine> lines) {
    if (lines.isEmpty) return 0;
    final index = lines.indexWhere(_looksLikeM3u8);
    return index >= 0 ? index : 0;
  }

  bool get isFavorite => _favoriteRepository.isFavorite(sourceKey, vodId);

  Future<bool?> toggleFavorite() async {
    final item = detail?.item;
    if (item == null) return null;
    return _favoriteRepository.toggleFromVod(
      item: item,
      sourceKey: sourceKey,
      vodId: vodId,
    );
  }

  @override
  void dispose() {
    _favoriteRepository.removeListener(notifyListeners);
    _offlineCacheRepository.removeListener(notifyListeners);
    super.dispose();
  }

  bool _looksLikeM3u8(PlayLine line) {
    if (line.name.toLowerCase().contains('m3u8')) return true;
    return line.episodes.any((episode) {
      final url = episode.url?.toLowerCase() ?? '';
      return url.contains('.m3u8');
    });
  }
}
