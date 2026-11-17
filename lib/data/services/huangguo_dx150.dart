import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'api_exception.dart';

class HuangguoDxPlay {
  const HuangguoDxPlay({
    required this.url,
    this.hevc = '',
    this.cdn,
  });

  final String url;
  final String hevc;
  final Map<String, dynamic>? cdn;
}

/// 源站 dx150-edge-v1：ECDH P-256 + HKDF-SHA256 + AES-GCM。
/// 内层播放请求：POST /api/videos/{id}/episodes/{ep}/playback
class HuangguoDx150 {
  HuangguoDx150({
    required String Function() siteOf,
    required Future<Map<String, dynamic>> Function(
      String path,
      Map<String, Object?> body,
    ) post,
  })  : _siteOf = siteOf,
        _postSite = post;

  final String Function() _siteOf;
  final Future<Map<String, dynamic>> Function(
    String path,
    Map<String, Object?> body,
  ) _postSite;

  String get site => _siteOf();

  static const _protocol = 'dx150-edge-v1';
  static const _endpoints = {
    'user': '/api/user/request',
    'playback': '/api/playback/request',
    'public': '/api/public/request',
    'dynamic': '/api/dynamic/request',
  };

  final Map<String, _DxSession> _sessions = {};

  Future<HuangguoDxPlay?> play(String id, String ep) async {
    if (id.isEmpty || ep.isEmpty) return null;
    final packet = _packet(
      'POST',
      '/api/videos/$id/episodes/$ep/playback',
      const {},
    );
    try {
      return _parsePlay(await _call('playback', packet));
    } catch (_) {
      _sessions.remove('playback');
      try {
        return _parsePlay(await _call('playback', packet));
      } catch (_) {
        return null;
      }
    }
  }

  HuangguoDxPlay? _parsePlay(_DxResponse r) {
    if (r.status != 200) return null;
    final decoded = jsonDecode(r.body);
    if (decoded is! Map) return null;
    final data = decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : decoded;
    final streams = data['streams'] is Map
        ? Map<String, dynamic>.from(data['streams'] as Map)
        : const <String, dynamic>{};
    final url = '${streams['main'] ?? streams['preview'] ?? ''}';
    if (url.isEmpty) return null;
    return HuangguoDxPlay(
      url: url,
      hevc: '${streams['hevc'] ?? ''}',
      cdn: data['cdn'] is Map
          ? Map<String, dynamic>.from(data['cdn'] as Map)
          : null,
    );
  }

  Future<_DxResponse> _call(String scope, Map<String, String> packet) async {
    var session = _sessions[scope];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (session == null || session.exp <= now + 5) {
      session = await _open(scope);
    }
    final seq = ++session.seq;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000 + session.off;
    final iv = _nonce(seq);
    final plain = utf8.encode(jsonEncode({'request': packet}));
    final ciphertext = _aesGcm(
      encrypt: true,
      key: session.reqKey,
      iv: iv,
      aad: utf8.encode([session.info, 'req', seq, ts].join('\n')),
      data: Uint8List.fromList(plain),
    );
    final json = await _post(scope, {
      'v': 1,
      'type': 'call',
      'kid': session.kid,
      'sid': session.sid,
      'seq': seq,
      'ts': ts,
      'ciphertext': _b64url(ciphertext),
    });
    final enc = json['ciphertext'];
    if (enc is! String || enc.isEmpty) {
      _sessions.remove(scope);
      throw ApiException('播放通道返回异常。');
    }
    final opened = utf8.decode(
      _aesGcm(
        encrypt: false,
        key: session.resKey,
        iv: iv,
        aad: utf8.encode([session.info, 'res', seq, ts].join('\n')),
        data: _unb64url(enc),
      ),
    );
    final inner = jsonDecode(opened);
    if (inner is! Map) {
      throw ApiException('播放通道返回异常。');
    }
    final status = inner['status'] is int
        ? inner['status'] as int
        : int.tryParse('${inner['status']}') ?? 0;
    final bodyRaw = inner['body'];
    final body = bodyRaw is String ? utf8.decode(_unb64(bodyRaw)) : '';
    return _DxResponse(status: status, body: body);
  }

  Future<_DxSession> _open(String scope) async {
    final domain = ECDomainParameters('prime256v1');
    final keyPair = _generateKeyPair(domain);
    final priv = keyPair.privateKey as ECPrivateKey;
    final pub = keyPair.publicKey as ECPublicKey;
    final hello = await _post(scope, {
      'v': 1,
      'type': 'hello',
      'client_pub': _b64url(_rawPublic(pub)),
    });
    if (hello['v'] != 1 || hello['type'] != 'hello') {
      throw ApiException('播放通道握手失败。');
    }
    final serverPub = hello['server_pub'];
    final saltValue = hello['salt'];
    if (serverPub is! String || saltValue is! String) {
      throw ApiException('播放通道握手失败。');
    }
    final shared = _sharedSecret(priv, _unb64url(serverPub));
    final salt = _unb64url(saltValue);
    final siteName = '${hello['site'] ?? ''}';
    final kid = '${hello['kid'] ?? ''}';
    final sid = '${hello['sid'] ?? ''}';
    final info = [_protocol, scope, siteName, kid, sid].join('\n');
    final reqKey = _hkdf(shared, salt, utf8.encode('$info\nreq'), 32);
    final resKey = _hkdf(shared, salt, utf8.encode('$info\nres'), 32);
    final local = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final serverTime = _asInt(hello['server_time'], local);
    final expiresAt = _asInt(hello['expires_at'], local + 300);
    final session = _DxSession(
      info: info,
      kid: kid,
      sid: sid,
      off: serverTime - local,
      exp: local + expiresAt - serverTime,
      reqKey: reqKey,
      resKey: resKey,
    );
    _sessions[scope] = session;
    return session;
  }

  Future<Map<String, dynamic>> _post(String scope, Map<String, Object?> body) {
    final path = _endpoints[scope];
    if (path == null) {
      throw ApiException('未知的播放通道。');
    }
    return _postSite(path, body);
  }

  static Map<String, String> _packet(String method, String path, Object? obj) {
    final bytes = utf8.encode(obj == null ? '' : jsonEncode(obj));
    return {
      'method': method,
      'path': path,
      'body': base64Encode(bytes),
      'content_type': obj == null ? '' : 'application/json',
      'visitor_id': '',
    };
  }

  static AsymmetricKeyPair<PublicKey, PrivateKey> _generateKeyPair(
    ECDomainParameters domain,
  ) {
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(
          ECKeyGeneratorParameters(domain), _secureRandom()));
    return gen.generateKeyPair();
  }

  static SecureRandom _secureRandom() {
    final rnd = FortunaRandom();
    final seed = Uint8List(32);
    final r = Random.secure();
    for (var i = 0; i < seed.length; i++) {
      seed[i] = r.nextInt(256);
    }
    rnd.seed(KeyParameter(seed));
    return rnd;
  }

  static Uint8List _rawPublic(ECPublicKey key) {
    final q = key.Q!;
    return Uint8List.fromList([
      0x04,
      ..._i2osp(q.x!.toBigInteger()!, 32),
      ..._i2osp(q.y!.toBigInteger()!, 32),
    ]);
  }

  static Uint8List _sharedSecret(ECPrivateKey priv, Uint8List serverRaw) {
    final domain = priv.parameters!;
    final point = domain.curve.decodePoint(serverRaw);
    if (point == null) {
      throw ApiException('播放通道握手失败。');
    }
    final agreement = ECDHBasicAgreement()..init(priv);
    return _i2osp(agreement.calculateAgreement(ECPublicKey(point, domain)), 32);
  }

  static Uint8List _hkdf(
      Uint8List ikm, Uint8List salt, List<int> info, int length) {
    final hkdf = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(ikm, length, salt, Uint8List.fromList(info)));
    final out = Uint8List(length);
    hkdf.deriveKey(Uint8List(0), 0, out, 0);
    return out;
  }

  static Uint8List _aesGcm({
    required bool encrypt,
    required Uint8List key,
    required Uint8List iv,
    required List<int> aad,
    required Uint8List data,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List.fromList(aad)),
      );
    final out = Uint8List(cipher.getOutputSize(data.length));
    var off = cipher.processBytes(data, 0, data.length, out, 0);
    off += cipher.doFinal(out, off);
    return off == out.length ? out : Uint8List.sublistView(out, 0, off);
  }

  static Uint8List _nonce(int seq) {
    final b = Uint8List(12);
    b[8] = (seq >> 24) & 0xff;
    b[9] = (seq >> 16) & 0xff;
    b[10] = (seq >> 8) & 0xff;
    b[11] = seq & 0xff;
    return b;
  }

  static Uint8List _i2osp(BigInt value, int size) {
    final out = Uint8List(size);
    var n = value;
    for (var i = size - 1; i >= 0 && n > BigInt.zero; i--) {
      out[i] = (n & BigInt.from(0xff)).toInt();
      n = n >> 8;
    }
    return out;
  }

  static String _b64url(Uint8List bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Uint8List _unb64url(String value) {
    var s = value.replaceAll('-', '+').replaceAll('_', '/');
    final pad = (4 - s.length % 4) % 4;
    s += '=' * pad;
    return Uint8List.fromList(base64Decode(s));
  }

  static Uint8List _unb64(String value) =>
      Uint8List.fromList(base64Decode(value));

  static int _asInt(Object? value, int fallback) {
    if (value is int) return value;
    return int.tryParse('$value') ?? fallback;
  }
}

class _DxSession {
  _DxSession({
    required this.info,
    required this.kid,
    required this.sid,
    required this.off,
    required this.exp,
    required this.reqKey,
    required this.resKey,
  });

  final String info;
  final String kid;
  final String sid;
  final int off;
  final int exp;
  int seq = 0;
  final Uint8List reqKey;
  final Uint8List resKey;
}

class _DxResponse {
  const _DxResponse({required this.status, required this.body});

  final int status;
  final String body;
}
