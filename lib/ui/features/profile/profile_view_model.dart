import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../data/repositories/favorite_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../domain/models/watch_record.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required HistoryRepository historyRepository,
    required FavoriteRepository favoriteRepository,
    required SourceRepository sourceRepository,
  })  : _historyRepository = historyRepository,
        _favoriteRepository = favoriteRepository,
        _sourceRepository = sourceRepository {
    _historyRepository.addListener(notifyListeners);
    _favoriteRepository.addListener(notifyListeners);
    _sourceRepository.addListener(notifyListeners);
    _loadVersion();
  }

  final HistoryRepository _historyRepository;
  final FavoriteRepository _favoriteRepository;
  final SourceRepository _sourceRepository;

  HistoryRepository get history => _historyRepository;

  List<WatchRecord> get continueWatching =>
      _historyRepository.continueWatching;

  int get historyCount => _historyRepository.records.length;

  int get favoriteCount => _favoriteRepository.count;

  String versionLabel = '';

  String get currentSourceName {
    final current = _sourceRepository.current;
    if (current == null) return '未选择';
    return _sourceRepository.displayNameOf(current);
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      versionLabel = info.version;
      notifyListeners();
    } catch (e) {
      debugPrint('load version failed: $e');
    }
  }

  @override
  void dispose() {
    _historyRepository.removeListener(notifyListeners);
    _favoriteRepository.removeListener(notifyListeners);
    _sourceRepository.removeListener(notifyListeners);
    super.dispose();
  }
}
