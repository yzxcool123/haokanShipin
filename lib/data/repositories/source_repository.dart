import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/media_source.dart';
import '../services/client_factory.dart';
import '../services/json_http.dart';

enum SourceAvailability { unknown, checking, available, unavailable }

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

  List<MediaSource> get sources {
    final byKey = <String, MediaSource>{};
    for (final source in [..._bundled, ..._custom]) {
      byKey[source.key] = source;
    }
    return byKey.values.toList();
  }

  MediaSource? get current {
    final list = sources;
    if (list.isEmpty) return null;
    for (final source in list) {
      if (source.key == _selectedKeyValue) return source;
    }
    return list.first;
  }

  SourceAvailability availabilityOf(String key) =>
      _availability[key] ?? SourceAvailability.unknown;

  String displayNameOf(MediaSource source) {
    if (availabilityOf(source.key) == SourceAvailability.unavailable) {
      return '${source.name}（不可用）';
    }
    return source.name;
  }

  Future<void> load() async {
    final raw = await _bundle.loadString(bundledAsset);
    _bundled = _parseSites(raw);
    final cached = _loadRemoteCache();
    if (cached.isNotEmpty) {
      _bundled = cached;
    }
    _custom = _loadCustom();
    _selectedKeyValue = _prefs.getString(_selectedKey);
    if (current == null && sources.isNotEmpty) {
      _selectedKeyValue = sources.first.key;
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
    _bundled = _parseSitesMap(data);
    await _prefs.setString(_remoteCacheKey, jsonEncode(data));
    notifyListeners();
  }

  Future<void> probeAll() async {
    final generation = ++_probeGeneration;
    final list = sources;
    final targets = list.where((source) => source.isSupported).toList();
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
  }

  Future<SourceAvailability> _probe(MediaSource source) async {
    try {
      final client = createVodClient(source);
      // 黄果的 categories() 只返回内置分类、不会发网络请求；
      // 探测必须走 HuangguoApiClient.list()，沿用 DoH、签名和站点/Worker 回退。
      final future = source.isHuangguo ? client.list(page: 1) : client.categories();
      await future.timeout(_probeTimeout);
      return SourceAvailability.available;
    } catch (_) {
      return SourceAvailability.unavailable;
    }
  }

  Future<void> select(MediaSource source) async {
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
      _selectedKeyValue = sources.isEmpty ? null : sources.first.key;
      if (_selectedKeyValue != null) {
        await _prefs.setString(_selectedKey, _selectedKeyValue!);
      }
    }
    notifyListeners();
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
