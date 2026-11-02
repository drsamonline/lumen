import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The support block, in the app.
///
/// The landing page carries the same six handles with a scannable UPI QR. Here
/// they are plain selectable text with a Copy button.
///
/// Deliberately no browser launching: that would mean the url_launcher package,
/// whose entry point is one of the symbols `test/offline_guard_test.dart` bans.
/// Copying a handle keeps the app's own promise — it makes no outbound request,
/// not even to say thank you.
class SupportDialog extends StatelessWidget {
  const SupportDialog({super.key});

  static const _handles = <_SupportHandle>[
    _SupportHandle(
      label: 'UPI (India)',
      value: 'drsohilboi@ybl',
      note: 'Payee: Dr. Sohil Momin. Open amount — nothing is preset.',
    ),
    _SupportHandle(label: 'Ko-fi', value: 'https://ko-fi.com/matneo'),
    _SupportHandle(
      label: 'PayPal',
      value: 'https://paypal.me/drsohilmomin?locale.x=en_GB&country.x=IN',
    ),
    _SupportHandle(
      label: 'Books',
      value:
          'https://www.amazon.com/stores/author/B08ZT331LY/allbooks?ccs_id=aed72b9f-71d9-41dc-adee-e9368a317acc',
    ),
    _SupportHandle(label: 'Everything else', value: 'https://drsamonline.github.io/'),
    _SupportHandle(label: 'Email', value: 'sohilmomin2000@gmail.com'),
  ];

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SupportDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Support this work'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Lumen is free, offline, and has no business model. If it is '
                'useful to you, these are the ways to say so. Nothing in the app '
                'is gated behind them.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              for (final handle in _handles) ...<Widget>[
                _HandleRow(handle: handle, scheme: scheme),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SupportHandle {
  const _SupportHandle({required this.label, required this.value, this.note});
  final String label;
  final String value;
  final String? note;
}

class _HandleRow extends StatelessWidget {
  const _HandleRow({required this.handle, required this.scheme});

  final _SupportHandle handle;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          handle.label.toUpperCase(),
          style: text.labelSmall?.copyWith(
            letterSpacing: 1.0,
            color: scheme.primary,
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: SelectableText(
                handle.value,
                style: text.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: handle.value));
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Copied ${handle.label}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
        if (handle.note != null)
          Text(
            handle.note!,
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
