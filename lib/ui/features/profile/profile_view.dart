import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/watch_record.dart';
import 'profile_view_model.dart';
import 'watch_cover.dart';
import 'watch_time.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  void _openDetail(BuildContext context, WatchRecord record) {
    context.push(
      '/detail/${Uri.encodeComponent(record.sourceKey)}/${Uri.encodeComponent(record.vodId)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final continuing = viewModel.continueWatching;
        final recent = viewModel.recentPreview;
        return Scaffold(
          appBar: AppBar(title: const Text('我的')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _SectionHeader(
                title: '继续观看',
                actionLabel: continuing.isEmpty ? null : '全部',
                onAction: continuing.isEmpty
                    ? null
                    : () => context.push('/history'),
              ),
              const SizedBox(height: 8),
              if (continuing.isEmpty)
                const _EmptyHint(text: '看过的片子会出现在这里，方便接着看')
              else
                SizedBox(
                  height: 196,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: continuing.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final record = continuing[index];
                      return _ContinueCard(
                        record: record,
                        onTap: () => _openDetail(context, record),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: '播放记录',
                actionLabel: viewModel.hasMoreHistory ? '全部' : null,
                onAction: viewModel.hasMoreHistory
                    ? () => context.push('/history')
                    : null,
              ),
              const SizedBox(height: 8),
              if (recent.isEmpty)
                const _EmptyHint(text: '还没有播放记录')
              else
                ...[
                  for (final record in recent)
                    _HistoryTile(
                      record: record,
                      onTap: () => _openDetail(context, record),
                    ),
                ],
              const SizedBox(height: 16),
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.swap_horiz),
                title: const Text('数据源'),
                subtitle: Text(viewModel.currentSourceName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/sources'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
            ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.record, required this.onTap});

  final WatchRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 146,
              width: 110,
              child: WatchCover(record: record, borderRadius: 12),
            ),
            const SizedBox(height: 6),
            Text(
              record.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              record.episodeTitle.isEmpty ? '继续播放' : record.episodeTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record, required this.onTap});

  final WatchRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: WatchCover(record: record, width: 52, height: 70),
      title: Text(record.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        formatWatchSubtitle(record),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}
