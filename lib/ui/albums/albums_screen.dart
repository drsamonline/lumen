import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_paths.dart';
import '../../core/db/photo_dao.dart';
import '../../core/models/album.dart';
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

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(albumLibraryProvider(album.id));
    return Scaffold(
      appBar: AppBar(title: Text(album.name)),
      body: PhotoGrid(
        controller: controller,
        emptyTitle: 'This album is empty',
        emptyMessage: 'Open a photo in the viewer and use "Add to album".',
      ),
    );
  }
}
