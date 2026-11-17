import 'package:flutter/foundation.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../domain/models/playable.dart';
import '../../../domain/models/vod_detail.dart';

class DetailViewModel extends ChangeNotifier {
  DetailViewModel({
    required CatalogRepository catalogRepository,
    required HistoryRepository historyRepository,
    required this.sourceKey,
    required this.vodId,
  })  : _catalogRepository = catalogRepository,
        _historyRepository = historyRepository;

  final CatalogRepository _catalogRepository;
  final HistoryRepository _historyRepository;
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

  Future<Playable> play(Episode episode) async {
    final playable = await _catalogRepository.play(
      id: vodId,
      episode: episode,
      lineName: currentLine?.name,
      sourceKey: sourceKey,
    );
    final record = _historyRepository.find(sourceKey, vodId);
    var start = Duration.zero;
    if (record != null &&
        !record.isFinished &&
        record.episodeId == episode.id) {
      start = Duration(milliseconds: record.positionMs);
    }
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

  int _preferredLineIndex(List<PlayLine> lines) {
    if (lines.isEmpty) return 0;
    final index = lines.indexWhere(_looksLikeM3u8);
    return index >= 0 ? index : 0;
  }

  bool _looksLikeM3u8(PlayLine line) {
    if (line.name.toLowerCase().contains('m3u8')) return true;
    return line.episodes.any((episode) {
      final url = episode.url?.toLowerCase() ?? '';
      return url.contains('.m3u8');
    });
  }
}
