import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 卡片语气：普通白/深灰卡、轻填充卡。
enum CardTone { plain, soft }

/// 统一的分组卡片：可选图标、标题、说明、右上角附加控件。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.icon,
    this.tone = CardTone.plain,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final IconData? icon;
  final CardTone tone;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.56);
    final body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: FitColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: FitTheme.accentOf(context)),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: icon != null ? 4 : 0),
                      child: Text(title, style: theme.textTheme.titleMedium),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );

    if (tone == CardTone.soft) {
      return Container(
        decoration: BoxDecoration(
          color: FitTheme.faint(context),
          borderRadius: BorderRadius.circular(FitRadius.card),
          border: Border.all(color: FitTheme.hairline(context)),
        ),
        child: body,
      );
    }
    return Card(child: body);
  }
}

/// 电量圆环：数值变化有过渡，数字用等宽字形避免抖动。
class BatteryRing extends StatelessWidget {
  const BatteryRing({
    super.key,
    required this.percent,
    required this.label,
    this.size = 118,
  });

  final int? percent;
  final String label;
  final double size;

  Color _color() {
    final value = percent;
    if (value == null) return FitColors.gold;
    if (value <= 15) return FitColors.danger;
    if (value <= 35) return FitColors.warning;
    return FitColors.accent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = percent;
    final color = _color();
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: (value ?? 0).clamp(0, 100) / 100),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) {
          return Stack(
            alignment: Alignment.center,
            // 以前用 CircularProgressIndicator：它的描边是「骑」在方框边线上的，
            // 外侧半个描边会被 Stack 默认的硬裁剪切掉，圆环看起来是「缺一块 / 被压平」。
            // 这里自己画，并且把半径整体内缩半个描边，圆环永远完整。
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BatteryRingPainter(
                    progress: value == null ? 0 : animated,
                    strokeWidth: size * 0.06,
                    track: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                    color: color,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value == null ? '--' : '$value',
                        style: TextStyle(
                          fontSize: size * 0.30,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: -1,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (value != null)
                        Padding(
                          padding: EdgeInsets.only(top: size * 0.035),
                          child: Text(
                            '%',
                            style: TextStyle(
                              fontSize: size * 0.115,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: size * 0.035),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: size * 0.095,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 电量圆环的画笔。
///
/// 关键点：`drawArc` 的矩形要按描边宽度内缩，这样描边的外沿刚好落在方框边上，
/// 不会被父级（Stack 默认 `Clip.hardEdge`）裁掉。之前的 `CircularProgressIndicator`
/// 把描边中心放在方框边线上，外侧一半直接被剪掉，圆环顶部/底部看起来是平的。
class _BatteryRingPainter extends CustomPainter {
  _BatteryRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.track,
    required this.color,
  });

  /// 0..1
  final double progress;
  final double strokeWidth;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Offset(inset, inset) &
        Size(size.width - strokeWidth, size.height - strokeWidth);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    final value = progress.clamp(0.0, 1.0).toDouble();
    if (value > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_BatteryRingPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.track != track ||
      old.color != color;
}

/// 可点选的大块选项（降噪 / 场景 / 音效共用）。
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.sublabel,
    this.enabled = true,
    this.compact = false,
  });

  final String label;
  final String? sublabel;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = FitTheme.isDark(context);
    final active = selected && enabled;
    final muted = theme.colorScheme.onSurface.withValues(alpha: enabled ? 0.62 : 0.26);
    final iconColor = !enabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.22)
        : active
            ? (dark ? FitColors.accentLight : FitColors.accent)
            : muted;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(FitRadius.tile),
            onTap: enabled ? onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 8,
                vertical: compact ? 10 : 12,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FitRadius.tile),
                color: active
                    ? FitColors.accent.withValues(alpha: dark ? 0.18 : 0.09)
                    : FitTheme.faint(context),
                border: Border.all(
                  width: 1,
                  color: active
                      ? FitColors.accent.withValues(alpha: dark ? 0.6 : 0.45)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 190),
                      width: compact ? 30 : 34,
                      height: compact ? 30 : 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? FitColors.accent.withValues(alpha: 0.16)
                            : Colors.transparent,
                      ),
                      child: Icon(icon, size: compact ? 18 : 20, color: iconColor),
                    ),
                  if (icon != null) const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: compact ? 10.5 : 11.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? theme.colorScheme.onSurface : muted,
                    ),
                  ),
                  if (sublabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sublabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9.5,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一排 / 一网格选项。`columns <= 0` 时等分一行。
class OptionGrid<T> extends StatelessWidget {
  const OptionGrid({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.iconOf,
    this.sublabelOf,
    this.columns = 0,
    this.enabled = true,
    this.gap = 8,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final IconData? Function(T)? iconOf;
  final String? Function(T)? sublabelOf;
  final ValueChanged<T> onSelected;
  final int columns;
  final bool enabled;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (columns <= 0) {
      return Row(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: OptionTile(
                label: labelOf(values[i]),
                icon: iconOf?.call(values[i]),
                sublabel: sublabelOf?.call(values[i]),
                compact: true,
                selected: values[i] == selected,
                enabled: enabled,
                onTap: () => onSelected(values[i]),
              ),
            ),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: OptionTile(
                  label: labelOf(value),
                  icon: iconOf?.call(value),
                  sublabel: sublabelOf?.call(value),
                  selected: value == selected,
                  enabled: enabled,
                  onTap: () => onSelected(value),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 可折叠卡片（高级设置用）。
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.initiallyOpen = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final bool initiallyOpen;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.56);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(FitRadius.card),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon, size: 17, color: muted),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: theme.textTheme.titleMedium),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(color: muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(Icons.expand_more_rounded, color: muted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// 三个金标：Hi-Res（有线）/ Hi-Res Wireless / HWA。
class CertBadges extends StatelessWidget {
  const CertBadges({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _GoldBadge(title: 'Hi-Res', subtitle: 'AUDIO', tooltip: 'Hi-Res Audio'),
        _GoldBadge(
          title: 'Hi-Res',
          subtitle: 'AUDIO WIRELESS',
          tooltip: 'Hi-Res Audio Wireless',
        ),
        _GoldBadge(title: 'HWA', subtitle: 'WIRELESS AUDIO', tooltip: 'HWA'),
      ],
    );
  }
}

class _GoldBadge extends StatelessWidget {
  const _GoldBadge({
    required this.title,
    required this.subtitle,
    required this.tooltip,
  });

  final String title;
  final String subtitle;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              FitColors.gold.withValues(alpha: 0.13),
              FitColors.gold.withValues(alpha: 0.04),
            ],
          ),
          border: Border.all(
            color: FitColors.gold.withValues(alpha: 0.55),
            width: 0.9,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF3DFA4), FitColors.gold, FitColors.goldDeep],
              ).createShader(bounds),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  height: 1.05,
                ),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
              style: TextStyle(
                color: FitColors.gold.withValues(alpha: 0.88),
                fontSize: 5.8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.75,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 两列信息表。
class InfoGrid extends StatelessWidget {
  const InfoGrid({super.key, required this.rows});

  final List<MapEntry<String, String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.52);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    rows[i].key,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    rows[i].value,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 一排可选项（旧版环境声等仍用）。
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.enabled = true,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(labelOf(value)),
            selected: value == selected,
            onSelected: enabled ? (_) => onSelected(value) : null,
            showCheckmark: false,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: value == selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

/// 小圆点状态指示。
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 8, spreadRadius: 1),
        ],
      ),
    );
  }
}

/// 扇形取值的滑杆（环境声 -3..+3）：用分段按钮更直观。
class StepSelector extends StatelessWidget {
  const StepSelector({
    super.key,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    this.labelOf,
  });

  final int min;
  final int max;
  final int? value;
  final ValueChanged<int> onChanged;
  final String Function(int)? labelOf;

  @override
  Widget build(BuildContext context) {
    final items = <int>[for (var i = min; i <= max; i++) i];
    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _StepButton(
                label: labelOf?.call(item) ?? (item > 0 ? '+$item' : '$item'),
                selected: item == value,
                onTap: () => onChanged(item),
              ),
            ),
          ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? FitColors.accent.withValues(alpha: 0.14) : FitTheme.faint(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 34,
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? FitTheme.accentOf(context) : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态徽标。
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FitRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// 简易信号强度图标。
class SignalIcon extends StatelessWidget {
  const SignalIcon({super.key, required this.rssi});

  final int rssi;

  @override
  Widget build(BuildContext context) {
    final strength = ((rssi + 100) / 60).clamp(0.15, 1.0).toDouble();
    final color = strength > 0.66
        ? FitColors.success
        : strength > 0.33
            ? FitColors.warning
            : FitColors.danger;
    return SizedBox(
      width: 20,
      height: 16,
      child: CustomPaint(painter: _SignalPainter(strength, color)),
    );
  }
}

class _SignalPainter extends CustomPainter {
  _SignalPainter(this.strength, this.color);

  final double strength;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const bars = 4;
    final barWidth = size.width / (bars * 2 - 1);
    for (var i = 0; i < bars; i++) {
      final height = size.height * (0.35 + 0.65 * (i / (bars - 1)));
      final active = (i + 1) / bars <= strength + 0.001;
      paint.color = color.withValues(alpha: active ? 1 : 0.18);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * barWidth * 2, size.height - height, barWidth, height),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalPainter oldDelegate) =>
      oldDelegate.strength != strength || oldDelegate.color != color;
}

/// 细进度线。
class LinearProgressThin extends StatelessWidget {
  const LinearProgressThin({super.key, required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: value,
        minHeight: 2,
        backgroundColor: Colors.transparent,
        color: FitTheme.accentOf(context),
      ),
    );
  }
}

/// 空状态插画：一副耳机轮廓 + 柔光。
class HeadphonesArt extends StatelessWidget {
  const HeadphonesArt({super.key, this.size = 140, this.color = FitColors.accent});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HeadphonesPainter(color)),
    );
  }
}

class _HeadphonesPainter extends CustomPainter {
  _HeadphonesPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: size.width / 2));
    canvas.drawCircle(center, size.width / 2, glow);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.062
      ..strokeCap = StrokeCap.round
      ..color = color;

    final bandCenter = Offset(size.width / 2, size.height * 0.60);
    final bandRect = Rect.fromCircle(center: bandCenter, radius: size.width * 0.29);
    canvas.drawArc(bandRect, math.pi * 1.13, math.pi * 0.74, false, stroke);

    final cupWidth = size.width * 0.185;
    final cupHeight = size.height * 0.27;
    final left = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.185,
        size.height * 0.56,
        cupWidth,
        cupHeight,
      ),
      Radius.circular(size.width * 0.075),
    );
    final right = left.shift(Offset(size.width * 0.445, 0));
    final fill = Paint()..color = color;
    canvas.drawRRect(left, fill);
    canvas.drawRRect(right, fill);
    final hole = Paint()..color = color.withValues(alpha: 0.25);
    canvas.drawCircle(
      Offset(left.center.dx, left.center.dy),
      size.width * 0.035,
      hole,
    );
    canvas.drawCircle(
      Offset(right.center.dx, right.center.dy),
      size.width * 0.035,
      hole,
    );
  }

  @override
  bool shouldRepaint(covariant _HeadphonesPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 呼吸感的骨架块（连接中占位）。
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    required this.height,
    this.width = double.infinity,
    this.radius = 16,
  });

  final double height;
  final double width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 0.85).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: FitTheme.faint(context),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
