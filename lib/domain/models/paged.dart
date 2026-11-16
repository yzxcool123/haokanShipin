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
}
