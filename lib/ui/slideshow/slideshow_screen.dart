import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formats/format_registry.dart';
import '../../core/models/edit_recipe.dart';
import '../../core/models/photo.dart';
import '../../state/providers.dart';
import '../widgets/edited_image.dart';
import '../widgets/image_disposal.dart';

/// Full-screen slideshow — Picasa's screensaver, which is honestly how a lot of
/// people used it.
///
/// Keyboard first, because a slideshow is a lean-back experience: arrows to
/// step, space to pause, Escape to leave.
class SlideshowScreen extends ConsumerStatefulWidget {
  const SlideshowScreen({
    super.key,
    required this.photos,
    this.initialIndex = 0,
    this.interval = const Duration(seconds: 5),
  });

  final List<Photo> photos;
  final int initialIndex;
  final Duration interval;

  @override
  ConsumerState<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends ConsumerState<SlideshowScreen> {
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  late Duration _interval = widget.interval;

  Timer? _timer;
  bool _playing = true;
  bool _chromeVisible = true;
  Timer? _chromeTimer;

  final Map<int, EditRecipe> _recipes = <int, EditRecipe>{};
  final Map<int, ui.Image?> _decoded = <int, ui.Image?>{};

  @override
  void initState() {
    super.initState();
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chromeTimer?.cancel();
    for (final image in _decoded.values) {
      deferImageDisposal(image);
    }
    _page.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _advance(1));
  }

  void _advance(int delta) {
    if (widget.photos.isEmpty) return;
    final next = _index + delta;
    if (next < 0 || next >= widget.photos.length) {
      // Wrap rather than stop — a slideshow that ends is a slideshow nobody
      // leaves running on a TV.
      final wrapped = next < 0 ? widget.photos.length - 1 : 0;
      _page.jumpToPage(wrapped);
      return;
    }
    _page.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _prefetch() async {
    // Load the current photo and the next two, so the transition never shows a
    // blank frame.
    for (var offset = 0; offset < 3; offset++) {
      final i = _index + offset;
      if (i >= widget.photos.length) break;
      await _load(i);
    }
    if (mounted) setState(() {});
  }

  Future<void> _load(int index) async {
    final photo = widget.photos[index];
    if (_recipes.containsKey(photo.id)) return;

    final recipe = await ref.read(editDaoProvider).recipeFor(photo.id);
    _recipes[photo.id] = recipe;

    if (!ImageFormatRegistry.instance.isEngineNative(photo.path)) {
      final image = await ImageFormatRegistry.instance.decode(
        File(photo.path),
        targetWidth: 1920,
      );
      _decoded[photo.id] = image;
    }

    // Without this a swiped-to photo that needed an exotic decode stayed blank
    // until the auto-advance timer happened to rebuild.
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _start();
      } else {
        _timer?.cancel();
      }
    });
  }

  void _setInterval(Duration value) {
    setState(() => _interval = value);
    if (_playing) _start();
  }

  void _bumpChrome() {
    _chromeTimer?.cancel();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.pageDown) {
      _bumpChrome();
      _advance(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp) {
      _bumpChrome();
      _advance(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      _togglePlay();
      _bumpChrome();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.photos.length;
    final progress = total <= 1 ? 1.0 : (_index + 1) / total;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final width = MediaQuery.sizeOf(context).width;
                final dx = details.localPosition.dx;
                _bumpChrome();
                if (dx < width * 0.3) {
                  _advance(-1);
                } else if (dx > width * 0.7) {
                  _advance(1);
                } else {
                  _togglePlay();
                }
              },
              child: PageView.builder(
                controller: _page,
                itemCount: total,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _load(i);
                  // Warm the next two frames ahead of the timer.
                  for (var k = 1; k <= 2; k++) {
                    if (i + k < total) _load(i + k);
                  }
                },
                itemBuilder: (context, i) {
                  final photo = widget.photos[i];
                  final recipe = _recipes[photo.id] ?? EditRecipe.empty;
                  return Center(
                    child: EditedImage(
                      file: File(photo.path),
                      recipe: recipe,
                      fit: BoxFit.contain,
                      cacheWidth: 1920,
                      decoded: _decoded[photo.id],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 260),
                child: IgnorePointer(
                  ignoring: !_chromeVisible,
                  child: _Chrome(
                    index: _index,
                    total: total,
                    playing: _playing,
                    interval: _interval,
                    progress: progress,
                    caption: total == 0 ? '' : widget.photos[_index].fileName,
                    onTogglePlay: _togglePlay,
                    onInterval: _setInterval,
                    onClose: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
            if (total == 0)
              const Center(
                child: Text(
                  'Nothing to show',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.index,
    required this.total,
    required this.playing,
    required this.interval,
    required this.progress,
    required this.caption,
    required this.onTogglePlay,
    required this.onInterval,
    required this.onClose,
  });

  final int index;
  final int total;
  final bool playing;
  final Duration interval;
  final double progress;
  final String caption;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onInterval;
  final VoidCallback onClose;

  static const _intervals = <Duration>[
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              IconButton(
                onPressed: onTogglePlay,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                color: Colors.white,
                tooltip: playing ? 'Pause' : 'Play',
              ),
              Text(
                total == 0 ? '' : '${index + 1} / $total',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              for (final value in _intervals)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    label: Text('${value.inSeconds}s'),
                    selected: interval == value,
                    onSelected: (_) => onInterval(value),
                    labelStyle: const TextStyle(fontSize: 11),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                color: Colors.white,
                tooltip: 'Exit (Esc)',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
