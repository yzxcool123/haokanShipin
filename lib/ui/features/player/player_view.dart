import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../domain/models/playable.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({super.key, required this.playable});

  final Playable playable;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const _accent = Color(0xFF7C9CFF);
  static const _seekStep = Duration(seconds: 10);

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String? _error;
  bool _looping = false;
  double _speed = 1.0;
  String? _seekHint;
  Timer? _seekHintTimer;
  DateTime? _lastTapAt;
  Offset? _lastTapPos;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.playable.url),
        httpHeaders: widget.playable.headers,
        formatHint: widget.playable.isHls ? VideoFormat.hls : null,
      );
      _videoController = controller;
      controller.addListener(_onVideoUpdated);
      await controller.initialize();
      await controller.setLooping(_looping);
      if (_speed != 1.0) {
        await controller.setPlaybackSpeed(_speed);
      }
      final ratio = controller.value.aspectRatio;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        allowedScreenSleep: false,
        zoomAndPan: true,
        draggableProgressBar: true,
        showOptions: true,
        showControls: true,
        showControlsOnInitialize: true,
        hideControlsTimer: const Duration(seconds: 4),
        playbackSpeeds: _speeds,
        aspectRatio: ratio == 0 ? 16 / 9 : ratio,
        optionsTranslation: OptionsTranslation(
          playbackSpeedButtonText: '倍速',
          subtitlesButtonText: '字幕',
          cancelButtonText: '取消',
        ),
        additionalOptions: (context) => [
          OptionItem(
            onTap: (ctx) {
              Navigator.pop(ctx);
              _toggleLoop();
            },
            iconData: Icons.loop,
            title: '循环播放',
            subtitle: _looping ? '已开启' : '已关闭',
          ),
        ],
        materialProgressColors: ChewieProgressColors(
          playedColor: _accent,
          handleColor: Colors.white,
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white24,
        ),
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: _accent,
          handleColor: Colors.white,
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white24,
        ),
        errorBuilder: (context, errorMessage) => _PlayerMessage(
          message: '播放失败，请稍后重试',
          actionLabel: '重试',
          onAction: _retry,
        ),
        bufferingBuilder: (context) => const Center(
          child: CircularProgressIndicator(color: _accent),
        ),
        deviceOrientationsOnEnterFullScreen: const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('player init failed: $e');
      if (mounted) setState(() => _error = '播放失败，请稍后重试');
    }
  }

  void _onVideoUpdated() {
    final controller = _videoController;
    if (controller == null || !mounted) return;
    final speed = controller.value.playbackSpeed;
    if (speed != _speed) {
      setState(() => _speed = speed);
    }
  }

  Future<void> _retry() async {
    _seekHintTimer?.cancel();
    _seekHintTimer = null;
    _chewieController?.dispose();
    _videoController?.removeListener(_onVideoUpdated);
    await _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
    if (!mounted) return;
    setState(() {
      _error = null;
      _seekHint = null;
    });
    await _init();
  }

  void _toggleLoop() {
    setState(() => _looping = !_looping);
    _videoController?.setLooping(_looping);
  }

  String _speedLabel(double speed) {
    final text = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toString();
    return '${text}x';
  }

  Future<void> _showSpeedPicker() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: const Color(0xFF1C1D22),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
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
        );
      },
    );
    if (selected == null || !mounted) return;
    await _videoController?.setPlaybackSpeed(selected);
    if (mounted) setState(() => _speed = selected);
  }

  void _onPointerDown(PointerDownEvent event, BoxConstraints constraints) {
    final topReserve = MediaQuery.paddingOf(context).top + 56;
    const controlReserve = 96.0;
    if (event.localPosition.dy < topReserve) return;
    if (event.localPosition.dy > constraints.maxHeight - controlReserve) {
      return;
    }
    final now = DateTime.now();
    final pos = event.localPosition;
    final lastAt = _lastTapAt;
    final lastPos = _lastTapPos;
    _lastTapAt = now;
    _lastTapPos = pos;
    if (lastAt == null || lastPos == null) return;
    if (now.difference(lastAt) > const Duration(milliseconds: 280)) return;
    if ((pos - lastPos).distance > 48) return;

    final rewind = pos.dx < constraints.maxWidth / 2;
    _seekRelative(rewind ? -_seekStep : _seekStep);
  }

  void _seekRelative(Duration delta) {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    var target = controller.value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    controller.seekTo(target);
    final seconds = delta.inSeconds;
    setState(() {
      _seekHint = seconds < 0 ? '快退 ${-seconds} 秒' : '快进 $seconds 秒';
    });
    _seekHintTimer?.cancel();
    _seekHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  void _onBack() {
    final chewie = _chewieController;
    if (chewie != null && chewie.isFullScreen) {
      chewie.exitFullScreen();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _seekHintTimer?.cancel();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _videoController?.removeListener(_onVideoUpdated);
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBody(),
            _buildOverlayBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayBar() {
    final ready = _chewieController != null && _error == null;
    final title = widget.playable.title.isEmpty ? '播放' : widget.playable.title;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                onPressed: _onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              if (ready) ...[
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
                TextButton(
                  onPressed: _showSpeedPicker,
                  child: Text(
                    _speed == 1.0 ? '倍速' : _speedLabel(_speed),
                    style: TextStyle(
                      color: _speed == 1.0 ? Colors.white : _accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _looping ? '关闭循环播放' : '开启循环播放',
                  onPressed: _toggleLoop,
                  icon: Icon(
                    Icons.loop,
                    color: _looping ? _accent : Colors.white,
                  ),
                ),
              ] else
                const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _PlayerMessage(
        message: _error!,
        actionLabel: '重试',
        onAction: _retry,
      );
    }
    if (_chewieController == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerDown: (event) => _onPointerDown(event, constraints),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Chewie(controller: _chewieController!),
              if (_seekHint != null)
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: 1,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _seekHint!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
