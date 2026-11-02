import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/export/album_zip.dart';
import '../../core/models/album.dart';
import '../../core/models/photo.dart';
import '../../state/library_controller.dart';
import '../../state/providers.dart';

/// Actions that apply to a whole selection.
///
/// Everything here is reversible: ratings, favourites and album membership can
/// all be undone. Nothing deletes a file.
class BatchActionBar extends ConsumerStatefulWidget {
  const BatchActionBar({
    super.key,
    required this.controller,
    required this.selectedIds,
    required this.onClear,
    required this.onMutated,
  });

  /// The controller that owns the grid this bar belongs to.
  ///
  /// Reading `libraryControllerProvider` here instead would mutate the main
  /// library while the user is looking at an album or a person — the rows would
  /// change in the database and nothing would change on screen.
  final LibraryController controller;

  final List<int> selectedIds;
  final VoidCallback onClear;
  final VoidCallback onMutated;

  @override
  ConsumerState<BatchActionBar> createState() => _BatchActionBarState();
}

class _BatchActionBarState extends ConsumerState<BatchActionBar> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = widget.selectedIds.length;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: <Widget>[
                  Text(
                    '$count selected',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Clear selection',
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClear,
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 62,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: <Widget>[
                  for (var star = 1; star <= 5; star++)
                    _BatchButton(
                      icon: Icons.star,
                      label: '$star',
                      onTap: _busy ? null : () => _rate(star),
                    ),
                  _BatchButton(
                    icon: Icons.star_border,
                    label: '0',
                    onTap: _busy ? null : () => _rate(0),
                  ),
                  const VerticalDivider(width: 12, indent: 12, endIndent: 12),
                  _BatchButton(
                    icon: Icons.favorite_border,
                    label: 'Favourite',
                    onTap: _busy ? null : () => _favorite(true),
                  ),
                  _BatchButton(
                    icon: Icons.heart_broken_outlined,
                    label: 'Unfav',
                    onTap: _busy ? null : () => _favorite(false),
                  ),
                  _BatchButton(
                    icon: Icons.collections_bookmark_outlined,
                    label: 'Album',
                    onTap: _busy ? null : _addToAlbum,
                  ),
                  _BatchButton(
                    icon: Icons.archive_outlined,
                    label: 'ZIP',
                    onTap: _busy ? null : _exportZip,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rate(int stars) async {
    await widget.controller.setRatingForAll(widget.selectedIds, stars);
    widget.onMutated();
  }

  Future<void> _favorite(bool value) async {
    await widget.controller.setFavoriteForAll(widget.selectedIds, value);
    widget.onMutated();
  }

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
              title: Text(
                'Add ${widget.selectedIds.length} photos to album',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final Album album in albums)
              ListTile(
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: Text(album.name),
                subtitle: Text('${album.count} photos'),
                onTap: () async {
                  await albumDao.addPhotos(album.id, widget.selectedIds);
                  ref.invalidate(albumsProvider);
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  widget.onClear();
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New album'),
              onTap: () async {
                final controller = TextEditingController();
                final name = await showDialog<String>(
                  context: sheetContext,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('New album'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                );
                controller.dispose();
                if (name == null || name.isEmpty) return;
                final id = await albumDao.create(name);
                await albumDao.addPhotos(id, widget.selectedIds);
                ref.invalidate(albumsProvider);
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                widget.onClear();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportZip() async {
    final messenger = ScaffoldMessenger.of(context);
    final dao = ref.read(photoDaoProvider);

    String? directory;
    try {
      directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Where should the ZIP go?',
      );
    } catch (_) {
      directory = null;
    }
    if (directory == null) return;

    setState(() => _busy = true);
    try {
      final photos = <Photo>[];
      for (final id in widget.selectedIds) {
        final photo = await dao.byId(id);
        if (photo != null) photos.add(photo);
      }
      final result = await AlbumZip.export(
        photos: photos,
        directory: directory,
        baseName: 'lumen-selection-${photos.length}',
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${result.count} photos · ${result.sizeLabel}'
            '${result.skipped > 0 ? ' · ${result.skipped} unreadable' : ''}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _BatchButton extends StatelessWidget {
  const _BatchButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 20, color: onTap == null ? scheme.onSurfaceVariant : null),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
