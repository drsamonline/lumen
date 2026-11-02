import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/person.dart';
import '../../state/providers.dart';
import '../library/photo_grid.dart';
import '../widgets/empty_state.dart';

class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: people.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Could not load people', message: e.toString()),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.people_outline,
              title: 'Nobody tagged yet',
              message: 'Open any photo, tap the person icon, drag a box around a face '
                  'and give it a name. Faces stay on your device — no upload, no cloud.',
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisExtent: 200,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) => _PersonCard(person: list[i]),
          );
        },
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PersonDetailScreen(person: person)),
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              clipBehavior: Clip.antiAlias,
              child: const Icon(Icons.person, size: 44),
            ),
          ),
          const SizedBox(height: 8),
          Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            '${person.count} photos',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(personLibraryProvider(person.id));
    return Scaffold(
      appBar: AppBar(title: Text(person.name)),
      body: PhotoGrid(
        controller: controller,
        emptyTitle: 'No photos for ${person.name}',
      ),
    );
  }
}
