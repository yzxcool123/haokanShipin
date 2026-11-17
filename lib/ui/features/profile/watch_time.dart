import '../../../domain/models/watch_record.dart';

String formatWatchClock(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds.clamp(0, 1 << 31));
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

String formatWatchAge(int updatedAtMs) {
  if (updatedAtMs <= 0) return '';
  final watched = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final now = DateTime.now();
  final diff = now.difference(watched);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24 && now.day == watched.day) {
    return '${diff.inHours}小时前';
  }
  final yesterday = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1));
  if (watched.isAfter(yesterday) &&
      watched.isBefore(DateTime(now.year, now.month, now.day))) {
    return '昨天';
  }
  final month = watched.month.toString().padLeft(2, '0');
  final day = watched.day.toString().padLeft(2, '0');
  if (now.year == watched.year) return '$month-$day';
  return '${watched.year}-$month-$day';
}

String formatWatchSubtitle(WatchRecord record) {
  final parts = <String>[];
  if (record.sourceName.isNotEmpty) parts.add(record.sourceName);
  if (record.episodeTitle.isNotEmpty) parts.add(record.episodeTitle);
  if (record.isFinished) {
    parts.add('已看完');
  } else if (record.positionMs > 0) {
    parts.add('看到 ${formatWatchClock(record.positionMs)}');
  }
  final age = formatWatchAge(record.updatedAtMs);
  if (age.isNotEmpty) parts.add(age);
  return parts.join(' · ');
}
