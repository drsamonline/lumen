import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../state/providers.dart';
import 'albums/albums_screen.dart';
import 'library/library_screen.dart';
import 'people/people_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.roots});

  final List<String> roots;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _destinations = <_Dest>[
    _Dest('Library', Icons.photo_library_outlined, Icons.photo_library),
    _Dest('Albums', Icons.collections_bookmark_outlined, Icons.collections_bookmark),
    _Dest('People', Icons.people_outline, Icons.people),
    _Dest('Search', Icons.search_outlined, Icons.search),
    _Dest('Settings', Icons.settings_outlined, Icons.settings),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final settings = ref.read(settingsProvider);
    final scan = ref.read(scanControllerProvider);
    final library = ref.read(libraryControllerProvider);

    await library.refresh();
    await scan.scanAll();
    await library.refresh();

    if (settings.watcherEnabled) {
      await scan.ensureWatching(enabled: true);
    }
    if (settings.lanEnabled) {
      await _startLan(settings);
    }
  }

  Future<void> _startLan(Settings settings) async {
    final server = ref.read(lanServerProvider);
    final beacon = ref.read(lanBeaconProvider);
    try {
      final port = await server.start(port: settings.lanPort);
      await beacon.start(httpPort: port, name: 'Lumen');
    } catch (_) {
      // Port in use, or a locked-down network stack. Surfaced in Settings.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const LibraryScreen(),
      const AlbumsScreen(),
      const PeopleScreen(),
      const SearchScreen(),
      const SettingsScreen(),
    ];

    final wide = MediaQuery.sizeOf(context).width >= 900;

    if (wide) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: <NavigationRailDestination>[
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: IndexedStack(index: _index, children: pages)),
          ],
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
