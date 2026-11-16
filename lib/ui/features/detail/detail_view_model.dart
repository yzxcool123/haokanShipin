import 'package:flutter/foundation.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../domain/models/playable.dart';
import '../../../domain/models/vod_detail.dart';

class DetailViewModel extends ChangeNotifier {
  DetailViewModel({
    required CatalogRepository catalogRepository,
    required this.sourceKey,
    required this.vodId,
  }) : _catalogRepository = catalogRepository;

  final CatalogRepository _catalogRepository;
  final String sourceKey;
  final String vodId;

  VodDetail? detail;
  bool loading = false;
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

  Future<Playable> play(Episode episode) {
    return _catalogRepository.play(
      id: vodId,
      episode: episode,
      lineName: currentLine?.name,
      sourceKey: sourceKey,
    );
  }
}
