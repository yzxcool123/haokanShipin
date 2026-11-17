import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/category.dart';
import '../../domain/models/media_source.dart';
import '../../domain/models/paged.dart';
import '../../domain/models/playable.dart';
import '../../domain/models/vod_detail.dart';
import '../services/client_factory.dart';
import '../services/vod_client.dart';
import 'catalog_cache.dart';
import 'source_repository.dart';

class CatalogRepository {
  CatalogRepository({
    required SourceRepository sourceRepository,
    required SharedPreferences prefs,
  })  : _sourceRepository = sourceRepository,
        _cache = CatalogCache(prefs);

  final SourceRepository _sourceRepository;
  final CatalogCache _cache;
  VodClient? _client;
  String? _clientKey;

  MediaSource get requireSource {
    final source = _sourceRepository.current;
    if (source == null) {
      throw StateError('还没有可用的数据源。');
    }
    return source;
  }

  VodClient _clientOf(MediaSource source) {
    if (_client != null && _clientKey == source.key) {
      return _client!;
    }
    _client = createVodClient(source);
    _clientKey = source.key;
    return _client!;
  }

  Future<List<VodCategory>> categories() {
    return _clientOf(requireSource).categories();
  }

  Future<PagedVod> list({
    int page = 1,
    String? categoryId,
    String? keyword,
  }) {
    return _clientOf(requireSource).list(
      page: page,
      categoryId: categoryId,
      keyword: keyword,
    );
  }

  Future<VodDetail> detail(String id, {String? sourceKey}) {
    final source = _sourceByKey(sourceKey);
    return _clientOf(source).detail(id);
  }

  Future<Playable> play({
    required String id,
    required Episode episode,
    String? lineName,
    String? sourceKey,
  }) {
    final source = _sourceByKey(sourceKey);
    return _clientOf(source).play(id: id, episode: episode, lineName: lineName);
  }

  List<VodCategory>? cachedCategories(String sourceKey) {
    return _cache.categories(sourceKey);
  }

  PagedVod? cachedFirstPage({required String sourceKey, String? categoryId}) {
    return _cache.firstPage(sourceKey, categoryId);
  }

  Future<void> saveCategories(String sourceKey, List<VodCategory> categories) {
    return _cache.saveCategories(sourceKey, categories);
  }

  Future<void> saveFirstPage({
    required String sourceKey,
    String? categoryId,
    required PagedVod page,
  }) {
    return _cache.saveFirstPage(
      sourceKey: sourceKey,
      categoryId: categoryId,
      page: page,
    );
  }

  MediaSource _sourceByKey(String? sourceKey) {
    if (sourceKey == null || sourceKey.isEmpty) return requireSource;
    return _sourceRepository.sources.firstWhere(
      (item) => item.key == sourceKey,
      orElse: () => requireSource,
    );
  }
}
