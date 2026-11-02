import 'package:flutter/material.dart';

class MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  MonthHeaderDelegate({
    required this.label,
    required this.count,
    required this.background,
    required this.divider,
  });

  final String label;
  final int count;
  final Color background;
  final Color divider;

  static const double height = 44;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final text = Theme.of(context).textTheme;
    return Container(
      // Opaque, so tiles scrolling underneath do not show through the label.
      color: background,
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              style: text.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: text.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
      ),
    );
  }

  @override
  bool shouldRebuild(MonthHeaderDelegate oldDelegate) =>
      oldDelegate.label != label ||
      oldDelegate.count != count ||
      oldDelegate.background != background ||
      oldDelegate.divider != divider;
}
