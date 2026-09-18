import 'package:claralight_ui/claralight_ui.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('large value jumps settle without a visible rebound', (
    tester,
  ) async {
    var value = 1000.0;
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                width: 300,
                child: CLSlider(
                  min: 0,
                  max: 10000,
                  value: value,
                  onChanged: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );

    final thumb = find.byWidgetPredicate(
      (widget) =>
          widget is Positioned &&
          widget.width == CLSlider.thumbWidth &&
          widget.height == CLSlider.thumbHeight,
    );
    double thumbLeft() => tester.widget<Positioned>(thumb).left!;

    update(() => value = 9000);
    await tester.pump();

    final positions = <double>[thumbLeft()];
    for (var frame = 0; frame < 90; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      positions.add(thumbLeft());
    }

    final target = (300 - CLSlider.thumbWidth) * 0.9;
    expect(positions.last, closeTo(target, 0.05));
    expect(
      positions.reduce((a, b) => a > b ? a : b),
      lessThanOrEqualTo(target + 0.01),
    );
    for (var index = 1; index < positions.length; index++) {
      expect(
        positions[index],
        greaterThanOrEqualTo(positions[index - 1] - 0.01),
      );
    }
  });

  _sliderShapeTests();
  _sliderBubbleTests();
}

/// Track pieces are the flat ones, the handle is the tall one that is not the
/// full-height hover box.
List<Positioned> _positioned(WidgetTester tester) =>
    tester.widgetList<Positioned>(find.byType(Positioned)).toList();

List<Positioned> _segments(WidgetTester tester) => _positioned(
  tester,
).where((widget) => widget.height! <= CLSlider.trackHeight).toList();

Positioned _handle(WidgetTester tester) => _positioned(tester).firstWhere(
  (widget) =>
      widget.height! > CLSlider.trackHeight &&
      widget.height != CLSlider.hitHeight,
);

Positioned _hoverBox(WidgetTester tester) => _positioned(
  tester,
).firstWhere((widget) => widget.height == CLSlider.hitHeight);

Widget _slider({double value = 0.5}) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 300,
      child: CLSlider(value: value, onChanged: (_) {}),
    ),
  ),
);

void _sliderShapeTests() {
  testWidgets('track keeps the progress gap either side of the handle', (
    tester,
  ) async {
    await tester.pumpWidget(_slider());

    final handle = _handle(tester);
    expect(handle.width, CLSlider.thumbWidth);
    expect(handle.height, CLSlider.thumbHeight);
    expect(handle.left, closeTo((300 - CLSlider.thumbWidth) * 0.5, 0.01));

    final segments = _segments(tester);
    expect(segments, hasLength(2));
    final active = segments.first;
    final track = segments.last;
    expect(active.left, 0);
    expect(active.width, closeTo(handle.left! - CLSlider.gap, 0.01));
    expect(
      track.left,
      closeTo(handle.left! + CLSlider.thumbWidth + CLSlider.gap, 0.01),
    );
    expect(track.width, closeTo(300 - track.left!, 0.01));
    for (final segment in segments) {
      expect(segment.height, CLSlider.trackHeight);
    }
  });

  testWidgets('a segment with less room than the gap is dropped, and a short '
      'one collapses to a dot', (tester) async {
    await tester.pumpWidget(_slider(value: 0));
    expect(_segments(tester), hasLength(1));
    expect(_segments(tester).single.left, CLSlider.thumbWidth + CLSlider.gap);

    // Three pixels of active track left of the handle: too short to be six
    // pixels tall, so it keeps its roundness and gives up its height.
    await tester.pumpWidget(_slider(value: 7 / (300 - CLSlider.thumbWidth)));
    await tester.pumpAndSettle();
    final active = _segments(tester).first;
    expect(active.width, closeTo(3, 0.05));
    expect(active.height, active.width);
  });

  testWidgets('the rail keeps its width at either end of the range', (
    tester,
  ) async {
    // A loosely constrained parent is what exposes this: a stack with any
    // unpositioned child takes that child's size, so an empty segment left in
    // the stack collapses the whole slider to nothing.
    for (final value in [0.0, 1.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [CLSlider(value: value, onChanged: (_) {})],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CLSlider)).width, 300);
    }
  });

  testWidgets('the line reaches both ends of the rail', (tester) async {
    await tester.pumpWidget(_slider(value: 0));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getTopLeft(find.byType(CLSlider)) +
          const Offset(2, CLSlider.hitHeight / 2),
    );
    await tester.pumpAndSettle();
    expect(_handle(tester).left, closeTo(0, 0.01));

    await tester.pumpWidget(_slider(value: 1));
    await tester.pumpAndSettle();
    final handle = _handle(tester);
    expect(handle.left! + handle.width!, closeTo(300, 0.01));
  });

  testWidgets('hover narrows the handle to a line at a fixed hover box', (
    tester,
  ) async {
    await tester.pumpWidget(_slider());

    final restingBox = _hoverBox(tester);
    expect(restingBox.width, CLSlider.hoverWidth);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(CLSlider)));
    await tester.pumpAndSettle();

    final handle = _handle(tester);
    expect(handle.width, closeTo(CLSlider.hoverLineWidth, 0.01));
    expect(handle.height, closeTo(CLSlider.hoverLineHeight, 0.01));

    // The box that answers to the pointer does not follow the line in.
    final hoveredBox = _hoverBox(tester);
    expect(hoveredBox.width, CLSlider.hoverWidth);
    expect(hoveredBox.left, closeTo(restingBox.left!, 0.01));

    // The track backs off the line rather than the capsule.
    final segments = _segments(tester);
    expect(segments.first.width, closeTo(handle.left! - CLSlider.gap, 0.01));

    await gesture.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_handle(tester).width, CLSlider.thumbWidth);
  });

  testWidgets(
    'hovering on the right side of the handle at value 0 does not flicker',
    (tester) async {
      await tester.pumpWidget(_slider(value: 0));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      // Hover over the right half of the resting capsule at value 0 (e.g. x = 16).
      final topLeft = tester.getTopLeft(find.byType(CLSlider));
      await gesture.moveTo(topLeft + const Offset(16, CLSlider.hitHeight / 2));
      await tester.pumpAndSettle();

      // Must be hovered steadily as a line without flickering back to capsule.
      final handle = _handle(tester);
      expect(handle.width, closeTo(CLSlider.hoverLineWidth, 0.01));
      expect(_hoverBox(tester).left, lessThanOrEqualTo(0));
      expect(
        _hoverBox(tester).left! + _hoverBox(tester).width!,
        greaterThanOrEqualTo(20),
      );

      // Pump additional frames to verify stability (no recursive flicker).
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_handle(tester).width, closeTo(CLSlider.hoverLineWidth, 0.01));
    },
  );

  testWidgets('shows grab cursor on hover and grabbing cursor while pressed', (
    tester,
  ) async {
    await tester.pumpWidget(_slider());

    final gesture = await tester.createGesture(
      pointer: 1,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: tester.getCenter(find.byType(CLSlider)));
    addTearDown(gesture.removePointer);
    await tester.pumpAndSettle();

    // Hover over handle: grab
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grab,
    );

    // Press down: grabbing everywhere, even far away
    await gesture.down(tester.getCenter(find.byType(CLSlider)));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(1, 0));
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grabbing,
    );

    // Drag far away from the slider track: remains grabbing!
    await gesture.moveBy(const Offset(30, 120));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grabbing,
    );

    // Release: returns to basic (since pointer was dragged far away)
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );
  });
}

Widget _labelledSlider({
  double value = 0.5,
  ValueChanged<double>? onChanged,
  String Function(double)? valueLabel,
}) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 300,
      child: CLSlider(
        value: value,
        onChanged: onChanged ?? (_) {},
        valueLabel: valueLabel ?? (v) => '${(v * 100).round()}%',
      ),
    ),
  ),
);

Finder _bubble = find.byType(CompositedTransformFollower);

double _bubbleTilt(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(of: _bubble, matching: find.byType(Transform)).first,
  );
  final storage = transform.transform.storage;
  return math.atan2(storage[1], storage[0]);
}

void _sliderBubbleTests() {
  testWidgets('no bubble without a valueLabel', (tester) async {
    await tester.pumpWidget(_slider());
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(CLSlider)));
    await tester.pumpAndSettle();

    expect(_bubble, findsNothing);
    expect(find.byType(CLNumericText), findsNothing);
  });

  testWidgets('hover lifts a bubble off the handle and drops it again', (
    tester,
  ) async {
    await tester.pumpWidget(_labelledSlider());
    expect(_bubble, findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(CLSlider)));
    await tester.pumpAndSettle();

    expect(find.byType(CLNumericText), findsOneWidget);
    expect(find.bySemanticsLabel('50%'), findsOneWidget);

    // The overlay constrains its children tightly; the bubble must keep its own
    // size inside that rather than being stretched to the whole overlay.
    final size = tester.getSize(_bubble);
    expect(size.width, lessThan(80));
    expect(
      size.height,
      closeTo(
        tester.getSize(find.byType(CLNumericText)).height +
            CLSlider.bubblePadding.vertical +
            CLSlider.bubbleTailExtent,
        0.5,
      ),
    );

    final follower = tester.widget<CompositedTransformFollower>(_bubble);
    // The foot hangs on the handle's centre, a gap above the line.
    expect(follower.followerAnchor, Alignment.bottomCenter);
    expect(
      follower.offset.dx,
      closeTo(
        (300 - CLSlider.thumbWidth) * 0.5 + CLSlider.thumbWidth / 2,
        0.01,
      ),
    );
    expect(
      follower.offset.dy,
      closeTo(
        CLSlider.hitHeight / 2 -
            CLSlider.hoverLineHeight / 2 -
            CLSlider.bubbleTipClearance,
        0.01,
      ),
    );

    await gesture.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_bubble, findsNothing);
  });

  testWidgets('bubble uses CLNumericText to present value updates', (
    tester,
  ) async {
    var value = 0.5;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                width: 300,
                child: CLSlider(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                  valueLabel: (v) => '${(v * 100).round()}%',
                ),
              );
            },
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(CLSlider)));
    await tester.pumpAndSettle();

    expect(find.byType(CLNumericText), findsOneWidget);
    expect(find.bySemanticsLabel('50%'), findsOneWidget);

    update(() => value = 0.75);
    await tester.pump();
    expect(find.bySemanticsLabel('75%'), findsOneWidget);
  });

  testWidgets('bubble scales up from bottom without translating vertically', (
    tester,
  ) async {
    await tester.pumpWidget(_labelledSlider());
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(CLSlider)));
    // Advance halfway through the opening animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(_bubble, findsOneWidget);
    final follower = tester.widget<CompositedTransformFollower>(_bubble);
    // Vertical offset is fixed to flight, not translated up from the track.
    expect(
      follower.offset.dy,
      closeTo(
        CLSlider.hitHeight / 2 -
            CLSlider.hoverLineHeight / 2 -
            CLSlider.bubbleTipClearance,
        0.01,
      ),
    );

    // Scaling is applied with bottomCenter alignment so it pops from the tail tip.
    final transforms = tester.widgetList<Transform>(
      find.descendant(of: _bubble, matching: find.byType(Transform)),
    );
    final scaleTransform = transforms.elementAt(1);
    expect(scaleTransform.alignment, Alignment.bottomCenter);
    final scaleMatrix = scaleTransform.transform.storage;
    final scaleValue = scaleMatrix[0];
    expect(scaleValue, greaterThan(0.0));
    expect(scaleValue, lessThanOrEqualTo(1.05));

    await tester.pumpAndSettle();
  });

  testWidgets('the balloon trails the drag and swings back level', (
    tester,
  ) async {
    var value = 0.2;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 300,
              child: CLSlider(
                value: value,
                onChanged: (next) => setState(() => value = next),
                valueLabel: (v) => '${(v * 100).round()}%',
              ),
            ),
          ),
        ),
      ),
    );

    final drag = await tester.startGesture(
      tester.getCenter(find.byType(CLSlider)) - const Offset(90, 0),
    );
    // Past the touch slop, so the arena settles on the horizontal drag.
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(_bubble, findsOneWidget);

    await drag.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 16));
    // Dragged right, so the top of the balloon is left of its foot.
    expect(_bubbleTilt(tester), lessThan(0));
    expect(_bubbleTilt(tester), greaterThanOrEqualTo(-CLSlider.bubbleMaxTilt));

    await tester.pumpAndSettle();
    expect(_bubbleTilt(tester), closeTo(0, 0.001));

    await drag.up();
    await tester.pumpAndSettle();
    expect(_bubble, findsNothing);
  });

  testWidgets('the balloon swings even when dragging after pausing or hovering', (
    tester,
  ) async {
    var value = 0.5;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 300,
              child: CLSlider(
                value: value,
                onChanged: (next) => setState(() => value = next),
                valueLabel: (v) => '${(v * 100).round()}%',
              ),
            ),
          ),
        ),
      ),
    );

    // 1. First, hover and let the bubble fully settle (which stops the ticker).
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(CLSlider)));
    await tester.pumpAndSettle();
    expect(_bubble, findsOneWidget);
    expect(_bubbleTilt(tester), 0);

    // 2. Now drag rightwards: ticker must reactivate and tilt the balloon.
    final center = tester.getCenter(find.byType(CLSlider));
    await mouse.down(center);
    await mouse.moveBy(const Offset(30, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    await mouse.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_bubbleTilt(tester), lessThan(0));

    // 3. Pause mid-drag and let it settle.
    await tester.pumpAndSettle();
    expect(_bubbleTilt(tester), closeTo(0, 0.001));

    // 4. Drag leftwards: ticker must reactivate again and tilt rightwards.
    await mouse.moveBy(const Offset(-30, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    await mouse.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_bubbleTilt(tester), greaterThan(0));

    await mouse.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'handle restores to capsule after drag ends even if cursor is outside',
    (tester) async {
      var value = 0.5;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 300,
                child: CLSlider(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      // Click and drag, releasing outside the hover box.
      await gesture.moveTo(tester.getCenter(find.byType(CLSlider)));
      await gesture.down(tester.getCenter(find.byType(CLSlider)));
      await gesture.moveBy(const Offset(80, 50));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Handle must restore to full capsule width.
      expect(_handle(tester).width, CLSlider.thumbWidth);
    },
  );

  testWidgets('balloon tilt angle is not artificially clamped to 12 degrees', (
    tester,
  ) async {
    var value = 0.2;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 300,
              child: CLSlider(
                value: value,
                onChanged: (next) => setState(() => value = next),
                valueLabel: (v) => '${(v * 100).round()}%',
              ),
            ),
          ),
        ),
      ),
    );
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(CLSlider)) - const Offset(90, 0),
    );
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // Fast drag moveBy.
    await drag.moveBy(const Offset(90, 0));
    await tester.pump(const Duration(milliseconds: 16));
    // Tilt must exceed the old 12° artificial clamp.
    expect(_bubbleTilt(tester).abs(), greaterThan(15 * math.pi / 180));

    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion keeps the bubble level and at fixed geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _labelledSlider(),
      ),
    );

    final drag = await tester.startGesture(
      tester.getCenter(find.byType(CLSlider)) - const Offset(90, 0),
    );
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    final lifted = tester.widget<CompositedTransformFollower>(_bubble);
    expect(
      lifted.offset.dy,
      closeTo(
        CLSlider.hitHeight / 2 -
            CLSlider.hoverLineHeight / 2 -
            CLSlider.bubbleTipClearance,
        0.01,
      ),
    );

    await drag.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_bubbleTilt(tester), 0);

    await drag.up();
    await tester.pumpAndSettle();
    expect(_bubble, findsNothing);
  });

  testWidgets('the label is what assistive technology reads', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_labelledSlider(value: 0.25));
    expect(tester.getSemantics(find.byType(CLSlider)).value, '25%');
    handle.dispose();
  });
}
