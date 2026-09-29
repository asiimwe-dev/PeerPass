import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The mark's geometry, held in a unit square and scaled once at paint time.
///
/// The splash mark is shown at roughly 60 to 200 logical pixels depending on the
/// device, so nothing here may be a pixel constant: every point is a fraction of
/// the mark's own box and the canvas is scaled by the size actually painted
/// before anything is drawn.
const List<Offset> _letterP = <Offset>[
  Offset(0.22, 0.06),
  Offset(0.58, 0.06),
  Offset(0.72, 0.09),
  Offset(0.80, 0.17),
  Offset(0.82, 0.28),
  Offset(0.80, 0.39),
  Offset(0.72, 0.47),
  Offset(0.58, 0.50),
  Offset(0.40, 0.50),
  Offset(0.40, 0.70),
  Offset(0.40, 0.92),
  Offset(0.31, 0.94),
  Offset(0.22, 0.88),
];

/// The shield the letter resolves into.
///
/// Same point count and same winding as the letter, because a silhouette morph
/// is a straight interpolation between two point lists. Matching the two lists
/// point for point is what makes the shield's tip grow out of the letter's waist
/// instead of the shape folding through itself halfway across.
const List<Offset> _shield = <Offset>[
  Offset(0.08, 0.10),
  Offset(0.30, 0.06),
  Offset(0.70, 0.06),
  Offset(0.92, 0.10),
  Offset(0.94, 0.28),
  Offset(0.90, 0.46),
  Offset(0.82, 0.62),
  Offset(0.70, 0.78),
  Offset(0.50, 0.93),
  Offset(0.30, 0.78),
  Offset(0.18, 0.62),
  Offset(0.10, 0.46),
  Offset(0.06, 0.28),
];

/// The letter's bowl, cut out of the fill so the solid shape reads as a glyph
/// rather than a blob.
const List<Offset> _bowl = <Offset>[
  Offset(0.49, 0.16),
  Offset(0.60, 0.14),
  Offset(0.71, 0.19),
  Offset(0.74, 0.28),
  Offset(0.71, 0.37),
  Offset(0.60, 0.41),
  Offset(0.49, 0.39),
];

/// Where the bowl collapses to.
const Offset _bowlCentre = Offset(0.62, 0.28);

/// The tick that replaces the bowl once the silhouette is a shield.
const List<Offset> _tick = <Offset>[
  Offset(0.32, 0.50),
  Offset(0.45, 0.63),
  Offset(0.70, 0.34),
];

/// Brand mark for the splash screen: a letter "P" that resolves into a shield
/// carrying a check.
///
/// The mark has to carry both halves of the product name, "peer" and "verified",
/// in one glance, and a wordmark cannot morph between them, so it is drawn
/// rather than typeset. The pass is finite and ends on the shield: the router
/// holds the splash while stored tokens are being checked, so a looping
/// animation would keep the raster thread busy behind a screen that is not going
/// to change.
class SplashMorph extends StatefulWidget {
  const SplashMorph({
    super.key,
    this.size = 120.0,
    this.duration = const Duration(milliseconds: 1400),
  });

  final double size;

  /// Length of the whole pass, all three stages included.
  final Duration duration;

  @override
  State<SplashMorph> createState() => _SplashMorphState();
}

class _SplashMorphState extends State<SplashMorph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// One 0-to-1 pass split into three weighted stages: the bowl fills and the
  /// outline is traced, the silhouette crosses to the shield, then the tick draws.
  /// The weights are the stage lengths, and each stage starts where the one
  /// before it ended, so slicing a stage back out of the master returns that
  /// stage's own eased progress.
  ///
  /// The first stage is linear on purpose. The painter reads its phases straight
  /// off this value, and a curve here would spend most of the wall clock in the
  /// opening two tenths of the pass and then hold an already finished mark.
  /// The last stage's overshoot is what lands the tick a shade before the pass
  /// ends: it stops the mark from arriving on the same frame the animation does.
  late final Animation<double> _progress = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 0, end: 0.4), weight: 40),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.4,
        end: 0.75,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.75,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 25,
    ),
  ]).animate(_controller);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Deliberately not initState: whether motion is wanted comes from the
    // ambient MediaQuery, and reduced motion has to win over a pass that has
    // already begun, not only over one that has not.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.value = 1;
      return;
    }
    if (_started) return;
    _started = true;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SplashMorphPainter(
            progress: _progress,
            mark: scheme.primary,
            tick: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _SplashMorphPainter extends CustomPainter {
  _SplashMorphPainter({
    required this.progress,
    required this.mark,
    required this.tick,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color mark;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    // The last stage overshoots 1.0 on the way to settling. The slice curves
    // absorb that, but the geometry helpers are handed it raw.
    final t = progress.value;
    final unit = math.min(size.width, size.height);

    // Windows are cut to the stage boundaries the master is built from, so a
    // window that covers a whole stage hands back that stage's eased progress
    // untouched rather than re-timing it a second time.
    final fade = const Interval(0, 0.05, curve: Curves.easeOut).transform(t);
    final fill = const Interval(0, 0.18, curve: Curves.easeOut).transform(t);
    final trace = const Interval(
      0.03,
      0.4,
      curve: Curves.easeOutCubic,
    ).transform(t);
    final morph = const Interval(0.4, 0.75).transform(t);
    final close = const Interval(0.44, 0.72).transform(t);
    final drawTick = const Interval(0.75, 1).transform(t);

    final outline = _traced(_morphedPoints(morph))..close();
    final bowl = _traced(_collapsedPoints(close))..close();
    // Measuring a contour that has closed onto itself is not safe, so a spent
    // bowl is swapped for an empty path rather than measured anyway.
    final bowlStroke = close < 1 ? _extract(bowl, close) : Path();

    final fillPaint = Paint()
      ..color = mark.withValues(alpha: fill)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = mark.withValues(alpha: fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.075
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final bowlPaint = Paint()
      ..color = mark.withValues(alpha: close)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final tickPaint = Paint()
      ..color = tick
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.085
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // The bowl is a hole in the fill rather than a shape painted over it, so
    // once it has collapsed the solid shield underneath is what the tick lands
    // on. Even-odd is what makes it a hole without caring how the two subpaths
    // happen to wind.
    final body = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(outline, Offset.zero)
      ..addPath(bowl, Offset.zero);
    canvas
      // One scale for the whole mark: the geometry above is authored in the
      // unit square, and the paint weights follow it out to the painted size.
      ..save()
      ..scale(unit, unit)
      ..drawPath(body, fillPaint)
      ..drawPath(_extract(outline, trace), linePaint)
      ..drawPath(bowlStroke, bowlPaint)
      ..drawPath(_extract(_traced(_tick), drawTick), tickPaint)
      ..restore();
  }

  @override
  bool shouldRepaint(_SplashMorphPainter oldDelegate) =>
      oldDelegate.mark != mark || oldDelegate.tick != tick;

  /// Point-by-point crossfade between the letter and the shield.
  List<Offset> _morphedPoints(double t) => <Offset>[
    for (var i = 0; i < _letterP.length; i += 1)
      Offset.lerp(_letterP[i], _shield[i], t)!,
  ];

  /// The bowl shrinking onto its own centre. Scaling beats authoring a second
  /// outline: the hole closes along the path it was drawn with, so there is no
  /// frame in which a different shape snaps into its place.
  List<Offset> _collapsedPoints(double t) {
    final keep = 1 - t;
    return <Offset>[
      for (final point in _bowl)
        Offset(
          _bowlCentre.dx + (point.dx - _bowlCentre.dx) * keep,
          _bowlCentre.dy + (point.dy - _bowlCentre.dy) * keep,
        ),
    ];
  }

  Path _traced(List<Offset> points) {
    final path = Path();
    for (var i = 0; i < points.length; i += 1) {
      final point = points[i];
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path;
  }

  /// Traces [fraction] of the way along a path, so a stroke looks drawn rather
  /// than revealed. Clamped because the last stage's settle overshoots 1.0.
  Path _extract(Path path, double fraction) =>
      path.computeMetrics().first.extractPath(0, math.min(1, fraction));
}
