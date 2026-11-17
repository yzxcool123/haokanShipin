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
  }

  final CatalogRepository _catalogRepository;
  final SourceRepository _sourceRepository;
  String? _sourceFingerprint;
  int _loadGeneration = 0;

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
    final categoryId = selectedCategoryId;

    if (reset) {
      error = null;
      page = 1;
      var shownCache = false;
      if (sourceKey != null) {
        final cachedCats = _catalogRepository.cachedCategories(sourceKey);
        if (cachedCats != null && cachedCats.isNotEmpty) {
          categories = cachedCats;
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
      notifyListeners();
    }

    try {
      if (reset) {
        try {
          final cats = await _catalogRepository.categories();
          if (generation != _loadGeneration) return;
          categories = cats;
          if (sourceKey != null && cats.isNotEmpty) {
            await _catalogRepository.saveCategories(sourceKey, cats);
          }
        } catch (_) {
          if (generation != _loadGeneration) return;
          if (categories.isEmpty) categories = const [];
        }
      }
      final result = await _catalogRepository.list(
        page: 1,
        categoryId: categoryId,
      );
      if (generation != _loadGeneration) return;
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
      if (generation != _loadGeneration) return;
      if (items.isEmpty) {
        error = e.toString();
      }
    } finally {
      if (generation == _loadGeneration) {
        loading = false;
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectCategory(String? id) async {
    selectedCategoryId = id;
    await load();
  }

  Future<void> loadMore() async {
    if (loading || refreshing || loadingMore || page >= pageCount) return;
    loadingMore = true;
    notifyListeners();
    final generation = _loadGeneration;
    try {
      final next = page + 1;
      final result = await _catalogRepository.list(
        page: next,
        categoryId: selectedCategoryId,
      );
      if (generation != _loadGeneration) return;
      items = [...items, ...result.list];
      page = result.page;
      pageCount = result.pageCount;
    } catch (e) {
      if (generation != _loadGeneration) return;
      error = e.toString();
    } finally {
      if (generation == _loadGeneration) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  void _onSourceChanged() {
    final fingerprint = _fingerprint(_sourceRepository.current);
    if (fingerprint == _sourceFingerprint) {
      // 可用性更新只刷新标题，不重新拉首页列表。
      notifyListeners();
      return;
    }
    _sourceFingerprint = fingerprint;
    selectedCategoryId = null;
    load();
  }

  String _fingerprint(MediaSource? source) {
    if (source == null) return '';
    return '${source.key}|${source.api}|${source.type}';
  }

  @override
  void dispose() {
    _sourceRepository.removeListener(_onSourceChanged);
    super.dispose();
  }
}
