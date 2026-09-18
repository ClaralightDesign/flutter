import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The semantic trend used by [CLNumericText].
///
/// A trend describes a value getting larger or smaller, not a physical screen
/// direction. With [increasing], old graphemes leave upward and new ones enter
/// from below; [decreasing] mirrors that.
///
/// [automatic] reads the direction out of the content: the number passed to
/// [CLNumericText.number], or the first number the presented string contains.
/// Arbitrary text — `Off` to `On`, `低` to `中` — has no larger or smaller, so
/// [automatic] there means *no direction at all* rather than an arbitrary one,
/// and the transition falls back to the neutral entrance described on
/// [CLNumericText]. Pass [increasing] or [decreasing] explicitly to force the
/// vertical roll on content whose order only the caller knows.
enum CLNumericTextTrend { automatic, increasing, decreasing }

/// A single-line run of text whose changed graphemes transition like SwiftUI's
/// `.contentTransition(.numericText())`.
///
/// The name is the transition, not the content type. What this widget owns is
/// the behaviour of *one line of text changing into another line of text*: the
/// graphemes that survive keep their identity and slide to where they now
/// belong, and only the ones that genuinely changed leave and enter. That is
/// worth a dedicated widget for counters and readouts, where a plain [Text]
/// swap reads as the whole value being replaced, and it is worth exactly as
/// much for `Off` → `On` or `Auto` → `Manual`.
///
/// The first value is shown without animation. Later changes are matched with a
/// diff — a shared prefix, a shared suffix, and the longest run flush with
/// neither end — under one extra rule that exists for numbers: **two ASCII
/// digits may only be paired when they occupy the same decimal place, counted
/// from the right.** That rule is the reason this component exists. It is what
/// makes `1,000` → `1,001` roll one digit while the thousands separator holds
/// still, and what stops `99` → `100` from sliding the old tens digit into the
/// new hundreds column simply because both are a `9` in the same position.
/// Digits at equal places pair up even when the diff never reaches them, so
/// place-matching outranks mere adjacency.
///
/// Unmatched graphemes leave and enter in one of two vocabularies. When a
/// direction is known they roll vertically in the value's direction, as they
/// always have. When it is not — [CLNumericTextTrend.automatic] over content no
/// number can be read out of — they cross-fade in place with a slight scale and
/// a blur instead, because a vertical roll would be asserting an order the
/// content does not have. Either way the departures and arrivals are staggered
/// a frame or two apart along the line, so a word replacing another word reads
/// as a wipe rather than as one simultaneous flicker.
///
/// [CLNumericText.number] is the numeric convenience: it defers formatting to
/// build time, so the widget stays `const`, and asserts the value is finite and
/// the formatter single-line.
class CLNumericText extends StatelessWidget {
  /// Presents [text], diffing it against whatever was presented before.
  const CLNumericText(
    String text, {
    super.key,
    this.style,
    this.alignment = AlignmentDirectional.centerEnd,
    this.trend = CLNumericTextTrend.automatic,
    this.semanticsLabel,
  }) : _text = text,
       value = null,
       formatter = null;

  /// Presents a formatted [value], and infers the trend from consecutive
  /// values rather than from the rendered string.
  ///
  /// [formatter] should return one primary numeric value with ordinary prefix,
  /// suffix, grouping, or decimal decoration. More complex multi-number strings
  /// still transition, but through the general diff rather than any
  /// mathematical field awareness.
  const CLNumericText.number(
    num value, {
    super.key,
    this.formatter,
    this.style,
    this.alignment = AlignmentDirectional.centerEnd,
    this.trend = CLNumericTextTrend.automatic,
    this.semanticsLabel,
  }) : assert(
         value == value &&
             value != double.infinity &&
             value != double.negativeInfinity,
         'CLNumericText.number requires a finite value.',
       ),
       value = value,
       _text = null;

  final String? _text;

  /// The text presented by the default constructor, or null under [number].
  ///
  /// Exactly one of [text] and [value] is non-null.
  String? get text => _text;

  /// The finite value presented by [number], or null under the default
  /// constructor.
  final num? value;

  /// Formats [value] for display. Defaults to [num.toString].
  ///
  /// The result must be a single line. It is called during build rather than in
  /// the constructor so that [number] can stay `const`.
  final String Function(num value)? formatter;

  /// Optional text style merged over the ambient [DefaultTextStyle].
  ///
  /// Tabular figures are enabled unless the merged style explicitly contains
  /// either the `tnum` or `pnum` OpenType feature.
  final TextStyle? style;

  /// Anchors content inside the widget while its intrinsic width changes.
  ///
  /// The parent still owns the widget's global position. Use an end-aligned or
  /// fixed-width parent when the trailing screen coordinate must remain fixed.
  final AlignmentGeometry alignment;

  /// Overrides the direction inferred from consecutive contents.
  final CLNumericTextTrend trend;

  /// Optional accessible label. Defaults to the presented text.
  ///
  /// Updates are not exposed as a live region, so rapidly changing counters do
  /// not repeatedly interrupt assistive technology.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final presented = text ?? (formatter?.call(value!) ?? value!.toString());
    assert(
      _isSingleLine(presented),
      text != null
          ? 'CLNumericText requires single-line text.'
          : 'CLNumericText.number formatter must return a single-line string.',
    );

    final ambientStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = _withDefaultTabularFigures(
      ambientStyle.merge(style),
    );
    final mediaQuery = MediaQuery.maybeOf(context);
    final disableAnimations =
        mediaQuery?.disableAnimations ??
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;

    final resolved = _ResolvedText(
      value: value,
      text: presented,
      style: effectiveStyle,
      alignment: alignment,
      trend: trend,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      disableAnimations: disableAnimations,
      tickerEnabled: TickerMode.valuesOf(context).enabled,
    );

    return Semantics(
      container: true,
      label: semanticsLabel ?? presented,
      excludeSemantics: true,
      child: _NumericTextVisual(resolved: resolved),
    );
  }
}

/// The number-first spelling of [CLNumericText.number].
///
/// The widget outgrew its name: it was never about numbers, only about text
/// that changes a piece at a time. This shim keeps the old call shape — and its
/// `value` and `formatter` fields, which tests reach for — compiling unchanged
/// while call sites move across.
@Deprecated('Renamed to CLNumericText. Will be removed in a future release.')
class CLAnimatedNumber extends StatelessWidget {
  const CLAnimatedNumber(
    this.value, {
    super.key,
    this.formatter,
    this.style,
    this.alignment = AlignmentDirectional.centerEnd,
    this.trend = CLNumericTextTrend.automatic,
    this.semanticsLabel,
  }) : assert(
         value == value &&
             value != double.infinity &&
             value != double.negativeInfinity,
         'CLAnimatedNumber requires a finite value.',
       );

  /// The finite value represented by this widget.
  final num value;

  /// Formats [value] for display. Defaults to [num.toString].
  final String Function(num value)? formatter;

  /// Optional text style merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Anchors content inside the widget while its intrinsic width changes.
  final AlignmentGeometry alignment;

  /// Overrides the trend inferred from consecutive [value]s.
  final CLNumericTextTrend trend;

  /// Optional accessible label. Defaults to the formatted number.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => CLNumericText.number(
    value,
    formatter: formatter,
    style: style,
    alignment: alignment,
    trend: trend,
    semanticsLabel: semanticsLabel,
  );
}

/// The former spelling of [CLNumericTextTrend].
@Deprecated(
  'Renamed to CLNumericTextTrend. Will be removed in a future release.',
)
typedef CLNumberTrend = CLNumericTextTrend;

bool _isSingleLine(String text) =>
    !text.contains('\n') &&
    !text.contains('\r') &&
    !text.contains(' ') &&
    !text.contains(' ');

TextStyle _withDefaultTabularFigures(TextStyle style) {
  final features = style.fontFeatures;
  final hasExplicitFigureWidth =
      features?.any(
        (feature) => feature.feature == 'tnum' || feature.feature == 'pnum',
      ) ??
      false;
  if (hasExplicitFigureWidth) return style;

  return style.copyWith(
    fontFeatures: [...?features, const ui.FontFeature.tabularFigures()],
  );
}

/// Which way unmatched graphemes travel, once the trend has been resolved
/// against the actual content.
///
/// [neutral] is not a third direction but the absence of one: it is what
/// [CLNumericTextTrend.automatic] resolves to when nothing in the content says
/// which of two values is the larger.
enum _TransitionDirection { increasing, decreasing, neutral }

/// An optional sign, then digits carrying ASCII, no-break, or narrow no-break
/// group separators, then an optional fractional part.
final RegExp _numericRun = RegExp(r'[-−]?\d[\d,   ]*(?:\.\d+)?');
final RegExp _groupSeparators = RegExp(r'[,   ]');

/// Reads a number out of presented text, for the sole purpose of deciding which
/// way a transition should roll.
///
/// This is deliberately not a parser: it takes the first run that looks like a
/// number, so that `Battery 84%` and `$1,234.50` still have a direction, and
/// `Off` or `低` correctly have none. Text it cannot read is not an error; it
/// simply means the transition has no direction and falls back to the neutral
/// entrance.
num? _numericInterpretation(String text) {
  final match = _numericRun.stringMatch(text);
  if (match == null) return null;
  final normalized = match
      .replaceAll(_groupSeparators, '')
      .replaceAll('−', '-');
  return num.tryParse(normalized);
}

@immutable
class _ResolvedText {
  const _ResolvedText({
    required this.value,
    required this.text,
    required this.style,
    required this.alignment,
    required this.trend,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required this.disableAnimations,
    required this.tickerEnabled,
  });

  /// The value behind [text] when one was given, and null when the caller
  /// handed over a string this widget has no arithmetic interpretation of.
  final num? value;
  final String text;
  final TextStyle style;
  final AlignmentGeometry alignment;
  final CLNumericTextTrend trend;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final bool disableAnimations;
  final bool tickerEnabled;

  bool get canAnimate => !disableAnimations && tickerEnabled;

  bool hasSameLayoutContext(_ResolvedText other) =>
      style == other.style &&
      alignment == other.alignment &&
      textDirection == other.textDirection &&
      textScaler == other.textScaler &&
      locale == other.locale;

  /// Resolves the caller's trend against what the two contents actually say.
  _TransitionDirection directionFrom(_ResolvedText previous) {
    switch (trend) {
      case CLNumericTextTrend.increasing:
        return _TransitionDirection.increasing;
      case CLNumericTextTrend.decreasing:
        return _TransitionDirection.decreasing;
      case CLNumericTextTrend.automatic:
        break;
    }

    final before = previous.value ?? _numericInterpretation(previous.text);
    final after = value ?? _numericInterpretation(text);
    if (before == null || after == null) return _TransitionDirection.neutral;
    return after > before
        ? _TransitionDirection.increasing
        : _TransitionDirection.decreasing;
  }
}

class _NumericTextVisual extends StatefulWidget {
  const _NumericTextVisual({required this.resolved});

  final _ResolvedText resolved;

  @override
  State<_NumericTextVisual> createState() => _NumericTextVisualState();
}

class _NumericTextVisualState extends State<_NumericTextVisual>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _GlyphScene _scene;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_handleTick);
    _scene = _GlyphScene(widget.resolved);
  }

  @override
  void didUpdateWidget(covariant _NumericTextVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.resolved;
    final next = widget.resolved;

    final textChanged = previous.text != next.text;
    final layoutContextChanged = !previous.hasSameLayoutContext(next);

    if (!next.canAnimate || !previous.canAnimate || layoutContextChanged) {
      _stopAndSnap(next);
      return;
    }

    // Nothing on screen differs, so there is nothing to transition — a value
    // that rounds to the same string, or a rebuild for unrelated reasons.
    if (!textChanged) {
      _scene.updateResolved(next);
      return;
    }

    // The same number in a new format is a presentation change rather than a
    // value change: rolling digits would claim the value moved.
    if (previous.value != null &&
        next.value != null &&
        previous.value == next.value) {
      _stopAndSnap(next);
      return;
    }

    if (!_ticker.isActive) _elapsed = Duration.zero;
    _scene.retarget(
      next,
      direction: next.directionFrom(previous),
      elapsed: _elapsed,
    );
    if (_scene.isAnimating && !_ticker.isActive) _ticker.start();
  }

  void _stopAndSnap(_ResolvedText resolved) {
    if (_ticker.isActive) _ticker.stop();
    _elapsed = Duration.zero;
    _scene.snap(resolved);
  }

  void _handleTick(Duration elapsed) {
    _elapsed = elapsed;
    if (_scene.advance(elapsed)) return;

    _ticker.stop();
    _elapsed = Duration.zero;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _NumericTextRender(scene: _scene);
}

class _GlyphScene extends ChangeNotifier {
  _GlyphScene(this.resolved) {
    _targetLayout = _buildLayout(resolved, previous: null);
    _width = _SpringTrack(_targetLayout.width);
    for (final token in _targetLayout.tokens) {
      _fragments.add(
        _GlyphFragment.resting(layout: _targetLayout, token: token),
      );
    }
  }

  static const double travelFraction = 0.4;
  static const double blurShutter = 1 / 30;
  static const double maxBlurFraction = 1;

  /// How far a neutrally entering grapheme starts from its settled size, and
  /// how much of the type size it is blurred by on the way in.
  ///
  /// Both are small on purpose. Without a direction to roll in, scale and blur
  /// are all that separate an arrival from a glyph that was simply always
  /// there; overdoing either turns a word change into an effect.
  static const double neutralScale = 0.84;
  static const double neutralBlurFraction = 0.09;

  /// The gap between consecutive departures and arrivals along the line.
  ///
  /// It is counted from the first staggered grapheme rather than from the start
  /// of the string, so the common case — one digit changing in a long formatted
  /// number — still starts on the frame it was asked to. The cap keeps a long
  /// word from turning into a visibly sequential crawl.
  static const Duration glyphStagger = Duration(milliseconds: 16);
  static const int maxStaggerRank = 8;

  static const int _maxLayersPerSlot = 4;

  _ResolvedText resolved;
  late _GlyphLayout _targetLayout;
  late _SpringTrack _width;
  final List<_GlyphFragment> _fragments = [];
  final Set<_GlyphLayout> _layouts = {};
  int _nextIdentitySlot = 0;

  double get width => math.max(0, _width.value);
  double get height => _targetLayout.height;
  double get alphabeticBaseline => _targetLayout.alphabeticBaseline;
  AlignmentGeometry get alignment => resolved.alignment;
  TextDirection get textDirection => resolved.textDirection;
  List<_GlyphFragment> get fragments => _fragments;
  _GlyphLayout get targetLayout => _targetLayout;

  bool get isAnimating =>
      _width.isAnimating ||
      _fragments.any(
        (fragment) =>
            fragment.x.isAnimating ||
            fragment.y.isAnimating ||
            fragment.scale.isAnimating ||
            fragment.opacity.isAnimating,
      );

  static Duration _staggerFor(int rank) =>
      glyphStagger * math.min(rank, maxStaggerRank);

  void updateResolved(_ResolvedText next) {
    resolved = next;
  }

  void snap(_ResolvedText next) {
    final previousLayout = _targetLayout;
    final nextLayout = _buildLayout(next, previous: previousLayout);
    final oldLayouts = Set<_GlyphLayout>.of(_layouts)..add(previousLayout);

    resolved = next;
    _targetLayout = nextLayout;
    _width.snap(nextLayout.width);
    _fragments
      ..clear()
      ..addAll(
        nextLayout.tokens.map(
          (token) => _GlyphFragment.resting(layout: nextLayout, token: token),
        ),
      );

    _layouts
      ..clear()
      ..add(nextLayout);
    for (final layout in oldLayouts) {
      if (!identical(layout, nextLayout)) layout.dispose();
    }
    notifyListeners();
  }

  void retarget(
    _ResolvedText next, {
    required _TransitionDirection direction,
    required Duration elapsed,
  }) {
    _sample(elapsed);

    final previousTarget = _targetLayout;
    final nextLayout = _buildLayout(next, previous: previousTarget);
    final nextBySlot = {
      for (final token in nextLayout.tokens) token.slot: token,
    };
    final used = <_GlyphFragment>{};
    final neutral = direction == _TransitionDirection.neutral;
    final incomingSign = direction == _TransitionDirection.decreasing
        ? -1.0
        : 1.0;
    final outgoingSign = -incomingSign;
    final travel = nextLayout.scaledFontSize * travelFraction;

    final entering = <_GlyphFragment>[];
    for (final token in nextLayout.tokens) {
      final matching = _bestMatch(token, used);
      if (matching != null) {
        used.add(matching);
        matching
          ..layout = nextLayout
          ..token = token
          ..isTarget = true;
        matching.x.retarget(token.relativeLeft, elapsed);
        matching.y.retarget(0, elapsed);
        matching.scale.retarget(1, elapsed);
        matching.opacity.retarget(1, elapsed);
        continue;
      }

      final fragment = _GlyphFragment.incoming(
        layout: nextLayout,
        token: token,
        y: token.isDigit && !neutral ? incomingSign * travel : 0,
        scale: neutral ? neutralScale : 1,
        isNeutral: neutral,
      );
      _fragments.add(fragment);
      used.add(fragment);
      entering.add(fragment);
    }

    for (var rank = 0; rank < entering.length; rank++) {
      final fragment = entering[rank];
      final delay = _staggerFor(rank);
      fragment.y.retarget(0, elapsed, delay: delay);
      fragment.scale.retarget(1, elapsed, delay: delay);
      fragment.opacity.retarget(1, elapsed, delay: delay);
    }

    final leaving = <_GlyphFragment>[];
    for (final fragment in _fragments) {
      if (used.contains(fragment)) continue;

      final wasTarget = fragment.isTarget;
      fragment.isTarget = false;
      final replacement = nextBySlot[fragment.token.slot];
      if (replacement != null) {
        fragment.x.retarget(replacement.relativeLeft, elapsed);
      }
      if (!wasTarget) continue;

      fragment.isNeutral = neutral;
      leaving.add(fragment);
    }

    leaving.sort((a, b) => a.token.index.compareTo(b.token.index));
    for (var rank = 0; rank < leaving.length; rank++) {
      final fragment = leaving[rank];
      final delay = _staggerFor(rank);
      if (neutral) {
        fragment.scale.retarget(neutralScale, elapsed, delay: delay);
      } else if (fragment.token.isDigit) {
        fragment.y.retarget(outgoingSign * travel, elapsed, delay: delay);
      }
      fragment.opacity.retarget(0, elapsed, delay: delay);
    }

    resolved = next;
    _targetLayout = nextLayout;
    _width.retarget(nextLayout.width, elapsed);
    _pruneInvisibleAndExcess();
    _disposeUnusedLayouts();
    notifyListeners();
  }

  _GlyphFragment? _bestMatch(_GlyphToken token, Set<_GlyphFragment> used) {
    _GlyphFragment? best;
    for (final fragment in _fragments) {
      if (used.contains(fragment) ||
          fragment.token.slot != token.slot ||
          fragment.token.text != token.text) {
        continue;
      }
      if (best == null ||
          (fragment.isTarget && !best.isTarget) ||
          fragment.opacity.value > best.opacity.value) {
        best = fragment;
      }
    }
    return best;
  }

  bool advance(Duration elapsed) {
    final animating = _sample(elapsed);
    _pruneInvisibleAndExcess();
    _disposeUnusedLayouts();

    if (!animating) {
      _width.snap(_width.target);
      for (final fragment in _fragments) {
        fragment
          ..x.snap(fragment.x.target)
          ..y.snap(fragment.y.target)
          ..scale.snap(fragment.scale.target)
          ..opacity.snap(fragment.opacity.target);
      }
      _fragments.removeWhere((fragment) => !fragment.isTarget);
      _disposeUnusedLayouts();
    }

    notifyListeners();
    return isAnimating;
  }

  bool _sample(Duration elapsed) {
    var animating = _width.sample(elapsed);
    for (final fragment in _fragments) {
      animating = fragment.x.sample(elapsed) || animating;
      animating = fragment.y.sample(elapsed) || animating;
      animating = fragment.scale.sample(elapsed) || animating;
      animating = fragment.opacity.sample(elapsed) || animating;
    }
    return animating;
  }

  void _pruneInvisibleAndExcess() {
    _fragments.removeWhere(
      (fragment) =>
          !fragment.isTarget &&
          fragment.opacity.target == 0 &&
          fragment.opacity.value <= 0.005 &&
          !fragment.opacity.isDelayed,
    );

    final bySlot = <_TokenSlot, List<_GlyphFragment>>{};
    for (final fragment in _fragments) {
      bySlot.putIfAbsent(fragment.token.slot, () => []).add(fragment);
    }
    for (final fragments in bySlot.values) {
      if (fragments.length <= _maxLayersPerSlot) continue;
      final removable =
          fragments.where((fragment) => !fragment.isTarget).toList()
            ..sort((a, b) => a.opacity.value.compareTo(b.opacity.value));
      var excess = fragments.length - _maxLayersPerSlot;
      for (final fragment in removable) {
        if (excess == 0) break;
        _fragments.remove(fragment);
        excess--;
      }
    }
  }

  _GlyphLayout _buildLayout(
    _ResolvedText configuration, {
    required _GlyphLayout? previous,
  }) {
    final layout = _GlyphLayout.create(
      configuration,
      previous: previous,
      nextIdentitySlot: () => _nextIdentitySlot++,
    );
    _layouts.add(layout);
    return layout;
  }

  void _disposeUnusedLayouts() {
    final used = <_GlyphLayout>{_targetLayout};
    for (final fragment in _fragments) {
      used.add(fragment.layout);
    }
    final unused = _layouts.difference(used).toList(growable: false);
    for (final layout in unused) {
      _layouts.remove(layout);
      layout.dispose();
    }
  }

  @override
  void dispose() {
    for (final layout in _layouts) {
      layout.dispose();
    }
    _layouts.clear();
    super.dispose();
  }
}

/// Pairs the graphemes of [previous] with those of [next].
///
/// Each list holds one comparison key per grapheme — its text, prefixed with
/// its decimal place so that two digits never compare equal unless they sit in
/// the same column. Three runs survive a change: the shared prefix, the shared
/// suffix, and the longest common run flush with neither end. Everything else
/// leaves and enters.
///
/// The middle run is what separates this from SwiftUI's own matching: it is why
/// the `1` in `Step 1 of 9` → `Step 1 of 12` is recognised at all, where prefix
/// and suffix alone would have cross-faded most of the line.
///
/// Returns, for each index in [next], the index in [previous] it continues, or
/// null when it is new.
List<int?> _matchGraphemes(List<String> previous, List<String> next) {
  final sources = List<int?>.filled(next.length, null);

  var prefix = 0;
  while (prefix < previous.length &&
      prefix < next.length &&
      previous[prefix] == next[prefix]) {
    sources[prefix] = prefix;
    prefix++;
  }

  var suffix = 0;
  while (suffix < previous.length - prefix &&
      suffix < next.length - prefix &&
      previous[previous.length - 1 - suffix] ==
          next[next.length - 1 - suffix]) {
    sources[next.length - 1 - suffix] = previous.length - 1 - suffix;
    suffix++;
  }

  final previousStart = prefix;
  final previousEnd = previous.length - suffix;
  final nextStart = prefix;
  final nextEnd = next.length - suffix;
  if (previousStart >= previousEnd || nextStart >= nextEnd) return sources;

  // Longest common run between the two middles. Both are short — what is left
  // of one line after its prefix and suffix have been taken — so the quadratic
  // table is cheaper than any cleverer scheme would be.
  final width = previousEnd - previousStart;
  var behind = List<int>.filled(width + 1, 0);
  var bestLength = 0;
  var bestPrevious = 0;
  var bestNext = 0;
  for (var n = nextStart; n < nextEnd; n++) {
    final row = List<int>.filled(width + 1, 0);
    for (var p = previousStart; p < previousEnd; p++) {
      if (previous[p] != next[n]) continue;
      final length = behind[p - previousStart] + 1;
      row[p - previousStart + 1] = length;
      if (length > bestLength) {
        bestLength = length;
        bestPrevious = p;
        bestNext = n;
      }
    }
    behind = row;
  }

  for (var offset = 0; offset < bestLength; offset++) {
    sources[bestNext - offset] = bestPrevious - offset;
  }
  return sources;
}

class _GlyphLayout {
  _GlyphLayout({
    required this.painter,
    required this.tokens,
    required this.scaledFontSize,
  }) : width = painter.width,
       height = painter.height,
       alphabeticBaseline = painter.computeDistanceToActualBaseline(
         TextBaseline.alphabetic,
       );

  final TextPainter painter;
  final List<_GlyphToken> tokens;
  final double width;
  final double height;
  final double alphabeticBaseline;
  final double scaledFontSize;

  static _GlyphLayout create(
    _ResolvedText configuration, {
    required _GlyphLayout? previous,
    required int Function() nextIdentitySlot,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: configuration.text, style: configuration.style),
      maxLines: 1,
      textDirection: configuration.textDirection,
      textScaler: configuration.textScaler,
      locale: configuration.locale,
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout();

    final rawTokens = <_RawToken>[];
    var codeUnitOffset = 0;
    for (final grapheme in configuration.text.characters) {
      final start = codeUnitOffset;
      codeUnitOffset += grapheme.length;
      final selection = TextSelection(
        baseOffset: start,
        extentOffset: codeUnitOffset,
      );
      final boxes = painter.getBoxesForSelection(
        selection,
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      final rect = _selectionRect(
        painter,
        boxes,
        start: start,
        end: codeUnitOffset,
      );
      rawTokens.add(
        _RawToken(
          text: grapheme,
          rect: Rect.fromLTRB(rect.left, 0, rect.right, painter.height),
          isDigit: _isAsciiDigit(grapheme),
        ),
      );
    }

    // A digit's identity is its decimal place counted from the right of the
    // line, so that the units column stays the units column however many digits
    // grow to its left. Everything else shares one non-place, -1, and so is
    // matched on its text alone.
    final places = List<int>.filled(rawTokens.length, -1);
    var digitPlace = 0;
    for (var index = rawTokens.length - 1; index >= 0; index--) {
      if (!rawTokens[index].isDigit) continue;
      places[index] = digitPlace++;
    }

    final sources = _matchGraphemes(
      [
        if (previous != null)
          for (final token in previous.tokens) token.matchKey,
      ],
      [
        for (var index = 0; index < rawTokens.length; index++)
          '${places[index]}:${rawTokens[index].text}',
      ],
    );

    final resolvedAlignment = configuration.alignment.resolve(
      configuration.textDirection,
    );
    final anchorFraction = (resolvedAlignment.x + 1) / 2;
    final tokens = <_GlyphToken>[];
    for (var index = 0; index < rawTokens.length; index++) {
      final raw = rawTokens[index];
      // Digits carry a derived slot rather than an inherited one, which is what
      // layers place-matching over the diff: two digits in the same column with
      // the same face are the same digit even when the diff, reading positions
      // rather than columns, never paired them.
      final source = sources[index];
      final slot = raw.isDigit
          ? _TokenSlot.digit(places[index])
          : source == null
          ? _TokenSlot.identity(nextIdentitySlot())
          : previous!.tokens[source].slot;
      tokens.add(
        _GlyphToken(
          text: raw.text,
          rect: raw.rect,
          slot: slot,
          index: index,
          place: places[index],
          isDigit: raw.isDigit,
          relativeLeft: raw.rect.left - painter.width * anchorFraction,
        ),
      );
    }

    final nominalFontSize = configuration.style.fontSize ?? 14;
    return _GlyphLayout(
      painter: painter,
      tokens: tokens,
      scaledFontSize: configuration.textScaler.scale(nominalFontSize),
    );
  }

  void dispose() => painter.dispose();
}

Rect _selectionRect(
  TextPainter painter,
  List<TextBox> boxes, {
  required int start,
  required int end,
}) {
  if (boxes.isNotEmpty) {
    var left = boxes.first.left;
    var top = boxes.first.top;
    var right = boxes.first.right;
    var bottom = boxes.first.bottom;
    for (final box in boxes.skip(1)) {
      left = math.min(left, box.left);
      top = math.min(top, box.top);
      right = math.max(right, box.right);
      bottom = math.max(bottom, box.bottom);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  final startOffset = painter.getOffsetForCaret(
    TextPosition(offset: start),
    Rect.zero,
  );
  final endOffset = painter.getOffsetForCaret(
    TextPosition(offset: end),
    Rect.zero,
  );
  return Rect.fromLTRB(
    math.min(startOffset.dx, endOffset.dx),
    0,
    math.max(startOffset.dx, endOffset.dx),
    painter.height,
  );
}

bool _isAsciiDigit(String grapheme) =>
    grapheme.length == 1 &&
    grapheme.codeUnitAt(0) >= 0x30 &&
    grapheme.codeUnitAt(0) <= 0x39;

@immutable
class _RawToken {
  const _RawToken({
    required this.text,
    required this.rect,
    required this.isDigit,
  });

  final String text;
  final Rect rect;
  final bool isDigit;
}

@immutable
class _GlyphToken {
  const _GlyphToken({
    required this.text,
    required this.rect,
    required this.slot,
    required this.index,
    required this.place,
    required this.isDigit,
    required this.relativeLeft,
  });

  final String text;
  final Rect rect;
  final _TokenSlot slot;

  /// Position in logical order, which is both the stagger order and the tie
  /// break that keeps departures sequential rather than arbitrary.
  final int index;

  /// Decimal place counted from the right for digits, and -1 for everything
  /// else.
  final int place;
  final bool isDigit;
  final double relativeLeft;

  /// What the diff compares: the grapheme, carrying its column in front of it
  /// so that two digits are never equal unless they stand in the same one. The
  /// leading integer cannot contain the separator, so the key is unambiguous.
  String get matchKey => '$place:$text';
}

@immutable
class _TokenSlot {
  const _TokenSlot._(this.isDigit, this.index);

  const _TokenSlot.digit(int place) : this._(true, place);
  const _TokenSlot.identity(int id) : this._(false, id);

  final bool isDigit;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is _TokenSlot && other.isDigit == isDigit && other.index == index;

  @override
  int get hashCode => Object.hash(isDigit, index);
}

class _GlyphFragment {
  _GlyphFragment._({
    required this.layout,
    required this.token,
    required double x,
    required double y,
    required double scale,
    required double opacity,
    required this.isTarget,
    required this.isNeutral,
  }) : x = _SpringTrack(x, spring: _SpringTrack.structureSpring),
       y = _SpringTrack(y, spring: _SpringTrack.rollSpring),
       scale = _SpringTrack(scale, spring: _SpringTrack.structureSpring),
       opacity = _SpringTrack(opacity, spring: _SpringTrack.fadeSpring);

  factory _GlyphFragment.resting({
    required _GlyphLayout layout,
    required _GlyphToken token,
  }) => _GlyphFragment._(
    layout: layout,
    token: token,
    x: token.relativeLeft,
    y: 0,
    scale: 1,
    opacity: 1,
    isTarget: true,
    isNeutral: false,
  );

  factory _GlyphFragment.incoming({
    required _GlyphLayout layout,
    required _GlyphToken token,
    required double y,
    required double scale,
    required bool isNeutral,
  }) => _GlyphFragment._(
    layout: layout,
    token: token,
    x: token.relativeLeft,
    y: y,
    scale: scale,
    opacity: 0,
    isTarget: true,
    isNeutral: isNeutral,
  );

  _GlyphLayout layout;
  _GlyphToken token;
  final _SpringTrack x;
  final _SpringTrack y;
  final _SpringTrack scale;
  final _SpringTrack opacity;
  bool isTarget;

  /// Whether this fragment is arriving or departing without a direction, and so
  /// carries the scale-and-blur entrance instead of the vertical roll.
  bool isNeutral;
}

class _SpringTrack {
  _SpringTrack(this.value, {this.spring = structureSpring})
    : target = value,
      velocity = 0;

  static const rollSpring = SpringDescription(
    mass: 1,
    stiffness: 246.74,
    damping: 25.13,
  );

  static const structureSpring = SpringDescription(
    mass: 1,
    stiffness: 246.74,
    damping: 31.42,
  );

  static const fadeSpring = SpringDescription(
    mass: 1,
    stiffness: 631.65,
    damping: 50.27,
  );

  static const _tolerance = Tolerance(distance: 0.001, velocity: 0.001);

  final SpringDescription spring;

  double value;
  double velocity;
  double target;
  SpringSimulation? _simulation;
  Duration _startedAt = Duration.zero;

  bool get isAnimating => _simulation != null;

  /// Whether the simulation exists but has not been allowed to start yet — the
  /// held frames that make a stagger a stagger.
  bool get isDelayed => _delayed;
  bool _delayed = false;

  /// Retargets the track, optionally holding it still for [delay] first.
  ///
  /// The delay is expressed as a start time in the future rather than as a
  /// timer, so an interrupting retarget simply overwrites it: a stagger can
  /// never outlive the transition that scheduled it.
  void retarget(
    double nextTarget,
    Duration elapsed, {
    Duration delay = Duration.zero,
  }) {
    sample(elapsed);
    if (_simulation != null &&
        !_delayed &&
        (target - nextTarget).abs() <= 0.000001) {
      return;
    }

    target = nextTarget;
    if ((value - target).abs() <= _tolerance.distance &&
        velocity.abs() <= _tolerance.velocity) {
      snap(target);
      return;
    }

    _simulation = SpringSimulation(
      spring,
      value,
      target,
      velocity,
      snapToEnd: true,
      tolerance: _tolerance,
    );
    _startedAt = elapsed + delay;
    _delayed = delay > Duration.zero;
  }

  bool sample(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return false;

    if (elapsed < _startedAt) return true;
    _delayed = false;

    final micros = math.max(
      0,
      elapsed.inMicroseconds - _startedAt.inMicroseconds,
    );
    final seconds = micros / Duration.microsecondsPerSecond;
    if (simulation.isDone(seconds)) {
      snap(target);
      return false;
    }

    value = simulation.x(seconds);
    velocity = simulation.dx(seconds);
    return true;
  }

  void snap(double nextValue) {
    value = nextValue;
    target = nextValue;
    velocity = 0;
    _simulation = null;
    _startedAt = Duration.zero;
    _delayed = false;
  }
}

class _NumericTextRender extends LeafRenderObjectWidget {
  const _NumericTextRender({required this.scene});

  final _GlyphScene scene;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNumericText(scene);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderNumericText renderObject,
  ) {
    renderObject.scene = scene;
  }
}

class _RenderNumericText extends RenderBox {
  _RenderNumericText(_GlyphScene scene) : _scene = scene {
    _scene.addListener(_handleSceneChanged);
  }

  _GlyphScene _scene;

  _GlyphScene get scene => _scene;
  set scene(_GlyphScene value) {
    if (identical(value, _scene)) return;
    _scene.removeListener(_handleSceneChanged);
    _scene = value;
    _scene.addListener(_handleSceneChanged);
    markNeedsLayout();
    markNeedsPaint();
  }

  void _handleSceneChanged() {
    markNeedsLayout();
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  double computeMinIntrinsicWidth(double height) => scene.width;

  @override
  double computeMaxIntrinsicWidth(double height) => scene.width;

  @override
  double computeMinIntrinsicHeight(double width) => scene.height;

  @override
  double computeMaxIntrinsicHeight(double width) => scene.height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size(scene.width, scene.height));

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final drySize = computeDryLayout(constraints);
    final resolvedAlignment = scene.alignment.resolve(scene.textDirection);
    final top =
        (drySize.height - scene.height) * ((resolvedAlignment.y + 1) / 2);
    return top +
        scene.targetLayout.painter.computeDistanceToActualBaseline(baseline);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final resolvedAlignment = scene.alignment.resolve(scene.textDirection);
    final top = (size.height - scene.height) * ((resolvedAlignment.y + 1) / 2);
    return top +
        scene.targetLayout.painter.computeDistanceToActualBaseline(baseline);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;

    final canvas = context.canvas;
    final resolvedAlignment = scene.alignment.resolve(scene.textDirection);
    final anchorX = size.width * ((resolvedAlignment.x + 1) / 2);
    final targetTop =
        (size.height - scene.height) * ((resolvedAlignment.y + 1) / 2);
    final targetBaseline = targetTop + scene.alphabeticBaseline;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);

    for (final fragment in scene.fragments) {
      _paintFragment(
        canvas,
        fragment,
        anchorX: anchorX,
        targetBaseline: targetBaseline,
      );
    }

    canvas.restore();
  }

  void _paintFragment(
    Canvas canvas,
    _GlyphFragment fragment, {
    required double anchorX,
    required double targetBaseline,
  }) {
    var opacity = fragment.opacity.value.clamp(0.0, 1.0);
    if (fragment.token.isDigit) {
      final travel =
          fragment.layout.scaledFontSize * _GlyphScene.travelFraction;
      if (travel > 0) {
        final remaining = (1 - fragment.y.value.abs() / travel).clamp(0.0, 1.0);
        opacity *= remaining * remaining * (3 - 2 * remaining);
      }
    }
    if (opacity <= 0.001 || fragment.token.rect.isEmpty) return;

    final tokenLeft = anchorX + fragment.x.value;
    final paragraphTop =
        targetBaseline - fragment.layout.alphabeticBaseline + fragment.y.value;
    final paintOffset = Offset(
      tokenLeft - fragment.token.rect.left,
      paragraphTop,
    );
    final tokenRect = fragment.token.rect.shift(paintOffset);

    // A rolling digit is blurred along the axis it travels, by the shutter time
    // its own speed would smear it over. A neutral arrival has no speed to read,
    // so its blur is tied to how far from settled it still is.
    final double sigmaX;
    final double sigmaY;
    if (fragment.isNeutral) {
      final sigma =
          fragment.layout.scaledFontSize *
          _GlyphScene.neutralBlurFraction *
          (1 - opacity);
      sigmaX = sigma;
      sigmaY = sigma;
    } else if (fragment.token.isDigit) {
      sigmaX = 0;
      sigmaY = math.min(
        fragment.layout.scaledFontSize * _GlyphScene.maxBlurFraction,
        fragment.y.velocity.abs() * _GlyphScene.blurShutter,
      );
    } else {
      sigmaX = 0;
      sigmaY = 0;
    }

    final sigma = math.max(sigmaX, sigmaY);
    final scale = fragment.scale.value;
    final needsLayer = opacity < 0.999 || sigma > 0.01;

    var layerRect = tokenRect;
    if (scale > 1) {
      layerRect = Rect.fromCenter(
        center: tokenRect.center,
        width: tokenRect.width * scale,
        height: tokenRect.height * scale,
      );
    }
    layerRect = layerRect.inflate(math.max(1, sigma * 3));

    if (needsLayer) {
      final layerPaint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, opacity);
      if (sigma > 0.01) {
        layerPaint.imageFilter = ui.ImageFilter.blur(
          sigmaX: sigmaX,
          sigmaY: sigmaY,
          tileMode: TileMode.decal,
        );
      }
      canvas.saveLayer(layerRect, layerPaint);
    } else {
      canvas.save();
    }

    // The clip is applied inside the scale so that the cell shrinks with the
    // glyph; applied outside it, a scaled glyph would be cropped by a box that
    // no longer fits it. The clip itself is not optional — the painter holds the
    // whole line, and each fragment may only show its own grapheme.
    if (scale != 1) {
      final center = tokenRect.center;
      canvas
        ..translate(center.dx, center.dy)
        ..scale(scale)
        ..translate(-center.dx, -center.dy);
    }
    canvas.clipRect(tokenRect);
    fragment.layout.painter.paint(canvas, paintOffset);
    canvas.restore();
  }

  @override
  void dispose() {
    _scene.removeListener(_handleSceneChanged);
    super.dispose();
  }
}
