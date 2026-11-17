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

  List<VodCategory> categories = const [];
  List<VodItem> items = const [];
  String? selectedCategoryId;
  bool loading = false;
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
    if (reset) {
      loading = true;
      error = null;
      items = const [];
      page = 1;
      notifyListeners();
    }
    try {
      if (reset) {
        try {
          categories = await _catalogRepository.categories();
        } catch (_) {
          categories = const [];
        }
      }
      final result = await _catalogRepository.list(
        page: 1,
        categoryId: selectedCategoryId,
      );
      items = result.list;
      page = result.page;
      pageCount = result.pageCount;
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectCategory(String? id) async {
    selectedCategoryId = id;
    await load();
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || page >= pageCount) return;
    loadingMore = true;
    notifyListeners();
    try {
      final next = page + 1;
      final result = await _catalogRepository.list(
        page: next,
        categoryId: selectedCategoryId,
      );
      items = [...items, ...result.list];
      page = result.page;
      pageCount = result.pageCount;
    } catch (e) {
      error = e.toString();
    } finally {
      loadingMore = false;
      notifyListeners();
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
