import 'package:flutter/material.dart';

import '../../../data/repositories/source_repository.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.sourceRepository});

  final SourceRepository sourceRepository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sourceRepository,
      builder: (context, _) {
        final mode = sourceRepository.contentMode;
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                '模式切换',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF181A20),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _ModeTile(
                      title: '健康模式',
                      subtitle: '隐藏带 🔞 标识的源和黄果短剧，并默认使用第一个可用的 🔵 源',
                      selected: mode == ContentMode.healthy,
                      onTap: () =>
                          sourceRepository.setContentMode(ContentMode.healthy),
                    ),
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.08),
                    ),
                    _ModeTile(
                      title: '成人模式',
                      subtitle: '显示全部数据源，并默认选中黄果短剧',
                      selected: mode == ContentMode.adult,
                      onTap: () =>
                          sourceRepository.setContentMode(ContentMode.adult),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '如果你手动选了其他源，下次打开应用时会继续使用上次选中的源。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.62),
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? const Color(0xFF7C9CFF)
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}
