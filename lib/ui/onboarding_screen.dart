import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// First run: pick one or more folders. On Android we offer the standard
/// camera roll locations so the user does not have to hunt through the
/// filesystem picker.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final List<String> _picked = <String>[];
  bool _busy = false;

  Future<void> _pickFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose a photo folder',
      );
      if (path == null) return;
      setState(() {
        if (!_picked.contains(path)) _picked.add(path);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the folder picker.')),
      );
    }
  }

  void _addAndroidDefaults() {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = <String>[
      if (home.isNotEmpty) '$home/Pictures',
      if (home.isNotEmpty) '$home/DCIM',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Download',
    ];
    setState(() {
      for (final c in candidates) {
        if (Directory(c).existsSync() && !_picked.contains(c)) _picked.add(c);
      }
    });
  }

  Future<void> _start() async {
    if (_picked.isEmpty) return;
    setState(() => _busy = true);
    final rootsDao = ref.read(rootsDaoProvider);
    for (final path in _picked) {
      await rootsDao.add(path);
    }
    if (!mounted) return;
    ref.invalidate(libraryRootsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(Icons.photo_library_outlined, size: 64, color: scheme.primary),
                const SizedBox(height: 20),
                Text('Welcome to Lumen', style: text.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  'A photo library that lives entirely on your machine. '
                  'No account, no upload, no internet connection required — '
                  'ever.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text('Folders to index', style: text.titleSmall),
                        const SizedBox(height: 12),
                        if (_picked.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No folders chosen yet.',
                              style: text.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          )
                        else
                          for (final path in _picked)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.folder_outlined, size: 20),
                              title: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() => _picked.remove(path)),
                              ),
                            ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            FilledButton.tonalIcon(
                              onPressed: _pickFolder,
                              icon: const Icon(Icons.add),
                              label: const Text('Add folder'),
                            ),
                            if (Platform.isAndroid)
                              OutlinedButton.icon(
                                onPressed: _addAndroidDefaults,
                                icon: const Icon(Icons.smartphone),
                                label: const Text('Use camera roll'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _picked.isEmpty || _busy ? null : _start,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(_busy ? 'Setting up…' : 'Start indexing'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Your photos are never copied, moved or modified. '
                  'Lumen only reads them and keeps its own index alongside.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
