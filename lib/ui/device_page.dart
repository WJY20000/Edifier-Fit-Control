import 'package:flutter/material.dart';

import '../config.dart';
import '../protocol/engine.dart';
import '../protocol/models.dart';
import '../protocol/opcodes.dart';
import '../state/session.dart';
import 'glass.dart';
import 'theme.dart';
import 'widgets.dart';

/// 设备主页：设备名 + 电量、降噪主卡、音效 / 场景次卡、高级折叠区。
class DevicePage extends StatelessWidget {
  const DevicePage({super.key, required this.session, required this.onGoScan});

  final Session session;
  final VoidCallback onGoScan;

  @override
  Widget build(BuildContext context) {
    if (session.phase == SessionPhase.connecting && !session.connected) {
      return const _ConnectingView();
    }
    if (!session.connected) {
      return _EmptyState(session: session, onGoScan: onGoScan);
    }

    final engine = session.engine!;
    final caps = engine.caps;

    final hero = _Hero(session: session);
    // 连上了但耳机不回包（多半是 GATT 通道没选对，或通知没订阅上）：
    // 给一条能照着做的提示，而不是让用户对着一堆「--」猜。
    // 只在「这一轮读取已经失败」时显示 —— 刚连上、还没读完的那一两秒不算。
    final negotiation = session.negotiation;
    final notice = (negotiation != null && !negotiation.ok)
        ? _NoReplyBanner(session: session)
        : null;
    // 只支持这一只耳机：降噪控件始终显示，不再按「探测到什么」来隐藏。
    final noise = _NoiseCard(session: session, engine: engine);
    final eq = caps.soundEffect
        ? _SoundEffectCard(session: session, engine: engine)
        : null;
    final scene = caps.scene ? _SceneCard(session: session, engine: engine) : null;
    final advanced = _AdvancedCard(session: session, engine: engine);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              hero,
              if (notice != null) ...[const SizedBox(height: 14), notice],
              const SizedBox(height: 14),
              noise,
              if (eq != null) ...[const SizedBox(height: 14), eq],
              if (scene != null) ...[const SizedBox(height: 14), scene],
              const SizedBox(height: 14),
              advanced,
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  children: [
                    hero,
                    if (notice != null) ...[const SizedBox(height: 16), notice],
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 11,
                          child: Column(
                            children: [
                              noise,
                              if (scene != null) ...[
                                const SizedBox(height: 18),
                                scene,
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 10,
                          child: Column(
                            children: [
                              if (eq != null) ...[
                                eq,
                                const SizedBox(height: 18),
                              ],
                              advanced,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 连接中的骨架屏：比空白页更能说明「正在发生什么」。
class _ConnectingView extends StatelessWidget {
  const _ConnectingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: const [
        SkeletonBox(height: 150, radius: FitRadius.hero),
        SizedBox(height: 16),
        SkeletonBox(height: 190, radius: FitRadius.card),
        SizedBox(height: 16),
        SkeletonBox(height: 150, radius: FitRadius.card),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.session, required this.onGoScan});

  final Session session;
  final VoidCallback onGoScan;

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HeadphonesArt(size: 168),
              const SizedBox(height: 10),
              Text(
                l10n.t('device.connectFirst'),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.t('device.connectFirstBody'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 固定过地址就直接连：扫描靠广播，耳机被系统占住时扫不到很正常。
              if (session.targetMac != null) ...[
                _PinnedConnect(session: session),
                const SizedBox(height: 10),
                Text(
                  session.targetMac!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                onPressed: onGoScan,
                icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
                label: Text(l10n.t('device.goScan')),
              ),
              if (session.lastError != null) ...[
                const SizedBox(height: 18),
                Text(
                  session.lastError!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                // 「无应答」= 命令发出去了，但一帧回包都没收到。
                // 多半是选错了 GATT 通道（48097303 是 OTA 口），把实际通道打出来。
                if (session.lastError!.toLowerCase().contains('did not answer')) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('device.errNoAnswer', {
                      'service': session.negotiation?.serviceUuid ?? '—',
                    }),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      height: 1.55,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (session.lastError!.toLowerCase().contains('accessdenied')) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('device.errAccess'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      height: 1.55,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                // WinRT 报「Failed to get device」= 这个地址不是 BLE 地址。
                // 原文对用户没有意义，补一句能动手的解释。
                if (session.lastError!.contains('Failed to get device')) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('device.errNoBle'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      height: 1.55,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 已固定地址时的一键直连：不扫描，直接向这个 MAC 发起 GATT 连接。
class _PinnedConnect extends StatefulWidget {
  const _PinnedConnect({required this.session});

  final Session session;

  @override
  State<_PinnedConnect> createState() => _PinnedConnectState();
}

class _PinnedConnectState extends State<_PinnedConnect> {
  bool _busy = false;

  Future<void> _connect() async {
    final mac = widget.session.targetMac;
    if (mac == null || _busy) return;
    setState(() => _busy = true);
    await widget.session.connectByAddress(mac);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.session.l10n;
    return SizedBox(
      width: 240,
      child: FilledButton.icon(
        onPressed: _busy ? null : _connect,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.link_rounded, size: 18),
        label: Text(l10n.t('device.connectMine')),
      ),
    );
  }
}

/// 顶部：设备名 + 三个金标 + 电量。不放固件 / MAC 等参数。
class _Hero extends StatelessWidget {
  const _Hero({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final dark = FitTheme.isDark(context);
    final state = session.engine?.state;
    final name = state?.name ?? session.deviceName ?? kMyHeadsetName;

    return GlassSurface(
      radius: FitRadius.hero,
      blur: GlassBlur.hero,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [
                const Color(0xFF1B2C3A).withValues(alpha: 0.72),
                const Color(0xFF0F161C).withValues(alpha: 0.60),
              ]
            : [
                Colors.white.withValues(alpha: 0.82),
                const Color(0xFFEDF2F8).withValues(alpha: 0.68),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 右上角一团极淡的品牌蓝：玻璃把它「折」进来，边缘会随之变化。
          Positioned(
            right: -40,
            top: -60,
            child: IgnorePointer(
              child: Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      FitColors.accent.withValues(alpha: dark ? 0.22 : 0.12),
                      FitColors.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              // 窄屏（Android 常见 360dp）把字号和圆环一起收一档，
              // 让「EDIFIER Fit900NB Turbo」最多两行就能放下。
              final compact = constraints.maxWidth < 280;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontSize: compact ? 19 : 22,
                            height: 1.18,
                            // 负字距会让字形的左边缘探出排版盒，
                            // 在窄屏 + 圆角裁剪下看起来像「首字母被切掉」。
                            letterSpacing: 0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 14),
                        const CertBadges(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  BatteryRing(
                    percent: state?.battery,
                    label: l10n.t('device.battery'),
                    size: compact ? 88 : 100,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 连上了但没读到电量：给一条可操作的提示。
class _NoReplyBanner extends StatelessWidget {
  const _NoReplyBanner({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = session.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: FitColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FitColors.warning.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.portable_wifi_off_rounded, size: 17, color: FitColors.warning),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  l10n.t('device.noReply'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: FitColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            l10n.t('device.noReplyBody'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              height: 1.45,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: session.reread,
              icon: const Icon(Icons.sync_rounded, size: 16),
              label: Text(l10n.t('device.reread')),
            ),
          ),
        ],
      ),
    );
  }
}

/// 降噪：本页的主控，图标化五档 + 环境声就地展开。
class _NoiseCard extends StatelessWidget {
  const _NoiseCard({required this.session, required this.engine});

  final Session session;
  final EdifierEngine engine;

  IconData _icon(NoiseMode mode) {
    switch (mode) {
      case NoiseMode.deep:
        return Icons.blur_on_rounded;
      case NoiseMode.comfort:
        return Icons.spa_rounded;
      case NoiseMode.wind:
        return Icons.air_rounded;
      case NoiseMode.ambient:
        return Icons.hearing_rounded;
      case NoiseMode.adaptive:
        return Icons.auto_awesome_rounded;
      case NoiseMode.off:
        return Icons.power_settings_new_rounded;
    }
  }

  String _shortKey(NoiseMode mode) {
    switch (mode) {
      case NoiseMode.deep:
        return 'noise.shortDeep';
      case NoiseMode.comfort:
        return 'noise.shortComfort';
      case NoiseMode.wind:
        return 'noise.shortWind';
      case NoiseMode.ambient:
        return 'noise.shortAmbient';
      case NoiseMode.adaptive:
        return 'noise.adaptive';
      case NoiseMode.off:
        return 'noise.shortOff';
    }
  }

  String _hintKey(NoiseMode mode) {
    switch (mode) {
      case NoiseMode.deep:
        return 'noise.deepHint';
      case NoiseMode.comfort:
        return 'noise.comfortHint';
      case NoiseMode.wind:
        return 'noise.windHint';
      case NoiseMode.ambient:
        return 'noise.ambientHint2';
      case NoiseMode.adaptive:
        return 'noise.deepHint';
      case NoiseMode.off:
        return 'noise.offHint';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final state = engine.state;
    const options = kNoiseOptions;
    final current = state.noise;
    final currentOption =
        options.where((o) => o.mode == current).toList();
    final active = currentOption.isEmpty ? null : currentOption.first;

    return SectionCard(
      title: l10n.t('device.noise'),
      icon: Icons.noise_control_off_rounded,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: current == null
                      ? FitTheme.faint(context)
                      : FitColors.accent.withValues(alpha: 0.12),
                ),
                child: Icon(
                  current == null ? Icons.help_outline_rounded : _icon(current),
                  size: 24,
                  color: current == null
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                      : FitTheme.accentOf(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.18),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        active == null ? l10n.t('device.unknown') : l10n.t(active.labelKey),
                        key: ValueKey<int?>(current?.index),
                        style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      current == null ? l10n.t('device.noiseUnknown') : l10n.t(_hintKey(current)),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          OptionGrid<NoiseOption>(
            values: options,
            selected: active,
            labelOf: (option) => l10n.t(_shortKey(option.mode)),
            iconOf: (option) => _icon(option.mode),
            onSelected: (option) => session.setNoise(option.mode),
          ),
          // 环境声等级：就地展开，不再单独弹一张卡（避免布局跳动）。
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: engine.caps.ambientLevel && current == NoiseMode.ambient
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _AmbientInline(session: session, engine: engine),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _AmbientInline extends StatelessWidget {
  const _AmbientInline({required this.session, required this.engine});

  final Session session;
  final EdifierEngine engine;

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final current = engine.state.ambientLevel;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: FitTheme.faint(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('device.ambientLevel'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          OptionGrid<int>(
            values: AmbientLevel.all,
            selected: current,
            columns: 3,
            labelOf: (value) => l10n.t(AmbientLevel.labelKey(value)),
            sublabelOf: (value) => switch (value) {
              AmbientLevel.vocal => l10n.t('ambient.vocalHint'),
              AmbientLevel.background => l10n.t('ambient.backgroundHint'),
              _ => l10n.t('ambient.balancedHint'),
            },
            onSelected: session.setAmbientLevel,
          ),
        ],
      ),
    );
  }
}

class _SoundEffectCard extends StatelessWidget {
  const _SoundEffectCard({required this.session, required this.engine});

  final Session session;
  final EdifierEngine engine;

  IconData _icon(int value) {
    switch (value) {
      case 0:
        return Icons.spa_rounded;
      case 1:
        return Icons.bolt_rounded;
      case 2:
        return Icons.record_voice_over_rounded;
      case 3:
        return Icons.speaker_rounded;
      case 4:
        return Icons.graphic_eq_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final presets = engine.eqPresets;
    // 只有「场景不是音乐」时设备才会拒绝音效（回 0xFF）。之前的判断只看
    // soundEffect 是否为空，读取时没读到就会把音乐场景下的控件也锁死，
    // 还提示用户去切场景，方向完全反了。
    final locked = engine.state.soundEffect == null &&
        (engine.state.scene ?? Scene.music) != Scene.music;

    return SectionCard(
      title: l10n.t('device.eq'),
      subtitle: l10n.t('eq.hint'),
      icon: Icons.equalizer_rounded,
      trailing: locked
          ? Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OptionGrid<int>(
            values: presets.map((p) => p.value).toList(),
            selected: engine.state.soundEffect,
            columns: 3,
            enabled: !locked,
            gap: 8,
            labelOf: (value) => l10n.t(
              presets
                  .firstWhere((p) => p.value == value, orElse: () => presets.first)
                  .labelKey,
            ),
            iconOf: _icon,
            onSelected: session.setSoundEffect,
          ),
          if (locked) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.t('eq.locked'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.session, required this.engine});

  final Session session;
  final EdifierEngine engine;

  IconData _icon(int value) {
    switch (value) {
      case Scene.game:
        return Icons.sports_esports_rounded;
      case Scene.spatial:
        return Icons.surround_sound_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }

  String _hintKey(int value) {
    switch (value) {
      case Scene.game:
        return 'scene.gameHint';
      case Scene.spatial:
        return 'scene.spatialHint';
      default:
        return 'scene.musicHint';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final selected = engine.state.scene;
    return SectionCard(
      title: l10n.t('scene.title'),
      icon: Icons.movie_filter_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OptionGrid<int>(
            values: Scene.all,
            selected: selected,
            columns: 3,
            labelOf: (value) => l10n.t(Scene.labelKey(value)),
            iconOf: _icon,
            onSelected: session.setScene,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.t(selected == null ? 'scene.hint' : _hintKey(selected)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 高级：LDAC、设备信息、管理。默认折叠，界面默认只留日常会用到的控制。
class _AdvancedCard extends StatelessWidget {
  const _AdvancedCard({required this.session, required this.engine});

  final Session session;
  final EdifierEngine engine;

  String _ldacShortKey(int value) {
    switch (value) {
      case LdacMode.off:
        return 'ldac.offShort';
      case LdacMode.auto:
        return 'ldac.autoShort';
      default:
        return 'ldac.hiresShort';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final state = engine.state;
    return CollapsibleSection(
      title: l10n.t('device.advanced'),
      subtitle: l10n.t('device.advancedHint'),
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (engine.caps.ldac) ...[
            Text(
              l10n.t('device.ldac'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 10),
            OptionGrid<int>(
              values: LdacMode.all,
              selected: state.ldac,
              columns: 3,
              labelOf: (value) => l10n.t(_ldacShortKey(value)),
              onSelected: session.setLdac,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('device.ldacHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const Divider(height: 30),
          ],
          InfoGrid(
            rows: [
              MapEntry(l10n.t('device.name'), state.name ?? session.deviceName ?? '--'),
              MapEntry(l10n.t('device.firmware'), state.firmware ?? '--'),
              MapEntry(
                l10n.t('device.mac'),
                state.mac ?? _macLike(session.deviceId) ?? '--',
              ),
              MapEntry(l10n.t('device.framing'), engine.framing.label),
              MapEntry(
                l10n.t('device.service'),
                session.negotiation?.serviceUuid ?? engine.serviceUuid ?? '--',
              ),
              MapEntry(
                l10n.t('device.mtu'),
                l10n.t('device.mtuValue', {'n': session.link?.chunkSize ?? 20}),
              ),
            ],
          ),
          const Divider(height: 30),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: session.reread,
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: Text(l10n.t('device.reread')),
              ),
              OutlinedButton.icon(
                onPressed: () => _rename(context, session),
                icon: const Icon(Icons.drive_file_rename_outline_rounded, size: 17),
                label: Text(l10n.t('device.rename')),
              ),
              OutlinedButton.icon(
                onPressed: session.disconnect,
                icon: const Icon(Icons.link_off_rounded, size: 17),
                label: Text(l10n.t('device.disconnect')),
              ),
              OutlinedButton.icon(
                onPressed: () => _confirmPowerOff(context, session),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.4)),
                ),
                icon: const Icon(Icons.power_settings_new_rounded, size: 17),
                label: Text(l10n.t('device.powerOff')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, Session session) async {
    final controller = TextEditingController(
      text: session.engine?.state.name ?? session.deviceName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(session.l10n.t('device.renameTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: InputDecoration(hintText: session.l10n.t('device.renameHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(session.l10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(session.l10n.t('common.ok')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final ok = await session.rename(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? session.l10n.t('device.renameDone') : session.l10n.t('common.failed')),
      ),
    );
  }

  Future<void> _confirmPowerOff(BuildContext context, Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(session.l10n.t('device.powerOff')),
        content: Text(session.l10n.t('device.resetConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(session.l10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(session.l10n.t('common.ok')),
          ),
        ],
      ),
    );
    if (confirmed == true) await session.powerOff();
  }
}

/// 系统给的是 MAC（安卓）就直接显示；Windows 给的是 GUID，显示出来没意义。
String? _macLike(String? id) {
  if (id == null) return null;
  final normalized = id.replaceAll('-', ':').toUpperCase();
  return RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(normalized)
      ? normalized
      : null;
}
