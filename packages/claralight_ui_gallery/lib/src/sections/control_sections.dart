part of '../../main.dart';

class _ButtonsSection extends StatelessWidget {
  const _ButtonsSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'CLButton',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CLButton(
            key: const Key('primary-button-demo'),
            label: '主要',
            leadingIcon: const Icon(Icons.check_rounded),
            variant: CLButtonVariant.primary,
            onPressed: () {},
          ),
          CLButton(
            label: '次要',
            variant: CLButtonVariant.secondary,
            onPressed: () {},
          ),
          CLButton(
            label: '幽灵',
            variant: CLButtonVariant.ghost,
            onPressed: () {},
          ),
          CLButton(
            key: const Key('danger-button-demo'),
            label: '删除',
            variant: CLButtonVariant.danger,
            onPressed: () {},
          ),
          const CLButton(label: '禁用'),
          CLButton(
            label: '中',
            size: CLControlSize.medium,
            variant: CLButtonVariant.secondary,
            onPressed: () {},
          ),
          CLButton(
            label: '小',
            size: CLControlSize.small,
            variant: CLButtonVariant.secondary,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _IconButtonsSection extends StatefulWidget {
  const _IconButtonsSection();

  @override
  State<_IconButtonsSection> createState() => _IconButtonsSectionState();
}

class _IconButtonsSectionState extends State<_IconButtonsSection> {
  int _alignment = 0;

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    return _SectionCard(
      title: 'CLIconButton',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CLIconButton(icon: Icons.add_rounded, onPressed: () {}),
              CLIconButton(icon: Icons.favorite_rounded, onPressed: () {}),
              CLIconButton(
                icon: Icons.more_horiz_rounded,
                variant: CLIconButtonVariant.ghost,
                onPressed: () {},
              ),
              CLIconButton(
                key: const Key('primary-icon-button-demo'),
                icon: Icons.ios_share_rounded,
                variant: CLIconButtonVariant.primary,
                onPressed: () {},
              ),
              CLIconButton(
                key: const Key('danger-icon-button-demo'),
                icon: Icons.delete_outline_rounded,
                variant: CLIconButtonVariant.danger,
                onPressed: () {},
              ),
              const CLIconButton(icon: Icons.block_rounded, onPressed: null),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CLIconButton(
                icon: Icons.title_rounded,
                size: CLControlSize.medium,
                semanticLabel: '文字工具（默认玻璃）',
                onPressed: () {},
              ),
              const SizedBox(width: 8),
              CLIconButton(
                icon: Icons.title_rounded,
                extent: 32,
                iconSize: 18,
                variant: CLIconButtonVariant.ghost,
                iconColor: theme.colors.textPrimary,
                semanticLabel: '文字工具',
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The alignment grid of the desktop mockup: small rounded squares.
          Row(
            children: [
              for (final (i, icon) in const [
                Icons.format_align_left_rounded,
                Icons.format_align_center_rounded,
                Icons.format_align_right_rounded,
                Icons.vertical_align_top_rounded,
                Icons.vertical_align_center_rounded,
                Icons.vertical_align_bottom_rounded,
              ].indexed) ...[
                CLIconButton(
                  icon: icon,
                  size: CLControlSize.small,
                  shape: CLIconButtonShape.rounded,
                  selected: _alignment == i,
                  onPressed: () => setState(() => _alignment = i),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TogglesSection extends StatefulWidget {
  const _TogglesSection();

  @override
  State<_TogglesSection> createState() => _TogglesSectionState();
}

class _TogglesSectionState extends State<_TogglesSection> {
  bool _value = true;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'CLToggle',
      child: Row(
        children: [
          CLToggle(value: _value, onChanged: (v) => setState(() => _value = v)),
          const SizedBox(width: 16),
          const CLToggle(value: false, onChanged: null),
          const SizedBox(width: 16),
          const CLToggle(value: true, onChanged: null),
        ],
      ),
    );
  }
}

class _SegmentedSection extends StatefulWidget {
  const _SegmentedSection();

  @override
  State<_SegmentedSection> createState() => _SegmentedSectionState();
}

class _SegmentedSectionState extends State<_SegmentedSection> {
  int _screen = 0;
  int _tool = 1;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'CLSegmentedControl',
      child: Column(
        children: [
          CLSegmentedControl(
            segments: const ['亮屏', '息屏'],
            selectedIndex: _screen,
            onChanged: (i) => setState(() => _screen = i),
          ),
          const SizedBox(height: 10),
          CLSegmentedControl(
            segments: const ['名称', '种类', '日期'],
            size: CLControlSize.medium,
            selectedIndex: _tool,
            onChanged: (i) => setState(() => _tool = i),
          ),
        ],
      ),
    );
  }
}

class _SliderSection extends StatefulWidget {
  const _SliderSection();

  @override
  State<_SliderSection> createState() => _SliderSectionState();
}

class _SliderSectionState extends State<_SliderSection> {
  double _value = 0.62;
  double _temperature = 22;
  double _balance = 0;
  double _rating = 3;

  @override
  Widget build(BuildContext context) {
    final theme = CLTheme.of(context);
    final caption = theme.typography.caption.copyWith(
      color: theme.colors.textSecondary,
    );
    return _SectionCard(
      title: 'CLSlider',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CLSlider(value: _value, onChanged: (v) => setState(() => _value = v)),
          const SizedBox(height: 4),
          Text('${(_value * 100).round()}%', style: caption),
          const SizedBox(height: 16),
          Text('悬停或拖动显示气泡数值', style: caption),
          const SizedBox(height: 6),
          CLSlider(
            value: _temperature,
            min: 16,
            max: 30,
            onChanged: (v) => setState(() => _temperature = v),
            valueLabel: (v) => '${v.round()}°',
          ),
          const SizedBox(height: 16),
          Text('吸附点：两端与中点有磁性，中间的值照样停得住', style: caption),
          const SizedBox(height: 6),
          CLSlider(
            value: _balance,
            min: -1,
            max: 1,
            snapPoints: const [-1, 0, 1],
            snapRadius: 24,
            onChanged: (v) => setState(() => _balance = v),
            valueLabel: (v) => v == 0
                ? '居中'
                : '${v < 0 ? 'L' : 'R'} ${(v.abs() * 100).round()}',
          ),
          const SizedBox(height: 16),
          Text('步进：只停在整档上', style: caption),
          const SizedBox(height: 6),
          CLSlider(
            value: _rating,
            min: 1,
            max: 5,
            step: 1,
            onChanged: (v) => setState(() => _rating = v),
            valueLabel: (v) => '${v.round()} 档',
          ),
          const SizedBox(height: 16),
          const CLSlider(value: 0.3, onChanged: null),
        ],
      ),
    );
  }
}

class _InputsSection extends StatelessWidget {
  const _InputsSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'CLTextField / CLSearchField',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: CLTextField(
                  size: CLControlSize.small,
                  mono: true,
                  prefix: const Text('X'),
                  suffix: const Text('px'),
                  controller: TextEditingController(text: '12'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CLTextField(
                  size: CLControlSize.small,
                  mono: true,
                  prefix: const Text('Y'),
                  suffix: const Text('px'),
                  controller: TextEditingController(text: '12'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const CLSearchField(
            placeholder: '搜索',
            trailing: Icon(Icons.mic_rounded),
          ),
        ],
      ),
    );
  }
}

class _TextAreasSection extends StatefulWidget {
  const _TextAreasSection();

  @override
  State<_TextAreasSection> createState() => _TextAreasSectionState();
}

class _TextAreasSectionState extends State<_TextAreasSection> {
  final _fixedController = TextEditingController(
    text:
        '本次版本完善了导出流程。\n'
        '图片与视频共用同一套命名规则。\n'
        '批量任务会保留原始时间戳。\n'
        '失败项目可在记录中单独重试。\n'
        '交付前请再次核对输出目录。',
  );
  final _readOnlyController = TextEditingController(text: '已确认的说明内容');
  final _errorController = TextEditingController(text: '这段内容需要修改');

  @override
  void dispose() {
    _fixedController.dispose();
    _readOnlyController.dispose();
    _errorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'CLTextArea',
      child: Column(
        children: [
          CLTextArea(
            key: const Key('fixed-text-area-demo'),
            controller: _fixedController,
          ),
          const SizedBox(height: 10),
          const CLTextArea(
            key: Key('auto-text-area-demo'),
            placeholder: '补充更多细节',
            minHeight: 80,
            maxHeight: 160,
            size: CLControlSize.medium,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CLTextArea(
                  key: const Key('read-only-text-area-demo'),
                  controller: _readOnlyController,
                  minHeight: 80,
                  readOnly: true,
                  size: CLControlSize.small,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CLTextArea(
                  key: const Key('error-text-area-demo'),
                  controller: _errorController,
                  minHeight: 80,
                  error: true,
                  size: CLControlSize.small,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectSection extends StatefulWidget {
  const _SelectSection();

  @override
  State<_SelectSection> createState() => _SelectSectionState();
}

class _SelectSectionState extends State<_SelectSection> {
  static final _largeOptionSet = List.generate(
    500,
    (index) => CLSelectOption(
      index,
      '项目 ${(index + 1).toString().padLeft(3, '0')} / 500',
    ),
    growable: false,
  );

  String _fillMode = '数字填充';
  String _ghostFormat = '00:00';
  int _selectedItem = 249;
  final _widthController = TextEditingController(text: '78');
  final _heightController = TextEditingController(text: '91');

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'CLSelect / numeric CLTextField',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CLSelect<String>(
                  variant: CLSelectVariant.standard,
                  size: CLControlSize.medium,
                  value: _fillMode,
                  options: const [
                    CLSelectOption('数字填充', '数字填充'),
                    CLSelectOption('图片填充', '图片填充'),
                    CLSelectOption('序列帧', '序列帧'),
                  ],
                  onChanged: (v) => setState(() => _fillMode = v),
                ),
              ),
              const SizedBox(width: 8),
              CLSelect<String>(
                variant: CLSelectVariant.ghost,
                size: CLControlSize.medium,
                value: _ghostFormat,
                options: const [
                  CLSelectOption('00:00', '00:00'),
                  CLSelectOption('00:00:00', '00:00:00'),
                  CLSelectOption('HH:mm:ss', 'HH:mm:ss'),
                ],
                onChanged: (v) => setState(() => _ghostFormat = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CLSelect<int>(
            key: const Key('large-select-demo'),
            size: CLControlSize.medium,
            value: _selectedItem,
            options: _largeOptionSet,
            onChanged: (value) => setState(() => _selectedItem = value),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CLTextField(
                  controller: _widthController,
                  keyboardType: TextInputType.number,
                  prefix: const Text('W'),
                  suffix: const Text('px'),
                  step: 1,
                  min: 1,
                  max: 480,
                  size: CLControlSize.small,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CLTextField(
                  controller: _heightController,
                  keyboardType: TextInputType.number,
                  prefix: const Text('H'),
                  suffix: const Text('px'),
                  step: 1,
                  min: 1,
                  max: 480,
                  size: CLControlSize.small,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
