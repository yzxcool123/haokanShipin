import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../domain/models/vod_item.dart';

class SearchViewModel extends ChangeNotifier {
  SearchViewModel({
    required CatalogRepository catalogRepository,
    required SharedPreferences prefs,
  })  : _catalogRepository = catalogRepository,
        _prefs = prefs {
    _loadHistory();
  }

  final CatalogRepository _catalogRepository;
  final SharedPreferences _prefs;
  Timer? _debounce;
  bool _disposed = false;

  static const _historyKey = 'search_history_v1';
  static const _maxHistory = 20;

  String keyword = '';
  List<String> history = const [];
  List<VodItem> items = const [];
  bool loading = false;
  String? error;
  int page = 1;
  int pageCount = 1;

  void onQueryChanged(String value) {
    keyword = value.trim();
    _debounce?.cancel();
    if (keyword.isEmpty) {
      items = const [];
      error = null;
      _notify();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), search);
  }

  Future<void> submit([String? value]) async {
    final next = (value ?? keyword).trim();
    if (next.isEmpty) return;
    _debounce?.cancel();
    keyword = next;
    await _remember(next);
    if (_disposed) return;
    await search();
  }

  Future<void> search() async {
    if (keyword.isEmpty || _disposed) return;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await _catalogRepository.list(page: 1, keyword: keyword);
      if (_disposed) return;
      items = result.list;
      page = result.page;
      pageCount = result.pageCount;
    } catch (e) {
      if (_disposed) return;
      error = e.toString();
      items = const [];
    }
    if (_disposed) return;
    loading = false;
    _notify();
  }

  Future<void> loadMore() async {
    if (loading || keyword.isEmpty || page >= pageCount || _disposed) return;
    try {
      final result =
          await _catalogRepository.list(page: page + 1, keyword: keyword);
      if (_disposed) return;
      items = [...items, ...result.list];
      page = result.page;
      pageCount = result.pageCount;
      _notify();
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    history = const [];
    _notify();
    await _prefs.remove(_historyKey);
  }

  void _loadHistory() {
    final raw = _prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      history = [
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    } catch (e) {
      debugPrint('search history load failed: $e');
    }
  }

  Future<void> _remember(String value) async {
    final next = [
      value,
      for (final item in history)
        if (item.toLowerCase() != value.toLowerCase()) item,
    ];
    history = next.length > _maxHistory ? next.sublist(0, _maxHistory) : next;
    _notify();
    try {
      await _prefs.setString(_historyKey, jsonEncode(history));
    } catch (e) {
      debugPrint('search history save failed: $e');
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
