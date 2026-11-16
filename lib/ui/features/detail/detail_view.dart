import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/playable.dart';
import '../../core/widgets/status_views.dart';
import 'detail_view_model.dart';

class DetailView extends StatefulWidget {
  const DetailView({super.key, required this.viewModel});

  final DetailViewModel viewModel;

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  Future<void> _play(Episode episode) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final playable = await widget.viewModel.play(episode);
      if (!mounted) return;
      await context.push('/player', extra: playable);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        if (vm.loading && vm.detail == null) {
          return const Scaffold(body: LoadingView());
        }
        if (vm.error != null && vm.detail == null) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorView(message: vm.error!, onRetry: vm.load),
          );
        }
        final detail = vm.detail;
        if (detail == null) {
          return const Scaffold(body: EmptyView());
        }
        final item = detail.item;
        return Scaffold(
          appBar: AppBar(title: Text(item.name)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 120,
                      height: 168,
                      child: item.pic.isEmpty
                          ? const ColoredBox(
                              color: Color(0xFF2A2B31),
                              child: Icon(Icons.movie_outlined),
                            )
                          : CachedNetworkImage(imageUrl: item.pic, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        if (item.remarks.isNotEmpty) Text(item.remarks),
                        if (detail.year.isNotEmpty) Text('年份：${detail.year}'),
                        if (detail.actor.isNotEmpty) Text('演员：${detail.actor}'),
                        if (item.typeName.isNotEmpty) Text(item.typeName),
                      ],
                    ),
                  ),
                ],
              ),
              if (detail.content.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(detail.content, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 20),
              if (detail.lines.length > 1)
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < detail.lines.length; i++)
                      ChoiceChip(
                        label: Text(detail.lines[i].name),
                        selected: vm.lineIndex == i,
                        onSelected: (_) => vm.selectLine(i),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              if (vm.currentLine == null || vm.currentLine!.episodes.isEmpty)
                const Text('没有可播放的分集')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final episode in vm.currentLine!.episodes)
                      FilledButton.tonal(
                        onPressed: _opening ? null : () => _play(episode),
                        child: Text(episode.title),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
