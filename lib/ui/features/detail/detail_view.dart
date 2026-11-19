import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/favorite_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/offline_cache_repository.dart';
import '../../../domain/models/offline_cache_item.dart';
import '../../../domain/models/playable.dart';
import '../../core/widgets/cache_status_button.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/status_views.dart';
import 'detail_view_model.dart';

class DetailView extends StatefulWidget {
  const DetailView({
    super.key,
    required this.catalogRepository,
    required this.historyRepository,
    required this.favoriteRepository,
    required this.offlineCacheRepository,
    required this.sourceKey,
    required this.vodId,
  });

  final CatalogRepository catalogRepository;
  final HistoryRepository historyRepository;
  final FavoriteRepository favoriteRepository;
  final OfflineCacheRepository offlineCacheRepository;
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
      offlineCacheRepository: widget.offlineCacheRepository,
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

  Future<void> _cache(Episode episode) async {
    try {
      await _viewModel.cacheEpisode(episode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始缓存本集')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _cacheLine() async {
    try {
      final added = await _viewModel.cacheCurrentLine();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added == 0 ? '当前线路已经全部缓存' : '已将 $added 集加入缓存队列'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _retryCache(Episode episode) async {
    try {
      await _viewModel.retryCache(episode);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  PreferredSizeWidget _appBar(DetailViewModel vm,
      {required bool showFavorite}) {
    return AppBar(
      title: const Text('详情'),
      actions: [
        if (showFavorite)
          IconButton(
            tooltip: vm.isFavorite ? '取消收藏' : '收藏',
            onPressed: () => _toggleFavorite(vm),
            icon: Icon(
              vm.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
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
                  _CoverThumb(
                    url: item.pic,
                    sourceKey: item.sourceKey,
                    title: item.name,
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
              else ...[
                if (vm.uncachedEpisodes.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _cacheLine,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('缓存本线路全部'),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final episode in vm.currentLine!.episodes)
                      _EpisodeChip(
                        title: episode.title,
                        enabled: !_opening,
                        cacheItem: vm.cacheItemOf(episode),
                        onPlay: () => _play(episode),
                        onCache: () => _cache(episode),
                        onCancel: () => vm.cancelCache(episode),
                        onRetry: () => _retryCache(episode),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({
    required this.title,
    required this.enabled,
    required this.cacheItem,
    required this.onPlay,
    required this.onCache,
    required this.onCancel,
    required this.onRetry,
  });

  final String title;
  final bool enabled;
  final OfflineCacheItem? cacheItem;
  final VoidCallback onPlay;
  final VoidCallback onCache;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onPlay : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
              ),
              CacheStatusButton(
                item: cacheItem,
                onCache: onCache,
                onCancel: onCancel,
                onRetry: onRetry,
                iconSize: 18,
                padding: const EdgeInsets.all(6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({
    required this.url,
    required this.sourceKey,
    required this.title,
  });

  final String url;
  final String sourceKey;
  final String title;

  void _open(BuildContext context) {
    if (url.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black54,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _CoverPreviewPage(
              url: url,
              sourceKey: sourceKey,
              title: title,
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cover = url.isEmpty
        ? const ColoredBox(
            color: Color(0xFF2A2B31),
            child: Icon(Icons.movie_outlined),
          )
        : CoverImage(url: url, sourceKey: sourceKey);
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 120, height: 168, child: cover),
    );
    if (url.isEmpty) return clipped;
    return GestureDetector(
      onTap: () => _open(context),
      child: clipped,
    );
  }
}

class _CoverPreviewPage extends StatefulWidget {
  const _CoverPreviewPage({
    required this.url,
    required this.sourceKey,
    required this.title,
  });

  final String url;
  final String sourceKey;
  final String title;

  @override
  State<_CoverPreviewPage> createState() => _CoverPreviewPageState();
}

class _CoverPreviewPageState extends State<_CoverPreviewPage> {
  final _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    final current = _transform.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      _transform.value = Matrix4.identity();
      return;
    }
    final position = _doubleTapDetails?.localPosition ?? Offset.zero;
    _transform.value = Matrix4.identity()
      ..translateByDouble(-position.dx, -position.dy, 0, 1)
      ..scaleByDouble(2.5, 2.5, 2.5, 1)
      ..translateByDouble(position.dx, position.dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: _onDoubleTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 5,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: CoverImage(
                  url: widget.url,
                  sourceKey: widget.sourceKey,
                  fit: BoxFit.contain,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
