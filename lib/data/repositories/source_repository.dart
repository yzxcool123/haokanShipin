import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/media_source.dart';

class SourceRepository extends ChangeNotifier {
  SourceRepository({
    required SharedPreferences prefs,
    required AssetBundle bundle,
    http.Client? client,
  })  : _prefs = prefs,
        _bundle = bundle,
        _client = client ?? http.Client();

  static const bundledAsset = 'assets/sources.json';
  static const remoteConfigUrl =
      'https://cdn.jsdelivr.net/gh/SikROo/huangguo-spider@v10.4/all_sources_config.json';
  static const _selectedKey = 'selected_source_key';
  static const _customKey = 'custom_sources_json';

  final SharedPreferences _prefs;
  final AssetBundle _bundle;
  final http.Client _client;

  List<MediaSource> _bundled = const [];
  List<MediaSource> _custom = const [];
  String? _selectedKeyValue;

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

  Future<void> load() async {
    final raw = await _bundle.loadString(bundledAsset);
    _bundled = _parseSites(raw);
    _custom = _loadCustom();
    _selectedKeyValue = _prefs.getString(_selectedKey);
    if (current == null && sources.isNotEmpty) {
      _selectedKeyValue = sources.first.key;
    }
    notifyListeners();
  }

  Future<void> refreshRemote() async {
    final response = await _client.get(Uri.parse(remoteConfigUrl)).timeout(
      const Duration(seconds: 20),
    );
    if (response.statusCode != 200) {
      throw Exception('刷新源列表失败：${response.statusCode}');
    }
    _bundled = _parseSites(utf8.decode(response.bodyBytes));
    notifyListeners();
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
    final sites = decoded['sites'];
    if (sites is! List) return const [];
    return [
      for (final item in sites)
        if (item is Map)
          MediaSource.fromJson(Map<String, dynamic>.from(item)),
    ];
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
