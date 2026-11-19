import 'package:flutter/material.dart';

import '../../../domain/models/media_source.dart';
import 'sources_view_model.dart';

class SourcesView extends StatelessWidget {
  const SourcesView({super.key, required this.viewModel});

  final SourcesViewModel viewModel;

  Future<void> _addSource(BuildContext context) async {
    final nameController = TextEditingController();
    final apiController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('添加采集源'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiController,
                decoration: const InputDecoration(
                  labelText: '接口地址',
                  hintText: 'https://example.com/api.php/provide/vod/',
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('添加')),
          ],
        );
      },
    );
    if (confirmed == true) {
      await viewModel.addCustom(
          name: nameController.text, api: apiController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final currentKey = viewModel.current?.key;
        if (viewModel.message != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final message = viewModel.message;
            if (message == null || !context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
            viewModel.message = null;
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('数据源'),
            actions: [
              IconButton(
                tooltip: '刷新源列表并检测可用性与延迟',
                onPressed:
                    viewModel.refreshing ? null : viewModel.refreshRemote,
                icon: viewModel.refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addSource(context),
            icon: const Icon(Icons.add),
            label: const Text('添加源'),
          ),
          body: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
            itemCount: viewModel.sources.length,
            itemBuilder: (context, index) {
              final source = viewModel.sources[index];
              return _SourceTile(
                source: source,
                title: viewModel.displayNameOf(source),
                unavailable: viewModel.isUnavailable(source),
                probing: viewModel.isProbing(source),
                latencyMs: viewModel.latencyMsOf(source),
                selected: source.key == currentKey,
                onTap: () => viewModel.select(source),
                onDelete:
                    source.custom ? () => viewModel.removeCustom(source) : null,
              );
            },
          ),
        );
      },
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.title,
    required this.unavailable,
    required this.probing,
    required this.latencyMs,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final MediaSource source;
  final String title;
  final bool unavailable;
  final bool probing;
  final int? latencyMs;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  String? get _latencyLabel {
    if (probing) return '检测中';
    if (unavailable || latencyMs == null) return null;
    final ms = latencyMs!;
    if (ms >= 1000) {
      final seconds = ms / 1000;
      final text = seconds >= 10
          ? seconds.toStringAsFixed(0)
          : seconds.toStringAsFixed(1);
      return '$text s';
    }
    return '$ms ms';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = source.isSupported
        ? (source.isHuangguo ? '黄果接口 · 需签名' : '采集站 JSON')
        : '当前版本暂不支持该爬虫源';
    final titleColor =
        unavailable ? scheme.onSurface.withValues(alpha: 0.55) : null;
    final latency = _latencyLabel;
    final latencyColor = probing
        ? scheme.onSurface.withValues(alpha: 0.55)
        : _latencyColor(scheme);
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? scheme.primary : null,
      ),
      title: Text(title,
          style: titleColor == null ? null : TextStyle(color: titleColor)),
      subtitle: Text('$subtitle\n${source.api}',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      isThreeLine: true,
      enabled: source.isSupported,
      selected: selected,
      onTap: source.isSupported ? onTap : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (latency != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                latency,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: latencyColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  Color? _latencyColor(ColorScheme scheme) {
    final ms = latencyMs;
    if (ms == null) return scheme.onSurface.withValues(alpha: 0.7);
    if (ms < 500) return const Color(0xFF7DDEA0);
    if (ms < 1500) return scheme.onSurface.withValues(alpha: 0.75);
    return const Color(0xFFE6B067);
  }
}
