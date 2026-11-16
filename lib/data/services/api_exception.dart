class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UnsupportedSourceException extends ApiException {
  UnsupportedSourceException()
      : super('这个源是自定义爬虫，当前版本还不能直接接入。请先选采集站 JSON 源，或使用「黄果短剧」。');
}
