import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:claralight_ui/claralight_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

const _barKey = Key('progress-bar');
const _boundaryKey = Key('progress-boundary');
const _accentColor = Color(0xFFFF0000);
const _trackColor = Color(0xFF0000FF);
const _barWidth = 120.0;
const _barHeight = 10.0;
const _gap = 4.0;

/// What a pixel is: the indicator, the track, or the ground behind the rail.
enum _Ink { accent, track, none }

Widget _host(
  Widget child, {
  bool disableAnimations = false,
  bool tickerEnabled = true,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: textDirection,
      child: TickerMode(
        enabled: tickerEnabled,
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );
}

Widget _bar(double? value, {double height = _barHeight}) {
  return RepaintBoundary(
    key: _boundaryKey,
    child: SizedBox(
      width: _barWidth,
      child: CLProgressBar(
        key: _barKey,
        value: value,
        height: height,
        color: _accentColor,
        trackColor: _trackColor,
      ),
    ),
  );
}

Widget _ring(
  double? value, {
  CLProgressSize size = CLProgressSize.large,
  Widget? child,
}) {
  return RepaintBoundary(
    key: _boundaryKey,
    child: CLProgressRing(
      value: value,
      size: size,
      color: _accentColor,
      trackColor: _trackColor,
      child: child,
    ),
  );
}

/// The painted rail, one [_Ink] per pixel.
class _Raster {
  _Raster(this.width, this.height, this._pixels);

  final int width;
  final int height;
  final List<_Ink> _pixels;

  _Ink at(int x, int y) => _pixels[y * width + x];

  /// The ink along a row, sampled at the rail's centre line by default.
  List<_Ink> row([int? y]) {
    final line = y ?? height ~/ 2;
    return List<_Ink>.generate(width, (x) => at(x, line));
  }

  bool get hasTrack => _pixels.contains(_Ink.track);
  bool get hasAccent => _pixels.contains(_Ink.accent);
}

Future<_Raster> _raster(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundaryKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = List<_Ink>.generate(image.width * image.height, (index) {
      final offset = index * 4;
      final red = bytes.getUint8(offset);
      final blue = bytes.getUint8(offset + 2);
      // Half coverage or better, so an antialiased edge lands on one side of
      // the boundary rather than widening every span by a pixel.
      if (red > 127 && red > blue) return _Ink.accent;
      if (blue > 127 && blue > red) return _Ink.track;
      return _Ink.none;
    });
    image.dispose();
    return _Raster(image.width, image.height, pixels);
  }))!;
}

/// A run of one kind of ink along a row, in pixels from the start edge.
typedef _Span = (_Ink, double, double);

Future<List<_Span>> _spans(WidgetTester tester, {int? y}) async {
  final row = (await _raster(tester)).row(y);
  final spans = <_Span>[];
  var start = 0;
  for (var x = 1; x <= row.length; x++) {
    if (x < row.length && row[x] == row[start]) continue;
    if (row[start] != _Ink.none) {
      spans.add((row[start], start.toDouble(), x.toDouble()));
    }
    start = x;
  }
  return spans;
}

Future<List<_Span>> _inkSpans(WidgetTester tester, _Ink ink) async {
  return (await _spans(tester)).where((span) => span.$1 == ink).toList();
}

/// The one accent run on a determinate rail.
Future<(double, double)> _accentBounds(WidgetTester tester) async {
  final accents = await _inkSpans(tester, _Ink.accent);
  expect(accents, hasLength(1), reason: 'The indicator must be one shape');
  return (accents.single.$2, accents.single.$3);
}

/// Where the indeterminate figure's leading edge has reached.
Future<double> _leadingEdge(WidgetTester tester) async {
  final accents = await _inkSpans(tester, _Ink.accent);
  expect(accents, isNotEmpty, reason: 'The indicator must be visible');
  return accents.last.$3;
}

void _expectSpan((double, double) span, double start, double end) {
  expect(span.$1, closeTo(start, 1));
  expect(span.$2, closeTo(end, 1));
}

Future<void> _runCycle(WidgetTester tester, Widget host) async {
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// The ink at [angle] on the ring's stroke centre line, measured clockwise from
/// twelve o'clock.
_Ink _ringInkAt(_Raster raster, double degrees, double radius) {
  final radians = (degrees - 90) * math.pi / 180;
  final center = raster.width / 2;
  final x = (center + radius * math.cos(radians)).round();
  final y = (center + radius * math.sin(radians)).round();
  return raster.at(x.clamp(0, raster.width - 1), y.clamp(0, raster.height - 1));
}

void main() {
  late Duration originalUpdateInterval;

  setUpAll(() {
    originalUpdateInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDownAll(() {
    VisibilityDetectorController.instance.updateInterval =
        originalUpdateInterval;
  });

  group('determinate bar', () {
    testWidgets('is an indicator and a track with the gap between them', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_bar(0.5), disableAnimations: true));
      await tester.pump();

      final spans = await _spans(tester);
      expect(spans, hasLength(2));
      expect(spans[0].$1, _Ink.accent);
      expect(spans[1].$1, _Ink.track);
      _expectSpan((spans[0].$2, spans[0].$3), 0, 60);
      // The track backs off by the gap and keeps the rail's far end.
      _expectSpan((spans[1].$2, spans[1].$3), 60 + _gap, _barWidth);
    });

    testWidgets('the gap collapses at both ends of the range', (tester) async {
      await tester.pumpWidget(_host(_bar(0), disableAnimations: true));
      await tester.pump();
      var spans = await _spans(tester);
      expect(spans.map((span) => span.$1), [_Ink.track]);
      // Nothing to back away from, so the track starts at the rail's edge.
      _expectSpan((spans.single.$2, spans.single.$3), 0, _barWidth);

      await tester.pumpWidget(_host(_bar(1), disableAnimations: true));
      await tester.pump();
      spans = await _spans(tester);
      expect(spans.map((span) => span.$1), [_Ink.accent]);
      _expectSpan((spans.single.$2, spans.single.$3), 0, _barWidth);
    });

    testWidgets('a segment with no room left for the gap keeps what it has', (
      tester,
    ) async {
      // Two pixels of indicator: less than the gap, so the track takes the two
      // pixels of clearance that exist rather than being pushed off the rail.
      await tester.pumpWidget(
        _host(_bar(2 / _barWidth), disableAnimations: true),
      );
      await tester.pump();

      final spans = await _spans(tester);
      expect(spans.map((span) => span.$1), [_Ink.accent, _Ink.track]);
      _expectSpan((spans[0].$2, spans[0].$3), 0, 2);
      _expectSpan((spans[1].$2, spans[1].$3), 4, _barWidth);
    });

    testWidgets('a segment shorter than the rail is thick leaves as a dot', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_bar(4 / _barWidth), disableAnimations: true),
      );
      await tester.pump();

      final raster = await _raster(tester);
      final column = List<_Ink>.generate(
        raster.height,
        (y) => raster.at(2, y),
      ).where((ink) => ink == _Ink.accent).length;
      // Four pixels long, so four tall and centred — a circle, not a sliver
      // standing the full height of the rail.
      expect(column, lessThanOrEqualTo(5));
      expect(column, greaterThanOrEqualTo(3));
      expect(raster.at(2, 0), _Ink.none);
      expect(raster.at(2, raster.height - 1), _Ink.none);
    });

    testWidgets('grows from the end edge in RTL', (tester) async {
      await tester.pumpWidget(
        _host(
          _bar(0.25),
          disableAnimations: true,
          textDirection: TextDirection.rtl,
        ),
      );
      await tester.pump();

      final spans = await _spans(tester);
      expect(spans.map((span) => span.$1), [_Ink.track, _Ink.accent]);
      _expectSpan((spans[0].$2, spans[0].$3), 0, 90 - _gap);
      _expectSpan((spans[1].$2, spans[1].$3), 90, _barWidth);
    });

    testWidgets('value changes run on the language\'s quick transition', (
      tester,
    ) async {
      final value = ValueNotifier(0.1);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<double>(
            valueListenable: value,
            builder: (context, progress, child) => _bar(progress),
          ),
        ),
      );

      final animation = tester.widget<TweenAnimationBuilder<double>>(
        find.descendant(
          of: find.byType(CLProgressBar),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
      );
      expect(animation.duration, CLMotion.fast);
      expect(animation.curve, CLMotion.easeOut);

      _expectSpan(await _accentBounds(tester), 0, 12);
      value.value = 0.9;
      await tester.pump();
      _expectSpan(await _accentBounds(tester), 0, 12);

      // Retargeting mid-flight starts from the painted edge, not from zero.
      await tester.pump(const Duration(milliseconds: 60));
      final inFlight = await _accentBounds(tester);
      expect(inFlight.$2, allOf(greaterThan(12), lessThan(108)));
      value.value = 0.2;
      await tester.pump();
      expect((await _accentBounds(tester)).$2, closeTo(inFlight.$2, 1));

      await tester.pump(CLMotion.fast);
      _expectSpan(await _accentBounds(tester), 0, 24);
    });

    testWidgets('reduced motion snaps the value and schedules no frames', (
      tester,
    ) async {
      final value = ValueNotifier(0.2);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<double>(
            valueListenable: value,
            builder: (context, progress, child) => _bar(progress),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      _expectSpan(await _accentBounds(tester), 0, 24);

      value.value = 0.8;
      await tester.pump();
      _expectSpan(await _accentBounds(tester), 0, 96);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('semantics report the value, and nothing when there is none', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_bar(0.42)));
      expect(
        tester
            .getSemantics(
              find.descendant(
                of: find.byType(CLProgressBar),
                matching: find.byType(Semantics),
              ),
            )
            .value,
        '42%',
      );

      await tester.pumpWidget(_host(_bar(null)));
      await tester.pump();
      expect(
        tester
            .getSemantics(
              find.descendant(
                of: find.byType(CLProgressBar),
                matching: find.byType(Semantics),
              ),
            )
            .value,
        isEmpty,
      );
    });

    testWidgets('the thickness ladder is the size step', (tester) async {
      for (final (size, thickness) in [
        (CLProgressSize.small, 2.0),
        (CLProgressSize.medium, 4.0),
        (CLProgressSize.large, 8.0),
      ]) {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: _barWidth,
              child: CLProgressBar(value: 0.5, size: size),
            ),
          ),
        );
        expect(tester.getSize(find.byType(CLProgressBar)).height, thickness);
      }
    });
  });

  group('indeterminate bar', () {
    testWidgets('starts as a full track and returns to one', (tester) async {
      await tester.pumpWidget(_host(_bar(null)));
      await tester.pump();

      var spans = await _spans(tester);
      expect(spans.map((span) => span.$1), [_Ink.track]);
      _expectSpan((spans.single.$2, spans.single.$3), 0, _barWidth);

      // One cycle later the two lines have left the rail and it is whole again.
      await tester.pump(const Duration(milliseconds: 1750));
      spans = await _spans(tester);
      expect(spans.map((span) => span.$1), [_Ink.track]);
      _expectSpan((spans.single.$2, spans.single.$3), 0, _barWidth);
    });

    testWidgets('sends two lines across the rail, in order, per cycle', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_bar(null)));
      await tester.pump();

      var seenTwoLines = false;
      var previousLeadingEdge = 0.0;
      for (var elapsed = 50; elapsed < 1700; elapsed += 50) {
        await tester.pump(const Duration(milliseconds: 50));
        final spans = await _spans(tester);
        final accents = spans.where((span) => span.$1 == _Ink.accent).toList();
        expect(accents.length, lessThanOrEqualTo(2));
        if (accents.length == 2) seenTwoLines = true;

        // Every stretch of track is bounded by whichever line is nearest it, so
        // the row is a chain: no two runs of the same ink ever touch, and the
        // ink alternates.
        for (var i = 1; i < spans.length; i++) {
          expect(spans[i].$1, isNot(spans[i - 1].$1));
          expect(spans[i].$2 - spans[i - 1].$3, greaterThan(0));
        }

        if (accents.isNotEmpty) {
          final leadingEdge = accents.last.$3;
          // The leading line only ever moves towards the end edge, until it
          // leaves the rail and the one behind it becomes the leading edge.
          if (leadingEdge >= previousLeadingEdge) {
            previousLeadingEdge = leadingEdge;
          } else {
            expect(previousLeadingEdge, closeTo(_barWidth, 1));
            previousLeadingEdge = leadingEdge;
          }
        }
      }
      expect(seenTwoLines, isTrue);
    });

    testWidgets('keeps the gap off the track while the lines travel', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_bar(null)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final spans = await _spans(tester);
      expect(spans.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < spans.length; i++) {
        final clearance = spans[i].$2 - spans[i - 1].$3;
        // Either the full gap, or whatever room a segment running out of the
        // rail has left.
        expect(clearance, lessThanOrEqualTo(_gap + 1));
        expect(clearance, greaterThan(0));
      }
    });

    testWidgets('keeps running under reduced motion', (tester) async {
      // Every other loop in Claralight stops under the preference; this one
      // cannot, because a bar that stops moving reads as work that finished.
      await _runCycle(tester, _host(_bar(null), disableAnimations: true));

      final before = await _leadingEdge(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(await _leadingEdge(tester), greaterThan(before));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('a disabled TickerMode holds and resumes the phase', (
      tester,
    ) async {
      final tickerEnabled = ValueNotifier(true);
      addTearDown(tickerEnabled.dispose);
      await _runCycle(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: tickerEnabled,
          builder: (context, enabled, child) =>
              _host(_bar(null), tickerEnabled: enabled),
        ),
      );

      final before = await _leadingEdge(tester);
      tickerEnabled.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await _leadingEdge(tester), closeTo(before, 1));

      tickerEnabled.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(await _leadingEdge(tester), greaterThan(before));
    });

    testWidgets('a paused app holds and resumes the phase', (tester) async {
      await _runCycle(tester, _host(_bar(null)));

      final before = await _leadingEdge(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await _leadingEdge(tester), closeTo(before, 1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(await _leadingEdge(tester), greaterThan(before));
    });

    testWidgets('leaving the viewport holds and resumes the phase', (
      tester,
    ) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await _runCycle(
        tester,
        _host(
          SizedBox(
            width: _barWidth,
            height: 40,
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [_bar(null), const SizedBox(height: 400)],
              ),
            ),
          ),
        ),
      );

      final before = await _leadingEdge(tester);
      scrollController.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      scrollController.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(await _leadingEdge(tester), closeTo(before, 2));
    });

    testWidgets('becoming indeterminate waits for the visibility report', (
      tester,
    ) async {
      final controller = VisibilityDetectorController.instance;
      controller.updateInterval = const Duration(days: 1);
      final value = ValueNotifier<double?>(0.4);
      addTearDown(value.dispose);

      try {
        await tester.pumpWidget(
          _host(
            ValueListenableBuilder<double?>(
              valueListenable: value,
              builder: (context, progress, child) => _bar(progress),
            ),
          ),
        );
        value.value = null;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect((await _raster(tester)).hasAccent, isFalse);

        controller.notifyNow();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect((await _raster(tester)).hasAccent, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.updateInterval = Duration.zero;
        controller.notifyNow();
      }
    });
  });

  group('ring', () {
    testWidgets('the size ladder is the stroke centre line plus a stroke', (
      tester,
    ) async {
      for (final (size, box) in [
        (CLProgressSize.small, 16.0),
        (CLProgressSize.medium, 24.0),
        (CLProgressSize.large, 40.0),
      ]) {
        await tester.pumpWidget(
          _host(CLProgressRing(value: 0.5, size: size)),
        );
        expect(
          tester.getSize(find.byType(CLProgressRing)),
          Size(box, box),
          reason: '$size',
        );
      }
    });

    testWidgets('starts at twelve o\'clock and backs the track off at both '
        'ends', (tester) async {
      await tester.pumpWidget(_host(_ring(0.5), disableAnimations: true));
      await tester.pump();

      final raster = await _raster(tester);
      const radius = 18.0;
      // Half the ring, clockwise from the top: twelve o'clock through six.
      expect(_ringInkAt(raster, 0, radius), _Ink.accent);
      expect(_ringInkAt(raster, 90, radius), _Ink.accent);
      expect(_ringInkAt(raster, 175, radius), _Ink.accent);
      // Both ends of the track stand off the same indicator by the same
      // amount, so the ring past either of the indicator's caps is neither.
      expect(_ringInkAt(raster, 195, radius), _Ink.none);
      expect(_ringInkAt(raster, 270, radius), _Ink.track);
      expect(_ringInkAt(raster, 350, radius), _Ink.none);
    });

    testWidgets('an empty ring is all track and a full one is all indicator', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_ring(0), disableAnimations: true));
      await tester.pump();
      var raster = await _raster(tester);
      expect(raster.hasAccent, isFalse);
      // Nothing to back away from: the track is the whole ring.
      for (final degrees in [0, 90, 180, 270]) {
        expect(_ringInkAt(raster, degrees.toDouble(), 18), _Ink.track);
      }

      await tester.pumpWidget(_host(_ring(1), disableAnimations: true));
      await tester.pump();
      raster = await _raster(tester);
      expect(raster.hasTrack, isFalse);
      for (final degrees in [0, 90, 180, 270]) {
        expect(_ringInkAt(raster, degrees.toDouble(), 18), _Ink.accent);
      }
    });

    testWidgets('the indeterminate ring draws no track and keeps turning', (
      tester,
    ) async {
      await _runCycle(tester, _host(_ring(null)));

      final raster = await _raster(tester);
      expect(raster.hasTrack, isFalse);
      expect(raster.hasAccent, isTrue);

      // The arc breathes and the ring turns, so the ink under a fixed point on
      // the circle changes within a cycle.
      var changed = false;
      for (var elapsed = 0; elapsed < 6000 && !changed; elapsed += 250) {
        await tester.pump(const Duration(milliseconds: 250));
        final next = await _raster(tester);
        for (var degrees = 0; degrees < 360; degrees += 15) {
          if (_ringInkAt(next, degrees.toDouble(), 18) !=
              _ringInkAt(raster, degrees.toDouble(), 18)) {
            changed = true;
            break;
          }
        }
      }
      expect(changed, isTrue);
    });

    testWidgets('value changes run on the same transition as the bar', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_ring(0.4)));

      final animation = tester.widget<TweenAnimationBuilder<double>>(
        find.descendant(
          of: find.byType(CLProgressRing),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
      );
      expect(animation.duration, CLMotion.fast);
      expect(animation.curve, CLMotion.easeOut);
    });

    testWidgets('reports the value and centres its child', (tester) async {
      await tester.pumpWidget(
        _host(
          _ring(
            0.42,
            child: const Text('42', textDirection: TextDirection.ltr),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester
            .getSemantics(
              find.descendant(
                of: find.byType(CLProgressRing),
                matching: find.byType(Semantics),
              ),
            )
            .value,
        '42%',
      );
      expect(
        tester.getCenter(find.text('42')),
        tester.getCenter(find.byType(CLProgressRing)),
      );
    });
  });
}
