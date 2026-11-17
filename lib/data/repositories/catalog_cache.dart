import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/category.dart';
import '../../domain/models/paged.dart';

/// 只缓存每个源、每个分类的第一页列表和分类栏，用于冷启动和切源时先出旧数据。
class CatalogCache {
  CatalogCache(this._prefs);

  final SharedPreferences _prefs;

  static const _indexKey = 'catalog_page1_index';
  static const _maxEntries = 48;

  final Map<String, List<VodCategory>> _categories = {};
  final Map<String, PagedVod> _pages = {};

  String _pageKey(String sourceKey, String? categoryId) {
    return 'c1_${Uri.encodeComponent(sourceKey)}_${Uri.encodeComponent(categoryId ?? '')}';
  }

  String _catsKey(String sourceKey) => 'cc_${Uri.encodeComponent(sourceKey)}';

  List<VodCategory>? categories(String sourceKey) {
    final key = _catsKey(sourceKey);
    final memory = _categories[key];
    if (memory != null) return memory;
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final list = [
        for (final item in decoded)
          if (item is Map)
            VodCategory.fromJson(Map<String, dynamic>.from(item)),
      ];
      _categories[key] = list;
      return list;
    } catch (_) {
      return null;
    }
  }

  PagedVod? firstPage(String sourceKey, String? categoryId) {
    final key = _pageKey(sourceKey, categoryId);
    final memory = _pages[key];
    if (memory != null) return memory;
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final page = PagedVod.fromJson(Map<String, dynamic>.from(decoded));
      _pages[key] = page;
      return page;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCategories(String sourceKey, List<VodCategory> categories) {
    final key = _catsKey(sourceKey);
    final copy = List<VodCategory>.unmodifiable(categories);
    _categories[key] = copy;
    return _write(
      key,
      jsonEncode([for (final item in copy) item.toJson()]),
    );
  }

  Future<void> saveFirstPage({
    required String sourceKey,
    String? categoryId,
    required PagedVod page,
  }) {
    final key = _pageKey(sourceKey, categoryId);
    _pages[key] = page;
    return _write(key, jsonEncode(page.toJson()));
  }

  Future<void> _write(String key, String raw) async {
    await _prefs.setString(key, raw);
    final index = [...?_prefs.getStringList(_indexKey)];
    index.remove(key);
    index.add(key);
    while (index.length > _maxEntries) {
      final evict = index.removeAt(0);
      _pages.remove(evict);
      _categories.remove(evict);
      await _prefs.remove(evict);
    }
    await _prefs.setStringList(_indexKey, index);
  }
}
