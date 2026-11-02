import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/photo_dao.dart';
import '../../state/providers.dart';
import '../duplicates/duplicates_screen.dart';
import '../places/places_screen.dart';
import '../slideshow/slideshow_screen.dart';
import 'photo_grid.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(libraryControllerProvider);
    final scan = ref.watch(scanControllerProvider);
    final progress = scan.progress;

    return Scaffold(
      appBar: AppBar(
        title: Text('Library'),
        bottom: scan.isScanning
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Indexing… ${progress.scanned} files'
                          '${progress.current != null ? ' · ${progress.current}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        actions: <Widget>[
          IconButton(
            tooltip: 'Rescan library',
            icon: const Icon(Icons.refresh),
            onPressed: scan.isScanning
                ? null
                : () async {
                    await scan.scanAll();
                    await controller.refresh();
                  },
          ),
          PopupMenuButton<PhotoSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: controller.filter.sort,
            onSelected: (sort) => controller.setFilter(controller.filter.copyWith(sort: sort)),
            itemBuilder: (context) => const <PopupMenuEntry<PhotoSort>>[
              PopupMenuItem(value: PhotoSort.dateTakenDesc, child: Text('Newest first')),
              PopupMenuItem(value: PhotoSort.dateTakenAsc, child: Text('Oldest first')),
              PopupMenuItem(value: PhotoSort.dateAddedDesc, child: Text('Recently indexed')),
              PopupMenuItem(value: PhotoSort.nameAsc, child: Text('File name')),
            ],
          ),
          IconButton(
            tooltip: 'Favourites only',
            icon: Icon(controller.filter.favoritesOnly ? Icons.star : Icons.star_border),
            onPressed: () => controller.setFilter(
              controller.filter.copyWith(favoritesOnly: !controller.filter.favoritesOnly),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'slideshow') {
                if (controller.photos.isEmpty) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SlideshowScreen(photos: controller.photos),
                  ),
                );
              } else if (value == 'duplicates') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const DuplicatesScreen()),
                );
              } else if (value == 'places') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PlacesScreen()),
                );
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: 'slideshow',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.slideshow_outlined),
                  title: Text('Slideshow'),
                ),
              ),
              PopupMenuItem(
                value: 'duplicates',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.filter_none),
                  title: Text('Find duplicates'),
                ),
              ),
              PopupMenuItem(
                value: 'places',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.place_outlined),
                  title: Text('Places'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _FilterStrip(ref: ref),
          Expanded(
            child: PhotoGrid(
              controller: controller,
              emptyTitle: 'Your library is empty',
              emptyMessage:
                  'Add a folder in Settings and Lumen will index every photo inside it. '
                  'Nothing leaves your device.',
              emptyAction: FilledButton.tonalIcon(
                onPressed: () async {
                  await scan.scanAll();
                  await controller.refresh();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Scan now'),
              ),
            ),
          ),
          _StatusBar(count: controller.total, filtered: controller.filter.isActive),
        ],
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(libraryControllerProvider);
    final filter = controller.filter;
    if (!filter.isActive) return const SizedBox.shrink();

    final chips = <Widget>[];
    if (filter.query.isNotEmpty) {
      chips.add(InputChip(
        label: Text('"${filter.query}"'),
        onDeleted: () => controller.setFilter(filter.copyWith(query: '')),
      ));
    }
    if (filter.folder != null) {
      chips.add(InputChip(
        label: Text(filter.folder!.split(RegExp(r'[/\\]')).last),
        onDeleted: () => controller.setFilter(filter.copyWith(clearFolder: true)),
      ));
    }
    if (filter.favoritesOnly) {
      chips.add(InputChip(
        label: const Text('Favourites'),
        onDeleted: () => controller.setFilter(filter.copyWith(favoritesOnly: false)),
      ));
    }
    if (filter.minRating > 0) {
      chips.add(InputChip(
        label: Text('${filter.minRating}+ stars'),
        onDeleted: () => controller.setFilter(filter.copyWith(minRating: 0)),
      ));
    }
    if (filter.albumId != null) {
      chips.add(InputChip(
        label: const Text('Album'),
        onDeleted: () => controller.setFilter(filter.copyWith(clearAlbum: true)),
      ));
    }
    if (filter.nearLat != null && filter.nearLon != null) {
      chips.add(InputChip(
        label: Text(
          '${filter.nearLat!.abs().toStringAsFixed(1)}°, '
          '${filter.nearLon!.abs().toStringAsFixed(1)}°',
        ),
        onDeleted: () => controller.setFilter(filter.copyWith(clearPlace: true)),
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: <Widget>[
          ...chips,
          const SizedBox(width: 8),
          TextButton(
            onPressed: controller.clearFilter,
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.count, required this.filtered});

  final int count;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 28,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Text(
        filtered ? '$count matching photos' : '$count photos',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
