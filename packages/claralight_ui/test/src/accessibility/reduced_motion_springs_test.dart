import 'dart:math' as math;

import 'package:claralight_ui/claralight_ui.dart';
import 'package:claralight_ui/src/overlays/anchored_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MotionHost extends StatefulWidget {
  const _MotionHost({super.key, required this.child, this.reduced = false});

  final Widget child;
  final bool reduced;

  @override
  State<_MotionHost> createState() => _MotionHostState();
}

class _MotionHostState extends State<_MotionHost> {
  late bool reduced = widget.reduced;

  @override
  void didUpdateWidget(covariant _MotionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduced != widget.reduced) reduced = widget.reduced;
  }

  void setReduced(bool value) => setState(() => reduced = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: widget.child)),
      ),
    );
  }
}

Widget _host(Widget child, {Key? key, bool reduced = false}) =>
    _MotionHost(key: key, reduced: reduced, child: child);

_MotionHostState _motionState(WidgetTester tester) =>
    tester.state<_MotionHostState>(find.byType(_MotionHost));

Positioned _segmentedThumb(WidgetTester tester) => tester
    .widgetList<Positioned>(find.byType(Positioned))
    .firstWhere((widget) => widget.width == 147 && widget.height == 34);

Positioned _sliderThumb(WidgetTester tester) => tester
    .widgetList<Positioned>(find.byType(Positioned))
    .firstWhere(
      (widget) =>
          widget.width == CLSlider.thumbWidth &&
          widget.height == CLSlider.thumbHeight,
    );

Finder _menuPanelFinder(WidgetTester tester) {
  for (final element in find.byType(CLSurface).evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox && renderObject.size.width > 50) {
      return find.byWidget(element.widget);
    }
  }
  throw StateError('The expanded menu surface is not mounted');
}

double _menuPanelOpacity(WidgetTester tester) {
  final opacity = find.ancestor(
    of: _menuPanelFinder(tester),
    matching: find.byType(Opacity),
  );
  return tester.widget<Opacity>(opacity.first).opacity;
}

double _pressScale(WidgetTester tester) => tester
    .widgetList<Transform>(
      find.descendant(
        of: find.byType(CLPressable),
        matching: find.byType(Transform),
      ),
    )
    .map((transform) => transform.transform.getMaxScaleOnAxis())
    .reduce(math.max);

bool _overlayMounted(WidgetTester tester) =>
    find.byType(CLAnchoredOverlay).evaluate().isNotEmpty;

double _overlayOpacity(WidgetTester tester) =>
    tester.widget<CLAnchoredOverlay>(find.byType(CLAnchoredOverlay)).opacity;

void _expectOverlayScale(WidgetTester tester) {
  expect(find.byType(CLAnchoredOverlay), findsOneWidget);
  expect(
    tester.widget<CLAnchoredOverlay>(find.byType(CLAnchoredOverlay)).scale,
    1,
  );
}

Future<TestGesture> _showTooltip(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.byKey(const Key('tooltip-anchor'))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  return mouse;
}

void main() {
  testWidgets('pressable preserves normal spring and reduced identity', (
    tester,
  ) async {
    var taps = 0;
    const key = Key('pressable-child');
    await tester.pumpWidget(
      _host(
        CLPressable(
          onTap: () => taps++,
          showHighlight: true,
          child: const SizedBox(
            key: key,
            width: 100,
            height: 40,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    final initial = tester.getRect(find.byKey(key));
    final normalGesture = await tester.startGesture(initial.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_pressScale(tester), greaterThan(1));
    await normalGesture.up();
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _host(
        CLPressable(
          onTap: () => taps++,
          child: const SizedBox(
            key: key,
            width: 100,
            height: 40,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
        reduced: true,
      ),
    );
    final reducedInitial = tester.getRect(find.byKey(key));
    final gesture = await tester.startGesture(reducedInitial.center);
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveTo(reducedInitial.center + const Offset(20, 10));
    await tester.pump();
    expect(tester.getSize(find.byKey(key)), const Size(100, 40));
    expect(_pressScale(tester), closeTo(1, 0.0001));
    expect(find.byType(CustomPaint), findsWidgets);
    await gesture.up();
    await tester.pump();
    await tester.tap(find.byKey(key));
    expect(taps, 2);
  });

  testWidgets('pressable snaps immediately when preference toggles mid-press', (
    tester,
  ) async {
    const key = Key('toggle-pressable-child');
    await tester.pumpWidget(
      _host(
        CLPressable(
          onTap: () {},
          child: const SizedBox(key: key, width: 100, height: 40),
        ),
      ),
    );
    final initial = tester.getRect(find.byKey(key));
    final gesture = await tester.startGesture(initial.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_pressScale(tester), greaterThan(1));
    _motionState(tester).setReduced(true);
    await tester.pump();
    expect(tester.getSize(find.byKey(key)), const Size(100, 40));
    expect(_pressScale(tester), closeTo(1, 0.0001));
    await gesture.up();
  });

  testWidgets('segmented control pairs spring motion with reduced snapping', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: 300,
              child: CLSegmentedControl(
                segments: const ['One', 'Two'],
                selectedIndex: selected,
                onChanged: (_) {},
              ),
            );
          },
        ),
      ),
    );
    update(() => selected = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_segmentedThumb(tester).left, greaterThan(3));
    expect(_segmentedThumb(tester).left, lessThan(150));
    await tester.pumpAndSettle();
    expect(_segmentedThumb(tester).left, closeTo(150, 0.01));

    selected = 0;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: 300,
              child: CLSegmentedControl(
                segments: const ['One', 'Two'],
                selectedIndex: selected,
                onChanged: (_) {},
              ),
            );
          },
        ),
        reduced: true,
      ),
    );
    update(() => selected = 1);
    await tester.pump();
    expect(_segmentedThumb(tester).left, closeTo(150, 0.01));
  });

  testWidgets(
    'segmented selection snaps when reduced motion toggles in flight',
    (tester) async {
      var selected = 0;
      late StateSetter update;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                width: 300,
                child: CLSegmentedControl(
                  segments: const ['One', 'Two'],
                  selectedIndex: selected,
                  onChanged: (_) {},
                ),
              );
            },
          ),
        ),
      );
      update(() => selected = 1);
      await tester.pump(const Duration(milliseconds: 16));
      _motionState(tester).setReduced(true);
      await tester.pump();
      expect(_segmentedThumb(tester).left, closeTo(150, 0.01));
    },
  );

  testWidgets('slider preserves callback, track, drag, and paired motion', (
    tester,
  ) async {
    var value = 0.2;
    final changes = <double>[];
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: 300,
              child: CLSlider(
                value: value,
                onChanged: (next) {
                  changes.add(next);
                  setState(() => value = next);
                },
              ),
            );
          },
        ),
      ),
    );
    update(() => value = 0.8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      _sliderThumb(tester).left,
      greaterThan((300 - CLSlider.thumbWidth) * 0.2),
    );
    expect(
      _sliderThumb(tester).left,
      lessThan((300 - CLSlider.thumbWidth) * 0.8),
    );
    await tester.pumpAndSettle();
    expect(
      _sliderThumb(tester).left,
      closeTo((300 - CLSlider.thumbWidth) * 0.8, 0.01),
    );

    final trackCenter = tester.getCenter(find.byType(CLSlider));
    await tester.tapAt(trackCenter + const Offset(-90, 0));
    await tester.pump();
    expect(changes, isNotEmpty);

    final beforeDrag = changes.length;
    final drag = await tester.startGesture(trackCenter);
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(changes.length, greaterThan(beforeDrag));

    await tester.pumpWidget(
      _host(
        key: const ValueKey('slider-reduced-host'),
        const SizedBox(
          width: 300,
          child: CLSlider(value: 0.8, onChanged: null),
        ),
        reduced: true,
      ),
    );
    await tester.pump();
    expect(
      _sliderThumb(tester).left,
      closeTo((300 - CLSlider.thumbWidth) * 0.8, 0.01),
    );
  });

  testWidgets('slider snaps when reduced motion toggles during visual spring', (
    tester,
  ) async {
    var value = 0.1;
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: 300,
              child: CLSlider(value: value, onChanged: (_) {}),
            );
          },
        ),
      ),
    );
    update(() => value = 0.9);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      _sliderThumb(tester).left,
      lessThan((300 - CLSlider.thumbWidth) * 0.9),
    );
    _motionState(tester).setReduced(true);
    await tester.pump();
    expect(
      _sliderThumb(tester).left,
      closeTo((300 - CLSlider.thumbWidth) * 0.9, 0.01),
    );
  });

  testWidgets(
    'menu reduced open fades whole panel at fixed geometry and focuses',
    (tester) async {
      final controller = CLMenuController();
      final focusNode = FocusNode(debugLabel: 'menu-test-focus');
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        _host(
          CLMenu(
            controller: controller,
            anchor: const Icon(Icons.more_horiz),
            children: [
              Focus(focusNode: focusNode, child: const Text('Menu item')),
            ],
          ),
          reduced: true,
        ),
      );
      controller.open();
      await tester.pump();
      await tester.pump();
      final panel = _menuPanelFinder(tester);
      final sizeAtStart = tester.getSize(panel);
      expect(sizeAtStart.width, closeTo(260, 0.01));
      expect(_menuPanelOpacity(tester), closeTo(0, 0.01));
      await tester.pump(const Duration(milliseconds: 62));
      expect(tester.getSize(_menuPanelFinder(tester)), sizeAtStart);
      expect(_menuPanelOpacity(tester), greaterThan(0));
      expect(_menuPanelOpacity(tester), lessThan(1));
      await tester.pump(const Duration(milliseconds: 63));
      expect(tester.getSize(_menuPanelFinder(tester)), sizeAtStart);
      expect(_menuPanelOpacity(tester), closeTo(1, 0.01));
      expect(focusNode.hasFocus, isTrue);
    },
  );

  testWidgets(
    'menu reduced close fixes geometry, fades, unmounts, and restores focus',
    (tester) async {
      final controller = CLMenuController();
      final anchorFocus = FocusNode(debugLabel: 'anchor-focus');
      final menuFocus = FocusNode(debugLabel: 'menu-focus');
      addTearDown(controller.dispose);
      addTearDown(anchorFocus.dispose);
      addTearDown(menuFocus.dispose);
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                focusNode: anchorFocus,
                child: const SizedBox(width: 1, height: 1),
              ),
              CLMenu(
                controller: controller,
                anchor: const Icon(Icons.more_horiz),
                children: [
                  Focus(focusNode: menuFocus, child: const Text('Close item')),
                ],
              ),
            ],
          ),
          reduced: true,
        ),
      );
      anchorFocus.requestFocus();
      controller.open();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      expect(menuFocus.hasFocus, isTrue);
      final panel = _menuPanelFinder(tester);
      final openSize = tester.getSize(panel);

      controller.close();
      await tester.pump();
      expect(tester.getSize(_menuPanelFinder(tester)), openSize);
      expect(_menuPanelOpacity(tester), closeTo(1, 0.01));
      await tester.pump(const Duration(milliseconds: 62));
      expect(tester.getSize(_menuPanelFinder(tester)), openSize);
      expect(_menuPanelOpacity(tester), greaterThan(0));
      expect(_menuPanelOpacity(tester), lessThan(1));
      await tester.pump(const Duration(milliseconds: 63));
      if (find.text('Close item').evaluate().isNotEmpty) {
        expect(tester.getSize(_menuPanelFinder(tester)), openSize);
      }
      await tester.pumpAndSettle();
      expect(find.text('Close item'), findsNothing);
      expect(anchorFocus.hasFocus, isTrue);
    },
  );

  testWidgets('menu close reopened at 60ms ignores stale completion', (
    tester,
  ) async {
    final controller = CLMenuController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        CLMenu(
          controller: controller,
          anchor: const Icon(Icons.more_horiz),
          children: const [Text('Reopen item')],
        ),
        reduced: true,
      ),
    );
    controller.open();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    controller.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Reopen item'), findsOneWidget);
    final opacityBeforeReopen = _menuPanelOpacity(tester);
    expect(opacityBeforeReopen, greaterThan(0));
    expect(opacityBeforeReopen, lessThan(1));
    controller.open();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_menuPanelOpacity(tester), greaterThan(opacityBeforeReopen));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Reopen item'), findsOneWidget);
  });

  testWidgets(
    'menu snaps to full size when reduced motion toggles during open',
    (tester) async {
      final controller = CLMenuController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          CLMenu(
            controller: controller,
            anchor: const Icon(Icons.more_horiz),
            children: const [Text('Toggle item')],
          ),
        ),
      );
      controller.open();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final normalWidth = tester.getSize(_menuPanelFinder(tester)).width;
      expect(normalWidth, lessThan(260));
      _motionState(tester).setReduced(true);
      await tester.pump();
      expect(
        tester.getSize(_menuPanelFinder(tester)).width,
        closeTo(260, 0.01),
      );
    },
  );

  testWidgets('menu finishes close after reduced motion toggles mid-spring', (
    tester,
  ) async {
    final controller = CLMenuController();
    final anchorFocus = FocusNode(debugLabel: 'toggle-close-anchor');
    addTearDown(controller.dispose);
    addTearDown(anchorFocus.dispose);
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              focusNode: anchorFocus,
              child: const SizedBox(width: 1, height: 1),
            ),
            CLMenu(
              controller: controller,
              anchor: const Icon(Icons.more_horiz),
              children: const [Text('Toggle close item')],
            ),
          ],
        ),
      ),
    );
    anchorFocus.requestFocus();
    controller.open();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    controller.close();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Toggle close item'), findsOneWidget);
    _motionState(tester).setReduced(true);
    await tester.pump();
    expect(tester.getSize(_menuPanelFinder(tester)).width, closeTo(260, 0.01));
    await tester.pump(const Duration(milliseconds: 125));
    await tester.pumpAndSettle();

    expect(find.text('Toggle close item'), findsNothing);
    expect(anchorFocus.hasFocus, isTrue);
  });

  testWidgets(
    'popover keeps normal spring, toggles to identity, and unmounts after reduced close',
    (tester) async {
      final controller = CLPopoverController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          CLPopover(
            controller: controller,
            anchorBuilder: (context, popover) =>
                const SizedBox(width: 40, height: 40),
            popoverBuilder: (context, popover) => const SizedBox(
              key: Key('popover-content'),
              width: 100,
              height: 50,
            ),
          ),
        ),
      );
      controller.open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final normalScale = tester
          .widget<CLAnchoredOverlay>(find.byType(CLAnchoredOverlay))
          .scale;
      // The surface grows from the anchor: mid-grow, still below identity.
      expect(normalScale, greaterThan(0.7));
      expect(normalScale, lessThan(1));
      _motionState(tester).setReduced(true);
      await tester.pump();
      expect(
        tester.widget<CLAnchoredOverlay>(find.byType(CLAnchoredOverlay)).scale,
        1,
      );

      await tester.pump(const Duration(milliseconds: 125));
      _expectOverlayScale(tester);
      controller.close();
      await tester.pump();
      _expectOverlayScale(tester);
      await tester.pump(const Duration(milliseconds: 62));
      _expectOverlayScale(tester);
      await tester.pump(const Duration(milliseconds: 63));
      expect(_overlayOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('popover-content')), findsNothing);
      expect(_overlayMounted(tester), isFalse);
    },
  );

  testWidgets('popover reduced close yields to normal motion', (tester) async {
    final controller = CLPopoverController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        CLPopover(
          controller: controller,
          anchorBuilder: (context, popover) =>
              const SizedBox(width: 40, height: 40),
          popoverBuilder: (context, popover) => const SizedBox(
            key: Key('interrupted-popover'),
            width: 100,
            height: 50,
          ),
        ),
        reduced: true,
      ),
    );
    controller.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    controller.close();
    await tester.pump(const Duration(milliseconds: 40));
    _motionState(tester).setReduced(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 85));

    expect(find.byKey(const Key('interrupted-popover')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interrupted-popover')), findsNothing);
  });

  testWidgets(
    'tooltip keeps normal spring, toggles to identity, and fades before unmount',
    (tester) async {
      await tester.pumpWidget(
        _host(
          CLTooltip(
            delay: const Duration(milliseconds: 1),
            enableLongPress: false,
            message: 'Toggle tooltip',
            child: const SizedBox(
              key: Key('tooltip-anchor'),
              width: 40,
              height: 40,
            ),
          ),
        ),
      );
      final mouse = await _showTooltip(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final normalScale = tester
          .widget<CLAnchoredOverlay>(find.byType(CLAnchoredOverlay))
          .scale;
      // The surface grows from the anchor: mid-grow, still below identity.
      expect(normalScale, greaterThan(0.7));
      expect(normalScale, lessThan(1));
      _motionState(tester).setReduced(true);
      await tester.pump();
      expect(
        tester.widget<CLAnchoredOverlay>(find.byType(CLAnchoredOverlay)).scale,
        1,
      );
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      _expectOverlayScale(tester);
      await tester.pump(const Duration(milliseconds: 62));
      _expectOverlayScale(tester);
      await tester.pump(const Duration(milliseconds: 63));
      expect(_overlayOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pumpAndSettle();
      expect(find.text('Toggle tooltip'), findsNothing);
      expect(_overlayMounted(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets('tooltip reduced close yields to normal motion', (tester) async {
    await tester.pumpWidget(
      _host(
        CLTooltip(
          delay: const Duration(milliseconds: 1),
          enableLongPress: false,
          message: 'Interrupted tooltip',
          child: const SizedBox(
            key: Key('tooltip-anchor'),
            width: 40,
            height: 40,
          ),
        ),
        reduced: true,
      ),
    );
    final mouse = await _showTooltip(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 40));
    _motionState(tester).setReduced(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 85));

    expect(find.text('Interrupted tooltip'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Interrupted tooltip'), findsNothing);
  });
}
