import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:claralight_ui/claralight_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _boundaryKey = Key('numeric-text-boundary');
const _numberKey = Key('numeric-text');

Widget _host(
  Widget child, {
  bool disableAnimations = false,
  bool tickerEnabled = true,
  TextDirection textDirection = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
  TextStyle style = const TextStyle(
    color: Colors.white,
    fontSize: 32,
    height: 1.2,
  ),
}) {
  return MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      textScaler: textScaler,
    ),
    child: Directionality(
      textDirection: textDirection,
      child: TickerMode(
        enabled: tickerEnabled,
        child: DefaultTextStyle(
          style: style,
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );
}

Widget _boundary(Widget child, {double? width, double? height}) {
  return RepaintBoundary(
    key: _boundaryKey,
    child: SizedBox(width: width, height: height, child: child),
  );
}

Future<({Uint8List bytes, int width, int height})> _raster(
  WidgetTester tester,
) async {
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundaryKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final result = (
      bytes: data.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
    image.dispose();
    return result;
  }))!;
}

(double, double)? _alphaBoundsX(
  ({Uint8List bytes, int width, int height}) raster,
) {
  var left = raster.width;
  var right = -1;
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      final alpha = raster.bytes[(y * raster.width + x) * 4 + 3];
      if (alpha <= 8) continue;
      if (x < left) left = x;
      if (x > right) right = x;
    }
  }
  return right < 0 ? null : (left.toDouble(), right + 1.0);
}

Uint8List _columnSlice(
  ({Uint8List bytes, int width, int height}) raster,
  int start,
  int end,
) {
  final builder = BytesBuilder(copy: false);
  for (var y = 0; y < raster.height; y++) {
    final rowStart = (y * raster.width + start) * 4;
    final rowEnd = (y * raster.width + end) * 4;
    builder.add(raster.bytes.sublist(rowStart, rowEnd));
  }
  return builder.takeBytes();
}

int _maxByteDifference(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var maxDifference = 0;
  for (var index = 0; index < a.length; index++) {
    maxDifference = math.max(maxDifference, (a[index] - b[index]).abs());
  }
  return maxDifference;
}

int _alphaSum(
  ({Uint8List bytes, int width, int height}) raster,
  int start,
  int end,
) {
  var total = 0;
  for (var y = 0; y < raster.height; y++) {
    for (var x = start; x < end; x++) {
      total += raster.bytes[(y * raster.width + x) * 4 + 3];
    }
  }
  return total;
}

Future<Uint8List> _transitionFrame(
  WidgetTester tester, {
  required CLNumericTextTrend trend,
}) async {
  final value = ValueNotifier<num>(1);
  addTearDown(value.dispose);
  await tester.pumpWidget(
    _host(
      _boundary(
        SizedBox(
          width: 80,
          height: 60,
          child: ValueListenableBuilder<num>(
            valueListenable: value,
            builder: (context, current, child) => CLNumericText.number(
              current,
              key: _numberKey,
              trend: trend,
              alignment: Alignment.center,
            ),
          ),
        ),
        width: 80,
        height: 60,
      ),
    ),
  );
  value.value = 2;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 90));
  return (await _raster(tester)).bytes;
}

Future<Uint8List> _textTransitionFrame(
  WidgetTester tester, {
  required String from,
  required String to,
  required CLNumericTextTrend trend,
  Duration at = const Duration(milliseconds: 90),
}) async {
  // Unmount first, so the scene under test starts from `from` rather than from
  // whatever the previous call left animating behind the same key.
  await tester.pumpWidget(const SizedBox.shrink());

  final text = ValueNotifier<String>(from);
  addTearDown(text.dispose);
  await tester.pumpWidget(
    _host(
      _boundary(
        SizedBox(
          width: 120,
          height: 60,
          child: ValueListenableBuilder<String>(
            valueListenable: text,
            builder: (context, current, child) => CLNumericText(
              current,
              key: _numberKey,
              trend: trend,
              alignment: Alignment.center,
            ),
          ),
        ),
        width: 120,
        height: 60,
      ),
    ),
  );
  text.value = to;
  await tester.pump();
  await tester.pump(at);
  return (await _raster(tester)).bytes;
}

void main() {
  test('constructor rejects non-finite values', () {
    expect(() => CLNumericText.number(double.nan), throwsAssertionError);
    expect(() => CLNumericText.number(double.infinity), throwsAssertionError);
    expect(
      () => CLNumericText.number(double.negativeInfinity),
      throwsAssertionError,
    );
  });

  testWidgets('initial value is static, formatted, and semantic', (
    tester,
  ) async {
    var formatCalls = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        CLNumericText.number(
          12.5,
          key: _numberKey,
          formatter: (value) {
            formatCalls++;
            return '\$${value.toStringAsFixed(2)}';
          },
        ),
      ),
    );
    await tester.pump();

    expect(formatCalls, 1);
    expect(find.bySemanticsLabel(r'$12.50'), findsOneWidget);
    expect(tester.getSize(find.byKey(_numberKey)).width, greaterThan(0));
    expect(tester.binding.hasScheduledFrame, isFalse);
    semantics.dispose();
  });

  testWidgets('default tnum and explicit pnum match TextPainter metrics', (
    tester,
  ) async {
    const ambient = TextStyle(
      color: Colors.white,
      fontFamily: CLTypography.uiFamily,
      fontSize: 40,
      height: 1.2,
    );

    double expectedWidth(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: '1811', style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    await tester.pumpWidget(
      _host(const CLNumericText.number(1811, key: _numberKey), style: ambient),
    );
    final defaultWidth = tester.getSize(find.byKey(_numberKey)).width;
    expect(
      defaultWidth,
      closeTo(
        expectedWidth(
          ambient.copyWith(
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
        0.001,
      ),
    );

    const proportional = TextStyle(
      fontFeatures: [ui.FontFeature.proportionalFigures()],
    );
    await tester.pumpWidget(
      _host(
        const CLNumericText.number(
          1811,
          key: ValueKey('pnum-number'),
          style: proportional,
        ),
        style: ambient,
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('pnum-number'))).width,
      closeTo(expectedWidth(ambient.merge(proportional)), 0.001),
    );
  });

  testWidgets('formatter must return one line', (tester) async {
    await tester.pumpWidget(
      _host(CLNumericText.number(1, formatter: (_) => '1\n2')),
    );
    expect(tester.takeException(), isAssertionError);
  });

  testWidgets('changed value springs width without a first-frame jump', (
    tester,
  ) async {
    final value = ValueNotifier<num>(9);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, child) => CLNumericText.number(
            current,
            key: _numberKey,
            style: const TextStyle(
              fontFamily: CLTypography.monoFamily,
              fontSize: 40,
            ),
          ),
        ),
      ),
    );

    final initialWidth = tester.getSize(find.byKey(_numberKey)).width;
    value.value = 1000;
    await tester.pump();
    expect(
      tester.getSize(find.byKey(_numberKey)).width,
      closeTo(initialWidth, 0.001),
    );

    await tester.pump(const Duration(milliseconds: 100));
    final intermediateWidth = tester.getSize(find.byKey(_numberKey)).width;
    expect(intermediateWidth, greaterThan(initialWidth));

    await tester.pumpAndSettle();
    final finalWidth = tester.getSize(find.byKey(_numberKey)).width;
    expect(finalWidth, greaterThan(intermediateWidth));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('retargeting preserves the presented width and latest value', (
    tester,
  ) async {
    final value = ValueNotifier<num>(9);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, child) => CLNumericText.number(
            current,
            key: _numberKey,
            style: const TextStyle(
              fontFamily: CLTypography.monoFamily,
              fontSize: 40,
            ),
          ),
        ),
      ),
    );

    value.value = 9999;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final beforeRetarget = tester.getSize(find.byKey(_numberKey)).width;

    value.value = 99;
    await tester.pump();
    expect(
      tester.getSize(find.byKey(_numberKey)).width,
      closeTo(beforeRetarget, 0.001),
    );

    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('99'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('retargeting preserves current pixels on the command frame', (
    tester,
  ) async {
    final value = ValueNotifier<num>(9);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        _boundary(
          ValueListenableBuilder<num>(
            valueListenable: value,
            builder: (context, current, child) =>
                CLNumericText.number(current, alignment: Alignment.centerRight),
          ),
          width: 160,
          height: 60,
        ),
      ),
    );

    value.value = 999;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final beforeRetarget = await _raster(tester);

    value.value = 99;
    await tester.pump();
    final afterRetarget = await _raster(tester);
    expect(
      _maxByteDifference(beforeRetarget.bytes, afterRetarget.bytes),
      lessThanOrEqualTo(8),
    );
  });

  testWidgets('unchanged digits and decorations remain pixel-stable', (
    tester,
  ) async {
    final value = ValueNotifier<num>(129);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        _boundary(
          ValueListenableBuilder<num>(
            valueListenable: value,
            builder: (context, current, child) => CLNumericText.number(
              current,
              key: _numberKey,
              formatter: (number) => '\$$number%',
              alignment: Alignment.centerLeft,
              style: const TextStyle(
                fontFamily: CLTypography.monoFamily,
                fontSize: 40,
                letterSpacing: 16,
              ),
            ),
          ),
          width: 320,
          height: 64,
        ),
      ),
    );
    await tester.pump();
    final resting = await _raster(tester);
    final bounds = _alphaBoundsX(resting)!;
    final left = bounds.$1.floor();
    final right = bounds.$2.ceil();
    final span = right - left;
    final stableLeftEnd = left + (span * 0.35).floor();
    final stableRightStart = left + (span * 0.65).ceil();

    value.value = 139;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final moving = await _raster(tester);

    expect(
      _maxByteDifference(
        _columnSlice(moving, left, stableLeftEnd),
        _columnSlice(resting, left, stableLeftEnd),
      ),
      lessThanOrEqualTo(2),
    );
    expect(
      _maxByteDifference(
        _columnSlice(moving, stableRightStart, right),
        _columnSlice(resting, stableRightStart, right),
      ),
      lessThanOrEqualTo(2),
    );
    expect(
      _maxByteDifference(
        _columnSlice(moving, stableLeftEnd, stableRightStart),
        _columnSlice(resting, stableLeftEnd, stableRightStart),
      ),
      greaterThan(20),
    );
  });

  testWidgets('inserted and removed decoration cross-fades in place', (
    tester,
  ) async {
    final value = ValueNotifier<num>(0);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        _boundary(
          ValueListenableBuilder<num>(
            valueListenable: value,
            builder: (context, current, child) => CLNumericText.number(
              current,
              formatter: (number) => number == 0 ? r'$1' : r'$1%',
              alignment: Alignment.centerLeft,
              style: const TextStyle(letterSpacing: 10),
            ),
          ),
          width: 180,
          height: 60,
        ),
      ),
    );
    final initial = await _raster(tester);
    final initialRight = _alphaBoundsX(initial)!.$2.ceil();

    value.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final inserting = await _raster(tester);
    await tester.pumpAndSettle();
    final inserted = await _raster(tester);
    final finalRight = _alphaBoundsX(inserted)!.$2.ceil();
    final initialAlpha = _alphaSum(initial, initialRight, finalRight);
    final insertingAlpha = _alphaSum(inserting, initialRight, finalRight);
    final insertedAlpha = _alphaSum(inserted, initialRight, finalRight);

    expect(initialAlpha, 0);
    expect(insertingAlpha, inExclusiveRange(0, insertedAlpha));

    value.value = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final removingAlpha = _alphaSum(
      await _raster(tester),
      initialRight,
      finalRight,
    );
    expect(removingAlpha, inExclusiveRange(0, insertedAlpha));
  });

  testWidgets('explicit trend reverses the rendered transition direction', (
    tester,
  ) async {
    final increasing = await _transitionFrame(
      tester,
      trend: CLNumericTextTrend.increasing,
    );
    final decreasing = await _transitionFrame(
      tester,
      trend: CLNumericTextTrend.decreasing,
    );

    expect(decreasing, isNot(orderedEquals(increasing)));
  });

  testWidgets('mixed bidi formatting transitions without layout errors', (
    tester,
  ) async {
    final value = ValueNotifier<num>(129);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, child) => CLNumericText.number(
            current,
            key: _numberKey,
            formatter: (number) => 'المجموع ${number.toInt()} ر.س',
          ),
        ),
        textDirection: TextDirection.rtl,
      ),
    );

    value.value = 139;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('المجموع 139 ر.س'), findsOneWidget);
    expect(tester.getSize(find.byKey(_numberKey)).isFinite, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('same formatted output suppresses visual animation', (
    tester,
  ) async {
    final value = ValueNotifier<num>(1.1);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, child) => CLNumericText.number(
            current,
            key: _numberKey,
            formatter: (number) => number.floor().toString(),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(_numberKey));
    value.value = 1.8;
    await tester.pump();

    expect(tester.getSize(find.byKey(_numberKey)), size);
    expect(find.bySemanticsLabel('1'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('same value reformatting snaps immediately', (tester) async {
    final expanded = ValueNotifier(false);
    addTearDown(expanded.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<bool>(
          valueListenable: expanded,
          builder: (context, useExpandedFormat, child) => CLNumericText.number(
            7,
            key: _numberKey,
            formatter: useExpandedFormat ? (_) => r'$7,000.00' : null,
          ),
        ),
      ),
    );

    final compactWidth = tester.getSize(find.byKey(_numberKey)).width;
    expanded.value = true;
    await tester.pump();

    expect(
      tester.getSize(find.byKey(_numberKey)).width,
      greaterThan(compactWidth),
    );
    expect(find.bySemanticsLabel(r'$7,000.00'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('layout-context and value changes snap together', (tester) async {
    final expanded = ValueNotifier(false);
    addTearDown(expanded.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<bool>(
          valueListenable: expanded,
          builder: (context, large, child) => CLNumericText.number(
            large ? 1000 : 1,
            key: _numberKey,
            style: TextStyle(fontSize: large ? 48 : 20),
          ),
        ),
      ),
    );

    final smallSize = tester.getSize(find.byKey(_numberKey));
    expanded.value = true;
    await tester.pump();
    final largeSize = tester.getSize(find.byKey(_numberKey));

    expect(largeSize.width, greaterThan(smallSize.width));
    expect(largeSize.height, greaterThan(smallSize.height));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion replaces values immediately', (tester) async {
    final value = ValueNotifier<num>(9);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, child) =>
              CLNumericText.number(current, key: _numberKey),
        ),
        disableAnimations: true,
      ),
    );

    final initialWidth = tester.getSize(find.byKey(_numberKey)).width;
    value.value = 1000;
    await tester.pump();
    final finalWidth = tester.getSize(find.byKey(_numberKey)).width;

    expect(finalWidth, greaterThan(initialWidth));
    expect(find.bySemanticsLabel('1000'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getSize(find.byKey(_numberKey)).width, finalWidth);
  });

  testWidgets('enabling reduced motion commits an in-flight target', (
    tester,
  ) async {
    final value = ValueNotifier<num>(9);
    final reduced = ValueNotifier(false);
    addTearDown(value.dispose);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: reduced,
        builder: (context, disableAnimations, child) => _host(
          ValueListenableBuilder<num>(
            valueListenable: value,
            builder: (context, current, child) =>
                CLNumericText.number(current, key: _numberKey),
          ),
          disableAnimations: disableAnimations,
        ),
      ),
    );

    value.value = 1000;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final inFlightWidth = tester.getSize(find.byKey(_numberKey)).width;

    reduced.value = true;
    await tester.pump();
    final snappedWidth = tester.getSize(find.byKey(_numberKey)).width;
    expect(snappedWidth, greaterThan(inFlightWidth));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('disabled TickerMode commits hidden updates without replay', (
    tester,
  ) async {
    final value = ValueNotifier<num>(9);
    final ticking = ValueNotifier(true);
    addTearDown(value.dispose);
    addTearDown(ticking.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: ticking,
        builder: (context, enabled, child) => _host(
          ValueListenableBuilder<num>(
            valueListenable: value,
            builder: (context, current, child) =>
                CLNumericText.number(current, key: _numberKey),
          ),
          tickerEnabled: enabled,
        ),
      ),
    );

    ticking.value = false;
    value.value = 1000;
    await tester.pump();
    final hiddenWidth = tester.getSize(find.byKey(_numberKey)).width;
    expect(find.bySemanticsLabel('1000'), findsOneWidget);

    ticking.value = true;
    await tester.pump();
    expect(tester.getSize(find.byKey(_numberKey)).width, hiddenWidth);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('semantics expose only the latest value during transition', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final value = ValueNotifier<num>(10);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, child) => CLNumericText.number(
            current,
            key: _numberKey,
            semanticsLabel: 'Total $current',
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Total 10'), findsOneWidget);
    value.value = 20;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.bySemanticsLabel('Total 10'), findsNothing);
    expect(find.bySemanticsLabel('Total 20'), findsOneWidget);
    final node = tester.getSemantics(find.byKey(_numberKey));
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
    semantics.dispose();
  });

  testWidgets('alignment anchors content inside fixed bounds and follows RTL', (
    tester,
  ) async {
    Future<(double, double)> boundsFor({
      required AlignmentGeometry alignment,
      TextDirection direction = TextDirection.ltr,
    }) async {
      await tester.pumpWidget(
        _host(
          _boundary(
            CLNumericText.number(42, key: _numberKey, alignment: alignment),
            width: 200,
            height: 60,
          ),
          textDirection: direction,
        ),
      );
      return _alphaBoundsX(await _raster(tester))!;
    }

    final start = await boundsFor(alignment: AlignmentDirectional.centerStart);
    final end = await boundsFor(alignment: AlignmentDirectional.centerEnd);
    final rtlEnd = await boundsFor(
      alignment: AlignmentDirectional.centerEnd,
      direction: TextDirection.rtl,
    );

    expect(start.$1, lessThan(10));
    expect(end.$2, greaterThan(190));
    expect(rtlEnd.$1, lessThan(10));
  });

  testWidgets('text scaling changes metrics and baseline aligns with Text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: const [
            Text('A', key: Key('baseline-text')),
            CLNumericText.number(42, key: _numberKey),
          ],
        ),
        textScaler: TextScaler.linear(1.5),
      ),
    );

    final textBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('baseline-text')),
    );
    final numberBox = tester.renderObject<RenderBox>(find.byKey(_numberKey));
    final textBaseline = textBox.localToGlobal(
      Offset(
        0,
        textBox.getDryBaseline(textBox.constraints, TextBaseline.alphabetic)!,
      ),
    );
    final numberBaseline = numberBox.localToGlobal(
      Offset(
        0,
        numberBox.getDryBaseline(
          numberBox.constraints,
          TextBaseline.alphabetic,
        )!,
      ),
    );

    expect(numberBaseline.dy, closeTo(textBaseline.dy, 0.001));
    expect(tester.getSize(find.byKey(_numberKey)).height, greaterThan(40));
  });

  testWidgets('rapid updates remain bounded and converge without residue', (
    tester,
  ) async {
    final value = ValueNotifier<num>(0);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        _boundary(
          ValueListenableBuilder<num>(
            valueListenable: value,
            builder: (context, current, child) => CLNumericText.number(
              current,
              key: _numberKey,
              alignment: Alignment.center,
            ),
          ),
          width: 120,
          height: 60,
        ),
      ),
    );

    for (var next = 1; next <= 80; next++) {
      value.value = next;
      await tester.pump(const Duration(milliseconds: 15));
    }
    expect(find.bySemanticsLabel('80'), findsOneWidget);

    await tester.pumpAndSettle();
    final settled = await _raster(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(
      _host(
        _boundary(
          const CLNumericText.number(
            80,
            key: ValueKey('fresh-static-number'),
            alignment: Alignment.center,
          ),
          width: 120,
          height: 60,
        ),
      ),
    );
    final fresh = await _raster(tester);
    expect(
      _maxByteDifference(settled.bytes, fresh.bytes),
      lessThanOrEqualTo(1),
    );
  });

  testWidgets('a shared prefix and suffix hold while the middle changes', (
    tester,
  ) async {
    final text = ValueNotifier<String>('AA-BB-CC');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      _host(
        _boundary(
          ValueListenableBuilder<String>(
            valueListenable: text,
            builder: (context, current, child) => CLNumericText(
              current,
              alignment: Alignment.centerLeft,
              style: const TextStyle(fontSize: 20, height: 1.2),
            ),
          ),
          width: 200,
          height: 40,
        ),
      ),
    );
    final resting = await _raster(tester);

    text.value = 'AA-XX-CC';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    final moving = await _raster(tester);

    // `AA-` and `-CC` are the shared prefix and suffix; only the two graphemes
    // between them may move. The gutters stop short of the changing pair so the
    // neutral entrance's blur is not mistaken for instability.
    expect(
      _maxByteDifference(
        _columnSlice(moving, 0, 52),
        _columnSlice(resting, 0, 52),
      ),
      lessThanOrEqualTo(2),
    );
    expect(
      _maxByteDifference(
        _columnSlice(moving, 108, 160),
        _columnSlice(resting, 108, 160),
      ),
      lessThanOrEqualTo(2),
    );
    expect(
      _maxByteDifference(
        _columnSlice(moving, 60, 100),
        _columnSlice(resting, 60, 100),
      ),
      greaterThan(20),
    );
  });

  testWidgets('a run flush with neither end survives the change', (
    tester,
  ) async {
    final text = ValueNotifier<String>('1abc9');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      _host(
        _boundary(
          ValueListenableBuilder<String>(
            valueListenable: text,
            builder: (context, current, child) => CLNumericText(
              current,
              alignment: Alignment.centerLeft,
              style: const TextStyle(fontSize: 20, height: 1.2),
            ),
          ),
          width: 200,
          height: 40,
        ),
      ),
    );
    final resting = await _raster(tester);

    text.value = '2abc8';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    final moving = await _raster(tester);

    // Neither end matches, so `abc` is only held by the middle run. Prefix and
    // suffix matching alone would have cross-faded all five graphemes.
    expect(
      _maxByteDifference(
        _columnSlice(moving, 22, 78),
        _columnSlice(resting, 22, 78),
      ),
      lessThanOrEqualTo(2),
    );
    expect(
      _maxByteDifference(
        _columnSlice(moving, 0, 20),
        _columnSlice(resting, 0, 20),
      ),
      greaterThan(20),
    );
    expect(
      _maxByteDifference(
        _columnSlice(moving, 80, 100),
        _columnSlice(resting, 80, 100),
      ),
      greaterThan(20),
    );
  });

  testWidgets('arbitrary text transitions and settles', (tester) async {
    final text = ValueNotifier<String>('Off');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<String>(
          valueListenable: text,
          builder: (context, current, child) =>
              CLNumericText(current, key: _numberKey),
        ),
      ),
    );

    final initialWidth = tester.getSize(find.byKey(_numberKey)).width;
    expect(find.bySemanticsLabel('Off'), findsOneWidget);

    text.value = 'On';
    await tester.pump();
    expect(
      tester.getSize(find.byKey(_numberKey)).width,
      closeTo(initialWidth, 0.001),
    );
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(find.bySemanticsLabel('On'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(_numberKey)).width,
      lessThan(initialWidth),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('entering graphemes are staggered along the line', (
    tester,
  ) async {
    final text = ValueNotifier<String>('A');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      _host(
        _boundary(
          SizedBox(
            width: 200,
            height: 40,
            child: ValueListenableBuilder<String>(
              valueListenable: text,
              builder: (context, current, child) => CLNumericText(
                current,
                alignment: Alignment.centerLeft,
                style: const TextStyle(fontSize: 20, height: 1.2),
              ),
            ),
          ),
          width: 200,
          height: 40,
        ),
      ),
    );

    text.value = 'ABCDEFGH';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    final early = await _raster(tester);

    // Three stagger steps in, the head of the new run has begun to arrive and
    // its tail has not been released yet.
    expect(_alphaSum(early, 20, 80), greaterThan(0));
    expect(_alphaSum(early, 100, 160), 0);

    await tester.pumpAndSettle();
    final settled = await _raster(tester);
    expect(_alphaSum(settled, 100, 160), greaterThan(0));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('automatic trend rolls numbers and stays neutral for words', (
    tester,
  ) async {
    final automaticNumber = await _textTransitionFrame(
      tester,
      from: '1',
      to: '2',
      trend: CLNumericTextTrend.automatic,
    );
    final risingNumber = await _textTransitionFrame(
      tester,
      from: '1',
      to: '2',
      trend: CLNumericTextTrend.increasing,
    );

    // A string a number can be read out of still has a direction, so automatic
    // and the explicit trend render the same frame.
    expect(automaticNumber, orderedEquals(risingNumber));

    final automaticWord = await _textTransitionFrame(
      tester,
      from: 'Off',
      to: 'On',
      trend: CLNumericTextTrend.automatic,
    );
    final risingWord = await _textTransitionFrame(
      tester,
      from: 'Off',
      to: 'On',
      trend: CLNumericTextTrend.increasing,
    );

    // `Off` is neither larger nor smaller than `On`, so automatic declines to
    // roll and the forced trend is visibly a different transition.
    expect(automaticWord, isNot(orderedEquals(risingWord)));
  });

  testWidgets('the deprecated number-first spelling still transitions', (
    tester,
  ) async {
    final value = ValueNotifier<num>(9);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<num>(
          valueListenable: value,
          builder: (context, current, child) =>
              // ignore: deprecated_member_use_from_same_package
              CLAnimatedNumber(
                current,
                key: _numberKey,
                formatter: (number) => '${number.toInt()}%',
              ),
        ),
      ),
    );

    final initialWidth = tester.getSize(find.byKey(_numberKey)).width;
    expect(find.bySemanticsLabel('9%'), findsOneWidget);

    value.value = 1000;
    await tester.pump();
    expect(
      tester.getSize(find.byKey(_numberKey)).width,
      closeTo(initialWidth, 0.001),
    );

    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('1000%'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(_numberKey)).width,
      greaterThan(initialWidth),
    );
  });

  testWidgets('a grouped number rolls only the digit that changed', (
    tester,
  ) async {
    final value = ValueNotifier<num>(1000);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        _boundary(
          ValueListenableBuilder<num>(
            valueListenable: value,
            builder: (context, current, child) => CLNumericText.number(
              current,
              formatter: (number) =>
                  '${number ~/ 1000},${(number % 1000).toInt().toString().padLeft(3, '0')}',
              alignment: Alignment.centerLeft,
              style: const TextStyle(fontSize: 20, height: 1.2),
            ),
          ),
          width: 200,
          height: 40,
        ),
      ),
    );
    final resting = await _raster(tester);

    value.value = 1001;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    final moving = await _raster(tester);

    // `1,00` is the shared prefix, and the units digit is the only column the
    // place rule lets change. The separator in particular must not drift.
    expect(
      _maxByteDifference(
        _columnSlice(moving, 0, 80),
        _columnSlice(resting, 0, 80),
      ),
      lessThanOrEqualTo(2),
    );
    expect(
      _maxByteDifference(
        _columnSlice(moving, 80, 100),
        _columnSlice(resting, 80, 100),
      ),
      greaterThan(20),
    );
  });

  testWidgets('digits keep their decimal place as the number grows', (
    tester,
  ) async {
    final value = ValueNotifier<num>(99);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _host(
        _boundary(
          SizedBox(
            width: 200,
            height: 40,
            child: ValueListenableBuilder<num>(
              valueListenable: value,
              builder: (context, current, child) => CLNumericText.number(
                current,
                alignment: Alignment.centerLeft,
                style: const TextStyle(fontSize: 20, height: 1.2),
              ),
            ),
          ),
          width: 200,
          height: 40,
        ),
      ),
    );

    final resting = await _raster(tester);

    value.value = 999;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    final moving = await _raster(tester);

    // Both old nines belong to the units and tens columns, so growing to three
    // digits slides them one column right and brings the new digit into the
    // hundreds column that opens up on the left. Pairing by position instead
    // would have left the first two sitting still — so the leftmost column is
    // exactly what must not be stable here.
    expect(
      _maxByteDifference(
        _columnSlice(moving, 0, 20),
        _columnSlice(resting, 0, 20),
      ),
      greaterThan(20),
    );

    await tester.pumpAndSettle();
    final settled = await _raster(tester);
    await tester.pumpWidget(
      _host(
        _boundary(
          const SizedBox(
            width: 200,
            height: 40,
            child: CLNumericText.number(
              999,
              alignment: Alignment.centerLeft,
              style: TextStyle(fontSize: 20, height: 1.2),
            ),
          ),
          width: 200,
          height: 40,
        ),
      ),
    );
    expect(
      _maxByteDifference(settled.bytes, (await _raster(tester)).bytes),
      lessThanOrEqualTo(1),
    );
  });
}
