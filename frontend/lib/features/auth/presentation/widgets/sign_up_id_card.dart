import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Card layout, in fractions of the mark's own box.
///
/// Everything is authored in the unit square and the canvas is scaled once
/// before anything is drawn, so the same numbers hold at 60px and at 240px and
/// no stroke width has to be restated in pixels.
const Rect _card = Rect.fromLTRB(0.02, 0.18, 0.98, 0.82);
const Rect _photo = Rect.fromLTRB(0.08, 0.26, 0.33, 0.60);
const Rect _nameBar = Rect.fromLTRB(0.39, 0.30, 0.86, 0.365);
const Rect _numberBar = Rect.fromLTRB(0.39, 0.42, 0.70, 0.475);
const Rect _chip = Rect.fromLTRB(0.70, 0.58, 0.88, 0.74);
const Rect _chipPlate = Rect.fromLTRB(0.728, 0.608, 0.852, 0.712);

const double _cardRadius = 0.055;
const double _photoRadius = 0.028;
const double _chipRadius = 0.022;
const double _plateRadius = 0.012;

/// A student ID card being issued, for the sign-up screen.
///
/// Sign-up is the point where the app asks for academic identity, so the mark
/// is the document it is asking for rather than a generic badge. The pass is
/// finite and ends on a settled card: the surrounding form is the thing the
/// user came for, and an animation that keeps moving under a text field is
/// noise.
class SignUpIdCard extends StatefulWidget {
  const SignUpIdCard({super.key, this.size = 120.0});

  final double size;

  @override
  State<SignUpIdCard> createState() => _SignUpIdCardState();
}

class _SignUpIdCardState extends State<SignUpIdCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// The card's own scale: it arrives, holds while its contents are written on
  /// it, takes a small kick as the chip lands, and settles. The kick is the
  /// part that makes it read as being issued rather than merely revealed.
  late final Animation<double> _issued = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.88,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1,
      ).chain(CurveTween(curve: Curves.linear)),
      weight: 20,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.022,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 18,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.022,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutSine)),
      weight: 22,
    ),
  ]).animate(_controller);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not initState: reduced motion comes from the ambient MediaQuery and has to
    // be able to stop a pass that has already started, not only prevent one.
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
          painter: _SignUpIdCardPainter(
            clock: _controller,
            issued: _issued,
            card: scheme.primary,
            ink: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _SignUpIdCardPainter extends CustomPainter {
  _SignUpIdCardPainter({
    required this.clock,
    required this.issued,
    required this.card,
    required this.ink,
  }) : super(repaint: clock);

  final Animation<double> clock;
  final Animation<double> issued;
  final Color card;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height);
    final t = clock.value.clamp(0.0, 1.0);

    final arrival = const Interval(0, 0.3, curve: Curves.easeOut).transform(t);
    final photoT = const Interval(
      0.28,
      0.5,
      curve: Curves.easeOut,
    ).transform(t);
    final nameT = const Interval(0.44, 0.66).transform(t);
    final numberT = const Interval(0.56, 0.76).transform(t);
    // The chip is the last detail and the only one allowed to bounce; everything
    // before it lands on the card rather than arriving at it.
    final chipT = const Interval(
      0.68,
      0.88,
      curve: Curves.easeOutBack,
    ).transform(t);

    final cardPaint = Paint()
      ..color = card.withValues(alpha: arrival)
      ..style = PaintingStyle.fill;
    final photoFill = Paint()
      ..color = ink.withValues(alpha: const Interval(0.28, 0.44).transform(t))
      ..style = PaintingStyle.fill;
    final photoLine = Paint()
      ..color = ink.withValues(alpha: const Interval(0.34, 0.5).transform(t))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.012;
    final namePaint = Paint()
      ..color = ink.withValues(alpha: const Interval(0.44, 0.58).transform(t))
      ..style = PaintingStyle.fill;
    final numberPaint = Paint()
      ..color = ink.withValues(alpha: const Interval(0.56, 0.7).transform(t))
      ..style = PaintingStyle.fill;
    final chipPaint = Paint()
      ..color = ink.withValues(
        alpha: const Interval(0.68, 0.82).transform(t) * 0.45,
      )
      ..style = PaintingStyle.fill;
    final platePaint = Paint()
      ..color = ink.withValues(
        alpha: const Interval(0.72, 0.86).transform(t) * 0.85,
      )
      ..style = PaintingStyle.fill;

    final scale = issued.value;
    canvas
      // One scale for the whole mark, so the drawing below can be authored in
      // the unit square and the card can still grow about its own centre.
      ..save()
      ..scale(unit, unit)
      ..translate(0.5, 0.5)
      ..scale(scale, scale)
      ..translate(-0.5, -0.5)
      ..drawRRect(_round(_card, _cardRadius), cardPaint)
      ..drawRRect(_round(_drawn(_photo, photoT), _photoRadius), photoFill)
      ..drawRRect(_round(_drawn(_photo, photoT), _photoRadius), photoLine)
      // The two bars grow from their left edge, the way text is written, rather
      // than fading in as whole blocks.
      ..drawRRect(
        _round(_drawn(_nameBar, nameT), _nameBar.height / 2),
        namePaint,
      )
      ..drawRRect(
        _round(_drawn(_numberBar, numberT), _numberBar.height / 2),
        numberPaint,
      )
      ..drawRRect(_round(_scaled(_chip, chipT), _chipRadius), chipPaint)
      ..drawRRect(_round(_scaled(_chipPlate, chipT), _plateRadius), platePaint)
      ..restore();
  }

  @override
  bool shouldRepaint(_SignUpIdCardPainter oldDelegate) =>
      oldDelegate.card != card || oldDelegate.ink != ink;

  RRect _round(Rect rect, double radius) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  Rect _drawn(Rect rect, double t) => Rect.fromLTRB(
    rect.left,
    rect.top,
    rect.left + rect.width * t,
    rect.bottom,
  );

  Rect _scaled(Rect rect, double k) {
    final half = (rect.bottomRight - rect.topLeft) / 2;
    return Rect.fromCenter(
      center: rect.center,
      width: half.dx * 2 * k,
      height: half.dy * 2 * k,
    );
  }
}
