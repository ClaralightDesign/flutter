import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../containers/toolbar_scope.dart';
import '../foundation/control_size.dart';
import '../foundation/shape.dart';
import '../scrolling/cl_list.dart';
import '../surfaces/pressable.dart';
import '../surfaces/surface.dart';
import '../theme/theme.dart';

/// Horizontal gap between an option's leading widget and its label, and the
/// width allowance reserved for a leading widget in width estimates.
const double _kLeadingGap = 8;
const double _kLeadingAllowance = 26;

/// Claralight select dropdown variants.
enum CLSelectVariant {
  /// Standard neutral control-fill select field.
  standard,

  /// No fill until hovered; for toolbar rows and quiet selects.
  ghost,
}

/// One option of a [CLSelect].
class CLSelectOption<T> {
  final T value;
  final String label;

  /// Optional widget shown before the label in both the trigger and the
  /// options panel, such as a leading glyph or icon.
  final Widget? leading;

  const CLSelectOption(this.value, this.label, {this.leading});
}

/// A Claralight dropdown — the "填充模式 / 数字填充" and "格式 / 00:00"
/// fields of the desktop mockup.
///
/// A control-fill rounded rectangle showing the selected label and a
/// chevron; tapping pops a flat options panel that springs open below or
/// above the field.
class CLSelect<T> extends StatefulWidget {
  final List<CLSelectOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  /// Configured variant. When omitted, the select defaults to [CLSelectVariant.standard]
  /// outside a toolbar and [CLSelectVariant.ghost] inside one.
  final CLSelectVariant variant;
  final bool _usesDefaultVariant;

  /// Configured size, defaulting to large outside a toolbar.
  CLControlSize? get size => _sizeOverride;
  final CLControlSize? _sizeOverride;

  final double? width;

  /// Alignment of the trigger label text.
  ///
  /// Defaults to [TextAlign.right] for [CLSelectVariant.ghost] and
  /// [TextAlign.left] for [CLSelectVariant.standard].
  final TextAlign? textAlign;

  /// Whether the selected option is centered over the trigger when opened.
  ///
  /// When false, the panel opens below the trigger, or above it when there is
  /// not enough room below.
  final bool alignSelectedOption;

  /// Overrides the trigger's corner radius. Pass [BorderRadius.zero] when
  /// the field is a cell of a grouped grid whose outer clip owns the corner
  /// rounding; null keeps the standalone control radius. The options panel
  /// is unaffected.
  final BorderRadius? borderRadius;

  const CLSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    CLSelectVariant? variant,
    CLControlSize? size,
    this.width,
    this.textAlign,
    this.alignSelectedOption = true,
    this.borderRadius,
  }) : variant = variant ?? CLSelectVariant.standard,
       _usesDefaultVariant = variant == null,
       _sizeOverride = size,
       assert(options.length > 0);

  @override
  State<CLSelect<T>> createState() => _CLSelectState<T>();
}

class _CLSelectState<T> extends State<CLSelect<T>>
    with TickerProviderStateMixin {
  static const _openTravelSpring = SpringDescription(
    mass: 1,
    stiffness: 700,
    damping: 30,
  );
  static const _openMorphDuration = Duration(milliseconds: 240);
  static const _closeTravelSpring = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 28,
  );
  static const _closeMorphDuration = Duration(milliseconds: 160);
  static const double _panelPadding = 6;
  static const double _panelHorizontalPadding = 6;
  static const double _panelOutlineWidth = 1;
  static const double _screenMargin = 8;
  static const double _fieldGap = 4;

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  late final AnimationController _travel;
  late final AnimationController _morph;
  late final AnimationController _content;

  bool _open = false;
  bool _closing = false;
  bool _hovered = false;
  bool _disableAnimations = false;
  int _closeGeneration = 0;
  ScrollController? _scrollController;
  Size _openTriggerSize = Size.zero;
  Offset _openTriggerOrigin = Offset.zero;
  Size _targetClosingTriggerSize = Size.zero;
  Offset _targetClosingTriggerOrigin = Offset.zero;
  Offset _globalPanelOrigin = Offset.zero;
  double _panelWidth = 0;
  double _panelHeight = 0;

  double get _travelUnit => _travel.value.clamp(0.0, 1.0).toDouble();

  double get _morphProgress => _morph.value.clamp(0.0, 1.0).toDouble();

  double _springVelocity(AnimationController controller) =>
      controller.velocity.clamp(-3.0, 3.0).toDouble();

  Offset _travelCenter(Offset start, Offset end) =>
      Offset.lerp(start, end, _travel.value)!;

  Offset get _panelTravelDelta {
    final targetSize = _closing ? _targetClosingTriggerSize : _openTriggerSize;
    final targetOrigin = _closing
        ? _targetClosingTriggerOrigin
        : _openTriggerOrigin;
    return (_globalPanelOrigin + Offset(_panelWidth / 2, _panelHeight / 2)) -
        (targetOrigin + Offset(targetSize.width / 2, targetSize.height / 2));
  }

  Offset get _triggerRecoilOffset => _travel.value < 0
      ? _travelCenter(Offset.zero, _panelTravelDelta)
      : Offset.zero;

  @override
  void initState() {
    super.initState();
    _travel = AnimationController.unbounded(vsync: this)
      ..addListener(_handleMotionTick);
    _morph = AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
    )..addListener(_handleMotionTick);
    _content = AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations == disableAnimations) return;
    _disableAnimations = disableAnimations;
    if (disableAnimations) {
      _snapReducedMotionGeometry();
    } else if (_closing) {
      _closeGeneration++;
      _startNormalCloseAnimation();
    }
  }

  void _snapReducedMotionGeometry() {
    _travel.stop();
    _morph.stop();
    if (_open) {
      _travel.value = 1;
      _morph.value = 1;
      _animateReducedContent(1);
    } else if (_closing) {
      _startReducedCloseAnimation(_closeGeneration);
    }
  }

  TickerFuture _animateReducedContent(double target) => _content.animateTo(
    target,
    duration: CLMotion.reducedFade,
    curve: CLMotion.easeOut,
  );

  void _startReducedCloseAnimation(int closeGeneration) {
    _travel.stop();
    _morph.stop();
    _travel.value = 1;
    _morph.value = 1;
    _animateReducedContent(0).whenCompleteOrCancel(() {
      if (!mounted || !_closing || closeGeneration != _closeGeneration) return;
      _finishClose();
    });
  }

  void _startNormalCloseAnimation() {
    _travel.animateWith(
      SpringSimulation(
        _closeTravelSpring,
        _travel.value,
        0,
        _springVelocity(_travel),
        tolerance: Tolerance.defaultTolerance,
      ),
    );
    _animateMorphTo(
      0,
      baseDuration: _closeMorphDuration,
      curve: Curves.easeOutCubic,
    );
    _content.animateTo(0, duration: CLMotion.fast, curve: Curves.easeOut);
  }

  void _startOpenAnimation() {
    if (_disableAnimations) {
      _travel.stop();
      _morph.stop();
      _travel.value = 1;
      _morph.value = 1;
      _animateReducedContent(1);
      return;
    }

    _travel
        .animateWith(
          SpringSimulation(
            _openTravelSpring,
            _travel.value,
            1,
            _springVelocity(_travel),
            tolerance: Tolerance.defaultTolerance,
          ),
        )
        .whenCompleteOrCancel(() => _settleOpenGeometry(_travel));
    _animateMorphTo(
      1,
      baseDuration: _openMorphDuration,
      curve: Curves.easeInOutCubic,
    );
    _content.animateTo(
      1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _animateMorphTo(
    double target, {
    required Duration baseDuration,
    required Curve curve,
  }) {
    final distance = (target - _morph.value).abs().clamp(0.0, 1.0);
    if (distance <= 0.001) {
      _morph.value = target;
      return;
    }
    _morph.animateTo(
      target,
      duration: Duration(
        microseconds: math.max(
          1,
          (baseDuration.inMicroseconds * distance).round(),
        ),
      ),
      curve: curve,
    );
  }

  void _settleOpenGeometry(AnimationController controller) {
    if (!mounted || !_open || _disableAnimations || controller.isAnimating) {
      return;
    }
    controller.value = 1;
  }

  void _handleMotionTick() {
    if (_closing &&
        _travel.value <= 0.001 &&
        _morph.value <= 0.001 &&
        !_travel.isAnimating &&
        !_morph.isAnimating) {
      _finishClose();
    }
  }

  void _finishClose() {
    if (!_closing) return;
    if (mounted) {
      setState(() => _closing = false);
    } else {
      _closing = false;
    }
    _travel.value = 0;
    _morph.value = 0;
    if (_portal.isShowing) _portal.hide();
    _scrollController?.dispose();
    _scrollController = null;
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    _travel.removeListener(_handleMotionTick);
    _travel.dispose();
    _morph.removeListener(_handleMotionTick);
    _morph.dispose();
    _content.dispose();
    super.dispose();
  }

  CLControlSize get _size =>
      widget._sizeOverride ??
      CLToolbarScope.maybeOf(context)?.size ??
      CLControlSize.large;

  double get _height => _size.controlHeight;

  double get _rowHeight => _height;

  bool get _enabled => widget.onChanged != null;

  double _calculateTriggerWidth(CLSelectOption<T> option) {
    if (widget.width != null) return widget.width!;
    final theme = CLTheme.of(context);
    final textStyle = (_size == CLControlSize.large
        ? theme.typography.body
        : theme.typography.callout);
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final painter = TextPainter(
      text: TextSpan(text: option.label, style: textStyle),
      maxLines: 1,
      textDirection: textDirection,
    )..layout();
    final horizontalPadding = (_size == CLControlSize.small ? 10 : 12) * 2;
    const chevronsWidth = 8.0;
    const gap = 6.0;
    return painter.width +
        chevronsWidth +
        gap +
        horizontalPadding +
        (option.leading == null ? 0 : _kLeadingAllowance);
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openPanel();
    }
  }

  void _openPanel() {
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final fieldBox = context.findRenderObject()! as RenderBox;
    final origin = fieldBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final mediaPadding = MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero;
    final safeLeft = mediaPadding.left + _screenMargin;
    final safeTop = mediaPadding.top + _screenMargin;
    final safeRight =
        overlayBox.size.width - mediaPadding.right - _screenMargin;
    final safeBottom =
        overlayBox.size.height - mediaPadding.bottom - _screenMargin;
    final availableWidth = math.max(0.0, safeRight - safeLeft);
    final availableHeight = math.max(0.0, safeBottom - safeTop);
    final listContentHeight =
        widget.options.length * _rowHeight + _panelPadding * 2;
    final panelContentHeight = listContentHeight + _panelOutlineWidth * 2;
    final selectedIndex = widget.options.indexWhere(
      (option) => option.value == widget.value,
    );
    final fieldCenterY = origin.dy + fieldBox.size.height / 2;
    final theme = CLTheme.of(context);

    double maxOptionWidth = 0;
    final calloutStyle = theme.typography.callout.copyWith(
      fontWeight: FontWeight.w500,
    );
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    for (final option in widget.options) {
      final painter = TextPainter(
        text: TextSpan(text: option.label, style: calloutStyle),
        maxLines: 1,
        textDirection: textDirection,
      )..layout();
      if (painter.width > maxOptionWidth) {
        maxOptionWidth = painter.width;
      }
    }

    final minPanelWidth =
        fieldBox.size.width +
        _panelHorizontalPadding * 2 +
        _panelOutlineWidth * 2;
    final naturalPanelWidth =
        maxOptionWidth +
        40 +
        (widget.options.any((option) => option.leading != null)
            ? _kLeadingAllowance
            : 0) +
        _panelHorizontalPadding * 2 +
        _panelOutlineWidth * 2;

    _panelWidth = math.min(
      math.max(minPanelWidth, naturalPanelWidth),
      availableWidth,
    );

    final inToolbar = CLToolbarScope.maybeOf(context) != null;
    final effectiveVariant = widget._usesDefaultVariant && inToolbar
        ? CLSelectVariant.ghost
        : widget.variant;
    final effectiveTextAlign =
        widget.textAlign ??
        (effectiveVariant == CLSelectVariant.ghost
            ? TextAlign.right
            : TextAlign.left);

    final desiredPanelLeft = effectiveTextAlign == TextAlign.right
        ? (origin.dx + fieldBox.size.width) -
              _panelWidth +
              _panelHorizontalPadding +
              _panelOutlineWidth
        : origin.dx - _panelHorizontalPadding - _panelOutlineWidth;

    final panelLeft = desiredPanelLeft.clamp(
      safeLeft,
      math.max(safeLeft, safeRight - _panelWidth),
    );

    double panelTop;
    double initialScrollOffset = 0;
    if (widget.alignSelectedOption && selectedIndex >= 0) {
      _panelHeight = math.min(panelContentHeight, availableHeight);
      final selectedPanelCenter =
          _panelOutlineWidth +
          _panelPadding +
          selectedIndex * _rowHeight +
          _rowHeight / 2;
      final desiredTop = fieldCenterY - selectedPanelCenter;
      panelTop = desiredTop.clamp(
        safeTop,
        math.max(safeTop, safeBottom - _panelHeight),
      );
      final listViewportHeight = math.max(
        0.0,
        _panelHeight - _panelOutlineWidth * 2,
      );
      final maxScrollOffset = math.max(
        0.0,
        listContentHeight - listViewportHeight,
      );
      initialScrollOffset = (panelTop + selectedPanelCenter - fieldCenterY)
          .clamp(0.0, maxScrollOffset);
    } else {
      final spaceBelow = math.max(
        0.0,
        safeBottom - (origin.dy + fieldBox.size.height + _fieldGap),
      );
      final spaceAbove = math.max(0.0, origin.dy - _fieldGap - safeTop);
      final dropUp = panelContentHeight > spaceBelow && spaceAbove > spaceBelow;
      _panelHeight = math.min(
        panelContentHeight,
        dropUp ? spaceAbove : spaceBelow,
      );
      panelTop = dropUp
          ? origin.dy - _fieldGap - _panelHeight
          : origin.dy + fieldBox.size.height + _fieldGap;
      panelTop = panelTop.clamp(
        safeTop,
        math.max(safeTop, safeBottom - _panelHeight),
      );
    }

    _scrollController?.dispose();
    setState(() {
      _openTriggerSize = fieldBox.size;
      _openTriggerOrigin = origin;
      _targetClosingTriggerSize = fieldBox.size;
      _targetClosingTriggerOrigin = origin;
      _globalPanelOrigin = Offset(panelLeft.toDouble(), panelTop.toDouble());
      _scrollController = ScrollController(
        initialScrollOffset: initialScrollOffset,
      );
      _open = true;
      _closing = false;
      _closeGeneration++;
    });
    _portal.show();
    _startOpenAnimation();
  }

  void _close() {
    if (!_open) return;
    late final int closeGeneration;
    setState(() {
      _open = false;
      _closing = true;
      closeGeneration = ++_closeGeneration;
    });

    if (_disableAnimations) {
      _startReducedCloseAnimation(closeGeneration);
      return;
    }
    if (_travel.value <= 0.001 &&
        _morph.value <= 0.001 &&
        !_travel.isAnimating &&
        !_morph.isAnimating) {
      _finishClose();
      return;
    }
    _startNormalCloseAnimation();
  }

  void _select(CLSelectOption<T> option) {
    final inToolbar = CLToolbarScope.maybeOf(context) != null;
    final effectiveVariant = widget._usesDefaultVariant && inToolbar
        ? CLSelectVariant.ghost
        : widget.variant;
    final isGhostShrinkWrap =
        effectiveVariant == CLSelectVariant.ghost && widget.width == null;

    if (isGhostShrinkWrap) {
      final newWidth = _calculateTriggerWidth(option);
      final effectiveTextAlign = widget.textAlign ?? TextAlign.right;
      _targetClosingTriggerSize = Size(newWidth, _height);
      if (effectiveTextAlign == TextAlign.right) {
        final rightEdge = _openTriggerOrigin.dx + _openTriggerSize.width;
        _targetClosingTriggerOrigin = Offset(
          rightEdge - newWidth,
          _openTriggerOrigin.dy,
        );
      } else {
        _targetClosingTriggerOrigin = _openTriggerOrigin;
      }
    } else {
      _targetClosingTriggerSize = _openTriggerSize;
      _targetClosingTriggerOrigin = _openTriggerOrigin;
    }

    widget.onChanged?.call(option.value);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    final variant = _effectiveVariant;
    final label = _selectedLabel;
    final radius =
        widget.borderRadius ?? BorderRadius.circular(theme.radii.control);
    final trigger = _buildTrigger(
      theme: theme,
      variant: variant,
      label: label,
      radius: radius,
    );

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: CompositedTransformTarget(
        link: _link,
        child: AnimatedBuilder(
          animation: _travel,
          builder: (context, child) =>
              Transform.translate(offset: _triggerRecoilOffset, child: child),
          child: trigger,
        ),
      ),
    );
  }

  CLSelectVariant get _effectiveVariant {
    final inToolbar = CLToolbarScope.maybeOf(context) != null;
    return widget._usesDefaultVariant && inToolbar
        ? CLSelectVariant.ghost
        : widget.variant;
  }

  CLSelectOption<T>? get _selectedOption {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  String get _selectedLabel => _selectedOption?.label ?? '';

  Widget _buildTrigger({
    required CLThemeData theme,
    required CLSelectVariant variant,
    required String label,
    required BorderRadius radius,
  }) {
    final colors = theme.colors;
    final fill = switch (variant) {
      CLSelectVariant.standard =>
        _hovered && _enabled ? colors.controlHighlight : colors.control,
      CLSelectVariant.ghost =>
        _hovered && _enabled
            ? colors.controlHighlight
            : const Color(0x00000000),
    };
    final surface = SizedBox(
      height: _height,
      child: CLSurface(
        fill: fill,
        borderRadius: radius,
        padding: EdgeInsets.symmetric(
          horizontal: _size == CLControlSize.small ? 10 : 12,
        ),
        child: _buildTriggerContent(theme, variant, label),
      ),
    );
    final triggerBox = SizedBox(
      width: widget.width,
      height: _height,
      child: variant == CLSelectVariant.ghost && widget.width == null
          ? Align(alignment: Alignment.centerRight, child: surface)
          : surface,
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: CLPressable(
          onTap: _enabled ? _toggle : null,
          borderRadius: radius,
          deformOnDrag: false,
          pressedScale: 1.02,
          child: triggerBox,
        ),
      ),
    );
  }

  Widget _buildTriggerContent(
    CLThemeData theme,
    CLSelectVariant variant,
    String label,
  ) {
    final expands = widget.width != null || variant == CLSelectVariant.standard;
    final textAlign =
        widget.textAlign ??
        (variant == CLSelectVariant.ghost ? TextAlign.right : TextAlign.left);
    final textStyle =
        (_size == CLControlSize.large
                ? theme.typography.body
                : theme.typography.callout)
            .copyWith(
              color: _enabled
                  ? theme.colors.textPrimary
                  : theme.colors.textDisabled,
            );
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: textStyle,
    );
    final leading = _selectedOption?.leading;

    return Row(
      mainAxisSize: expands ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (leading != null) ...[
          IconTheme.merge(
            data: IconThemeData(
              color: _enabled
                  ? theme.colors.textPrimary
                  : theme.colors.textDisabled,
            ),
            child: leading,
          ),
          const SizedBox(width: _kLeadingGap),
        ],
        if (expands) Expanded(child: text) else Flexible(child: text),
        const SizedBox(width: 6),
        _Chevrons(color: theme.colors.textTertiary),
      ],
    );
  }

  Offset get _currentPanelOffset {
    final tMorph = _morphProgress;
    final targetSize = _closing ? _targetClosingTriggerSize : _openTriggerSize;
    final targetOrigin = _closing
        ? _targetClosingTriggerOrigin
        : _openTriggerOrigin;
    final width = ui.lerpDouble(targetSize.width, _panelWidth, tMorph)!;
    final height = ui.lerpDouble(targetSize.height, _panelHeight, tMorph)!;
    final startCenter = Offset(targetSize.width / 2, targetSize.height / 2);
    final endCenter =
        (_globalPanelOrigin - targetOrigin) +
        Offset(_panelWidth / 2, _panelHeight / 2);
    final center = _travelCenter(startCenter, endCenter);
    return center - Offset(width / 2, height / 2);
  }

  Widget _buildOverlay(BuildContext context) {
    final theme = CLTheme.of(context);

    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: _open
                ? HitTestBehavior.opaque
                : HitTestBehavior.translucent,
            onPointerDown: (_) => _close(),
          ),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([_travel, _morph, _content]),
          child: CLList.builder(
            controller: _scrollController,
            itemCount: widget.options.length,
            itemExtent: _rowHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: _panelHorizontalPadding,
              vertical: _panelPadding,
            ),
            blurExtent: const EdgeInsets.symmetric(vertical: 16),
            borderRadius: BorderRadius.circular(theme.radii.medium),
            itemBuilder: (context, index) {
              final option = widget.options[index];
              return _OptionRow<T>(
                option: option,
                checked: option.value == widget.value,
                height: _rowHeight,
                onTap: () => _select(option),
              );
            },
          ),
          builder: (context, child) => CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.topLeft,
            offset: _currentPanelOffset,
            child: _buildPanel(child!),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(Widget list) {
    final theme = CLTheme.of(context);
    final tTravel = _travelUnit;
    final tMorph = _morphProgress;
    if (tTravel <= 0.001 && tMorph <= 0.001 && !_open) {
      return const SizedBox.shrink();
    }

    final targetSize = _closing ? _targetClosingTriggerSize : _openTriggerSize;
    final width = ui.lerpDouble(targetSize.width, _panelWidth, tMorph)!;
    final height = ui.lerpDouble(targetSize.height, _panelHeight, tMorph)!;
    final triggerRadius =
        widget.borderRadius ?? BorderRadius.circular(theme.radii.control);
    final panelRadius = BorderRadius.circular(theme.radii.medium);
    final borderRadius = BorderRadius.lerp(
      triggerRadius,
      panelRadius,
      tMorph.clamp(0.0, 1.0),
    )!;
    final reveal = _content.value;
    final contentOpacity = _disableAnimations
        ? 1.0
        : math.pow(reveal, 0.6).toDouble();
    final shadowStrength = tMorph.clamp(0.0, 1.0);
    final presence =
        (_disableAnimations
                ? reveal.clamp(0.0, 1.0)
                : (math.max(tTravel, tMorph) * 5).clamp(0.0, 1.0))
            .toDouble();
    final targetContentSize = Size(
      math.max(0, _panelWidth - _panelOutlineWidth * 2),
      math.max(0, _panelHeight - _panelOutlineWidth * 2),
    );

    final matrix = _computeSelectMorphMatrix(width, height);

    return IgnorePointer(
      ignoring: !_open,
      child: ExcludeSemantics(
        excluding: !_open,
        child: Opacity(
          opacity: presence,
          child: SizedBox(
            width: width,
            height: height,
            child: Transform(
              transform: matrix,
              child: CLSurface(
                frosted: true,
                borderRadius: borderRadius,
                outlined: true,
                shadow: [
                  BoxShadow(
                    color: Color.fromARGB(
                      (0x59 * shadowStrength).round(),
                      0,
                      0,
                      0,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
                child: Opacity(
                  opacity: contentOpacity.clamp(0.0, 1.0).toDouble(),
                  child: Flow(
                    delegate: _CLSelectContentFlowDelegate(
                      targetSize: targetContentSize,
                    ),
                    children: [list],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Matrix4 _computeSelectMorphMatrix(double width, double height) {
    final tMorph = _morphProgress;
    if (tMorph <= 0.001 || tMorph >= 0.999) return Matrix4.identity();

    final clampedProgress = tMorph.clamp(0.0, 1.0);
    final factor = math.sin(clampedProgress * math.pi);

    final skewX = 0.00003 * factor * (width > 120 ? 1.0 : -1.0);
    final skewY = 0.00004 * factor;

    return Matrix4.identity()
      ..setEntry(3, 0, skewX)
      ..setEntry(3, 1, skewY);
  }
}

class _CLSelectContentFlowDelegate extends FlowDelegate {
  const _CLSelectContentFlowDelegate({required this.targetSize});

  final Size targetSize;

  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tight(targetSize);

  @override
  void paintChildren(FlowPaintingContext context) {
    final childSize = context.getChildSize(0);
    if (childSize == null) return;

    final offset = Offset(
      (context.size.width - childSize.width) / 2,
      (context.size.height - childSize.height) / 2,
    );
    final transform = Matrix4.identity()
      ..translateByDouble(offset.dx, offset.dy, 0, 1);
    context.paintChild(0, transform: transform);
  }

  @override
  bool shouldRelayout(_CLSelectContentFlowDelegate oldDelegate) =>
      targetSize != oldDelegate.targetSize;

  @override
  bool shouldRepaint(_CLSelectContentFlowDelegate oldDelegate) => false;
}

class _OptionRow<T> extends StatefulWidget {
  final CLSelectOption<T> option;
  final bool checked;
  final double height;
  final VoidCallback onTap;

  const _OptionRow({
    required this.option,
    required this.checked,
    required this.height,
    required this.onTap,
  });

  @override
  State<_OptionRow<T>> createState() => _OptionRowState<T>();
}

class _OptionRowState<T> extends State<_OptionRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    final colors = theme.colors;
    final rowColor = widget.checked
        ? (_hovered
              ? Color.alphaBlend(colors.control, colors.accentBackground)
              : colors.accentBackground)
        : (_hovered ? colors.control : const Color(0x00000000));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: clSmoothDecoration(
            color: rowColor,
            borderRadius: BorderRadius.circular(theme.radii.control - 2),
          ),
          child: _buildContent(theme),
        ),
      ),
    );
  }

  Widget _buildContent(CLThemeData theme) {
    final color = widget.checked
        ? theme.colors.accent
        : theme.colors.textPrimary;
    final leading = widget.option.leading;
    return Row(
      children: [
        if (leading != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: color),
            child: leading,
          ),
          const SizedBox(width: _kLeadingGap),
        ],
        Expanded(
          child: Text(
            widget.option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: theme.typography.callout.copyWith(
              color: color,
              fontWeight: widget.checked ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
        if (widget.checked) ...[
          const SizedBox(width: 8),
          CustomPaint(
            size: const Size(12, 10),
            painter: _CheckPainter(color: color),
          ),
        ],
      ],
    );
  }
}

class _CheckPainter extends CustomPainter {
  final Color color;

  const _CheckPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.05, size.height * 0.55)
        ..lineTo(size.width * 0.38, size.height * 0.9)
        ..lineTo(size.width * 0.95, size.height * 0.1),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => color != oldDelegate.color;
}

/// The stacked up/down chevrons of the mockup's dropdown fields.
class _Chevrons extends StatelessWidget {
  final Color color;

  const _Chevrons({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(9, 14),
      painter: _ChevronsPainter(color: color),
    );
  }
}

class _ChevronsPainter extends CustomPainter {
  final Color color;

  const _ChevronsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.15, h * 0.36)
        ..lineTo(w * 0.5, h * 0.08)
        ..lineTo(w * 0.85, h * 0.36),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.15, h * 0.64)
        ..lineTo(w * 0.5, h * 0.92)
        ..lineTo(w * 0.85, h * 0.64),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ChevronsPainter oldDelegate) =>
      color != oldDelegate.color;
}
