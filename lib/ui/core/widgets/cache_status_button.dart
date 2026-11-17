import 'package:flutter/material.dart';

import '../../../domain/models/offline_cache_item.dart';

class CacheStatusButton extends StatelessWidget {
  const CacheStatusButton({
    super.key,
    required this.item,
    required this.onCache,
    required this.onCancel,
    required this.onRetry,
    this.color,
    this.iconSize = 20,
    this.padding = const EdgeInsets.all(4),
    this.tooltipWhenIdle = '缓存本集',
  });

  final OfflineCacheItem? item;
  final VoidCallback onCache;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final Color? color;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final String tooltipWhenIdle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = item?.status;
    final iconColor = color ?? scheme.onSurface.withValues(alpha: 0.75);
    final accent = color ?? const Color(0xFF7C9CFF);

    if (status == OfflineCacheStatus.completed) {
      return _icon(
        icon: Icons.download_done_rounded,
        color: accent,
        tooltip: '已缓存',
        onPressed: null,
      );
    }
    if (status == OfflineCacheStatus.queued ||
        status == OfflineCacheStatus.downloading) {
      final progress = item?.progress ?? 0;
      return IconButton(
        tooltip: '取消缓存',
        onPressed: onCancel,
        padding: padding,
        constraints: BoxConstraints.tightFor(
          width: iconSize + 12,
          height: iconSize + 12,
        ),
        icon: SizedBox(
          width: iconSize,
          height: iconSize,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            value: status == OfflineCacheStatus.downloading && progress > 0
                ? progress.clamp(0.05, 1.0)
                : null,
            color: accent,
            backgroundColor: accent.withValues(alpha: 0.2),
          ),
        ),
      );
    }
    if (status == OfflineCacheStatus.failed) {
      return _icon(
        icon: Icons.error_outline_rounded,
        color: scheme.error,
        tooltip: item?.error.isNotEmpty == true ? item!.error : '缓存失败，点击重试',
        onPressed: onRetry,
      );
    }
    return _icon(
      icon: Icons.download_outlined,
      color: iconColor,
      tooltip: tooltipWhenIdle,
      onPressed: onCache,
    );
  }

  Widget _icon({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: padding,
      constraints: BoxConstraints.tightFor(
        width: iconSize + 12,
        height: iconSize + 12,
      ),
      icon: Icon(icon, size: iconSize, color: color),
    );
  }
}
