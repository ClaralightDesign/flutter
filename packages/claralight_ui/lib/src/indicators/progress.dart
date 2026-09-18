import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../theme/theme.dart';

/// Thickness ladder for [CLProgressBar] and size ladder for [CLProgressRing].
///
/// A progress indicator is a line rather than a box, so these are not the
/// control densities of `CLControlSize`: the bar doubles — the hairline under a
/// toolbar, the default row, and the bar a sheet gives a line of its own — and
/// the ring is measured along its stroke's centre line, giving 16, 24 and 40px
/// boxes with 2, 3 and 4px strokes.
enum CLProgressSize {
  small,
  medium,
  large;

  /// Rail thickness for [CLProgressBar] at this step.
  double get barThickness => switch (this) {
    CLProgressSize.small => 2,
    CLProgressSize.medium => 4,
    CLProgressSize.large => 8,
  };

  /// Radius of the ring's stroke centre line.
  double get ringRadius => switch (this) {
    CLProgressSize.small => 7,
    CLProgressSize.medium => 10.5,
    CLProgressSize.large => 18,
  };

  /// How far a round cap reaches either side of that line — half the stroke,
  /// and the radius of the dot a vanishing arc collapses to.
  double get ringCap => switch (this) {
    CLProgressSize.small => 1,
    CLProgressSize.medium => 1.5,
    CLProgressSize.large => 2,
  };

  /// The ring's box: the centre line plus a full stroke.
  double get ringDiameter => ringRadius * 2 + ringCap * 2;
}

/// The distance a track segment keeps from the active indicator.
///
/// It is what makes the rail read as two pieces rather than one bar filling up,
/// and it collapses on its own as either end runs out of room — so there is no
/// second, smaller value for the ends of the range.
const double _clProgressGap = 4;

/// The indeterminate bar's cycle. The one duration in Claralight that is not
/// quick: it is a loop that has to read as unhurried work rather than as
/// something repeatedly failing and restarting.
const Duration _clProgressCycle = Duration(milliseconds: 1750);

/// The indeterminate ring's cycle — the arc's breath, three turns, and a fourth
/// arriving a quarter at a time, all on one clock.
const Duration _clProgressRingCycle = Duration(milliseconds: 6000);

/// Value changes move on the language's standard quick transition; the
/// indicator and the track share it, or the gap between them breathes on every
/// change.
const Duration _clProgressSettle = CLMotion.fast;
const Curve _clProgressSettleCurve = CLMotion.easeOut;

/// A Claralight linear progress bar.
///
/// The rail is two pieces with a gap between them — the active indicator, and
/// the track it has not reached yet — rather than one bar filling up. That gap
/// is the design: two shapes that meet edge to edge read as a single object
/// changing colour, and two that stand apart read as a distance being covered.
/// It closes on its own as a piece runs out of room at either end, so a bar at 0
/// and a bar at 1 are both a single clean shape.
///
/// Every piece is drawn as a round-capped line rather than as a rounded box: its
/// height is `min(length, thickness)`, so a piece that runs out of room becomes
/// a circle and then a smaller circle instead of a sliver standing on end.
///
/// Pass a null [value] for the indeterminate figure: two lines cross the rail
/// per cycle, each stretching as it travels — the head leaves first and the tail
/// follows a beat later on the same curve — with the track filling the stretches
/// they leave behind.
class CLProgressBar extends StatefulWidget {
  /// Progress 0..1, or null for indeterminate.
  final double? value;

  /// Thickness step. Ignored when [height] is given.
  final CLProgressSize size;

  /// Rail thickness. Defaults to [size]'s step.
  final double? height;

  /// Indicator color. Defaults to the theme accent.
  final Color? color;

  /// Track color. Defaults to the theme track.
  final Color? trackColor;

  const CLProgressBar({
    super.key,
    required this.value,
    this.size = CLProgressSize.medium,
    this.height,
    this.color,
    this.trackColor,
  });

  @override
  State<CLProgressBar> createState() => _CLProgressBarState();
}

class _CLProgressBarState extends _CLProgressCycleState<CLProgressBar> {
  @override
  Duration get cyclePeriod => _clProgressCycle;

  @override
  bool get isIndeterminate => widget.value == null;

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    final thickness = widget.height ?? widget.size.barThickness;
    final color = widget.color ?? theme.colors.accent;
    final trackColor = widget.trackColor ?? theme.colors.track;
    final textDirection = Directionality.of(context);

    return wrapWithVisibility(
      Semantics(
        value: widget.value == null
            ? null
            : '${(widget.value!.clamp(0.0, 1.0) * 100).round()}%',
        child: SizedBox(
          height: thickness,
          child: widget.value == null
              ? AnimatedBuilder(
                  animation: cycle,
                  builder: (context, _) => CustomPaint(
                    painter: _CLProgressBarPainter(
                      value: null,
                      phase: cycle.value,
                      color: color,
                      trackColor: trackColor,
                      textDirection: textDirection,
                    ),
                    size: Size.infinite,
                  ),
                )
              : TweenAnimationBuilder<double>(
                  key: ValueKey(animationsDisabled),
                  tween: Tween<double>(
                    end: widget.value!.clamp(0.0, 1.0).toDouble(),
                  ),
                  duration: animationsDisabled
                      ? Duration.zero
                      : _clProgressSettle,
                  curve: _clProgressSettleCurve,
                  builder: (context, animated, _) => CustomPaint(
                    painter: _CLProgressBarPainter(
                      value: animated,
                      phase: 0,
                      color: color,
                      trackColor: trackColor,
                      textDirection: textDirection,
                    ),
                    size: Size.infinite,
                  ),
                ),
        ),
      ),
    );
  }
}

/// A Claralight circular progress ring — the same figure bent into a circle.
///
/// Everything the bar establishes holds here: a null [value] is the
/// indeterminate one, the track keeps the gap off the indicator, and an arc with
/// less room than the stroke is thick leaves as a shrinking dot rather than a
/// stub. Two things are different. The track has no far end — a circle closes,
/// so both of its ends meet the same indicator and both back off by the same
/// amount, bounded by how long that indicator actually is. And the indeterminate
/// figure draws no track at all: an arc chasing its own tail around a full ring
/// reads as a value that keeps resetting, where the same arc alone reads as
/// motion.
class CLProgressRing extends StatefulWidget {
  /// Progress 0..1, or null for indeterminate.
  final double? value;

  /// Size step. Ignored for whichever of [diameter] and [strokeWidth] is given.
  final CLProgressSize size;

  /// Box size. Defaults to [size]'s step: the centre line plus a full stroke.
  final double? diameter;

  /// Stroke thickness. Defaults to [size]'s step.
  final double? strokeWidth;

  /// Ring color. Defaults to the theme accent.
  final Color? color;

  /// Track color. Defaults to the theme track.
  final Color? trackColor;

  /// Optional centered child (e.g. a percentage label).
  final Widget? child;

  const CLProgressRing({
    super.key,
    required this.value,
    this.size = CLProgressSize.medium,
    this.diameter,
    this.strokeWidth,
    this.color,
    this.trackColor,
    this.child,
  });

  @override
  State<CLProgressRing> createState() => _CLProgressRingState();
}

class _CLProgressRingState extends _CLProgressCycleState<CLProgressRing> {
  @override
  Duration get cyclePeriod => _clProgressRingCycle;

  @override
  bool get isIndeterminate => widget.value == null;

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    final stroke = widget.strokeWidth ?? widget.size.ringCap * 2;
    final box = widget.diameter ?? widget.size.ringDiameter;
    // The box is the centre line plus a full stroke, so the radius is what is
    // left of it once the stroke has taken its half at each side.
    final radius = math.max(0.0, (box - stroke) / 2);
    final color = widget.color ?? theme.colors.accent;
    final trackColor = widget.trackColor ?? theme.colors.track;

    final Widget ring = widget.value == null
        ? AnimatedBuilder(
            animation: cycle,
            builder: (context, child) => CustomPaint(
              painter: _CLProgressRingPainter(
                value: null,
                phase: cycle.value,
                radius: radius,
                strokeWidth: stroke,
                color: color,
                trackColor: trackColor,
              ),
              child: child,
            ),
            child: Center(child: widget.child),
          )
        : TweenAnimationBuilder<double>(
            key: ValueKey(animationsDisabled),
            tween: Tween<double>(end: widget.value!.clamp(0.0, 1.0).toDouble()),
            duration: animationsDisabled ? Duration.zero : _clProgressSettle,
            curve: _clProgressSettleCurve,
            builder: (context, animated, child) => CustomPaint(
              painter: _CLProgressRingPainter(
                value: animated,
                phase: 0,
                radius: radius,
                strokeWidth: stroke,
                color: color,
                trackColor: trackColor,
              ),
              child: child,
            ),
            child: Center(child: widget.child),
          );

    return wrapWithVisibility(
      Semantics(
        value: widget.value == null
            ? null
            : '${(widget.value!.clamp(0.0, 1.0) * 100).round()}%',
        child: SizedBox(width: box, height: box, child: ring),
      ),
    );
  }
}

/// The parts both indicators share: one repeating cycle, and the gates that
/// keep it from burning frames where nothing can see it.
///
/// Reduced motion is deliberately not one of those gates. Every other loop in
/// Claralight stops under it; an indeterminate indicator cannot, because what is
/// left on screen — a quiet track, or an arc parked at one angle — reads as work
/// that has finished. The motion is the message, and it is small, steady travel
/// with no flashing and no scaling: the kind of motion the preference is least
/// concerned with. Reduced motion still snaps determinate value changes.
abstract class _CLProgressCycleState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// How long one full cycle of the indeterminate figure takes.
  Duration get cyclePeriod;

  /// Whether this build wants the cycle running at all.
  bool get isIndeterminate;

  late final AnimationController cycle;
  final Key _visibilityKey = UniqueKey();

  bool _visible = false;
  bool _tickerEnabled = true;
  bool _appActive = true;

  /// Whether finite transitions should snap. Read by subclasses for their
  /// determinate animation; never a reason to stop the cycle.
  bool animationsDisabled = false;

  bool get _canRun =>
      isIndeterminate && _visible && _tickerEnabled && _appActive;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appActive =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    cycle = AnimationController(vsync: this, duration: cyclePeriod);
    _syncCycle();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (_tickerEnabled == tickerEnabled && animationsDisabled == disabled) {
      return;
    }
    _tickerEnabled = tickerEnabled;
    animationsDisabled = disabled;
    _syncCycle();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCycle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appActive = state == AppLifecycleState.resumed;
    if (_appActive == appActive) return;
    _appActive = appActive;
    _syncCycle();
  }

  void _handleVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;
    final visible = info.visibleFraction > 0;
    if (_visible == visible) return;
    _visible = visible;
    _syncCycle();
  }

  void _syncCycle() {
    if (!_canRun) {
      if (cycle.isAnimating) cycle.stop(canceled: false);
      return;
    }
    if (!cycle.isAnimating) cycle.repeat(period: cyclePeriod);
  }

  /// Wraps [child] in the detector that gates the cycle on being on screen.
  Widget wrapWithVisibility(Widget child) {
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _handleVisibilityChanged,
      child: child,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cycle.dispose();
    super.dispose();
  }
}

/// One leg of the indeterminate cycle: an edge that waits, travels the whole
/// rail on the language's acceleration curve, and then holds where it arrived
/// until the cycle comes round again.
double _clProgressLeg(double phase, double start, double end) {
  if (phase <= start) return 0;
  if (phase >= end) return 1;
  return CLMotion.easeIn.transform((phase - start) / (end - start));
}

/// The rail and its segments.
///
/// Each segment knows only where it starts and where it ends, as fractions of
/// the rail, and how far it keeps off its neighbours. The gap is why: a segment
/// that has less room than the gap keeps only the room it has, which is what
/// makes an empty and a full bar correct without a second case.
class _CLProgressBarPainter extends CustomPainter {
  const _CLProgressBarPainter({
    required this.value,
    required this.phase,
    required this.color,
    required this.trackColor,
    required this.textDirection,
  });

  /// Determinate fraction, or null for the indeterminate figure.
  final double? value;

  /// Position within the indeterminate cycle, 0..1.
  final double phase;

  final Color color;
  final Color trackColor;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (value case final fraction?) {
      _segment(canvas, size, 0, fraction, 0, color);
      _segment(canvas, size, fraction, 1, _clProgressGap, trackColor);
      return;
    }

    // Two lines cross the rail per cycle, each stretching as it goes; the
    // percentages are where each leg starts and ends within the cycle.
    final head1 = _clProgressLeg(phase, 0, 1000 / 1750);
    final tail1 = _clProgressLeg(phase, 250 / 1750, 1250 / 1750);
    final head2 = _clProgressLeg(phase, 650 / 1750, 1500 / 1750);
    final tail2 = _clProgressLeg(phase, 900 / 1750, 1750 / 1750);

    // Start edge to the trailing line, between the lines, and the leading line
    // to the end edge. Each is bounded by whichever moving edge is nearest it,
    // so these read as a chain rather than as five independent animations; one
    // whose far edge has overtaken its near one has no room left and is not
    // drawn at all.
    _segment(canvas, size, 0, tail2, _clProgressGap, trackColor);
    _segment(canvas, size, head2, tail1, _clProgressGap, trackColor);
    _segment(canvas, size, head1, 1, _clProgressGap, trackColor);
    _segment(canvas, size, tail2, head2, 0, color);
    _segment(canvas, size, tail1, head1, 0, color);
  }

  void _segment(
    Canvas canvas,
    Size size,
    double from,
    double to,
    double space,
    Color color,
  ) {
    final near = from * size.width;
    final far = size.width - to * size.width;
    final start = near + math.min(near, space);
    final end = far + math.min(far, space);
    final length = size.width - start - end;
    if (length <= 0) return;

    // The range and the shape drawn in it are not the same box. A round-capped
    // line can never be thinner than it is tall: shorten it and it stops at a
    // circle the width of the rail, and it is round the whole way there. A
    // rounded box does the opposite — its corners give out as it narrows, worst
    // exactly at the two ends of the range that every segment passes through.
    final fill = math.min(length, size.height);
    final left = textDirection == TextDirection.rtl
        ? size.width - start - length
        : start;
    final rect = Rect.fromLTWH(left, (size.height - fill) / 2, length, fill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(fill / 2)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CLProgressBarPainter oldDelegate) =>
      value != oldDelegate.value ||
      phase != oldDelegate.phase ||
      color != oldDelegate.color ||
      trackColor != oldDelegate.trackColor ||
      textDirection != oldDelegate.textDirection;
}

/// The ring. Every length here is measured along the stroke's centre line, so
/// the ring's own circumference is the unit and fractions of the value scale
/// straight onto it.
class _CLProgressRingPainter extends CustomPainter {
  const _CLProgressRingPainter({
    required this.value,
    required this.phase,
    required this.radius,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  /// Determinate fraction, or null for the indeterminate figure.
  final double? value;

  /// Position within the indeterminate cycle, 0..1.
  final double phase;

  final double radius;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  /// Twelve o'clock, clockwise: an arc's zero is at three.
  static const double _start = -math.pi / 2;

  /// The arc breathes between these two fractions of the ring.
  static const double _arcMin = 0.1;
  static const double _arcMax = 0.87;

  /// Three turns on the clock, and a fourth a quarter at a time.
  static const double _spin = 3 * 2 * math.pi;
  static const double _stepHold = 0.25;
  static const double _stepTravel = 0.05;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || radius <= 0) return;
    final center = size.center(Offset.zero);
    final circumference = 2 * math.pi * radius;

    if (value case final fraction?) {
      final indicator = fraction * circumference;
      // Round caps reach half a stroke past each end of an arc, so two arcs
      // whose centre lines stop a gap apart would paint over it from both sides
      // and leave nothing. The gap the design asks for is therefore widened by
      // a whole stroke here, and what shows is the gap itself.
      //
      // Both of the track's ends meet the same indicator — a circle has no far
      // edge to run out at — so both back off by the same amount, and neither
      // can take more room than that indicator has: at zero the gaps vanish and
      // the track is the whole ring.
      final space = math.min(_clProgressGap + strokeWidth, indicator);
      _arc(
        canvas,
        center,
        indicator + space,
        circumference - indicator - space - space,
        trackColor,
      );
      _arc(canvas, center, 0, indicator, color);
      return;
    }

    // No track. Three motions on one clock: the arc breathes, the ring turns,
    // and the stepped rotation adds its quarter turns on top.
    final arc = phase < 0.5
        ? _arcMin + (_arcMax - _arcMin) * (phase / 0.5)
        : _arcMax +
              (_arcMin - _arcMax) *
                  CLMotion.easeInOut.transform((phase - 0.5) / 0.5);
    final rotation = _spin * phase + _stepRotation(phase);
    _arc(canvas, center, 0, arc * circumference, color, rotation: rotation);
  }

  /// Each quarter lands in 300ms and then waits out the rest of its 1500ms. The
  /// wait is the figure: a spinner that turns at one rate reads as a wheel, and
  /// one that keeps arriving somewhere reads as work.
  double _stepRotation(double phase) {
    final index = math.min(3, (phase / _stepHold).floor());
    final travelled = ((phase - index * _stepHold) / _stepTravel).clamp(
      0.0,
      1.0,
    );
    return (index + CLMotion.easeOut.transform(travelled)) * math.pi / 2;
  }

  /// One arc: [begin] is where it starts and [length] how much of the ring it
  /// covers, both as lengths along the centre line.
  ///
  /// The stroke carries the same rule as the rail's fill — an arc with less room
  /// than the stroke is thick keeps its roundness and gives up its width, so it
  /// leaves as a shrinking dot instead of a stub.
  void _arc(
    Canvas canvas,
    Offset center,
    double begin,
    double length,
    Color color, {
    double rotation = 0,
  }) {
    if (length <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.min(length, strokeWidth);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _start + rotation + begin / radius,
      length / radius,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_CLProgressRingPainter oldDelegate) =>
      value != oldDelegate.value ||
      phase != oldDelegate.phase ||
      radius != oldDelegate.radius ||
      strokeWidth != oldDelegate.strokeWidth ||
      color != oldDelegate.color ||
      trackColor != oldDelegate.trackColor;
}
