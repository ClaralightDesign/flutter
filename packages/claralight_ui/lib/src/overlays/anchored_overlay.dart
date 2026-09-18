import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// The preferred physical side of an anchored overlay.
enum CLPopoverPosition { top, bottom, left, right }

const double _arrowExtent = 7;
const double _arrowHalfWidth = 12;
const double _anchorGap = 4;
const double _screenMargin = 8;

/// Shared positioning and surface implementation for popovers and tooltips.
///
/// This is public only so sibling Dart libraries can reuse it. It is not
/// exported from the package barrel.
class CLAnchoredOverlay extends StatefulWidget {
  const CLAnchoredOverlay({
    super.key,
    required this.anchorKey,
    required this.position,
    required this.showArrow,
    required this.padding,
    required this.borderRadius,
    required this.fill,
    required this.outlineColor,
    required this.shadowColor,
    required this.shadowBlur,
    required this.shadowOffset,
    required this.opacity,
    required this.scale,
    required this.child,
  });

  final GlobalKey anchorKey;
  final CLPopoverPosition position;
  final bool showArrow;
  final EdgeInsets padding;
  final double borderRadius;
  final Color fill;
  final Color outlineColor;
  final Color shadowColor;
  final double shadowBlur;
  final Offset shadowOffset;
  final double opacity;
  final double scale;
  final Widget child;

  @override
  State<CLAnchoredOverlay> createState() => _CLAnchoredOverlayState();
}

class _CLAnchoredOverlayState extends State<CLAnchoredOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _overlayKey = GlobalKey();
  late final AnimationController _placementTransition;
  Rect? _anchorRect;
  bool _trackingScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _placementTransition = AnimationController(
      vsync: this,
      duration: CLMotion.standard,
      value: 1,
    );
    _scheduleTracking();
  }

  @override
  void didUpdateWidget(CLAnchoredOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchorKey != widget.anchorKey) _measureAnchor();
  }

  @override
  void didChangeMetrics() {
    _measureAnchor();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _placementTransition.dispose();
    super.dispose();
  }

  void _scheduleTracking() {
    if (_trackingScheduled) return;
    _trackingScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback(_trackAfterFrame);
  }

  void _trackAfterFrame(Duration _) {
    _trackingScheduled = false;
    if (!mounted) return;
    _measureAnchor();
    // This does not schedule a frame. It simply samples the anchor whenever
    // scrolling, resizing, or another animation produces the next frame.
    _scheduleTracking();
  }

  void _measureAnchor() {
    final anchorObject = widget.anchorKey.currentContext?.findRenderObject();
    final overlayObject = _overlayKey.currentContext?.findRenderObject();
    if (anchorObject is! RenderBox ||
        overlayObject is! RenderBox ||
        !anchorObject.hasSize ||
        !overlayObject.hasSize) {
      return;
    }

    final globalOrigin = anchorObject.localToGlobal(Offset.zero);
    final localOrigin = overlayObject.globalToLocal(globalOrigin);
    final next = localOrigin & anchorObject.size;
    final current = _anchorRect;
    if (current == null || !_rectNear(current, next)) {
      setState(() => _anchorRect = next);
    }
  }

  void _animatePlacementChange() {
    if (!mounted) return;
    _placementTransition.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final insets = EdgeInsets.fromLTRB(
      math.max(media.viewPadding.left, media.viewInsets.left) + _screenMargin,
      math.max(media.viewPadding.top, media.viewInsets.top) + _screenMargin,
      math.max(media.viewPadding.right, media.viewInsets.right) + _screenMargin,
      math.max(media.viewPadding.bottom, media.viewInsets.bottom) +
          _screenMargin,
    );

    return SizedBox.expand(
      key: _overlayKey,
      child: AnimatedBuilder(
        animation: _placementTransition,
        builder: (context, child) {
          final anchorRect = _anchorRect;
          if (anchorRect == null) return const SizedBox.shrink();
          return _CLAnchoredLayout(
            anchorRect: anchorRect,
            safeInsets: insets,
            preferredPosition: widget.position,
            transitionProgress: Curves.easeOutCubic.transform(
              _placementTransition.value,
            ),
            onDiscretePlacementChanged: _animatePlacementChange,
            child: child!,
          );
        },
        child: _CLAnchoredSurface(
          position: widget.position,
          showArrow: widget.showArrow,
          padding: widget.padding,
          borderRadius: widget.borderRadius,
          fill: widget.fill,
          outlineColor: widget.outlineColor,
          shadowColor: widget.shadowColor,
          shadowBlur: widget.shadowBlur,
          shadowOffset: widget.shadowOffset,
          opacity: widget.opacity,
          scale: widget.scale,
          child: widget.child,
        ),
      ),
    );
  }
}

bool _rectNear(Rect a, Rect b) {
  const epsilon = 0.1;
  return (a.left - b.left).abs() < epsilon &&
      (a.top - b.top).abs() < epsilon &&
      (a.width - b.width).abs() < epsilon &&
      (a.height - b.height).abs() < epsilon;
}

class _CLAnchoredLayout extends SingleChildRenderObjectWidget {
  const _CLAnchoredLayout({
    required this.anchorRect,
    required this.safeInsets,
    required this.preferredPosition,
    required this.transitionProgress,
    required this.onDiscretePlacementChanged,
    required super.child,
  });

  final Rect anchorRect;
  final EdgeInsets safeInsets;
  final CLPopoverPosition preferredPosition;
  final double transitionProgress;
  final VoidCallback onDiscretePlacementChanged;

  @override
  _RenderCLAnchoredLayout createRenderObject(BuildContext context) {
    return _RenderCLAnchoredLayout(
      anchorRect: anchorRect,
      safeInsets: safeInsets,
      preferredPosition: preferredPosition,
      transitionProgress: transitionProgress,
      onDiscretePlacementChanged: onDiscretePlacementChanged,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCLAnchoredLayout renderObject,
  ) {
    renderObject
      ..anchorRect = anchorRect
      ..safeInsets = safeInsets
      ..preferredPosition = preferredPosition
      ..transitionProgress = transitionProgress
      ..onDiscretePlacementChanged = onDiscretePlacementChanged;
  }
}

class _RenderCLAnchoredLayout extends RenderShiftedBox {
  _RenderCLAnchoredLayout({
    required Rect anchorRect,
    required EdgeInsets safeInsets,
    required CLPopoverPosition preferredPosition,
    required double transitionProgress,
    required VoidCallback onDiscretePlacementChanged,
  }) : _anchorRect = anchorRect,
       _safeInsets = safeInsets,
       _preferredPosition = preferredPosition,
       _transitionProgress = transitionProgress,
       _onDiscretePlacementChanged = onDiscretePlacementChanged,
       super(null);

  Rect _anchorRect;
  EdgeInsets _safeInsets;
  CLPopoverPosition _preferredPosition;
  double _transitionProgress;
  VoidCallback _onDiscretePlacementChanged;

  Offset _fromOffset = Offset.zero;
  Offset _targetOffset = Offset.zero;
  Offset _currentOffset = Offset.zero;
  CLPopoverPosition? _resolvedPosition;
  bool? _wasOffscreen;
  bool _hasGeometry = false;
  bool _transitioning = false;
  bool _placementCallbackScheduled = false;

  set anchorRect(Rect value) {
    if (_rectNear(_anchorRect, value)) return;
    _anchorRect = value;
    markNeedsLayout();
  }

  set safeInsets(EdgeInsets value) {
    if (_safeInsets == value) return;
    _safeInsets = value;
    markNeedsLayout();
  }

  set preferredPosition(CLPopoverPosition value) {
    if (_preferredPosition == value) return;
    _preferredPosition = value;
    markNeedsLayout();
  }

  set transitionProgress(double value) {
    if (_transitionProgress == value) return;
    _transitionProgress = value;
    markNeedsLayout();
  }

  set onDiscretePlacementChanged(VoidCallback value) {
    _onDiscretePlacementChanged = value;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  Rect _safeRectFor(Size overlaySize) {
    final left = _safeInsets.left.clamp(0.0, overlaySize.width);
    final top = _safeInsets.top.clamp(0.0, overlaySize.height);
    final right = (overlaySize.width - _safeInsets.right).clamp(
      left,
      overlaySize.width,
    );
    final bottom = (overlaySize.height - _safeInsets.bottom).clamp(
      top,
      overlaySize.height,
    );
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final surface = child;
    if (surface is! _RenderCLAnchoredSurface) return;

    final safeRect = _safeRectFor(size);
    final offscreen = !_anchorRect.overlaps(safeRect);
    var position = offscreen
        ? _positionForOffscreenAnchor(_anchorRect, safeRect)
        : _preferredPosition;

    surface.setPositionForParentLayout(position);
    // Arbitrary popover content may contain LayoutBuilder, which explicitly
    // cannot compute dry layout. A real loose layout gives us the natural
    // screen-constrained size used to choose a side; the final side-specific
    // layout below then applies the available main-axis space.
    surface.layout(BoxConstraints.loose(safeRect.size), parentUsesSize: true);
    final naturalSize = surface.size;

    if (!offscreen) {
      final preferredSpace = _spaceFor(position, _anchorRect, safeRect);
      final opposite = _opposite(position);
      final oppositeSpace = _spaceFor(opposite, _anchorRect, safeRect);
      final naturalMain = _mainExtent(naturalSize, position);
      if (naturalMain > preferredSpace && oppositeSpace >= naturalMain) {
        position = opposite;
      } else if (naturalMain > preferredSpace &&
          naturalMain > oppositeSpace &&
          oppositeSpace > preferredSpace) {
        position = opposite;
      }
    }

    surface.setPositionForParentLayout(position);
    final maxMain = offscreen
        ? _mainExtent(safeRect.size, position)
        : math.max(0.0, _spaceFor(position, _anchorRect, safeRect));
    final childConstraints = switch (position) {
      CLPopoverPosition.top || CLPopoverPosition.bottom => BoxConstraints(
        maxWidth: safeRect.width,
        maxHeight: maxMain,
      ),
      CLPopoverPosition.left || CLPopoverPosition.right => BoxConstraints(
        maxWidth: maxMain,
        maxHeight: safeRect.height,
      ),
    };
    surface.layout(childConstraints, parentUsesSize: true);

    final target = _targetOffsetFor(
      position: position,
      childSize: surface.size,
      safeRect: safeRect,
      offscreen: offscreen,
    );
    final discreteChange =
        _hasGeometry &&
        (_resolvedPosition != position || _wasOffscreen != offscreen);

    if (!_hasGeometry) {
      _currentOffset = target;
      _fromOffset = target;
      _targetOffset = target;
      _hasGeometry = true;
    } else if (discreteChange) {
      _fromOffset = _currentOffset;
      _targetOffset = target;
      _transitioning = true;
      _schedulePlacementCallback();
    } else if (_transitioning) {
      _targetOffset = target;
      _currentOffset = Offset.lerp(
        _fromOffset,
        _targetOffset,
        _transitionProgress,
      )!;
      if (_transitionProgress >= 1) _transitioning = false;
    } else {
      _currentOffset = target;
      _fromOffset = target;
      _targetOffset = target;
    }

    _resolvedPosition = position;
    _wasOffscreen = offscreen;
    (surface.parentData! as BoxParentData).offset = _currentOffset;

    final arrowCenter = switch (position) {
      CLPopoverPosition.top || CLPopoverPosition.bottom =>
        (_anchorRect.center.dx.clamp(safeRect.left, safeRect.right) -
            _currentOffset.dx),
      CLPopoverPosition.left || CLPopoverPosition.right =>
        (_anchorRect.center.dy.clamp(safeRect.top, safeRect.bottom) -
            _currentOffset.dy),
    };
    surface.setArrowCenterForParentLayout(arrowCenter);
  }

  void _schedulePlacementCallback() {
    if (_placementCallbackScheduled) return;
    _placementCallbackScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _placementCallbackScheduled = false;
      if (attached) _onDiscretePlacementChanged();
    });
  }

  Offset _targetOffsetFor({
    required CLPopoverPosition position,
    required Size childSize,
    required Rect safeRect,
    required bool offscreen,
  }) {
    double x;
    double y;
    switch (position) {
      case CLPopoverPosition.top:
        x = _anchorRect.center.dx - childSize.width / 2;
        y = offscreen
            ? safeRect.bottom - childSize.height
            : _anchorRect.top - _anchorGap - childSize.height;
      case CLPopoverPosition.bottom:
        x = _anchorRect.center.dx - childSize.width / 2;
        y = offscreen ? safeRect.top : _anchorRect.bottom + _anchorGap;
      case CLPopoverPosition.left:
        x = offscreen
            ? safeRect.right - childSize.width
            : _anchorRect.left - _anchorGap - childSize.width;
        y = _anchorRect.center.dy - childSize.height / 2;
      case CLPopoverPosition.right:
        x = offscreen ? safeRect.left : _anchorRect.right + _anchorGap;
        y = _anchorRect.center.dy - childSize.height / 2;
    }

    return Offset(
      _clampAxis(x, safeRect.left, safeRect.right - childSize.width),
      _clampAxis(y, safeRect.top, safeRect.bottom - childSize.height),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final surface = child;
    if (surface == null) return false;
    final childParentData = surface.parentData! as BoxParentData;
    return result.addWithPaintOffset(
      offset: childParentData.offset,
      position: position,
      hitTest: (result, transformed) =>
          surface.hitTest(result, position: transformed),
    );
  }
}

double _clampAxis(double value, double min, double max) {
  if (max < min) return min;
  return value.clamp(min, max);
}

double _mainExtent(Size size, CLPopoverPosition position) {
  return switch (position) {
    CLPopoverPosition.top || CLPopoverPosition.bottom => size.height,
    CLPopoverPosition.left || CLPopoverPosition.right => size.width,
  };
}

double _spaceFor(CLPopoverPosition position, Rect anchorRect, Rect safeRect) {
  return math.max(0, switch (position) {
    CLPopoverPosition.top => anchorRect.top - safeRect.top - _anchorGap,
    CLPopoverPosition.bottom =>
      safeRect.bottom - anchorRect.bottom - _anchorGap,
    CLPopoverPosition.left => anchorRect.left - safeRect.left - _anchorGap,
    CLPopoverPosition.right => safeRect.right - anchorRect.right - _anchorGap,
  });
}

CLPopoverPosition _opposite(CLPopoverPosition position) {
  return switch (position) {
    CLPopoverPosition.top => CLPopoverPosition.bottom,
    CLPopoverPosition.bottom => CLPopoverPosition.top,
    CLPopoverPosition.left => CLPopoverPosition.right,
    CLPopoverPosition.right => CLPopoverPosition.left,
  };
}

CLPopoverPosition _positionForOffscreenAnchor(Rect anchor, Rect safeRect) {
  final candidates = <(double, CLPopoverPosition)>[];
  if (anchor.bottom <= safeRect.top) {
    candidates.add((safeRect.top - anchor.bottom, CLPopoverPosition.bottom));
  }
  if (anchor.top >= safeRect.bottom) {
    candidates.add((anchor.top - safeRect.bottom, CLPopoverPosition.top));
  }
  if (anchor.right <= safeRect.left) {
    candidates.add((safeRect.left - anchor.right, CLPopoverPosition.right));
  }
  if (anchor.left >= safeRect.right) {
    candidates.add((anchor.left - safeRect.right, CLPopoverPosition.left));
  }
  if (candidates.isEmpty) return CLPopoverPosition.bottom;
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  return candidates.first.$2;
}

class _CLAnchoredSurface extends SingleChildRenderObjectWidget {
  const _CLAnchoredSurface({
    required this.position,
    required this.showArrow,
    required this.padding,
    required this.borderRadius,
    required this.fill,
    required this.outlineColor,
    required this.shadowColor,
    required this.shadowBlur,
    required this.shadowOffset,
    required this.opacity,
    required this.scale,
    required super.child,
  });

  final CLPopoverPosition position;
  final bool showArrow;
  final EdgeInsets padding;
  final double borderRadius;
  final Color fill;
  final Color outlineColor;
  final Color shadowColor;
  final double shadowBlur;
  final Offset shadowOffset;
  final double opacity;
  final double scale;

  @override
  _RenderCLAnchoredSurface createRenderObject(BuildContext context) {
    return _RenderCLAnchoredSurface(
      position: position,
      showArrow: showArrow,
      padding: padding,
      borderRadius: borderRadius,
      fill: fill,
      outlineColor: outlineColor,
      shadowColor: shadowColor,
      shadowBlur: shadowBlur,
      shadowOffset: shadowOffset,
      opacity: opacity,
      scale: scale,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCLAnchoredSurface renderObject,
  ) {
    renderObject
      ..position = position
      ..showArrow = showArrow
      ..padding = padding
      ..borderRadius = borderRadius
      ..fill = fill
      ..outlineColor = outlineColor
      ..shadowColor = shadowColor
      ..shadowBlur = shadowBlur
      ..shadowOffset = shadowOffset
      ..opacity = opacity
      ..scale = scale;
  }
}

class _RenderCLAnchoredSurface extends RenderShiftedBox {
  _RenderCLAnchoredSurface({
    required CLPopoverPosition position,
    required bool showArrow,
    required EdgeInsets padding,
    required double borderRadius,
    required Color fill,
    required Color outlineColor,
    required Color shadowColor,
    required double shadowBlur,
    required Offset shadowOffset,
    required double opacity,
    required double scale,
  }) : _position = position,
       _showArrow = showArrow,
       _padding = padding,
       _borderRadius = borderRadius,
       _fill = fill,
       _outlineColor = outlineColor,
       _shadowColor = shadowColor,
       _shadowBlur = shadowBlur,
       _shadowOffset = shadowOffset,
       _opacity = opacity,
       _scale = scale,
       super(null);

  CLPopoverPosition _position;
  bool _showArrow;
  EdgeInsets _padding;
  double _borderRadius;
  Color _fill;
  Color _outlineColor;
  Color _shadowColor;
  double _shadowBlur;
  Offset _shadowOffset;
  double _opacity;
  double _scale;
  double _arrowCenter = 0;

  set position(CLPopoverPosition value) {
    if (_position == value) return;
    _position = value;
    markNeedsLayout();
  }

  set showArrow(bool value) {
    if (_showArrow == value) return;
    _showArrow = value;
    markNeedsPaint();
  }

  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  set borderRadius(double value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  set fill(Color value) {
    if (_fill == value) return;
    _fill = value;
    markNeedsPaint();
  }

  set outlineColor(Color value) {
    if (_outlineColor == value) return;
    _outlineColor = value;
    markNeedsPaint();
  }

  set shadowColor(Color value) {
    if (_shadowColor == value) return;
    _shadowColor = value;
    markNeedsPaint();
  }

  set shadowBlur(double value) {
    if (_shadowBlur == value) return;
    _shadowBlur = value;
    markNeedsPaint();
  }

  set shadowOffset(Offset value) {
    if (_shadowOffset == value) return;
    _shadowOffset = value;
    markNeedsPaint();
  }

  set opacity(double value) {
    if (_opacity == value) return;
    _opacity = value;
    markNeedsPaint();
  }

  set scale(double value) {
    if (_scale == value) return;
    _scale = value;
    markNeedsPaint();
  }

  void setPositionForParentLayout(CLPopoverPosition value) {
    _position = value;
  }

  void setArrowCenterForParentLayout(double value) {
    if (_arrowCenter == value) return;
    _arrowCenter = value;
    markNeedsPaint();
  }

  EdgeInsets get _outerInsets => switch (_position) {
    CLPopoverPosition.top => const EdgeInsets.only(bottom: _arrowExtent),
    CLPopoverPosition.bottom => const EdgeInsets.only(top: _arrowExtent),
    CLPopoverPosition.left => const EdgeInsets.only(right: _arrowExtent),
    CLPopoverPosition.right => const EdgeInsets.only(left: _arrowExtent),
  };

  EdgeInsets get _contentInsets => _padding + _outerInsets;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final insets = _contentInsets;
    final innerConstraints = constraints.deflate(insets);
    final childSize = child?.getDryLayout(innerConstraints) ?? Size.zero;
    return constraints.constrain(
      Size(
        childSize.width + insets.horizontal,
        childSize.height + insets.vertical,
      ),
    );
  }

  @override
  void performLayout() {
    final insets = _contentInsets;
    final innerConstraints = constraints.deflate(insets);
    child?.layout(innerConstraints, parentUsesSize: true);
    final childSize = child?.size ?? Size.zero;
    size = constraints.constrain(
      Size(
        childSize.width + insets.horizontal,
        childSize.height + insets.vertical,
      ),
    );
    if (child != null) {
      (child!.parentData! as BoxParentData).offset = Offset(
        insets.left,
        insets.top,
      );
    }
  }

  Rect get _bodyRect => switch (_position) {
    CLPopoverPosition.top => Rect.fromLTRB(
      0,
      0,
      size.width,
      size.height - _arrowExtent,
    ),
    CLPopoverPosition.bottom => Rect.fromLTRB(
      0,
      _arrowExtent,
      size.width,
      size.height,
    ),
    CLPopoverPosition.left => Rect.fromLTRB(
      0,
      0,
      size.width - _arrowExtent,
      size.height,
    ),
    CLPopoverPosition.right => Rect.fromLTRB(
      _arrowExtent,
      0,
      size.width,
      size.height,
    ),
  };

  Path _surfacePath() => clOverlaySurfacePath(
    body: _bodyRect,
    borderRadius: _borderRadius,
    position: _position,
    arrowCenter: _arrowCenter,
    showArrow: _showArrow,
  );

  Offset get _scaleOrigin => switch (_position) {
    CLPopoverPosition.top => Offset(_arrowCenter, size.height),
    CLPopoverPosition.bottom => Offset(_arrowCenter, 0),
    CLPopoverPosition.left => Offset(size.width, _arrowCenter),
    CLPopoverPosition.right => Offset(0, _arrowCenter),
  };

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_opacity <= 0 || _scale <= 0 || size.isEmpty) return;
    final alpha = (_opacity.clamp(0.0, 1.0) * 255).round();
    context.pushOpacity(offset, alpha, (context, offset) {
      final origin = _scaleOrigin;
      final transform = Matrix4.identity()
        ..translateByDouble(origin.dx, origin.dy, 0, 1)
        ..scaleByDouble(_scale, _scale, 1, 1)
        ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
      context.pushTransform(needsCompositing, offset, transform, _paintSurface);
    });
  }

  void _paintSurface(PaintingContext context, Offset offset) {
    final localPath = _surfacePath();
    final path = localPath.shift(offset);

    context.pushClipPath(needsCompositing, offset, offset & size, path, (
      context,
      offset,
    ) {
      context.pushLayer(
        BackdropFilterLayer(
          filter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        ),
        (context, offset) {
          context.canvas.drawRect(offset & size, Paint()..color = _fill);
          if (child != null) {
            final childParentData = child!.parentData! as BoxParentData;
            context.paintChild(child!, offset + childParentData.offset);
          }
        },
        offset,
      );
    }, clipBehavior: Clip.antiAlias);

    // Paint the shadow after the backdrop layer, then clear the surface
    // interior. This keeps the shadow visually behind the panel without
    // feeding it back into the backdrop blur.
    final canvas = context.canvas;
    if (_shadowColor.a > 0 && _shadowBlur > 0) {
      final extent =
          _shadowBlur * 2 + _shadowOffset.dx.abs() + _shadowOffset.dy.abs();
      canvas.saveLayer(path.getBounds().inflate(extent), Paint());
      canvas.drawPath(
        path.shift(_shadowOffset),
        Paint()
          ..color = _shadowColor
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            ui.Shadow.convertRadiusToSigma(_shadowBlur),
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.clear
          ..isAntiAlias = true,
      );
      canvas.restore();
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = _outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool hitTestSelf(Offset position) {
    if (_scale <= 0) return false;
    // The surface is painted through an anchor-origin scale, so hits must be
    // inverse-transformed into the same space. This keeps the hit area glued
    // to the visually growing surface instead of the full-size placeholder.
    final origin = _scaleOrigin;
    return _surfacePath().contains(
      Offset(
        origin.dx + (position.dx - origin.dx) / _scale,
        origin.dy + (position.dy - origin.dy) / _scale,
      ),
    );
  }
}

/// The outline an anchored surface is cut from: a smooth-cornered body, and the
/// tail that points it at its anchor.
///
/// Public so the slider's value bubble can be cut from the same one. A bubble
/// tethered to a handle and a tooltip tethered to its anchor are the same
/// gesture, and two hand-fitted outlines would drift apart the moment either
/// was adjusted. The tail's curve is written in fractions of [halfWidth] and
/// [extent], so a small bubble takes a small tail rather than a different
/// shape, and an [extent] of zero is the body alone — which is how a shape that
/// grows its tail on the way up gets there.
Path clOverlaySurfacePath({
  required Rect body,
  required double borderRadius,
  required CLPopoverPosition position,
  required double arrowCenter,
  bool showArrow = true,
  double halfWidth = _arrowHalfWidth,
  double extent = _arrowExtent,
}) {
  final radius = math.min(borderRadius, math.min(body.width, body.height) / 2);
  final bodyPath = Path()
    ..addRSuperellipse(
      RSuperellipse.fromRectAndRadius(body, Radius.circular(radius)),
    );
  if (!showArrow) return bodyPath;

  final minCenter = radius + halfWidth + 1;
  final maxCenter = switch (position) {
    CLPopoverPosition.top || CLPopoverPosition.bottom => body.width - minCenter,
    CLPopoverPosition.left ||
    CLPopoverPosition.right => body.height - minCenter,
  };
  final center = maxCenter < minCenter
      ? switch (position) {
          CLPopoverPosition.top || CLPopoverPosition.bottom => body.width / 2,
          CLPopoverPosition.left || CLPopoverPosition.right => body.height / 2,
        }
      : arrowCenter.clamp(minCenter, maxCenter);
  return Path.combine(
    PathOperation.union,
    bodyPath,
    _overlayTailPath(body, center, position, halfWidth, extent),
  );
}

Path _overlayTailPath(
  Rect body,
  double center,
  CLPopoverPosition position,
  double halfWidth,
  double extent,
) {
  const overlap = 1.5;
  final width = halfWidth;
  final height = extent;

  Offset point(double cross, double outward) => switch (position) {
    CLPopoverPosition.top => Offset(center + cross, body.bottom + outward),
    CLPopoverPosition.bottom => Offset(center - cross, body.top - outward),
    CLPopoverPosition.left => Offset(body.right + outward, center - cross),
    CLPopoverPosition.right => Offset(body.left - outward, center + cross),
  };

  // Two cubic segments per half keep the body join G2 with the flat edge.
  // The compact 0.16w body handle controls the root rounding; the following
  // cross-axis controls are derived so the shoulder join remains C2.
  // Mirroring preserves tangent and curvature at the rounded tip, whose
  // 0.225w handle gives a radius of about 0.446h for the fixed 24x7 tail.
  final bodyControlCross = -0.84 * width;
  final midCross = -0.50 * width;
  final tipControlCross = -0.225 * width;
  final shoulderControlCross =
      (4 * midCross + bodyControlCross - tipControlCross) / 4;
  final midControlCross = 2 * midCross - shoulderControlCross;

  final leftBase = point(-width, 0);
  final leftBodyControl = point(bodyControlCross, 0);
  final leftShoulderControl = point(shoulderControlCross, 0);
  final leftMid = point(midCross, 0.25 * height);
  final leftMidControl = point(midControlCross, 0.50 * height);
  final leftTipControl = point(tipControlCross, height);
  final tip = point(0, height);
  final rightTipControl = point(-tipControlCross, height);
  final rightMidControl = point(-midControlCross, 0.50 * height);
  final rightMid = point(-midCross, 0.25 * height);
  final rightShoulderControl = point(-shoulderControlCross, 0);
  final rightBodyControl = point(-bodyControlCross, 0);
  final rightBase = point(width, 0);
  final backingRight = point(width, -overlap);
  final backingLeft = point(-width, -overlap);

  return Path()
    ..moveTo(leftBase.dx, leftBase.dy)
    ..cubicTo(
      leftBodyControl.dx,
      leftBodyControl.dy,
      leftShoulderControl.dx,
      leftShoulderControl.dy,
      leftMid.dx,
      leftMid.dy,
    )
    ..cubicTo(
      leftMidControl.dx,
      leftMidControl.dy,
      leftTipControl.dx,
      leftTipControl.dy,
      tip.dx,
      tip.dy,
    )
    ..cubicTo(
      rightTipControl.dx,
      rightTipControl.dy,
      rightMidControl.dx,
      rightMidControl.dy,
      rightMid.dx,
      rightMid.dy,
    )
    ..cubicTo(
      rightShoulderControl.dx,
      rightShoulderControl.dy,
      rightBodyControl.dx,
      rightBodyControl.dy,
      rightBase.dx,
      rightBase.dy,
    )
    // Keep overlap inside the body for robust path union without moving the
    // visible curve away from the body edge.
    ..lineTo(backingRight.dx, backingRight.dy)
    ..lineTo(backingLeft.dx, backingLeft.dy)
    ..close();
}
