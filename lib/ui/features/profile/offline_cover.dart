import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/models/offline_cache_item.dart';
import '../../core/widgets/cover_image.dart';

class OfflineCover extends StatelessWidget {
  const OfflineCover({
    super.key,
    required this.item,
    this.width,
    this.height,
    this.borderRadius = 8,
  });

  final OfflineCacheItem item;
  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final local = item.coverPath;
    final hasLocal = local.isNotEmpty && File(local).existsSync();
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: ColoredBox(
          color: const Color(0xFF2A2B31),
          child: hasLocal
              ? Image.file(File(local), fit: BoxFit.cover)
              : CoverImage(url: item.pic, sourceKey: item.sourceKey),
        ),
      ),
    );
  }
}

String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
  final gb = bytes / (1024 * 1024 * 1024);
  return '${gb.toStringAsFixed(gb < 10 ? 2 : 1)} GB';
}

String offlineStatusText(OfflineCacheItem item) {
  switch (item.status) {
    case OfflineCacheStatus.queued:
      return '等待缓存';
    case OfflineCacheStatus.downloading:
      final percent = (item.progress * 100).clamp(0, 100).round();
      return '正在缓存 $percent%';
    case OfflineCacheStatus.completed:
      return item.bytes > 0 ? formatByteSize(item.bytes) : '已缓存';
    case OfflineCacheStatus.failed:
      return item.error.isNotEmpty ? item.error : '缓存失败';
  }
}
