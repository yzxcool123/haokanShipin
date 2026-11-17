import 'dart:convert';

/// 轻量 m3u8 解析：支持主播放列表、媒体列表、密钥和初始化片段。
class M3u8Playlist {
  const M3u8Playlist({
    required this.playlistUri,
    required this.lines,
    required this.variants,
    required this.mediaUris,
  });

  final Uri playlistUri;
  final List<String> lines;
  final List<M3u8Variant> variants;
  final List<M3u8MediaUri> mediaUris;

  bool get isMaster => variants.isNotEmpty;

  factory M3u8Playlist.parse(String text, Uri playlistUri) {
    final rawLines = const LineSplitter().convert(text.replaceAll('\r\n', '\n'));
    final lines = [for (final line in rawLines) line.trim()];
    final variants = <M3u8Variant>[];
    final mediaUris = <M3u8MediaUri>[];
    final seen = <String>{};

    void addMedia(Uri uri, {required String kind, String? byteRange}) {
      final key = uri.toString();
      if (!seen.add(key)) {
        return;
      }
      mediaUris.add(M3u8MediaUri(uri: uri, kind: kind, byteRange: byteRange));
    }

    Map<String, String>? pendingStreamInf;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        pendingStreamInf = _parseAttributes(line.substring('#EXT-X-STREAM-INF:'.length));
        continue;
      }
      if (line.startsWith('#EXT-X-I-FRAME-STREAM-INF:')) {
        // 关键帧预览流不用于离线观看。
        continue;
      }
      if (line.startsWith('#EXT-X-KEY:') || line.startsWith('#EXT-X-SESSION-KEY:')) {
        final prefix = line.startsWith('#EXT-X-KEY:')
            ? '#EXT-X-KEY:'
            : '#EXT-X-SESSION-KEY:';
        final attrs = _parseAttributes(line.substring(prefix.length));
        final uriValue = attrs['URI'];
        if (uriValue != null && uriValue.isNotEmpty) {
          addMedia(playlistUri.resolve(uriValue), kind: 'key');
        }
        continue;
      }
      if (line.startsWith('#EXT-X-MAP:')) {
        final attrs = _parseAttributes(line.substring('#EXT-X-MAP:'.length));
        final uriValue = attrs['URI'];
        if (uriValue != null && uriValue.isNotEmpty) {
          addMedia(
            playlistUri.resolve(uriValue),
            kind: 'map',
            byteRange: attrs['BYTERANGE'],
          );
        }
        continue;
      }
      if (line.startsWith('#')) continue;

      final uri = playlistUri.resolve(line);
      if (pendingStreamInf != null) {
        variants.add(M3u8Variant(
          uri: uri,
          bandwidth: int.tryParse(pendingStreamInf['BANDWIDTH'] ?? '') ?? 0,
          averageBandwidth:
              int.tryParse(pendingStreamInf['AVERAGE-BANDWIDTH'] ?? '') ?? 0,
          width: _resolution(pendingStreamInf['RESOLUTION'])?.$1,
          height: _resolution(pendingStreamInf['RESOLUTION'])?.$2,
        ));
        pendingStreamInf = null;
        continue;
      }

      String? byteRange;
      for (var j = i - 1; j >= 0; j--) {
        final prev = lines[j];
        if (prev.isEmpty) continue;
        if (prev.startsWith('#EXT-X-BYTERANGE:')) {
          byteRange = prev.substring('#EXT-X-BYTERANGE:'.length).trim();
        }
        break;
      }
      addMedia(uri, kind: 'segment', byteRange: byteRange);
    }

    return M3u8Playlist(
      playlistUri: playlistUri,
      lines: lines,
      variants: variants,
      mediaUris: mediaUris,
    );
  }

  /// 主播放列表优先选接近 720p 的变体；没有分辨率时选次高或中等带宽。
  M3u8Variant? pickPreferredVariant() {
    if (variants.isEmpty) return null;
    final withResolution = [
      for (final item in variants)
        if (item.width != null && item.height != null) item,
    ];
    if (withResolution.isNotEmpty) {
      withResolution.sort((a, b) {
        final da = (a.width! - 1280).abs() + (a.height! - 720).abs();
        final db = (b.width! - 1280).abs() + (b.height! - 720).abs();
        final compared = da.compareTo(db);
        if (compared != 0) return compared;
        return a.bandwidth.compareTo(b.bandwidth);
      });
      return withResolution.first;
    }

    final sorted = [...variants]
      ..sort((a, b) => a.effectiveBandwidth.compareTo(b.effectiveBandwidth));
    if (sorted.length >= 3) return sorted[sorted.length - 2];
    if (sorted.length == 2) return sorted.first;
    return sorted.first;
  }

  String rewrite(Map<String, String> localNames) {
    final out = StringBuffer();
    Map<String, String>? pendingStreamInf;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        pendingStreamInf = _parseAttributes(line.substring('#EXT-X-STREAM-INF:'.length));
        continue;
      }
      if (line.startsWith('#EXT-X-I-FRAME-STREAM-INF:')) {
        continue;
      }
      if (line.startsWith('#EXT-X-KEY:') ||
          line.startsWith('#EXT-X-SESSION-KEY:') ||
          line.startsWith('#EXT-X-MAP:')) {
        out.writeln(_replaceUriAttribute(line, localNames));
        continue;
      }
      if (line.startsWith('#') || line.isEmpty) {
        out.writeln(line);
        pendingStreamInf = null;
        continue;
      }
      if (pendingStreamInf != null) {
        // 离线时只保留选中的媒体列表，主播放列表不会写回本地。
        pendingStreamInf = null;
        continue;
      }
      final absolute = playlistUri.resolve(line).toString();
      out.writeln(localNames[absolute] ?? line);
    }
    return out.toString();
  }

  String _replaceUriAttribute(String line, Map<String, String> localNames) {
    return line.replaceAllMapped(RegExp(r'URI=("([^"]*)"|[^,]*)'), (match) {
      final quoted = match.group(2);
      final raw = (quoted ?? match.group(1) ?? '').trim();
      if (raw.isEmpty) return match.group(0)!;
      final absolute = playlistUri.resolve(raw).toString();
      final local = localNames[absolute];
      if (local == null) return match.group(0)!;
      return 'URI="$local"';
    });
  }

  static Map<String, String> _parseAttributes(String raw) {
    final attrs = <String, String>{};
    final regex = RegExp(r'([A-Z0-9-]+)=("([^"]*)"|[^,]*)');
    for (final match in regex.allMatches(raw)) {
      final key = match.group(1);
      if (key == null) continue;
      final quoted = match.group(3);
      final value = (quoted ?? match.group(2) ?? '').trim();
      attrs[key] = value;
    }
    return attrs;
  }

  static (int, int)? _resolution(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.toLowerCase().split('x');
    if (parts.length != 2) return null;
    final width = int.tryParse(parts[0]);
    final height = int.tryParse(parts[1]);
    if (width == null || height == null) return null;
    return (width, height);
  }
}

class M3u8Variant {
  const M3u8Variant({
    required this.uri,
    required this.bandwidth,
    this.averageBandwidth = 0,
    this.width,
    this.height,
  });

  final Uri uri;
  final int bandwidth;
  final int averageBandwidth;
  final int? width;
  final int? height;

  int get effectiveBandwidth =>
      bandwidth > 0 ? bandwidth : averageBandwidth;
}

class M3u8MediaUri {
  const M3u8MediaUri({
    required this.uri,
    required this.kind,
    this.byteRange,
  });

  final Uri uri;
  final String kind;
  final String? byteRange;
}
