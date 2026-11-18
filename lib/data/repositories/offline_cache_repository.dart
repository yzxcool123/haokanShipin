import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/media_source.dart';
import '../../domain/models/offline_cache_item.dart';
import '../../domain/models/playable.dart';
import '../services/huangguo_cover_codec.dart';
import '../services/json_http.dart';
import '../services/offline_media_downloader.dart';
import 'catalog_repository.dart';
import 'source_repository.dart';

class OfflineCacheRepository extends ChangeNotifier {
  OfflineCacheRepository({
    required SharedPreferences prefs,
    required SourceRepository sourceRepository,
    required CatalogRepository catalogRepository,
    OfflineMediaDownloader? downloader,
  })  : _prefs = prefs,
        _sourceRepository = sourceRepository,
        _catalogRepository = catalogRepository,
        _downloader = downloader ?? OfflineMediaDownloader() {
    _load();
    _ready = _initRoot();
  }

  final SharedPreferences _prefs;
  final SourceRepository _sourceRepository;
  final CatalogRepository _catalogRepository;
  final OfflineMediaDownloader _downloader;
  final JsonHttp _coverHttp = JsonHttp();

  static const _prefsKey = 'offline_cache_v1';

  late final Future<void> _ready;
  Directory? _root;
  List<OfflineCacheItem> _items = const [];
  final List<String> _queue = [];
  final Map<String, CancelToken> _tokens = {};
  final Map<String, _TransferRate> _rates = {};
  bool _pumping = false;
  DateTime? _lastProgressNotify;

  List<OfflineCacheItem> get items => _items;

  List<OfflineCacheItem> get visibleItems {
    final next = [..._items];
    next.sort((a, b) {
      final active = (b.isActive ? 1 : 0) - (a.isActive ? 1 : 0);
      if (active != 0) return active;
      final failed = (b.isFailed ? 1 : 0) - (a.isFailed ? 1 : 0);
      if (failed != 0) return failed;
      final aTime = a.completedAtMs > 0 ? a.completedAtMs : a.createdAtMs;
      final bTime = b.completedAtMs > 0 ? b.completedAtMs : b.createdAtMs;
      return bTime.compareTo(aTime);
    });
    return next;
  }

  int get completedCount =>
      _items.where((item) => item.isCompleted).length;

  int get activeCount => _items.where((item) => item.isActive).length;

  int get totalBytes =>
      _items.fold<int>(0, (sum, item) => sum + item.bytes);

  OfflineCacheItem? findById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  OfflineCacheItem? findEpisode({
    required String sourceKey,
    required String vodId,
    required String lineName,
    required String episodeId,
  }) {
    return findById(_idOf(sourceKey, vodId, lineName, episodeId));
  }

  static String idOf({
    required String sourceKey,
    required String vodId,
    required String lineName,
    required String episodeId,
  }) {
    return _idOf(sourceKey, vodId, lineName, episodeId);
  }

  bool isCompleted({
    required String sourceKey,
    required String vodId,
    required String lineName,
    required String episodeId,
  }) {
    final item = findEpisode(
      sourceKey: sourceKey,
      vodId: vodId,
      lineName: lineName,
      episodeId: episodeId,
    );
    return item != null && item.isCompleted && localFileExists(item);
  }

  bool localFileExists(OfflineCacheItem item) {
    if (item.localPath.isEmpty) return false;
    return File(item.localPath).existsSync();
  }

  Playable? localPlayable(
    OfflineCacheItem item, {
    Duration startPosition = Duration.zero,
  }) {
    if (!item.isCompleted || !localFileExists(item)) return null;
    return item.toPlayable(startPosition: startPosition);
  }

  Future<void> cachePlayable(Playable playable) {
    if (playable.isLocal) return Future.value();
    if (playable.sourceKey.isEmpty ||
        playable.vodId.isEmpty ||
        playable.episodeId.isEmpty) {
      return Future.error(const OfflineDownloadException('当前影片信息不完整，无法缓存'));
    }
    return _enqueue(
      sourceKey: playable.sourceKey,
      vodId: playable.vodId,
      name: playable.name.isNotEmpty ? playable.name : playable.title,
      pic: playable.pic,
      sourceName: playable.sourceName,
      lineName: playable.lineName,
      episodeId: playable.episodeId,
      episodeTitle: playable.episodeTitle,
      resolved: playable.isLocal ? null : playable,
    );
  }

  Future<void> cacheEpisode({
    required String sourceKey,
    required String vodId,
    required String name,
    String pic = '',
    String sourceName = '',
    required String lineName,
    required Episode episode,
    Playable? resolved,
  }) {
    return _enqueue(
      sourceKey: sourceKey,
      vodId: vodId,
      name: name,
      pic: pic,
      sourceName: sourceName,
      lineName: lineName,
      episodeId: episode.id,
      episodeTitle: episode.title,
      episode: episode,
      resolved: resolved,
    );
  }

  Future<int> cacheEpisodes({
    required String sourceKey,
    required String vodId,
    required String name,
    String pic = '',
    String sourceName = '',
    required String lineName,
    required List<Episode> episodes,
  }) async {
    var added = 0;
    for (final episode in episodes) {
      final existing = findEpisode(
        sourceKey: sourceKey,
        vodId: vodId,
        lineName: lineName,
        episodeId: episode.id,
      );
      if (existing != null &&
          (existing.isCompleted && localFileExists(existing) ||
              existing.isActive)) {
        continue;
      }
      await _enqueue(
        sourceKey: sourceKey,
        vodId: vodId,
        name: name,
        pic: pic,
        sourceName: sourceName,
        lineName: lineName,
        episodeId: episode.id,
        episodeTitle: episode.title,
        episode: episode,
      );
      added += 1;
    }
    return added;
  }

  Future<void> retry(String id) async {
    final item = findById(id);
    if (item == null) return;
    await _enqueue(
      sourceKey: item.sourceKey,
      vodId: item.vodId,
      name: item.name,
      pic: item.pic,
      sourceName: item.sourceName,
      lineName: item.lineName,
      episodeId: item.episodeId,
      episodeTitle: item.episodeTitle,
    );
  }

  Future<void> cancel(String id) async {
    final token = _tokens.remove(id);
    if (token != null && !token.isCancelled) {
      token.cancel('已取消缓存');
    }
    _queue.remove(id);
    _rates.remove(id);
    final item = findById(id);
    if (item != null && !item.isCompleted) {
      await _deleteFiles(item);
      _replace(_items.where((entry) => entry.id != id).toList());
    }
  }

  Future<void> delete(String id) async {
    await cancel(id);
    final item = findById(id);
    if (item == null) return;
    await _deleteFiles(item);
    _replace(_items.where((entry) => entry.id != id).toList());
  }

  Future<void> _enqueue({
    required String sourceKey,
    required String vodId,
    required String name,
    String pic = '',
    String sourceName = '',
    required String lineName,
    required String episodeId,
    String episodeTitle = '',
    Episode? episode,
    Playable? resolved,
  }) async {
    if (sourceKey.isEmpty || vodId.isEmpty || episodeId.isEmpty) {
      throw const OfflineDownloadException('当前影片信息不完整，无法缓存');
    }
    final id = _idOf(sourceKey, vodId, lineName, episodeId);
    final existing = findById(id);
    if (existing != null && existing.isCompleted && localFileExists(existing)) {
      return;
    }
    if (existing != null && existing.isActive) {
      return;
    }

    final item = OfflineCacheItem(
      sourceKey: sourceKey,
      vodId: vodId,
      name: name,
      pic: pic,
      sourceName: _sourceName(sourceKey, sourceName),
      lineName: lineName,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
      localPath: existing?.localPath ?? '',
      coverPath: existing?.coverPath ?? '',
      bytes: 0,
      status: OfflineCacheStatus.queued,
      progress: 0,
      error: '',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _upsert(item, persist: true);
    if (!_queue.contains(id)) {
      _queue.add(id);
    }
    if (resolved != null && !resolved.isLocal) {
      _pendingPlayables[id] = resolved;
    }
    if (episode != null) {
      _pendingEpisodes[id] = episode;
    }
    // 下载在后台排队执行，避免调用方一直等到缓存结束。
    unawaited(_pump());
  }

  final Map<String, Playable> _pendingPlayables = {};
  final Map<String, Episode> _pendingEpisodes = {};

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        final id = _queue.removeAt(0);
        await _downloadOne(id);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _downloadOne(String id) async {
    var item = findById(id);
    if (item == null) return;
    if (item.isCompleted && localFileExists(item)) return;

    final token = CancelToken();
    _tokens[id] = token;
    _upsert(
      item.copyWith(
        status: OfflineCacheStatus.downloading,
        progress: 0,
        bytes: 0,
        totalBytes: 0,
        speedBytesPerSec: 0,
        clearError: true,
      ),
      persist: true,
    );

    Directory? dir;
    try {
      await _ready;
      final root = _root;
      if (root == null) {
        throw const OfflineDownloadException('无法创建本地缓存目录');
      }
      dir = Directory('${root.path}/${_folderName(id)}');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);

      item = findById(id) ?? item;
      final playable = await _resolvePlayable(item);
      if (playable.isLocal) {
        throw const OfflineDownloadException('当前已是本地文件');
      }
      final coverFuture = _cacheCover(item, dir);
      final result = await _downloader.download(
        playable: playable,
        directory: dir,
        cancelToken: token,
        onProgress: (progress) {
          final current = findById(id);
          if (current == null || current.status != OfflineCacheStatus.downloading) {
            return;
          }
          final rate = _rates.putIfAbsent(id, _TransferRate.new);
          _upsert(
            current.copyWith(
              progress: progress.progress.clamp(0.0, 1.0),
              bytes: progress.receivedBytes,
              totalBytes: progress.totalBytes,
              speedBytesPerSec: rate.observe(progress.receivedBytes),
            ),
            persist: false,
            throttle: true,
          );
        },
      );
      String coverPath = item.coverPath;
      try {
        coverPath = await coverFuture;
      } catch (e) {
        debugPrint('cache cover failed: $e');
      }

      final latest = findById(id);
      if (latest == null) {
        await _deleteDirectory(dir);
        return;
      }
      _upsert(
        latest.copyWith(
          localPath: result.localPath,
          coverPath: coverPath.isNotEmpty ? coverPath : latest.coverPath,
          bytes: result.bytes,
          totalBytes: result.bytes,
          speedBytesPerSec: 0,
          status: OfflineCacheStatus.completed,
          progress: 1,
          clearError: true,
          completedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        persist: true,
      );
    } catch (e, st) {
      debugPrint('offline cache failed: $e\n$st');
      if (dir != null) {
        await _deleteDirectory(dir);
      }
      final latest = findById(id);
      if (latest == null) return;
      if (_isCancelled(e)) {
        _replace(_items.where((entry) => entry.id != id).toList());
        return;
      }
      _upsert(
        latest.copyWith(
          status: OfflineCacheStatus.failed,
          progress: 0,
          error: _errorMessage(e),
          localPath: '',
          bytes: 0,
          totalBytes: 0,
          speedBytesPerSec: 0,
        ),
        persist: true,
      );
    } finally {
      _tokens.remove(id);
      _rates.remove(id);
      _pendingPlayables.remove(id);
      _pendingEpisodes.remove(id);
    }
  }

  Future<Playable> _resolvePlayable(OfflineCacheItem item) async {
    final pending = _pendingPlayables.remove(item.id);
    if (pending != null && pending.url.isNotEmpty && !pending.isLocal) {
      return pending.copyWith(
        sourceKey: item.sourceKey,
        vodId: item.vodId,
        name: item.name,
        pic: item.pic,
        sourceName: item.sourceName,
        lineName: item.lineName,
        episodeId: item.episodeId,
        episodeTitle: item.episodeTitle,
      );
    }
    final episode = _pendingEpisodes[item.id] ??
        Episode(id: item.episodeId, title: item.episodeTitle);
    final playable = await _catalogRepository.play(
      id: item.vodId,
      episode: episode,
      lineName: item.lineName,
      sourceKey: item.sourceKey,
    );
    return playable.copyWith(
      sourceKey: item.sourceKey,
      vodId: item.vodId,
      name: item.name,
      pic: item.pic,
      sourceName: item.sourceName,
      lineName: item.lineName,
      episodeId: item.episodeId,
      episodeTitle: item.episodeTitle,
    );
  }

  Future<String> _cacheCover(OfflineCacheItem item, Directory dir) async {
    if (item.coverPath.isNotEmpty && File(item.coverPath).existsSync()) {
      final current = File(item.coverPath);
      final target = File('${dir.path}/cover${_coverExtension(current.path)}');
      if (current.path != target.path) {
        await current.copy(target.path);
        return target.path;
      }
      return current.path;
    }
    if (item.pic.isEmpty) return '';
    try {
      final raw = await _coverHttp.getBytes(
        Uri.parse(item.pic),
        headers: _shouldDecryptCover(item.sourceKey, item.pic)
            ? const {
                'User-Agent': JsonHttp.defaultUa,
                'Referer': 'https://huangguoai.io/',
                'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
              }
            : null,
      );
      final bytes = _decodeCoverBytes(raw);
      if (bytes.isEmpty) return '';
      final file = File('${dir.path}/cover.jpg');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('cache cover failed: $e');
      return '';
    }
  }

  Future<void> _initRoot() async {
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/offline_cache');
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      _root = root;
      await _cleanupInterrupted();
    } catch (e) {
      debugPrint('offline cache dir failed: $e');
    }
  }

  Future<void> _cleanupInterrupted() async {
    final root = _root;
    if (root == null) return;
    for (final item in _items) {
      if (item.isFailed && item.localPath.isEmpty) {
        await _deleteDirectory(
          Directory('${root.path}/${_folderName(item.id)}'),
        );
      }
    }
  }

  void _load() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <OfflineCacheItem>[
        for (final item in decoded)
          if (item is Map)
            OfflineCacheItem.fromJson(Map<String, dynamic>.from(item)),
      ];
      _items = [
        for (final item in loaded)
          if (item.isActive)
            item.copyWith(
              status: OfflineCacheStatus.failed,
              progress: 0,
              error: '下载中断，请重试',
              localPath: '',
              bytes: 0,
              totalBytes: 0,
              speedBytesPerSec: 0,
            )
          else if (item.isCompleted && !localFileExists(item))
            item.copyWith(
              status: OfflineCacheStatus.failed,
              progress: 0,
              error: '本地文件已丢失，请重新缓存',
              localPath: '',
              bytes: 0,
              totalBytes: 0,
              speedBytesPerSec: 0,
            )
          else
            item,
      ];
      final changed = loaded.length != _items.length ||
          [
            for (var i = 0; i < loaded.length && i < _items.length; i++)
              if (loaded[i].status != _items[i].status) i,
          ].isNotEmpty;
      if (changed) {
        _persist();
      }
    } catch (e) {
      debugPrint('offline cache load failed: $e');
    }
  }

  void _upsert(
    OfflineCacheItem item, {
    required bool persist,
    bool throttle = false,
  }) {
    final next = <OfflineCacheItem>[];
    var found = false;
    for (final existing in _items) {
      if (existing.id == item.id) {
        next.add(item);
        found = true;
      } else {
        next.add(existing);
      }
    }
    if (!found) next.insert(0, item);
    _items = next;
    if (throttle) {
      _notifyThrottled();
    } else {
      notifyListeners();
    }
    if (persist) {
      _persist();
    }
  }

  void _replace(List<OfflineCacheItem> items) {
    _items = items;
    notifyListeners();
    _persist();
  }

  void _notifyThrottled() {
    final now = DateTime.now();
    if (_lastProgressNotify != null &&
        now.difference(_lastProgressNotify!) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastProgressNotify = now;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _prefs.setString(
        _prefsKey,
        jsonEncode([for (final item in _items) item.toJson()]),
      );
    } catch (e) {
      debugPrint('offline cache save failed: $e');
    }
  }

  Future<void> _deleteFiles(OfflineCacheItem item) async {
    await _ready;
    final files = <String>{
      if (item.localPath.isNotEmpty) item.localPath,
      if (item.coverPath.isNotEmpty) item.coverPath,
    };
    for (final path in files) {
      final file = File(path);
      final parent = file.parent;
      if (_root != null && parent.path.startsWith(_root!.path)) {
        await _deleteDirectory(parent);
      } else {
        try {
          if (await file.exists()) await file.delete();
        } catch (e) {
          debugPrint('delete cache file failed: $e');
        }
      }
    }
    if (_root != null) {
      await _deleteDirectory(Directory('${_root!.path}/${_folderName(item.id)}'));
    }
  }

  Future<void> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('delete cache dir failed: $e');
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

  bool _isCancelled(Object error) {
    if (error is OfflineDownloadException && error.message.contains('取消')) {
      return true;
    }
    if (error is DioException && error.type == DioExceptionType.cancel) {
      return true;
    }
    return '$error'.contains('已取消缓存') || '$error'.contains('cancelled');
  }

  String _errorMessage(Object error) {
    if (error is OfflineDownloadException) return error.message;
    if (error is DioException && error.type == DioExceptionType.cancel) {
      return '已取消缓存';
    }
    final text = error.toString();
    if (text.contains('还没有可用的数据源')) return '还没有可用的数据源';
    if (text.contains('超时')) return '下载超时，请稍后重试';
    return '缓存失败，请稍后重试';
  }


  bool _shouldDecryptCover(String sourceKey, String url) {
    if (sourceKey == 'huangguo_web') return true;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.endsWith('drleao.cn');
  }

  Uint8List _decodeCoverBytes(Uint8List bytes) {
    if (HuangguoCoverCodec.isImage(bytes)) return bytes;
    final plain = HuangguoCoverCodec.decrypt(bytes);
    if (plain != null && HuangguoCoverCodec.isImage(plain)) return plain;
    return bytes;
  }

  String _coverExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    if (lower.endsWith('.gif')) return '.gif';
    return '.jpg';
  }

  static String _idOf(
    String sourceKey,
    String vodId,
    String lineName,
    String episodeId,
  ) {
    return '$sourceKey|$vodId|$lineName|$episodeId';
  }

  static String _folderName(String id) {
    return sha1.convert(utf8.encode(id)).toString();
  }

  static T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  @override
  void dispose() {
    for (final token in _tokens.values) {
      if (!token.isCancelled) {
        token.cancel('已取消缓存');
      }
    }
    _tokens.clear();
    _rates.clear();
    super.dispose();
  }
}

class _TransferRate {
  int _lastBytes = 0;
  DateTime? _lastAt;
  double _bytesPerSec = 0;

  int observe(int bytes) {
    final now = DateTime.now();
    final previousAt = _lastAt;
    if (previousAt == null) {
      _lastBytes = bytes;
      _lastAt = now;
      return 0;
    }
    final elapsedMs = now.difference(previousAt).inMilliseconds;
    if (elapsedMs >= 300) {
      final delta = bytes - _lastBytes;
      if (delta >= 0) {
        final inst = delta * 1000 / elapsedMs;
        _bytesPerSec = _bytesPerSec <= 0 ? inst : (_bytesPerSec * 0.6 + inst * 0.4);
      }
      _lastBytes = bytes;
      _lastAt = now;
    }
    return _bytesPerSec.round();
  }
}
