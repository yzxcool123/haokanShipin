import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/favorite_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../domain/models/playable.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/status_views.dart';
import 'detail_view_model.dart';

class DetailView extends StatefulWidget {
  const DetailView({
    super.key,
    required this.catalogRepository,
    required this.historyRepository,
    required this.favoriteRepository,
    required this.sourceKey,
    required this.vodId,
  });

  final CatalogRepository catalogRepository;
  final HistoryRepository historyRepository;
  final FavoriteRepository favoriteRepository;
  final String sourceKey;
  final String vodId;

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  late DetailViewModel _viewModel;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _viewModel = _createViewModel();
    _viewModel.load();
  }

  @override
  void didUpdateWidget(covariant DetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.vodId != widget.vodId) {
      _viewModel.dispose();
      _viewModel = _createViewModel();
      _viewModel.load();
    }
  }

  DetailViewModel _createViewModel() {
    return DetailViewModel(
      catalogRepository: widget.catalogRepository,
      historyRepository: widget.historyRepository,
      favoriteRepository: widget.favoriteRepository,
      sourceKey: widget.sourceKey,
      vodId: widget.vodId,
    );
  }

  Future<void> _play(Episode episode) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final playable = await _viewModel.play(episode);
      if (!mounted) return;
      await context.push('/player', extra: playable);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  PreferredSizeWidget _appBar(DetailViewModel vm, {required bool showFavorite}) {
    return AppBar(
      title: const Text('详情'),
      actions: [
        if (showFavorite)
          IconButton(
            tooltip: vm.isFavorite ? '取消收藏' : '收藏',
            onPressed: () => _toggleFavorite(vm),
            icon: Icon(
              vm.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: vm.isFavorite ? const Color(0xFFFF7A9C) : null,
            ),
          ),
      ],
    );
  }

  Future<void> _toggleFavorite(DetailViewModel vm) async {
    final added = await vm.toggleFavorite();
    if (!mounted || added == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added ? '已收藏' : '已取消收藏')),
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final vm = _viewModel;
        if (vm.loading && vm.detail == null) {
          return Scaffold(
            appBar: _appBar(vm, showFavorite: false),
            body: const LoadingView(),
          );
        }
        if (vm.error != null && vm.detail == null) {
          return Scaffold(
            appBar: _appBar(vm, showFavorite: false),
            body: ErrorView(message: vm.error!, onRetry: vm.load),
          );
        }
        final detail = vm.detail;
        if (detail == null) {
          return Scaffold(
            appBar: _appBar(vm, showFavorite: false),
            body: const EmptyView(),
          );
        }
        final item = detail.item;
        return Scaffold(
          appBar: _appBar(vm, showFavorite: true),
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
                          : CoverImage(
                              url: item.pic, sourceKey: item.sourceKey),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: Theme.of(context).textTheme.titleLarge),
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
                Text(detail.content,
                    style: Theme.of(context).textTheme.bodyMedium),
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
