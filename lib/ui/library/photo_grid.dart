import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_paths.dart';
import '../../core/models/photo.dart';
import '../../state/library_controller.dart';
import '../../state/providers.dart';
import '../viewer/viewer_screen.dart';
import '../widgets/empty_state.dart';
import 'batch_action_bar.dart';

/// The timeline grid: month headers with photo tiles beneath, exactly the
/// rhythm Picasa used. Paging is driven by scroll position, and thumbnails are
/// requested only for tiles that actually get built.
class PhotoGrid extends ConsumerStatefulWidget {
  const PhotoGrid({
    super.key,
    required this.controller,
    this.emptyTitle = 'No photos here yet',
    this.emptyMessage,
    this.emptyAction,
  });

  final LibraryController controller;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;

  @override
  ConsumerState<PhotoGrid> createState() => _PhotoGridState();
}

class _PhotoGridState extends ConsumerState<PhotoGrid> {
  final ScrollController _scroll = ScrollController();
  final Set<int> _selected = <int>{};
  double _tileExtent = 160;

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(int photoId) {
    setState(() {
      if (!_selected.remove(photoId)) _selected.add(photoId);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _tileExtent = ref.read(settingsProvider).thumbSize;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 1400) {
      widget.controller.loadMore();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  List<_MonthGroup> _group(List<Photo> photos) {
    final groups = <_MonthGroup>[];
    final fmt = DateFormat('MMMM yyyy');
    String? currentKey;
    for (final photo in photos) {
      final key = '${photo.takenAt.year}-${photo.takenAt.month}';
      if (key != currentKey) {
        currentKey = key;
        groups.add(_MonthGroup(label: fmt.format(photo.takenAt)));
      }
      groups.last.photos.add(photo);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    if (controller.isLoading && controller.photos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.photos.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Could not read the library',
        message: controller.error,
      );
    }
    if (controller.photos.isEmpty) {
      return EmptyState(
        icon: Icons.photo_outlined,
        title: widget.emptyTitle,
        message: widget.emptyMessage,
        action: widget.emptyAction,
      );
    }

    final groups = _group(controller.photos);
    final slivers = <Widget>[];

    for (final group in groups) {
      slivers.add(SliverToBoxAdapter(child: _MonthHeader(label: group.label, count: group.photos.length)));
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _tileExtent,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final photo = group.photos[i];
                return _PhotoTile(
                  photo: photo,
                  selected: _selected.contains(photo.id),
                  selecting: _selecting,
                  onTap: () => _selecting ? _toggle(photo.id) : _openViewer(photo),
                  onLongPress: () => _toggle(photo.id),
                );
              },
              childCount: group.photos.length,
            ),
          ),
        ),
      );
    }

    if (controller.isLoadingMore) {
      slivers.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ));
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            child: CustomScrollView(
              controller: _scroll,
              slivers: slivers,
            ),
          ),
        ),
        if (_selecting)
          BatchActionBar(
            selectedIds: _selected.toList(growable: false),
            onClear: _clearSelection,
            onMutated: controller.refresh,
          ),
      ],
    );
  }

  void _openViewer(Photo photo) {
    final photos = widget.controller.photos;
    final index = photos.indexWhere((p) => p.id == photo.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerScreen(photos: photos, initialIndex: index < 0 ? 0 : index),
      ),
    );
  }


}

class _MonthGroup {
  _MonthGroup({required this.label});
  final String label;
  final List<Photo> photos = <Photo>[];
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({
    required this.photo,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.selecting = false,
  });

  final Photo photo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final thumbFile = File(AppPaths.thumbPath(photo.id));
    final hasThumb = thumbFile.existsSync();

    if (!hasThumb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(thumbnailServiceProvider).request(photo.id);
      });
    }

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasThumb)
              Image.file(
                thumbFile,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            else
              const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ),
            if (photo.isFavorite)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.star, size: 14, color: Colors.amber),
              ),
            if (photo.rating > 0)
              Positioned(
                bottom: 4,
                left: 6,
                child: Row(
                  children: <Widget>[
                    for (var i = 0; i < photo.rating; i++)
                      const Icon(Icons.circle, size: 4, color: Colors.white70),
                  ],
                ),
              ),
            if (selecting)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? scheme.primary : Colors.black38,
                    border: Border.all(color: Colors.white70, width: 1.5),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 13, color: scheme.onPrimary)
                      : null,
                ),
              ),
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
