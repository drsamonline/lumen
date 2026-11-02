import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/scan/cache_compactor.dart';
import '../state/providers.dart';

/// Frees disk taken by the thumbnail cache.
///
/// The dialog always shows the numbers before offering a button, and says
/// plainly that a thumbnail is regenerable. Nothing here can touch a photo —
/// that is the whole reason it is safe to put a destructive-looking button on
/// a settings screen.
class ReclaimSpaceDialog extends ConsumerStatefulWidget {
  const ReclaimSpaceDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ReclaimSpaceDialog(),
    );
  }

  @override
  ConsumerState<ReclaimSpaceDialog> createState() => _ReclaimSpaceDialogState();
}

class _ReclaimSpaceDialogState extends ConsumerState<ReclaimSpaceDialog> {
  CacheReport? _report;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _survey();
  }

  Future<void> _survey() async {
    final report = await ref.read(cacheCompactorProvider).survey();
    if (!mounted) return;
    setState(() => _report = report);
  }

  Future<void> _run(Future<int> Function() action, String what) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final freed = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = freed == 0
          ? 'Nothing to free.'
          : 'Freed ${CacheCompactor.human(freed)} — $what.';
    });
    await _survey();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final report = _report;

    return AlertDialog(
      title: const Text('Reclaim space'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Lumen keeps a thumbnail for every photo. They are rebuilt from '
                'the original whenever they are missing, so deleting them costs '
                'a re-render and nothing else. Your photos are never touched.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              if (report == null)
                const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else ...<Widget>[
                _Row(
                  label: 'Thumbnails on disk',
                  value: '${report.thumbFiles} · ${CacheCompactor.human(report.thumbBytes)}',
                ),
                _Row(
                  label: 'Photos in the index',
                  value: '${report.livePhotos}',
                ),
                _Row(
                  label: 'Orphaned thumbnails',
                  value: '${report.orphanFiles} · ${CacheCompactor.human(report.orphanBytes)}',
                  highlight: report.orphanFiles > 0,
                ),
                const SizedBox(height: 8),
                Text(
                  report.orphanFiles == 0
                      ? 'Nothing is orphaned — every thumbnail on disk still has '
                        'a photo behind it.'
                      : 'Orphans are thumbnails whose photo has been removed or '
                        'moved. Nothing can ever display them again.',
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_message != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: text.bodySmall?.copyWith(color: scheme.primary),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: _busy || report == null || report.thumbFiles == 0
              ? null
              : () => _run(
                    ref.read(cacheCompactorProvider).clearAll,
                    'the cache will rebuild as you browse',
                  ),
          child: const Text('Clear cache'),
        ),
        FilledButton(
          onPressed: _busy || report == null || report.orphanFiles == 0
              ? null
              : () => _run(
                    ref.read(cacheCompactorProvider).deleteOrphans,
                    'nothing that still has a photo was removed',
                  ),
          child: Text(
            report == null || report.orphanFiles == 0
                ? 'Delete orphans'
                : 'Delete ${report.orphanFiles} orphans',
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodySmall)),
          Text(
            value,
            style: text.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: highlight ? scheme.primary : null,
              fontWeight: highlight ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}
