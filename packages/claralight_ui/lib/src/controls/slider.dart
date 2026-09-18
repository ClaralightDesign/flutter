import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../foundation/shape.dart';
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
class CLSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// Fill color of the active track. Defaults to the theme accent.
  final Color? activeColor;

  const CLSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.activeColor,
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
  }

  @override
  void didUpdateWidget(CLSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _visual.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onChanged != null;

  double get _fraction =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  void _update(Offset localPosition, double width) {
    if (!_enabled) return;
    final usable = width - CLSlider.thumbWidth;
    final fraction = ((localPosition.dx - CLSlider.thumbWidth / 2) / usable)
        .clamp(0.0, 1.0);
    widget.onChanged!(widget.min + fraction * (widget.max - widget.min));
  }

  void _setPressed(bool pressed, {bool tracking = false}) {
    _tracking = pressed && tracking;
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

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    var active = widget.activeColor ?? theme.colors.accent;
    var thumb = const Color(0xFFFFFFFF);
    if (!_enabled) {
      active = active.withValues(alpha: active.a * 0.45);
      thumb = thumb.withValues(alpha: 0.7);
    }

    return Semantics(
      slider: true,
      enabled: _enabled,
      value: widget.value.toStringAsFixed(2),
      child: SizedBox(
        height: CLSlider.hitHeight,
        child: AnimatedBuilder(
          animation: _geometryAnimation,
          builder: (context, _) => _buildInteractiveSlider(
            theme: theme,
            activeColor: active,
            thumbColor: thumb,
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveSlider({
    required CLThemeData theme,
    required Color activeColor,
    required Color thumbColor,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
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
    // The press state is the hover line thickened, so it carries the handle
    // through the capsule-to-line morph on its own where there is no pointer
    // to hover — a touch drag.
    final pressed = _press.value.clamp(0.0, 1.0);
    final line = math.max(_hover.value, pressed);
    final handleWidth = _lerp(
      _lerp(CLSlider.thumbWidth, CLSlider.hoverLineWidth, line),
      CLSlider.pressLineWidth,
      pressed,
    );
    final handleHeight = _lerp(
      _lerp(CLSlider.thumbHeight, CLSlider.hoverLineHeight, line),
      CLSlider.pressLineHeight,
      pressed,
    );

    final center = thumbLeft + CLSlider.thumbWidth / 2;
    final handleLeft = center - handleWidth / 2;
    final handleRight = center + handleWidth / 2;

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        _segment(
          from: 0,
          to: handleLeft - CLSlider.gap,
          width: width,
          color: activeColor,
        ),
        _segment(
          from: handleRight + CLSlider.gap,
          to: width,
          width: width,
          color: theme.colors.track,
        ),
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
          left: center - CLSlider.hoverWidth / 2,
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
  Widget _segment({
    required double from,
    required double to,
    required double width,
    required Color color,
  }) {
    final start = from.clamp(0.0, width);
    final length = to.clamp(0.0, width) - start;
    if (length <= 0) return const SizedBox.shrink();
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
