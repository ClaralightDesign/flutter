import 'package:claralight_ui/claralight_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
}
