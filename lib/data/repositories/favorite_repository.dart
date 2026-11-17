import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/favorite_item.dart';
import '../../domain/models/media_source.dart';
import '../../domain/models/vod_item.dart';
import 'source_repository.dart';

class FavoriteRepository extends ChangeNotifier {
  FavoriteRepository({
    required SharedPreferences prefs,
    required SourceRepository sourceRepository,
  })  : _prefs = prefs,
        _sourceRepository = sourceRepository {
    _load();
  }

  final SharedPreferences _prefs;
  final SourceRepository _sourceRepository;

  static const _prefsKey = 'favorites_v1';
  static const _maxEntries = 200;

  List<FavoriteItem> _items = const [];

  List<FavoriteItem> get items => _items;

  int get count => _items.length;

  bool isFavorite(String sourceKey, String vodId) {
    for (final item in _items) {
      if (item.sourceKey == sourceKey && item.vodId == vodId) return true;
    }
    return false;
  }

  Future<bool> toggleFromVod({
    required VodItem item,
    required String sourceKey,
    required String vodId,
  }) {
    if (isFavorite(sourceKey, vodId)) {
      return removeKey(sourceKey, vodId).then((_) => false);
    }
    return add(FavoriteItem(
      sourceKey: sourceKey,
      vodId: vodId,
      name: item.name,
      pic: item.pic,
      sourceName: _sourceName(sourceKey),
      remarks: item.remarks.isNotEmpty ? item.remarks : item.typeName,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    )).then((_) => true);
  }

  Future<void> add(FavoriteItem item) {
    if (item.sourceKey.isEmpty || item.vodId.isEmpty) {
      return Future.value();
    }
    final next = [
      item,
      for (final existing in _items) if (existing.key != item.key) existing,
    ];
    _items = next.length > _maxEntries ? next.sublist(0, _maxEntries) : next;
    notifyListeners();
    return _persist();
  }

  Future<void> remove(FavoriteItem item) => removeKey(item.sourceKey, item.vodId);

  Future<void> removeKey(String sourceKey, String vodId) {
    _items = [
      for (final item in _items)
        if (item.sourceKey != sourceKey || item.vodId != vodId) item,
    ];
    notifyListeners();
    return _persist();
  }

  void _load() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _items = [
        for (final item in decoded)
          if (item is Map)
            FavoriteItem.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (e) {
      debugPrint('favorites load failed: $e');
    }
  }

  Future<void> _persist() async {
    try {
      await _prefs.setString(
        _prefsKey,
        jsonEncode([for (final item in _items) item.toJson()]),
      );
    } catch (e) {
      debugPrint('favorites save failed: $e');
    }
  }

  String _sourceName(String sourceKey) {
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
