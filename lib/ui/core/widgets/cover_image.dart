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
  });

  final String url;
  final String sourceKey;
  final BoxFit fit;

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
      return Image(
        image: HuangguoCoverImage(url: url),
        fit: fit,
        gaplessPlayback: true,
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
      errorWidget: (_, __, ___) => const Icon(Icons.movie_outlined, size: 36),
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
  ImageStreamCompleter loadImage(HuangguoCoverImage key, ImageDecoderCallback decode) {
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
  bool operator ==(Object other) => other is HuangguoCoverImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

class HuangguoCoverLoader {
  static final JsonHttp _http = JsonHttp();
  static final Map<String, Uint8List> _cache = {};
  static const _max = 80;
  static const _referer = 'https://huangguoai.io/';

  static Future<Uint8List> load(String url) async {
    final cached = _cache[url];
    if (cached != null) return cached;
    final bytes = await _http.getBytes(
      Uri.parse(url),
      headers: {
        'User-Agent': JsonHttp.defaultUa,
        'Referer': _referer,
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      },
    );
    final decoded = bytes.length > 1024 * 1024
        ? await compute(_decodeCover, bytes)
        : _decodeCover(bytes);
    if (_cache.length >= _max) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = decoded;
    return decoded;
  }
}

Uint8List _decodeCover(Uint8List bytes) {
  if (HuangguoCoverCodec.isImage(bytes)) return bytes;
  final plain = HuangguoCoverCodec.decrypt(bytes);
  if (plain != null && HuangguoCoverCodec.isImage(plain)) return plain;
  throw StateError('cover is not an image');
}
