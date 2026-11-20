import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/favorite_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/offline_cache_repository.dart';
import '../../../domain/models/offline_cache_item.dart';
import '../../../domain/models/playable.dart';
import '../../core/widgets/cache_status_button.dart';
import '../../core/widgets/cover_hero.dart';
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
    this.preview,
  });

  final CatalogRepository catalogRepository;
  final HistoryRepository historyRepository;
  final FavoriteRepository favoriteRepository;
  final OfflineCacheRepository offlineCacheRepository;
  final String sourceKey;
  final String vodId;
  final CoverHeroInfo? preview;

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
      await context.push(
        '/player',
        extra: PlayerSession(
          playable: playable,
          episodes: _viewModel.currentLine?.episodes ?? const [],
        ),
      );
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

  Widget _infoHeader(
    BuildContext context, {
    required String url,
    required String sourceKey,
    required String id,
    required String title,
    String remarks = '',
    String year = '',
    String actor = '',
    String typeName = '',
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CoverThumb(
          url: url,
          sourceKey: sourceKey,
          id: id,
          title: title,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (remarks.isNotEmpty) Text(remarks),
              if (year.isNotEmpty) Text('年份：$year'),
              if (actor.isNotEmpty) Text('演员：$actor'),
              if (typeName.isNotEmpty) Text(typeName),
            ],
          ),
        ),
      ],
    );
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
        final detail = vm.detail;
        final item = detail?.item;
        final preview = widget.preview;
        if (detail == null) {
          return Scaffold(
            appBar: _appBar(vm, showFavorite: false),
            body: Column(
              children: [
                if (preview != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: _infoHeader(
                      context,
                      url: preview.pic,
                      sourceKey: preview.sourceKey,
                      id: preview.id,
                      title: preview.name,
                      remarks: preview.remarks,
                      typeName: preview.typeName,
                    ),
                  ),
                Expanded(
                  child: vm.loading
                      ? const LoadingView()
                      : vm.error != null
                          ? ErrorView(message: vm.error!, onRetry: vm.load)
                          : const EmptyView(),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: _appBar(vm, showFavorite: true),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              _infoHeader(
                context,
                url: item!.pic,
                sourceKey: item.sourceKey,
                id: item.id,
                title: item.name,
                remarks: item.remarks,
                year: detail.year,
                actor: detail.actor,
                typeName: item.typeName,
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
    required this.id,
    required this.title,
  });

  final String url;
  final String sourceKey;
  final String id;
  final String title;

  void _open(BuildContext context) {
    if (url.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
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
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: 120, height: 168, child: cover),
    );
    final hero = Hero(
      tag: CoverHeroInfo.tag(sourceKey, id),
      child: clipped,
    );
    if (url.isEmpty) return hero;
    return GestureDetector(
      onTap: () => _open(context),
      child: hero,
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

class _CoverPreviewPageState extends State<_CoverPreviewPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _doubleTap;
  Animation<double>? _scaleAnimation;
  VoidCallback? _scaleListener;
  double _chromeOpacity = 1;

  @override
  void initState() {
    super.initState();
    _doubleTap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    final listener = _scaleListener;
    if (listener != null) {
      _scaleAnimation?.removeListener(listener);
    }
    _doubleTap.dispose();
    super.dispose();
  }

  void _onDoubleTap(ExtendedImageGestureState state) {
    final pointer = state.pointerDownPosition;
    final begin = state.gestureDetails?.totalScale ?? 1.0;
    final end = begin < 1.5 ? 2.5 : 1.0;
    final oldListener = _scaleListener;
    if (oldListener != null) {
      _scaleAnimation?.removeListener(oldListener);
    }
    _doubleTap
      ..stop()
      ..reset();
    late final VoidCallback listener;
    listener = () {
      state.handleDoubleTap(
        scale: _scaleAnimation?.value ?? end,
        doubleTapPosition: pointer,
      );
    };
    _scaleListener = listener;
    _scaleAnimation = _doubleTap.drive(Tween<double>(begin: begin, end: end));
    _scaleAnimation!.addListener(listener);
    _doubleTap.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ExtendedImageSlidePage(
        slideAxis: SlideAxis.both,
        slideType: SlideType.onlyImage,
        onSlidingPage: (state) {
          final size = MediaQuery.sizeOf(context);
          final maxDistance = Offset(size.width, size.height).distance / 2;
          final opacity =
              (1.0 - state.offset.distance / maxDistance).clamp(0.0, 1.0);
          if ((opacity - _chromeOpacity).abs() > 0.01) {
            setState(() => _chromeOpacity = opacity);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExtendedImage(
              image: CoverImage.providerFor(
                url: widget.url,
                sourceKey: widget.sourceKey,
              ),
              fit: BoxFit.contain,
              enableLoadState: true,
              enableSlideOutPage: true,
              gaplessPlayback: true,
              mode: ExtendedImageMode.gesture,
              filterQuality: FilterQuality.medium,
              initGestureConfigHandler: (_) => GestureConfig(
                minScale: 1,
                animationMinScale: 0.8,
                maxScale: 5,
                animationMaxScale: 6,
                speed: 1,
                inertialSpeed: 100,
                initialScale: 1,
                inPageView: false,
                initialAlignment: InitialAlignment.center,
              ),
              onDoubleTap: _onDoubleTap,
              loadStateChanged: (state) {
                switch (state.extendedImageLoadState) {
                  case LoadState.loading:
                    return const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    );
                  case LoadState.failed:
                    return const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48,
                      ),
                    );
                  case LoadState.completed:
                    return null;
                }
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: _chromeOpacity < 0.05,
                child: Opacity(
                  opacity: _chromeOpacity,
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
