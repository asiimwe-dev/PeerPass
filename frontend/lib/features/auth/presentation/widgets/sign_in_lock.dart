import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The lock's geometry, in fractions of the mark's own box.
///
/// A padlock is shown at one size in one place, but that size is inherited from a
/// caller rather than fixed here, so the drawing is authored in the unit square
/// and the canvas is scaled by the size actually painted.
const double _bodyTop = 0.42;
const double _bodyBottom = 0.94;
const double _bodyInset = 0.10;
const double _bodyRadius = 0.11;

const double _shackleLeft = 0.30;
const double _shackleRight = 0.70;
const double _shackleShoulder = 0.44;
const double _shackleLegBottom = 0.58;
const double _shackleRadius = 0.20;

const double _keyholeCentreY = 0.62;
const double _keyholeRadius = 0.07;
const double _keyholeReach = 0.22;
const double _keyholeHalfWidth = 0.035;

/// Padlock that drops into place, for the sign-in screen.
///
/// The screen is a security moment, so the mark reads as a lock closing rather
/// than as decoration. The pass is finite: the lock lands and stays, because a
/// form that loops while the user is typing their password is a form that burns
/// battery for nothing.
class SignInLock extends StatefulWidget {
  const SignInLock({super.key, this.size = 96.0});

  final double size;

  @override
  State<SignInLock> createState() => _SignInLockState();
}

class _SignInLockState extends State<SignInLock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// The body's descent: a fall, an overshoot above its resting line, and the
  /// return to rest. A single curve rather than three controllers keeps the
  /// phases from drifting apart, and a pure ease-in would let the body arrive
  /// with a dead stop, which is the thing that makes a drop look fake.
  late final Animation<double> _fall = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: -0.14,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 22,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: -0.14,
        end: 0,
      ).chain(CurveTween(curve: Curves.easeOutSine)),
      weight: 28,
    ),
  ]).animate(_controller);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not initState: the ambient MediaQuery is what says whether motion is
    // wanted, and it has to be able to stop a pass already under way.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
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
          painter: _SignInLockPainter(
            clock: _controller,
            fall: _fall,
            metal: scheme.primary,
            hole: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _SignInLockPainter extends CustomPainter {
  _SignInLockPainter({
    required this.clock,
    required this.fall,
    required this.metal,
    required this.hole,
  }) : super(repaint: clock);

  final Animation<double> clock;
  final Animation<double> fall;
  final Color metal;
  final Color hole;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height);
    final t = clock.value.clamp(0.0, 1.0);

    // The shackle is ahead of the body: it is released into the lock first and
    // the body settles onto it second, which is also the order a real padlock
    // moves in.
    final shackleT = const Interval(
      0.05,
      0.45,
      curve: Curves.easeInCubic,
    ).transform(t);
    final keyholeT = const Interval(0.8, 1).transform(t);

    // Travel is measured in boxes so both parts start off the edge of the
    // canvas. A shorter travel would leave the first frame showing a sliver of
    // the shape popping into existence.
    final shackle = _shacklePath().shift(Offset(0, -(1 - shackleT) * 0.75));
    // The keyhole is cut into the body, so it has to ride with it even though
    // it is not revealed until the body has already landed.
    final landing = Offset(0, -(1 - fall.value));

    final metalPaint = Paint()
      ..color = metal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.085
      ..strokeCap = StrokeCap.round;
    final bodyPaint = Paint()
      ..color = metal
      ..style = PaintingStyle.fill;
    final holePaint = Paint()
      ..color = hole.withValues(alpha: keyholeT)
      ..style = PaintingStyle.fill;

    canvas
      // One scale for the whole mark: the paths below are authored in the unit
      // square, and the paint weights follow them out to the painted size.
      ..save()
      ..scale(unit, unit)
      ..drawPath(shackle, metalPaint)
      ..drawPath(_bodyPath().shift(landing), bodyPaint)
      ..drawPath(_keyholePath(keyholeT).shift(landing), holePaint)
      ..restore();
  }

  @override
  bool shouldRepaint(_SignInLockPainter oldDelegate) =>
      oldDelegate.metal != metal || oldDelegate.hole != hole;

  Path _shacklePath() => Path()
    ..moveTo(_shackleLeft, _shackleLegBottom)
    ..lineTo(_shackleLeft, _shackleShoulder)
    ..addArc(
      Rect.fromCircle(
        center: const Offset(0.5, _shackleShoulder),
        radius: _shackleRadius,
      ),
      math.pi,
      math.pi,
    )
    ..lineTo(_shackleRight, _shackleLegBottom);

  Path _bodyPath() => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(_bodyInset, _bodyTop, 1 - _bodyInset, _bodyBottom),
        const Radius.circular(_bodyRadius),
      ),
    );

  /// One outline rather than a circle and a stem painted separately, so there
  /// is no winding to reason about where the two would overlap.
  Path _keyholePath(double grow) {
    // Floored away from zero: a collapsed radius is a degenerate arc, and there
    // is nothing to gain from handing one to the rasteriser.
    final reach = 0.15 + 0.85 * grow;
    final radius = _keyholeRadius * reach;
    return Path()
      ..moveTo(0.5 - radius, _keyholeCentreY)
      ..addArc(
        Rect.fromCircle(
          center: const Offset(0.5, _keyholeCentreY),
          radius: radius,
        ),
        math.pi,
        math.pi,
      )
      ..lineTo(
        0.5 + _keyholeHalfWidth * reach,
        _keyholeCentreY + _keyholeReach * reach,
      )
      ..lineTo(
        0.5 - _keyholeHalfWidth * reach,
        _keyholeCentreY + _keyholeReach * reach,
      )
      ..close();
  }
}
