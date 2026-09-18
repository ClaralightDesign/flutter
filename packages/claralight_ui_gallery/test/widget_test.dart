import 'package:claralight_ui/claralight_ui.dart';
import 'package:claralight_ui_gallery/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _groupBranchKey = Key('tree-group-2-branch');
const _containerBranchKey = Key('tree-container-1-branch');
const _subtreeBranchKey = Key('tree-group-1-branch');

Finder _tile(String label) => find.byWidgetPredicate(
  (widget) => widget is CLListTile && widget.label == label,
  skipOffstage: false,
);

Finder _text(String label) => find.text(label, skipOffstage: false);

Finder _branch(Key key) => find.byKey(key, skipOffstage: false);

Widget _galleryHost({bool disableAnimations = false}) {
  return CLTheme(
    data: CLThemeData(),
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(1600, 2400),
          disableAnimations: disableAnimations,
        ),
        child: GalleryHome(
          brightness: Brightness.dark,
          onBrightnessChanged: (_) {},
        ),
      ),
    ),
  );
}

Future<void> _pumpGalleryHost(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(_galleryHost(disableAnimations: disableAnimations));
  // Scrollability is measured post-frame; settle the edge-effect wrapper
  // before tests retain descendant state or geometry.
  await tester.pump();
  await tester.pump();
}

void _useLargeView(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 2400);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void _toggleTile(WidgetTester tester, String label) {
  tester.widget<CLListTile>(_tile(label)).onTap!();
}

Future<void> _tapTile(WidgetTester tester, String label) async {
  await tester.ensureVisible(_tile(label));
  await tester.pump();
  await tester.tap(_tile(label));
}

Future<void> _flushVisibilityUpdates(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 500));
}

void _galleryTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } finally {
      await _flushVisibilityUpdates(tester);
    }
  });
}

T _branchDescendant<T extends Widget>(WidgetTester tester, Key key) {
  T? result;

  void visit(Element element) {
    if (result != null) return;
    if (element.widget case final T widget) {
      result = widget;
      return;
    }
    element.visitChildren(visit);
  }

  tester.element(_branch(key)).visitChildren(visit);
  return result!;
}

double _branchOpacity(WidgetTester tester, Key key) =>
    _branchDescendant<Opacity>(tester, key).opacity;

bool _hasSemanticsLabel(WidgetTester tester, String label) {
  return tester.semantics.simulatedAccessibilityTraversal().any((node) {
    return node.getSemanticsData().label.split('\n').contains(label);
  });
}

void main() {
  setUpAll(CLScrollable.precache);

  _galleryTestWidgets('Gallery tolerates transient zero and phone viewports', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size.zero;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const GalleryApp());
    await tester.pump();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(375.38, 817.23);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    final addButtons = find.byWidgetPredicate(
      (widget) => widget is CLIconButton && widget.icon == Icons.add_rounded,
    );
    final disabledButton = find.byWidgetPredicate(
      (widget) => widget is CLIconButton && widget.icon == Icons.block_rounded,
    );
    expect(
      tester.getTopLeft(disabledButton).dy,
      greaterThan(tester.getTopLeft(addButtons.first).dy),
    );
  });

  _galleryTestWidgets('Gallery shows the Claralight component sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GalleryApp());
    await tester.pump();

    expect(find.text('Claralight UI'), findsOneWidget);
    expect(find.text('CLButton'), findsOneWidget);
    expect(find.text('CLToggle'), findsOneWidget);
    expect(find.text('CLSegmentedControl'), findsOneWidget);
    expect(find.text('CLNumericText'), findsOneWidget);
    expect(find.text('CLDialog'), findsOneWidget);
    expect(find.text('CLMenu'), findsOneWidget);
    expect(find.byType(CLButton), findsWidgets);
    expect(find.byType(CLToggle), findsWidgets);
    expect(find.byType(CLSegmentedControl), findsWidgets);
    expect(find.byType(CLNumericText), findsOneWidget);
    expect(find.byType(CLColorSwatchGroup), findsWidgets);
    expect(find.byType(CLProgressBar), findsWidgets);
    expect(find.byType(CLMenu), findsWidgets);
    expect(find.byType(CLTextArea), findsNWidgets(4));
    expect(find.byType(CLTreeView), findsOneWidget);

    final fixedTextArea = tester.widget<CLTextArea>(
      find.byKey(const Key('fixed-text-area-demo')),
    );
    final autoTextArea = tester.widget<CLTextArea>(
      find.byKey(const Key('auto-text-area-demo')),
    );
    final readOnlyTextArea = tester.widget<CLTextArea>(
      find.byKey(const Key('read-only-text-area-demo')),
    );
    final errorTextArea = tester.widget<CLTextArea>(
      find.byKey(const Key('error-text-area-demo')),
    );
    expect(fixedTextArea.minHeight, 120);
    expect(fixedTextArea.maxHeight, 120);
    expect(fixedTextArea.controller?.text.split('\n'), hasLength(5));
    final fixedScrollable = tester.widget<CLScrollable>(
      find.descendant(
        of: find.byKey(const Key('fixed-text-area-demo')),
        matching: find.byType(CLScrollable),
      ),
    );
    expect(
      fixedScrollable.verticalController!.position.maxScrollExtent,
      greaterThan(0),
    );
    expect(autoTextArea.minHeight, 80);
    expect(autoTextArea.maxHeight, 160);
    expect(readOnlyTextArea.readOnly, isTrue);
    expect(errorTextArea.error, isTrue);
    expect(
      tester
          .widget<CLButton>(find.byKey(const Key('primary-button-demo')))
          .variant,
      CLButtonVariant.primary,
    );
    expect(
      tester
          .widget<CLButton>(find.byKey(const Key('danger-button-demo')))
          .variant,
      CLButtonVariant.danger,
    );
    expect(
      tester
          .widget<CLIconButton>(
            find.byKey(const Key('primary-icon-button-demo')),
          )
          .variant,
      CLIconButtonVariant.primary,
    );
    expect(
      tester
          .widget<CLIconButton>(
            find.byKey(const Key('danger-icon-button-demo')),
          )
          .variant,
      CLIconButtonVariant.danger,
    );

    final galleryScroll = tester.widget<CLScrollable>(
      find.byKey(const Key('gallery-scroll')),
    );
    expect(galleryScroll.direction, CLScrollDirection.vertical);
    expect(galleryScroll.horizontalScrollbar, CLScrollbarVisibility.hidden);
    expect(
      tester.getSize(find.byKey(const Key('gallery-scroll'))).width,
      tester.getSize(find.byType(SafeArea)).width,
    );

    final subtreeLeaf = tester.widget<CLListTile>(_tile('矩形 1'));
    expect(subtreeLeaf.depth, 2);
    expect(find.byKey(const Key('three-action-dialog-demo')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });

  _galleryTestWidgets('overflow toolbar promotes the selected menu tool', (
    WidgetTester tester,
  ) async {
    _useLargeView(tester);
    await _pumpGalleryHost(tester, disableAnimations: true);

    final more = find.byKey(const Key('overflow-toolbar-more'));
    await tester.ensureVisible(more);
    await tester.pump();

    expect(tester.widget<CLIconButton>(more).selected, isFalse);
    expect(find.byKey(const Key('overflow-toolbar-tool-4')), findsOneWidget);
    expect(find.byKey(const Key('overflow-toolbar-tool-6')), findsNothing);

    await tester.tap(more);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final exportRow = find.byKey(const Key('overflow-menu-tool-6'));
    final overflowList = find.ancestor(
      of: exportRow,
      matching: find.byType(CLList),
    );
    expect(exportRow, findsOneWidget);
    expect(tester.getSize(overflowList).width, lessThan(140));

    await tester.tap(exportRow);
    await tester.pump(const Duration(milliseconds: 200));

    final selectedTool = find.byKey(const Key('overflow-toolbar-tool-6'));
    expect(selectedTool, findsOneWidget);
    expect(find.byKey(const Key('overflow-toolbar-tool-4')), findsNothing);
    expect(
      tester.getCenter(selectedTool).dx,
      lessThan(tester.getCenter(more).dx),
    );
    expect(tester.widget<CLIconButton>(selectedTool).selected, isTrue);
    expect(tester.widget<CLIconButton>(more).selected, isFalse);
  });

  _galleryTestWidgets('tooltip position control updates the demo', (
    WidgetTester tester,
  ) async {
    _useLargeView(tester);
    await _pumpGalleryHost(tester);

    final control = find.byKey(const Key('tooltip-position-control'));
    final tooltip = find.byKey(const Key('tooltip-demo'));
    await tester.ensureVisible(control);
    await tester.pump();

    expect(tester.widget<CLTooltip>(tooltip).position, CLPopoverPosition.top);

    tester.widget<CLSegmentedControl>(control).onChanged!(3);
    await tester.pump();

    expect(tester.widget<CLTooltip>(tooltip).position, CLPopoverPosition.right);
  });

  _galleryTestWidgets('animated number demo exercises formatted retargets', (
    WidgetTester tester,
  ) async {
    _useLargeView(tester);
    final semantics = tester.ensureSemantics();
    await _pumpGalleryHost(tester);

    final number = find.byKey(const Key('animated-number-demo'));
    await tester.ensureVisible(number);
    await tester.pump();
    expect(tester.widget<CLNumericText>(number).value, 123450);
    expect(find.bySemanticsLabel(r'$1,234.50'), findsOneWidget);

    await tester.tap(find.byKey(const Key('animated-number-increment')));
    await tester.pump();
    expect(tester.widget<CLNumericText>(number).value, 124649);
    expect(find.bySemanticsLabel(r'$1,246.49'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const Key('animated-number-cycle')));
    await tester.pump();
    expect(tester.widget<CLNumericText>(number).value, 99999900);
    expect(find.bySemanticsLabel(r'$999,999.00'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    semantics.dispose();
  });

  _galleryTestWidgets('tree branch animates height and opacity for 160ms', (
    WidgetTester tester,
  ) async {
    _useLargeView(tester);
    await _pumpGalleryHost(tester);

    final branch = _branch(_groupBranchKey);
    final container = _branch(_containerBranchKey);
    final header = _tile('组 2');
    final expandedHeight = tester.getSize(branch).height;
    final initialBranchState = tester.state(branch);
    final initialContainerTop = tester.getTopLeft(container).dy;

    expect(expandedHeight, 113);
    expect(MediaQuery.disableAnimationsOf(tester.element(branch)), isFalse);
    expect(_branchOpacity(tester, _groupBranchKey), 1);

    _toggleTile(tester, '组 2');
    await tester.pump();
    expect(tester.state(branch), same(initialBranchState));
    await tester.pump(const Duration(milliseconds: 40));
    final heightAt40ms = tester.getSize(branch).height;
    final opacityAt40ms = _branchOpacity(tester, _groupBranchKey);
    final containerTopAt40ms = tester.getTopLeft(container).dy;

    await tester.pump(const Duration(milliseconds: 40));
    final heightAt80ms = tester.getSize(branch).height;
    final opacityAt80ms = _branchOpacity(tester, _groupBranchKey);
    final containerTopAt80ms = tester.getTopLeft(container).dy;

    expect(heightAt40ms, inExclusiveRange(35, expandedHeight));
    expect(heightAt80ms, inExclusiveRange(35, heightAt40ms));
    expect(opacityAt40ms, inExclusiveRange(0, 1));
    expect(opacityAt80ms, inExclusiveRange(0, opacityAt40ms));
    expect(containerTopAt40ms, lessThan(initialContainerTop));
    expect(containerTopAt80ms, lessThan(containerTopAt40ms));
    expect(_text('进度条 1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(microseconds: 1));

    expect(_text('进度条 1'), findsNothing);
    expect(_text('序列帧 1'), findsNothing);
    expect(tester.getSize(branch).height, 35);
    expect(
      tester.getTopLeft(container).dy - tester.getBottomLeft(header).dy,
      4,
    );
  });

  _galleryTestWidgets(
    'collapsing branch gates hits and semantics immediately',
    (WidgetTester tester) async {
      _useLargeView(tester);
      final semantics = tester.ensureSemantics();
      await _pumpGalleryHost(tester);
      await tester.ensureVisible(_tile('进度条 1'));
      await tester.pump();

      expect(_hasSemanticsLabel(tester, '进度条 1'), isTrue);
      _toggleTile(tester, '组 2');
      await tester.pump();

      expect(
        _branchDescendant<IgnorePointer>(tester, _groupBranchKey).ignoring,
        isTrue,
      );
      expect(find.text('进度条 1'), findsOneWidget);
      expect(_hasSemanticsLabel(tester, '进度条 1'), isFalse);
      expect(_hasSemanticsLabel(tester, '组 2'), isTrue);
      expect(_text('进度条 1').hitTestable(), findsNothing);

      await tester.tap(_text('进度条 1'), warnIfMissed: false);
      await tester.pump();
      expect(tester.widget<CLListTile>(_tile('组 2')).expanded, isFalse);
      expect(tester.widget<CLListTile>(_tile('容器 1')).expanded, isTrue);

      await _tapTile(tester, '组 2');
      await tester.pump();
      expect(tester.widget<CLListTile>(_tile('组 2')).expanded, isTrue);
      expect(_hasSemanticsLabel(tester, '进度条 1'), isTrue);
      await tester.pump(const Duration(milliseconds: 160));
      semantics.dispose();
    },
  );

  _galleryTestWidgets(
    'tree branch reverses continuously and honors the last target',
    (WidgetTester tester) async {
      _useLargeView(tester);
      await _pumpGalleryHost(tester);

      final branch = _branch(_groupBranchKey);
      void expectSingleChildren() {
        expect(_text('进度条 1'), findsOneWidget);
        expect(_text('序列帧 1'), findsOneWidget);
      }

      _toggleTile(tester, '组 2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final collapseHeight = tester.getSize(branch).height;
      final collapseOpacity = _branchOpacity(tester, _groupBranchKey);
      expectSingleChildren();

      _toggleTile(tester, '组 2');
      await tester.pump();
      expect(tester.getSize(branch).height, closeTo(collapseHeight, 0.001));
      expect(
        _branchOpacity(tester, _groupBranchKey),
        closeTo(collapseOpacity, 0.001),
      );
      await tester.pump(const Duration(milliseconds: 40));
      final expandHeight = tester.getSize(branch).height;
      final expandOpacity = _branchOpacity(tester, _groupBranchKey);
      expect(expandHeight, greaterThan(collapseHeight));
      expect(expandOpacity, greaterThan(collapseOpacity));
      expectSingleChildren();

      _toggleTile(tester, '组 2');
      await tester.pump();
      expect(tester.getSize(branch).height, closeTo(expandHeight, 0.001));
      expect(
        _branchOpacity(tester, _groupBranchKey),
        closeTo(expandOpacity, 0.001),
      );
      await tester.pump(const Duration(milliseconds: 40));
      final secondCollapseHeight = tester.getSize(branch).height;
      final secondCollapseOpacity = _branchOpacity(tester, _groupBranchKey);
      expect(secondCollapseHeight, lessThan(expandHeight));
      expect(secondCollapseOpacity, lessThan(expandOpacity));
      expectSingleChildren();

      _toggleTile(tester, '组 2');
      await tester.pump();
      expect(
        tester.getSize(branch).height,
        closeTo(secondCollapseHeight, 0.001),
      );
      expect(
        _branchOpacity(tester, _groupBranchKey),
        closeTo(secondCollapseOpacity, 0.001),
      );
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.getSize(branch).height, 113);
      expect(_branchOpacity(tester, _groupBranchKey), 1);
      expectSingleChildren();

      _toggleTile(tester, '组 2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump(const Duration(microseconds: 1));
      expect(tester.getSize(branch).height, 35);
      expect(_text('进度条 1'), findsNothing);
      expect(_text('序列帧 1'), findsNothing);
    },
  );

  _galleryTestWidgets(
    'nested tree preserves expanded geometry and independent state',
    (WidgetTester tester) async {
      _useLargeView(tester);
      await _pumpGalleryHost(tester);

      const labels = [
        'Frame 114',
        '图组 1',
        '文字 1',
        '组 2',
        '进度条 1',
        '序列帧 1',
        '容器 1',
        '组 1',
        '矩形 1',
        '文字 2',
      ];
      for (final label in labels) {
        expect(tester.getSize(_tile(label)).height, 35);
      }
      for (var i = 1; i < labels.length; i++) {
        expect(
          tester.getTopLeft(_tile(labels[i])).dy -
              tester.getBottomLeft(_tile(labels[i - 1])).dy,
          4,
        );
      }

      expect(tester.widget<CLListTile>(_tile('组 1')).depth, 1);
      expect(tester.widget<CLListTile>(_tile('矩形 1')).depth, 2);
      final groupIcon = find.descendant(
        of: _tile('组 1'),
        matching: find.byIcon(Icons.crop_free_rounded),
      );
      final leafIcon = find.descendant(
        of: _tile('矩形 1'),
        matching: find.byIcon(Icons.rectangle_outlined),
      );
      expect(
        tester.getTopLeft(groupIcon).dx - tester.getTopLeft(_tile('组 1')).dx,
        32,
      );
      expect(
        tester.getTopLeft(leafIcon).dx - tester.getTopLeft(_tile('矩形 1')).dx,
        56,
      );

      final treeScrollable = find.descendant(
        of: find.byType(CLTreeView),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(treeScrollable).position.maxScrollExtent,
        78,
      );

      _toggleTile(tester, '组 1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump(const Duration(microseconds: 1));
      expect(_text('矩形 1'), findsNothing);
      expect(tester.getSize(_branch(_subtreeBranchKey)).height, 35);
      expect(tester.getSize(_branch(_containerBranchKey)).height, 74);
      expect(tester.widget<CLListTile>(_tile('容器 1')).expanded, isTrue);

      _toggleTile(tester, '容器 1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump(const Duration(microseconds: 1));
      expect(_branch(_subtreeBranchKey), findsNothing);

      _toggleTile(tester, '容器 1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(_branch(_subtreeBranchKey), findsOneWidget);
      expect(_text('矩形 1'), findsNothing);

      _toggleTile(tester, '组 1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(_text('矩形 1'), findsOneWidget);
      expect(_text('文字 2'), findsOneWidget);
    },
  );

  _galleryTestWidgets('reduced motion snaps every tree branch', (
    WidgetTester tester,
  ) async {
    _useLargeView(tester);
    final semantics = tester.ensureSemantics();
    await _pumpGalleryHost(tester, disableAnimations: true);

    expect(tester.getSize(_branch(_groupBranchKey)).height, 113);
    _toggleTile(tester, '组 2');
    await tester.pump();
    expect(tester.getSize(_branch(_groupBranchKey)).height, 35);
    expect(_text('进度条 1'), findsNothing);
    expect(_hasSemanticsLabel(tester, '进度条 1'), isFalse);

    await _tapTile(tester, '组 2');
    await tester.pump();
    expect(tester.getSize(_branch(_groupBranchKey)).height, 113);
    expect(_text('进度条 1'), findsOneWidget);
    expect(_hasSemanticsLabel(tester, '进度条 1'), isTrue);

    await _tapTile(tester, '容器 1');
    await tester.pump();
    expect(tester.getSize(_branch(_containerBranchKey)).height, 35);
    expect(_branch(_subtreeBranchKey), findsNothing);
    expect(_hasSemanticsLabel(tester, '组 1'), isFalse);

    await _tapTile(tester, '容器 1');
    await tester.pump();
    expect(tester.getSize(_branch(_containerBranchKey)).height, 152);
    expect(_branch(_subtreeBranchKey), findsOneWidget);
    expect(_text('矩形 1'), findsOneWidget);

    await _tapTile(tester, '组 1');
    await tester.pump();
    expect(tester.getSize(_branch(_subtreeBranchKey)).height, 35);
    expect(_text('矩形 1'), findsNothing);
    expect(_hasSemanticsLabel(tester, '矩形 1'), isFalse);

    await _tapTile(tester, '组 1');
    await tester.pump();
    expect(tester.getSize(_branch(_subtreeBranchKey)).height, 113);
    expect(_text('矩形 1'), findsOneWidget);
    expect(_hasSemanticsLabel(tester, '矩形 1'), isTrue);
    semantics.dispose();
  });

  _galleryTestWidgets(
    'enabling reduced motion snaps an in-flight tree branch',
    (WidgetTester tester) async {
      _useLargeView(tester);
      var disableAnimations = false;
      late StateSetter updateHost;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return _galleryHost(disableAnimations: disableAnimations);
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      _toggleTile(tester, '组 2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.getSize(_branch(_groupBranchKey)).height,
        inExclusiveRange(35, 113),
      );

      updateHost(() => disableAnimations = true);
      await tester.pump();
      expect(tester.getSize(_branch(_groupBranchKey)).height, 35);
      expect(_text('进度条 1'), findsNothing);

      updateHost(() => disableAnimations = false);
      await tester.pump();
      _toggleTile(tester, '组 2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.getSize(_branch(_groupBranchKey)).height,
        inExclusiveRange(35, 113),
      );

      updateHost(() => disableAnimations = true);
      await tester.pump();
      expect(tester.getSize(_branch(_groupBranchKey)).height, 113);
      expect(_text('进度条 1'), findsOneWidget);
    },
  );

  _galleryTestWidgets('Gallery opens the three-action dialog demo', (
    tester,
  ) async {
    await tester.pumpWidget(const GalleryApp());
    await tester.pump();

    final demoButton = tester.widget<CLButton>(
      find.byKey(const Key('three-action-dialog-demo')),
    );
    demoButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('保存更改'), findsOneWidget);
    expect(tester.getSize(find.byType(CLDialog)).width, 320);
    expect(find.text('关闭前是否保存当前更改？'), findsOneWidget);
    expect(find.text('保存并关闭'), findsOneWidget);
    expect(find.text('不保存'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  _galleryTestWidgets('Gallery switches between dark and light themes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GalleryApp());
    await tester.pump();

    CLTheme theme() => tester.widget<CLTheme>(find.byType(CLTheme));

    expect(theme().data.colors.brightness, Brightness.dark);

    final modeControl = find.byKey(const Key('theme-mode-control'));
    await tester.tap(
      find.descendant(of: modeControl, matching: find.text('浅色')),
    );
    await tester.pump();

    expect(theme().data.colors.brightness, Brightness.light);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      const CLColorScheme.light().background,
    );

    await tester.tap(
      find.descendant(of: modeControl, matching: find.text('深色')),
    );
    await tester.pump();

    expect(theme().data.colors.brightness, Brightness.dark);
  });

  _galleryTestWidgets('Gallery exposes a 500-option aligned select demo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GalleryApp());
    await tester.pump();

    final selectFinder = find.byKey(const Key('large-select-demo'));
    final select = tester.widget<CLSelect<int>>(selectFinder);
    expect(select.options, hasLength(500));
    expect(select.value, 249);
    expect(select.alignSelectedOption, isTrue);
    expect(select.options.first.label, '项目 001 / 500');
    expect(select.options.last.label, '项目 500 / 500');
  });

  _galleryTestWidgets(
    'Gallery toolbar demo previews and switches its active tool',
    (WidgetTester tester) async {
      await tester.pumpWidget(const GalleryApp());
      await tester.pump();

      final first = find.byKey(const Key('toolbar-tool-0'));
      final initial = find.byKey(const Key('toolbar-tool-3'));
      expect(tester.widget<CLIconButton>(initial).selected, isTrue);
      expect(tester.widget<CLIconButton>(first).selected, isFalse);

      await tester.ensureVisible(first);
      await tester.pump();
      await tester.tap(first);
      await tester.pump();

      expect(tester.widget<CLIconButton>(first).selected, isTrue);
      expect(tester.widget<CLIconButton>(initial).selected, isFalse);
    },
  );

  _galleryTestWidgets('Gallery exposes the interactive CLScrollable demo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GalleryApp());
    await tester.pump();

    expect(find.text('CLScrollable'), findsOneWidget);
    final directionControl = find.byKey(
      const Key('scrollable-direction-control'),
    );
    final visibilityControl = find.byKey(
      const Key('scrollable-visibility-control'),
    );
    expect(
      find.descendant(of: directionControl, matching: find.text('双轴')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: visibilityControl, matching: find.text('自动')),
      findsOneWidget,
    );
    final demo = tester.widget<CLScrollable>(
      find.byKey(const Key('scrollable-demo')),
    );
    expect(demo.direction, CLScrollDirection.both);
    expect(demo.horizontalScrollbar, CLScrollbarVisibility.auto);
    expect(demo.verticalScrollbar, CLScrollbarVisibility.auto);

    await tester.ensureVisible(directionControl);
    await tester.pump();
    await tester.tap(
      find.descendant(of: directionControl, matching: find.text('横向')),
    );
    await tester.pump();
    await tester.ensureVisible(visibilityControl);
    await tester.pump();
    await tester.tap(
      find.descendant(of: visibilityControl, matching: find.text('始终')),
    );
    await tester.pump();

    final updatedDemo = tester.widget<CLScrollable>(
      find.byKey(const Key('scrollable-demo')),
    );
    expect(updatedDemo.direction, CLScrollDirection.horizontal);
    expect(updatedDemo.horizontalScrollbar, CLScrollbarVisibility.always);
    expect(updatedDemo.verticalScrollbar, CLScrollbarVisibility.always);
  });

  _galleryTestWidgets('Gallery exposes the interactive CLList demo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GalleryApp());
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('list-demo')));
    final demo = tester.widget<CLList>(find.byKey(const Key('list-demo')));
    expect(demo.scrollDirection, Axis.vertical);
    expect(demo.scrollbarVisibility, CLScrollbarVisibility.auto);
    expect(find.text('#001'), findsOneWidget);

    final directionControl = find.byKey(const Key('list-direction-control'));
    await tester.ensureVisible(directionControl);
    await tester.pump();
    await tester.tap(
      find.descendant(of: directionControl, matching: find.text('横向')),
    );
    await tester.pump();

    final visibilityControl = find.byKey(const Key('list-visibility-control'));
    await tester.ensureVisible(visibilityControl);
    await tester.pump();
    await tester.tap(
      find.descendant(of: visibilityControl, matching: find.text('始终')),
    );
    await tester.pump();

    final updatedDemo = tester.widget<CLList>(
      find.byKey(const Key('list-demo')),
    );
    expect(updatedDemo.scrollDirection, Axis.horizontal);
    expect(updatedDemo.scrollbarVisibility, CLScrollbarVisibility.always);
  });
}
