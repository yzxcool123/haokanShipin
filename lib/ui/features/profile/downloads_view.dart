import 'package:flutter/material.dart';

class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Scaffold(
      appBar: AppBar(title: const Text('已下载')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_outlined, size: 40, color: muted),
              const SizedBox(height: 12),
              Text(
                '离线缓存稍后推出',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '这里以后会用来查看已经缓存到本地的视频，方便离线观看。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
