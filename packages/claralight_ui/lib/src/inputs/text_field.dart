import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show SemanticsValidationResult;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../foundation/haptics.dart';
import '../foundation/numeric_text.dart';
import '../foundation/control_size.dart';
import '../foundation/shape.dart';
import '../overlays/anchored_overlay.dart';
import '../theme/theme.dart';
import 'numeric_scrub_cursor.dart';

/// The screen direction in which a numeric field's value increases.
///
/// The default preserves conventional numeric steppers: up increases and down
/// decreases. Positional fields can use [right] for X and [down] for Y so the
/// controls move an element in the direction shown by their chevrons.
enum CLNumericStepperDirection { up, down, left, right }

/// A Claralight text field — the inspector inputs of the desktop mockup
/// ("X 12px", "W 78") and the touch fields of the mobile mockup.
///
/// A flat control-fill rounded rectangle with an optional [prefix] label
/// (dimmed, e.g. the axis letter), an optional [suffix] (unit or actions)
/// and an animated accent focus ring.
///
/// Numeric fields with a non-zero [step] can be scrubbed horizontally from the
/// prefix or arrow strip. Vertical movement changes ruler spacing and therefore
/// precision; every tick crossing the center commits exactly one step. Finite
/// [min] and [max] bounds truncate unreachable ruler ticks.
class CLTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;

  /// Leading widget or short label, rendered dimmed (e.g. "X", an icon).
  final Widget? prefix;

  /// Trailing widget (e.g. a unit label or clear button).
  final Widget? suffix;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Called once when a completed user interaction changes the value.
  ///
  /// A scrub, held step button, keyboard repeat, or wheel sequence is one
  /// interaction. Direct text editing commits on submit or focus loss.
  final ValueChanged<String>? onCommit;

  /// Called when an in-progress interaction is canceled. The value is the
  /// text restored by the field.
  final ValueChanged<String>? onCancel;

  final TextInputType? keyboardType;

  /// Optional formatters applied to user-entered text.
  final List<TextInputFormatter>? inputFormatters;

  /// Whether this field should focus itself when first built.
  final bool autofocus;

  final bool enabled;

  /// Prevents editing without applying disabled-state colors.
  final bool readOnly;

  /// Whether to render the field with error-state colors.
  ///
  /// Numeric validation errors are combined with this external state.
  final bool error;

  final bool obscureText;
  final TextAlign textAlign;
  final CLControlSize size;

  /// The numeric increment used by buttons, dragging, scrolling, and keys.
  ///
  /// A value of zero disables numeric adjustment and hides the step buttons.
  /// This only applies when [keyboardType] is numeric.
  final double step;

  /// Direction in which stepping increases the value.
  final CLNumericStepperDirection stepperDirection;

  /// Optional inclusive bounds for numeric input.
  final double? min;
  final double? max;

  /// Formats values produced by stepping. The result must remain parseable as
  /// a [double] so it can be edited and stepped again.
  final String Function(double value)? format;

  /// Whether mouse-based numeric scrubbing wraps the system cursor across the
  /// desktop window and restores it to its pointer-down position on release.
  ///
  /// Unsupported desktop environments silently keep finite cursor movement.
  final bool wrapNumericScrubCursor;

  /// Renders the value in the monospace family — for numeric fields like
  /// the design's "X 12px" inspector inputs.
  final bool mono;

  /// Corner radius override; null uses the theme's control radius. Use a
  /// larger value inside large-radius containers so the corners stay
  /// optically concentric.
  final double? borderRadius;

  /// Per-corner radius override for controls joined inside a group.
  /// Takes precedence over [borderRadius].
  final BorderRadiusGeometry? borderRadiusGeometry;

  /// Fixed width; null fills the parent.
  final double? width;

  const CLTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.onCommit,
    this.onCancel,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.error = false,
    this.obscureText = false,
    this.textAlign = TextAlign.start,
    this.size = CLControlSize.large,
    this.step = 0,
    this.stepperDirection = CLNumericStepperDirection.up,
    this.min,
    this.max,
    this.format,
    this.wrapNumericScrubCursor = true,
    this.mono = false,
    this.borderRadius,
    this.borderRadiusGeometry,
    this.width,
  }) : assert(step >= 0 && step < double.infinity),
       assert(
         min == null ||
             (min > double.negativeInfinity && min < double.infinity),
       ),
       assert(
         max == null ||
             (max > double.negativeInfinity && max < double.infinity),
       ),
       assert(min == null || max == null || min <= max);

  @override
  State<CLTextField> createState() => _CLTextFieldState();
}

class _CLTextFieldState extends State<CLTextField>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocusNode;
  final FocusNode _operationFocusNode = FocusNode(
    debugLabel: 'CLTextField numeric operation focus',
  );
  final OverlayPortalController _scrubPortal = OverlayPortalController();
  final GlobalKey _scrubAnchorKey = GlobalKey();
  late final AnimationController _scrubReveal;
  late final AnimationController _rulerSpacingTransition;
  late final NumericScrubCursorSession _scrubCursorSession;

  int? _scrubMouseDevice;
  bool _showValidationError = false;
  bool _operationFocusRequested = false;
  bool _lifecycleSuspended = false;
  bool _disableAnimations = false;
  bool _scrubGestureActive = false;
  bool _scrubVisualMounted = false;
  bool _hapticSentThisFrame = false;
  double _scrubDy = 0;
  int _scrubTier = 0;
  double _scrubProgress = 0;
  double _scrubMultiplier = 1;
  double _rulerSpacingFrom = _NumericScrubMetrics.baseSpacing;
  double _rulerSpacingTarget = _NumericScrubMetrics.baseSpacing;
  String? _textEditingStartText;
  String? _numericInteractionStartText;
  bool _textEditingChanged = false;
  bool _numericInteractionChanged = false;
  LogicalKeyboardKey? _activeStepKey;
  Timer? _scrollCommitTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrubCursorSession = NumericScrubCursorSession();
    _scrubReveal = AnimationController(
      vsync: this,
      duration: CLMotion.fast,
      reverseDuration: const Duration(milliseconds: 110),
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_handleScrubRevealStatus);
    _rulerSpacingTransition = AnimationController(
      vsync: this,
      duration: _NumericScrubMetrics.spacingTransitionDuration,
      value: 1,
      animationBehavior: AnimationBehavior.preserve,
    );
    _operationFocusNode.addListener(_onOperationFocusChanged);
    _adoptController();
    _adoptFocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations && !_disableAnimations) {
      _rulerSpacingFrom = _rulerSpacingTarget;
      _rulerSpacingTransition.value = 1;
    }
    _disableAnimations = disableAnimations;
  }

  @override
  void didUpdateWidget(CLTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _ownedController?.dispose();
      _adoptController();
    }
    if (widget.focusNode != oldWidget.focusNode) {
      final oldFocusNode = oldWidget.focusNode ?? _ownedFocusNode!;
      oldFocusNode.removeListener(_onFocusChanged);
      _ownedFocusNode?.dispose();
      _adoptFocusNode();
    }
    if (oldWidget.wrapNumericScrubCursor && !widget.wrapNumericScrubCursor) {
      _scrubCursorSession.finish();
    }
    if ((!widget.enabled || !_showsStepper || _number == null) &&
        (_scrubGestureActive || _scrubVisualMounted)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeScrub(immediate: true);
      });
    }
  }

  TextEditingController get _controller =>
      widget.controller ?? _ownedController!;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  void _adoptController() {
    _ownedController = widget.controller == null
        ? TextEditingController()
        : null;
  }

  void _adoptFocusNode() {
    _ownedFocusNode = widget.focusNode == null ? FocusNode() : null;
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (_textEditingStartText == null) {
        setState(() {
          _textEditingStartText = _controller.text;
          _textEditingChanged = false;
        });
      }
      return;
    }

    if (_numericInteractionStartText != null) {
      _cancelNumericInteraction();
    }
    if (_isNumeric && !_isValidNumber) {
      setState(() => _showValidationError = true);
      _cancelTextEditing();
    } else {
      _commitTextEditing();
    }
    _closeScrub(immediate: true);
  }

  void _onOperationFocusChanged() {
    if (!_operationFocusNode.hasPrimaryFocus && _operationFocusRequested) {
      setState(() => _operationFocusRequested = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lifecycleSuspended = false;
      return;
    }
    if (_lifecycleSuspended) return;
    _lifecycleSuspended = true;
    _scrollCommitTimer?.cancel();
    _scrollCommitTimer = null;
    final canceledNumericInteraction = _numericInteractionStartText != null;
    _cancelNumericInteraction();
    if (!canceledNumericInteraction) _cancelTextEditing();
    _closeScrub(immediate: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCommitTimer?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    if (_numericInteractionStartText != null) {
      _cancelNumericInteraction();
    } else if (_textEditingStartText != null &&
        (_textEditingChanged || _textEditingStartText != _controller.text)) {
      _cancelTextEditing();
    } else {
      _textEditingStartText = null;
    }
    _scrubCursorSession.finish();
    _scrubReveal.dispose();
    _rulerSpacingTransition.dispose();
    _operationFocusNode.removeListener(_onOperationFocusChanged);
    _operationFocusNode.dispose();
    _ownedController?.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  double get _height => widget.size.controlHeight;

  bool get _isNumeric =>
      widget.keyboardType?.index == TextInputType.number.index;

  /// The stepper keeps its geometry while [readOnly] so disabling a numeric
  /// field never reflows the control; readOnly steppers render gray and
  /// inert ([_canStep] rejects them).
  bool get _showsStepper => _isNumeric && widget.step > 0;

  double? get _number {
    final value = double.tryParse(_controller.text.trim());
    return value != null && value.isFinite ? value : null;
  }

  bool get _isValidNumber {
    final value = _number;
    if (value == null) return false;
    if (widget.min case final min? when value < min) return false;
    if (widget.max case final max? when value > max) return false;
    return true;
  }

  bool get _showsError =>
      widget.enabled &&
      (widget.error || (_isNumeric && _showValidationError && !_isValidNumber));

  bool _canStep(double direction) {
    if (!widget.enabled || widget.readOnly || !_showsStepper) return false;
    final value = _number;
    if (value == null) return false;
    final min = widget.min;
    final max = widget.max;
    if (direction > 0 && max != null && value >= max) return false;
    if (direction < 0 && min != null && value <= min) return false;
    return true;
  }

  String? _semanticSteppedValue(double direction) {
    if (!_canStep(direction)) return null;
    final stepped = _number! + direction * widget.step;
    if (!stepped.isFinite) return null;
    final next = _clampNumber(stepped);
    return widget.format?.call(next) ?? _defaultNumberFormat(next);
  }

  bool _bump(double direction) => _bumpSteps(direction > 0 ? 1 : -1);

  bool _bumpSteps(int steps) {
    if (steps == 0) return false;
    final direction = steps.sign.toDouble();
    if (!_canStep(direction)) return false;

    final current = _number!;
    var next = current + direction * widget.step;
    if (!next.isFinite) return false;
    next = _clampNumber(next);

    final remaining = steps.abs() - 1;
    if (remaining > 0) {
      next += direction * widget.step * remaining;
      if (!next.isFinite) return false;
      next = _clampNumber(next);
    }

    final text = widget.format?.call(next) ?? _defaultNumberFormat(next);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _numericInteractionChanged = true;
    widget.onChanged?.call(text);
    return true;
  }

  void _beginNumericInteraction() {
    if (_numericInteractionStartText == null) {
      _numericInteractionStartText = _controller.text;
      _numericInteractionChanged = false;
    }
  }

  void _commitNumericInteraction() {
    final start = _numericInteractionStartText;
    final changed = _numericInteractionChanged;
    _numericInteractionStartText = null;
    _numericInteractionChanged = false;
    _activeStepKey = null;
    if (start == null) return;
    if (start == _controller.text) {
      if (changed) widget.onCancel?.call(start);
      return;
    }
    _textEditingStartText = _controller.text;
    _textEditingChanged = false;
    widget.onCommit?.call(_controller.text);
  }

  void _cancelNumericInteraction() {
    final start = _numericInteractionStartText;
    _numericInteractionStartText = null;
    _numericInteractionChanged = false;
    _activeStepKey = null;
    if (start == null) return;
    _restoreText(start);
    _textEditingStartText = start;
    _textEditingChanged = false;
    widget.onCancel?.call(start);
  }

  void _commitTextEditing() {
    final start = _textEditingStartText;
    final changed = _textEditingChanged;
    _textEditingStartText = null;
    _textEditingChanged = false;
    if (start == null) return;
    if (start == _controller.text) {
      if (changed) widget.onCancel?.call(start);
      return;
    }
    widget.onCommit?.call(_controller.text);
  }

  void _cancelTextEditing() {
    final start = _textEditingStartText;
    _textEditingStartText = null;
    _textEditingChanged = false;
    if (start == null) return;
    _restoreText(start);
    widget.onCancel?.call(start);
  }

  void _restoreText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _requestEditingFocus() {
    _operationFocusRequested = false;
    // Always request focus first: it wins any pending deferred unfocus (e.g.
    // the Done action's _finalizeEditing) and is a no-op when already focused.
    _focusNode.requestFocus();
    if (_focusNode.hasPrimaryFocus) {
      // The platform can dismiss the IME while this node keeps focus (Android
      // back button, Done action, iOS swipe-down). requestFocus() alone cannot
      // re-attach the soft keyboard, so explicitly re-open it.
      _requestKeyboard();
    }
  }

  /// Re-attaches the soft keyboard when the field already owns primary focus.
  void _requestKeyboard() {
    _focusNode.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.requestKeyboard();
  }

  void _requestOperationFocus() {
    _operationFocusRequested = true;
    _operationFocusNode.requestFocus();
  }

  bool _handlePointerStep(int steps) {
    _beginNumericInteraction();
    final changed = _bumpSteps(steps);
    if (changed) _emitPointerHaptic();
    return changed;
  }

  void _emitPointerHaptic() {
    if (_hapticSentThisFrame) return;
    _hapticSentThisFrame = true;
    unawaited(clSelectionHaptic());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hapticSentThisFrame = false;
    });
  }

  double get _currentRulerSpacing {
    final progress = Curves.easeOutCubic.transform(
      _rulerSpacingTransition.value,
    );
    return _rulerSpacingFrom +
        (_rulerSpacingTarget - _rulerSpacingFrom) * progress;
  }

  void _resetRulerSpacing() {
    _rulerSpacingTransition.stop();
    _rulerSpacingFrom = _NumericScrubMetrics.baseSpacing;
    _rulerSpacingTarget = _NumericScrubMetrics.baseSpacing;
    _rulerSpacingTransition.value = 1;
  }

  void _transitionRulerSpacing(double multiplier) {
    if (multiplier == _scrubMultiplier) return;
    final current = _currentRulerSpacing;
    _rulerSpacingTransition.stop();
    _rulerSpacingFrom = current;
    _rulerSpacingTarget = _NumericScrubMetrics.baseSpacing / multiplier;
    if (_disableAnimations) {
      _rulerSpacingTransition.value = 1;
    } else {
      _rulerSpacingTransition.forward(from: 0);
    }
    _scrubMultiplier = multiplier;
  }

  void _prepareScrubCursor(PointerDownEvent event) {
    final isMouse = event.kind == PointerDeviceKind.mouse;
    _scrubMouseDevice = isMouse ? event.device : null;
    _scrubCursorSession.prepare(
      enabled: widget.wrapNumericScrubCursor && isMouse,
      position: event.position,
    );
  }

  void _keepScrubMouseCursor() {
    final device = _scrubMouseDevice;
    if (device == null) return;

    void activate() {
      unawaited(
        SystemChannels.mouseCursor.invokeMethod<void>('activateSystemCursor', {
          'device': device,
          'kind': SystemMouseCursors.resizeLeftRight.kind,
        }),
      );
    }

    activate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrubGestureActive && _scrubMouseDevice == device) {
        activate();
      }
    });
  }

  bool _beginScrub(PointerDeviceKind kind) {
    if (_scrubGestureActive || !_canAdjustNumber) return false;

    _beginNumericInteraction();
    _scrubCursorSession.activate(
      enabled: widget.wrapNumericScrubCursor && kind == PointerDeviceKind.mouse,
    );
    if (kind == PointerDeviceKind.touch) {
      _requestOperationFocus();
    } else {
      _requestEditingFocus();
    }

    setState(() {
      _scrubGestureActive = true;
      _scrubVisualMounted = true;
      _scrubDy = 0;
      _scrubTier = 0;
      _scrubProgress = 0;
      _scrubMultiplier = 1;
      _resetRulerSpacing();
    });

    if (!_scrubPortal.isShowing) _scrubPortal.show();
    _keepScrubMouseCursor();
    _animateScrubReveal(show: true);
    return true;
  }

  void _updateScrub(_NumericScrubUpdate update) {
    if (!_scrubGestureActive) return;

    final corrected = _scrubCursorSession.correctUpdate(
      delta: update.delta,
      position: update.position,
    );
    final delta = corrected.delta;
    setState(() {
      _scrubDy += delta.dy;
      _transitionRulerSpacing(_updateScrubMultiplierForDy(_scrubDy));
      _applyHorizontalScrub(delta.dx);
    });

    _scrubCursorSession.maybeWrap(
      position: corrected.position,
      horizontalDirection: corrected.canWrap ? delta.dx : 0,
      viewSize: update.viewSize,
      devicePixelRatio: update.devicePixelRatio,
      canIncrease: _canStep(1),
      canDecrease: _canStep(-1),
    );
    _keepScrubMouseCursor();
  }

  void _applyHorizontalScrub(double deltaX) {
    if (deltaX == 0) return;
    final direction = deltaX.sign;
    if (!_canStep(direction)) {
      _scrubProgress = 0;
      return;
    }

    final combined = _scrubProgress + deltaX / _currentRulerSpacing;
    final steps = combined.truncate();
    if (steps == 0) {
      _scrubProgress = combined;
    } else if (_handlePointerStep(steps)) {
      _scrubProgress = combined - steps;
      if (!_canStep(steps.sign.toDouble())) _scrubProgress = 0;
    } else {
      _scrubProgress = 0;
    }
  }

  void _endScrub() {
    if (!_scrubGestureActive) return;
    _scrubCursorSession.finish();
    setState(() {
      _scrubMouseDevice = null;
      _scrubGestureActive = false;
      _scrubProgress = 0;
      _scrubDy = 0;
      _scrubTier = 0;
    });
    _animateScrubReveal(show: false);
  }

  void _closeScrub({required bool immediate}) {
    if (!_scrubGestureActive && !_scrubVisualMounted) return;
    _scrubCursorSession.finish();
    setState(() {
      _scrubMouseDevice = null;
      _scrubGestureActive = false;
      _scrubProgress = 0;
      _scrubDy = 0;
      _scrubTier = 0;
      if (immediate) {
        _scrubMultiplier = 1;
        _resetRulerSpacing();
        _scrubVisualMounted = false;
      }
    });

    if (!immediate) {
      _animateScrubReveal(show: false);
      return;
    }

    _scrubReveal.stop();
    _scrubReveal.value = 0;
    if (_scrubPortal.isShowing) _scrubPortal.hide();
  }

  void _handleScrubRevealStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || _scrubGestureActive) return;
    if (_scrubPortal.isShowing) _scrubPortal.hide();
    if (!_scrubVisualMounted) return;
    _scrubMultiplier = 1;
    _resetRulerSpacing();
    if (mounted) setState(() => _scrubVisualMounted = false);
  }

  TickerFuture _animateScrubReveal({required bool show}) {
    if (_disableAnimations) {
      return show
          ? _scrubReveal.animateTo(1, duration: CLMotion.reducedFade)
          : _scrubReveal.animateBack(0, duration: CLMotion.reducedFade);
    }
    return show ? _scrubReveal.forward() : _scrubReveal.reverse();
  }

  bool get _canAdjustNumber => _canStep(1) || _canStep(-1);

  ({int? increase, int? decrease}) get _scrubTickCounts {
    final value = _number;
    if (value == null || !_isValidNumber) {
      return (increase: null, decrease: null);
    }
    return (
      increase: _stepsToBoundary(widget.max, value, increasing: true),
      decrease: _stepsToBoundary(widget.min, value, increasing: false),
    );
  }

  int? _stepsToBoundary(
    double? boundary,
    double value, {
    required bool increasing,
  }) {
    if (boundary == null || !boundary.isFinite || !widget.step.isFinite) {
      return null;
    }
    final distance = increasing ? boundary - value : value - boundary;
    if (distance <= 0) return 0;

    final ratio = distance / widget.step;
    if (!ratio.isFinite) return null;
    final nearest = ratio.roundToDouble();
    final tolerance = 1e-9 * math.max(1.0, ratio.abs());
    return (ratio - nearest).abs() <= tolerance
        ? nearest.toInt()
        : ratio.ceil();
  }

  double _updateScrubMultiplierForDy(double dy) {
    while (true) {
      final previousTier = _scrubTier;
      switch (_scrubTier) {
        case -2:
          if (dy >=
              -_NumericScrubMetrics.outerBandBoundary +
                  _NumericScrubMetrics.bandHysteresis) {
            _scrubTier = -1;
          }
        case -1:
          if (dy <= -_NumericScrubMetrics.outerBandBoundary) {
            _scrubTier = -2;
          } else if (dy >=
              -_NumericScrubMetrics.innerBandBoundary +
                  _NumericScrubMetrics.bandHysteresis) {
            _scrubTier = 0;
          }
        case 0:
          if (dy <= -_NumericScrubMetrics.innerBandBoundary) {
            _scrubTier = -1;
          } else if (dy >= _NumericScrubMetrics.innerBandBoundary) {
            _scrubTier = 1;
          }
        case 1:
          if (dy <=
              _NumericScrubMetrics.innerBandBoundary -
                  _NumericScrubMetrics.bandHysteresis) {
            _scrubTier = 0;
          } else if (dy >= _NumericScrubMetrics.outerBandBoundary) {
            _scrubTier = 2;
          }
        case 2:
          if (dy <=
              _NumericScrubMetrics.outerBandBoundary -
                  _NumericScrubMetrics.bandHysteresis) {
            _scrubTier = 1;
          }
      }
      if (_scrubTier == previousTier) break;
    }

    return switch (_scrubTier) {
      -2 => 4,
      -1 => 2,
      1 => 0.5,
      2 => 0.25,
      _ => 1,
    };
  }

  double _clampNumber(double value) {
    var result = value;
    if (widget.min case final min? when result < min) result = min;
    if (widget.max case final max? when result > max) result = max;
    return result;
  }

  String _defaultNumberFormat(double value) {
    final rounded = double.parse(value.toStringAsPrecision(15));
    return rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toString();
  }

  void _handleChanged(String value) {
    if (_textEditingStartText != null) _textEditingChanged = true;
    widget.onChanged?.call(value);
  }

  void _handleSubmitted(String value) {
    if (_isNumeric && !_isValidNumber) {
      setState(() => _showValidationError = true);
      // Keep the keyboard up so the user can fix the invalid value; the
      // field still owns focus here, so requestFocus alone would do nothing.
      _requestEditingFocus();
      return;
    }
    _commitTextEditing();
    widget.onSubmitted?.call(value);
  }

  bool get _hasStepModifier {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed;
  }

  Axis get _stepperAxis => switch (widget.stepperDirection) {
    CLNumericStepperDirection.up ||
    CLNumericStepperDirection.down => Axis.vertical,
    CLNumericStepperDirection.left ||
    CLNumericStepperDirection.right => Axis.horizontal,
  };

  double get _leadingStepDirection => switch (widget.stepperDirection) {
    CLNumericStepperDirection.up || CLNumericStepperDirection.left => 1,
    CLNumericStepperDirection.down || CLNumericStepperDirection.right => -1,
  };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _scrollCommitTimer?.cancel();
      _scrollCommitTimer = null;
      if (_numericInteractionStartText != null) {
        _cancelNumericInteraction();
      } else {
        _cancelTextEditing();
      }
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }
    if (!_showsStepper) return KeyEventResult.ignored;

    final stepDirection = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp when _stepperAxis == Axis.vertical =>
        _leadingStepDirection,
      LogicalKeyboardKey.arrowDown when _stepperAxis == Axis.vertical =>
        -_leadingStepDirection,
      LogicalKeyboardKey.arrowLeft when _stepperAxis == Axis.horizontal =>
        _leadingStepDirection,
      LogicalKeyboardKey.arrowRight when _stepperAxis == Axis.horizontal =>
        -_leadingStepDirection,
      _ => null,
    };
    if (stepDirection == null) return KeyEventResult.ignored;

    if (event is KeyUpEvent) {
      if (_activeStepKey == event.logicalKey) _commitNumericInteraction();
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final composing = _controller.value.composing;
    if ((composing.isValid && !composing.isCollapsed) || _hasStepModifier) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (_activeStepKey != null && _activeStepKey != event.logicalKey) {
        _commitNumericInteraction();
      }
      _beginNumericInteraction();
      _activeStepKey = event.logicalKey;
    }
    _bump(stepDirection);
    return KeyEventResult.handled;
  }

  /// The field is focused and shows its accent ring: either the editing
  /// focus node or an active scrub operation. Wheel stepping only responds
  /// in this state so unfocused fields never steal scroll from ancestors.
  bool get _isFocused =>
      _focusNode.hasFocus ||
      (_operationFocusRequested && _operationFocusNode.hasPrimaryFocus);

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_isFocused ||
        event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        _hasStepModifier) {
      return;
    }

    final delta = event.scrollDelta;
    if (delta.dy == 0 || delta.dy.abs() < delta.dx.abs()) return;
    final direction = delta.dy < 0 ? 1 : -1;
    if (!_canStep(direction.toDouble())) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      final scrollEvent = resolvedEvent as PointerScrollEvent;
      _beginNumericInteraction();
      if (_bump(direction.toDouble())) {
        _scrollCommitTimer?.cancel();
        _scrollCommitTimer = Timer(
          const Duration(milliseconds: 120),
          _commitNumericInteraction,
        );
        scrollEvent.respond(allowPlatformDefault: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _controller,
        _focusNode,
        _operationFocusNode,
      ]),
      builder: (context, _) => _buildTextField(context),
    );
  }

  Widget _buildTextField(BuildContext context) {
    final theme = CLTheme.of(context);
    final focused = _isFocused;
    final textStyle = _textStyle(theme);
    final field = _buildEditableText(theme, textStyle);
    final horizontalPad = widget.size == CLControlSize.small ? 10.0 : 12.0;
    final borderRadius =
        widget.borderRadiusGeometry ??
        BorderRadius.circular(widget.borderRadius ?? theme.radii.control);
    final content = _showsStepper
        ? _buildStepperContent(field, theme, focused, horizontalPad)
        : _buildPlainContent(field, theme);
    final control = _buildControl(
      theme: theme,
      focused: focused,
      borderRadius: borderRadius,
      horizontalPad: horizontalPad,
      content: content,
    );
    return _buildSemantics(control);
  }

  TextStyle _textStyle(CLThemeData theme) {
    final useMono = widget.mono || _showsStepper;
    return (useMono
            ? theme.typography.monoStrong
            : widget.size == CLControlSize.large
            ? theme.typography.body
            : theme.typography.callout)
        .copyWith(
          color: widget.enabled
              ? theme.colors.textPrimary
              : theme.colors.textDisabled,
        );
  }

  Widget _buildEditableText(CLThemeData theme, TextStyle textStyle) {
    return CupertinoTextField(
      controller: _controller,
      focusNode: _focusNode,
      placeholder: widget.placeholder,
      placeholderStyle: textStyle.copyWith(color: theme.colors.textHint),
      style: textStyle,
      cursorColor: _showsError ? theme.colors.danger : theme.colors.accent,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      enableInteractiveSelection: !widget.readOnly,
      obscureText: widget.obscureText,
      textAlign: widget.textAlign,
      onChanged: _handleChanged,
      onSubmitted: _handleSubmitted,
      // Keep the Claralight surface in charge of disabled styling.
      // A null decoration makes CupertinoTextField inject its opaque
      // platform disabled background behind the editable region.
      decoration: const BoxDecoration(),
      padding: EdgeInsets.zero,
      maxLines: 1,
    );
  }

  Widget _buildStepperContent(
    Widget field,
    CLThemeData theme,
    bool focused,
    double horizontalPad,
  ) {
    return Row(
      children: [
        if (widget.prefix case final prefix?)
          _NumericPrefixScrubRegion(
            key: const Key('cl-text-field-prefix-scrub-zone'),
            enabled: _canAdjustNumber,
            height: _height,
            onRequestOperationFocus: _requestOperationFocus,
            onScrubPointerDown: _prepareScrubCursor,
            onScrubStart: _beginScrub,
            onScrubUpdate: _updateScrub,
            onScrubEnd: _endScrub,
            onAdjustmentEnd: _finishAdjustment,
            child: Padding(
              padding: EdgeInsets.only(left: horizontalPad, right: 10),
              child: _stepperSlot(prefix, theme, unit: false),
            ),
          )
        else
          SizedBox(width: horizontalPad),
        Expanded(
          child: KeyedSubtree(
            key: _scrubAnchorKey,
            child: _buildNumericBody(
              field: field,
              theme: theme,
              focused: focused,
            ),
          ),
        ),
      ],
    );
  }

  void _finishAdjustment(bool canceled) {
    if (canceled) {
      _cancelNumericInteraction();
    } else {
      _commitNumericInteraction();
    }
  }

  Widget _buildPlainContent(Widget field, CLThemeData theme) {
    final gap = widget.size == CLControlSize.small ? 6.0 : 8.0;
    return Row(
      children: [
        if (widget.prefix case final prefix?) ...[
          _slot(prefix, theme),
          SizedBox(width: gap),
        ],
        Expanded(child: Center(child: field)),
        if (widget.suffix case final suffix?) ...[
          SizedBox(width: gap),
          _slot(suffix, theme),
        ],
      ],
    );
  }

  Widget _buildControl({
    required CLThemeData theme,
    required bool focused,
    required BorderRadiusGeometry borderRadius,
    required double horizontalPad,
    required Widget content,
  }) {
    final colors = theme.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled && !widget.readOnly ? _requestEditingFocus : null,
      child: Focus(
        focusNode: _operationFocusNode,
        skipTraversal: true,
        onKeyEvent: _handleKeyEvent,
        child: SizedBox(
          width: widget.width,
          height: _height,
          child: AnimatedContainer(
            key: const Key('cl-text-field-surface'),
            duration: CLMotion.fast,
            curve: Curves.easeOutCubic,
            decoration: clSmoothDecoration(
              color: widget.enabled
                  ? colors.control
                  : colors.control.withValues(alpha: colors.control.a * 0.5),
              borderRadius: borderRadius,
              side: BorderSide(
                color: _showsError
                    ? colors.danger
                    : focused
                    ? colors.accent
                    : const Color(0x00000000),
                width: focused ? 1.5 : 1,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            padding: _showsStepper
                ? EdgeInsets.zero
                : EdgeInsets.symmetric(horizontal: horizontalPad),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildSemantics(Widget control) {
    final increasedValue = _semanticSteppedValue(1);
    final decreasedValue = _semanticSteppedValue(-1);
    return Semantics(
      validationResult: _showsError
          ? ui.SemanticsValidationResult.invalid
          : ui.SemanticsValidationResult.none,
      value: increasedValue != null || decreasedValue != null
          ? _controller.text
          : null,
      increasedValue: increasedValue,
      decreasedValue: decreasedValue,
      onIncrease: increasedValue != null ? () => _semanticStep(1) : null,
      onDecrease: decreasedValue != null ? () => _semanticStep(-1) : null,
      child: TextFieldTapRegion(
        child: Listener(
          onPointerSignal: _showsStepper ? _handlePointerSignal : null,
          child: OverlayPortal(
            controller: _scrubPortal,
            overlayChildBuilder: _buildScrubOverlay,
            child: control,
          ),
        ),
      ),
    );
  }

  void _semanticStep(double direction) {
    _beginNumericInteraction();
    _bump(direction);
    _commitNumericInteraction();
  }

  Widget _buildNumericBody({
    required Widget field,
    required CLThemeData theme,
    required bool focused,
  }) {
    final regularContent = Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  fit: FlexFit.loose,
                  child: IntrinsicWidth(child: field),
                ),
                if (!_scrubVisualMounted && widget.suffix != null)
                  _stepperSlot(widget.suffix!, theme, unit: true),
              ],
            ),
          ),
        ),
        _NumericStepper(
          key: const Key('cl-text-field-stepper-drag-zone'),
          height: _height,
          focused: focused,
          increaseDirection: widget.stepperDirection,
          canStep: (direction) => _canStep(direction.toDouble()),
          onPointerStep: _handlePointerStep,
          onRequestEditingFocus: _requestEditingFocus,
          onRequestOperationFocus: _requestOperationFocus,
          onScrubPointerDown: _prepareScrubCursor,
          onScrubStart: _beginScrub,
          onScrubUpdate: _updateScrub,
          onScrubEnd: _endScrub,
          onAdjustmentEnd: (canceled) => canceled
              ? _cancelNumericInteraction()
              : _commitNumericInteraction(),
        ),
      ],
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_scrubReveal, _rulerSpacingTransition]),
      child: regularContent,
      builder: (context, child) {
        final presence = CLMotion.easeOut.transform(_scrubReveal.value);
        final tickCounts = _scrubTickCounts;
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: 1 - presence, child: child),
            if (_scrubVisualMounted)
              IgnorePointer(
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: presence,
                    child: CustomPaint(
                      key: const Key('cl-text-field-scrub-ruler'),
                      painter: _NumericScrubRulerPainter(
                        color: theme.colors.textPrimary,
                        progress: _scrubProgress,
                        spacing: _currentRulerSpacing,
                        increaseTickCount: tickCounts.increase,
                        decreaseTickCount: tickCounts.decrease,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildScrubOverlay(BuildContext context) {
    final value = _number;
    if (!_scrubVisualMounted || value == null) {
      return const SizedBox.shrink();
    }

    final theme = CLTheme.of(context);
    final colors = theme.colors;
    final maxWidth = math.max(80.0, MediaQuery.sizeOf(context).width - 40);

    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _scrubReveal,
          builder: (context, child) {
            final growth = CLMotion.easeOut.transform(_scrubReveal.value);
            return CLAnchoredOverlay(
              key: const Key('cl-text-field-scrub-popover'),
              anchorKey: _scrubAnchorKey,
              position: CLPopoverPosition.top,
              showArrow: true,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              borderRadius: theme.radii.panel,
              fill: colors.frost.withValues(alpha: colors.frost.a * 0.68),
              outlineColor: colors.outlineStrong,
              shadowColor: const Color(0x59000000),
              shadowBlur: 24,
              shadowOffset: const Offset(0, 10),
              // Normal motion grows the value chip from the anchor; opacity
              // is reserved for the non-moving reduced-motion fallback.
              opacity: _disableAnimations ? growth : 1,
              scale: _disableAnimations ? 1 : growth,
              child: child!,
            );
          },
          child: _NumericScrubValueOverlay(
            key: const Key('cl-text-field-scrub-value-overlay'),
            value: value,
            formattedValue:
                widget.format?.call(value) ?? _defaultNumberFormat(value),
            suffix: widget.suffix,
            maxWidth: maxWidth,
            theme: theme,
          ),
        ),
      ),
    );
  }

  Widget _slot(Widget child, CLThemeData theme) {
    return IconTheme.merge(
      data: IconThemeData(
        color: theme.colors.textTertiary,
        size: widget.size == CLControlSize.small ? 14 : 18,
      ),
      child: DefaultTextStyle.merge(
        style: (widget.mono ? theme.typography.mono : theme.typography.callout)
            .withCLWeight(FontWeight.w400)
            .copyWith(color: theme.colors.textTertiary),
        child: child,
      ),
    );
  }

  Widget _stepperSlot(Widget child, CLThemeData theme, {required bool unit}) {
    final color = widget.enabled
        ? theme.colors.textTertiary
        : theme.colors.textDisabled;
    final style = unit
        ? theme.typography.mono
        : theme.typography.callout.withCLWeight(FontWeight.w400);

    return IconTheme.merge(
      data: IconThemeData(
        color: color,
        size: widget.size == CLControlSize.small ? 14 : 18,
      ),
      child: DefaultTextStyle.merge(
        style: style.copyWith(color: color),
        child: child,
      ),
    );
  }
}

abstract final class _NumericScrubMetrics {
  static const double baseSpacing = 8;
  static const Duration spacingTransitionDuration = Duration(milliseconds: 80);
  static const double innerBandBoundary = 50;
  static const double outerBandBoundary = 150;
  static const double bandHysteresis = 4;
  static const double preciseActivationDistance = 4;
  static const double touchActivationDistance = 8;
}

const _preciseScrubPointerKinds = <PointerDeviceKind>{
  PointerDeviceKind.mouse,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

bool _primaryButtonOnly(int buttons) => buttons == kPrimaryButton;

final Object _gestureArenaCanceled = Object();

typedef _ScrubStartCallback = bool Function(PointerDeviceKind kind);
typedef _NumericScrubUpdate = ({
  Offset delta,
  Offset position,
  Size viewSize,
  double devicePixelRatio,
});

_NumericScrubUpdate _scrubUpdateFor(
  BuildContext context, {
  required Offset delta,
  required Offset position,
}) {
  final view = View.of(context);
  return (
    delta: delta,
    position: position,
    viewSize: view.physicalSize / view.devicePixelRatio,
    devicePixelRatio: view.devicePixelRatio,
  );
}

class _NumericPrefixScrubRegion extends StatefulWidget {
  const _NumericPrefixScrubRegion({
    super.key,
    required this.enabled,
    required this.height,
    required this.onRequestOperationFocus,
    required this.onScrubPointerDown,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onAdjustmentEnd,
    required this.child,
  });

  final bool enabled;
  final double height;
  final VoidCallback onRequestOperationFocus;
  final ValueChanged<PointerDownEvent> onScrubPointerDown;
  final _ScrubStartCallback onScrubStart;
  final ValueChanged<_NumericScrubUpdate> onScrubUpdate;
  final VoidCallback onScrubEnd;
  final ValueChanged<bool> onAdjustmentEnd;
  final Widget child;

  @override
  State<_NumericPrefixScrubRegion> createState() =>
      _NumericPrefixScrubRegionState();
}

class _NumericPrefixScrubRegionState extends State<_NumericPrefixScrubRegion> {
  bool _preciseScrubActive = false;
  bool _touchLongPressActive = false;
  bool _touchScrubActive = false;
  Offset _lastTouchOffset = Offset.zero;

  void _handlePreciseStart(DragStartDetails details) {
    _preciseScrubActive = widget.onScrubStart(
      details.kind ?? PointerDeviceKind.unknown,
    );
  }

  void _handlePreciseUpdate(DragUpdateDetails details) {
    if (_preciseScrubActive) {
      widget.onScrubUpdate(
        _scrubUpdateFor(
          context,
          delta: details.delta,
          position: details.globalPosition,
        ),
      );
    }
  }

  void _handlePreciseEnd([Object? details]) {
    if (_preciseScrubActive) {
      widget.onScrubEnd();
      widget.onAdjustmentEnd(
        details == null || identical(details, _gestureArenaCanceled),
      );
    }
    _preciseScrubActive = false;
  }

  void _handleTouchStart(LongPressStartDetails details) {
    if (!widget.enabled) return;
    _touchLongPressActive = true;
    _touchScrubActive = false;
    _lastTouchOffset = Offset.zero;
    widget.onRequestOperationFocus();
  }

  void _handleTouchMove(LongPressMoveUpdateDetails details) {
    if (!_touchLongPressActive) return;
    final offset = details.localOffsetFromOrigin;
    if (!_touchScrubActive) {
      if (offset.distance < _NumericScrubMetrics.touchActivationDistance) {
        return;
      }
      _touchScrubActive = widget.onScrubStart(PointerDeviceKind.touch);
      if (!_touchScrubActive) return;
    }

    final delta = offset - _lastTouchOffset;
    _lastTouchOffset = offset;
    widget.onScrubUpdate(
      _scrubUpdateFor(context, delta: delta, position: details.globalPosition),
    );
  }

  void _handleTouchEnd([Object? details]) {
    if (_touchScrubActive) {
      widget.onScrubEnd();
      widget.onAdjustmentEnd(
        details == null || identical(details, _gestureArenaCanceled),
      );
    }
    _touchLongPressActive = false;
    _touchScrubActive = false;
    _lastTouchOffset = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.resizeLeftRight
            : MouseCursor.defer,
        child: _NumericScrubGestureDetector(
          enabled: widget.enabled,
          onPointerDown: widget.onScrubPointerDown,
          onPreciseStart: _handlePreciseStart,
          onPreciseUpdate: _handlePreciseUpdate,
          onPreciseEnd: _handlePreciseEnd,
          onTouchStart: _handleTouchStart,
          onTouchMove: _handleTouchMove,
          onTouchEnd: _handleTouchEnd,
          child: SizedBox(
            height: widget.height,
            child: Align(alignment: Alignment.center, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _NumericStepper extends StatefulWidget {
  static const double width = 24;
  static const double arrowWidth = 18;
  static const double arrowHeight = 10;

  const _NumericStepper({
    super.key,
    required this.height,
    required this.focused,
    required this.increaseDirection,
    required this.canStep,
    required this.onPointerStep,
    required this.onRequestEditingFocus,
    required this.onRequestOperationFocus,
    required this.onScrubPointerDown,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onAdjustmentEnd,
  });

  final double height;
  final bool focused;
  final CLNumericStepperDirection increaseDirection;
  final bool Function(int direction) canStep;
  final bool Function(int steps) onPointerStep;
  final VoidCallback onRequestEditingFocus;
  final VoidCallback onRequestOperationFocus;
  final ValueChanged<PointerDownEvent> onScrubPointerDown;
  final _ScrubStartCallback onScrubStart;
  final ValueChanged<_NumericScrubUpdate> onScrubUpdate;
  final VoidCallback onScrubEnd;
  final ValueChanged<bool> onAdjustmentEnd;

  @override
  State<_NumericStepper> createState() => _NumericStepperState();
}

class _NumericStepperState extends State<_NumericStepper>
    with WidgetsBindingObserver {
  static const _touchLongPressDelay = Duration(milliseconds: 300);
  static const _repeatDelay = Duration(milliseconds: 500);
  static const _touchRepeatDelay = Duration(milliseconds: 200);
  static const _repeatInterval = Duration(milliseconds: 80);

  Timer? _repeatDelayTimer;
  Timer? _repeatTimer;
  int? _pressedDirection;
  PointerDeviceKind? _pressedKind;
  bool _didRepeat = false;
  bool _touchLongPressActive = false;
  bool _touchScrubActive = false;
  bool _preciseScrubActive = false;
  bool _interactionCanceled = false;
  Offset _lastTouchOffset = Offset.zero;

  bool get _canAdjust => widget.canStep(1) || widget.canStep(-1);

  Axis get _axis => switch (widget.increaseDirection) {
    CLNumericStepperDirection.up ||
    CLNumericStepperDirection.down => Axis.vertical,
    CLNumericStepperDirection.left ||
    CLNumericStepperDirection.right => Axis.horizontal,
  };

  int get _leadingDirection => switch (widget.increaseDirection) {
    CLNumericStepperDirection.up || CLNumericStepperDirection.left => 1,
    CLNumericStepperDirection.down || CLNumericStepperDirection.right => -1,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(_NumericStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.focused && !widget.focused) || !_canAdjust) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _cancelInteraction(
            notifyScrubEnd: true,
            notifyAdjustmentCancel: true,
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cancelInteraction(notifyScrubEnd: true, notifyAdjustmentCancel: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelInteraction(notifyScrubEnd: true, notifyAdjustmentCancel: true);
    super.dispose();
  }

  void _stopRepeatTimers() {
    _repeatDelayTimer?.cancel();
    _repeatDelayTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _cancelInteraction({
    bool markCanceled = false,
    bool notifyScrubEnd = false,
    bool notifyAdjustmentCancel = false,
  }) {
    final hadInteraction =
        _pressedDirection != null ||
        _touchLongPressActive ||
        _touchScrubActive ||
        _preciseScrubActive;
    final hadScrub = _touchScrubActive || _preciseScrubActive;
    _stopRepeatTimers();
    _pressedDirection = null;
    _pressedKind = null;
    _didRepeat = false;
    _touchLongPressActive = false;
    _touchScrubActive = false;
    _preciseScrubActive = false;
    _interactionCanceled = markCanceled;
    _lastTouchOffset = Offset.zero;
    if (hadScrub && notifyScrubEnd) widget.onScrubEnd();
    if (hadInteraction && notifyAdjustmentCancel) {
      widget.onAdjustmentEnd(true);
    }
  }

  void _finishInteraction() {
    final hadInteraction =
        _pressedDirection != null ||
        _touchLongPressActive ||
        _touchScrubActive ||
        _preciseScrubActive;
    _cancelInteraction(notifyScrubEnd: true);
    if (hadInteraction) widget.onAdjustmentEnd(false);
    _interactionCanceled = false;
  }

  void _finishOrCancelInteraction(Object? details) {
    final arenaCanceled = identical(details, _gestureArenaCanceled);
    if (arenaCanceled &&
        !_preciseScrubActive &&
        !_touchLongPressActive &&
        !_touchScrubActive) {
      return;
    }
    if (details == null || arenaCanceled) {
      _cancelInteraction(
        markCanceled: true,
        notifyScrubEnd: true,
        notifyAdjustmentCancel: true,
      );
      return;
    }
    _finishInteraction();
  }

  void _scheduleRepeat(Duration delay) {
    _repeatDelayTimer?.cancel();
    _repeatDelayTimer = Timer(delay, _startRepeating);
  }

  void _requestFocusFor(PointerDeviceKind? kind) {
    if (kind == PointerDeviceKind.touch) {
      widget.onRequestOperationFocus();
    } else {
      widget.onRequestEditingFocus();
    }
  }

  void _startRepeating() {
    _repeatDelayTimer = null;
    final direction = _pressedDirection;
    if (!mounted || _interactionCanceled || direction == null) return;

    _didRepeat = true;
    if (!widget.canStep(direction)) return;
    _requestFocusFor(_pressedKind);
    if (!widget.onPointerStep(direction) || !widget.canStep(direction)) return;

    _repeatTimer = Timer.periodic(_repeatInterval, (_) {
      if (!mounted ||
          _interactionCanceled ||
          !widget.canStep(direction) ||
          !widget.onPointerStep(direction)) {
        _repeatTimer?.cancel();
        _repeatTimer = null;
      }
    });
  }

  void _handleButtonDown(int direction, PointerDownEvent event) {
    if (!_primaryButtonOnly(event.buttons)) return;
    _stopRepeatTimers();
    _interactionCanceled = false;
    _pressedDirection = direction;
    _pressedKind = event.kind;
    _didRepeat = false;
    if (event.kind != PointerDeviceKind.touch) {
      _scheduleRepeat(_repeatDelay);
    }
  }

  void _handleButtonTap(int direction) {
    final repeated = _didRepeat;
    _stopRepeatTimers();
    _pressedDirection = null;
    _pressedKind = null;
    _didRepeat = false;

    if (!_interactionCanceled && !repeated && widget.canStep(direction)) {
      widget.onRequestEditingFocus();
      widget.onPointerStep(direction);
    }
    if (!_interactionCanceled) widget.onAdjustmentEnd(false);
    _interactionCanceled = false;
  }

  void _deferAdjustmentCancel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _interactionCanceled && !_preciseScrubActive) {
        widget.onAdjustmentEnd(true);
      }
    });
  }

  void _handleButtonCancel() {
    if (_touchLongPressActive || _preciseScrubActive) return;
    _cancelInteraction(markCanceled: true, notifyScrubEnd: true);
    _deferAdjustmentCancel();
  }

  void _handleButtonExit(int direction) {
    if (_pressedDirection == direction &&
        !_touchLongPressActive &&
        !_preciseScrubActive) {
      _cancelInteraction(markCanceled: true, notifyScrubEnd: true);
      _deferAdjustmentCancel();
    }
  }

  int? _directionAt(Offset localPosition) {
    if (_axis == Axis.vertical) {
      if (localPosition.dx < 0 ||
          localPosition.dx >= _NumericStepper.arrowWidth) {
        return null;
      }

      final top = (widget.height - 2 * _NumericStepper.arrowHeight) / 2;
      if (localPosition.dy >= top &&
          localPosition.dy < top + _NumericStepper.arrowHeight) {
        return _leadingDirection;
      }
      if (localPosition.dy >= top + _NumericStepper.arrowHeight &&
          localPosition.dy < top + 2 * _NumericStepper.arrowHeight) {
        return -_leadingDirection;
      }
      return null;
    }

    if (localPosition.dy < 0 || localPosition.dy >= widget.height) return null;
    if (localPosition.dx >= 0 &&
        localPosition.dx < _NumericStepper.arrowHeight) {
      return _leadingDirection;
    }
    if (localPosition.dx >= _NumericStepper.arrowHeight &&
        localPosition.dx < 2 * _NumericStepper.arrowHeight) {
      return -_leadingDirection;
    }
    return null;
  }

  void _handleTouchLongPressStart(LongPressStartDetails details) {
    if (!_canAdjust) return;
    _stopRepeatTimers();
    _pressedDirection = null;
    _pressedKind = PointerDeviceKind.touch;
    _didRepeat = false;
    _touchLongPressActive = true;
    _touchScrubActive = false;
    _preciseScrubActive = false;
    _interactionCanceled = false;
    _lastTouchOffset = Offset.zero;

    widget.onRequestOperationFocus();
    final direction = _directionAt(details.localPosition);
    if (direction != null && widget.canStep(direction)) {
      _pressedDirection = direction;
      _scheduleRepeat(_touchRepeatDelay);
    }
  }

  void _handleTouchLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_touchLongPressActive || _interactionCanceled) return;
    final offset = details.localOffsetFromOrigin;

    if (!_touchScrubActive) {
      if (offset.distance < _NumericScrubMetrics.touchActivationDistance) {
        return;
      }
      _stopRepeatTimers();
      _pressedDirection = null;
      _touchScrubActive = widget.onScrubStart(PointerDeviceKind.touch);
      if (!_touchScrubActive) return;
    }

    final delta = offset - _lastTouchOffset;
    _lastTouchOffset = offset;
    widget.onScrubUpdate(
      _scrubUpdateFor(context, delta: delta, position: details.globalPosition),
    );
  }

  void _handlePreciseDragStart(DragStartDetails details) {
    if (!_canAdjust) return;
    _stopRepeatTimers();
    _pressedDirection = null;
    _pressedKind = null;
    _didRepeat = false;
    _touchLongPressActive = false;
    _touchScrubActive = false;
    _interactionCanceled = false;
    _preciseScrubActive = widget.onScrubStart(
      details.kind ?? PointerDeviceKind.unknown,
    );
  }

  void _handlePreciseDragUpdate(DragUpdateDetails details) {
    if (_preciseScrubActive && !_interactionCanceled) {
      widget.onScrubUpdate(
        _scrubUpdateFor(
          context,
          delta: details.delta,
          position: details.globalPosition,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdjust = _canAdjust;
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: canAdjust
            ? SystemMouseCursors.resizeLeftRight
            : MouseCursor.defer,
        child: _NumericScrubGestureDetector(
          enabled: canAdjust,
          onPointerDown: widget.onScrubPointerDown,
          onPreciseStart: _handlePreciseDragStart,
          onPreciseUpdate: _handlePreciseDragUpdate,
          onPreciseEnd: _finishOrCancelInteraction,
          onTouchStart: _handleTouchLongPressStart,
          onTouchMove: _handleTouchLongPressMove,
          onTouchEnd: _finishOrCancelInteraction,
          child: SizedBox(
            width: _NumericStepper.width,
            height: widget.height,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Flex(
                direction: _axis,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildChevron(_leadingDirection),
                  _buildChevron(-_leadingDirection),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChevron(int direction) {
    final leading = direction == _leadingDirection;
    final vertical = _axis == Axis.vertical;
    return _ChevronButton(
      key: Key(
        vertical
            ? leading
                  ? 'cl-text-field-step-up'
                  : 'cl-text-field-step-down'
            : leading
            ? 'cl-text-field-step-left'
            : 'cl-text-field-step-right',
      ),
      direction: vertical
          ? leading
                ? CLNumericStepperDirection.up
                : CLNumericStepperDirection.down
          : leading
          ? CLNumericStepperDirection.left
          : CLNumericStepperDirection.right,
      enabled: widget.canStep(direction),
      onPointerDown: (event) => _handleButtonDown(direction, event),
      onTap: () => _handleButtonTap(direction),
      onTapCancel: _handleButtonCancel,
      onExit: () => _handleButtonExit(direction),
    );
  }
}

class _NumericScrubGestureDetector extends StatelessWidget {
  const _NumericScrubGestureDetector({
    required this.enabled,
    required this.onPointerDown,
    required this.onPreciseStart,
    required this.onPreciseUpdate,
    required this.onPreciseEnd,
    required this.onTouchStart,
    required this.onTouchMove,
    required this.onTouchEnd,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final GestureDragStartCallback onPreciseStart;
  final GestureDragUpdateCallback onPreciseUpdate;
  final ValueChanged<Object?> onPreciseEnd;
  final GestureLongPressStartCallback onTouchStart;
  final GestureLongPressMoveUpdateCallback onTouchMove;
  final ValueChanged<Object?> onTouchEnd;
  final Widget child;

  Map<Type, GestureRecognizerFactory> _gestureFactories(
    DeviceGestureSettings? gestureSettings,
  ) {
    if (!enabled) return const <Type, GestureRecognizerFactory>{};
    return <Type, GestureRecognizerFactory>{
      _PreciseScrubGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<_PreciseScrubGestureRecognizer>(
            () => _PreciseScrubGestureRecognizer(
              debugOwner: this,
              supportedDevices: _preciseScrubPointerKinds,
            ),
            (recognizer) {
              recognizer
                ..gestureSettings = gestureSettings
                ..dragStartBehavior = DragStartBehavior.down
                ..onlyAcceptDragOnThreshold = true
                ..onStart = onPreciseStart
                ..onUpdate = onPreciseUpdate
                ..onEnd = onPreciseEnd
                ..onCancel = () => onPreciseEnd(_gestureArenaCanceled);
            },
          ),
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: _NumericStepperState._touchLongPressDelay,
              postAcceptSlopTolerance: null,
              supportedDevices: const <PointerDeviceKind>{
                PointerDeviceKind.touch,
              },
              allowedButtonsFilter: _primaryButtonOnly,
              debugOwner: this,
            ),
            (recognizer) {
              recognizer
                ..gestureSettings = gestureSettings
                ..onLongPressStart = onTouchStart
                ..onLongPressMoveUpdate = onTouchMove
                ..onLongPressEnd = onTouchEnd
                ..onLongPressCancel = () => onTouchEnd(_gestureArenaCanceled);
            },
          ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: enabled
          ? (event) {
              if (_primaryButtonOnly(event.buttons)) {
                onPointerDown(event);
              }
            }
          : null,
      onPointerCancel: enabled ? (_) => onPreciseEnd(null) : null,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        gestures: _gestureFactories(MediaQuery.maybeGestureSettingsOf(context)),
        child: child,
      ),
    );
  }
}

class _PreciseScrubGestureRecognizer extends PanGestureRecognizer {
  _PreciseScrubGestureRecognizer({super.debugOwner, super.supportedDevices})
    : super(allowedButtonsFilter: _primaryButtonOnly);

  Offset _distance = Offset.zero;
  bool _trackingSequence = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!_trackingSequence) {
      _distance = Offset.zero;
      _trackingSequence = true;
    }
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _distance += event.localDelta;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => _distance.distance >= _NumericScrubMetrics.preciseActivationDistance;

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _trackingSequence = false;
    _distance = Offset.zero;
  }
}

class _NumericScrubRulerPainter extends CustomPainter {
  const _NumericScrubRulerPainter({
    required this.color,
    required this.progress,
    required this.spacing,
    required this.increaseTickCount,
    required this.decreaseTickCount,
  });

  final Color color;
  final double progress;
  final double spacing;
  final int? increaseTickCount;
  final int? decreaseTickCount;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.width / 2;
    final halfWidth = math.max(1.0, center);
    final lineHeight = size.height * 0.55;
    final top = (size.height - lineHeight) / 2;
    final bottom = top + lineHeight;
    final phase = progress * spacing;
    final lineCount = (size.width / spacing).ceil() + 2;

    final paint = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var index = -lineCount; index <= lineCount; index++) {
      if (increaseTickCount case final count? when index < -count) continue;
      if (decreaseTickCount case final count? when index > count) continue;
      final x = center + phase + index * spacing;
      if (x < -spacing || x > size.width + spacing) continue;
      final distance = ((x - center).abs() / halfWidth).clamp(0.0, 1.0);
      final opacity = math.pow(1 - distance, 1.65).toDouble() * 0.72;
      if (opacity <= 0.01) continue;
      paint.color = color.withValues(alpha: color.a * opacity);
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }

    paint
      ..strokeWidth = 1.25
      ..color = color.withValues(alpha: color.a * 0.96);
    canvas.drawLine(Offset(center, top), Offset(center, bottom), paint);
  }

  @override
  bool shouldRepaint(_NumericScrubRulerPainter oldDelegate) =>
      color != oldDelegate.color ||
      progress != oldDelegate.progress ||
      spacing != oldDelegate.spacing ||
      increaseTickCount != oldDelegate.increaseTickCount ||
      decreaseTickCount != oldDelegate.decreaseTickCount;
}

class _NumericScrubValueOverlay extends StatelessWidget {
  const _NumericScrubValueOverlay({
    super.key,
    required this.value,
    required this.formattedValue,
    required this.suffix,
    required this.maxWidth,
    required this.theme,
  });

  final double value;
  final String formattedValue;
  final Widget? suffix;
  final double maxWidth;
  final CLThemeData theme;

  @override
  Widget build(BuildContext context) {
    final valueStyle = theme.typography.monoStrong.copyWith(
      color: theme.colors.textPrimary,
      fontSize: 30,
      height: 1.12,
    );
    final suffixStyle = theme.typography.mono.copyWith(
      color: theme.colors.textTertiary,
      fontSize: 18,
      height: 1.12,
    );

    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 80, maxWidth: maxWidth),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              CLNumericText.number(
                value,
                formatter: (_) => formattedValue,
                style: valueStyle,
                alignment: Alignment.center,
              ),
              if (suffix case final suffix?) ...[
                const SizedBox(width: 3),
                IgnorePointer(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: theme.colors.textTertiary,
                      size: 18,
                    ),
                    child: DefaultTextStyle.merge(
                      style: suffixStyle,
                      child: suffix,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChevronButton extends StatefulWidget {
  final CLNumericStepperDirection direction;
  final bool enabled;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback onTap;
  final VoidCallback onTapCancel;
  final VoidCallback onExit;

  const _ChevronButton({
    super.key,
    required this.direction,
    required this.enabled,
    required this.onPointerDown,
    required this.onTap,
    required this.onTapCancel,
    required this.onExit,
  });

  @override
  State<_ChevronButton> createState() => _ChevronButtonState();
}

class _ChevronButtonState extends State<_ChevronButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = CLTheme.of(context).colors;
    final color = widget.enabled
        ? (_hovered ? colors.textPrimary : colors.textSecondary)
        : colors.textDisabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onExit();
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.enabled ? widget.onPointerDown : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          onTapCancel: widget.enabled ? widget.onTapCancel : null,
          child: SizedBox.fromSize(
            size: _buttonSize,
            child: Center(
              child: CustomPaint(
                size: _chevronSize,
                painter: _StepChevronPainter(
                  color: color,
                  direction: widget.direction,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isVertical => switch (widget.direction) {
    CLNumericStepperDirection.up || CLNumericStepperDirection.down => true,
    CLNumericStepperDirection.left || CLNumericStepperDirection.right => false,
  };

  Size get _buttonSize => _isVertical
      ? const Size(_NumericStepper.arrowWidth, _NumericStepper.arrowHeight)
      : const Size(_NumericStepper.arrowHeight, _NumericStepper.arrowWidth);

  Size get _chevronSize =>
      _isVertical ? const Size(8, 4.5) : const Size(4.5, 8);
}

class _StepChevronPainter extends CustomPainter {
  final Color color;
  final CLNumericStepperDirection direction;

  const _StepChevronPainter({required this.color, required this.direction});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = switch (direction) {
      CLNumericStepperDirection.up =>
        Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width / 2, 0)
          ..lineTo(size.width, size.height),
      CLNumericStepperDirection.down =>
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width / 2, size.height)
          ..lineTo(size.width, 0),
      CLNumericStepperDirection.left =>
        Path()
          ..moveTo(size.width, 0)
          ..lineTo(0, size.height / 2)
          ..lineTo(size.width, size.height),
      CLNumericStepperDirection.right =>
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(0, size.height),
    };
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StepChevronPainter oldDelegate) =>
      color != oldDelegate.color || direction != oldDelegate.direction;
}
