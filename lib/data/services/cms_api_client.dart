import '../../domain/models/category.dart';
import '../../domain/models/media_source.dart';
import '../../domain/models/paged.dart';
import '../../domain/models/playable.dart';
import '../../domain/models/vod_detail.dart';
import '../../domain/models/vod_item.dart';
import 'api_exception.dart';
import 'json_http.dart';
import 'play_url_parser.dart';
import 'vod_client.dart';

class CmsApiClient implements VodClient {
  CmsApiClient({required this.source, JsonHttp? http})
      : _http = http ?? JsonHttp();

  @override
  final MediaSource source;
  final JsonHttp _http;

  List<VodCategory>? _cachedCategories;

  Uri _uri(Map<String, String> params) {
    final api = source.api.trim();
    final base = Uri.parse(api);
    final merged = <String, String>{
      ...base.queryParameters,
      ...params,
    };
    // 部分站需要 at=json 才会返回 JSON，无害地加上
    merged.putIfAbsent('at', () => 'json');
    return base.replace(queryParameters: merged);
  }

  Future<Map<String, dynamic>> _get(Map<String, String> params) {
    final referer = Uri.parse(source.api).origin;
    return _http.get(
      _uri(params),
      headers: {
        'Referer': '$referer/',
      },
    );
  }

  int _asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  String _asString(Object? value) => value == null ? '' : '$value';

  VodItem _toItem(Map<String, dynamic> raw) {
    return VodItem(
      sourceKey: source.key,
      id: _asString(raw['vod_id'] ?? raw['id']),
      name: _asString(raw['vod_name'] ?? raw['name'] ?? raw['title']),
      pic: _asString(raw['vod_pic'] ?? raw['vod_pic_thumb']),
      remarks: _asString(raw['vod_remarks'] ?? raw['vod_note']),
      score: _asString(raw['vod_score']),
      typeName: _asString(raw['type_name'] ?? raw['vod_class']),
      description: _asString(raw['vod_blurb'] ?? raw['vod_content']),
    );
  }

  List<VodCategory> _readCategories(Map<String, dynamic> data) {
    final raw = data['class'];
    if (raw is! List) return const [];
    final list = <VodCategory>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = _asString(map['type_id']);
      final name = _asString(map['type_name']);
      if (id.isEmpty || name.isEmpty) continue;
      list.add(VodCategory(id: id, name: name));
    }
    return list;
  }

  PagedVod _toPage(Map<String, dynamic> data) {
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
    final page = _asInt(data['page'], 1);
    var pageCount = _asInt(data['pagecount'] ?? data['pageCount'], 1);
    final total = _asInt(data['total'], items.length);
    if (pageCount <= 0) {
      pageCount = items.isEmpty ? page : page + 1;
    }
    return PagedVod(list: items, page: page, pageCount: pageCount, total: total);
  }

  @override
  Future<List<VodCategory>> categories() async {
    if (_cachedCategories != null) return _cachedCategories!;
    final data = await _get({'ac': 'list', 'pg': '1'});
    _cachedCategories = _readCategories(data);
    return _cachedCategories!;
  }

  @override
  Future<PagedVod> list({
    int page = 1,
    String? categoryId,
    String? keyword,
  }) async {
    final params = <String, String>{
      'ac': 'videolist',
      'pg': '$page',
    };
    if (categoryId != null && categoryId.isNotEmpty) {
      params['t'] = categoryId;
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      params['wd'] = keyword.trim();
    }
    var data = await _get(params);
    var result = _toPage(data);
    // 个别站 videolist 为空时，退回精简列表
    if (result.list.isEmpty && keyword == null) {
      params['ac'] = 'list';
      data = await _get(params);
      result = _toPage(data);
    }
    final cats = _readCategories(data);
    if (cats.isNotEmpty) _cachedCategories = cats;
    return result;
  }

  @override
  Future<VodDetail> detail(String id) async {
    final data = await _get({'ac': 'detail', 'ids': id});
    final rawList = data['list'];
    if (rawList is! List || rawList.isEmpty || rawList.first is! Map) {
      throw ApiException('没有找到该条目的详情。');
    }
    final raw = Map<String, dynamic>.from(rawList.first as Map);
    final item = _toItem(raw);
    final content = _asString(raw['vod_content'] ?? raw['vod_blurb']);
    final lines = parsePlayUrls(
      playFrom: _asString(raw['vod_play_from']),
      playUrl: _asString(raw['vod_play_url']),
    );
    return VodDetail(
      item: item,
      lines: lines,
      content: _stripHtml(content),
      year: _asString(raw['vod_year']),
      actor: _asString(raw['vod_actor']),
    );
  }

  @override
  Future<Playable> play({
    required String id,
    required Episode episode,
    String? lineName,
  }) async {
    if (episode.url != null && episode.url!.isNotEmpty) {
      return Playable(
        url: episode.url!,
        title: episode.title,
        headers: {
          'User-Agent': JsonHttp.defaultUa,
          'Referer': '${Uri.parse(source.api).origin}/',
        },
      );
    }
    final detailData = await detail(id);
    for (final line in detailData.lines) {
      if (lineName != null && line.name != lineName) continue;
      for (final ep in line.episodes) {
        if (ep.id == episode.id || ep.title == episode.title) {
          if (ep.url == null || ep.url!.isEmpty) continue;
          return Playable(
            url: ep.url!,
            title: ep.title,
            headers: {
              'User-Agent': JsonHttp.defaultUa,
              'Referer': '${Uri.parse(source.api).origin}/',
            },
          );
        }
      }
    }
    throw ApiException('没有拿到播放地址。');
  }

  String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
