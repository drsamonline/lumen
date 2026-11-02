import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_paths.dart';
import '../../core/models/photo.dart';
import '../../core/scan/duplicate_service.dart';
import '../../state/providers.dart';
import '../viewer/viewer_screen.dart';
import '../widgets/empty_state.dart';

/// Near-duplicate review.
///
/// Lumen never deletes anything. It groups the copies, marks the one worth
/// keeping, and tells you how much space the rest are using — the decision stays
/// with the person who took the photos.
class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  List<DuplicateGroup>? _groups;
  DuplicateProgress? _progress;
  bool _busy = false;
  int _pendingHash = 0;
  int _threshold = 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPending());
  }

  Future<void> _loadPending() async {
    final pending = await ref.read(photoDaoProvider).countMissingHash();
    if (!mounted) return;
    setState(() => _pendingHash = pending);
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _progress = null;
      _groups = null;
    });
    try {
      final service = ref.read(duplicateServiceProvider);
      await service.hashMissing(onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      final groups = await service.findGroups(threshold: _threshold);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _busy = false;
        _pendingHash = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Duplicate scan failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicates'),
        actions: <Widget>[
          PopupMenuButton<int>(
            tooltip: 'Sensitivity',
            icon: const Icon(Icons.tune),
            initialValue: _threshold,
            onSelected: (value) => setState(() => _threshold = value),
            itemBuilder: (context) => const <PopupMenuEntry<int>>[
              PopupMenuItem(value: 4, child: Text('Strict — re-encodes only')),
              PopupMenuItem(value: 8, child: Text('Balanced (default)')),
              PopupMenuItem(value: 12, child: Text('Loose — similar shots too')),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_busy) {
      final p = _progress;
      final value = p == null || p.total == 0 ? null : p.hashed / p.total;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                p == null ? 'Reading photos…' : 'Fingerprinting ${p.hashed} of ${p.total}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: value),
              const SizedBox(height: 14),
              Text(
                'Each photo is reduced to a 64-bit visual fingerprint taken from '
                'its thumbnail. Only the fingerprint is compared — no image ever '
                'leaves this device.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final groups = _groups;
    if (groups == null) {
      return EmptyState(
        icon: Icons.filter_none,
        title: 'Find duplicate photos',
        message: _pendingHash == 0
            ? 'Every photo already has a fingerprint. Run a scan to group the copies.'
            : '$_pendingHash photos still need a fingerprint. The first scan reads '
                'each thumbnail once; after that it is instant.',
        action: FilledButton.icon(
          onPressed: _scan,
          icon: const Icon(Icons.search),
          label: Text(_pendingHash == 0 ? 'Scan for duplicates' : 'Fingerprint and scan'),
        ),
      );
    }

    if (groups.isEmpty) {
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: 'No duplicates found',
        message: 'Nothing in the library matches at this sensitivity.',
        action: OutlinedButton(
          onPressed: () => setState(() => _groups = null),
          child: const Text('Back'),
        ),
      );
    }

    final reclaimable = groups.fold<int>(0, (sum, g) => sum + g.wastedBytes);
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Text(
            '${groups.length} groups · ${_mb(reclaimable)} in extra copies',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _GroupCard(
              group: groups[i],
              onOpen: (photo) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ViewerScreen(
                    photos: groups[i].photos,
                    initialIndex: groups[i].photos.indexOf(photo),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _mb(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onOpen});

  final DuplicateGroup group;
  final ValueChanged<Photo> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final best = group.best;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              itemCount: group.photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final photo = group.photos[i];
                final isBest = photo.id == best.id;
                return GestureDetector(
                  onTap: () => onOpen(photo),
                  child: Stack(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 112,
                          height: 112,
                          child: Image.file(
                            File(AppPaths.thumbPath(photo.id)),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(Icons.image_not_supported_outlined,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                      if (isBest)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'KEEP',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              '${group.photos.length} copies · distance ${group.maxDistance} · '
              '${group.photos.first.dimensions} best',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
