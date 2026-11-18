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
  final size = bytes < 0 ? 0 : bytes;
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) {
    return '${(size / 1024).toStringAsFixed(size < 10 * 1024 ? 1 : 0)} KB';
  }
  if (size < 1024 * 1024 * 1024) {
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
  if (size < 1024 * 1024 * 1024 * 1024) {
    final gb = size / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(gb < 10 ? 2 : 1)} GB';
  }
  final tb = size / (1024 * 1024 * 1024 * 1024);
  return '${tb.toStringAsFixed(tb < 10 ? 2 : 1)} TB';
}

String formatByteSpeed(int bytesPerSec) {
  final speed = bytesPerSec < 0 ? 0 : bytesPerSec;
  return '${formatByteSize(speed)}/s';
}

String offlineStatusText(OfflineCacheItem item) {
  switch (item.status) {
    case OfflineCacheStatus.queued:
      return '等待缓存';
    case OfflineCacheStatus.downloading:
      final percent = (item.progress * 100).clamp(0, 100).round();
      final parts = <String>['正在缓存 $percent%'];
      if (item.speedBytesPerSec > 0) {
        parts.add(formatByteSpeed(item.speedBytesPerSec));
      }
      if (item.totalBytes > 0) {
        final received = item.bytes > 0 ? item.bytes : 0;
        parts.add('${formatByteSize(received)} / ${formatByteSize(item.totalBytes)}');
      } else if (item.bytes > 0) {
        parts.add('已下载 ${formatByteSize(item.bytes)}');
      }
      return parts.join(' · ');
    case OfflineCacheStatus.completed:
      return item.bytes > 0 ? formatByteSize(item.bytes) : '已缓存';
    case OfflineCacheStatus.failed:
      return item.error.isNotEmpty ? item.error : '缓存失败';
  }
}
