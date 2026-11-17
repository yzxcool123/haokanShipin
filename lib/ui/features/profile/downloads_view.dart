import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/offline_cache_repository.dart';
import '../../../domain/models/offline_cache_item.dart';
import 'offline_cover.dart';
import 'storage_usage_bar.dart';

class DownloadsView extends StatelessWidget {
  const DownloadsView({
    super.key,
    required this.offlineCacheRepository,
    required this.historyRepository,
  });

  final OfflineCacheRepository offlineCacheRepository;
  final HistoryRepository historyRepository;

  Future<void> _open(BuildContext context, OfflineCacheItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    if (item.isFailed) {
      await offlineCacheRepository.retry(item.id);
      return;
    }
    if (item.isActive) {
      messenger.showSnackBar(const SnackBar(content: Text('正在缓存，请稍候')));
      return;
    }
    final record = historyRepository.find(item.sourceKey, item.vodId);
    var start = Duration.zero;
    if (record != null &&
        !record.isFinished &&
        record.episodeId == item.episodeId) {
      start = Duration(milliseconds: record.positionMs);
    }
    final playable = offlineCacheRepository.localPlayable(
      item,
      startPosition: start,
    );
    if (playable == null) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('本地文件已丢失'),
          content: const Text('这集的缓存文件已经找不到了，要从列表中删除吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (remove == true) {
        await offlineCacheRepository.delete(item.id);
      }
      return;
    }
    if (!context.mounted) return;
    await context.push('/player', extra: playable);
  }

  Future<bool> _confirmRemove(
    BuildContext context,
    OfflineCacheItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_removeTitle(item)),
        content: Text(_removeMessage(item)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _remove(BuildContext context, OfflineCacheItem item) async {
    final confirmed = await _confirmRemove(context, item);
    if (!confirmed) return;
    final status = item.status;
    await offlineCacheRepository.delete(item.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_removedSnackText(status))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: offlineCacheRepository,
      builder: (pageContext, _) {
        final items = offlineCacheRepository.visibleItems;
        final muted = Theme.of(pageContext).colorScheme.onSurface.withValues(alpha: 0.55);
        return Scaffold(
          appBar: AppBar(title: const Text('已下载')),
          body: Column(
            children: [
              if (items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _summaryText(offlineCacheRepository),
                      style: Theme.of(pageContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: muted),
                    ),
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_outlined, size: 40, color: muted),
                              const SizedBox(height: 12),
                              Text(
                                '还没有缓存的影片',
                                style: Theme.of(pageContext).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '在详情页或播放页选择「缓存本集」，就可以在这里离线观看。',
                                textAlign: TextAlign.center,
                                style: Theme.of(pageContext)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: muted),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Dismissible(
                            key: ValueKey(item.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(pageContext).colorScheme.error,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                              ),
                            ),
                            confirmDismiss: (_) =>
                                _confirmRemove(pageContext, item),
                            onDismissed: (_) {
                              final status = item.status;
                              offlineCacheRepository.delete(item.id);
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(content: Text(_removedSnackText(status))),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF181A20),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: _DownloadTile(
                                  item: item,
                                  onTap: () => _open(pageContext, item),
                                  onRetry: () =>
                                      offlineCacheRepository.retry(item.id),
                                  onRemove: () => _remove(pageContext, item),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              StorageUsageBar(
                cacheBytes: offlineCacheRepository.totalBytes,
                cacheItemCount: items.length,
                activeCount: offlineCacheRepository.activeCount,
              ),
            ],
          ),
        );
      },
    );
  }

  String _summaryText(OfflineCacheRepository repository) {
    final completed = repository.completedCount;
    final active = repository.activeCount;
    final size = formatByteSize(repository.totalBytes);
    final parts = <String>[
      if (completed > 0) '已缓存 $completed 集',
      if (active > 0) '$active 集下载中',
      if (repository.totalBytes > 0) '占用 $size',
    ];
    return parts.isEmpty ? '缓存任务' : parts.join(' · ');
  }
}

String _removeTitle(OfflineCacheItem item) {
  switch (item.status) {
    case OfflineCacheStatus.queued:
      return '取消缓存';
    case OfflineCacheStatus.downloading:
      return '取消下载';
    case OfflineCacheStatus.completed:
      return '删除缓存';
    case OfflineCacheStatus.failed:
      return '移除记录';
  }
}

String _removeMessage(OfflineCacheItem item) {
  switch (item.status) {
    case OfflineCacheStatus.queued:
      return '确认取消这次缓存吗？';
    case OfflineCacheStatus.downloading:
      return '确认取消下载并删除已下的不完整文件吗？';
    case OfflineCacheStatus.completed:
      return '确认删除这份离线缓存吗？';
    case OfflineCacheStatus.failed:
      return '确认移除这条失败记录吗？';
  }
}

String _removedSnackText(OfflineCacheStatus status) {
  switch (status) {
    case OfflineCacheStatus.queued:
    case OfflineCacheStatus.downloading:
      return '已取消缓存';
    case OfflineCacheStatus.completed:
      return '已删除缓存';
    case OfflineCacheStatus.failed:
      return '已移除记录';
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.item,
    required this.onTap,
    required this.onRetry,
    required this.onRemove,
  });

  final OfflineCacheItem item;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusText = offlineStatusText(item);
    final removeTooltip = item.isActive
        ? '取消缓存'
        : item.isFailed
            ? '移除记录'
            : '删除缓存';
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  OfflineCover(item: item, width: 56, height: 76, borderRadius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (item.displayEpisode.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.displayEpisode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface.withValues(alpha: 0.62),
                                ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          statusText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: item.isFailed
                                    ? scheme.error
                                    : scheme.onSurface.withValues(alpha: 0.62),
                              ),
                        ),
                        if (item.isActive) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            minHeight: 3,
                            value: item.status == OfflineCacheStatus.downloading &&
                                    item.progress > 0
                                ? item.progress.clamp(0.05, 1.0)
                                : null,
                            backgroundColor:
                                scheme.onSurface.withValues(alpha: 0.08),
                            color: const Color(0xFF7C9CFF),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (item.isFailed)
          IconButton(
            tooltip: '重新缓存',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        IconButton(
          tooltip: removeTooltip,
          onPressed: onRemove,
          icon: Icon(
            item.isActive ? Icons.close_rounded : Icons.delete_outline_rounded,
            color: scheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
