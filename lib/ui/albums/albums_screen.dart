import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/app_paths.dart';
import '../../core/db/photo_dao.dart';
import '../../core/export/zip_writer.dart';
import '../../core/models/album.dart';
import '../../core/models/photo.dart';
import '../../state/providers.dart';
import '../library/photo_grid.dart';
import '../widgets/empty_state.dart';

class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        actions: <Widget>[
          IconButton(
            tooltip: 'New album',
            icon: const Icon(Icons.add),
            onPressed: () => _createAlbum(context, ref),
          ),
        ],
      ),
      body: albums.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Could not load albums', message: e.toString()),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.collections_bookmark_outlined,
              title: 'No albums yet',
              message: 'Albums are virtual collections — a photo can sit in as many '
                  'as you like without being copied anywhere.',
              action: FilledButton.tonalIcon(
                onPressed: () => _createAlbum(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Create album'),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 210,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) => _AlbumCard(album: list[i]),
          );
        },
      ),
    );
  }

  Future<void> _createAlbum(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New album'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name', border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await ref.read(albumDaoProvider).create(name);
    ref.invalidate(albumsProvider);
  }
}

class _AlbumCard extends ConsumerWidget {
  const _AlbumCard({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cover = album.coverPhotoId;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => AlbumDetailScreen(album: album)),
      ),
      onLongPress: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Delete "${album.name}"?'),
            content: const Text('The photos themselves are not deleted.'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
            ],
          ),
        );
        if (confirmed != true) return;
        await ref.read(albumDaoProvider).delete(album.id);
        ref.invalidate(albumsProvider);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: cover == null
                    ? Icon(Icons.collections_bookmark_outlined, color: scheme.onSurfaceVariant)
                    : Image.file(
                        File(AppPaths.thumbPath(cover)),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            '${album.count} photos',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({super.key, required this.album});

  final Album album;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(albumLibraryProvider(widget.album.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        actions: <Widget>[
          if (_exporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Export album as ZIP',
              icon: const Icon(Icons.archive_outlined),
              onPressed: _exportZip,
            ),
        ],
      ),
      body: PhotoGrid(
        controller: controller,
        emptyTitle: 'This album is empty',
        emptyMessage: 'Open a photo in the viewer and use "Add to album".',
      ),
    );
  }

  /// Bundles the album into a store-only ZIP.
  ///
  /// Photos are already compressed, so DEFLATE would burn CPU for ~0% gain.
  /// The archive streams straight to disk, so album size is limited by free
  /// space rather than by RAM.
  Future<void> _exportZip() async {
    final messenger = ScaffoldMessenger.of(context);
    final dao = ref.read(photoDaoProvider);

    final ids = await dao.idsFor(PhotoFilter(albumId: widget.album.id));
    if (ids.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('This album is empty.')));
      return;
    }

    final photos = <Photo>[];
    for (final id in ids) {
      final photo = await dao.byId(id);
      if (photo != null) photos.add(photo);
    }

    String? directory;
    try {
      directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Where should the ZIP go?',
      );
    } catch (_) {
      directory = null;
    }
    if (directory == null) return;

    setState(() => _exporting = true);
    try {
      final safeName = widget.album.name
          .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '-');
      final target = File(p.join(directory, '${safeName.isEmpty ? 'album' : safeName}.zip'));

      final sources = <ZipSource>[];
      for (var i = 0; i < photos.length; i++) {
        final photo = photos[i];
        final file = File(photo.path);
        if (!await file.exists()) continue;
        sources.add(ZipSource.file(
          '${i + 1}-${photo.fileName}',
          file,
        ));
      }

      final bytes = await ZipArchiveWriter.write(target, sources);
      messenger.showSnackBar(SnackBar(
        content: Text(
          '${sources.length} photos · ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB '
          '→ ${p.basename(target.path)}',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
