import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_paths.dart';
import '../../core/formats/format_registry.dart';
import '../../core/models/album.dart';
import '../../core/models/box_rotation.dart';
import '../../core/models/edit_recipe.dart';
import '../../core/models/photo.dart';
import '../../core/models/person.dart';
import '../../core/models/tone_curve.dart';
import '../../core/scan/exporter.dart';
import '../../core/scan/lut_renderer.dart';
import '../../state/providers.dart';
import '../slideshow/slideshow_screen.dart';
import '../widgets/edited_image.dart';
import '../widgets/image_disposal.dart';
import 'edit_panel.dart';

/// Full-screen viewer with zoom, swipe, live editing, face tagging and
/// non-destructive export.
class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({
    super.key,
    required this.photos,
    this.initialIndex = 0,
  });

  final List<Photo> photos;
  final int initialIndex;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  EditRecipe _recipe = EditRecipe.empty;
  EditRecipe _savedRecipe = EditRecipe.empty;

  /// Pixels decoded through the format registry, for formats the engine cannot
  /// read directly (HEIC, TIFF, RAW, JXL). Null for ordinary JPEG/PNG.
  ui.Image? _decoded;

  /// Debounces the re-render of the live curve preview.
  Timer? _curvePreviewTimer;
  bool _showInfo = true;

  bool? _favoriteOverride;
  bool get _isFavorite => _favoriteOverride ?? _photo.isFavorite;

  bool _tagMode = false;
  Offset? _dragStart;
  Offset? _dragCurrent;
  /// True while the current photo is zoomed in. The PageView is locked out
  /// while it is: a horizontal drag on a zoomed photo is a pan, and letting the
  /// pager claim it flipped to the next photo mid-gesture.
  bool _zoomed = false;

  /// The box the tag gesture started in. Per-gesture rather than a field shared
  /// across pages — with different aspect ratios the neighbour's box is not the
  /// one the user dragged in.
  Size _dragBox = const Size(1, 1);

  /// Decode width, matched to the screen rather than fixed.
  ///
  /// A fixed 2400 px decode is right on a tablet and roughly four times the
  /// pixels a 1080p phone can show, which is peak memory for no visible gain.
  /// Sized from the device pixel width, with a floor so zooming stays sharp.
  int _decodeWidth = 1600;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final physical = (media.size.width * media.devicePixelRatio).round();
    // 1.5x the viewport keeps detail when zoomed, without holding a poster-size
    // bitmap per page.
    _decodeWidth = (physical * 1.5).round().clamp(1080, 2600);
  }
  List<Face> _faces = const <Face>[];

  Photo get _photo => widget.photos[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForCurrent());
  }

  @override
  void dispose() {
    _curvePreviewTimer?.cancel();
    deferImageDisposal(_decoded);
    _page.dispose();
    super.dispose();
  }

  Future<void> _loadForCurrent() async {
    final photo = _photo;
    final recipe = await ref.read(editDaoProvider).recipeFor(photo.id);
    final faces = await ref.read(personDaoProvider).facesFor(photo.id);

    // Decode when the engine cannot read the file, or when a tone curve has to
    // be baked into the pixels. A curve cannot be expressed as a colour matrix,
    // so it is applied to the decoded image instead.
    ui.Image? decoded;
    final needsPixels =
        !ImageFormatRegistry.instance.isEngineNative(photo.path) || recipe.hasCurve;
    if (needsPixels) {
      final base = await ImageFormatRegistry.instance.decode(
        File(photo.path),
        targetWidth: _decodeWidth,
      );
      if (base != null) {
        decoded = recipe.hasCurve
            ? await LutRenderer.applyCurve(base, ToneCurve(recipe.curve))
            : base;
      }
    }

    if (!mounted) {
      deferImageDisposal(decoded);
      return;
    }
    final previous = _decoded;
    setState(() {
      _decoded = decoded;
      _recipe = recipe;
      _savedRecipe = recipe;
      _faces = faces;
    });
    // The outgoing page's RawImage may still hold this for one more frame.
    deferImageDisposal(previous);
  }

  void _onPageChanged(int index) {
    final previous = _decoded;
    setState(() {
      _decoded = null;
      _index = index;
      _tagMode = false;
      _dragStart = null;
      _dragCurrent = null;
      _recipe = EditRecipe.empty;
      _savedRecipe = EditRecipe.empty;
      _faces = const <Face>[];
      _favoriteOverride = null;
    });
    deferImageDisposal(previous);
    _loadForCurrent();
  }

  // ------------------------------------------------------------------ editor

  /// Re-renders the preview with the current curve.
  ///
  /// Applying a 256-entry LUT to a 1400 px image takes tens of milliseconds, so
  /// doing it on every pointer move would make the slider stutter. Debouncing
  /// keeps the drag smooth and still shows the result before the finger stops.
  void _scheduleCurvePreview(EditRecipe recipe) {
    _curvePreviewTimer?.cancel();
    _curvePreviewTimer = Timer(const Duration(milliseconds: 240), () async {
      if (!mounted) return;
      final base = await ImageFormatRegistry.instance.decode(
        File(_photo.path),
        targetWidth: 1400,
      );
      if (base == null) return;
      final image = recipe.hasCurve
          ? await LutRenderer.applyCurve(base, ToneCurve(recipe.curve))
          : base;
      if (!mounted) {
        deferImageDisposal(image);
        return;
      }
      final previous = _decoded;
      setState(() => _decoded = image);
      deferImageDisposal(previous);
    });
  }

  Future<void> _openEditor() async {
    final photo = _photo;
    final editDao = ref.read(editDaoProvider);
    final original = _savedRecipe;
    final aspect = (photo.width != null && photo.height != null && photo.height! > 0)
        ? photo.width! / photo.height!
        : 1.0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.55;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: EditPanel(
                initial: original,
                onChanged: (recipe) {
                  final curveChanged = recipe.curve != _recipe.curve;
                  setState(() => _recipe = recipe);
                  if (curveChanged) _scheduleCurvePreview(recipe);
                },
                file: File(photo.path),
                imageAspect: aspect,
                decoded: _decoded,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _recipe = original);
                        Navigator.pop(sheetContext);
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(sheetContext);
                        final saved = _recipe;
                        await editDao.save(photo.id, saved);

                        // Regenerate the cached thumbnail so the grid tile shows
                        // the edit too. Skipping this is why most photo apps
                        // show the unedited photo in the grid.
                        await Exporter.regenerateThumbnail(photo, saved);
                        final thumb = await AppPaths.thumbFile(photo.id);
                        await FileImage(thumb).evict();

                        if (!mounted) return;
                        setState(() => _savedRecipe = saved);
                        ref.read(libraryControllerProvider).refresh();
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Edit saved')),
                        );
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportCopy() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Rendering edited copy…')),
    );
    final result = await Exporter.exportEdited(_photo, _recipe);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result == null
              ? 'Could not export this file.'
              : 'Saved ${result.file.path.split(Platform.pathSeparator).last} · ${result.report}',
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ albums

  Future<void> _addToAlbum() async {
    final albumDao = ref.read(albumDaoProvider);
    final albums = await albumDao.all();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text('Add to album', style: Theme.of(context).textTheme.titleSmall),
            ),
            if (albums.isEmpty)
              const ListTile(
                subtitle: Text('No albums yet — create one first.'),
              ),
            for (final Album album in albums)
              ListTile(
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: Text(album.name),
                subtitle: Text('${album.count} photos'),
                onTap: () async {
                  await albumDao.addPhotos(album.id, <int>[_photo.id]);
                  ref.invalidate(albumsProvider);
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New album'),
              onTap: () async {
                final name = await _promptText(sheetContext, 'New album name');
                if (name == null || name.isEmpty) return;
                final id = await albumDao.create(name);
                await albumDao.addPhotos(id, <int>[_photo.id]);
                ref.invalidate(albumsProvider);
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- faces

  /// A stored face box, drawn where it appears on the rotated photo.
  Widget _faceBox(Face face, Size box) {
    final shown = BoxRotation.toDisplay(
      Rect.fromLTWH(face.x, face.y, face.w, face.h),
      _recipe.rotate,
    );
    return Positioned(
      left: shown.left * box.width,
      top: shown.top * box.height,
      width: shown.width * box.width,
      height: shown.height * box.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.tealAccent, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Future<void> _finishTagging() async {
    final start = _dragStart;
    final current = _dragCurrent;
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
    if (start == null || current == null) return;

    final rect = Rect.fromPoints(start, current);
    if (rect.width < 12 || rect.height < 12) return;

    // The drag happened on the rotated view; faces are stored unrotated.
    final drawn = Rect.fromLTWH(
      (rect.left / _dragBox.width).clamp(0.0, 1.0),
      (rect.top / _dragBox.height).clamp(0.0, 1.0),
      (rect.width / _dragBox.width).clamp(0.0, 1.0),
      (rect.height / _dragBox.height).clamp(0.0, 1.0),
    );
    final stored = BoxRotation.fromDisplay(drawn, _recipe.rotate);
    final nx = stored.left;
    final ny = stored.top;
    final nw = stored.width;
    final nh = stored.height;

    final personDao = ref.read(personDaoProvider);
    final people = await personDao.all();
    if (!mounted) return;

    final personId = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(title: Text('Who is this?', style: Theme.of(context).textTheme.titleSmall)),
            for (final Person person in people)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(person.name),
                onTap: () => Navigator.pop(sheetContext, person.id),
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('New person'),
              onTap: () async {
                final name = await _promptText(sheetContext, 'Person name');
                if (name == null || name.isEmpty) return;
                final id = await personDao.createOrGet(name);
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext, id);
              },
            ),
          ],
        ),
      ),
    );

    if (personId == null) return;
    await personDao.addFace(
      photoId: _photo.id,
      x: nx,
      y: ny,
      w: nw,
      h: nh,
      personId: personId,
    );
    ref.invalidate(peopleProvider);
    final faces = await personDao.facesFor(_photo.id);
    if (!mounted) return;
    setState(() => _faces = faces);
  }

  Future<String?> _promptText(BuildContext context, String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    var aspect = (photo.width != null && photo.height != null && photo.height! > 0)
        ? photo.width! / photo.height!
        : 1.0;
    // A quarter turn swaps the displayed aspect; without this the box and the
    // picture disagree and everything about zoom and pan feels wrong.
    if ((_recipe.rotate ~/ 90) % 2 == 1) aspect = 1 / aspect;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          photo.fileName,
          style: const TextStyle(fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: _isFavorite ? 'Unfavourite' : 'Favourite',
            icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
            onPressed: () {
              final next = !_isFavorite;
              setState(() => _favoriteOverride = next);
              ref.read(libraryControllerProvider).setFavoriteFlag(photo, next);
            },
          ),
          IconButton(
            tooltip: 'Tag a face',
            icon: Icon(_tagMode ? Icons.person : Icons.person_outline),
            onPressed: () => setState(() {
              _tagMode = !_tagMode;
              _dragStart = null;
              _dragCurrent = null;
            }),
          ),
          IconButton(
            tooltip: 'Add to album',
            icon: const Icon(Icons.collections_bookmark_outlined),
            onPressed: _addToAlbum,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                _openEditor();
              } else if (value == 'export') {
                _exportCopy();
              } else if (value == 'info') {
                setState(() => _showInfo = !_showInfo);
              } else if (value == 'slideshow') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SlideshowScreen(
                      photos: widget.photos,
                      initialIndex: _index,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'edit', child: Text('Adjust…')),
              PopupMenuItem(value: 'export', child: Text('Export edited copy')),
              PopupMenuItem(value: 'slideshow', child: Text('Play slideshow')),
              PopupMenuItem(value: 'info', child: Text('Toggle details')),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: _page,
              onPageChanged: _onPageChanged,
              // While zoomed, a horizontal drag belongs to the photo, not the
              // pager. Without this, panning a zoomed photo swiped to the next.
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: widget.photos.length,
              itemBuilder: (context, i) {
                final item = widget.photos[i];
                final isCurrent = i == _index;
                return Center(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            _ZoomableImage(
                              active: isCurrent,
                              enabled: !_tagMode,
                              onZoomChanged: (zoomed) {
                                if (!mounted || zoomed == _zoomed) return;
                                // This can fire while the parent is rebuilding
                                // (the reset on leaving a page), so defer it.
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted && zoomed != _zoomed) {
                                    setState(() => _zoomed = zoomed);
                                  }
                                });
                              },
                              child: EditedImage(
                                file: File(item.path),
                                recipe: isCurrent ? _recipe : EditRecipe.empty,
                                fit: BoxFit.contain,
                                cacheWidth: _decodeWidth,
                                decoded: isCurrent ? _decoded : null,
                              ),
                            ),
                            if (isCurrent)
                              for (final face in _faces)
                                _faceBox(
                                  face,
                                  Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  ),
                                ),
                            if (isCurrent && _tagMode)
                              GestureDetector(
                                onPanStart: (d) => setState(() {
                                  _dragStart = d.localPosition;
                                  _dragCurrent = d.localPosition;
                                  _dragBox = Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  );
                                }),
                                onPanUpdate: (d) => setState(() {
                                  _dragCurrent = d.localPosition;
                                }),
                                onPanEnd: (_) => _finishTagging(),
                                child: Container(color: Colors.transparent),
                              ),
                            if (isCurrent && _dragStart != null && _dragCurrent != null)
                              Positioned.fromRect(
                                rect: Rect.fromPoints(_dragStart!, _dragCurrent!),
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.tealAccent, width: 2),
                                      color: Colors.tealAccent.withValues(alpha: 0.12),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          if (_showInfo) _InfoStrip(photo: photo, recipe: _recipe),
          if (_tagMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.teal.shade900,
              child: const Text(
                'Drag a box around a face, then pick a person.',
                style: TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.photo, required this.recipe});

  final Photo photo;
  final EditRecipe recipe;

  @override
  Widget build(BuildContext context) {
    final rows = <String>[
      photo.takenLabel,
      if (photo.cameraModel != null) photo.cameraLabel,
      if (photo.exposureLabel != '—') photo.exposureLabel,
      if (photo.width != null) photo.dimensions,
      if (photo.hasGps)
        '${photo.lat!.toStringAsFixed(4)}, ${photo.lon!.toStringAsFixed(4)}',
      if (!recipe.isIdentity) 'Edited',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            rows.first,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            rows.skip(1).join('  ·  '),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// A photo you can pinch, pan and double-tap, which reports whether it is zoomed.
///
/// Three things the bare `InteractiveViewer` got wrong here:
///
/// * A horizontal drag on a zoomed photo was claimed by the surrounding
///   `PageView`, so panning flipped to the next photo instead.
/// * There was no double-tap, which is the gesture everyone reaches for.
/// * Leaving a page kept its zoom, so coming back to it found the photo still
///   magnified and off-centre.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.child,
    required this.active,
    required this.enabled,
    required this.onZoomChanged,
  });

  final Widget child;
  final bool active;
  final bool enabled;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _controller = TransformationController();
  Offset _lastTap = Offset.zero;
  bool _reportedZoom = false;

  static const double _doubleTapScale = 2.6;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_report);
  }

  @override
  void didUpdateWidget(_ZoomableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_report);
    _controller.dispose();
    super.dispose();
  }

  bool get _isZoomed => _controller.value.getMaxScaleOnAxis() > 1.01;

  void _report() {
    if (!mounted) return;
    final zoomed = _isZoomed;
    if (zoomed == _reportedZoom) return;
    _reportedZoom = zoomed;
    widget.onZoomChanged(zoomed);
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _controller.value = Matrix4.identity();
      return;
    }
    // Zoom about the tapped point: the tap position must map to itself, which
    // is what the -p * (scale - 1) translation does.
    final p = _lastTap;
    _controller.value = Matrix4.identity()
      ..translate(
        -p.dx * (_doubleTapScale - 1),
        -p.dy * (_doubleTapScale - 1),
      )
      ..scale(_doubleTapScale);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _lastTap = details.localPosition,
      onDoubleTap: widget.enabled ? _handleDoubleTap : null,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 8,
        panEnabled: widget.enabled,
        scaleEnabled: widget.enabled,
        clipBehavior: Clip.hardEdge,
        child: widget.child,
      ),
    );
  }
}
