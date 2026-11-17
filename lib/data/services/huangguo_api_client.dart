import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import '../../domain/models/category.dart';
import '../../domain/models/media_source.dart';
import '../../domain/models/paged.dart';
import '../../domain/models/playable.dart';
import '../../domain/models/vod_detail.dart';
import '../../domain/models/vod_item.dart';
import 'api_exception.dart';
import 'huangguo_dx150.dart';
import 'json_http.dart';
import 'vod_client.dart';

class HuangguoApiClient implements VodClient {
  HuangguoApiClient({required this.source, JsonHttp? http})
      : _http = http ?? JsonHttp();

  @override
  final MediaSource source;
  final JsonHttp _http;
  late final HuangguoDx150 _dx = HuangguoDx150(site: site, http: _http);

  static const defaultWorker = 'https://huangguo-parser.13681235735.workers.dev';
  static const site = 'https://huangguoai.io';
  static const origin = 'https://drdrdrrddrdr.github.io';
  static const referer = 'https://drdrdrrddrdr.github.io/huangguo-web/';
  // 与公开爬虫脚本中的签名密钥一致，站点可能会更换。
  static const secret = 'hg-dx150-2026-11-w7Qm4pLz';

  static const fallbackCategories = [
    VodCategory(id: 'ai-duanju', name: 'AI短剧'),
    VodCategory(id: 'ai-manju', name: 'AI漫剧'),
    VodCategory(id: 'chigua', name: '吃瓜·全部'),
    VodCategory(id: 'rank:hot', name: '热播榜'),
    VodCategory(id: 'rank:recommend', name: '推荐榜'),
    VodCategory(id: 'rank:potential', name: '潜力榜'),
  ];

  String get _base {
    final api = source.api.trim();
    if (api.startsWith('http') && !api.endsWith('.js')) {
      return api.endsWith('/') ? api.substring(0, api.length - 1) : api;
    }
    return defaultWorker;
  }

  Map<String, String> _signHeaders(String pathWithQuery, {int shift = 0}) {
    final win = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 300 + shift;
    final message = '$win\n$pathWithQuery';
    final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(message));
    return {
      'User-Agent': JsonHttp.defaultUa,
      'Accept': 'application/json, text/plain, */*',
      'Origin': origin,
      'Referer': referer,
      'X-HG-Ts': '${win * 300}',
      'X-HG-Sig': sig.toString(),
    };
  }

  Future<Map<String, dynamic>> _workerGet(String pathWithQuery) async {
    final uri = Uri.parse('$_base$pathWithQuery');
    ApiException? last;
    for (final shift in const [0, -1, 1]) {
      try {
        return await _http.get(uri, headers: _signHeaders(pathWithQuery, shift: shift));
      } on ApiException catch (e) {
        last = e;
        if (!e.message.contains('403') && !e.message.contains('401')) {
          rethrow;
        }
      }
    }
    throw last ?? ApiException('黄果接口请求失败。');
  }

  Future<Map<String, dynamic>> _siteGet(String pathWithQuery) {
    return _http.get(
      Uri.parse('$site$pathWithQuery'),
      headers: {
        'User-Agent': JsonHttp.defaultUa,
        'Referer': '$site/',
        'Origin': site,
      },
    );
  }

  Future<T> _siteThenWorker<T>(
    Future<T> Function() siteCall,
    Future<T> Function() workerCall,
  ) async {
    try {
      return await siteCall();
    } catch (_) {
      return workerCall();
    }
  }

  PagedVod _fromSiteList(
    Map<String, dynamic> data,
    int page, {
    VodItem Function(Map<String, dynamic>)? mapper,
  }) {
    final payload = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
    final rawItems = payload['items'] is List ? payload['items'] as List : const [];
    final pg = payload['pagination'];
    final mapItem = mapper ?? _toSiteItem;
    final items = <VodItem>[];
    for (final item in rawItems) {
      if (item is Map) {
        final vod = mapItem(Map<String, dynamic>.from(item));
        if (vod.id.isNotEmpty) items.add(vod);
      }
    }
    return PagedVod(
      list: items,
      page: pg is Map ? _asInt(pg['page'], page) : page,
      pageCount: pg is Map ? _asInt(pg['pages'], items.isEmpty ? page : page + 1) : (items.isEmpty ? page : page + 1),
      total: pg is Map ? _asInt(pg['total'], items.length) : items.length,
    );
  }

  String _asString(Object? value) => value == null ? '' : '$value';

  int _asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  String _picOf(Object? value) {
    final u = _asString(value);
    if (u.isEmpty) return '';
    if (RegExp(r'^https?:\/\/', caseSensitive: false).hasMatch(u)) {
      return u;
    }
    if (u.startsWith('/')) return '$site$u';
    return u;
  }

  VodItem _toItem(Map<String, dynamic> raw) {
    final tags = raw['vod_tags'];
    final typeName = tags is List
        ? tags.map((e) => '$e').where((e) => e.isNotEmpty).join(' / ')
        : _asString(raw['vod_type_name'] ?? raw['type_name']);
    return VodItem(
      sourceKey: source.key,
      id: _asString(raw['vod_id'] ?? raw['id']),
      name: _asString(raw['vod_name'] ?? raw['title']),
      pic: _picOf(raw['vod_pic'] ?? raw['cover']),
      remarks: _asString(raw['vod_remarks']),
      score: _asString(raw['vod_score'] ?? raw['score']),
      typeName: typeName,
      description: _asString(raw['vod_desc'] ?? raw['description'] ?? raw['vod_content']),
    );
  }

  VodItem _toSiteItem(Map<String, dynamic> raw) {
    final eps = _asInt(raw['episode_count']);
    final tags = <String>[
      if (eps > 0) '$eps集',
      if (raw['is_original'] == true || raw['is_original'] == 1) '原创',
      if (_asString(raw['score']).isNotEmpty) '${raw['score']}分',
    ];
    return VodItem(
      sourceKey: source.key,
      id: _asString(raw['id'] ?? raw['vod_id']),
      name: _asString(raw['title'] ?? raw['vod_name']),
      pic: _picOf(raw['cover'] ?? raw['vod_pic']),
      remarks: tags.join(' · '),
      score: _asString(raw['score']),
      typeName: '',
      description: _asString(raw['description']),
    );
  }

  VodItem _toPostItem(Map<String, dynamic> raw) {
    return VodItem(
      sourceKey: source.key,
      id: 'archives_${_asString(raw['id'])}',
      name: _asString(raw['title']),
      pic: _picOf(raw['cover']),
      remarks: _asString(raw['created_at']),
      typeName: '吃瓜',
      description: _asString(raw['desc']),
    );
  }

  PagedVod _fromWorkerList(Map<String, dynamic> data, int page) {
    final rawList = data['list'];
    final items = <VodItem>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          final vod = _toItem(Map<String, dynamic>.from(item));
          if (vod.id.isNotEmpty) items.add(vod);
        }
      }
    }
    return PagedVod(
      list: items,
      page: _asInt(data['page'], page),
      pageCount: _asInt(data['pagecount'], items.isEmpty ? page : page),
      total: _asInt(data['total'], items.length),
    );
  }

  @override
  Future<List<VodCategory>> categories() async {
    // 官方前端已改为直连源站，分类枚举也是内置的；不再先打会超时的 Worker。
    return fallbackCategories;
  }

  @override
  Future<PagedVod> list({
    int page = 1,
    String? categoryId,
    String? keyword,
  }) async {
    final key = keyword?.trim() ?? '';
    if (key.isNotEmpty) {
      return _search(key, page);
    }
    final tid = (categoryId == null || categoryId.isEmpty) ? 'recommend' : categoryId;
    return _listPage(tid, page);
  }

  Future<PagedVod> _listPage(String tid, int page) async {
    const size = 20;
    if (tid == 'recommend') {
      return _listPage('ai-duanju', page);
    }

    if (tid.startsWith('topic:')) {
      final slug = Uri.encodeComponent(tid.substring(6));
      final data = await _siteGet('/api/topics/$slug?page=$page&size=$size');
      final videos = data['data'] is Map ? (data['data'] as Map)['videos'] : null;
      final itemsRaw =
          videos is Map && videos['items'] is List ? videos['items'] as List : const [];
      final pagination = videos is Map ? videos['pagination'] : null;
      final items = <VodItem>[];
      for (final item in itemsRaw) {
        if (item is Map) items.add(_toSiteItem(Map<String, dynamic>.from(item)));
      }
      return PagedVod(
        list: items,
        page: page,
        pageCount: pagination is Map ? _asInt(pagination['pages'], page) : page,
        total: pagination is Map ? _asInt(pagination['total'], items.length) : items.length,
      );
    }

    if (tid.startsWith('chigua')) {
      final cate = tid.contains(':') ? tid.split(':')[1] : 'all';
      return _siteThenWorker(
        () async {
          final site = await _siteGet(
            '/api/posts?cate=${Uri.encodeComponent(cate)}&page=$page&size=$size',
          );
          return _fromSiteList(site, page, mapper: _toPostItem);
        },
        () async {
          final data = await _workerGet(
            '/api/chigua?cate=${Uri.encodeComponent(cate)}&page=$page&size=$size',
          );
          return _fromWorkerList(data, page);
        },
      );
    }

    if (tid.startsWith('rank:')) {
      final kind = tid.substring(5);
      return _siteThenWorker(
        () async {
          final data = await _siteGet(
            '/api/ranks/${Uri.encodeComponent(kind)}?page=$page&size=$size',
          );
          return _fromSiteList(data, page);
        },
        () async {
          final data = await _workerGet(
            '/api/ranks/${Uri.encodeComponent(kind)}?page=$page&size=$size',
          );
          return _fromWorkerList(data, page);
        },
      );
    }

    return _siteThenWorker(
      () async {
        final data = await _siteGet(
          '/api/videos/category/${Uri.encodeComponent(tid)}?page=$page&size=$size&sort=latest',
        );
        return _fromSiteList(data, page);
      },
      () async {
        final data = await _workerGet(
          '/api/category/${Uri.encodeComponent(tid)}?page=$page&size=$size&sort=latest',
        );
        return _fromWorkerList(data, page);
      },
    );
  }

  Future<PagedVod> _search(String keyword, int page) async {
    final encoded = Uri.encodeComponent(keyword);
    return _siteThenWorker(
      () async {
        final site = await _siteGet('/api/search?q=$encoded&page=$page&size=20');
        return _fromSiteList(site, page);
      },
      () async {
        final data = await _workerGet('/api/search/$encoded?page=$page&size=20');
        return _fromWorkerList(data, page);
      },
    );
  }

  @override
  Future<VodDetail> detail(String id) async {
    Map<String, dynamic>? raw;
    if (!id.startsWith('archives_')) {
      try {
        final site = await _siteGet('/api/videos/${Uri.encodeComponent(id)}');
        if (site['data'] is Map) {
          raw = Map<String, dynamic>.from(site['data'] as Map);
        }
      } catch (_) {}
    }
    if (raw == null) {
      try {
        final data = await _workerGet('/api/detail/${Uri.encodeComponent(id)}');
        final list = data['list'];
        if (list is List && list.isNotEmpty && list.first is Map) {
          raw = Map<String, dynamic>.from(list.first as Map);
        }
      } catch (_) {}
    }

    if (raw == null && id.startsWith('archives_')) {
      final pid = id.replaceFirst('archives_', '');
      final site = await _siteGet('/api/posts/${Uri.encodeComponent(pid)}');
      final pd = site['data'] is Map ? Map<String, dynamic>.from(site['data'] as Map) : {};
      raw = {
        'vod_id': id,
        'vod_name': _asString(pd['title']),
        'vod_pic': pd['cover'] ?? '',
        'vod_remarks': _asString(pd['created_at']),
        'vod_desc': _asString(pd['content'] ?? pd['desc']),
        'episodes': const [],
      };
    }
    if (raw == null) {
      throw ApiException('没有找到该条目的详情。');
    }

    var episodes = <Episode>[];
    final rawEps = raw['episodes'];
    if (rawEps is List) {
      for (final item in rawEps) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final ep = _asString(map['ep']);
        if (ep.isEmpty) continue;
        episodes.add(Episode(
          id: ep,
          title: _asString(map['title']).isEmpty ? '第$ep集' : _asString(map['title']),
          url: _asString(map['url']).isEmpty ? null : _asString(map['url']),
        ));
      }
    }

    if (id.startsWith('archives_') && episodes.isEmpty) {
      final videos = await _postVideos(id.replaceFirst('archives_', ''));
      for (var i = 0; i < videos.length; i++) {
        episodes.add(Episode(
          id: '${i + 1}',
          title: '视频${i + 1}',
          url: videos[i]['url'] as String?,
        ));
      }
    }

    if (episodes.isEmpty) {
      final count = _asInt(
        raw['vod_episode_count'],
        _asInt(raw['episode_count'], _asInt(raw['total_episodes'], 1)),
      );
      final total = count <= 0 ? 1 : count;
      episodes = [
        for (var i = 1; i <= total; i++) Episode(id: '$i', title: '第$i集'),
      ];
    }

    final item = _toItem(raw);
    return VodDetail(
      item: item,
      lines: [PlayLine(name: '黄果', episodes: episodes)],
      content: _asString(raw['vod_desc'] ?? raw['vod_content']),
      year: _asString(raw['vod_year']),
      actor: _asString(raw['vod_author'] ?? raw['vod_actor']),
    );
  }

  Future<List<Map<String, dynamic>>> _postVideos(String pid) async {
    try {
      final data = await _http.post(
        Uri.parse('$site/api/posts/${Uri.encodeComponent(pid)}/playback'),
        headers: {
          'User-Agent': JsonHttp.defaultUa,
          'Referer': '$site/',
          'Origin': site,
        },
        body: {},
      );
      final payload = data['data'] is Map ? Map<String, dynamic>.from(data['data'] as Map) : {};
      final videos = payload['videos'];
      if (videos is! List) return const [];
      final out = <Map<String, dynamic>>[];
      for (final item in videos) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final url = _asString(map['url']);
        if (url.isEmpty) continue;
        out.add({'url': url, 'cdn': payload['cdn']});
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Playable> play({
    required String id,
    required Episode episode,
    String? lineName,
  }) async {
    if (episode.url != null &&
        episode.url!.isNotEmpty &&
        episode.url!.startsWith('http')) {
      return Playable(
        url: episode.url!,
        title: episode.title,
        headers: _playHeaders(),
      );
    }

    if (id.startsWith('archives_')) {
      final videos = await _postVideos(id.replaceFirst('archives_', ''));
      if (videos.isNotEmpty) {
        final index = int.tryParse(episode.id) ?? 1;
        final picked = (index - 1) >= 0 && (index - 1) < videos.length
            ? videos[index - 1]
            : videos.first;
        return Playable(
          url: picked['url'] as String,
          title: episode.title,
          headers: _playHeaders(cdn: picked['cdn']),
        );
      }
    }

    try {
      final dx = await _dx.play(id, episode.id);
      if (dx != null && dx.url.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('huangguo play via dx150');
        }
        return Playable(
          url: dx.url,
          title: episode.title,
          headers: _playHeaders(cdn: dx.cdn),
        );
      }
    } catch (_) {}

    final data = await _workerGet(
      '/api/play?url=${Uri.encodeComponent(id)}&ep=${Uri.encodeComponent(episode.id)}',
    );
    final url = _asString(data['url']);
    if (url.isEmpty) {
      throw ApiException('没有拿到播放地址。');
    }
    if (kDebugMode) {
      debugPrint('huangguo play via worker');
    }
    return Playable(url: url, title: episode.title, headers: _playHeaders());
  }

  Map<String, String> _playHeaders({Object? cdn}) {
    final headers = <String, String>{
      'User-Agent': JsonHttp.defaultUa,
      'Referer': '$site/',
    };
    if (cdn is Map) {
      final authKey = _asString(cdn['authKey']);
      final authValue = _asString(cdn['authValue']);
      if (authKey.isNotEmpty && authValue.isNotEmpty) {
        headers[authKey] = authValue;
      }
      final app = _asString(cdn['app']);
      if (app.isNotEmpty) headers['x-cdn-app'] = app;
    }
    return headers;
  }
}
