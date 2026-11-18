import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../data/repositories/favorite_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/offline_cache_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../domain/models/watch_record.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required HistoryRepository historyRepository,
    required FavoriteRepository favoriteRepository,
    required OfflineCacheRepository offlineCacheRepository,
    required SourceRepository sourceRepository,
  })  : _historyRepository = historyRepository,
        _favoriteRepository = favoriteRepository,
        _offlineCacheRepository = offlineCacheRepository,
        _sourceRepository = sourceRepository {
    _historyRepository.addListener(notifyListeners);
    _favoriteRepository.addListener(notifyListeners);
    _offlineCacheRepository.addListener(notifyListeners);
    _sourceRepository.addListener(notifyListeners);
    _loadVersion();
  }

  final HistoryRepository _historyRepository;
  final FavoriteRepository _favoriteRepository;
  final OfflineCacheRepository _offlineCacheRepository;
  final SourceRepository _sourceRepository;

  HistoryRepository get history => _historyRepository;

  static const _continueWatchingLimit = 5;

  List<WatchRecord> get continueWatching =>
      _historyRepository.continueWatching.take(_continueWatchingLimit).toList();

  int get historyCount => _historyRepository.records.length;

  int get favoriteCount => _favoriteRepository.count;

  int get downloadCount => _offlineCacheRepository.completedCount;

  int get downloadingCount => _offlineCacheRepository.activeCount;

  String get downloadSubtitle {
    final completed = downloadCount;
    final active = downloadingCount;
    if (completed == 0 && active == 0) return '暂无缓存';
    if (completed == 0) return '下载中';
    if (active > 0) return '$completed 集 · 下载中';
    return '$completed 集';
  }

  String versionLabel = '';

  String get currentSourceName {
    final current = _sourceRepository.current;
    if (current == null) return '未选择';
    return _sourceRepository.displayNameOf(current);
  }

  String get contentModeLabel =>
      _sourceRepository.contentMode == ContentMode.healthy ? '健康模式' : '成人模式';

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
    _offlineCacheRepository.removeListener(notifyListeners);
    _sourceRepository.removeListener(notifyListeners);
    super.dispose();
  }
}
