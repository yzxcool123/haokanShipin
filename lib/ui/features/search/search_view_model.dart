import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../domain/models/vod_item.dart';

class SearchViewModel extends ChangeNotifier {
  SearchViewModel({required CatalogRepository catalogRepository})
      : _catalogRepository = catalogRepository;

  final CatalogRepository _catalogRepository;
  Timer? _debounce;

  String keyword = '';
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
      final result = await _catalogRepository.list(page: page + 1, keyword: keyword);
      items = [...items, ...result.list];
      page = result.page;
      pageCount = result.pageCount;
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
