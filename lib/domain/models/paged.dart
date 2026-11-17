import 'vod_item.dart';

class PagedVod {
  const PagedVod({
    required this.list,
    required this.page,
    required this.pageCount,
    required this.total,
  });

  final List<VodItem> list;
  final int page;
  final int pageCount;
  final int total;

  bool get hasMore => page < pageCount;

  factory PagedVod.fromJson(Map<String, dynamic> json) {
    final raw = json['list'];
    return PagedVod(
      list: [
        if (raw is List)
          for (final item in raw)
            if (item is Map) VodItem.fromJson(Map<String, dynamic>.from(item)),
      ],
      page: _asInt(json['page'], 1),
      pageCount: _asInt(json['pageCount'], 1),
      total: _asInt(json['total'], 0),
    );
  }

  Map<String, dynamic> toJson() => {
        'list': [for (final item in list) item.toJson()],
        'page': page,
        'pageCount': pageCount,
        'total': total,
      };
}

int _asInt(Object? value, int fallback) {
  if (value is int) return value;
  return int.tryParse('${value ?? ''}') ?? fallback;
}
