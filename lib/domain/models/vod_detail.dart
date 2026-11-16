import 'playable.dart';
import 'vod_item.dart';

class VodDetail {
  const VodDetail({
    required this.item,
    this.lines = const [],
    this.content = '',
    this.year = '',
    this.actor = '',
  });

  final VodItem item;
  final List<PlayLine> lines;
  final String content;
  final String year;
  final String actor;

  List<Episode> get firstEpisodes =>
      lines.isEmpty ? const [] : lines.first.episodes;
}
