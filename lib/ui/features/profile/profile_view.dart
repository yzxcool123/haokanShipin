import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/watch_record.dart';
import 'profile_view_model.dart';
import 'watch_cover.dart';
import 'watch_record_tile.dart';

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
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text(
                  '我的',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 16),
                _ProfileHeader(sourceName: viewModel.currentSourceName),
                const SizedBox(height: 12),
                _StatsCard(
                  continueCount: viewModel.continueCount,
                  historyCount: viewModel.historyCount,
                  finishedCount: viewModel.finishedCount,
                  onHistoryTap: () => context.push('/history'),
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: '继续观看',
                  actionLabel: continuing.isEmpty ? null : '全部',
                  onAction: continuing.isEmpty
                      ? null
                      : () => context.push('/history'),
                ),
                const SizedBox(height: 10),
                if (continuing.isEmpty)
                  const _EmptyCard(text: '看过的片子会出现在这里，方便接着看')
                else
                  SizedBox(
                    height: 210,
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
                  title: '最近播放',
                  actionLabel: viewModel.historyCount == 0 ? null : '全部',
                  onAction: viewModel.historyCount == 0
                      ? null
                      : () => context.push('/history'),
                ),
                const SizedBox(height: 10),
                if (recent.isEmpty)
                  const _EmptyCard(text: '还没有播放记录')
                else
                  _GroupCard(
                    children: [
                      for (var i = 0; i < recent.length; i++)
                        WatchRecordTile(
                          record: recent[i],
                          showDivider: i != recent.length - 1,
                          onTap: () => _openDetail(context, recent[i]),
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
                const _SectionHeader(title: '常用功能'),
                const SizedBox(height: 10),
                _GroupCard(
                  children: [
                    _MenuTile(
                      icon: Icons.swap_horiz_rounded,
                      title: '数据源',
                      subtitle: viewModel.currentSourceName,
                      onTap: () => context.push('/sources'),
                    ),
                    Divider(
                      height: 1,
                      indent: 52,
                      endIndent: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.08),
                    ),
                    _MenuTile(
                      icon: Icons.history_rounded,
                      title: '播放记录',
                      subtitle: viewModel.historyCount == 0
                          ? '暂无记录'
                          : '${viewModel.historyCount} 条',
                      onTap: () => context.push('/history'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.sourceName});

  final String sourceName;

  @override
  Widget build(BuildContext context) {
    return _GroupCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF2F4BDB),
                    Color(0xFF7C9CFF),
                    Color(0xFFB8E6E0),
                  ],
                ),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '蓝果短剧',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前源  $sourceName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.62),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.continueCount,
    required this.historyCount,
    required this.finishedCount,
    required this.onHistoryTap,
  });

  final int continueCount;
  final int historyCount;
  final int finishedCount;
  final VoidCallback onHistoryTap;

  @override
  Widget build(BuildContext context) {
    return _GroupCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        Row(
          children: [
            _StatItem(value: '$continueCount', label: '继续观看', onTap: onHistoryTap),
            _StatDivider(),
            _StatItem(value: '$historyCount', label: '播放记录', onTap: onHistoryTap),
            _StatDivider(),
            _StatItem(value: '$finishedCount', label: '已看完', onTap: onHistoryTap),
          ],
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    required this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF7C9CFF),
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.62),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const Spacer(),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.children,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF181A20),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: padding,
        child: Column(children: children),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _GroupCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      children: [
        Icon(
          Icons.movie_filter_outlined,
          size: 28,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
        ),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.record, required this.onTap});

  final WatchRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final episode = record.episodeTitle.isEmpty ? '继续播放' : record.episodeTitle;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 114,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 152,
              width: 114,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WatchCover(record: record, borderRadius: 12),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                      child: Text(
                        episode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              record.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF7C9CFF).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF7C9CFF)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Flexible(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: scheme.onSurface.withValues(alpha: 0.28),
            ),
          ],
        ),
      ),
    );
  }
}
