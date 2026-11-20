import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/history_repository.dart';
import '../../../data/repositories/offline_cache_repository.dart';
import '../../../domain/models/offline_cache_item.dart';
import '../../../domain/models/playable.dart';
import '../../core/widgets/cache_status_button.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({
    super.key,
    required this.session,
    required this.historyRepository,
    required this.offlineCacheRepository,
    required this.catalogRepository,
  });

  final PlayerSession session;
  final HistoryRepository historyRepository;
  final OfflineCacheRepository offlineCacheRepository;
  final CatalogRepository catalogRepository;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerSlot {
  VideoPlayerController? controller;
  Playable? playable;
  int? index;
  int generation = 0;
  Future<void>? pending;

  bool get isReady =>
      controller != null && controller!.value.isInitialized;
}

class _PlayerViewState extends State<PlayerView> with WidgetsBindingObserver {
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
  static const _accent = Color(0xFF7C9CFF);
  static const _seekStep = Duration(seconds: 10);
  static const _hideAfter = Duration(seconds: 3);

  final List<_PlayerSlot> _slots = [_PlayerSlot(), _PlayerSlot()];
  final Map<String, Playable> _resolved = {};
  final Map<String, Future<Playable>> _resolving = {};
  final Map<String, Duration> _sessionPositions = {};

  late Playable _playable;
  late List<Episode> _episodes;
  late int _currentIndex;
  PageController? _pageController;

  String? _error;
  bool _fullscreen = false;
  bool _panelVisible = true;
  bool _dragging = false;
  Duration? _dragPosition;
  double _speed = 1.0;
  bool _swipeTowardPrev = false;
  int _switchSeq = 0;
  DateTime? _hintAt;
  Timer? _hideTimer;
  Timer? _historyTimer;

  bool get _canSwitch => _episodes.length > 1;

  VideoPlayerController? get _controller =>
      _slotForIndex(_currentIndex)?.controller;

  bool get _swipeEnabled {
    if (!_canSwitch || _fullscreen) return false;
    return MediaQuery.orientationOf(context) != Orientation.landscape;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.offlineCacheRepository.addListener(_onCacheUpdated);
    _playable = widget.session.playable;
    _episodes = widget.session.episodes.isNotEmpty
        ? List<Episode>.from(widget.session.episodes)
        : [
            Episode(
              id: _playable.episodeId,
              title: _playable.episodeTitle.isNotEmpty
                  ? _playable.episodeTitle
                  : _playable.title,
              url: _playable.url,
            ),
          ];
    final initial = widget.session.initialIndex;
    _currentIndex = initial.clamp(0, _episodes.length - 1);
    if (_canSwitch) {
      _pageController = PageController(initialPage: _currentIndex);
    }
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.enable();
    _init();
  }

  Future<void> _init() async {
    await _loadSlot(_slots[0], _currentIndex, autoplay: true);
  }

  _PlayerSlot? _slotForIndex(int index) {
    for (final slot in _slots) {
      if (slot.index == index) return slot;
    }
    return null;
  }

  _PlayerSlot _slotToRecycle() {
    for (final slot in _slots) {
      if (slot.index != _currentIndex) return slot;
    }
    return _slots.last;
  }

  Duration _startPosition(Episode episode) {
    final saved = _sessionPositions[episode.id];
    if (saved != null) return saved;
    if (episode.id == widget.session.playable.episodeId) {
      return widget.session.playable.startPosition;
    }
    final meta = widget.session.playable;
    if (!meta.canTrackHistory) return Duration.zero;
    final record = widget.historyRepository.find(meta.sourceKey, meta.vodId);
    if (record != null &&
        !record.isFinished &&
        record.episodeId == episode.id) {
      return Duration(milliseconds: record.positionMs);
    }
    return Duration.zero;
  }

  String _titleOf(Playable playable, Episode episode, Playable meta) {
    if (playable.title.isNotEmpty) return playable.title;
    if (meta.name.isNotEmpty && episode.title.isNotEmpty) {
      return '${meta.name} ${episode.title}';
    }
    if (episode.title.isNotEmpty) return episode.title;
    return meta.title;
  }

  Future<Playable> _resolveFromRepos(Episode episode) async {
    final meta = widget.session.playable;
    final start = _startPosition(episode);
    final item = widget.offlineCacheRepository.findEpisode(
      sourceKey: meta.sourceKey,
      vodId: meta.vodId,
      lineName: meta.lineName,
      episodeId: episode.id,
    );
    if (item != null) {
      final local = widget.offlineCacheRepository.localPlayable(
        item,
        startPosition: start,
      );
      if (local != null) return local;
    }
    final playable = await widget.catalogRepository.play(
      id: meta.vodId,
      episode: episode,
      lineName: meta.lineName,
      sourceKey: meta.sourceKey,
    );
    return playable.copyWith(
      sourceKey: meta.sourceKey,
      vodId: meta.vodId,
      name: meta.name.isNotEmpty ? meta.name : playable.name,
      pic: meta.pic.isNotEmpty ? meta.pic : playable.pic,
      sourceName: meta.sourceName.isNotEmpty
          ? meta.sourceName
          : playable.sourceName,
      lineName: meta.lineName,
      episodeId: episode.id,
      episodeTitle: episode.title,
      title: _titleOf(playable, episode, meta),
      startPosition: start,
    );
  }

  Future<Playable> _resolvePlayable(Episode episode) {
    final cached = _resolved[episode.id];
    if (cached != null) {
      return Future.value(cached.copyWith(startPosition: _startPosition(episode)));
    }
    final inflight = _resolving[episode.id];
    if (inflight != null) {
      return inflight.then(
        (playable) => playable.copyWith(startPosition: _startPosition(episode)),
      );
    }
    final future = _resolveFromRepos(episode).then((playable) {
      _resolved[episode.id] = playable;
      return playable;
    });
    _resolving[episode.id] = future;
    return future.whenComplete(() => _resolving.remove(episode.id));
  }

  Future<VideoPlayerController> _createController(Playable playable) async {
    if (playable.isLocal) {
      final file = File(_localFilePath(playable.url));
      if (!await file.exists()) {
        throw StateError('local-missing');
      }
      // 本地 HLS 需要带上 formatHint，file 构造函数不支持该参数。
      if (playable.isHls) {
        return VideoPlayerController.networkUrl(
          Uri.file(file.path),
          formatHint: VideoFormat.hls,
        );
      }
      return VideoPlayerController.file(file);
    }
    return VideoPlayerController.networkUrl(
      Uri.parse(playable.url),
      httpHeaders: playable.headers,
      formatHint: playable.isHls ? VideoFormat.hls : null,
    );
  }

  Future<void> _loadSlot(
    _PlayerSlot slot,
    int index, {
    required bool autoplay,
  }) {
    final future = _openSlot(slot, index, autoplay: autoplay);
    slot.pending = future;
    return future;
  }

  Future<void> _openSlot(
    _PlayerSlot slot,
    int index, {
    required bool autoplay,
  }) async {
    final gen = ++slot.generation;
    final episode = _episodes[index];
    final existing = slot.controller;
    slot.controller = null;
    slot.playable = null;
    if (existing != null) {
      existing.removeListener(_onVideoUpdated);
      await existing.dispose();
    }
    if (!mounted || slot.generation != gen) return;

    slot.index = index;
    try {
      final playable = await _resolvePlayable(episode);
      if (!mounted || slot.generation != gen) return;
      final controller = await _createController(playable);
      if (!mounted || slot.generation != gen) {
        await controller.dispose();
        return;
      }
      await controller.initialize();
      if (!mounted || slot.generation != gen) {
        await controller.dispose();
        return;
      }
      if (_speed != 1.0) {
        await controller.setPlaybackSpeed(_speed);
      }
      final start = _startPosition(episode);
      final duration = controller.value.duration;
      if (start > const Duration(seconds: 3) &&
          duration > Duration.zero &&
          start < duration - const Duration(seconds: 3)) {
        await controller.seekTo(start);
      }
      if (!mounted || slot.generation != gen) {
        await controller.dispose();
        return;
      }
      final shouldPlay = autoplay && index == _currentIndex;
      if (shouldPlay) {
        await controller.setVolume(1);
        await controller.play();
        controller.addListener(_onVideoUpdated);
      } else {
        await controller.setVolume(0);
        await controller.pause();
      }
      if (!mounted || slot.generation != gen) {
        await controller.dispose();
        return;
      }
      slot.controller = controller;
      slot.playable = playable;
      if (index == _currentIndex) {
        _playable = playable;
        _error = null;
        _saveHistory();
        _startHistoryTimer();
        _scheduleHide();
        _prefetchNeighborPlayables();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _prepareNeighbor();
        });
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('player load failed: $e');
      if (!mounted || slot.generation != gen || index != _currentIndex) return;
      final message = e is StateError && e.message == 'local-missing'
          ? '本地文件已丢失，请重新缓存或从已下载中删除'
          : '播放失败，请稍后重试';
      setState(() => _error = message);
    }
  }

  void _prefetchNeighborPlayables() {
    if (!_canSwitch) return;
    for (final index in [_currentIndex - 1, _currentIndex + 1]) {
      if (index < 0 || index >= _episodes.length) continue;
      final episode = _episodes[index];
      if (_resolved.containsKey(episode.id) ||
          _resolving.containsKey(episode.id)) {
        continue;
      }
      unawaited(_resolvePlayable(episode));
    }
  }

  int? _preferredNeighborIndex() {
    final last = _episodes.length - 1;
    final next = _currentIndex < last ? _currentIndex + 1 : null;
    final prev = _currentIndex > 0 ? _currentIndex - 1 : null;
    if (_swipeTowardPrev) return prev ?? next;
    return next ?? prev;
  }

  void _prepareNeighbor() {
    if (!_canSwitch || !mounted) return;
    final target = _preferredNeighborIndex();
    if (target == null) return;
    if (_slotForIndex(target) != null) return;
    unawaited(_loadSlot(_slotToRecycle(), target, autoplay: false));
  }

  Future<void> _switchToPage(int index) async {
    if (index == _currentIndex || index < 0 || index >= _episodes.length) {
      return;
    }
    final seq = ++_switchSeq;
    final oldIndex = _currentIndex;
    _swipeTowardPrev = index < oldIndex;

    final current = _slotForIndex(oldIndex);
    final position = current?.controller?.value.position;
    if (position != null) {
      _sessionPositions[_playable.episodeId] = position;
    }
    _saveHistory();
    current?.controller?.removeListener(_onVideoUpdated);
    await current?.controller?.pause();
    if (!mounted || seq != _switchSeq) return;

    _currentIndex = index;
    _error = null;
    _panelVisible = true;
    _dragging = false;
    _dragPosition = null;

    var prepared = _slotForIndex(index);
    if (prepared != null && !prepared.isReady && prepared.pending != null) {
      if (mounted) setState(() {});
      await prepared.pending;
      if (!mounted || seq != _switchSeq) return;
      prepared = _slotForIndex(index);
    }

    if (prepared != null && prepared.isReady) {
      final controller = prepared.controller!;
      controller.addListener(_onVideoUpdated);
      await controller.setVolume(1);
      if (_speed != controller.value.playbackSpeed) {
        await controller.setPlaybackSpeed(_speed);
      }
      await controller.play();
      if (!mounted || seq != _switchSeq) return;
      if (prepared.playable != null) {
        _playable = prepared.playable!;
      }
      if (mounted) setState(() {});
      _saveHistory();
      _startHistoryTimer();
      _scheduleHide();
    } else {
      if (mounted) setState(() {});
      final slot = prepared ?? _slotToRecycle();
      await _loadSlot(slot, index, autoplay: true);
      if (!mounted || seq != _switchSeq) return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || seq != _switchSeq) return;
      _prefetchNeighborPlayables();
      _prepareNeighbor();
    });
  }

  void _goToEpisode(int index) {
    if (index < 0 || index >= _episodes.length || index == _currentIndex) {
      return;
    }
    final controller = _pageController;
    if (controller != null && controller.hasClients) {
      controller.jumpToPage(index);
      return;
    }
    unawaited(_switchToPage(index));
  }

  bool _onOverscroll(OverscrollNotification notification) {
    if (!_swipeEnabled) return false;
    if (!notification.metrics.atEdge) return false;
    if (notification.overscroll < -2 && _currentIndex <= 0) {
      _showEdgeHint('已经是第一集');
    } else if (notification.overscroll > 2 &&
        _currentIndex >= _episodes.length - 1) {
      _showEdgeHint('已经是最后一集');
    }
    return false;
  }

  void _showEdgeHint(String text) {
    final now = DateTime.now();
    if (_hintAt != null &&
        now.difference(_hintAt!) < const Duration(seconds: 2)) {
      return;
    }
    _hintAt = now;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onVideoUpdated() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (value.hasError && _error == null) {
      setState(() => _error = '播放失败，请稍后重试');
      return;
    }
    if (_speed != value.playbackSpeed) {
      _speed = value.playbackSpeed;
    }
    final finished = value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying;
    if (finished && !_panelVisible) {
      _hideTimer?.cancel();
      setState(() => _panelVisible = true);
      return;
    }
    if (_panelVisible && !_dragging) {
      setState(() {});
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    final playing = _controller?.value.isPlaying ?? false;
    if (!playing || _dragging) return;
    _hideTimer = Timer(_hideAfter, () {
      if (!mounted || _dragging) return;
      if (_controller?.value.isPlaying ?? false) {
        setState(() => _panelVisible = false);
      }
    });
  }

  void _showPanel({bool restartTimer = true}) {
    if (!_panelVisible) {
      setState(() => _panelVisible = true);
    }
    if (restartTimer) _scheduleHide();
  }

  void _onTapVideo() {
    if (_panelVisible) {
      _hideTimer?.cancel();
      setState(() => _panelVisible = false);
    } else {
      _showPanel();
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      _hideTimer?.cancel();
      _saveHistory();
      _showPanel(restartTimer: false);
    } else {
      if (controller.value.duration > Duration.zero &&
          controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      _showPanel();
    }
  }

  Future<void> _seekRelative(Duration delta) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    var target = controller.value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await controller.seekTo(target);
    _showPanel();
  }

  Future<void> _seekTo(Duration position) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.seekTo(position);
  }

  Future<void> _showSpeedPicker() async {
    _hideTimer?.cancel();
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: const Color(0xFF1C1D22),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Text(
                    '倍速',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (landscape)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final speed in _speeds)
                          ChoiceChip(
                            label: Text(_speedLabel(speed)),
                            selected: speed == _speed,
                            selectedColor: _accent,
                            labelStyle: TextStyle(
                              color: speed == _speed
                                  ? Colors.white
                                  : Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => Navigator.pop(context, speed),
                          ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final speed in _speeds)
                          ListTile(
                            title: Text(_speedLabel(speed)),
                            trailing: speed == _speed
                                ? const Icon(Icons.check, color: _accent)
                                : null,
                            selected: speed == _speed,
                            selectedColor: _accent,
                            onTap: () => Navigator.pop(context, speed),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (selected != null) {
      setState(() => _speed = selected);
      for (final slot in _slots) {
        final controller = slot.controller;
        if (controller != null && controller.value.isInitialized) {
          unawaited(controller.setPlaybackSpeed(selected));
        }
      }
    }
    _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (!mounted) return;
    setState(() => _fullscreen = !_fullscreen);
    _showPanel();
  }

  Future<void> _onBack() async {
    if (_fullscreen) {
      await _toggleFullscreen();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _retry() async {
    _hideTimer?.cancel();
    _historyTimer?.cancel();
    _saveHistory();
    if (!mounted) return;
    setState(() {
      _error = null;
      _panelVisible = true;
      _dragging = false;
      _dragPosition = null;
    });
    final slot = _slotForIndex(_currentIndex) ?? _slots.first;
    await _loadSlot(slot, _currentIndex, autoplay: true);
  }

  String _speedLabel(double speed) {
    final text = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toString();
    return '${text}x';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  void _startHistoryTimer() {
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveHistory();
    });
  }

  void _saveHistory() {
    final playable = _playable;
    if (!playable.canTrackHistory) return;
    final value = _controller?.value;
    final position = value?.position ?? Duration.zero;
    final duration = value?.duration ?? Duration.zero;
    widget.historyRepository.savePlayable(
      playable,
      position: position,
      duration: duration,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveHistory();
    }
  }

  @override
  void dispose() {
    widget.offlineCacheRepository.removeListener(_onCacheUpdated);
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _historyTimer?.cancel();
    _saveHistory();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _pageController?.dispose();
    for (final slot in _slots) {
      slot.generation++;
      slot.controller?.removeListener(_onVideoUpdated);
      slot.controller?.dispose();
      slot.controller = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreen) {
          _toggleFullscreen();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _buildVideoLayer(),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _error != null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _controller == null || _error != null
                        ? null
                        : _onTapVideo,
                    onDoubleTap: _controller == null || _error != null
                        ? null
                        : _togglePlay,
                  ),
                ),
              ),
              if (_panelVisible) _buildPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoLayer() {
    if (!_canSwitch) return _buildSingleVideo();
    return NotificationListener<OverscrollNotification>(
      onNotification: _onOverscroll,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: _swipeEnabled
            ? const PageScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: _episodes.length,
        onPageChanged: (index) => unawaited(_switchToPage(index)),
        itemBuilder: (context, index) => _buildPage(index),
      ),
    );
  }

  Widget _buildSingleVideo() {
    if (_error != null) {
      return _PlayerMessage(
        message: _error!,
        actionLabel: '重试',
        onAction: _retry,
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    return _videoBox(controller);
  }

  Widget _buildPage(int index) {
    if (_error != null && index == _currentIndex) {
      return _PlayerMessage(
        message: _error!,
        actionLabel: '重试',
        onAction: _retry,
      );
    }
    final slot = _slotForIndex(index);
    final controller = slot?.controller;
    if (controller != null && controller.value.isInitialized) {
      return _videoBox(controller);
    }
    return const Center(child: CircularProgressIndicator(color: _accent));
  }

  Widget _videoBox(VideoPlayerController controller) {
    final aspect = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  void _onCacheUpdated() {
    if (mounted) setState(() {});
  }

  String _localFilePath(String url) {
    if (url.startsWith('file:')) {
      return Uri.parse(url).toFilePath();
    }
    return url;
  }

  OfflineCacheItem? get _cacheItem {
    final playable = _playable;
    if (playable.sourceKey.isEmpty ||
        playable.vodId.isEmpty ||
        playable.episodeId.isEmpty) {
      return null;
    }
    return widget.offlineCacheRepository.findEpisode(
      sourceKey: playable.sourceKey,
      vodId: playable.vodId,
      lineName: playable.lineName,
      episodeId: playable.episodeId,
    );
  }

  bool get _alreadyLocal => _playable.isLocal;

  Future<void> _cacheCurrent() async {
    try {
      await widget.offlineCacheRepository.cachePlayable(_playable);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始缓存本集')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _cancelCache() async {
    final item = _cacheItem;
    if (item == null) return;
    await widget.offlineCacheRepository.cancel(item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已取消缓存')),
    );
  }

  Future<void> _retryCache() async {
    final item = _cacheItem;
    try {
      if (item == null) {
        await _cacheCurrent();
        return;
      }
      await widget.offlineCacheRepository.retry(item.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _absorbVerticalSwipe(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) {},
      onVerticalDragUpdate: (_) {},
      onVerticalDragEnd: (_) {},
      child: child,
    );
  }

  Widget _buildPanel() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final value = ready ? controller.value : null;
    final duration = value?.duration ?? Duration.zero;
    final position = _dragPosition ?? value?.position ?? Duration.zero;
    final playing = value?.isPlaying ?? false;
    final title = _playable.title.isEmpty ? '播放' : _playable.title;
    final maxMs = duration.inMilliseconds.toDouble();
    final posMs =
        position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();
    final playSize = landscape ? 56.0 : 64.0;
    final seekSize = landscape ? 40.0 : 44.0;

    return SafeArea(
      child: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 96,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _absorbVerticalSwipe(
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _onBack,
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_canSwitch) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_currentIndex + 1}/${_episodes.length}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (_playable.canTrackHistory)
                      CacheStatusButton(
                        item: _alreadyLocal
                            ? (_cacheItem ??
                                OfflineCacheItem(
                                  sourceKey: _playable.sourceKey,
                                  vodId: _playable.vodId,
                                  name: _playable.name,
                                  episodeId: _playable.episodeId,
                                  status: OfflineCacheStatus.completed,
                                  createdAtMs: 0,
                                ))
                            : _cacheItem,
                        onCache: _cacheCurrent,
                        onCancel: _cancelCache,
                        onRetry: _retryCache,
                        color: Colors.white,
                        iconSize: 22,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (ready)
            Center(
              child: _absorbVerticalSwipe(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoundControlButton(
                      icon: Icons.replay_10,
                      size: seekSize,
                      onPressed: () => _seekRelative(-_seekStep),
                    ),
                    SizedBox(width: landscape ? 36 : 28),
                    _RoundControlButton(
                      icon: playing ? Icons.pause : Icons.play_arrow,
                      size: playSize,
                      iconSize: landscape ? 34 : 40,
                      onPressed: _togglePlay,
                    ),
                    SizedBox(width: landscape ? 36 : 28),
                    _RoundControlButton(
                      icon: Icons.forward_10,
                      size: seekSize,
                      onPressed: () => _seekRelative(_seekStep),
                    ),
                  ],
                ),
              ),
            ),
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _absorbVerticalSwipe(
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    landscape ? 12 : 8,
                    0,
                    landscape ? 12 : 8,
                    landscape ? 4 : 8,
                  ),
                  child: landscape
                      ? _buildLandscapeBottom(position, duration, maxMs, posMs)
                      : _buildPortraitBottom(position, duration, maxMs, posMs),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPortraitBottom(
    Duration position,
    Duration duration,
    double maxMs,
    double posMs,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _TimeLabel(_formatDuration(position)),
            Expanded(child: _buildSlider(maxMs, posMs)),
            _TimeLabel(_formatDuration(duration)),
          ],
        ),
        Row(
          children: [
            _buildSpeedButton(),
            const Spacer(),
            _buildFullscreenButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildLandscapeBottom(
    Duration position,
    Duration duration,
    double maxMs,
    double posMs,
  ) {
    return Row(
      children: [
        _TimeLabel(_formatDuration(position)),
        if (_canSwitch) _buildEpisodeButton(prev: true),
        Expanded(child: _buildSlider(maxMs, posMs)),
        if (_canSwitch) _buildEpisodeButton(prev: false),
        _TimeLabel(_formatDuration(duration)),
        _buildSpeedButton(),
        _buildFullscreenButton(),
      ],
    );
  }

  Widget _buildEpisodeButton({required bool prev}) {
    final enabled =
        prev ? _currentIndex > 0 : _currentIndex < _episodes.length - 1;
    return TextButton(
      onPressed: enabled
          ? () => _goToEpisode(prev ? _currentIndex - 1 : _currentIndex + 1)
          : null,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        prev ? '上一集' : '下一集',
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white38,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildSlider(double maxMs, double posMs) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: _accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: _accent.withValues(alpha: 0.24),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      child: Slider(
        min: 0,
        max: maxMs <= 0 ? 1 : maxMs,
        value: maxMs <= 0 ? 0 : posMs,
        onChangeStart: maxMs <= 0
            ? null
            : (v) {
                _dragging = true;
                _hideTimer?.cancel();
                setState(() {
                  _dragPosition = Duration(milliseconds: v.round());
                });
              },
        onChanged: maxMs <= 0
            ? null
            : (v) {
                setState(() {
                  _dragPosition = Duration(milliseconds: v.round());
                });
              },
        onChangeEnd: maxMs <= 0
            ? null
            : (v) async {
                final next = Duration(milliseconds: v.round());
                await _seekTo(next);
                _dragging = false;
                _dragPosition = null;
                _scheduleHide();
                if (mounted) setState(() {});
              },
      ),
    );
  }

  Widget _buildSpeedButton() {
    return TextButton(
      onPressed: _showSpeedPicker,
      child: Text(
        _speed == 1.0 ? '倍速' : _speedLabel(_speed),
        style: TextStyle(
          color: _speed == 1.0 ? Colors.white : _accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFullscreenButton() {
    return IconButton(
      tooltip: _fullscreen ? '退出全屏' : '全屏',
      onPressed: _toggleFullscreen,
      icon: Icon(
        _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        color: Colors.white,
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _RoundControlButton extends StatelessWidget {
  const _RoundControlButton({
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.iconSize = 28,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}

class _PlayerMessage extends StatelessWidget {
  const _PlayerMessage({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
