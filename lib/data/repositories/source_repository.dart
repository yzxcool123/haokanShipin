import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/media_source.dart';
import '../services/client_factory.dart';
import '../services/json_http.dart';

enum SourceAvailability { unknown, checking, available, unavailable }

enum ContentMode { healthy, adult }

/// 可切换的远程源列表。默认「推荐」沿用原来的地址和缓存，其它列表按需加载。
class SourceListCatalog {
  const SourceListCatalog({
    required this.id,
    required this.name,
    required this.url,
    this.pinHuangguo = false,
    this.useBundledFallback = false,
    this.cmsOnly = false,
  });

  final String id;
  final String name;
  final String url;
  final bool pinHuangguo;
  final bool useBundledFallback;
  /// 只保留苹果 CMS（type 1）且带 http(s) 接口的源，用于 TVBox 完整配置。
  final bool cmsOnly;
}

class SourceRepository extends ChangeNotifier {
  SourceRepository({
    required SharedPreferences prefs,
    required AssetBundle bundle,
    JsonHttp? http,
  })  : _prefs = prefs,
        _bundle = bundle,
        _http = http ?? JsonHttp();

  static const bundledAsset = 'assets/sources.json';
  static const defaultListId = 'default';
  static const remoteConfigUrl =
      'https://cdn.jsdelivr.net/gh/SikROo/huangguo-spider@v10.4/all_sources_config.json';
  static const sourceLists = [
    SourceListCatalog(
      id: defaultListId,
      name: '推荐',
      url: remoteConfigUrl,
      pinHuangguo: true,
      useBundledFallback: true,
    ),
    SourceListCatalog(
      id: 'niubihu',
      name: '牛虎',
      url:
          'https://gh-proxy.com/https://raw.githubusercontent.com/niubihu1/tvbox/main/1.json',
      cmsOnly: true,
    ),
  ];
  static const _selectedKey = 'selected_source_key';
  static const _selectedListKey = 'selected_source_list_id_v1';
  static const _customKey = 'custom_sources_json';
  static const _remoteCacheKey = 'remote_sources_json';
  static const _contentModeKey = 'content_mode_v1';
  static const _latencyKey = 'source_latency_ms_v1';
  static const _probeTimeout = Duration(seconds: 8);
  static const _probeConcurrency = 5;

  final SharedPreferences _prefs;
  final AssetBundle _bundle;
  final JsonHttp _http;

  final Map<String, List<MediaSource>> _listSources = {};
  List<MediaSource> _custom = const [];
  String _activeListId = defaultListId;
  String? _selectedKeyValue;
  final Map<String, SourceAvailability> _availability = {};
  final Map<String, int> _latencyMs = {};
  final Set<String> _probing = {};
  final Set<String> _probedLists = {};
  int _probeGeneration = 0;
  MediaSource? _localHuangguo;
  ContentMode _contentMode = ContentMode.healthy;
  bool _autoSelected = false;

  ContentMode get contentMode => _contentMode;

  List<SourceListCatalog> get lists => sourceLists;

  String get activeListId => _activeListId;

  SourceListCatalog get activeList =>
      sourceLists.firstWhere((item) => item.id == _activeListId,
          orElse: () => sourceLists.first);

  bool hasLoadedList(String id) {
    final list = _listSources[id];
    return list != null && list.isNotEmpty;
  }


  /// 所有已加载列表与自定义源，不受当前 tab 和模式过滤。
  List<MediaSource> get allSources {
    final byKey = <String, MediaSource>{};
    for (final sources in _listSources.values) {
      for (final source in sources) {
        byKey[source.key] = source;
      }
    }
    for (final source in _custom) {
      byKey[source.key] = source;
    }
    return byKey.values.toList();
  }

  /// 当前 tab 的远程源（加上自定义源），再按健康/成人模式过滤。
  List<MediaSource> get sources {
    final remote = _listSources[_activeListId] ?? const <MediaSource>[];
    final byKey = <String, MediaSource>{};
    for (final source in [...remote, ..._custom]) {
      byKey[source.key] = source;
    }
    return _visibleInMode(byKey.values.toList());
  }

  MediaSource? get current {
    final key = _selectedKeyValue;
    if (key == null) return null;
    for (final source in allSources) {
      if (source.key != key) continue;
      if (_contentMode == ContentMode.adult || source.isVisibleInHealthyMode) {
        return source;
      }
      return null;
    }
    return null;
  }

  SourceAvailability availabilityOf(String key) {
    final source = _sourceByKey(key);
    if (source != null && source.isHuangguo) {
      return SourceAvailability.available;
    }
    return _availability[key] ?? SourceAvailability.unknown;
  }

  int? latencyMsOf(String key) => _latencyMs[key];

  bool isProbing(String key) => _probing.contains(key);

  String displayNameOf(MediaSource source) {
    if (source.isHuangguo) return source.name;
    if (availabilityOf(source.key) == SourceAvailability.unavailable) {
      return '${source.name}（不可用）';
    }
    return source.name;
  }

  Future<void> load() async {
    final raw = await _bundle.loadString(bundledAsset);
    final bundled = _parseSites(raw);
    _localHuangguo = bundled.where((source) => source.isHuangguo).firstOrNull ??
        _canonicalHuangguo;
    final cached = _loadRemoteCacheFor(defaultListId);
    _listSources[defaultListId] =
        _withLocalHuangguo(cached.isNotEmpty ? cached : bundled);
    for (final catalog in sourceLists) {
      if (catalog.id == defaultListId) continue;
      final listCache = _loadRemoteCacheFor(catalog.id);
      if (listCache.isEmpty) continue;
      _listSources[catalog.id] =
          catalog.pinHuangguo ? _withLocalHuangguo(listCache) : listCache;
    }
    _custom = _loadCustom();
    _contentMode = _loadContentMode();
    if (_prefs.getString(_contentModeKey) == null) {
      await _prefs.setString(_contentModeKey, _contentMode.name);
    }
    _activeListId = _loadActiveListId();
    _selectedKeyValue = _prefs.getString(_selectedKey);
    _autoSelected = false;
    _readLatencies();
    final activeRemote = _listSources[_activeListId];
    if (_activeListId != defaultListId &&
        (activeRemote == null || activeRemote.isEmpty)) {
      try {
        await refreshRemote();
      } catch (_) {
        // 非默认列表没有缓存且远程失败时，tab 先显示空列表。
      }
    }
    await _reconcileSelection();
    notifyListeners();
  }

  Future<void> setActiveList(String id) async {
    if (sourceLists.every((item) => item.id != id)) return;
    if (_activeListId == id) return;
    _activeListId = id;
    await _prefs.setString(_selectedListKey, id);
    notifyListeners();
    final existing = _listSources[id];
    if (existing == null || existing.isEmpty) {
      try {
        await refreshRemote();
      } catch (_) {
        // 保留空列表，由界面提示刷新失败。
      }
    }
    if (!_probedLists.contains(id)) {
      await probeAll();
    }
  }

  Future<void> setContentMode(ContentMode mode) async {
    if (_contentMode == mode) return;
    _contentMode = mode;
    await _prefs.setString(_contentModeKey, mode.name);
    if (mode == ContentMode.adult) {
      await _applyDefaultSelection(force: true);
    } else {
      await _reconcileSelection();
    }
    notifyListeners();
  }

  /// 冷启动后台任务：先拉远程列表（失败则保留本地/缓存），再探测当前 tab 的受支持源。
  Future<void> refreshOnColdStart() async {
    try {
      if (_activeListId != defaultListId) {
        try {
          await _refreshList(defaultListId);
        } catch (_) {
          // 推荐列表缓存刷新失败不影响当前 tab。
        }
      }
      await refreshRemote();
    } catch (_) {
      // 远程失败时继续使用本地或上次缓存的列表。
    }
    await probeAll();
  }

  Future<void> refreshRemote() async {
    await _refreshList(_activeListId);
    await _reconcileSelection();
    notifyListeners();
  }

  Future<void> _refreshList(String id) async {
    final catalog = sourceLists.cast<SourceListCatalog?>().firstWhere(
          (item) => item?.id == id,
          orElse: () => null,
        );
    if (catalog == null) return;
    final data = await _http
        .get(Uri.parse(catalog.url))
        .timeout(const Duration(seconds: 15));
    final parsed = _parseSitesMap(data, cmsOnly: catalog.cmsOnly);
    _listSources[id] =
        catalog.pinHuangguo ? _withLocalHuangguo(parsed) : parsed;
    await _prefs.setString(_cacheKeyFor(id), jsonEncode(data));
    _probedLists.remove(id);
  }

  Future<void> probeAll() async {
    final generation = ++_probeGeneration;
    final listId = _activeListId;
    final list = sources;
    final targets = list.where((source) => source.isSupported).toList();
    // 只重置当前 tab 里即将探测的源，保留其它列表已测过的延迟。
    _probing
      ..clear()
      ..addAll([for (final source in targets) source.key]);
    for (final source in targets) {
      _latencyMs.remove(source.key);
      if (source.isHuangguo) {
        _availability[source.key] = SourceAvailability.available;
      } else {
        _availability[source.key] = SourceAvailability.checking;
      }
    }
    notifyListeners();
    if (targets.isEmpty) {
      _probing.clear();
      _probedLists.add(listId);
      return;
    }

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next;
        next += 1;
        if (index >= targets.length) return;
        final source = targets[index];
        final result = await _probe(source);
        if (generation != _probeGeneration) return;
        if (sources.every((item) => item.key != source.key)) {
          _probing.remove(source.key);
          continue;
        }
        if (source.isHuangguo) {
          _availability[source.key] = SourceAvailability.available;
        } else {
          _availability[source.key] = result.status;
        }
        if (result.latencyMs != null) {
          _latencyMs[source.key] = result.latencyMs!;
        } else {
          _latencyMs.remove(source.key);
        }
        _probing.remove(source.key);
        await _writeLatencies();
        notifyListeners();
      }
    }

    await Future.wait(
      List.generate(
        _probeConcurrency.clamp(1, targets.length),
        (_) => worker(),
      ),
    );
    if (generation != _probeGeneration) return;
    _probedLists.add(listId);
    await _promoteHealthyDefaultIfNeeded();
  }

  Future<_ProbeResult> _probe(MediaSource source) async {
    final stopwatch = Stopwatch()..start();
    try {
      final client = createVodClient(source);
      await client.categories().timeout(_probeTimeout);
      stopwatch.stop();
      return _ProbeResult(
        status: SourceAvailability.available,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      return const _ProbeResult(status: SourceAvailability.unavailable);
    }
  }

  Future<void> select(MediaSource source) async {
    _autoSelected = false;
    _selectedKeyValue = source.key;
    await _prefs.setString(_selectedKey, source.key);
    notifyListeners();
  }

  Future<void> addCustom({required String name, required String api}) async {
    final trimmedName = name.trim();
    final trimmedApi = api.trim();
    final key = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final source = MediaSource(
      key: key,
      name: trimmedName.isEmpty ? '自定义源' : trimmedName,
      type: 1,
      api: trimmedApi,
      custom: true,
    );
    _custom = [..._custom, source];
    await _saveCustom();
    await select(source);
  }

  Future<void> removeCustom(MediaSource source) async {
    if (!source.custom) return;
    _custom = _custom.where((item) => item.key != source.key).toList();
    _availability.remove(source.key);
    _latencyMs.remove(source.key);
    _probing.remove(source.key);
    await _saveCustom();
    await _writeLatencies();
    if (_selectedKeyValue == source.key) {
      await _applyDefaultSelection(force: true);
    }
    notifyListeners();
  }

  ContentMode _loadContentMode() {
    switch (_prefs.getString(_contentModeKey)) {
      case 'adult':
        return ContentMode.adult;
      default:
        return ContentMode.healthy;
    }
  }

  String _loadActiveListId() {
    final id = _prefs.getString(_selectedListKey);
    if (id != null && sourceLists.any((item) => item.id == id)) {
      return id;
    }
    return defaultListId;
  }

  List<MediaSource> _visibleInMode(List<MediaSource> list) {
    if (_contentMode == ContentMode.adult) return list;
    return [
      for (final source in list)
        if (source.isVisibleInHealthyMode) source,
    ];
  }

  Future<void> _reconcileSelection() async {
    if (current != null || _visibleInMode(allSources).isEmpty) return;
    await _applyDefaultSelection(force: true);
  }

  Future<void> _applyDefaultSelection({bool force = false}) async {
    final next = _defaultSourceForMode;
    if (next == null) return;
    if (!force && current?.key == next.key) return;
    _autoSelected = true;
    _selectedKeyValue = next.key;
    await _prefs.setString(_selectedKey, next.key);
  }

  MediaSource? get _defaultSourceForMode {
    // 自动选源仍以原来的合集列表为准，避免切换 tab 改变默认源。
    if (_contentMode == ContentMode.adult) {
      return allSources.where((source) => source.isHuangguo).firstOrNull ??
          _visibleInMode(_defaultListSources + _custom).firstOrNull;
    }
    return _defaultHealthySource;
  }

  List<MediaSource> get _defaultListSources =>
      _listSources[defaultListId] ?? const [];

  MediaSource? get _defaultHealthySource {
    final pool = _visibleInMode([..._defaultListSources, ..._custom]);
    final preferred = [
      for (final source in pool)
        if (source.isHealthyPreferred) source,
    ];
    final blue = [
      for (final source in pool)
        if (source.isHealthyMarked && source.isSupported) source,
    ];
    return _firstUsable(preferred) ??
        preferred.firstOrNull ??
        _firstUsable(blue) ??
        blue.firstOrNull ??
        pool.where((source) => source.isSupported).firstOrNull ??
        pool.firstOrNull;
  }

  MediaSource? _firstUsable(List<MediaSource> candidates) {
    for (final source in candidates) {
      if (availabilityOf(source.key) == SourceAvailability.available) {
        return source;
      }
    }
    for (final source in candidates) {
      if (availabilityOf(source.key) != SourceAvailability.unavailable) {
        return source;
      }
    }
    return null;
  }

  Future<void> _promoteHealthyDefaultIfNeeded() async {
    if (_contentMode != ContentMode.healthy || !_autoSelected) return;
    final selected = current;
    if (selected != null &&
        availabilityOf(selected.key) == SourceAvailability.available) {
      return;
    }
    final next = _defaultHealthySource;
    if (next == null || next.key == selected?.key) return;
    _selectedKeyValue = next.key;
    await _prefs.setString(_selectedKey, next.key);
    notifyListeners();
  }

  static const _canonicalHuangguo = MediaSource(
    key: 'huangguo_web',
    name: '黄果短剧',
    type: 3,
    api:
        'https://cdn.jsdelivr.net/gh/SikROo/huangguo-spider@v10.4/huangguo_web_spider.js',
  );

  MediaSource get _pinnedHuangguo => _localHuangguo ?? _canonicalHuangguo;

  MediaSource? _sourceByKey(String key) {
    for (final source in allSources) {
      if (source.key == key) return source;
    }
    return null;
  }

  bool _isHuangguoEntry(MediaSource source) {
    if (source.isHuangguo) return true;
    final key = source.key.toLowerCase();
    final api = source.api.toLowerCase();
    return key.contains('huangguo') ||
        source.name.contains('黄果') ||
        api.contains('huangguo');
  }

  /// 远程/缓存列表里的黄果条目一律丢掉，改用本地单独适配的源。
  List<MediaSource> _withLocalHuangguo(List<MediaSource> sources) {
    final pinned = _pinnedHuangguo;
    final others =
        sources.where((source) => !_isHuangguoEntry(source)).toList();
    final index = sources.indexWhere(_isHuangguoEntry);
    if (index < 0 || index >= others.length) {
      return [pinned, ...others];
    }
    return [...others.sublist(0, index), pinned, ...others.sublist(index)];
  }

  List<MediaSource> _parseSites(String raw, {bool cmsOnly = false}) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    return _parseSitesMap(Map<String, dynamic>.from(decoded), cmsOnly: cmsOnly);
  }

  List<MediaSource> _parseSitesMap(
    Map<String, dynamic> decoded, {
    bool cmsOnly = false,
  }) {
    final sites = decoded['sites'];
    if (sites is! List) return const [];
    final parsed = [
      for (final item in sites)
        if (item is Map) MediaSource.fromJson(Map<String, dynamic>.from(item)),
    ];
    if (!cmsOnly) return parsed;
    return [
      for (final source in parsed)
        if (source.isCms && _hasHttpApi(source.api)) source,
    ];
  }

  bool _hasHttpApi(String api) {
    final uri = Uri.tryParse(api.trim());
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }

  void _readLatencies() {
    final raw = _prefs.getString(_latencyKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _latencyMs
        ..clear()
        ..addEntries([
          for (final entry in decoded.entries)
            if (entry.value is num)
              MapEntry('${entry.key}', (entry.value as num).round()),
        ]);
    } catch (_) {
      // 忽略损坏的延迟缓存。
    }
  }

  Future<void> _writeLatencies() {
    return _prefs.setString(_latencyKey, jsonEncode(_latencyMs));
  }

  String _cacheKeyFor(String id) {
    if (id == defaultListId) return _remoteCacheKey;
    return '${_remoteCacheKey}_$id';
  }

  List<MediaSource> _loadRemoteCacheFor(String id) {
    final raw = _prefs.getString(_cacheKeyFor(id));
    if (raw == null || raw.isEmpty) return const [];
    final catalog = sourceLists.cast<SourceListCatalog?>().firstWhere(
          (item) => item?.id == id,
          orElse: () => null,
        );
    try {
      final parsed = _parseSites(raw, cmsOnly: catalog?.cmsOnly ?? false);
      return parsed.isEmpty ? const [] : parsed;
    } catch (_) {
      return const [];
    }
  }

  List<MediaSource> _loadCustom() {
    final raw = _prefs.getString(_customKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            MediaSource.fromJson(Map<String, dynamic>.from(item), custom: true),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveCustom() async {
    final raw = jsonEncode([for (final item in _custom) item.toJson()]);
    await _prefs.setString(_customKey, raw);
  }
}

class _ProbeResult {
  const _ProbeResult({required this.status, this.latencyMs});

  final SourceAvailability status;
  final int? latencyMs;
}
