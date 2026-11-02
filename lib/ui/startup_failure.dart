import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shown when startup throws before the first frame.
///
/// Without this the app is a blank window: `main()` runs before `runApp`, so an
/// exception there produces no red screen, no log the user can see, and no clue.
/// A photo library that fails silently on launch is worse than one that fails
/// loudly, because the user cannot even tell you what happened.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error, this.stack});

  final Object error;
  final StackTrace? stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E6F6B),
          brightness: Brightness.dark,
        ),
      ),
      home: StartupFailureScreen(error: error, stack: stack),
    );
  }
}

class StartupFailureScreen extends StatelessWidget {
  const StartupFailureScreen({super.key, required this.error, this.stack});

  final Object error;
  final StackTrace? stack;

  String get _report {
    final buffer = StringBuffer()
      ..writeln('Lumen failed to start')
      ..writeln('platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('dart: ${Platform.version}')
      ..writeln()
      ..writeln('error: $error');
    if (stack != null) {
      buffer
        ..writeln()
        ..writeln('stack:')
        ..writeln(stack);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(Icons.error_outline, size: 44, color: scheme.error),
              const SizedBox(height: 14),
              Text('Lumen could not start', style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Something failed before the window was ready. The details are '
                'below — please send them along.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _report,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(ClipboardData(text: _report));
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Details copied')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy details'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                kReleaseMode
                    ? 'This is a bug in Lumen, not something you did.'
                    : 'Debug build.',
                textAlign: TextAlign.center,
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
