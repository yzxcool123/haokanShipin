import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/playable.dart';
import 'json_http.dart';
import 'm3u8_playlist.dart';

class OfflineDownloadException implements Exception {
  const OfflineDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OfflineDownloadResult {
  const OfflineDownloadResult({
    required this.localPath,
    required this.bytes,
  });

  final String localPath;
  final int bytes;
}

/// 将在线播放地址缓存到本地目录，支持整文件和 HLS 分片。
class OfflineMediaDownloader {
  OfflineMediaDownloader({Dio? client}) : _dio = client ?? _createClient();

  final Dio _dio;
  static const _concurrency = 4;

  static Dio _createClient() {
    final dio = JsonHttp.createDefaultClient();
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.sendTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 120);
    return dio;
  }

  Future<OfflineDownloadResult> download({
    required Playable playable,
    required Directory directory,
    required CancelToken cancelToken,
    required void Function(double progress) onProgress,
  }) async {
    if (playable.url.isEmpty) {
      throw const OfflineDownloadException('没有可缓存的播放地址');
    }
    await directory.create(recursive: true);
    onProgress(0);
    if (playable.isHls) {
      return _downloadHls(
        playlistUri: Uri.parse(playable.url),
        headers: playable.headers,
        directory: directory,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    }
    return _downloadProgressiveOrHls(
      playable: playable,
      directory: directory,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  Future<OfflineDownloadResult> _downloadProgressiveOrHls({
    required Playable playable,
    required Directory directory,
    required CancelToken cancelToken,
    required void Function(double progress) onProgress,
  }) async {
    final uri = Uri.parse(playable.url);
    final temp = File('${directory.path}/download.tmp');
    await _downloadToFile(
      uri,
      temp,
      headers: playable.headers,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total != null && total > 0) {
          onProgress((received / total).clamp(0.0, 0.99));
        }
      },
    );
    final header = await _readPrefix(temp, 32);
    if (_looksLikePlaylist(header)) {
      final text = _decodePlaylist(Uint8List.fromList(await temp.readAsBytes()));
      await temp.delete();
      return _downloadHlsFromText(
        text: text,
        playlistUri: uri,
        headers: playable.headers,
        directory: directory,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    }
    final file = File('${directory.path}/video${_extensionOf(uri, '.mp4')}');
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
    onProgress(1);
    return OfflineDownloadResult(
      localPath: file.path,
      bytes: await file.length(),
    );
  }

  Future<OfflineDownloadResult> _downloadHls({
    required Uri playlistUri,
    required Map<String, String> headers,
    required Directory directory,
    required CancelToken cancelToken,
    required void Function(double progress) onProgress,
  }) async {
    final text = await _getPlaylistText(
      playlistUri,
      headers: headers,
      cancelToken: cancelToken,
    );
    return _downloadHlsFromText(
      text: text,
      playlistUri: playlistUri,
      headers: headers,
      directory: directory,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  Future<OfflineDownloadResult> _downloadHlsFromText({
    required String text,
    required Uri playlistUri,
    required Map<String, String> headers,
    required Directory directory,
    required CancelToken cancelToken,
    required void Function(double progress) onProgress,
    int depth = 0,
  }) async {
    final parsed = M3u8Playlist.parse(text, playlistUri);
    if (parsed.isMaster) {
      if (depth >= 2) {
        throw const OfflineDownloadException('播放列表层级过深，无法缓存');
      }
      final variant = parsed.pickPreferredVariant();
      if (variant == null) {
        throw const OfflineDownloadException('播放列表中没有可用的清晰度');
      }
      final childText = await _getPlaylistText(
        variant.uri,
        headers: headers,
        cancelToken: cancelToken,
      );
      return _downloadHlsFromText(
        text: childText,
        playlistUri: variant.uri,
        headers: headers,
        directory: directory,
        cancelToken: cancelToken,
        onProgress: onProgress,
        depth: depth + 1,
      );
    }

    if (parsed.mediaUris.isEmpty) {
      throw const OfflineDownloadException('播放列表中没有可缓存的分片');
    }

    final localNames = <String, String>{};
    var keyIndex = 0;
    var mapIndex = 0;
    var segmentIndex = 0;
    for (final item in parsed.mediaUris) {
      final key = item.uri.toString();
      if (localNames.containsKey(key)) continue;
      late final String name;
      switch (item.kind) {
        case 'key':
          name = 'key_$keyIndex.key';
          keyIndex += 1;
        case 'map':
          name = 'init_$mapIndex${_extensionOf(item.uri, '.mp4')}';
          mapIndex += 1;
        default:
          name =
              'seg_${segmentIndex.toString().padLeft(4, '0')}${_extensionOf(item.uri, '.ts')}';
          segmentIndex += 1;
      }
      localNames[key] = name;
    }

    final resources = localNames.entries.toList();
    var completed = 0;
    final total = resources.length;
    await _runLimited(resources, _concurrency, (entry) async {
      _throwIfCancelled(cancelToken);
      final file = File('${directory.path}/${entry.value}');
      await _downloadToFile(
        Uri.parse(entry.key),
        file,
        headers: headers,
        cancelToken: cancelToken,
      );
      completed += 1;
      onProgress((completed / (total + 1)).clamp(0.0, 0.99));
    });

    final index = File('${directory.path}/index.m3u8');
    await index.writeAsString(parsed.rewrite(localNames), flush: true);
    onProgress(1);
    return OfflineDownloadResult(
      localPath: index.path,
      bytes: await _directoryBytes(directory),
    );
  }

  Future<void> _runLimited<T>(
    List<T> items,
    int concurrency,
    Future<void> Function(T item) worker,
  ) async {
    final pending = List<T>.from(items);
    Future<void> run() async {
      while (pending.isNotEmpty) {
        final item = pending.removeAt(0);
        await worker(item);
      }
    }

    final workers = List.generate(
      concurrency.clamp(1, items.isEmpty ? 1 : items.length),
      (_) => run(),
    );
    await Future.wait(workers);
  }

  Future<String> _getPlaylistText(
    Uri uri, {
    required Map<String, String> headers,
    required CancelToken cancelToken,
  }) async {
    final bytes = await _getBytes(
      uri,
      headers: headers,
      cancelToken: cancelToken,
      receiveTimeout: const Duration(seconds: 30),
    );
    if (!_looksLikePlaylist(bytes) && !_looksLikeTextPlaylist(bytes)) {
      throw const OfflineDownloadException('无法解析播放列表');
    }
    return _decodePlaylist(bytes);
  }

  Future<Uint8List> _getBytes(
    Uri uri, {
    required Map<String, String> headers,
    required CancelToken cancelToken,
    Duration? receiveTimeout,
    void Function(int received, int? total)? onReceiveProgress,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      _throwIfCancelled(cancelToken);
      try {
        final response = await _dio.get<List<int>>(
          uri.toString(),
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
          options: Options(
            method: 'GET',
            headers: _headersOf(headers),
            responseType: ResponseType.bytes,
            followRedirects: true,
            receiveTimeout: receiveTimeout,
            validateStatus: (status) => status != null && status >= 200 && status < 300,
          ),
        );
        return Uint8List.fromList(response.data ?? const <int>[]);
      } on DioException catch (e) {
        lastError = e;
        if (e.type == DioExceptionType.cancel) rethrow;
        if (attempt == 2 || !_shouldRetry(e)) {
          throw OfflineDownloadException(_messageFromDio(e));
        }
      } on OfflineDownloadException {
        rethrow;
      } catch (e) {
        lastError = e;
        if (attempt == 2) {
          throw OfflineDownloadException(_messageFromError(e));
        }
      }
    }
    throw OfflineDownloadException(_messageFromError(lastError));
  }

  Future<void> _downloadToFile(
    Uri uri,
    File file, {
    required Map<String, String> headers,
    required CancelToken cancelToken,
    void Function(int received, int? total)? onReceiveProgress,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      _throwIfCancelled(cancelToken);
      try {
        await _dio.download(
          uri.toString(),
          file.path,
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
          options: Options(
            headers: _headersOf(headers),
            followRedirects: true,
            receiveTimeout: const Duration(seconds: 120),
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
        );
        if (!await file.exists() || await file.length() <= 0) {
          throw const OfflineDownloadException('分片下载不完整');
        }
        return;
      } on DioException catch (e) {
        lastError = e;
        if (e.type == DioExceptionType.cancel) rethrow;
        if (attempt == 2 || !_shouldRetry(e)) {
          throw OfflineDownloadException(_messageFromDio(e));
        }
      } on OfflineDownloadException {
        rethrow;
      } catch (e) {
        lastError = e;
        if (attempt == 2) {
          throw OfflineDownloadException(_messageFromError(e));
        }
      }
    }
    throw OfflineDownloadException(_messageFromError(lastError));
  }

  Map<String, String> _headersOf(Map<String, String> headers) {
    return {
      'User-Agent': JsonHttp.defaultUa,
      'Accept': '*/*',
      ...headers,
    };
  }

  bool _shouldRetry(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      default:
        return false;
    }
  }

  void _throwIfCancelled(CancelToken cancelToken) {
    if (cancelToken.isCancelled) {
      throw const OfflineDownloadException('已取消缓存');
    }
  }

  Future<Uint8List> _readPrefix(File file, int length) async {
    final raf = await file.open();
    try {
      final size = await raf.length();
      return await raf.read(size < length ? size : length);
    } finally {
      await raf.close();
    }
  }

  bool _looksLikePlaylist(Uint8List bytes) {
    final body = _maybeGunzip(bytes);
    final start = utf8.decode(body.take(16).toList(), allowMalformed: true).trimLeft();
    return start.startsWith('#EXTM3U');
  }

  bool _looksLikeTextPlaylist(Uint8List bytes) {
    final start = utf8.decode(_maybeGunzip(bytes).take(32).toList(), allowMalformed: true);
    return start.contains('#EXT');
  }

  String _decodePlaylist(Uint8List bytes) {
    final body = _maybeGunzip(bytes);
    return utf8.decode(body);
  }

  Uint8List _maybeGunzip(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        return Uint8List.fromList(gzip.decode(bytes));
      } catch (_) {
        return bytes;
      }
    }
    return bytes;
  }

  String _extensionOf(Uri uri, String fallback) {
    final path = uri.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    final slash = path.lastIndexOf('/');
    if (dot > slash && dot >= 0 && dot < path.length - 1) {
      final ext = path.substring(dot);
      if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) return ext;
    }
    return fallback;
  }

  Future<int> _directoryBytes(Directory directory) async {
    var total = 0;
    if (!await directory.exists()) return 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  String _messageFromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '下载超时，请稍后重试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络后重试';
      case DioExceptionType.badCertificate:
        return '安全证书校验失败';
      case DioExceptionType.badResponse:
        return '缓存失败，服务器返回 ${e.response?.statusCode ?? '异常'}';
      case DioExceptionType.cancel:
        return '已取消缓存';
      case DioExceptionType.unknown:
        final message = e.message ?? e.error?.toString() ?? '';
        if (message.toLowerCase().contains('timeout') ||
            message.contains('timed out')) {
          return '下载超时，请稍后重试';
        }
        if (message.toLowerCase().contains('space') ||
            message.contains('No space')) {
          return '存储空间不足';
        }
        return '缓存失败，请稍后重试';
    }
  }

  String _messageFromError(Object? error) {
    final message = '$error';
    if (message.contains('已取消')) return '已取消缓存';
    if (message.toLowerCase().contains('space') || message.contains('No space')) {
      return '存储空间不足';
    }
    return '缓存失败，请稍后重试';
  }
}
