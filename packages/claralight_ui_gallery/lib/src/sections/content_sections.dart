part of '../../main.dart';

class _AnimatedTreeBranch extends StatefulWidget {
  final CLListTile header;
  final List<Widget> children;
  final bool expanded;

  const _AnimatedTreeBranch({
    super.key,
    required this.header,
    required this.children,
    required this.expanded,
  });

  @override
  State<_AnimatedTreeBranch> createState() => _AnimatedTreeBranchState();
}

class _AnimatedTreeBranchState extends State<_AnimatedTreeBranch>
    with SingleTickerProviderStateMixin {
  static const _duration = CLMotion.standard;
  static const _curve = CLMotion.easeOut;

  late final AnimationController _controller;
  late final Animation<double> _reveal;
  late bool _childrenMounted;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _childrenMounted = widget.expanded;
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      reverseDuration: _duration,
      value: widget.expanded ? 1 : 0,
    )..addStatusListener(_handleStatus);
    _reveal = CurvedAnimation(
      parent: _controller,
      curve: _curve,
      reverseCurve: const FlippedCurve(_curve),
    );
  }

  @override
  void didUpdateWidget(_AnimatedTreeBranch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded == widget.expanded) return;

    if (_disableAnimations) {
      _controller.stop();
      _childrenMounted = widget.expanded;
      _controller.value = widget.expanded ? 1 : 0;
    } else if (widget.expanded) {
      _childrenMounted = true;
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations == disableAnimations) return;

    _disableAnimations = disableAnimations;
    if (disableAnimations) {
      _controller.stop();
      _childrenMounted = widget.expanded;
      _controller.value = widget.expanded ? 1 : 0;
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed ||
        widget.expanded ||
        !_childrenMounted) {
      return;
    }
    setState(() => _childrenMounted = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header,
        if (_childrenMounted)
          AnimatedBuilder(
            animation: _reveal,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                for (var i = 0; i < widget.children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  widget.children[i],
                ],
              ],
            ),
            builder: (context, child) {
              final interactive = widget.expanded && _reveal.value > 0;
              return IgnorePointer(
                ignoring: !interactive,
                child: ExcludeSemantics(
                  excluding: !interactive,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: _reveal.value,
                      child: Opacity(opacity: _reveal.value, child: child),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ListsSection extends StatefulWidget {
  const _ListsSection();

  @override
  State<_ListsSection> createState() => _ListsSectionState();
}

class _ListsSectionState extends State<_ListsSection> {
  int _selectedStyle = 0;
  bool _groupExpanded = true;
  bool _containerExpanded = true;
  bool _subtreeExpanded = true;
  final _groupBranchSlotKey = GlobalKey();
  final _containerBranchSlotKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    return _SectionCard(
      title: 'CLTreeView / CLListSection / CLListTile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CLListSection(
            header: '表盘样式',
            children: [
              CLListTile(
                label: '新增样式',
                outlined: true,
                leading: const Icon(Icons.add_rounded),
                onTap: () {},
              ),
              for (final (i, label) in const ['样式 1', '样式 2', '样式 3'].indexed)
                CLListTile(
                  label: label,
                  selected: _selectedStyle == i,
                  onTap: () => setState(() => _selectedStyle = i),
                ),
            ],
          ),
          CLDivider(indent: theme.spacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 282,
              height: 316,
              child: CLTreeView(
                children: [
                  CLListTile(
                    label: 'Frame 114',
                    leading: const Icon(Icons.image_outlined),
                    selected: true,
                    onTap: () {},
                  ),
                  CLListTile(
                    label: '图组 1',
                    leading: const Icon(Icons.collections_outlined),
                    onTap: () {},
                  ),
                  CLListTile(
                    label: '文字 1',
                    leading: const Icon(Icons.text_fields_rounded),
                    onTap: () {},
                  ),
                  KeyedSubtree(
                    key: _groupBranchSlotKey,
                    child: _AnimatedTreeBranch(
                      key: const Key('tree-group-2-branch'),
                      expanded: _groupExpanded,
                      header: CLListTile(
                        label: '组 2',
                        leading: const Icon(Icons.crop_free_rounded),
                        expanded: _groupExpanded,
                        onExpandedChanged: (v) =>
                            setState(() => _groupExpanded = v),
                        onTap: () =>
                            setState(() => _groupExpanded = !_groupExpanded),
                      ),
                      children: [
                        CLListTile(
                          label: '进度条 1',
                          depth: 1,
                          leading: const Icon(Icons.data_usage_rounded),
                          onTap: () {},
                        ),
                        CLListTile(
                          label: '序列帧 1',
                          depth: 1,
                          leading: const Icon(Icons.auto_awesome_rounded),
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                  KeyedSubtree(
                    key: _containerBranchSlotKey,
                    child: _AnimatedTreeBranch(
                      key: const Key('tree-container-1-branch'),
                      expanded: _containerExpanded,
                      header: CLListTile(
                        label: '容器 1',
                        tint: const Color(0xFFBE93E4),
                        leading: const Icon(Icons.grid_view_rounded),
                        expanded: _containerExpanded,
                        onExpandedChanged: (v) =>
                            setState(() => _containerExpanded = v),
                        onTap: () => setState(
                          () => _containerExpanded = !_containerExpanded,
                        ),
                      ),
                      children: [
                        _AnimatedTreeBranch(
                          key: const Key('tree-group-1-branch'),
                          expanded: _subtreeExpanded,
                          header: CLListTile(
                            label: '组 1',
                            tint: const Color(0xFFBE93E4),
                            depth: 1,
                            leading: const Icon(Icons.crop_free_rounded),
                            expanded: _subtreeExpanded,
                            onExpandedChanged: (v) =>
                                setState(() => _subtreeExpanded = v),
                            onTap: () => setState(
                              () => _subtreeExpanded = !_subtreeExpanded,
                            ),
                          ),
                          children: [
                            CLListTile(
                              label: '矩形 1',
                              tint: const Color(0xFFBE93E4),
                              depth: 2,
                              leading: const Icon(Icons.rectangle_outlined),
                              onTap: () {},
                            ),
                            CLListTile(
                              label: '文字 2',
                              tint: const Color(0xFFBE93E4),
                              depth: 2,
                              leading: const Icon(Icons.text_fields_rounded),
                              onTap: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwatchesSection extends StatefulWidget {
  const _SwatchesSection();

  @override
  State<_SwatchesSection> createState() => _SwatchesSectionState();
}

class _SwatchesSectionState extends State<_SwatchesSection> {
  int _selected = 1;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'CLColorSwatchGroup',
      child: CLColorSwatchGroup(
        colors: const [
          Color(0xFF2E9E8F),
          Color(0xFF4A7FA8),
          Color(0xFF9E9E9E),
          Color(0xFFE0930F),
          Color(0xFFC2504B),
        ],
        selectedIndex: _selected,
        onChanged: (i) => setState(() => _selected = i),
      ),
    );
  }
}

class _AnimatedNumberSection extends StatefulWidget {
  const _AnimatedNumberSection();

  @override
  State<_AnimatedNumberSection> createState() => _AnimatedNumberSectionState();
}

class _AnimatedNumberSectionState extends State<_AnimatedNumberSection> {
  static const _samples = [9, 1299, 123450, 99999900, -4250];

  int _sampleIndex = 2;
  int _cents = _samples[2];

  String _formatCents(num rawValue) {
    final cents = rawValue.toInt();
    final absolute = cents.abs();
    final whole = absolute ~/ 100;
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    final digits = whole.toString();
    final grouped = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        grouped.write(',');
      }
      grouped.write(digits[index]);
    }
    return '${cents.isNegative ? '-' : ''}\$$grouped.$fraction';
  }

  void _adjust(int delta) => setState(() => _cents += delta);

  void _cycleValue() {
    setState(() {
      _sampleIndex = (_sampleIndex + 1) % _samples.length;
      _cents = _samples[_sampleIndex];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    return _SectionCard(
      title: 'CLAnimatedNumber',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Align(
              alignment: Alignment.centerRight,
              child: CLAnimatedNumber(
                _cents,
                key: const Key('animated-number-demo'),
                formatter: _formatCents,
                style: theme.typography.monoStrong.copyWith(
                  color: theme.colors.textPrimary,
                  fontSize: 36,
                  height: 1.15,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CLIconButton(
                key: const Key('animated-number-decrement'),
                icon: Icons.remove_rounded,
                size: CLControlSize.small,
                semanticLabel: '减少金额',
                onPressed: () => _adjust(-1199),
              ),
              const SizedBox(width: 8),
              CLTooltip(
                message: '切换数值',
                child: CLIconButton(
                  key: const Key('animated-number-cycle'),
                  icon: Icons.swap_vert_rounded,
                  size: CLControlSize.small,
                  semanticLabel: '切换数值',
                  onPressed: _cycleValue,
                ),
              ),
              const SizedBox(width: 8),
              CLIconButton(
                key: const Key('animated-number-increment'),
                icon: Icons.add_rounded,
                size: CLControlSize.small,
                semanticLabel: '增加金额',
                onPressed: () => _adjust(1199),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressSection extends StatefulWidget {
  const _ProgressSection();

  @override
  State<_ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends State<_ProgressSection> {
  double _progress = 368 / 1024;

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    return _SectionCard(
      title: 'CLProgressBar / CLProgressRing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(
              () => _progress = _progress > 0.9 ? 0.15 : _progress + 0.25,
            ),
            child: CLProgressBar(value: _progress),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              text: '占用固件内存: ',
              style: theme.typography.callout
                  .withCLWeight(FontWeight.w500)
                  .copyWith(color: theme.colors.textTertiary),
              children: [
                TextSpan(
                  text: '${(_progress * 1024).round()}KB/1024KB',
                  style: theme.typography.mono.copyWith(
                    color: theme.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // The same value on all three, so the ladder is the only variable:
          // the gap does not scale with the rail, and neither does the dot the
          // ends collapse to.
          CLProgressBar(value: _progress, size: CLProgressSize.small),
          const SizedBox(height: 8),
          CLProgressBar(value: _progress, size: CLProgressSize.large),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: CLProgressBar(value: null)),
              const SizedBox(width: 16),
              CLProgressRing(
                value: _progress,
                size: CLProgressSize.large,
                child: Text(
                  '${(_progress * 100).round()}',
                  style: theme.typography.caption.copyWith(
                    color: theme.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CLProgressRing(value: _progress, size: CLProgressSize.small),
              const SizedBox(width: 12),
              CLProgressRing(value: _progress),
              const SizedBox(width: 24),
              // No track while indeterminate: the arc breathes as the ring
              // turns, and a fourth turn arrives a quarter at a time.
              const CLProgressRing(value: null, size: CLProgressSize.small),
              const SizedBox(width: 12),
              const CLProgressRing(value: null),
              const SizedBox(width: 12),
              const CLProgressRing(value: null, size: CLProgressSize.large),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'CLBanner / CLBadge',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CLBanner(
            '上传图片素材尺寸需保持一致',
            icon: Icon(Icons.lightbulb_outline_rounded),
          ),
          const SizedBox(height: 8),
          const CLBanner('已连接到设备', tone: CLBannerTone.success),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              const CLBadge('78x91', unit: 'px'),
              const CLBadge('12', unit: 'px', color: Color(0xFFEF5F00)),
              CLBadge(
                'BETA',
                color: CLTheme.of(context).colors.selection,
                foreground: CLTheme.of(context).colors.textPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
