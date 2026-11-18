import 'package:flutter/material.dart';

import '../../../data/services/device_storage.dart';
import 'offline_cover.dart';

class StorageUsageBar extends StatefulWidget {
  const StorageUsageBar({
    super.key,
    required this.cacheBytes,
    required this.cacheItemCount,
    required this.activeCount,
  });

  final int cacheBytes;
  final int cacheItemCount;
  final int activeCount;

  @override
  State<StorageUsageBar> createState() => _StorageUsageBarState();
}

class _StorageUsageBarState extends State<StorageUsageBar> {
  
  final DeviceStorage _storage = const DeviceStorage();
  DeviceStorageInfo? _info;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant StorageUsageBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheItemCount != widget.cacheItemCount ||
        oldWidget.activeCount != widget.activeCount) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      final info = await _storage.query();
      if (!mounted) return;
      setState(() {
        _info = info;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _info = null;
        _error = '暂时无法读取设备存储空间';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.55);
    return Material(
      color: const Color(0xFF16171C),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: _buildBody(context, muted),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Color muted) {
    if (_loading && _info == null) {
      return Text('正在读取存储空间…', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted));
    }
    if (_error != null || _info == null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _error ?? '暂时无法读取设备存储空间',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _loading = true);
              _refresh();
            },
            child: const Text('重试'),
          ),
        ],
      );
    }

    final info = _info!;
    final total = info.totalBytes;
    final available = info.availableBytes.clamp(0, total);
    final used = (total - available).clamp(0, total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MetricGrid(
          rows: [
            ('总容量', formatByteSize(total)),
            ('  已用空间', formatByteSize(used)),
            ('可用空间', formatByteSize(available)),
            ('  ${info.appUsageLabel}', formatByteSize(info.appBytes)),
          ],
        ),
        if (widget.cacheBytes > 0) ...[
          const SizedBox(height: 6),
          Text(
            '其中离线缓存 ${formatByteSize(widget.cacheBytes)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < rows.length ? 4 : 0),
            child: Row(
              children: [
                Expanded(child: _Metric(label: rows[i].$1, value: rows[i].$2)),
                if (i + 1 < rows.length)
                  Expanded(child: _Metric(label: rows[i + 1].$1, value: rows[i + 1].$2)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
