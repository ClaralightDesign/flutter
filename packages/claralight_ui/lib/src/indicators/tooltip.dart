import 'dart:async';

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../overlays/anchored_overlay.dart';
import '../theme/theme.dart';

export '../overlays/anchored_overlay.dart' show CLPopoverPosition;

class _TooltipGracePeriod {
  static const duration = Duration(milliseconds: 500);

  Timer? _cooldown;
  bool _active = false;

  bool get isActive => _active;

  void start() {
    _cooldown?.cancel();
    _active = true;
    _cooldown = Timer(duration, () {
      _active = false;
      _cooldown = null;
    });
  }
}

final _tooltipGracePeriods = Expando<_TooltipGracePeriod>(
  'CLTooltip grace periods',
);

_TooltipGracePeriod _gracePeriodFor(BuildContext context) {
  final overlay = Overlay.of(context);
  return _tooltipGracePeriods[overlay] ??= _TooltipGracePeriod();
}

/// A ClaraLight tooltip.
///
/// Wrap any widget; hovering (desktop) or long-pressing (touch) reveals a
/// frosted label near it, popping in from the pointing arrow.
class CLTooltip extends StatefulWidget {
  const CLTooltip({
    super.key,
    required this.message,
    required this.child,
    this.delay = const Duration(milliseconds: 450),
    this.position = CLPopoverPosition.top,
    this.showArrow = true,
    this.enableLongPress = true,
  });

  /// Tooltip text ("这按钮是干嘛的").
  final String message;

  final Widget child;

  /// Hover dwell time before the tooltip appears.
  final Duration delay;

  /// Preferred physical side. The tooltip may flip to remain visible.
  final CLPopoverPosition position;

  /// Whether the tooltip surface includes its pointing arrow.
  final bool showArrow;

  /// Whether touch and stylus long presses show the tooltip.
  final bool enableLongPress;

  @override
  State<CLTooltip> createState() => _CLTooltipState();
}

class _CLTooltipState extends State<CLTooltip> with TickerProviderStateMixin {
  final _anchorKey = GlobalKey();
  final _portal = OverlayPortalController();
  late final AnimationController _reveal;
  late final AnimationController _spring;
  Timer? _dwell;
  bool _shownFromHover = false;
  bool _open = false;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: CLMotion.fast,
      reverseDuration: const Duration(milliseconds: 110),
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_handleRevealStatus);
    _spring = AnimationController.unbounded(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations == disableAnimations) return;
    _disableAnimations = disableAnimations;
    if (disableAnimations) {
      _snapReducedMotionGeometry();
    } else if (_portal.isShowing) {
      _spring.animateWith(
        SpringSimulation(
          _open
              ? const SpringDescription(mass: 1, stiffness: 560, damping: 37)
              : const SpringDescription(mass: 1, stiffness: 620, damping: 40),
          _spring.value,
          _open ? 1 : 0,
          0,
        ),
      );
      _animateReveal(_open);
    }
  }

  void _snapReducedMotionGeometry() {
    _spring.stop();
    _spring.value = (_portal.isShowing || _reveal.value > 0) ? 1 : 0;
    if (_portal.isShowing) _animateReveal(_open);
  }

  TickerFuture _animateReveal(bool show) {
    if (!_disableAnimations) {
      return show ? _reveal.forward() : _reveal.reverse();
    }
    return show
        ? _reveal.animateTo(1, duration: CLMotion.reducedFade)
        : _reveal.animateBack(0, duration: CLMotion.reducedFade);
  }

  void _handleRevealStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || !_portal.isShowing) return;
    // OverlayPortalController owns the overlay rebuild; no local widget state
    // changes when the dismissed overlay is removed.
    _portal.hide();
    if (_disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_portal.isShowing) {
          _spring.stop();
          _spring.value = 0;
        }
      });
    }
  }

  @override
  void dispose() {
    _dwell?.cancel();
    _reveal.dispose();
    _spring.dispose();
    super.dispose();
  }

  void _scheduleShow() {
    _dwell?.cancel();
    final grace = _gracePeriodFor(context);
    final delay = grace.isActive ? Duration.zero : widget.delay;
    _dwell = Timer(delay, _showFromHover);
  }

  void _showFromHover() {
    if (!mounted) return;
    _shownFromHover = true;
    _show();
  }

  void _show() {
    if (!mounted) return;
    _open = true;
    if (_disableAnimations) {
      _spring.stop();
      _spring.value = 1;
    }
    if (!_portal.isShowing) _portal.show();
    _animateReveal(true);
    if (_disableAnimations) return;
    _spring.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 560, damping: 37),
        _spring.value,
        1,
        0,
      ),
    );
  }

  void _hide() {
    _dwell?.cancel();
    _open = false;
    final revealActive = _reveal.isAnimating || _reveal.value > 0;
    if (_disableAnimations) {
      _spring.stop();
      _spring.value = 1;
      if (!revealActive) {
        if (_portal.isShowing) _portal.hide();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_portal.isShowing) {
            _spring.stop();
            _spring.value = 0;
          }
        });
        return;
      }
      _animateReveal(false);
      return;
    }
    if (!revealActive) {
      _spring
        ..stop()
        ..value = 0;
      if (_portal.isShowing) _portal.hide();
      return;
    }

    _animateReveal(false);
    _spring.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 620, damping: 40),
        _spring.value,
        0,
        0,
      ),
    );
  }

  void _handleHoverExit() {
    final shouldStartGrace =
        _shownFromHover &&
        (_portal.isShowing || _reveal.isAnimating || _reveal.value > 0);
    _shownFromHover = false;
    _hide();
    if (shouldStartGrace) _gracePeriodFor(context).start();
  }

  void _handleLongPress() {
    _dwell?.cancel();
    _dwell = null;
    _shownFromHover = false;
    _show();
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _dwell?.cancel();
    _dwell = null;
    _shownFromHover = false;
    _hide();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: KeyedSubtree(
        key: _anchorKey,
        child: MouseRegion(
          onEnter: (_) => _scheduleShow(),
          onExit: (_) => _handleHoverExit(),
          child: GestureDetector(
            onLongPress: widget.enableLongPress ? _handleLongPress : null,
            onLongPressEnd: widget.enableLongPress ? _handleLongPressEnd : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final theme = CLTheme.of(context);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_reveal, _spring]),
        builder: (context, child) {
          return CLAnchoredOverlay(
            anchorKey: _anchorKey,
            position: widget.position,
            showArrow: widget.showArrow,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            borderRadius: theme.radii.medium,
            fill: theme.colors.frost.withValues(
              alpha: theme.colors.frost.a * 0.68,
            ),
            outlineColor: theme.colors.outline,
            shadowColor: const Color(0x40000000),
            shadowBlur: 18,
            shadowOffset: const Offset(0, 6),
            // Normal motion grows the surface from the anchor with a spring
            // overshoot; opacity is reserved for the non-moving
            // reduced-motion fallback.
            opacity: _disableAnimations
                ? CLMotion.easeOut.transform(_reveal.value)
                : 1,
            scale: _disableAnimations
                ? 1
                : Curves.easeOutCubic.transform(_reveal.value) * _spring.value,
            child: child!,
          );
        },
        child: Text(
          widget.message,
          style: theme.typography.callout
              .withCLWeight(FontWeight.w500)
              .copyWith(color: theme.colors.textSecondary),
        ),
      ),
    );
  }
}
