import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One year on the rail, and the scroll offset that year starts at.
class ScrubMarker {
  const ScrubMarker({required this.year, required this.offset});

  final int year;
  final double offset;
}

/// The vertical year rail on the right of the timeline.
///
/// Two things it has to survive:
///
/// * **Many years.** A library spanning thirty years wants thirty labels, which
///   is taller than the screen. Labels are thinned to what fits rather than
///   overflowing; the years that remain are evenly spaced.
/// * **A short window.** On a phone in landscape there may be room for five.
class YearScrubber extends StatefulWidget {
  const YearScrubber({
    super.key,
    required this.markers,
    required this.onSeek,
    this.width = 40,
  });

  final List<ScrubMarker> markers;
  final ValueChanged<double> onSeek;
  final double width;

  /// Minimum vertical space one label needs. A 12 px glyph is ~17 px tall and
  /// carries 2 px of padding above and below, so 26 is the first honest number —
  /// 20 thinned to a count that still overflowed by 80 px.
  static const double slotHeight = 26;

  @override
  State<YearScrubber> createState() => _YearScrubberState();
}

class _YearScrubberState extends State<YearScrubber> {
  int? _activeYear;

  /// The subset of markers that fits, always including the first and the last.
  List<ScrubMarker> _visible(double height) {
    final markers = widget.markers;
    if (markers.isEmpty) return markers;
    final usable = height - 8; // the rail's own padding
    final capacity =
        math.max(1, (usable / YearScrubber.slotHeight).floor());
    if (markers.length <= capacity) return markers;

    final step = (markers.length / capacity).ceil();
    final out = <ScrubMarker>[];
    for (var i = 0; i < markers.length; i += step) {
      out.add(markers[i]);
    }
    // The most recent year is the one people reach for; keep it visible.
    if (out.last != markers.last) out.add(markers.last);
    return out;
  }

  void _seekTo(double dy, double height, List<ScrubMarker> visible) {
    if (height <= 0 || visible.isEmpty) return;
    final fraction = (dy / height).clamp(0.0, 0.9999);
    final index = (fraction * visible.length).floor();
    final marker = visible[index.clamp(0, visible.length - 1)];
    setState(() => _activeYear = marker.year);
    widget.onSeek(marker.offset);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = _visible(constraints.maxHeight);
        final height = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) => _seekTo(d.localPosition.dy, height, visible),
          onVerticalDragUpdate: (d) => _seekTo(d.localPosition.dy, height, visible),
          onVerticalDragEnd: (_) => setState(() => _activeYear = null),
          onTapDown: (d) => _seekTo(d.localPosition.dy, height, visible),
          onTapUp: (_) => setState(() => _activeYear = null),
          child: SizedBox(
            width: widget.width,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (final marker in visible)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          style: TextStyle(
                            fontSize: _activeYear == marker.year ? 12 : 10,
                            fontWeight: _activeYear == marker.year
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _activeYear == marker.year
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          child: Text('${marker.year}'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
