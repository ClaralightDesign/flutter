import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claralight_ui/claralight_ui.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  BorderSide outlineSide(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(CLButton),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.position == DecorationPosition.foreground,
        ),
      ),
    );
    final shape = (box.decoration as ShapeDecoration).shape;
    return (shape as RoundedSuperellipseBorder).side;
  }

  test('CLButton exposes its default configuration', () {
    const button = CLButton(label: 'Continue');

    expect(button.size, CLControlSize.large);
    expect(button.variant, CLButtonVariant.secondary);
  });

  testWidgets('CLButton renders the flat Claralight base', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(CLButton(label: '继续', onPressed: () {})));

    final surface = tester.widget<CLSurface>(find.byType(CLSurface));
    expect(surface.frosted, isTrue);
    expect(surface.fill, CLThemeData().colors.floatingControl);
    expect(surface.frostSigma, 36);
    expect(surface.shadow, isNull);

    final box = tester.getSize(find.byType(CLSurface));
    expect(box.height, 44);
  });

  testWidgets('CLButton sizes follow the density steps', (
    WidgetTester tester,
  ) async {
    for (final (size, height) in [
      (CLControlSize.small, 28.0),
      (CLControlSize.medium, 36.0),
      (CLControlSize.large, 44.0),
    ]) {
      await tester.pumpWidget(
        host(CLButton(label: '继续', size: size, onPressed: () {})),
      );
      expect(
        tester.getSize(find.byType(CLSurface)).height,
        height,
        reason: 'height of $size',
      );
    }
  });

  testWidgets('CLButton applies label style and semantic label overrides', (
    WidgetTester tester,
  ) async {
    const trailingKey = Key('custom-trailing-icon');
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        CLButton(
          label: '100%',
          semanticLabel: 'Canvas zoom 100%',
          labelStyle: const TextStyle(
            color: Color(0xFFFF0000),
            fontFamily: 'Test Mono',
            fontSize: 15,
          ),
          trailingIcon: const Icon(
            Icons.arrow_drop_down,
            key: trailingKey,
            size: 14,
          ),
          onPressed: () {},
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('100%'));
    expect(label.style?.fontFamily, 'Test Mono');
    expect(label.style?.fontSize, 15);
    expect(label.style?.color, CLThemeData().colors.onFloatingControl);
    expect(tester.widget<Icon>(find.byKey(trailingKey)).size, 14);
    expect(find.bySemanticsLabel('Canvas zoom 100%'), findsOneWidget);
    semantics.dispose();
  });

  test('CLButton validates custom label contracts', () {
    expect(() => CLButton(), throwsAssertionError);
    expect(
      () => CLButton(
        label: 'Label',
        labelWidget: const SizedBox(),
        semanticLabel: 'Label',
      ),
      throwsAssertionError,
    );
    expect(() => CLButton(labelWidget: const SizedBox()), throwsAssertionError);
  });

  testWidgets('CLButton renders arbitrary label content with inherited style', (
    WidgetTester tester,
  ) async {
    late TextStyle inheritedTextStyle;
    late IconThemeData inheritedIconTheme;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        CLButton(
          labelWidget: Builder(
            builder: (context) {
              inheritedTextStyle = DefaultTextStyle.of(context).style;
              inheritedIconTheme = IconTheme.of(context);
              return const SizedBox(
                key: ValueKey('custom-button-label'),
                width: 32,
                height: 16,
              );
            },
          ),
          semanticLabel: 'Dynamic value',
          labelStyle: const TextStyle(fontFamily: 'Test Mono', fontSize: 15),
          onPressed: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('custom-button-label')), findsOneWidget);
    expect(inheritedTextStyle.fontFamily, 'Test Mono');
    expect(inheritedTextStyle.fontSize, 15);
    expect(inheritedTextStyle.color, CLThemeData().colors.onFloatingControl);
    expect(inheritedIconTheme.color, CLThemeData().colors.onFloatingControl);
    expect(find.bySemanticsLabel('Dynamic value'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('CLButton supports an accessible icon-only composition', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        CLButton(
          label: '',
          semanticLabel: 'Application menu',
          leadingIcon: const Icon(Icons.apps),
          trailingIcon: const Icon(Icons.arrow_drop_down),
          onPressed: () {},
        ),
      ),
    );

    expect(find.bySemanticsLabel('Application menu'), findsOneWidget);
    expect(find.byType(Icon), findsNWidgets(2));
    semantics.dispose();
  });

  testWidgets('CLButton inline content does not overlap at fixed width', (
    WidgetTester tester,
  ) async {
    const trailingKey = Key('inline-trailing-icon');

    await tester.pumpWidget(
      host(
        CLButton(
          labelWidget: CLNumericText.number(
            363,
            key: const ValueKey('inline-number'),
            formatter: (value) => '${value.round()}%',
          ),
          semanticLabel: 'Canvas zoom 363%',
          width: 88,
          size: CLControlSize.medium,
          iconSize: 14,
          horizontalPadding: 8,
          centerLabel: false,
          trailingIcon: const Icon(
            Icons.keyboard_arrow_down,
            key: trailingKey,
            size: 14,
          ),
          onPressed: () {},
        ),
      ),
    );

    final labelRect = tester.getRect(
      find.byKey(const ValueKey('inline-number')),
    );
    final iconRect = tester.getRect(find.byKey(trailingKey));
    final buttonRect = tester.getRect(find.byType(CLButton));
    expect(labelRect.right, lessThan(iconRect.left));
    expect(iconRect.center.dy, closeTo(buttonRect.center.dy, 0.01));
  });

  testWidgets('CLButton hugs content by default and accepts fixed width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(CLButton(label: '继续', onPressed: () {})));
    final hugged = tester.getSize(find.byType(CLSurface)).width;

    await tester.pumpWidget(
      host(CLButton(label: '继续', width: 300, onPressed: () {})),
    );
    final fixed = tester.getSize(find.byType(CLSurface)).width;

    expect(hugged, lessThan(300));
    expect(fixed, 300);
  });

  testWidgets('CLButton centers a full-width label independently of icons', (
    WidgetTester tester,
  ) async {
    const leadingKey = Key('leading-icon');
    const trailingKey = Key('trailing-icon');

    Future<void> expectLayout({
      required bool constrainedByParent,
      Widget? leadingIcon,
      Widget? trailingIcon,
    }) async {
      final button = CLButton(
        width: constrainedByParent ? null : 354,
        label: '继续',
        leadingIcon: leadingIcon,
        trailingIcon: trailingIcon,
        onPressed: () {},
      );
      await tester.pumpWidget(
        host(
          constrainedByParent
              ? SizedBox(
                  width: 354,
                  child: Row(children: [Expanded(child: button)]),
                )
              : button,
        ),
      );

      final buttonRect = tester.getRect(find.byType(CLSurface));
      final textRect = tester.getRect(find.text('继续'));
      expect(textRect.center.dx, moreOrLessEquals(buttonRect.center.dx));
    }

    await expectLayout(
      constrainedByParent: false,
      leadingIcon: const SizedBox(key: leadingKey, width: 24, height: 24),
    );
    final leadingRect = tester.getRect(find.byKey(leadingKey));
    final leadingButtonRect = tester.getRect(find.byType(CLSurface));
    expect(leadingRect.left, leadingButtonRect.left + 16);

    await expectLayout(
      constrainedByParent: false,
      trailingIcon: const SizedBox(key: trailingKey, width: 24, height: 24),
    );
    final trailingRect = tester.getRect(find.byKey(trailingKey));
    final trailingButtonRect = tester.getRect(find.byType(CLSurface));
    expect(trailingRect.right, trailingButtonRect.right - 16);

    // ExportPage uses Expanded rather than CLButton.width; the label must
    // still stay centered when only the trailing arrow is present.
    await expectLayout(
      constrainedByParent: true,
      trailingIcon: const SizedBox(width: 24, height: 24),
    );
  });

  testWidgets('CLButton reports taps', (WidgetTester tester) async {
    var tapped = false;

    await tester.pumpWidget(
      host(CLButton(label: '继续', onPressed: () => tapped = true)),
    );

    await tester.tap(find.byType(CLButton));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('CLButton variants use the scheme fills', (
    WidgetTester tester,
  ) async {
    final theme = CLThemeData();

    Future<Color> fillFor(CLButtonVariant variant) async {
      await tester.pumpWidget(
        host(CLButton(label: '继续', variant: variant, onPressed: () {})),
      );
      final surface = tester.widget<CLSurface>(find.byType(CLSurface));
      return surface.fill!;
    }

    expect(await fillFor(CLButtonVariant.primary), theme.colors.accent);
    expect(
      await fillFor(CLButtonVariant.secondary),
      theme.colors.floatingControl,
    );
    expect(await fillFor(CLButtonVariant.danger), theme.colors.danger);
  });

  testWidgets('CLButton secondary uses the default glass treatment', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        CLButton(
          label: '继续',
          variant: CLButtonVariant.secondary,
          onPressed: () {},
        ),
      ),
    );

    final surface = tester.widget<CLSurface>(find.byType(CLSurface));
    expect(surface.frosted, isTrue);
    expect(surface.frostSigma, 36);
    expect(surface.shadow, isNull);
    expect(
      tester.widget<Text>(find.text('继续')).style?.color,
      CLThemeData().colors.onFloatingControl,
    );
  });

  testWidgets('CLButton variants do not cast shadows', (
    WidgetTester tester,
  ) async {
    for (final variant in CLButtonVariant.values) {
      await tester.pumpWidget(
        host(CLButton(label: '继续', variant: variant, onPressed: () {})),
      );

      expect(
        tester.widget<CLSurface>(find.byType(CLSurface)).shadow,
        isNull,
        reason: 'shadow of $variant',
      );
    }
  });

  testWidgets('CLButton outlines non-ghost variants by default', (
    WidgetTester tester,
  ) async {
    final outline = CLThemeData().colors.outline;

    for (final (variant, expectedOutlined) in [
      (CLButtonVariant.primary, true),
      (CLButtonVariant.secondary, true),
      (CLButtonVariant.danger, true),
      (CLButtonVariant.ghost, false),
    ]) {
      await tester.pumpWidget(
        host(CLButton(label: '继续', variant: variant, onPressed: () {})),
      );

      expect(
        outlineSide(tester),
        expectedOutlined ? BorderSide(color: outline) : BorderSide.none,
        reason: 'outline of $variant',
      );
    }
  });

  testWidgets('CLButton outline can be enabled, disabled, and recolored', (
    WidgetTester tester,
  ) async {
    const customOutline = Color(0xFF00FF00);

    await tester.pumpWidget(
      host(
        CLButton(
          label: '继续',
          variant: CLButtonVariant.ghost,
          outlined: true,
          outlineColor: customOutline,
          onPressed: () {},
        ),
      ),
    );
    expect(outlineSide(tester), const BorderSide(color: customOutline));

    await tester.pumpWidget(
      host(CLButton(label: '继续', outlined: false, onPressed: () {})),
    );
    expect(outlineSide(tester), BorderSide.none);
  });

  testWidgets('CLButton only ghosts skip the frosted background', (
    WidgetTester tester,
  ) async {
    for (final (variant, frosted) in [
      (CLButtonVariant.primary, true),
      (CLButtonVariant.secondary, true),
      (CLButtonVariant.danger, true),
      (CLButtonVariant.ghost, false),
    ]) {
      await tester.pumpWidget(
        host(CLButton(label: '继续', variant: variant, onPressed: () {})),
      );
      expect(
        tester.widget<CLSurface>(find.byType(CLSurface)).frosted,
        frosted,
        reason: 'frosted state of $variant',
      );
    }
  });

  testWidgets('CLButton semantic variants use contrasting foregrounds', (
    WidgetTester tester,
  ) async {
    final theme = CLThemeData();

    for (final (variant, foreground) in [
      (CLButtonVariant.primary, theme.colors.onAccent),
      (CLButtonVariant.secondary, theme.colors.onFloatingControl),
      (CLButtonVariant.danger, theme.colors.onDanger),
    ]) {
      await tester.pumpWidget(
        host(
          CLButton(
            label: variant.name,
            leadingIcon: const Icon(Icons.add),
            variant: variant,
            onPressed: () {},
          ),
        ),
      );

      expect(
        tester.widget<Text>(find.text(variant.name)).style?.color,
        foreground,
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.add))).color,
        foreground,
      );
    }
  });

  testWidgets('CLButton tint overrides the variant fill', (
    WidgetTester tester,
  ) async {
    const tint = Color(0xFF00FF00);

    await tester.pumpWidget(
      host(CLButton(label: '继续', tint: tint, onPressed: () {})),
    );

    final surface = tester.widget<CLSurface>(find.byType(CLSurface));
    expect(surface.fill, tint);
  });

  testWidgets('CLButton disabled ghost stays transparent', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(const CLButton(label: '继续', variant: CLButtonVariant.ghost)),
    );

    expect(
      tester.widget<CLSurface>(find.byType(CLSurface)).fill,
      const Color(0x00000000),
    );
  });

  testWidgets('CLButton disabled secondary keeps its glass fill', (
    WidgetTester tester,
  ) async {
    final theme = CLThemeData();
    await tester.pumpWidget(host(const CLButton(label: '继续')));

    expect(
      tester.widget<CLSurface>(find.byType(CLSurface)).fill,
      theme.colors.floatingControl,
    );
  });

  testWidgets('CLButton can retain an active foreground while disabled', (
    WidgetTester tester,
  ) async {
    const foreground = Color(0xFF123456);
    await tester.pumpWidget(
      host(const CLButton(label: '42%', disabledForegroundColor: foreground)),
    );

    expect(tester.widget<Text>(find.text('42%')).style?.color, foreground);
    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(CLButton),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.enabled, isFalse);
  });

  testWidgets('CLButton disabled primary retains its accent fill', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(const CLButton(label: '继续', variant: CLButtonVariant.primary)),
    );

    final theme = CLThemeData();
    final surface = tester.widget<CLSurface>(find.byType(CLSurface));
    expect(surface.fill, theme.colors.accent);
    expect(surface.shadow, isNull);

    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(CLButton),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.enabled, isFalse);
  });
}
