import '../../domain/models/category.dart';
import '../../domain/models/media_source.dart';
import '../../domain/models/paged.dart';
import '../../domain/models/playable.dart';
import '../../domain/models/vod_detail.dart';

abstract class VodClient {
  MediaSource get source;

  Future<List<VodCategory>> categories();

  Future<PagedVod> list({
    int page = 1,
    String? categoryId,
    String? keyword,
  });

  Future<VodDetail> detail(String id);

  Future<Playable> play({
    required String id,
    required Episode episode,
    String? lineName,
  });
}
