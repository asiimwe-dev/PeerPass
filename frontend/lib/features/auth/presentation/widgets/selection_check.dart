import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The tick's geometry, in fractions of its own box.
///
/// Same unit-square convention as the animated marks, so a row's tick and the
/// sign-in lock are cut from the same ruler and sit the same distance from the
/// edge of whatever they are drawn into.
const Offset _centre = Offset(0.5, 0.5);
const double _radius = 0.44;
const double _lineWeight = 0.085;
const double _tickWeight = 0.1;

/// The tick shown inside a selected onboarding option.
///
/// Driven by a boolean rather than by time, so the change is animated implicitly
/// and costs the list no controller per row. The tween deliberately has no begin
/// value: the implicit animation then starts at its end, which is what makes a
/// freshly mounted row show the correct state on its first frame instead of a
/// frame of the wrong one.
class SelectionCheck extends StatelessWidget {
  // Required before the optional key because the project lints for it; the two
  // are both named, so the order does not change how the widget is called.
  const SelectionCheck({required this.selected, super.key, this.size = 28.0});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: selected ? 1 : 0),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        builder: (context, fill, _) => CustomPaint(
          painter: _SelectionCheckPainter(
            fill: fill,
            mark: scheme.primary,
            tick: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _SelectionCheckPainter extends CustomPainter {
  const _SelectionCheckPainter({
    required this.fill,
    required this.mark,
    required this.tick,
  });

  final double fill;
  final Color mark;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height);

    final ringPaint = Paint()
      ..color = mark
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lineWeight;
    final discPaint = Paint()
      ..color = mark.withValues(alpha: fill)
      ..style = PaintingStyle.fill;
    // The tick shares the fill's alpha, so an unselected row cannot show a pale
    // ghost of a tick over whatever the page behind it happens to be.
    final tickPaint = Paint()
      ..color = tick.withValues(alpha: fill)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _tickWeight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Measured rather than scaled so the tick is drawn from its own origin
    // instead of popping in at full size.
    final tickPath = Path()
      ..moveTo(0.29, 0.51)
      ..lineTo(0.43, 0.65)
      ..lineTo(0.71, 0.35);

    canvas
      // The shapes are authored in the unit square and scaled once, the same as
      // the other marks. No repaint boundary: this sits in every row of a
      // scrollable, and a layer per row costs more than the paint it saves.
      ..save()
      ..scale(unit, unit)
      ..drawCircle(_centre, _radius, discPaint)
      ..drawCircle(_centre, _radius, ringPaint)
      ..drawPath(
        tickPath.computeMetrics().first.extractPath(0, fill),
        tickPaint,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_SelectionCheckPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.mark != mark ||
      oldDelegate.tick != tick;
}
