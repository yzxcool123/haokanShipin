import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 给所有 dart:io HttpClient 接上自定义解析，避免系统 DNS 把域名指到无效地址。
class DohHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = DohResolver.instance.startConnect;
    return client;
  }
}

/// 用国内可访问的 DoH 解析被污染的域名，并在多次请求间轮换 IP。
class DohResolver {
  DohResolver() : _client = _createBootstrapClient();

  static final DohResolver instance = DohResolver();

  static const poisonedHosts = {
    'huangguoai.io',
    'huangguoai.com',
    'huangguoai.ai',
  };

  static bool shouldUseDoh(String host) {
    return poisonedHosts.contains(host) ||
        host == 'workers.dev' ||
        host.endsWith('.workers.dev');
  }

  static const _dohEndpoints = [
    'https://dns.alidns.com/resolve',
    'https://doh.pub/dns-query',
  ];

  static const _pinnedHosts = {
    'dns.alidns.com': ['223.5.5.5', '223.6.6.6'],
    'doh.pub': ['1.12.12.12', '120.53.53.53'],
  };

  final HttpClient _client;
  final Map<String, _Cache> _cache = {};
  final Map<String, int> _cursors = {};

  static HttpClient _createBootstrapClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);
    client.idleTimeout = const Duration(seconds: 10);
    client.connectionFactory = (uri, _, __) {
      return instance._connectHost(uri, allowSystemDns: false);
    };
    return client;
  }

  Future<ConnectionTask<Socket>> startConnect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) {
    final host = uri.host;
    final bypassProxy = shouldUseDoh(host) || _pinnedHosts.containsKey(host);
    if (proxyHost != null && proxyPort != null && !bypassProxy) {
      return Socket.startConnect(proxyHost, proxyPort);
    }
    return _connectHost(uri, allowSystemDns: true);
  }

  Future<ConnectionTask<Socket>> _connectHost(
    Uri uri, {
    required bool allowSystemDns,
  }) async {
    final host = uri.host;
    if (host.isEmpty) {
      throw SocketException('缺少主机名：$uri');
    }

    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      return _startSocket(literal, uri, sni: host);
    }

    final ips = await _resolve(host, allowSystemDns: allowSystemDns);
    if (ips.isEmpty) {
      throw SocketException('无法解析 $host');
    }
    final index = _cursors[host] ?? 0;
    _cursors[host] = index + 1;
    final ordered = [
      for (var i = 0; i < ips.length; i++) ips[(index + i) % ips.length],
    ];
    if (ordered.length == 1) {
      if (kDebugMode) {
        debugPrint('连接 $host -> ${ordered.first.address}');
      }
      return _startSocket(ordered.first, uri, sni: host);
    }
    final socket = await _raceSockets(ordered, uri, host);
    return ConnectionTask.fromSocket(Future<Socket>.value(socket), socket.destroy);
  }

  Future<Socket> _raceSockets(
    List<InternetAddress> ips,
    Uri uri,
    String sni,
  ) {
    final completer = Completer<Socket>();
    final pending = <ConnectionTask<Socket>>[];
    var remaining = ips.length;

    Future<void> attempt(InternetAddress ip) async {
      if (completer.isCompleted) return;
      if (kDebugMode) {
        debugPrint('连接 $sni -> ${ip.address}');
      }
      try {
        final task = await _startSocket(ip, uri, sni: sni);
        pending.add(task);
        final socket = await task.socket.timeout(const Duration(seconds: 5));
        if (completer.isCompleted) {
          socket.destroy();
          return;
        }
        completer.complete(socket);
        for (final other in pending) {
          if (!identical(other, task)) {
            other.cancel();
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('连接失败 $sni ${ip.address} -> $e');
        }
        remaining--;
        if (remaining <= 0 && !completer.isCompleted) {
          completer.completeError(e);
        }
      }
    }

    for (var i = 0; i < ips.length; i++) {
      final ip = ips[i];
      Future<void>.delayed(Duration(milliseconds: i * 180), () => attempt(ip));
    }
    return completer.future;
  }

  Future<List<InternetAddress>> _resolve(
    String host, {
    required bool allowSystemDns,
  }) async {
    final pinned = _pinnedHosts[host];
    if (pinned != null) {
      return [
        for (final item in pinned) InternetAddress(item),
      ];
    }
    final mustUseDoh = shouldUseDoh(host) || await isSystemLookupPoisoned(host);
    if (mustUseDoh) {
      return lookup(host);
    }
    if (!allowSystemDns) {
      return lookup(host);
    }
    return InternetAddress.lookup(host);
  }

  Future<ConnectionTask<Socket>> _startSocket(
    Object host,
    Uri uri, {
    required String sni,
  }) async {
    final port = uri.port == 0 ? (uri.isScheme('https') ? 443 : 80) : uri.port;
    if (!uri.isScheme('https')) {
      return Socket.startConnect(host, port);
    }
    final rawTask = await Socket.startConnect(host, port);
    final tlsFuture = rawTask.socket.then((raw) {
      return SecureSocket.secure(
        raw,
        host: sni,
        supportedProtocols: const ['http/1.1'],
      );
    });
    return ConnectionTask.fromSocket<Socket>(tlsFuture, rawTask.cancel);
  }

  Future<bool> isSystemLookupPoisoned(String host) async {
    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) return true;
      return addresses.every(isPoisonedAddress);
    } catch (_) {
      return true;
    }
  }

  static bool isPoisonedAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return true;
    }
    final raw = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && raw.length == 4) {
      if (raw.every((b) => b == 0)) return true;
    }
    return false;
  }

  Future<List<InternetAddress>> lookup(String host) async {
    final cached = _cache[host];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.addresses;
    }
    Object? last;
    for (final endpoint in _dohEndpoints) {
      try {
        final result = await _query(endpoint, host);
        if (result.addresses.isNotEmpty) {
          final ttl = result.ttl.clamp(30, 300);
          _cache[host] = _Cache(
            result.addresses,
            DateTime.now().add(Duration(seconds: ttl)),
          );
          if (kDebugMode) {
            debugPrint(
              'DoH $host -> ${result.addresses.map((e) => e.address).join(", ")}',
            );
          }
          return result.addresses;
        }
      } catch (e) {
        last = e;
        if (kDebugMode) {
          debugPrint('DoH 查询失败 $endpoint $host -> $e');
        }
      }
    }
    if (cached != null) return cached.addresses;
    throw SocketException('无法解析 $host${last == null ? '' : '：$last'}');
  }

  Future<({List<InternetAddress> addresses, int ttl})> _query(
    String endpoint,
    String host,
  ) async {
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {'name': host, 'type': 'A'},
    );
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
    final response = await request.close().timeout(const Duration(seconds: 6));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw SocketException('DoH ${response.statusCode}');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('DoH 响应无效');
    }
    final answers = decoded['Answer'];
    final addresses = <InternetAddress>[];
    var ttl = 60;
    if (answers is List) {
      for (final item in answers) {
        if (item is! Map) continue;
        if (_asInt(item['type']) != 1) continue;
        final data = item['data']?.toString() ?? '';
        final ip = InternetAddress.tryParse(data);
        if (ip == null || isPoisonedAddress(ip)) continue;
        addresses.add(ip);
        final itemTtl = _asInt(item['TTL']);
        if (itemTtl != null && itemTtl > 0) {
          ttl = itemTtl < ttl ? itemTtl : ttl;
        }
      }
    }
    return (addresses: addresses, ttl: ttl);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class _Cache {
  const _Cache(this.addresses, this.expires);
  final List<InternetAddress> addresses;
  final DateTime expires;
}
