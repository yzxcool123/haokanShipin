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
      notifyListeners();
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
    await search();
  }

  Future<void> search() async {
    if (keyword.isEmpty) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await _catalogRepository.list(page: 1, keyword: keyword);
      items = result.list;
      page = result.page;
      pageCount = result.pageCount;
    } catch (e) {
      error = e.toString();
      items = const [];
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loading || keyword.isEmpty || page >= pageCount) return;
    try {
      final result =
          await _catalogRepository.list(page: page + 1, keyword: keyword);
      items = [...items, ...result.list];
      page = result.page;
      pageCount = result.pageCount;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    history = const [];
    notifyListeners();
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
    notifyListeners();
    try {
      await _prefs.setString(_historyKey, jsonEncode(history));
    } catch (e) {
      debugPrint('search history save failed: $e');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
