import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/album.dart';
import '../../core/models/edit_recipe.dart';
import '../../core/models/photo.dart';
import '../../core/models/person.dart';
import '../../core/scan/exporter.dart';
import '../../state/providers.dart';
import '../widgets/edited_image.dart';
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
  bool _showInfo = true;

  bool? _favoriteOverride;
  bool get _isFavorite => _favoriteOverride ?? _photo.isFavorite;

  bool _tagMode = false;
  Offset? _dragStart;
  Offset? _dragCurrent;
  Size _imageBox = const Size(1, 1);
  List<Face> _faces = const <Face>[];

  Photo get _photo => widget.photos[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForCurrent());
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _loadForCurrent() async {
    final photo = _photo;
    final recipe = await ref.read(editDaoProvider).recipeFor(photo.id);
    final faces = await ref.read(personDaoProvider).facesFor(photo.id);
    if (!mounted) return;
    setState(() {
      _recipe = recipe;
      _savedRecipe = recipe;
      _faces = faces;
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      _tagMode = false;
      _dragStart = null;
      _dragCurrent = null;
      _recipe = EditRecipe.empty;
      _savedRecipe = EditRecipe.empty;
      _faces = const <Face>[];
      _favoriteOverride = null;
    });
    _loadForCurrent();
  }

  // ------------------------------------------------------------------ editor

  Future<void> _openEditor() async {
    final photo = _photo;
    final editDao = ref.read(editDaoProvider);
    final original = _savedRecipe;

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
                onChanged: (recipe) => setState(() => _recipe = recipe),
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
                        await editDao.save(photo.id, _recipe);
                        if (!mounted) return;
                        setState(() => _savedRecipe = _recipe);
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(context).showSnackBar(
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

    final nx = (rect.left / _imageBox.width).clamp(0.0, 1.0);
    final ny = (rect.top / _imageBox.height).clamp(0.0, 1.0);
    final nw = (rect.width / _imageBox.width).clamp(0.0, 1.0);
    final nh = (rect.height / _imageBox.height).clamp(0.0, 1.0);

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
    final aspect = (photo.width != null && photo.height != null && photo.height! > 0)
        ? photo.width! / photo.height!
        : 1.0;

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
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'edit', child: Text('Adjust…')),
              PopupMenuItem(value: 'export', child: Text('Export edited copy')),
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
              itemCount: widget.photos.length,
              itemBuilder: (context, i) {
                final item = widget.photos[i];
                final isCurrent = i == _index;
                return Center(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _imageBox = Size(constraints.maxWidth, constraints.maxHeight);
                        return Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            InteractiveViewer(
                              minScale: 1,
                              maxScale: 6,
                              panEnabled: !_tagMode,
                              scaleEnabled: !_tagMode,
                              child: EditedImage(
                                file: File(item.path),
                                recipe: isCurrent ? _recipe : EditRecipe.empty,
                                fit: BoxFit.contain,
                                cacheWidth: 2400,
                              ),
                            ),
                            if (isCurrent)
                              for (final face in _faces)
                                Positioned(
                                  left: face.x * constraints.maxWidth,
                                  top: face.y * constraints.maxHeight,
                                  width: face.w * constraints.maxWidth,
                                  height: face.h * constraints.maxHeight,
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.tealAccent,
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                            if (isCurrent && _tagMode)
                              GestureDetector(
                                onPanStart: (d) => setState(() {
                                  _dragStart = d.localPosition;
                                  _dragCurrent = d.localPosition;
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
