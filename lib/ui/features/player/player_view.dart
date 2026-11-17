import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  static const _hideAfter = Duration(seconds: 5);

  VideoPlayerController? _controller;
  String? _error;
  bool _fullscreen = false;
  bool _panelVisible = true;
  bool _dragging = false;
  Duration? _dragPosition;
  double _speed = 1.0;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.enable();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.playable.url),
        httpHeaders: widget.playable.headers,
        formatHint: widget.playable.isHls ? VideoFormat.hls : null,
      );
      _controller = controller;
      controller.addListener(_onVideoUpdated);
      await controller.initialize();
      if (_speed != 1.0) {
        await controller.setPlaybackSpeed(_speed);
      }
      await controller.play();
      if (!mounted) return;
      setState(() {});
      _scheduleHide();
    } catch (e) {
      debugPrint('player init failed: $e');
      if (mounted) setState(() => _error = '播放失败，请稍后重试');
    }
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
      await _controller?.setPlaybackSpeed(selected);
      setState(() => _speed = selected);
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
    _controller?.removeListener(_onVideoUpdated);
    await _controller?.dispose();
    _controller = null;
    if (!mounted) return;
    setState(() {
      _error = null;
      _panelVisible = true;
      _dragging = false;
      _dragPosition = null;
    });
    await _init();
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

  @override
  void dispose() {
    _hideTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _controller?.removeListener(_onVideoUpdated);
    _controller?.dispose();
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
              _buildVideo(),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _controller == null || _error != null
                      ? null
                      : _onTapVideo,
                  onDoubleTap: _controller == null || _error != null
                      ? null
                      : _togglePlay,
                ),
              ),
              if (_panelVisible) _buildPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideo() {
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

  Widget _buildPanel() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final value = ready ? controller.value : null;
    final duration = value?.duration ?? Duration.zero;
    final position = _dragPosition ?? value?.position ?? Duration.zero;
    final playing = value?.isPlaying ?? false;
    final title = widget.playable.title.isEmpty ? '播放' : widget.playable.title;
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
            child: SizedBox(
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
                ],
              ),
            ),
          ),
          if (ready)
            Center(
              child: Row(
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
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
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
        Expanded(child: _buildSlider(maxMs, posMs)),
        _TimeLabel(_formatDuration(duration)),
        _buildSpeedButton(),
        _buildFullscreenButton(),
      ],
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
