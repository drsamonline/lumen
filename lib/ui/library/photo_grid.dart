import 'dart:io';
import 'dart:math' as math;

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

  /// Approximate scroll offset of each year, so the scrubber can jump straight
  /// there. The estimate uses the same column formula as the grid delegate and
  /// the known tile and header heights, which lands within a row — close enough
  /// for a scrubber, and far cheaper than measuring every sliver.
  List<_ScrubMarker> _markers(List<_MonthGroup> groups, double width) {
    final usable = width - 24;
    final columns = usable <= 0
        ? 1
        : math.max(1, (usable / (_tileExtent + 4)).ceil());
    const headerHeight = 48.0;
    final rowHeight = _tileExtent + 4;

    final markers = <_ScrubMarker>[];
    var offset = 0.0;
    int? lastYear;

    for (final group in groups) {
      if (group.photos.isEmpty) continue;
      final year = group.photos.first.takenAt.year;
      if (year != lastYear) {
        markers.add(_ScrubMarker(year: year, offset: offset));
        lastYear = year;
      }
      final rows = (group.photos.length / columns).ceil();
      offset += headerHeight + rows * rowHeight + 10;
    }
    return markers;
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Decide whether the rail is shown, then give it its own column
              // rather than overlaying it. As an overlay it covered part of the
              // last column, so the rightmost tile in every row was partly
              // untappable and the year labels sat on top of photos.
              const railWidth = 34.0;
              var markers = _markers(groups, constraints.maxWidth);
              final showRail = markers.length >= 3 && !_selecting;
              if (showRail) {
                markers = _markers(groups, constraints.maxWidth - railWidth);
              }

              final scroll = RefreshIndicator(
                onRefresh: controller.refresh,
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: slivers,
                ),
              );

              if (!showRail) return scroll;

              return Row(
                children: <Widget>[
                  Expanded(child: scroll),
                  SizedBox(
                    width: railWidth,
                    child: _YearScrubber(
                      markers: markers,
                      onSeek: (offset) {
                        if (!_scroll.hasClients) return;
                        final max = _scroll.position.maxScrollExtent;
                        _scroll.jumpTo(offset.clamp(0.0, max));
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (_selecting)
          BatchActionBar(
            controller: controller,
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

class _ScrubMarker {
  const _ScrubMarker({required this.year, required this.offset});
  final int year;
  final double offset;
}

/// A vertical year rail down the right edge, as Picasa had.
///
/// Dragging anywhere on the rail jumps to the nearest year, which is the only
/// navigation that works when the library is ten thousand photos long and the
/// scrollbar tells you nothing.
class _YearScrubber extends StatefulWidget {
  const _YearScrubber({required this.markers, required this.onSeek});

  final List<_ScrubMarker> markers;
  final ValueChanged<double> onSeek;

  @override
  State<_YearScrubber> createState() => _YearScrubberState();
}

class _YearScrubberState extends State<_YearScrubber> {
  int? _activeYear;

  void _seekTo(double dy, double height) {
    if (height <= 0) return;
    final fraction = (dy / height).clamp(0.0, 0.9999);
    final index = (fraction * widget.markers.length).floor();
    final marker = widget.markers[index.clamp(0, widget.markers.length - 1)];
    setState(() => _activeYear = marker.year);
    widget.onSeek(marker.offset);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (d) => _seekTo(d.localPosition.dy, context.size?.height ?? 0),
      onVerticalDragUpdate: (d) => _seekTo(d.localPosition.dy, context.size?.height ?? 0),
      onVerticalDragEnd: (_) => setState(() => _activeYear = null),
      onTapDown: (d) => _seekTo(d.localPosition.dy, context.size?.height ?? 0),
      onTapUp: (_) => setState(() => _activeYear = null),
      child: SizedBox(
        width: 40,
        child: Stack(
          children: <Widget>[
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (final marker in widget.markers)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          style: TextStyle(
                            fontSize: _activeYear == marker.year ? 12 : 10,
                            fontWeight: _activeYear == marker.year
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _activeYear == marker.year
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          child: Text('${marker.year}'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
