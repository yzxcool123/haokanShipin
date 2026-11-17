import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/media_source.dart';
import '../../domain/models/playable.dart';
import '../../domain/models/watch_record.dart';
import 'source_repository.dart';

class HistoryRepository extends ChangeNotifier {
  HistoryRepository({
    required SharedPreferences prefs,
    required SourceRepository sourceRepository,
  })  : _prefs = prefs,
        _sourceRepository = sourceRepository {
    _load();
  }

  final SharedPreferences _prefs;
  final SourceRepository _sourceRepository;

  static const _prefsKey = 'watch_history_v1';
  static const _maxEntries = 200;

  List<WatchRecord> _records = const [];

  List<WatchRecord> get records => _records;

  List<WatchRecord> get continueWatching =>
      [for (final item in _records) if (item.isInProgress) item];

  WatchRecord? find(String sourceKey, String vodId) {
    for (final item in _records) {
      if (item.sourceKey == sourceKey && item.vodId == vodId) return item;
    }
    return null;
  }

  Future<void> savePlayable(
    Playable playable, {
    required Duration position,
    required Duration duration,
  }) {
    if (!playable.canTrackHistory) return Future.value();
    final record = WatchRecord(
      sourceKey: playable.sourceKey,
      vodId: playable.vodId,
      name: playable.name.isNotEmpty ? playable.name : playable.title,
      pic: playable.pic,
      sourceName: _sourceName(playable.sourceKey, playable.sourceName),
      lineName: playable.lineName,
      episodeId: playable.episodeId,
      episodeTitle: playable.episodeTitle,
      positionMs: position.inMilliseconds.clamp(0, 1 << 31),
      durationMs: duration.inMilliseconds.clamp(0, 1 << 31),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    return upsert(record);
  }

  Future<void> upsert(WatchRecord record) {
    if (record.sourceKey.isEmpty || record.vodId.isEmpty) {
      return Future.value();
    }
    final next = [
      record,
      for (final item in _records) if (item.key != record.key) item,
    ];
    if (next.length > _maxEntries) {
      _records = next.sublist(0, _maxEntries);
    } else {
      _records = next;
    }
    notifyListeners();
    return _persist();
  }

  Future<void> remove(WatchRecord record) {
    _records = [
      for (final item in _records) if (item.key != record.key) item,
    ];
    notifyListeners();
    return _persist();
  }

  Future<void> clear() {
    _records = const [];
    notifyListeners();
    return _persist();
  }

  void _load() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _records = [
        for (final item in decoded)
          if (item is Map)
            WatchRecord.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (e) {
      debugPrint('history load failed: $e');
    }
  }

  Future<void> _persist() async {
    try {
      await _prefs.setString(
        _prefsKey,
        jsonEncode([for (final item in _records) item.toJson()]),
      );
    } catch (e) {
      debugPrint('history save failed: $e');
    }
  }

  String _sourceName(String sourceKey, String fallback) {
    if (fallback.isNotEmpty) return fallback;
    final match = _firstWhereOrNull(
      _sourceRepository.sources,
      (MediaSource item) => item.key == sourceKey,
    );
    if (match == null) return '';
    return _sourceRepository.displayNameOf(match);
  }

  static T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}
