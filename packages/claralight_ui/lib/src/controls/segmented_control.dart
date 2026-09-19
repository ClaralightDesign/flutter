import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../foundation/control_size.dart';
import '../foundation/shape.dart';
import '../theme/theme.dart';

/// The Claralight segmented control — the 亮屏/息屏 pill of the mockups.
///
/// A recessed capsule track with a raised capsule thumb that springs between
/// equal-width segments.
class CLSegmentedControl extends StatefulWidget {
  /// Segment labels, in order.
  final List<String> segments;

  /// Index of the selected segment.
  final int selectedIndex;

  /// Called with the tapped segment index.
  final ValueChanged<int>? onChanged;

  final CLControlSize size;

  const CLSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.size = CLControlSize.large,
  }) : assert(segments.length >= 2),
       assert(selectedIndex >= 0 && selectedIndex < segments.length);

  @override
  State<CLSegmentedControl> createState() => _CLSegmentedControlState();
}

class _CLSegmentedControlState extends State<CLSegmentedControl>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 22,
  );

  late final AnimationController _position;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _position = AnimationController.unbounded(
      value: widget.selectedIndex.toDouble(),
      vsync: this,
    );
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
    _position.stop();
    _position.value = widget.selectedIndex.toDouble();
  }

  @override
  void didUpdateWidget(CLSegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      if (_disableAnimations) {
        _snapReducedMotionGeometry();
        return;
      }
      _position.animateWith(
        SpringSimulation(
          _spring,
          _position.value,
          widget.selectedIndex.toDouble(),
          // A thumb redirected while it is still travelling keeps the speed it
          // had. Starting the new flight from rest stops it dead in the middle
          // of the track, which is the one thing a sprung weight cannot do.
          _position.velocity,
          tolerance: Tolerance.defaultTolerance,
        ),
      );
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  double get _height => switch (widget.size) {
    CLControlSize.small => 26,
    CLControlSize.medium => 32,
    CLControlSize.large => 40,
  };

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    final enabled = widget.onChanged != null;
    final textStyle = widget.size == CLControlSize.small
        ? theme.typography.callout
        : theme.typography.body.withCLWeight(FontWeight.w600);

    return Semantics(
      enabled: enabled,
      child: SizedBox(
        height: _height,
        child: AnimatedBuilder(
          animation: _position,
          builder: (context, _) =>
              _buildTrack(theme: theme, enabled: enabled, textStyle: textStyle),
        ),
      ),
    );
  }

  Widget _buildTrack({
    required CLThemeData theme,
    required bool enabled,
    required TextStyle textStyle,
  }) {
    const inset = 3.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth =
            (constraints.maxWidth - inset * 2) / widget.segments.length;
        final thumbLeft =
            inset +
            segmentWidth * _position.value.clamp(0, widget.segments.length - 1);

        return DecoratedBox(
          decoration: clSmoothDecoration(
            color: theme.colors.track,
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          child: Stack(
            children: [
              Positioned(
                left: thumbLeft,
                top: inset,
                width: segmentWidth,
                height: _height - inset * 2,
                child: DecoratedBox(
                  // The raised segment is another white-alpha layer on top of
                  // the track, per the design source.
                  decoration: clSmoothDecoration(
                    color: theme.colors.control,
                    borderRadius: BorderRadius.circular(
                      (_height - inset * 2) / 2,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < widget.segments.length; i++)
                    Expanded(
                      child: _Segment(
                        label: widget.segments[i],
                        selected: i == widget.selectedIndex,
                        enabled: enabled,
                        textStyle: textStyle,
                        onTap: enabled ? () => widget.onChanged!(i) : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final TextStyle textStyle;
  final VoidCallback? onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.textStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = CLTheme.of(context).colors;
    final color = !enabled
        ? colors.textDisabled
        : selected
        ? colors.textPrimary
        : colors.textHint;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: CLMotion.standard,
            style: textStyle.copyWith(color: color),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}
