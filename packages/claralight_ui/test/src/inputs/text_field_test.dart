import 'dart:math' as math;

import 'package:claralight_ui/claralight_ui.dart';
import 'package:claralight_ui/src/inputs/numeric_scrub_cursor.dart';
import 'package:claralight_ui/src/overlays/anchored_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNumericScrubCursorBackend implements NumericScrubCursorBackend {
  _FakeNumericScrubCursorBackend({
    this.isSupported = true,
    this.scale = 1,
    math.Point<double>? position,
  }) : position = position ?? const math.Point<double>(320, 240);

  @override
  final bool isSupported;
  final double scale;
  math.Point<double> position;
  final moves = <math.Point<double>>[];
  int getPositionCalls = 0;
  bool throwOnGet = false;
  bool throwOnMove = false;
  bool ignoreMoves = false;

  @override
  math.Point<double> getPosition() {
    getPositionCalls++;
    if (throwOnGet) throw StateError('cursor unavailable');
    return position;
  }

  @override
  double logicalToSystemScale(double devicePixelRatio) => scale;

  @override
  void moveTo(math.Point<double> position) {
    if (throwOnMove) throw StateError('cursor unavailable');
    moves.add(position);
    if (!ignoreMoves) this.position = position;
  }
}

void main() {
  late _FakeNumericScrubCursorBackend cursorBackend;

  setUp(() {
    cursorBackend = _FakeNumericScrubCursorBackend();
    debugNumericScrubCursorBackendOverride = cursorBackend;
  });
  tearDown(() => debugNumericScrubCursorBackendOverride = null);

  Widget host(
    Widget child, {
    Alignment alignment = Alignment.center,
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Align(
              alignment: alignment,
              child: SizedBox(width: 240, child: child),
            ),
          ),
        ),
      ),
    );
  }

  final stepUp = find.byKey(const Key('cl-text-field-step-up'));
  final stepDown = find.byKey(const Key('cl-text-field-step-down'));
  final dragZone = find.byKey(const Key('cl-text-field-stepper-drag-zone'));
  final prefixZone = find.byKey(const Key('cl-text-field-prefix-scrub-zone'));
  final scrubRuler = find.byKey(const Key('cl-text-field-scrub-ruler'));
  final scrubOverlay = find.byKey(
    const Key('cl-text-field-scrub-value-overlay'),
  );

  BorderSide fieldBorder(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(CLTextField),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.decoration! as ShapeDecoration;
    return (decoration.shape as RoundedSuperellipseBorder).side;
  }

  ({int? increase, int? decrease}) rulerTickCounts(WidgetTester tester) {
    final dynamic painter = tester.widget<CustomPaint>(scrubRuler).painter;
    return (
      increase: painter.increaseTickCount as int?,
      decrease: painter.decreaseTickCount as int?,
    );
  }

  test('cursor session wraps with overshoot and removes warp delta', () {
    cursorBackend = _FakeNumericScrubCursorBackend(
      scale: 2,
      position: const math.Point<double>(1000, 500),
    );
    final session = NumericScrubCursorSession(backend: cursorBackend);
    session.prepare(enabled: true, position: const Offset(300, 200));
    session.activate(enabled: true);

    session.maybeWrap(
      position: const Offset(803, 200),
      horizontalDirection: 1,
      viewSize: const Size(800, 600),
      devicePixelRatio: 2,
      canIncrease: true,
      canDecrease: true,
    );

    expect(cursorBackend.moves, [const math.Point<double>(-584, 500)]);
    expect(
      session
          .correctUpdate(
            delta: const Offset(-789, 1),
            position: const Offset(14, 201),
          )
          .delta,
      const Offset(3, 1),
    );

    session.finish();
    expect(cursorBackend.moves.last, const math.Point<double>(1000, 500));
  });

  test('cursor warp calibrates system units from pointer travel', () {
    cursorBackend = _FakeNumericScrubCursorBackend(
      position: const math.Point<double>(1000, 500),
    );
    final session = NumericScrubCursorSession(backend: cursorBackend);
    session.prepare(enabled: true, position: const Offset(300, 200));
    session.activate(enabled: true);

    cursorBackend.position = const math.Point<double>(1992, 500);
    session.maybeWrap(
      position: const Offset(796, 200),
      horizontalDirection: 1,
      viewSize: const Size(800, 600),
      devicePixelRatio: 2,
      canIncrease: true,
      canDecrease: true,
    );

    expect(cursorBackend.moves, [const math.Point<double>(408, 500)]);
  });

  test('cursor warp preserves queued pre-warp movement', () {
    cursorBackend = _FakeNumericScrubCursorBackend(
      position: const math.Point<double>(772.7, 875.6),
    );
    final session = NumericScrubCursorSession(backend: cursorBackend);
    session.prepare(enabled: true, position: const Offset(456.7, 842.6));
    session.activate(enabled: true);

    cursorBackend.position = const math.Point<double>(1198.3, 759.4);
    session.maybeWrap(
      position: const Offset(882.3, 726.4),
      horizontalDirection: 9.5,
      viewSize: const Size(880, 949),
      devicePixelRatio: 2,
      canIncrease: true,
      canDecrease: true,
    );

    final corrected = session.correctUpdate(
      delta: const Offset(9.5, -0.3),
      position: const Offset(891.8, 726.1),
    );
    expect(corrected.delta, const Offset(9.5, -0.3));
    expect(corrected.canWrap, isFalse);

    session.maybeWrap(
      position: corrected.position,
      horizontalDirection: corrected.canWrap ? corrected.delta.dx : 0,
      viewSize: const Size(880, 949),
      devicePixelRatio: 2,
      canIncrease: true,
      canDecrease: true,
    );
    expect(cursorBackend.moves, hasLength(1));
  });

  test('cursor warp allows an immediate reverse crossing', () {
    final session = NumericScrubCursorSession(backend: cursorBackend);
    session.prepare(enabled: true, position: const Offset(300, 200));
    session.activate(enabled: true);

    session.maybeWrap(
      position: const Offset(796, 200),
      horizontalDirection: 1,
      viewSize: const Size(800, 600),
      devicePixelRatio: 1,
      canIncrease: true,
      canDecrease: true,
    );
    expect(cursorBackend.moves, hasLength(1));

    final corrected = session.correctUpdate(
      delta: const Offset(-792.5, 0),
      position: const Offset(3.5, 200),
    );
    session.maybeWrap(
      position: corrected.position,
      horizontalDirection: corrected.canWrap ? corrected.delta.dx : 0,
      viewSize: const Size(800, 600),
      devicePixelRatio: 1,
      canIncrease: true,
      canDecrease: true,
    );

    expect(cursorBackend.moves, hasLength(2));
  });

  test('cursor warp discards an unsynchronized teleport delta', () {
    final session = NumericScrubCursorSession(backend: cursorBackend);
    session.prepare(enabled: true, position: const Offset(300, 200));
    session.activate(enabled: true);

    cursorBackend.ignoreMoves = true;
    session.maybeWrap(
      position: const Offset(796, 200),
      horizontalDirection: 1,
      viewSize: const Size(800, 600),
      devicePixelRatio: 1,
      canIncrease: true,
      canDecrease: true,
    );

    final corrected = session.correctUpdate(
      delta: const Offset(-792, 0),
      position: const Offset(4, 200),
    );

    expect(corrected.delta, Offset.zero);
    expect(corrected.canWrap, isFalse);
  });

  test(
    'cursor warp keeps high-speed movement after an unsynchronized teleport',
    () {
      final session = NumericScrubCursorSession(backend: cursorBackend);
      session.prepare(enabled: true, position: const Offset(300, 200));
      session.activate(enabled: true);

      cursorBackend.ignoreMoves = true;
      session.maybeWrap(
        position: const Offset(796, 200),
        horizontalDirection: 1,
        viewSize: const Size(800, 600),
        devicePixelRatio: 1,
        canIncrease: true,
        canDecrease: true,
      );

      final corrected = session.correctUpdate(
        delta: const Offset(-712, 0),
        position: const Offset(84, 200),
      );

      expect(corrected.delta, const Offset(80, 0));
      expect(corrected.canWrap, isFalse);
    },
  );

  test('cursor session survives hardware movement racing a warp', () {
    final session = NumericScrubCursorSession(backend: cursorBackend);
    session.prepare(enabled: true, position: const Offset(300, 200));
    session.activate(enabled: true);

    cursorBackend.ignoreMoves = true;
    session.maybeWrap(
      position: const Offset(796, 200),
      horizontalDirection: 1,
      viewSize: const Size(800, 600),
      devicePixelRatio: 1,
      canIncrease: true,
      canDecrease: true,
    );
    expect(cursorBackend.moves, hasLength(1));

    cursorBackend
      ..ignoreMoves = false
      ..position = const math.Point<double>(-472, 240);
    session.correctUpdate(
      delta: const Offset(-792, 0),
      position: const Offset(4, 200),
    );
    session.maybeWrap(
      position: const Offset(796, 200),
      horizontalDirection: 1,
      viewSize: const Size(800, 600),
      devicePixelRatio: 1,
      canIncrease: true,
      canDecrease: true,
    );

    expect(cursorBackend.moves, hasLength(2));
  });

  test('cursor session respects bounds and silently disables failed warps', () {
    final unsupportedBackend = _FakeNumericScrubCursorBackend(
      isSupported: false,
    );
    final unsupportedSession = NumericScrubCursorSession(
      backend: unsupportedBackend,
    );
    unsupportedSession.prepare(enabled: true, position: const Offset(300, 200));
    unsupportedSession.activate(enabled: true);
    expect(unsupportedBackend.getPositionCalls, 0);

    final session = NumericScrubCursorSession(backend: cursorBackend);
    session.prepare(enabled: true, position: const Offset(300, 200));
    session.activate(enabled: true);

    session.maybeWrap(
      position: const Offset(796, 200),
      horizontalDirection: 1,
      viewSize: const Size(800, 600),
      devicePixelRatio: 1,
      canIncrease: false,
      canDecrease: true,
    );
    expect(cursorBackend.moves, isEmpty);

    cursorBackend.throwOnMove = true;
    session.maybeWrap(
      position: const Offset(796, 200),
      horizontalDirection: 1,
      viewSize: const Size(800, 600),
      devicePixelRatio: 1,
      canIncrease: true,
      canDecrease: true,
    );
    expect(cursorBackend.moves, isEmpty);

    cursorBackend.throwOnMove = false;
    session.maybeWrap(
      position: const Offset(796, 200),
      horizontalDirection: 1,
      viewSize: const Size(800, 600),
      devicePixelRatio: 1,
      canIncrease: true,
      canDecrease: true,
    );
    expect(cursorBackend.moves, isEmpty);
    expect(
      session
          .correctUpdate(
            delta: const Offset(5, 0),
            position: const Offset(10, 200),
          )
          .delta,
      const Offset(5, 0),
    );
  });

  testWidgets('mouse scrub restores the pointer-down cursor position', (
    tester,
  ) async {
    cursorBackend.position = const math.Point<double>(420, 260);
    final controller = TextEditingController(text: '4');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    await mouse.up();

    expect(cursorBackend.getPositionCalls, 1);
    expect(cursorBackend.moves, [const math.Point<double>(420, 260)]);
  });

  testWidgets('cursor wrapping can be disabled per text field', (tester) async {
    final controller = TextEditingController(text: '4');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
          wrapNumericScrubCursor: false,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    await mouse.up();

    expect(cursorBackend.getPositionCalls, 0);
    expect(cursorBackend.moves, isEmpty);
  });

  testWidgets('forwards autofocus and input formatters', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final formatter = FilteringTextInputFormatter.digitsOnly;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          inputFormatters: [formatter],
          autofocus: true,
        ),
      ),
    );
    await tester.pump();

    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(field.inputFormatters, [formatter]);
    expect(field.autofocus, isTrue);
    expect(focusNode.hasFocus, isTrue);

    await tester.enterText(find.byType(CupertinoTextField), '12ab34');
    expect(controller.text, '1234');
  });

  testWidgets('sizes use the standard control heights', (tester) async {
    for (final size in CLControlSize.values) {
      await tester.pumpWidget(host(CLTextField(size: size)));

      expect(
        tester.getSize(find.byType(CLTextField)).height,
        size.controlHeight,
        reason: 'height of $size',
      );
    }
  });

  testWidgets('step buttons only appear for numeric fields with a step', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const CLTextField(keyboardType: TextInputType.number, step: 1)),
    );
    expect(stepUp, findsOneWidget);
    expect(stepDown, findsOneWidget);

    await tester.pumpWidget(
      host(const CLTextField(keyboardType: TextInputType.number)),
    );
    expect(stepUp, findsNothing);
    expect(stepDown, findsNothing);

    await tester.pumpWidget(
      host(const CLTextField(keyboardType: TextInputType.text, step: 1)),
    );
    expect(stepUp, findsNothing);
    expect(stepDown, findsNothing);
  });

  testWidgets('numeric stepper preserves the original inline geometry', (
    tester,
  ) async {
    final controller = TextEditingController(text: '78');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('W'),
          suffix: const Text('px'),
          step: 1,
          size: CLControlSize.small,
        ),
      ),
    );

    final prefixRect = tester.getRect(find.text('W'));
    final fieldRect = tester.getRect(find.byType(CupertinoTextField));
    final suffixRect = tester.getRect(find.text('px'));
    final stepperRect = tester.getRect(stepUp);

    expect(fieldRect.left - prefixRect.right, closeTo(10, 0.01));
    expect(suffixRect.left - fieldRect.right, closeTo(0, 0.01));
    expect(stepperRect.left - suffixRect.right, greaterThan(10));

    final typography = CLThemeData().typography;
    expect(
      DefaultTextStyle.of(tester.element(find.text('W'))).style.fontFamily,
      typography.callout.fontFamily,
    );
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField))
          .style
          ?.fontFamily,
      typography.monoStrong.fontFamily,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('px'))).style.fontFamily,
      typography.mono.fontFamily,
    );
  });

  testWidgets(
    'readOnly and disabled keep the stepper layout and render it inert',
    (tester) async {
      final controller = TextEditingController(text: '4');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      Widget build({required bool enabled, required bool readOnly}) => host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: const TextInputType.numberWithOptions(signed: false),
          prefix: const Text('W'),
          enabled: enabled,
          readOnly: readOnly,
          step: 1,
          min: 0,
          max: 10,
          size: CLControlSize.small,
        ),
      );

      await tester.pumpWidget(build(enabled: true, readOnly: false));
      await tester.pumpAndSettle();
      final base = tester.getSize(find.byType(CLTextField));
      expect(stepUp, findsOneWidget);

      // readOnly keeps the arrows and the geometry, but cannot step.
      await tester.pumpWidget(build(enabled: true, readOnly: true));
      await tester.pumpAndSettle();
      expect(stepUp, findsOneWidget);
      expect(tester.getSize(find.byType(CLTextField)), base);
      await tester.tap(stepUp);
      await tester.pump();
      expect(controller.text, '4');
      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(controller.text, '4');

      // disabled keeps the arrows and the geometry, and grays out.
      await tester.pumpWidget(build(enabled: false, readOnly: false));
      await tester.pumpAndSettle();
      expect(stepUp, findsOneWidget);
      expect(tester.getSize(find.byType(CLTextField)), base);
    },
  );

  testWidgets('disabled state leaves its fill to the Claralight surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const CLTextField(enabled: false, placeholder: 'Unavailable')),
    );

    final theme = CLThemeData();
    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const Key('cl-text-field-surface')),
    );
    final surfaceDecoration = surface.decoration! as ShapeDecoration;
    expect(
      surfaceDecoration.color,
      theme.colors.control.withValues(alpha: theme.colors.control.a * 0.5),
    );

    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    final fieldDecoration = field.decoration!;
    expect(field.enabled, isFalse);
    expect(fieldDecoration, isA<BoxDecoration>());
    expect(fieldDecoration.color, isNull);
    expect(field.style?.color, theme.colors.textDisabled);
  });

  testWidgets('the whole numeric stepper surface focuses the text field', (
    tester,
  ) async {
    final controller = TextEditingController(text: '78');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          prefix: const Text('W'),
          suffix: const Text('px'),
          step: 1,
          size: CLControlSize.small,
        ),
      ),
    );

    final controlRect = tester.getRect(find.byType(CLTextField));
    await tester.tapAt(controlRect.center);
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('buttons step, format, and report the edited text', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0.2');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    final changes = <String>[];

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          step: 0.1,
          format: (value) => value.toStringAsFixed(2),
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(stepUp);
    await tester.pump();

    expect(controller.text, '0.30');
    expect(changes, ['0.30']);
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('step buttons clamp values and can repair out-of-range input', (
    tester,
  ) async {
    final controller = TextEditingController(text: '12');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 2,
          min: 1,
          max: 10,
        ),
      ),
    );

    await tester.tap(stepUp);
    await tester.pump();
    expect(controller.text, '12');

    await tester.tap(stepDown);
    await tester.pump();
    expect(controller.text, '10');

    controller.text = '2';
    await tester.pump();
    await tester.tap(stepDown);
    await tester.pump();
    expect(controller.text, '1');
  });

  testWidgets('unmodified arrow keys step a focused numeric field', (
    tester,
  ) async {
    final controller = TextEditingController(text: '4');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          step: 2,
        ),
      ),
    );

    await tester.tap(find.byType(CupertinoTextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(controller.text, '6');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(controller.text, '6');

    controller.value = const TextEditingValue(
      text: '6',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange(start: 0, end: 1),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(controller.text, '6');
  });

  testWidgets('numeric scrub zones preserve geometry and use an EW cursor', (
    tester,
  ) async {
    final controller = TextEditingController(text: '4');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
          size: CLControlSize.small,
        ),
      ),
    );

    final controlRect = tester.getRect(find.byType(CLTextField));
    final trailingRect = tester.getRect(dragZone);
    final prefixRect = tester.getRect(prefixZone);
    final upRect = tester.getRect(stepUp);

    expect(trailingRect.width, 24);
    expect(trailingRect.left, upRect.left);
    expect(trailingRect.right, closeTo(controlRect.right, 1.01));
    expect(prefixRect.left, closeTo(controlRect.left, 1.01));
    expect(prefixRect.width, greaterThan(tester.getSize(find.text('X')).width));
    expect(
      tester
          .widgetList<MouseRegion>(find.byType(MouseRegion))
          .where(
            (region) => region.cursor == SystemMouseCursors.resizeLeftRight,
          ),
      hasLength(2),
    );

    controller.text = 'invalid';
    await tester.pump();
    expect(
      tester
          .widgetList<MouseRegion>(find.byType(MouseRegion))
          .where(
            (region) => region.cursor == SystemMouseCursors.resizeLeftRight,
          ),
      isEmpty,
    );

    controller.text = '4';
    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );
    expect(prefixZone, findsNothing);
    expect(
      tester
          .widgetList<MouseRegion>(find.byType(MouseRegion))
          .where(
            (region) => region.cursor == SystemMouseCursors.resizeLeftRight,
          ),
      hasLength(1),
    );
  });

  testWidgets('active hover cursor matches the numeric scrub hit regions', (
    tester,
  ) async {
    final controller = TextEditingController(text: '4');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(prefixZone));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.resizeLeftRight,
    );

    await mouse.moveTo(tester.getCenter(stepUp));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.resizeLeftRight,
    );
    await mouse.removePointer();
  });

  testWidgets('mouse scrub only starts in prefix and arrow regions', (
    tester,
  ) async {
    final controller = TextEditingController(text: '10');
    final focusNode = FocusNode();
    final changes = <String>[];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          suffix: const Text('px'),
          step: 2,
          onChanged: changes.add,
        ),
      ),
    );

    final controlRect = tester.getRect(find.byType(CLTextField));
    final outside = await tester.startGesture(
      controlRect.center,
      kind: PointerDeviceKind.mouse,
    );
    await outside.moveBy(const Offset(24, 0));
    await outside.up();
    await tester.pump();
    expect(controller.text, '10');
    expect(scrubRuler, findsNothing);

    final scrub = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.mouse,
    );
    await scrub.moveBy(const Offset(4, 0));
    await tester.pump();
    await tester.pump();
    expect(controller.text, '10');
    expect(scrubRuler, findsOneWidget);
    expect(scrubOverlay, findsOneWidget);
    expect(find.byType(CLNumericText), findsOneWidget);
    expect(
      find.descendant(of: scrubOverlay, matching: find.text('px')),
      findsOneWidget,
    );

    await scrub.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(controller.text, '12');

    await scrub.moveBy(const Offset(17, 0));
    await tester.pump();
    expect(controller.text, '16');
    expect(changes, ['12', '16']);
    expect(focusNode.hasFocus, isTrue);

    await scrub.up();
    await tester.pumpAndSettle();
    expect(scrubOverlay, findsNothing);
  });

  testWidgets('focus loss immediately finishes a mouse scrub', (tester) async {
    final controller = TextEditingController(text: '10');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    expect(scrubRuler, findsOneWidget);

    focusNode.unfocus();
    await tester.pump();

    expect(scrubRuler, findsNothing);
    expect(cursorBackend.moves, [const math.Point<double>(320, 240)]);
    await mouse.up();
  });

  testWidgets('mouse scrub keeps the horizontal resize cursor while dragging', (
    tester,
  ) async {
    final cursorKinds = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.mouseCursor,
      (call) async {
        if (call.method == 'activateSystemCursor') {
          cursorKinds.add(
            (call.arguments as Map<Object?, Object?>)['kind']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.mouseCursor,
        null,
      ),
    );

    final controller = TextEditingController(text: '10');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-280, 0));
    await tester.pump();

    expect(cursorKinds.last, SystemMouseCursors.resizeLeftRight.kind);
    await mouse.up();
  });

  testWidgets('prefix scrub moves right to increase and left to decrease', (
    tester,
  ) async {
    final controller = TextEditingController(text: '4');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    expect(controller.text, '5');
    expect(scrubRuler, findsOneWidget);

    await mouse.moveBy(const Offset(-16, 0));
    await tester.pump();
    expect(controller.text, '3');

    await mouse.up();
  });

  testWidgets('vertical bands select strict 2/4/8/16/32px spacing', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, -4));
    await tester.pump();

    await mouse.moveBy(const Offset(0, -46));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(controller.text, '1');

    await mouse.moveBy(const Offset(0, -100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await mouse.moveBy(const Offset(2, 0));
    await tester.pump();
    expect(controller.text, '2');

    await mouse.moveBy(const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await mouse.moveBy(const Offset(16, 0));
    await tester.pump();
    expect(controller.text, '3');

    await mouse.moveBy(const Offset(0, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await mouse.moveBy(const Offset(32, 0));
    await tester.pump();
    expect(controller.text, '4');
    expect(
      find.byKey(const Key('cl-text-field-scrub-multiplier')),
      findsNothing,
    );

    await mouse.up();
  });

  testWidgets('ruler spacing and step threshold interpolate together', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, -4));
    await mouse.moveBy(const Offset(0, -46));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(controller.text, '0');
    await mouse.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(controller.text, '1');

    await mouse.up();
  });

  testWidgets('100px vertical bands use 4px return hysteresis', (tester) async {
    final controller = TextEditingController(text: '0');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, -4));
    await mouse.moveBy(const Offset(0, -46));
    await mouse.moveBy(const Offset(0, 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(controller.text, '1');

    await mouse.moveBy(const Offset(0, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(controller.text, '1');
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(controller.text, '2');

    await mouse.up();
  });

  testWidgets('pointer changes continuously and commits once on release', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    final changes = <String>[];
    final commits = <String>[];
    final platformCalls = <MethodCall>[];
    addTearDown(controller.dispose);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
          onChanged: changes.add,
          onCommit: commits.add,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 4));
    await tester.pump();
    await mouse.moveBy(const Offset(24, 0));
    await tester.pump();

    expect(controller.text, '3');
    expect(changes, ['3']);
    expect(commits, isEmpty);
    expect(
      platformCalls.where(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      hasLength(1),
    );

    await mouse.up();
    await tester.pumpAndSettle();
    expect(commits, ['3']);

    await tester.tap(stepUp);
    await tester.pump();
    expect(controller.text, '4');
    expect(commits, ['3', '4']);
    expect(
      platformCalls.where(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      hasLength(2),
    );
  });

  testWidgets('pointer cancel restores the start value without committing', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    final changes = <String>[];
    final commits = <String>[];
    final cancels = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
          onChanged: changes.add,
          onCommit: commits.add,
          onCancel: cancels.add,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    expect(controller.text, '1');

    await mouse.cancel();
    await tester.pump();

    expect(changes, ['1']);
    expect(commits, isEmpty);
    expect(cancels, ['0']);
    expect(controller.text, '0');
  });

  testWidgets('stepper scrub cancellation restores without committing', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    final commits = <String>[];
    final cancels = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
          onCommit: commits.add,
          onCancel: cancels.add,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(stepUp),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    expect(controller.text, '1');

    await mouse.cancel();
    await tester.pump();

    expect(controller.text, '0');
    expect(commits, isEmpty);
    expect(cancels, ['0']);
  });

  testWidgets('disposing an active numeric field cancels its interaction', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    final commits = <String>[];
    final cancels = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
          onCommit: commits.add,
          onCancel: cancels.add,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    expect(controller.text, '1');

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await tester.pump();

    expect(controller.text, '0');
    expect(commits, isEmpty);
    expect(cancels, ['0']);
  });

  testWidgets('disposing a net-zero text edit clears its preview', (
    tester,
  ) async {
    final controller = TextEditingController(text: '4');
    final changes = <String>[];
    final commits = <String>[];
    final cancels = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          onChanged: changes.add,
          onCommit: commits.add,
          onCancel: cancels.add,
        ),
      ),
    );
    await tester.tap(find.byType(CupertinoTextField));
    await tester.enterText(find.byType(CupertinoTextField), '8');
    await tester.enterText(find.byType(CupertinoTextField), '4');
    await tester.pumpWidget(host(const SizedBox.shrink()));
    await tester.pump();

    expect(changes, ['8', '4']);
    expect(commits, isEmpty);
    expect(cancels, ['4']);
  });

  testWidgets('app suspension cancels an active numeric interaction once', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    final commits = <String>[];
    final cancels = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
          onCommit: commits.add,
          onCancel: cancels.add,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    expect(controller.text, '1');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await mouse.cancel();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(controller.text, '0');
    expect(commits, isEmpty);
    expect(cancels, ['0']);
  });

  testWidgets('net-zero scrub clears preview without committing', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    final changes = <String>[];
    final commits = <String>[];
    final cancels = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
          onChanged: changes.add,
          onCommit: commits.add,
          onCancel: cancels.add,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    await mouse.moveBy(const Offset(-8, 0));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(changes, ['1', '0']);
    expect(commits, isEmpty);
    expect(cancels, ['0']);
    expect(controller.text, '0');
  });

  testWidgets('keyboard repeat commits once on key up', (tester) async {
    final controller = TextEditingController(text: '0');
    final focusNode = FocusNode();
    final changes = <String>[];
    final commits = <String>[];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          step: 1,
          onChanged: changes.add,
          onCommit: commits.add,
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(changes, ['1', '2']);
    expect(commits, isEmpty);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(commits, ['2']);
  });

  testWidgets('scrub discards bound overshoot for immediate reversal', (
    tester,
  ) async {
    final controller = TextEditingController(text: '9');
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
          max: 10,
          onChanged: changes.add,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 4));
    await mouse.moveBy(const Offset(24, 0));
    await tester.pump();
    expect(controller.text, '10');

    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    expect(controller.text, '10');

    await mouse.moveBy(const Offset(-8, 0));
    await tester.pump();
    expect(controller.text, '9');
    expect(changes, ['10', '9']);

    await mouse.up();
  });

  testWidgets('ruler truncates ticks at both finite value boundaries', (
    tester,
  ) async {
    final controller = TextEditingController(text: '8');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
          min: 0,
          max: 10,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 4));
    await tester.pump();

    expect(rulerTickCounts(tester), (increase: 2, decrease: 8));

    controller.text = '10';
    await tester.pump();
    expect(rulerTickCounts(tester), (increase: 0, decrease: 10));

    controller.text = '0';
    await tester.pump();
    expect(rulerTickCounts(tester), (increase: 10, decrease: 0));

    await mouse.up();
  });

  testWidgets('ruler keeps a partial-step endpoint and expands when invalid', (
    tester,
  ) async {
    final controller = TextEditingController(text: '9');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 3,
          min: 0,
          max: 10,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 4));
    await tester.pump();

    expect(rulerTickCounts(tester), (increase: 1, decrease: 3));

    controller.text = '11';
    await tester.pump();
    expect(rulerTickCounts(tester), (increase: null, decrease: null));

    await mouse.up();
  });

  testWidgets('a null scrub bound leaves only that ruler side unbounded', (
    tester,
  ) async {
    final controller = TextEditingController(text: '10');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          step: 1,
          max: 10,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 4));
    await tester.pump();

    expect(rulerTickCounts(tester), (increase: 0, decrease: null));

    await mouse.up();
  });

  testWidgets('stylus activates at 4px and still steps every 8px at 1x', (
    tester,
  ) async {
    final controller = TextEditingController(text: '4');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );

    final stylus = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.stylus,
    );
    await stylus.moveBy(const Offset(3, 0));
    await tester.pump();
    expect(scrubRuler, findsNothing);
    expect(controller.text, '4');

    await stylus.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(scrubRuler, findsOneWidget);
    expect(controller.text, '4');

    await stylus.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(controller.text, '5');
    await stylus.up();
  });

  testWidgets('pointer cancel stops a pending arrow repeat', (tester) async {
    final controller = TextEditingController(text: '0');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(stepUp),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 499));
    await mouse.cancel();
    await tester.pump(const Duration(milliseconds: 160));

    expect(controller.text, '0');
    expect(scrubOverlay, findsNothing);
  });

  testWidgets('trackpad pan zoom does not scrub numeric values', (
    tester,
  ) async {
    final controller = TextEditingController(text: '4');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );

    await tester.drag(
      dragZone,
      const Offset(40, 0),
      kind: PointerDeviceKind.trackpad,
    );
    await tester.pump();

    expect(controller.text, '4');
    expect(scrubRuler, findsNothing);
  });

  testWidgets('mouse hold repeats then hands off cleanly to 2D scrub', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(stepUp),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 499));
    expect(controller.text, '0');
    expect(scrubRuler, findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.text, '1');
    expect(focusNode.hasFocus, isTrue);
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.text, '2');

    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();
    expect(controller.text, '3');
    expect(scrubRuler, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 160));
    expect(controller.text, '3');
    await mouse.up();
  });

  testWidgets('mouse hold repeats while the focused value is fully selected', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );
    focusNode.requestFocus();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    await tester.pump();

    final mouse = await tester.startGesture(
      tester.getCenter(stepUp),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.text, '1');
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.text, '2');

    await mouse.up();
  });

  testWidgets('touch long press waits for 8px movement before scrubbing', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1');
    final focusNode = FocusNode();
    final platformCalls = <MethodCall>[];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );

    final touch = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 299));
    expect(focusNode.hasFocus, isFalse);
    expect(fieldBorder(tester).color.a, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(focusNode.hasFocus, isFalse);
    expect(fieldBorder(tester).color, CLThemeData().colors.accent);
    expect(controller.text, '1');
    expect(scrubRuler, findsNothing);
    expect(
      platformCalls.where(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      isEmpty,
    );

    await touch.moveBy(const Offset(7, 0));
    await tester.pump();
    expect(controller.text, '1');
    expect(scrubRuler, findsNothing);

    await touch.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(controller.text, '2');
    expect(scrubRuler, findsOneWidget);
    expect(
      platformCalls.where(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      hasLength(1),
    );

    await touch.up();
  });

  testWidgets('touch hold repeats without visual then hands off to scrub', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );

    final touch = await tester.startGesture(
      tester.getCenter(stepUp),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(focusNode.hasFocus, isFalse);
    expect(scrubRuler, findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.text, '1');
    expect(scrubRuler, findsNothing);
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.text, '2');

    await touch.moveBy(const Offset(8, 0));
    await tester.pump();
    expect(controller.text, '3');
    expect(scrubRuler, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 160));
    expect(controller.text, '3');

    await touch.up();
  });

  testWidgets(
    'scrub direction stays right-to-increase for every arrow layout',
    (tester) async {
      final controller = TextEditingController(text: '4');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(
          CLTextField(
            controller: controller,
            keyboardType: TextInputType.number,
            step: 1,
            stepperDirection: CLNumericStepperDirection.down,
          ),
        ),
      );

      final mouse = await tester.startGesture(
        tester.getCenter(dragZone),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(8, 0));
      await tester.pump();
      expect(controller.text, '5');
      await mouse.up();
    },
  );

  testWidgets(
    'value overlay flips around the field and keeps compact geometry',
    (tester) async {
      final controller = TextEditingController(text: '12');
      addTearDown(controller.dispose);

      Widget field() => CLTextField(
        controller: controller,
        keyboardType: TextInputType.number,
        prefix: const Text('X'),
        suffix: const Text('px'),
        step: 1,
      );

      await tester.pumpWidget(host(field(), alignment: Alignment.topCenter));
      var mouse = await tester.startGesture(
        tester.getCenter(prefixZone),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(4, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      var fieldRect = tester.getRect(find.byType(CLTextField));
      var overlayRect = tester.getRect(scrubOverlay);
      expect(overlayRect.top, greaterThanOrEqualTo(fieldRect.bottom + 7));
      expect(overlayRect.width, greaterThanOrEqualTo(80));
      await mouse.up();
      await tester.pumpAndSettle();

      await tester.pumpWidget(host(field(), alignment: Alignment.bottomCenter));
      mouse = await tester.startGesture(
        tester.getCenter(prefixZone),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(4, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      fieldRect = tester.getRect(find.byType(CLTextField));
      overlayRect = tester.getRect(scrubOverlay);
      expect(overlayRect.bottom, lessThanOrEqualTo(fieldRect.top - 7));
      await mouse.up();
    },
  );

  testWidgets('value popover tracks a scrub field inside a scroller', (
    tester,
  ) async {
    final controller = TextEditingController(text: '12');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scrollController,
            child: SizedBox(
              height: 1200,
              child: Align(
                alignment: const Alignment(0, 0.35),
                child: SizedBox(
                  width: 240,
                  child: CLTextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    prefix: const Text('W'),
                    suffix: const Text('px'),
                    step: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    scrollController.jumpTo(400);
    await tester.pump();

    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    await tester.pump();

    final fieldRect = tester.getRect(find.byType(CLTextField));
    final prefixRect = tester.getRect(prefixZone);
    final overlayRect = tester.getRect(scrubOverlay);
    final rulerCenter = (prefixRect.right + fieldRect.right) / 2;
    expect(overlayRect.bottom, lessThan(fieldRect.top));
    expect(fieldRect.top - overlayRect.bottom, lessThan(80));
    expect(overlayRect.center.dx, closeTo(rulerCenter, 1));

    await mouse.up();
  });

  testWidgets('overlay uses the numeric formatter and safely moves suffix', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1');
    final suffixKey = GlobalKey();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          prefix: const Text('X'),
          suffix: Text('kg', key: suffixKey),
          step: 0.25,
          format: (value) => value.toStringAsFixed(2),
        ),
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(prefixZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    await tester.pump();

    final number = tester.widget<CLNumericText>(find.byType(CLNumericText));
    expect(number.formatter!(1), '1.00');
    expect(find.byKey(suffixKey), findsOneWidget);
    expect(
      find.descendant(of: scrubOverlay, matching: find.byKey(suffixKey)),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(suffixKey),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );

    await mouse.up();
  });

  testWidgets('reduced motion removes scaling and snaps ruler spacing', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
        ),
        disableAnimations: true,
      ),
    );

    final mouse = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 4));
    await tester.pump();
    var popover = tester.widget<CLAnchoredOverlay>(
      find.byKey(const Key('cl-text-field-scrub-popover')),
    );
    expect(popover.opacity, 0);
    expect(popover.scale, 1);

    await tester.pump(const Duration(milliseconds: 62));
    popover = tester.widget<CLAnchoredOverlay>(
      find.byKey(const Key('cl-text-field-scrub-popover')),
    );
    expect(popover.opacity, inExclusiveRange(0, 1));
    expect(popover.scale, 1);

    await mouse.moveBy(const Offset(0, -54));
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(controller.text, '2');

    await mouse.up();
  });

  testWidgets('value overlay reuses the complete arrow popover material', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    await tester.pump();

    final theme = CLThemeData();
    final popover = tester.widget<CLAnchoredOverlay>(
      find.byKey(const Key('cl-text-field-scrub-popover')),
    );
    expect(popover.position, CLPopoverPosition.top);
    expect(popover.showArrow, isTrue);
    expect(popover.padding, const EdgeInsets.fromLTRB(16, 10, 16, 8));
    expect(popover.borderRadius, theme.radii.panel);
    expect(popover.outlineColor, theme.colors.outlineStrong);
    expect(popover.shadowBlur, 24);
    expect(popover.shadowOffset, const Offset(0, 10));
    expect(scrubOverlay, findsOneWidget);
    await mouse.up();
  });

  testWidgets('value overlay uses light theme foreground colors', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1');
    final theme = CLThemeData(colors: const CLColorScheme.light());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CLTheme(
          data: theme,
          child: CLTextField(
            controller: controller,
            keyboardType: TextInputType.number,
            suffix: const Text('px'),
            step: 1,
          ),
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(4, 0));
    await tester.pump();
    await tester.pump();

    final number = tester.widget<CLNumericText>(find.byType(CLNumericText));
    final suffix = find.descendant(of: scrubOverlay, matching: find.text('px'));

    expect(number.style?.color, theme.colors.textPrimary);
    expect(
      DefaultTextStyle.of(tester.element(suffix)).style.color,
      theme.colors.textTertiary,
    );
    expect(
      IconTheme.of(tester.element(suffix)).color,
      theme.colors.textTertiary,
    );
    await mouse.up();
  });

  testWidgets('macOS pointer steps use the native alignment haptic channel', (
    tester,
  ) async {
    const channel = MethodChannel('dev.claralight.ui/haptics');
    final calls = <MethodCall>[];
    final controller = TextEditingController(text: '1');
    addTearDown(controller.dispose);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          keyboardType: TextInputType.number,
          step: 1,
        ),
      ),
    );
    final mouse = await tester.startGesture(
      tester.getCenter(dragZone),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 4));
    await mouse.moveBy(const Offset(8, 0));
    await tester.pump();

    expect(controller.text, '2');
    expect(calls, contains(isMethodCall('selectionClick', arguments: null)));
    debugDefaultTargetPlatformOverride = null;
    await mouse.up();
  });

  testWidgets(
    'wheel steps only while focused, preserves focus, and filters signals',
    (tester) async {
      final controller = TextEditingController(text: '4');
      final focusNode = FocusNode();
      final commits = <String>[];
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        host(
          CLTextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.number,
            step: 2,
            min: 0,
            max: 10,
            onCommit: commits.add,
          ),
        ),
      );

      final position = tester.getCenter(find.byType(CLTextField));
      bool? allowedPlatformDefault;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: position,
          scrollDelta: const Offset(0, -120),
          onRespond: ({required allowPlatformDefault}) {
            allowedPlatformDefault = allowPlatformDefault;
          },
        ),
      );
      await tester.pump();
      expect(controller.text, '4');
      expect(focusNode.hasFocus, isFalse);
      expect(allowedPlatformDefault, isTrue);
      expect(commits, isEmpty);

      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: position,
          scrollDelta: const Offset(0, -120),
          onRespond: ({required allowPlatformDefault}) {
            allowedPlatformDefault = allowPlatformDefault;
          },
        ),
      );
      await tester.pump();
      expect(controller.text, '6');
      expect(focusNode.hasFocus, isTrue);
      expect(allowedPlatformDefault, isFalse);
      expect(commits, isEmpty);
      await tester.pump(const Duration(milliseconds: 119));
      expect(commits, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(commits, ['6']);

      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: position,
          scrollDelta: const Offset(30, -10),
        ),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.trackpad,
          position: position,
          scrollDelta: const Offset(0, -20),
        ),
      );
      await tester.pump();
      expect(controller.text, '6');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: position,
          scrollDelta: const Offset(0, -20),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(controller.text, '6');

      focusNode.unfocus();
      await tester.pump();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: position,
          scrollDelta: const Offset(0, -20),
        ),
      );
      await tester.pump();
      expect(controller.text, '6');

      focusNode.requestFocus();
      await tester.pump();
      controller.text = '10';
      await tester.pump();
      var respondedAtBoundary = false;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: position,
          scrollDelta: const Offset(0, -20),
          onRespond: ({required allowPlatformDefault}) {
            respondedAtBoundary = true;
          },
        ),
      );
      await tester.pump();
      expect(controller.text, '10');
      expect(respondedAtBoundary, isTrue);
    },
  );

  testWidgets('wheel yields to an ancestor scroller at a numeric bound', (
    tester,
  ) async {
    final controller = TextEditingController(text: '4');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          controller: scrollController,
          child: SizedBox(
            height: 1000,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 240,
                child: CLTextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  step: 1,
                  min: 0,
                  max: 10,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final position = tester.getCenter(find.byType(CLTextField));
    await tester.tap(find.byType(CLTextField));
    await tester.pump();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: position,
        scrollDelta: const Offset(0, 20),
      ),
    );
    await tester.pump();
    expect(controller.text, '3');
    expect(scrollController.offset, 0);

    controller.text = '0';
    await tester.pump();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: position,
        scrollDelta: const Offset(0, 20),
      ),
    );
    await tester.pump();
    expect(controller.text, '0');
    expect(scrollController.offset, 20);
  });

  testWidgets('numeric semantics expose available step directions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController(text: '1');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          step: 1,
          min: 0,
          max: 2,
        ),
      ),
    );

    var node = tester.getSemantics(find.byType(CLTextField));
    var data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    expect(data.value, '1');
    expect(data.increasedValue, '2');
    expect(data.decreasedValue, '0');

    node.owner!.performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(controller.text, '2');
    expect(focusNode.hasFocus, isFalse);

    node = tester.getSemantics(find.byType(CLTextField));
    data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isFalse);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    expect(data.value, '2');
    expect(data.increasedValue, isEmpty);
    expect(data.decreasedValue, '1');
    semantics.dispose();
  });

  testWidgets('external error keeps text readable and exposes semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(CLTextField(focusNode: focusNode, error: true)),
    );

    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(field.style?.color, CLThemeData().colors.textPrimary);
    expect(fieldBorder(tester).color, CLThemeData().colors.danger);
    expect(fieldBorder(tester).width, 1);
    expect(
      tester
          .getSemantics(find.byType(CLTextField))
          .getSemanticsData()
          .validationResult,
      SemanticsValidationResult.invalid,
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(fieldBorder(tester).color, CLThemeData().colors.danger);
    expect(fieldBorder(tester).width, 1.5);

    await tester.pumpWidget(host(const CLTextField()));
    await tester.pumpAndSettle();

    expect(fieldBorder(tester).color.a, 0);
    expect(
      tester
          .getSemantics(find.byType(CLTextField))
          .getSemanticsData()
          .validationResult,
      SemanticsValidationResult.none,
    );
    semantics.dispose();
  });

  testWidgets('text editing commits on blur and cancels on escape', (
    tester,
  ) async {
    final controller = TextEditingController(text: '4');
    final focusNode = FocusNode();
    final changes = <String>[];
    final commits = <String>[];
    final cancels = <String>[];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          onChanged: changes.add,
          onCommit: commits.add,
          onCancel: cancels.add,
        ),
      ),
    );

    await tester.tap(find.byType(CupertinoTextField));
    await tester.enterText(find.byType(CupertinoTextField), '8');
    focusNode.unfocus();
    await tester.pump();
    expect(commits, ['8']);

    await tester.tap(find.byType(CupertinoTextField));
    await tester.enterText(find.byType(CupertinoTextField), '12');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.text, '8');
    expect(commits, ['8']);
    expect(cancels, ['8']);
    expect(changes, ['8', '12']);
  });

  testWidgets('invalid numeric input uses a danger outline after blur', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          min: 1,
          max: 10,
        ),
      ),
    );

    Color? textColor() => tester
        .widget<CupertinoTextField>(find.byType(CupertinoTextField))
        .style
        ?.color;

    expect(textColor(), CLThemeData().colors.textPrimary);
    expect(fieldBorder(tester).color.a, 0);

    await tester.tap(find.byType(CupertinoTextField));
    await tester.enterText(find.byType(CupertinoTextField), '12');
    focusNode.unfocus();
    await tester.pump();

    expect(textColor(), CLThemeData().colors.textPrimary);
    expect(fieldBorder(tester).color, CLThemeData().colors.danger);

    await tester.tap(find.byType(CupertinoTextField));
    await tester.enterText(find.byType(CupertinoTextField), '8');
    await tester.pump();

    expect(textColor(), CLThemeData().colors.textPrimary);
    expect(fieldBorder(tester).color, CLThemeData().colors.accent);
  });

  testWidgets('invalid submission is blocked and retains focus', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'invalid');
    final focusNode = FocusNode();
    String? submitted;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      host(
        CLTextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          onSubmitted: (value) => submitted = value,
        ),
      ),
    );

    await tester.tap(find.byType(CupertinoTextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, isNull);
    expect(focusNode.hasFocus, isTrue);
    expect(fieldBorder(tester).color, CLThemeData().colors.danger);
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField))
          .style
          ?.color,
      CLThemeData().colors.textPrimary,
    );

    await tester.enterText(find.byType(CupertinoTextField), '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, '7');
  });

  testWidgets(
    'tapping the field surface reopens the IME after the platform hides it',
    (tester) async {
      // Regression: Android back / iOS swipe-down dismisses the IME while the
      // field keeps focus; requestFocus() alone could never re-attach it.
      await tester.pumpWidget(
        host(
          CLTextField(
            controller: TextEditingController(text: '12'),
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
          ),
        ),
      );

      final field = find.byType(CLTextField);
      await tester.tap(field);
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);

      await tester.enterText(field, '1');
      await tester.pump();

      // Platform hides the IME without telling the framework (back button).
      tester.testTextInput.hide();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);

      // Tap the field surface away from the tiny editable strip.
      final rect = tester.getRect(field);
      await tester.tapAt(Offset(rect.left + 24, rect.center.dy));
      await tester.pump();

      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(
        tester.testTextInput.isVisible,
        isTrue,
        reason: 'tapping the field must re-attach the soft keyboard',
      );
    },
  );

  testWidgets('invalid submission re-attaches the keyboard for correction', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CLTextField(
          controller: TextEditingController(text: '5'),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
        ),
      ),
    );

    final field = find.byType(CLTextField);
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, '-');
    await tester.pump();

    // Submitting an incomplete number closes the connection (Done action);
    // the field must bring the IME right back so the user can finish it.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: 'invalid submission must keep the keyboard available',
    );
  });
}
