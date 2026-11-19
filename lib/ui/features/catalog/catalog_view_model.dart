import 'package:flutter/foundation.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../domain/models/category.dart';
import '../../../domain/models/media_source.dart';
import '../../../domain/models/vod_item.dart';

class CatalogViewModel extends ChangeNotifier {
  CatalogViewModel({
    required CatalogRepository catalogRepository,
    required SourceRepository sourceRepository,
  })  : _catalogRepository = catalogRepository,
        _sourceRepository = sourceRepository {
    _sourceFingerprint = _fingerprint(_sourceRepository.current);
    _sourceRepository.addListener(_onSourceChanged);
    _restoreSelectedCategory();
  }

  final CatalogRepository _catalogRepository;
  final SourceRepository _sourceRepository;
  String? _sourceFingerprint;
  int _loadGeneration = 0;
  bool _disposed = false;

  List<VodCategory> categories = const [];
  List<VodItem> items = const [];
  String? selectedCategoryId;
  bool loading = false;
  bool refreshing = false;
  bool loadingMore = false;
  String? error;
  int page = 1;
  int pageCount = 1;

  MediaSource? get source => _sourceRepository.current;

  String get sourceDisplayName {
    final current = source;
    if (current == null) return '未选择源';
    return _sourceRepository.displayNameOf(current);
  }

  bool get isCurrentUnavailable {
    final current = source;
    if (current == null) return false;
    return _sourceRepository.availabilityOf(current.key) ==
        SourceAvailability.unavailable;
  }

  Future<void> load({bool reset = true}) async {
    final generation = ++_loadGeneration;
    final sourceKey = source?.key;
    var categoryId = selectedCategoryId;

    if (reset) {
      error = null;
      page = 1;
      var shownCache = false;
      if (sourceKey != null) {
        final cachedCats = _catalogRepository.cachedCategories(sourceKey);
        if (cachedCats != null && cachedCats.isNotEmpty) {
          categories = cachedCats;
          if (_dropInvalidCategory()) {
            categoryId = selectedCategoryId;
          }
        }
        final cachedPage = _catalogRepository.cachedFirstPage(
          sourceKey: sourceKey,
          categoryId: categoryId,
        );
        if (cachedPage != null && cachedPage.list.isNotEmpty) {
          items = cachedPage.list;
          page = cachedPage.page;
          pageCount = cachedPage.pageCount;
          shownCache = true;
        } else {
          items = const [];
        }
      } else {
        items = const [];
      }
      loading = !shownCache;
      refreshing = true;
      _notify();
    }

    try {
      if (reset) {
        try {
          final cats = await _catalogRepository.categories();
          if (_isStale(generation)) return;
          categories = cats;
          if (sourceKey != null && cats.isNotEmpty) {
            await _catalogRepository.saveCategories(sourceKey, cats);
          }
          if (_dropInvalidCategory()) {
            categoryId = selectedCategoryId;
          }
        } catch (_) {
          if (_isStale(generation)) return;
          if (categories.isEmpty) categories = const [];
        }
      }
      final result = await _catalogRepository.list(
        page: 1,
        categoryId: categoryId,
      );
      if (_isStale(generation)) return;
      items = result.list;
      page = result.page;
      pageCount = result.pageCount;
      error = null;
      if (sourceKey != null) {
        await _catalogRepository.saveFirstPage(
          sourceKey: sourceKey,
          categoryId: categoryId,
          page: result,
        );
      }
    } catch (e) {
      if (_isStale(generation)) return;
      if (items.isEmpty) {
        error = e.toString();
      }
    }
    if (_isStale(generation)) return;
    loading = false;
    refreshing = false;
    _notify();
  }

  Future<void> selectCategory(String? id) async {
    selectedCategoryId = id;
    final sourceKey = source?.key;
    if (sourceKey != null) {
      await _catalogRepository.saveSelectedCategoryId(sourceKey, id);
    }
    await load();
  }

  Future<void> loadMore() async {
    if (loading ||
        refreshing ||
        loadingMore ||
        page >= pageCount ||
        _disposed) {
      return;
    }
    loadingMore = true;
    _notify();
    final generation = _loadGeneration;
    try {
      final next = page + 1;
      final result = await _catalogRepository.list(
        page: next,
        categoryId: selectedCategoryId,
      );
      if (_isStale(generation)) return;
      items = [...items, ...result.list];
      page = result.page;
      pageCount = result.pageCount;
    } catch (e) {
      if (_isStale(generation)) return;
      error = e.toString();
    }
    if (_isStale(generation)) return;
    loadingMore = false;
    _notify();
  }

  void _onSourceChanged() {
    if (_disposed) return;
    final fingerprint = _fingerprint(_sourceRepository.current);
    if (fingerprint == _sourceFingerprint) {
      // 可用性更新只刷新标题，不重新拉首页列表。
      _notify();
      return;
    }
    _sourceFingerprint = fingerprint;
    _restoreSelectedCategory();
    load();
  }

  void _restoreSelectedCategory() {
    final sourceKey = source?.key;
    if (sourceKey == null) {
      selectedCategoryId = null;
      return;
    }
    selectedCategoryId = _catalogRepository.selectedCategoryId(sourceKey);
  }

  /// 若记住的分类在当前源中已不存在，则回到「推荐」。
  bool _dropInvalidCategory() {
    final id = selectedCategoryId;
    if (id == null || categories.isEmpty) return false;
    if (categories.any((item) => item.id == id)) return false;
    selectedCategoryId = null;
    final sourceKey = source?.key;
    if (sourceKey != null) {
      _catalogRepository.saveSelectedCategoryId(sourceKey, null);
    }
    return true;
  }

  String _fingerprint(MediaSource? source) {
    if (source == null) return '';
    return '${source.key}|${source.api}|${source.type}';
  }

  bool _isStale(int generation) => _disposed || generation != _loadGeneration;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _sourceRepository.removeListener(_onSourceChanged);
    super.dispose();
  }
}
