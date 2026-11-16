import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

class JsonHttp {
  JsonHttp({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const defaultUa =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

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
    final reqHeaders = <String, String>{
      'User-Agent': defaultUa,
      'Accept': 'application/json, text/plain, */*',
      ...?headers,
    };
    http.Response response;
    try {
      if (method.toUpperCase() == 'POST') {
        final encoded = body is String ? body : jsonEncode(body ?? {});
        reqHeaders.putIfAbsent('Content-Type', () => 'application/json');
        response = await _client
            .post(uri, headers: reqHeaders, body: encoded)
            .timeout(timeout);
      } else {
        response = await _client.get(uri, headers: reqHeaders).timeout(timeout);
      }
    } on TimeoutException {
      throw ApiException('请求超时，请稍后重试。');
    } catch (e) {
      throw ApiException('网络请求失败：$e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('接口返回 ${response.statusCode}');
    }

    final text = utf8.decode(response.bodyBytes).trim();
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
}
