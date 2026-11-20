import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/cover_hero.dart';

import '../../../domain/models/watch_record.dart';
import 'profile_view_model.dart';
import 'watch_cover.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  void _openDetail(BuildContext context, WatchRecord record) {
    openDetail(
      context,
      CoverHeroInfo(
        sourceKey: record.sourceKey,
        id: record.vodId,
        name: record.name,
        pic: record.pic,
        scope: 'profile',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final continuing = viewModel.continueWatching;
        final dividerColor =
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text(
                  '我的',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                ),
                const SizedBox(height: 16),
                _ProfileHeader(sourceName: viewModel.currentSourceName),
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
                  const _EmptyCard(text: '看过的影片会出现在这里，方便接着看')
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
                const _SectionHeader(title: '常用功能'),
                const SizedBox(height: 10),
                _GroupCard(
                  children: [
                    _MenuTile(
                      icon: Icons.history_rounded,
                      title: '播放记录',
                      subtitle: viewModel.historyCount == 0
                          ? '暂无记录'
                          : '${viewModel.historyCount} 条',
                      onTap: () => context.push('/history'),
                    ),
                    Divider(
                        height: 1,
                        indent: 52,
                        endIndent: 12,
                        color: dividerColor),
                    _MenuTile(
                      icon: Icons.favorite_rounded,
                      title: '收藏',
                      subtitle: viewModel.favoriteCount == 0
                          ? '暂无收藏'
                          : '${viewModel.favoriteCount} 部',
                      onTap: () => context.push('/favorites'),
                    ),
                    Divider(
                        height: 1,
                        indent: 52,
                        endIndent: 12,
                        color: dividerColor),
                    _MenuTile(
                      icon: Icons.download_rounded,
                      title: '已下载',
                      subtitle: viewModel.downloadSubtitle,
                      onTap: () => context.push('/downloads'),
                    ),
                    Divider(
                        height: 1,
                        indent: 52,
                        endIndent: 12,
                        color: dividerColor),
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
                        color: dividerColor),
                    _MenuTile(
                      icon: Icons.settings_rounded,
                      title: '设置',
                      subtitle: viewModel.contentModeLabel,
                      onTap: () => context.push('/settings'),
                    ),
                    Divider(
                        height: 1,
                        indent: 52,
                        endIndent: 12,
                        color: dividerColor),
                    _MenuTile(
                      icon: Icons.info_outline_rounded,
                      title: '关于',
                      subtitle: viewModel.versionLabel,
                      onTap: () => context.push('/about'),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/images/profile_avatar.jpg',
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '彦祖',
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
              foregroundColor: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7),
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
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
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
                  WatchCover(record: record, borderRadius: 12, heroScope: 'profile'),
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
        padding: const EdgeInsets.fromLTRB(10, 14, 12, 10),
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
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
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: scheme.onSurface.withValues(alpha: 0.28),
            ),
          ],
        ),
      ),
    );
  }
}
