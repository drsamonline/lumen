import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding_screen.dart';

class LumenApp extends ConsumerWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = const Color(0xFF2E6F6B);
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: _theme(seed, Brightness.light),
      darkTheme: _theme(seed, Brightness.dark),
      themeMode: ThemeMode.dark,
      home: const _Bootstrap(),
    );
  }

  ThemeData _theme(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

/// Decides between first-run setup and the library.
class _Bootstrap extends ConsumerWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roots = ref.watch(libraryRootsProvider);
    return roots.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Could not open the library index.\n$e')),
      ),
      data: (paths) => paths.isEmpty
          ? const OnboardingScreen()
          : HomeShell(roots: paths),
    );
  }
}
