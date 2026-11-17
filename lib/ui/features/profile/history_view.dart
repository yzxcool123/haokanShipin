import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/history_repository.dart';
import 'watch_cover.dart';
import 'watch_time.dart';

class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.historyRepository});

  final HistoryRepository historyRepository;

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清空播放记录'),
          content: const Text('确定要删除全部播放记录吗？此操作无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await historyRepository.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: historyRepository,
      builder: (context, _) {
        final records = historyRepository.records;
        return Scaffold(
          appBar: AppBar(
            title: const Text('播放记录'),
            actions: [
              if (records.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClear(context),
                  child: const Text('清空'),
                ),
            ],
          ),
          body: records.isEmpty
              ? const Center(child: Text('还没有播放记录'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return Dismissible(
                      key: ValueKey(record.key),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Theme.of(context).colorScheme.error,
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      onDismissed: (_) => historyRepository.remove(record),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        leading: WatchCover(
                          record: record,
                          width: 52,
                          height: 70,
                        ),
                        title: Text(
                          record.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          formatWatchSubtitle(record),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => context.push(
                          '/detail/${Uri.encodeComponent(record.sourceKey)}/${Uri.encodeComponent(record.vodId)}',
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
