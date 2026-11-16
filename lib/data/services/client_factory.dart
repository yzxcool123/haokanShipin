import '../../domain/models/media_source.dart';
import 'api_exception.dart';
import 'cms_api_client.dart';
import 'huangguo_api_client.dart';
import 'vod_client.dart';

VodClient createVodClient(MediaSource source) {
  if (source.isHuangguo) {
    return HuangguoApiClient(source: source);
  }
  if (source.isCms) {
    return CmsApiClient(source: source);
  }
  throw UnsupportedSourceException();
}
