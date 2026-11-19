import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/services/huangguo_cover_codec.dart';
import '../../../data/services/json_http.dart';

class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    this.sourceKey = '',
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String url;
  final String sourceKey;
  final BoxFit fit;
  final int? cacheWidth;

  /// 三列封面网格按屏幕宽度和像素密度算出的解码宽度，避免原图过大导致滑动掉帧。
  static int cacheWidthForGrid(
    BuildContext context, {
    int crossAxisCount = 3,
    double horizontalPadding = 24,
    double crossSpacing = 10,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cardWidth =
        (width - horizontalPadding - crossSpacing * (crossAxisCount - 1)) /
            crossAxisCount;
    return (cardWidth * dpr).round().clamp(1, 2048);
  }

  static bool shouldDecrypt(String sourceKey, String url) {
    if (sourceKey == 'huangguo_web') return true;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.endsWith('drleao.cn');
  }

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF2A2B31),
        child: Icon(Icons.movie_outlined, size: 36),
      );
    }
    if (shouldDecrypt(sourceKey, url)) {
      ImageProvider provider = HuangguoCoverImage(url: url);
      final cacheWidth = this.cacheWidth;
      if (cacheWidth != null) {
        provider = ResizeImage(provider, width: cacheWidth);
      }
      return Image(
        image: provider,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Color(0xFF2A2B31),
          child: Icon(Icons.movie_outlined, size: 36),
        ),
        frameBuilder: (context, child, frame, sync) {
          if (sync || frame != null) return child;
          return const ColoredBox(color: Color(0xFF2A2B31));
        },
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      memCacheWidth: cacheWidth,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      filterQuality: FilterQuality.low,
      placeholder: (_, __) => const ColoredBox(color: Color(0xFF2A2B31)),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0xFF2A2B31),
        child: Icon(Icons.movie_outlined, size: 36),
      ),
    );
  }
}

class HuangguoCoverImage extends ImageProvider<HuangguoCoverImage> {
  const HuangguoCoverImage({required this.url});

  final String url;

  @override
  Future<HuangguoCoverImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    HuangguoCoverImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
      debugLabel: 'HuangguoCoverImage',
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await HuangguoCoverLoader.load(url);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is HuangguoCoverImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

class HuangguoCoverLoader {
  static final JsonHttp _http = JsonHttp();
  static final Map<String, Uint8List> _cache = {};
  static final Map<String, Future<Uint8List>> _inflight = {};
  static const _max = 80;
  static const _referer = 'https://huangguoai.io/';

  static Future<Uint8List> load(String url) {
    final cached = _cache[url];
    if (cached != null) return SynchronousFuture(cached);
    return _inflight.putIfAbsent(url, () async {
      try {
        final bytes = await _http.getBytes(
          Uri.parse(url),
          headers: {
            'User-Agent': JsonHttp.defaultUa,
            'Referer': _referer,
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          },
        );
        final decoded = await _CoverDecryptIsolate.decode(bytes);
        if (_cache.length >= _max) {
          _cache.remove(_cache.keys.first);
        }
        _cache[url] = decoded;
        return decoded;
      } finally {
        _inflight.remove(url);
      }
    });
  }
}

class _CoverDecryptIsolate {
  static SendPort? _port;
  static Future<SendPort>? _starting;
  static int _nextId = 0;
  static final Map<int, Completer<Uint8List>> _pending = {};
  static final RawReceivePort _reply = RawReceivePort(_onMessage);

  static Future<Uint8List> decode(Uint8List bytes) async {
    final port = _port ?? await (_starting ??= _start());
    final id = _nextId++;
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    port.send(<dynamic>[id, bytes]);
    return completer.future;
  }

  static Future<SendPort> _start() async {
    final ready = ReceivePort();
    await Isolate.spawn(
      _huangguoCoverIsolateMain,
      ready.sendPort,
      debugName: 'huangguo-cover-decrypt',
    );
    final port = await ready.first as SendPort;
    ready.close();
    port.send(_reply.sendPort);
    _port = port;
    return port;
  }

  static void _onMessage(dynamic message) {
    final list = message as List<dynamic>;
    final id = list[0] as int;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    final error = list[2] as String?;
    if (error != null) {
      completer.completeError(StateError(error));
    } else {
      completer.complete(list[1] as Uint8List);
    }
  }
}

void _huangguoCoverIsolateMain(SendPort ready) {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);
  SendPort? reply;
  inbox.listen((message) {
    if (reply == null) {
      reply = message as SendPort;
      return;
    }
    final list = message as List<dynamic>;
    final id = list[0] as int;
    final bytes = list[1] as Uint8List;
    try {
      reply!.send(<dynamic>[id, _decodeCover(bytes), null]);
    } catch (e) {
      reply!.send(<dynamic>[id, null, e.toString()]);
    }
  });
}

Uint8List _decodeCover(Uint8List bytes) {
  if (HuangguoCoverCodec.isImage(bytes)) return bytes;
  final plain = HuangguoCoverCodec.decrypt(bytes);
  if (plain != null && HuangguoCoverCodec.isImage(plain)) return plain;
  throw StateError('cover is not an image');
}
