import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_paths.dart';
import '../../core/db/photo_dao.dart';
import '../../state/providers.dart';
import '../library/photo_grid.dart';
import '../widgets/empty_state.dart';

/// Photos grouped by where they were taken.
///
/// No map, no tiles, no network. Picasa drew pins on Google Maps; that is an
/// internet feature and this app does not use the internet. What survives the
/// port is the part people actually browsed: a list of places, largest first.
class PlacesScreen extends ConsumerStatefulWidget {
  const PlacesScreen({super.key});

  @override
  ConsumerState<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends ConsumerState<PlacesScreen> {
  List<PlaceBucket>? _places;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final places = await ref.read(photoDaoProvider).places();
    if (!mounted) return;
    setState(() {
      _places = places;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Places')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final places = _places ?? const <PlaceBucket>[];
    if (places.isEmpty) {
      return const EmptyState(
        icon: Icons.place_outlined,
        title: 'No location data',
        message: 'None of your photos carry GPS coordinates. Photos from a phone '
            'camera usually do; screenshots and scans never will.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 200,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: places.length,
      itemBuilder: (context, i) => _PlaceCard(place: places[i]),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place});

  final PlaceBucket place;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sample = place.samplePhotoId;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlaceDetailScreen(place: place)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: sample == null
                    ? Icon(Icons.place_outlined, color: scheme.onSurfaceVariant)
                    : Image.file(
                        File(AppPaths.thumbPath(sample)),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            place.coordinateLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            '${place.count} photos',
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

class PlaceDetailScreen extends ConsumerWidget {
  const PlaceDetailScreen({super.key, required this.place});

  final PlaceBucket place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(filteredLibraryProvider(place.filter));
    return Scaffold(
      appBar: AppBar(
        title: Text(place.coordinateLabel),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${place.count} photos within about 25 km',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ),
      body: PhotoGrid(
        controller: controller,
        emptyTitle: 'Nothing here',
      ),
    );
  }
}
