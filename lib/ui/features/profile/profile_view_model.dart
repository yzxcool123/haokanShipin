import 'package:flutter/foundation.dart';

import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../domain/models/watch_record.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required HistoryRepository historyRepository,
    required SourceRepository sourceRepository,
  })  : _historyRepository = historyRepository,
        _sourceRepository = sourceRepository {
    _historyRepository.addListener(notifyListeners);
    _sourceRepository.addListener(notifyListeners);
  }

  final HistoryRepository _historyRepository;
  final SourceRepository _sourceRepository;

  static const previewCount = 6;

  HistoryRepository get history => _historyRepository;

  List<WatchRecord> get continueWatching =>
      _historyRepository.continueWatching;

  List<WatchRecord> get allRecords => _historyRepository.records;

  List<WatchRecord> get recentPreview {
    final all = allRecords;
    if (all.length <= previewCount) return all;
    return all.sublist(0, previewCount);
  }

  bool get hasMoreHistory => allRecords.length > previewCount;

  int get historyCount => allRecords.length;

  int get continueCount => continueWatching.length;

  int get finishedCount =>
      allRecords.where((record) => record.isFinished).length;

  String get currentSourceName {
    final current = _sourceRepository.current;
    if (current == null) return '未选择';
    return _sourceRepository.displayNameOf(current);
  }

  Future<void> remove(WatchRecord record) => _historyRepository.remove(record);

  @override
  void dispose() {
    _historyRepository.removeListener(notifyListeners);
    _sourceRepository.removeListener(notifyListeners);
    super.dispose();
  }
}
