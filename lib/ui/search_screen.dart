import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/photo_dao.dart';
import '../state/library_controller.dart';
import '../state/providers.dart';
import 'library/photo_grid.dart';
import 'widgets/empty_state.dart';

/// Full-text search over file names, folders, captions and tags, backed by
/// SQLite FTS5 where available. Everything is local and instant.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final mode = controller.searchMode;
    if (mode == SearchMode.exact) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final message = mode == SearchMode.substring
        ? 'Partial matches — the exact words were not found'
        : 'Near matches — spelling corrected';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: scheme.tertiaryContainer,
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: scheme.onTertiaryContainer),
      ),
    );
  }
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _input = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int _minRating = 0;
  bool _favoritesOnly = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      setState(() => _query = value.trim());
    });
  }

  PhotoFilter get _filter => PhotoFilter(
        query: _query,
        minRating: _minRating,
        favoritesOnly: _favoritesOnly,
      );

  bool get _hasCriteria =>
      _query.isNotEmpty || _minRating > 0 || _favoritesOnly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _input,
          autofocus: false,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search file names, folders, captions, tags',
            border: InputBorder.none,
            suffixIcon: _input.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _input.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: <Widget>[
                FilterChip(
                  label: const Text('Favourites'),
                  selected: _favoritesOnly,
                  onSelected: (v) => setState(() => _favoritesOnly = v),
                ),
                const SizedBox(width: 8),
                for (var i = 1; i <= 3; i++) ...<Widget>[
                  FilterChip(
                    label: Text('$i★+'),
                    selected: _minRating == i,
                    onSelected: (v) => setState(() => _minRating = v ? i : 0),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (_hasCriteria)
            _ModeBanner(controller: ref.watch(filteredLibraryProvider(_filter))),
          Expanded(
            child: _hasCriteria
                ? PhotoGrid(
                    controller: ref.watch(filteredLibraryProvider(_filter)),
                    emptyTitle: 'Nothing matched',
                    emptyMessage: 'Try a shorter word, or clear the filters.',
                  )
                : const EmptyState(
                    icon: Icons.search,
                    title: 'Search your library',
                    message: 'Type a word to search across every indexed photo. '
                        'Results appear as you type — no network involved.',
                  ),
          ),
        ],
      ),
    );
  }
}
