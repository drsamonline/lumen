import 'package:flutter/material.dart';

import '../../core/formats/image_format.dart';

class FormatTile extends StatelessWidget {
  const FormatTile({super.key, required this.status});

  final FormatStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plugin = status.plugin;
    final ready = status.availability != FormatAvailability.needsInstall;

    final text = Theme.of(context).textTheme;

    // Deliberately not a ListTile with a Row title: the extension list for RAW
    // is eighteen entries long, the Row had no bounded width, and it overflowed
    // so hard that the plugin name was squeezed to one character per line.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            ready ? Icons.check_circle_outline : Icons.download_outlined,
            color: ready ? scheme.primary : scheme.onSurfaceVariant,
            size: 22,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(plugin.displayName, style: text.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  status.extensionsLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  ready
                      ? plugin.poweredBy
                      : '${plugin.requirement ?? 'Not installed'}\nUses ${plugin.poweredBy}',
                  style: text.bodySmall?.copyWith(
                    color: ready ? null : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
