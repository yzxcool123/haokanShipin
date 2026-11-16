import '../../domain/models/playable.dart';

/// 兼容两种播放地址：
/// 1. 裸链接，如 https://host/index.m3u8
/// 2. 采集站分集格式：线路用 $$$ 分隔，分集用 # 分隔，标题和地址用 $ 分隔
List<PlayLine> parsePlayUrls({
  required String playFrom,
  required String playUrl,
}) {
  final raw = playUrl.trim();
  if (raw.isEmpty) return const [];

  final isPlainUrl = raw.startsWith('http') &&
      !raw.contains('\$') &&
      !raw.contains('#') &&
      !raw.contains('\$\$\$');
  if (isPlainUrl) {
    final name = playFrom.trim().isEmpty
        ? '默认'
        : playFrom.split('\$\$\$').first.trim();
    return [
      PlayLine(
        name: name.isEmpty ? '默认' : name,
        episodes: [Episode(id: '1', title: '播放', url: raw)],
      ),
    ];
  }

  final froms = playFrom.split('\$\$\$');
  final groups = raw.split('\$\$\$');
  final lines = <PlayLine>[];
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    if (group.trim().isEmpty) continue;
    final name = (i < froms.length && froms[i].trim().isNotEmpty)
        ? froms[i].trim()
        : '线路${i + 1}';
    final episodes = <Episode>[];
    final parts = group.split('#');
    for (var j = 0; j < parts.length; j++) {
      final part = parts[j].trim();
      if (part.isEmpty) continue;
      if (part.contains('\$')) {
        final idx = part.indexOf('\$');
        final title = part.substring(0, idx).trim();
        final url = part.substring(idx + 1).trim();
        if (url.isEmpty) continue;
        episodes.add(Episode(
          id: '${j + 1}',
          title: title.isEmpty ? '第${j + 1}集' : title,
          url: url,
        ));
      } else if (part.startsWith('http')) {
        episodes.add(Episode(id: '${j + 1}', title: '第${j + 1}集', url: part));
      }
    }
    if (episodes.isNotEmpty) {
      lines.add(PlayLine(name: name, episodes: episodes));
    }
  }
  return lines;
}
