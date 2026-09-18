# claralight_ui

**ClaraLight** — a quiet, layered dark design language for Flutter,
matching the ClaraLight Figma source (the Facetory demo app).

Translucent white-alpha control fills stacked over deep layered surfaces,
smooth superellipse corners everywhere, sparing accent color, springy
press physics. Rendering stays pure Dart across platforms; a bundled SwiftPM
macOS plugin adds native trackpad haptics without host-app setup.

## Quick start

```dart
import 'package:claralight_ui/claralight_ui.dart';

CLTheme(
  data: CLThemeData(), // dark ClaraLight scheme by default
  child: MaterialApp(...),
)
```

Widgets also work without an ancestor `CLTheme` by falling back to the
default dark theme.

## Numeric text

`CLNumericText` diffs one line of text against the last — a shared prefix, a
shared suffix, and the longest run flush with neither end — so the graphemes
that survive slide to their new place and only the ones that changed leave and
enter. Two digits pair only when they share a decimal place, which is what keeps
`1,000` to `1,001` down to a single rolling digit. It inherits
`DefaultTextStyle`, uses tabular figures by default, and snaps immediately when
reduced motion is enabled:

```dart
CLNumericText.number(
  score,
  formatter: (value) => '${value.toInt()}%',
  style: CLTheme.of(context).typography.monoStrong,
)

CLNumericText(isOn ? 'On' : 'Off')
```

`trend` describes a value getting larger or smaller. It is inferred from
consecutive numbers; pass `trend: CLNumericTextTrend.decreasing` to override that
for a cyclic countdown. Text no number can be read out of has no direction at
all, and enters with a staggered fade, scale, and blur rather than an arbitrary
vertical roll. `alignment` anchors content inside the widget while its width
animates; place it in an end-aligned or fixed-width parent when the global
trailing edge must not move.

`CLAnimatedNumber` is the deprecated former spelling.

## Responsive overflow toolbars

`CLOverflowToolbar` keeps fixed-width tools on a `CLToolbar` until the
available width is exhausted, then moves the lowest-priority overflowable
items into a `CLMenu`:

```dart
CLOverflowToolbar<int>(
  selectedId: activeTool,
  items: [
    CLOverflowToolbarItem<int>(
      id: 0,
      extent: 36,
      retention: CLToolbarItemRetention.pinned,
      toolbarBuilder: (_) => CLIconButton(
        icon: Icons.image_outlined,
        selected: activeTool == 0,
        onPressed: () => setState(() => activeTool = 0),
      ),
    ),
    CLOverflowToolbarItem<int>(
      id: 1,
      extent: 36,
      retention: CLToolbarItemRetention.overflowable,
      overflowLabel: 'Effects',
      overflowLeadingExtent: 28,
      toolbarBuilder: (_) => CLIconButton(
        icon: Icons.auto_awesome_outlined,
        selected: activeTool == 1,
        onPressed: () => setState(() => activeTool = 1),
      ),
      overflowBuilder: (context, closeMenu) => CLListTile(
        label: 'Effects',
        leading: const Icon(Icons.auto_awesome_outlined),
        onTap: () {
          setState(() => activeTool = 1);
          closeMenu();
        },
      ),
    ),
  ],
  overflowTriggerBuilder: (context, toggle) => CLIconButton(
    icon: Icons.more_horiz,
    onPressed: toggle,
  ),
)
```

Each item declares its main-axis `extent` explicitly. Overflowable items also
provide an `overflowLabel`; the menu measures only its current hidden labels and
hugs the longest one. Add `overflowLeadingExtent: 28` for a standard medium
`CLListTile` leading icon and gap. Labels are capped to the available safe-area
width.

That explicit geometry lets visibility be decided before calling a toolbar
builder, avoiding a one-frame overflow and avoiding hidden focus, hit-test, and
semantics nodes. Item IDs remain in their original logical order in the menu;
pinned items are never moved. When `selectedId` would be hidden, it replaces the
trailing visible overflowable item and occupies the final tool slot before
More. The replaced item returns to the menu, so More remains a neutral menu
entry instead of representing selection. If pinned items, the selected item,
and More cannot fit, the toolbar uses an explicit horizontal scroll fallback.

The More trigger is keyboard focusable and opens with Enter or Space. Set
`overflowEnabled: false` to disable pointer, keyboard, focus, and trigger
semantics together; the trigger builder then receives a null callback. A custom
`toolbarBuilder` must use the same `spacing` and `horizontalPadding` passed to
`CLOverflowToolbar`; those values form the component's deterministic
width-allocation contract.

## Progressive scrolling

Precache the shader shared by `CLScrollable`, `CLList`, and `CLTextArea`
before the first frame:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CLScrollable.precache();
  runApp(const App());
}
```

`CLTextArea.precache()` warms the same shader and is the equivalent entry point
for apps that only use multiline text input.

`CLScrollable` supports one or two axes, content padding, per-edge blur and
mask extents, rounded clipping, and independent scrollbar policies:

```dart
SizedBox(
  width: 320,
  height: 240,
  child: CLScrollable(
    direction: CLScrollDirection.both,
    horizontalScrollbar: CLScrollbarVisibility.auto,
    verticalScrollbar: CLScrollbarVisibility.auto,
    padding: const EdgeInsets.all(16),
    borderRadius: BorderRadius.circular(12),
    child: const SizedBox(width: 640, height: 480),
  ),
)
```

Use `CLList`, `CLList.builder`, or `CLList.separated` when the content should
retain `ListView`'s lazy sliver construction:

```dart
SizedBox(
  height: 320,
  child: CLList.builder(
    itemCount: 1000,
    itemExtent: 44,
    padding: const EdgeInsets.symmetric(vertical: 8),
    scrollbarVisibility: CLScrollbarVisibility.auto,
    borderRadius: BorderRadius.circular(12),
    itemBuilder: (context, index) => Text('Item $index'),
  ),
)
```

Every enabled axis must receive bounded constraints unless a `CLList` uses
`shrinkWrap`. If both `CLScrollable` controllers are provided, use a distinct
`ScrollController` for each axis. A zero side in `blurExtent` disables both
blur and masking on that physical edge; a zero side in `blurSigma` disables
blur only. For Flutter web, prefer the Skwasm renderer for this shader-backed
effect.

## Bundled fonts

Three free-for-commercial-use families ship with the package (see
`fonts/FONTS.md` for licenses) and are pre-wired into `CLTypography`:

- **MiSans** (Regular/Medium/Demibold/Semibold) — all UI text
- **Sarasa Mono SC** (Regular/SemiBold) — `typography.mono` /
  `monoStrong` for values and units (`368KB/1024KB`, `78x91px`)
- **ChillDINGothic** (Bold) — `typography.display` for large headings

## Design rules

- **Corners are smooth.** Every rounded corner is a rounded
  superellipse (`clSmoothShape` / `clSmoothDecoration` /
  `ClipRSuperellipse`), never a plain circular arc.
- **Fills are layers.** Controls use translucent white overlays
  (`colors.control` = 10% white, `controlHighlight` = 15%) so the same
  component reads correctly on any surface.
- **Springy physics.** Presses scale with overshoot, drags deform like
  jelly (`CLPressable`), menus morph out of their buttons.

## Components

- **Theme** — `CLTheme`, `CLThemeData`, `CLColorScheme`, `CLTypography`,
  `CLRadii`, `CLSpacing`
- **Foundation** — `CLNumericText` (interruptible numeric-text transition),
  `CLMarqueeText`, `CLControlSize`, shape helpers
- **Surfaces** — `CLSurface` (layered fills), `CLPressable` (springy press
  scale, jelly drag, pointer highlight)
- **Scrolling** — `CLScrollable`, `CLList`, `CLScrollDirection`,
  `CLScrollbarVisibility`
- **Buttons** — `CLButton`, `CLIconButton` (`primary`, `secondary`, `ghost`,
  and red `danger` variants)
- **Controls** — `CLToggle`, `CLSegmentedControl`, `CLSlider`,
  `CLChipTabs`
- **Inputs** — `CLTextField` (`mono:` and external `error:` states; numeric
  steppers support buttons, wheel, Up/Down, and Figma-style horizontal scrubbing
  from the prefix or arrow strip; vertical movement selects 2/4/8/16/32px tick
  spacing in stable 100px bands, finite min/max values truncate unreachable
  ticks, and macOS provides native per-frame trackpad feedback),
  `CLSearchField`, `CLSelect`, `CLStepper`, `CLColorPicker`
- **Containers** — `CLPanel`, `CLSectionHeader`, `CLSheet`, `CLDialog`,
  `CLToolbar`, `CLOverflowToolbar`, `CLSideBar`
- **Lists** — `CLTreeView`, `CLListSection`, `CLListTile` (progressive
  scrolling, selection, tree guides, disclosure, tint, `outlined:` add-rows)
- **Menus** — `CLMenu` (morphs out of its anchor with the jelly spring and
  hosts caller-built rows in an internal `CLList`) and `CLMenuSubmenu`
  (arbitrary-depth trigger-to-panel morphs with stacked ancestors)
- **Indicators** — `CLProgressBar`, `CLProgressRing`, `CLColorSwatchGroup`,
  `CLBanner`, `CLBadge`, `CLDivider` (solid/dashed), `CLTooltip`

### Numeric scrub cursor wrapping

Mouse-based numeric scrubbing wraps across the active Flutter window's left and
right edges, then restores the cursor to its pointer-down position on release.
Set `wrapNumericScrubCursor: false` to opt out. Cursor control is best-effort on
macOS, Windows, and Linux X11; unsupported environments fall back to finite
movement without affecting the value gesture. Linux Wayland is not supported by
the underlying `mouse` package, and its Windows multi-display positioning is
currently limited to the primary display coordinate model.

Nested menu pages use `CLMenuSubmenu` inside any `CLMenu.children` or
`CLMenuSubmenu.children` list:

```dart
CLMenu(
  anchor: const Icon(Icons.more_horiz),
  children: const [
    CLMenuSubmenu(
      label: 'View mode',
      children: [
        CLListTile(label: 'Grid'),
        CLMenuSubmenu(
          label: 'Sort by',
          children: [CLListTile(label: 'Capture date')],
        ),
      ],
    ),
  ],
)
```

The active submenu trigger becomes its fixed header. Activating that header
returns one level; Escape, system Back, an outside tap, or
`CLMenuController.close()` closes the complete stack. Ancestors remain visible
but inert, while safe-area or keyboard pressure may shift the new page left or
up and constrain its scrolling body.

Floating layers (menus, popovers, dialogs, sheets, tooltips) are
frosted: a backdrop blur under a translucent `colors.frost` wash.

See `claralight_ui_gallery` for a live showcase of every component.
