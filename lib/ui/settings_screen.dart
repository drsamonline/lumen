import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formats/format_registry.dart';
import '../core/formats/image_format.dart';
import '../core/lan/lan_server.dart';
import '../state/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<String> _addresses = const <String>[];
  double _thumbSize = 160;
  bool _watching = false;
  bool _lanOn = false;
  late Future<List<FormatStatus>> _formats;

  @override
  void initState() {
    super.initState();
    // Probed once and cached; re-probing on every rebuild would spawn a process
    // per decoder on each frame.
    _formats = ImageFormatRegistry.instance.status();
    final settings = ref.read(settingsProvider);
    _thumbSize = settings.thumbSize;
    _watching = settings.watcherEnabled;
    _lanOn = settings.lanEnabled;
    _refreshAddresses();
  }

  Future<void> _refreshAddresses() async {
    final list = await LanServer.localAddresses();
    if (!mounted) return;
    setState(() => _addresses = list);
  }

  @override
  Widget build(BuildContext context) {
    final rootsAsync = ref.watch(libraryRootsProvider);
    final scan = ref.watch(scanControllerProvider);
    final settings = ref.read(settingsProvider);
    final server = ref.watch(lanServerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: <Widget>[
          const _SectionHeader('Library folders'),
          rootsAsync.when(
            loading: () => const ListTile(title: Text('Loading…')),
            error: (e, _) => ListTile(title: Text('Error: $e')),
            data: (roots) => Column(
              children: <Widget>[
                if (roots.isEmpty)
                  const ListTile(
                    dense: true,
                    title: Text('No folders yet. Add one below.'),
                  ),
                for (final root in roots)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(root, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      Directory(root).existsSync() ? 'Available' : 'Missing on disk',
                      style: TextStyle(
                        color: Directory(root).existsSync() ? null : scheme.error,
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove folder',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () async {
                        await scan.removeRoot(root);
                        ref.invalidate(libraryRootsProvider);
                      },
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add folder'),
                  onTap: () async {
                    final path = await FilePicker.platform.getDirectoryPath(
                      dialogTitle: 'Add a photo folder',
                    );
                    if (path == null) return;
                    await scan.addRoot(path);
                    ref.invalidate(libraryRootsProvider);
                    await ref.read(libraryControllerProvider).refresh();
                  },
                ),
              ],
            ),
          ),

          const _SectionHeader('Indexing'),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Rescan everything'),
            subtitle: Text(
              scan.isScanning
                  ? 'Scanning… ${scan.progress.scanned} files'
                  : 'Re-reads metadata and picks up new or changed files',
            ),
            trailing: scan.isScanning
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: scan.isScanning
                ? null
                : () async {
                    await scan.scanAll();
                    await ref.read(libraryControllerProvider).refresh();
                  },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: const Text('Watch folders for changes'),
            subtitle: const Text('Rescan a folder automatically when files land in it'),
            value: _watching,
            onChanged: (value) async {
              setState(() => _watching = value);
              await settings.setWatcherEnabled(value);
              await scan.ensureWatching(enabled: value);
            },
          ),

          const _SectionHeader('Grid'),
          ListTile(
            title: const Text('Thumbnail size'),
            subtitle: Slider(
              value: _thumbSize,
              min: 100,
              max: 300,
              divisions: 8,
              label: _thumbSize.round().toString(),
              onChanged: (v) => setState(() => _thumbSize = v),
              onChangeEnd: (v) async {
                await settings.setThumbSize(v);
                await ref.read(libraryControllerProvider).refresh();
              },
            ),
          ),

          const _SectionHeader('Stream to your network'),
          SwitchListTile(
            secondary: const Icon(Icons.cast_outlined),
            title: const Text('Serve this library on the LAN'),
            subtitle: const Text(
              'Any phone, tablet or TV browser on the same Wi-Fi can browse and '
              'view your photos. Nothing leaves your home network.',
            ),
            value: _lanOn,
            onChanged: (value) async {
              setState(() => _lanOn = value);
              await settings.setLanEnabled(value);
              final beacon = ref.read(lanBeaconProvider);
              if (value) {
                try {
                  final port = await server.start(port: settings.lanPort);
                  await beacon.start(httpPort: port, name: 'Lumen');
                  await _refreshAddresses();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not start the server: $e')),
                  );
                  setState(() => _lanOn = false);
                  await settings.setLanEnabled(false);
                }
              } else {
                await server.stop();
                await beacon.stop();
              }
            },
          ),
          if (server.isRunning)
            Column(
              children: <Widget>[
                if (_addresses.isEmpty)
                  const ListTile(
                    dense: true,
                    title: Text('No private network address found.'),
                  ),
                for (final address in _addresses)
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text('http://$address:${server.port}'),
                    trailing: IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: 'http://$address:${server.port}'),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Address copied')),
                        );
                      },
                    ),
                  ),
              ],
            ),

          const _SectionHeader('Image formats'),
          FutureBuilder<List<FormatStatus>>(
            future: _formats,
            builder: (context, snapshot) {
              final statuses = snapshot.data;
              if (statuses == null) {
                return const ListTile(
                  dense: true,
                  title: Text('Checking installed decoders…'),
                );
              }
              return Column(
                children: <Widget>[
                  for (final status in statuses) _FormatTile(status: status),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline, size: 20),
                    title: Text(
                      'Formats beyond the built-in ones are decoded by established '
                      'open-source libraries installed on this machine. Lumen never '
                      'downloads or bundles one.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            },
          ),

          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.wifi_off),
            title: Text('Fully offline'),
            subtitle: Text(
              'Lumen never makes an outbound network request. No account, no '
              'telemetry, no sync. The only socket it opens is a listener on your '
              'own local network, and only when you turn it on above.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.sd_storage_outlined),
            title: Text('Your files are untouched'),
            subtitle: Text(
              'Lumen only reads your photos. Edits are stored as recipes in its '
              'own database, and exports write a new file next to the original.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text('1.0.0 · ${Platform.operatingSystem}'),
          ),
        ],
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.status});

  final FormatStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plugin = status.plugin;
    final ready = status.availability != FormatAvailability.needsInstall;

    return ListTile(
      leading: Icon(
        ready ? Icons.check_circle_outline : Icons.download_outlined,
        color: ready ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Row(
        children: <Widget>[
          Flexible(child: Text(plugin.displayName)),
          const SizedBox(width: 8),
          Text(
            status.extensionsLabel,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Text(
        ready
            ? plugin.poweredBy
            : '${plugin.requirement ?? 'Not installed'}\nUses ${plugin.poweredBy}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      isThreeLine: !ready,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
