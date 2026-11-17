import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/media_source.dart';
import '../services/client_factory.dart';
import '../services/json_http.dart';

enum SourceAvailability { unknown, checking, available, unavailable }

enum ContentMode { healthy, adult }

class SourceRepository extends ChangeNotifier {
  SourceRepository({
    required SharedPreferences prefs,
    required AssetBundle bundle,
    JsonHttp? http,
  })  : _prefs = prefs,
        _bundle = bundle,
        _http = http ?? JsonHttp();

  static const bundledAsset = 'assets/sources.json';
  static const remoteConfigUrl =
      'https://cdn.jsdelivr.net/gh/SikROo/huangguo-spider@v10.4/all_sources_config.json';
  static const _selectedKey = 'selected_source_key';
  static const _customKey = 'custom_sources_json';
  static const _remoteCacheKey = 'remote_sources_json';
  static const _contentModeKey = 'content_mode_v1';
  static const _probeTimeout = Duration(seconds: 8);
  static const _probeConcurrency = 5;

  final SharedPreferences _prefs;
  final AssetBundle _bundle;
  final JsonHttp _http;

  List<MediaSource> _bundled = const [];
  List<MediaSource> _custom = const [];
  String? _selectedKeyValue;
  final Map<String, SourceAvailability> _availability = {};
  int _probeGeneration = 0;
  MediaSource? _localHuangguo;
  ContentMode _contentMode = ContentMode.healthy;
  bool _autoSelected = false;

  ContentMode get contentMode => _contentMode;

  List<MediaSource> get allSources {
    final byKey = <String, MediaSource>{};
    for (final source in [..._bundled, ..._custom]) {
      byKey[source.key] = source;
    }
    return byKey.values.toList();
  }

  List<MediaSource> get sources {
    final list = allSources;
    if (_contentMode == ContentMode.adult) return list;
    return [
      for (final source in list)
        if (source.isVisibleInHealthyMode) source,
    ];
  }

  MediaSource? get current {
    final list = sources;
    if (list.isEmpty) return null;
    for (final source in list) {
      if (source.key == _selectedKeyValue) return source;
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
    final cached = _loadRemoteCache();
    _bundled = _withLocalHuangguo(cached.isNotEmpty ? cached : bundled);
    _custom = _loadCustom();
    _contentMode = _loadContentMode();
    if (_prefs.getString(_contentModeKey) == null) {
      await _prefs.setString(_contentModeKey, _contentMode.name);
    }
    _selectedKeyValue = _prefs.getString(_selectedKey);
    _autoSelected = false;
    await _reconcileSelection();
    notifyListeners();
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

  /// 冷启动后台任务：先拉远程列表（失败则保留本地/缓存），再探测全部受支持源。
  Future<void> refreshOnColdStart() async {
    try {
      await refreshRemote();
    } catch (_) {
      // 远程失败时继续使用本地或上次缓存的列表。
    }
    await probeAll();
  }

  Future<void> refreshRemote() async {
    final data = await _http
        .get(Uri.parse(remoteConfigUrl))
        .timeout(const Duration(seconds: 15));
    _bundled = _withLocalHuangguo(_parseSitesMap(data));
    await _prefs.setString(_remoteCacheKey, jsonEncode(data));
    await _reconcileSelection();
    notifyListeners();
  }

  Future<void> probeAll() async {
    final generation = ++_probeGeneration;
    final list = sources;
    for (final source in list.where((item) => item.isHuangguo)) {
      _availability[source.key] = SourceAvailability.available;
    }
    final targets =
        list.where((source) => source.isSupported && !source.isHuangguo).toList();
    _availability.removeWhere((key, _) => list.every((source) => source.key != key));
    for (final source in targets) {
      _availability[source.key] = SourceAvailability.checking;
    }
    notifyListeners();
    if (targets.isEmpty) return;

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next;
        next += 1;
        if (index >= targets.length) return;
        final source = targets[index];
        final status = await _probe(source);
        if (generation != _probeGeneration) return;
        if (sources.every((item) => item.key != source.key)) continue;
        _availability[source.key] = status;
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
    await _promoteHealthyDefaultIfNeeded();
  }

  Future<SourceAvailability> _probe(MediaSource source) async {
    if (source.isHuangguo) return SourceAvailability.available;
    try {
      final client = createVodClient(source);
      await client.categories().timeout(_probeTimeout);
      return SourceAvailability.available;
    } catch (_) {
      return SourceAvailability.unavailable;
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
    await _saveCustom();
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

  Future<void> _reconcileSelection() async {
    if (current != null || sources.isEmpty) return;
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
    if (_contentMode == ContentMode.healthy) {
      return _defaultHealthySource;
    }
    return allSources.where((source) => source.isHuangguo).firstOrNull ??
        sources.firstOrNull;
  }

  MediaSource? get _defaultHealthySource {
    final preferred = [
      for (final source in sources)
        if (source.isHealthyPreferred) source,
    ];
    final blue = [
      for (final source in sources)
        if (source.isHealthyMarked && source.isSupported) source,
    ];
    return _firstUsable(preferred) ??
        preferred.firstOrNull ??
        _firstUsable(blue) ??
        blue.firstOrNull ??
        sources.where((source) => source.isSupported).firstOrNull ??
        sources.firstOrNull;
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
    for (final source in sources) {
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
    final others = sources.where((source) => !_isHuangguoEntry(source)).toList();
    final index = sources.indexWhere(_isHuangguoEntry);
    if (index < 0 || index >= others.length) {
      return [pinned, ...others];
    }
    return [...others.sublist(0, index), pinned, ...others.sublist(index)];
  }

  List<MediaSource> _parseSites(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    return _parseSitesMap(Map<String, dynamic>.from(decoded));
  }

  List<MediaSource> _parseSitesMap(Map<String, dynamic> decoded) {
    final sites = decoded['sites'];
    if (sites is! List) return const [];
    return [
      for (final item in sites)
        if (item is Map)
          MediaSource.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  List<MediaSource> _loadRemoteCache() {
    final raw = _prefs.getString(_remoteCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final parsed = _parseSites(raw);
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
