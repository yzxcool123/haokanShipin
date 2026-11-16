import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_exception.dart';

class JsonHttp {
  JsonHttp({Dio? client}) : _client = client ?? createDefaultClient();

  final Dio _client;

  static const defaultUa =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static Dio createDefaultClient() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'User-Agent': defaultUa,
          'Accept': 'application/json, text/plain, */*',
        },
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );
  }

  Future<Map<String, dynamic>> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) {
    return send(uri, method: 'GET', headers: headers, timeout: timeout);
  }

  Future<Map<String, dynamic>> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) {
    return send(
      uri,
      method: 'POST',
      headers: headers,
      body: body,
      timeout: timeout,
    );
  }

  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final reqHeaders = <String, dynamic>{
      'User-Agent': defaultUa,
      'Accept': 'application/json, text/plain, */*',
      ...?headers,
    };

    try {
      final response = await _client.request<List<int>>(
        uri.toString(),
        data: method.toUpperCase() == 'POST'
            ? (body is String ? body : jsonEncode(body ?? {}))
            : null,
        options: Options(
          method: method,
          headers: reqHeaders,
          contentType: method.toUpperCase() == 'POST' ? Headers.jsonContentType : null,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          responseType: ResponseType.bytes,
        ),
      );
      return _parseBody(response);
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      final error = _fromDio(e);
      if (kDebugMode) {
        debugPrint('请求失败 ${uri.toString()} -> ${error.message}');
      }
      throw error;
    } catch (e) {
      throw ApiException('网络请求失败：$e');
    }
  }

  Map<String, dynamic> _parseBody(Response<List<int>> response) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiException('接口返回 $status');
    }

    final bytes = _maybeGunzip(response.data ?? const <int>[]);
    final text = utf8.decode(bytes).trim();
    if (text.isEmpty) {
      throw ApiException('接口返回为空。');
    }
    if (!(text.startsWith('{') || text.startsWith('['))) {
      throw ApiException('接口没有返回 JSON 数据。');
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw ApiException('接口数据结构不符合预期。');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('无法解析接口返回的 JSON。');
    }
  }

  List<int> _maybeGunzip(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      return gzip.decode(bytes);
    }
    return bytes;
  }

  ApiException _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException('请求超时，请稍后重试。');
      case DioExceptionType.connectionError:
        return ApiException('网络连接失败，请检查网络后重试。');
      case DioExceptionType.badCertificate:
        return ApiException('安全证书校验失败。');
      case DioExceptionType.badResponse:
        return ApiException('接口返回 ${e.response?.statusCode ?? '异常'}');
      case DioExceptionType.cancel:
        return ApiException('请求已取消。');
      case DioExceptionType.unknown:
        final message = e.message ?? e.error?.toString() ?? '';
        if (message.contains('timed out') || message.contains('Timeout')) {
          return ApiException('请求超时，请稍后重试。');
        }
        return ApiException(message.isEmpty ? '网络请求失败。' : '网络请求失败：$message');
    }
  }
}
