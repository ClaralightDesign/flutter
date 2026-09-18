import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../foundation/numeric_text.dart';
import '../foundation/shape.dart';
import '../overlays/anchored_overlay.dart';
import '../theme/theme.dart';

/// A Claralight slider.
///
/// The rail is not one bar with a knob on top of it: it is three separate
/// pieces — the active line, the handle, and the track the handle has not
/// reached — each standing a gap apart, the same figure [CLProgressBar] draws.
///
/// The handle is a flat capsule at rest. Under the pointer it narrows into a
/// line, so the thing that marks the value gets thinner exactly when a pointer
/// is there to place it precisely, and thickens again while dragging. Only the
/// drawing changes: the hover box, the hit area and the value mapping are all
/// measured from the resting capsule and never move.
///
/// Give it a [valueLabel] and the pinch has somewhere to go: the material
/// squeezed out of the capsule rises into a bubble carrying the value, tethered
/// to the handle like a balloon on a string — its foot stays over the handle
/// and its body trails behind the drag, swinging back when the drag stops.
class CLSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// Fill color of the active track. Defaults to the theme accent.
  final Color? activeColor;

  /// Formats the value for the bubble the handle lifts under the pointer.
  ///
  /// Null is the slider without a bubble, which is the default: a slider whose
  /// value is already spelled out beside it does not need one.
  final String Function(double value)? valueLabel;

  const CLSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.activeColor,
    this.valueLabel,
  }) : assert(min < max);

  static const double trackHeight = 6;

  /// The handle at rest: a flat capsule.
  static const double thumbWidth = 20;
  static const double thumbHeight = 12;

  /// The handle under the pointer, and while it is being dragged.
  static const double hoverLineWidth = 3;
  static const double hoverLineHeight = 20;
  static const double pressLineWidth = 4;
  static const double pressLineHeight = 24;

  /// The distance the track keeps from the handle — [CLProgressBar]'s gap.
  static const double gap = 4;

  /// The box that answers to the pointer. Sized from the resting capsule, so
  /// the handle narrowing to a line never pulls the box out from under the
  /// cursor and leaves it flickering between the two shapes.
  static const double hoverWidth = 28;

  static const double hitHeight = 32;

  /// The bubble's own padding, and the tail it points at the handle with — the
  /// tooltip's tail, cut small.
  static const EdgeInsets bubblePadding = EdgeInsets.symmetric(
    horizontal: 7,
    vertical: 3,
  );
  static const double bubbleTailExtent = 5;
  static const double bubbleTailHalfWidth = 7;

  /// How far the tail's tip stops short of the line it points at.
  static const double bubbleTipClearance = 2;

  /// How far the balloon may lean out of true.
  static const double bubbleMaxTilt = 12 * math.pi / 180;

  /// The bubble is the handle's own material, and the handle is white in either
  /// theme, so what is written on it is a fixed ink rather than a themed text
  /// color that would turn white on white.
  static const Color bubbleInk = Color(0xFF1A1A1A);

  @override
  State<CLSlider> createState() => _CLSliderState();
}

class _CLSliderState extends State<CLSlider> with TickerProviderStateMixin {
  static const _pressSpring = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 18,
  );

  static SpringDescription _visualSpringFor(double distance) {
    final dampingProgress = (distance / 0.35).clamp(0.0, 1.0);
    return SpringDescription(
      mass: 1,
      stiffness: 520,
      // Small corrections retain a light spring. Large jumps approach
      // critical damping so their rebound does not scale with the distance.
      damping: 24 + 24 * dampingProgress,
    );
  }

  late final AnimationController _press;
  late final AnimationController _hover;

  /// The bubble's flight: 0 is the capsule still sitting on the track, 1 is the
  /// bubble in the air. It carries its own overshoot, which is the pop.
  late final AnimationController _bubble;
  final OverlayPortalController _bubblePortal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  /// The balloon's top, as a mass on a spring pinned to the handle. The tilt is
  /// not computed from a velocity: it is where this point has lagged to, so the
  /// swing back when a drag stops is the same physics and needs no animation of
  /// its own.
  late final Ticker _balloon;
  final ValueNotifier<double> _tilt = ValueNotifier<double>(0);
  Duration _balloonElapsed = Duration.zero;
  double _balloonX = 0;
  double _balloonVelocity = 0;

  /// The last width the slider was laid out at, and the bubble measured for it.
  double _layoutWidth = 0;
  Size? _bubbleSize;
  Object? _bubbleMeasureKey;

  bool _hovered = false;
  bool _pressed = false;

  /// Animated track fraction. Follows the finger 1:1 while dragging and
  /// springs to the new position when the value jumps (track taps,
  /// programmatic changes).
  late final AnimationController _visual;
  late final Listenable _geometryAnimation;

  /// Whether the pointer is actively tracking (drag) — jumps skip the
  /// spring so the thumb never lags behind the finger.
  bool _tracking = false;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _press = AnimationController.unbounded(vsync: this);
    _hover = AnimationController(vsync: this, duration: CLMotion.fast);
    _bubble = AnimationController(vsync: this, duration: CLMotion.standard)
      ..addStatusListener(_handleBubbleStatus);
    _balloon = createTicker(_handleBalloonTick);
    _visual = AnimationController.unbounded(value: _fraction, vsync: this);
    _geometryAnimation = Listenable.merge([_press, _hover, _visual]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations == disableAnimations) return;
    _disableAnimations = disableAnimations;
    if (disableAnimations) _snapReducedMotionGeometry();
  }

  void _snapReducedMotionGeometry() {
    _press.stop();
    _hover.stop();
    _visual.stop();
    _press.value = 0;
    _hover.value = 0;
    _visual.value = _fraction;
    _stopBalloon();
  }

  @override
  void didUpdateWidget(CLSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.valueLabel != oldWidget.valueLabel ||
        widget.min != oldWidget.min ||
        widget.max != oldWidget.max) {
      _bubbleMeasureKey = null;
    }
    if (!_enabled && _hover.value != 0) _setHovered(false);
    final target = _fraction;
    if (_disableAnimations || _tracking) {
      _visual.stop();
      _visual.value = target;
    } else if ((target - _visual.value).abs() > 0.0005) {
      final distance = (target - _visual.value).abs();
      _visual.animateWith(
        SpringSimulation(
          _visualSpringFor(distance),
          _visual.value,
          target,
          0,
          tolerance: Tolerance.defaultTolerance,
        ),
      );
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _hover.dispose();
    _bubble.dispose();
    _balloon.dispose();
    _tilt.dispose();
    _visual.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onChanged != null;

  double get _fraction =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  /// Pointer position to value. Measured from the line rather than the resting
  /// capsule, because a pointer is only ever on the rail while the handle is a
  /// line: mapping from the capsule would put the ends of the range half a
  /// capsule inside the rail, where no press can reach them.
  void _update(Offset localPosition, double width) {
    if (!_enabled) return;
    final usable = width - CLSlider.pressLineWidth;
    final fraction = ((localPosition.dx - CLSlider.pressLineWidth / 2) / usable)
        .clamp(0.0, 1.0);
    widget.onChanged!(widget.min + fraction * (widget.max - widget.min));
  }

  void _setPressed(bool pressed, {bool tracking = false}) {
    _tracking = pressed && tracking;
    _pressed = pressed;
    _syncBubble();
    if (_disableAnimations) {
      _press.stop();
      _press.value = pressed ? 1 : 0;
      return;
    }
    if (pressed) {
      _press.animateTo(1, duration: CLMotion.fast, curve: CLMotion.easeOut);
    } else {
      _press.animateWith(
        SpringSimulation(
          _pressSpring,
          _press.value,
          0,
          0,
          tolerance: Tolerance.defaultTolerance,
        ),
      );
    }
  }

  void _setHovered(bool hovered) {
    if (hovered && !_enabled) return;
    _hovered = hovered;
    _syncBubble();
    if (_disableAnimations) {
      _hover.stop();
      _hover.value = hovered ? 1 : 0;
      return;
    }
    _hover.animateTo(
      hovered ? 1 : 0,
      duration: CLMotion.fast,
      curve: CLMotion.easeOut,
    );
  }

  /// The handle's drawn width. The press state is the hover line thickened, so
  /// it carries the capsule-to-line morph on its own where there is no pointer
  /// to hover — a touch drag.
  double get _handleWidth {
    final pressed = _press.value.clamp(0.0, 1.0);
    final line = math.max(_hover.value, pressed);
    return _lerp(
      _lerp(CLSlider.thumbWidth, CLSlider.hoverLineWidth, line),
      CLSlider.pressLineWidth,
      pressed,
    );
  }

  /// Where the handle's centre is, in the slider's own coordinates: each shape
  /// travels its own width, so whichever one is drawn ends flush with the rail
  /// at 0 and at 1. The balloon chases this, and the bubble hangs off it.
  double get _handleCenter {
    final handleWidth = _handleWidth;
    return handleWidth / 2 +
        (_layoutWidth - handleWidth) * _visual.value.clamp(0.0, 1.0);
  }

  /// The bubble is up whenever the handle is a line — hover on a desktop, and
  /// the press itself on a touch drag, where there is no hover to reach it.
  void _syncBubble() {
    if (widget.valueLabel == null) return;
    final show = _enabled && (_hovered || _pressed);
    if (show && !_bubblePortal.isShowing) {
      // Start the balloon where the handle is, or it swings in from wherever
      // the last drag abandoned it.
      _balloonX = _handleCenter;
      _balloonVelocity = 0;
      _tilt.value = 0;
      _bubblePortal.show();
    }
    if (_disableAnimations) {
      // Fixed geometry, fade only: the bubble is already where it belongs and
      // only its opacity crosses.
      _bubble.animateTo(
        show ? 1 : 0,
        duration: CLMotion.reducedFade,
        curve: Curves.linear,
      );
      return;
    }
    if (show) {
      _bubble.animateTo(
        1,
        duration: CLMotion.standard,
        curve: CLMotion.springOut,
      );
      if (!_balloon.isActive) {
        _balloonElapsed = Duration.zero;
        _balloon.start();
      }
    } else {
      _bubble.animateBack(0, duration: CLMotion.fast, curve: CLMotion.easeIn);
    }
  }

  void _handleBubbleStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    _stopBalloon();
    if (_bubblePortal.isShowing) _bubblePortal.hide();
  }

  void _stopBalloon() {
    if (_balloon.isActive) _balloon.stop();
    _balloonElapsed = Duration.zero;
    _balloonVelocity = 0;
    _balloonX = _handleCenter;
    _tilt.value = 0;
  }

  /// One mass, one spring, one anchor: the balloon's top is pulled toward the
  /// handle and resists being moved. Everything the tilt does — leaning out of a
  /// drag, overshooting when the drag stops, settling — falls out of this.
  static const double _balloonStiffness = 200;
  static const double _balloonDamping = 20;

  void _handleBalloonTick(Duration elapsed) {
    final delta = (elapsed - _balloonElapsed).inMicroseconds / 1e6;
    _balloonElapsed = elapsed;
    final target = _handleCenter;

    // Fixed sub-steps: a dropped frame must not hand the integrator a step
    // large enough to make the spring gain energy.
    var remaining = delta.clamp(0.0, 1 / 20);
    while (remaining > 0) {
      final step = math.min(remaining, 1 / 240);
      final acceleration =
          _balloonStiffness * (target - _balloonX) -
          _balloonDamping * _balloonVelocity;
      _balloonVelocity += acceleration * step;
      _balloonX += _balloonVelocity * step;
      remaining -= step;
    }

    _tilt.value = _tiltFor(target);
    if (!_bubblePortal.isShowing) return;
    final settled =
        (target - _balloonX).abs() < 0.05 && _balloonVelocity.abs() < 0.05;
    if (settled && _bubble.isCompleted) {
      _balloonX = target;
      _balloonVelocity = 0;
      _tilt.value = 0;
      _balloon.stop();
    }
  }

  /// The lag read as an angle: the balloon's top sits at [_balloonX], so the
  /// string it hangs from is exactly as long as the distance from the handle to
  /// the top of the bubble.
  double _tiltFor(double target) {
    final string =
        CLSlider.hoverLineHeight / 2 +
        CLSlider.bubbleTipClearance +
        CLSlider.bubbleTailExtent +
        (_bubbleSize?.height ?? CLSlider.thumbHeight);
    if (string <= 0) return 0;
    final sine = ((_balloonX - target) / string).clamp(-1.0, 1.0);
    return math
        .asin(sine)
        .clamp(-CLSlider.bubbleMaxTilt, CLSlider.bubbleMaxTilt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    var active = widget.activeColor ?? theme.colors.accent;
    var thumb = const Color(0xFFFFFFFF);
    if (!_enabled) {
      active = active.withValues(alpha: active.a * 0.45);
      thumb = thumb.withValues(alpha: 0.7);
    }

    final Widget rail = SizedBox(
      height: CLSlider.hitHeight,
      child: AnimatedBuilder(
        animation: _geometryAnimation,
        builder: (context, _) => _buildInteractiveSlider(
          theme: theme,
          activeColor: active,
          thumbColor: thumb,
        ),
      ),
    );

    return Semantics(
      slider: true,
      enabled: _enabled,
      value:
          widget.valueLabel?.call(widget.value) ??
          widget.value.toStringAsFixed(2),
      child: widget.valueLabel == null
          ? rail
          : OverlayPortal(
              controller: _bubblePortal,
              overlayChildBuilder: _buildBubble,
              child: CompositedTransformTarget(link: _link, child: rail),
            ),
    );
  }

  /// The bubble, drawn in the overlay so it is never clipped by whatever the
  /// slider sits in, and followed to the handle by the compositor rather than
  /// by a measurement taken a frame late.
  Widget _buildBubble(BuildContext context) {
    final theme = CLTheme.of(context);
    final style = theme.typography.caption.copyWith(
      color: CLSlider.bubbleInk,
      fontWeight: FontWeight.w600,
      height: 1.15,
    );
    final body = _measureBubble(context, style);

    // Position the bubble's tail tip just clear of the hover line.
    // Like CLTooltip, the bubble does not translate into position — its foot
    // stays anchored above the handle while the surface scales up from the tail tip.
    const flight =
        CLSlider.hitHeight / 2 -
        CLSlider.hoverLineHeight / 2 -
        CLSlider.bubbleTipClearance;

    // The overlay hands its children tight constraints, which a bare SizedBox
    // would be stretched by: a stack takes that size and lays the bubble out
    // loose inside it, at its own.
    return Stack(
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([_bubble, _visual, _tilt]),
          builder: (context, _) {
            if (_bubble.value <= 0) return const SizedBox.shrink();

            // Like CLTooltip, normal motion scales the surface from the tail tip
            // with a spring overshoot; opacity is reserved for the reduced-motion fallback.
            final scale = _disableAnimations
                ? 1.0
                : math.max(0.0, _bubble.value);
            final opacity = _disableAnimations
                ? CLMotion.easeOut.transform(_bubble.value)
                : 1.0;

            if (scale <= 0) return const SizedBox.shrink();

            const tail = CLSlider.bubbleTailExtent;
            final width = body.width;
            final bodyHeight = body.height;

            return CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomCenter,
              offset: Offset(_handleCenter, flight),
              // The bubble floats over the hover box that summoned it. Letting it
              // take a pointer would mean the cursor entering the bubble counts as
              // leaving the handle, which retracts the bubble, which hands the
              // cursor back — a flicker with nothing to stop it.
              child: IgnorePointer(
                child: Transform.rotate(
                  // The tip is the knot in the string, so that is what it turns
                  // about: the bubble leans, the tether does not move.
                  angle:
                      _tilt.value *
                      (_disableAnimations ? 0.0 : scale.clamp(0.0, 1.0)),
                  alignment: Alignment.bottomCenter,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.bottomCenter,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: SizedBox(
                        width: width,
                        height: bodyHeight + tail,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: const Color(0xFFFFFFFF),
                            shape: _CLSliderBubbleShape(
                              radius: math.min(width, bodyHeight) / 2,
                              tailExtent: tail,
                              tailHalfWidth: math.min(
                                CLSlider.bubbleTailHalfWidth,
                                width / 2,
                              ),
                            ),
                            shadows: const [
                              BoxShadow(
                                color: Color(0x4D000000),
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: tail),
                            child: Center(
                              child: CLNumericText(
                                widget.valueLabel!(widget.value),
                                style: style,
                                alignment: Alignment.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// The bubble's size, fixed for the life of the range rather than measured
  /// per value: a bubble that resized under the finger would breathe on every
  /// digit. The widest label is looked for at both ends of the range and at its
  /// middle, which covers the sign and digit-count changes labels actually have.
  Size _measureBubble(BuildContext context, TextStyle style) {
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final key = Object.hash(style, textScaler, textDirection);
    final cached = _bubbleSize;
    if (cached != null && _bubbleMeasureKey == key) return cached;

    var width = 0.0;
    var height = 0.0;
    for (final value in [
      widget.min,
      (widget.min + widget.max) / 2,
      widget.max,
    ]) {
      final painter = TextPainter(
        text: TextSpan(text: widget.valueLabel!(value), style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      width = math.max(width, painter.width);
      height = math.max(height, painter.height);
      painter.dispose();
    }

    final size = Size(
      width + CLSlider.bubblePadding.horizontal,
      height + CLSlider.bubblePadding.vertical,
    );
    _bubbleSize = size;
    _bubbleMeasureKey = key;
    return size;
  }

  Widget _buildInteractiveSlider({
    required CLThemeData theme,
    required Color activeColor,
    required Color thumbColor,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _layoutWidth = width;
        final usable = width - CLSlider.thumbWidth;
        final thumbLeft = usable * _visual.value.clamp(0.0, 1.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Track taps spring the thumb; drags keep it glued to the finger.
          onTapDown: (details) {
            _setPressed(true);
            _update(details.localPosition, width);
          },
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onHorizontalDragStart: (details) {
            _setPressed(true, tracking: true);
            _update(details.localPosition, width);
          },
          onHorizontalDragUpdate: (details) =>
              _update(details.localPosition, width),
          onHorizontalDragEnd: (_) => _setPressed(false),
          onHorizontalDragCancel: () {
            if (_tracking) _setPressed(false);
          },
          child: _buildTrack(
            theme: theme,
            activeColor: activeColor,
            thumbColor: thumbColor,
            width: width,
            thumbLeft: thumbLeft,
          ),
        );
      },
    );
  }

  Widget _buildTrack({
    required CLThemeData theme,
    required Color activeColor,
    required Color thumbColor,
    required double width,
    required double thumbLeft,
  }) {
    final pressed = _press.value.clamp(0.0, 1.0);
    final line = math.max(_hover.value, pressed);
    final handleWidth = _handleWidth;
    final handleHeight = _lerp(
      _lerp(CLSlider.thumbHeight, CLSlider.hoverLineHeight, line),
      CLSlider.pressLineHeight,
      pressed,
    );

    final center = _handleCenter;
    final handleLeft = center - handleWidth / 2;
    final handleRight = center + handleWidth / 2;

    final active = _segment(
      from: 0,
      to: handleLeft - CLSlider.gap,
      width: width,
      color: activeColor,
    );
    final rest = _segment(
      from: handleRight + CLSlider.gap,
      to: width,
      width: width,
      color: theme.colors.track,
    );

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        // A segment with no room leaves the stack entirely rather than standing
        // in it as an empty box: a stack with any unpositioned child takes that
        // child's size, which would collapse the slider to nothing at either end
        // of the range.
        ?active,
        ?rest,
        Positioned(
          left: handleLeft,
          top: (CLSlider.hitHeight - handleHeight) / 2,
          width: handleWidth,
          height: handleHeight,
          child: DecoratedBox(
            decoration: clSmoothDecoration(
              color: thumbColor,
              borderRadius: BorderRadius.circular(
                math.min(handleWidth, handleHeight) / 2,
              ),
              shadows: const [
                BoxShadow(
                  color: Color(0x4D000000),
                  blurRadius: 6,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          // Measured from the resting capsule, not from the line: a box that
          // slid into the corner with the line could slide out from under the
          // cursor that opened it.
          left: thumbLeft + CLSlider.thumbWidth / 2 - CLSlider.hoverWidth / 2,
          top: 0,
          width: CLSlider.hoverWidth,
          height: CLSlider.hitHeight,
          child: MouseRegion(
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
          ),
        ),
      ],
    );
  }

  /// One piece of the rail, drawn the way [CLProgressBar] draws its segments:
  /// a round-capped line whose height is `min(length, trackHeight)`, so a piece
  /// running out of room beside the handle shrinks to a dot and leaves instead
  /// of standing on end as a sliver.
  Widget? _segment({
    required double from,
    required double to,
    required double width,
    required Color color,
  }) {
    final start = from.clamp(0.0, width);
    final length = to.clamp(0.0, width) - start;
    if (length <= 0) return null;
    final fill = math.min(length, CLSlider.trackHeight);
    return Positioned(
      left: start,
      top: (CLSlider.hitHeight - fill) / 2,
      width: length,
      height: fill,
      child: DecoratedBox(
        decoration: clSmoothDecoration(
          color: color,
          borderRadius: BorderRadius.circular(fill / 2),
        ),
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// The bubble's outline: the anchored-surface shape a tooltip is cut from, with
/// its tail shortened to nothing while the bubble is still the handle's capsule.
class _CLSliderBubbleShape extends ShapeBorder {
  const _CLSliderBubbleShape({
    required this.radius,
    required this.tailExtent,
    required this.tailHalfWidth,
  });

  final double radius;
  final double tailExtent;
  final double tailHalfWidth;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width,
      math.max(0, rect.height - tailExtent),
    );
    return clOverlaySurfacePath(
      body: body,
      borderRadius: radius,
      position: CLPopoverPosition.top,
      arrowCenter: body.width / 2,
      showArrow: tailExtent > 0.01,
      halfWidth: tailHalfWidth,
      extent: tailExtent,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => _CLSliderBubbleShape(
    radius: radius * t,
    tailExtent: tailExtent * t,
    tailHalfWidth: tailHalfWidth * t,
  );

  @override
  bool operator ==(Object other) =>
      other is _CLSliderBubbleShape &&
      other.radius == radius &&
      other.tailExtent == tailExtent &&
      other.tailHalfWidth == tailHalfWidth;

  @override
  int get hashCode => Object.hash(radius, tailExtent, tailHalfWidth);
}
