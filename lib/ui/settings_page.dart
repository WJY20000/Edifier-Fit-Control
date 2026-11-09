import 'package:flutter/material.dart';

import '../app_info.dart';
import '../config.dart';
import '../platform/quit.dart';
import '../state/session.dart';
import 'theme.dart';
import 'widgets.dart';

/// 设置：外观、语言、连接、型号说明、开发者与关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session});

  final Session session;

  /// 开发者头像（打包在 assets 里，离线可用）。
  static const String avatarAsset = 'assets/branding/avatar.jpg';

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    // 用 SingleChildScrollView + Column 而不是 ListView：
    // ListView 只构建可见项，设置项一多，「开发者」「退出应用」这些卡片
    // 在无头测试（以及很矮的窗口）里根本不会被创建，测试只能靠滚动去碰运气。
    // 设置页只有十几个卡片，全部构建的开销可以忽略。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        SectionCard(
          title: l10n.t('settings.theme'),
          icon: Icons.palette_outlined,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: 'system',
                label: Text(l10n.t('settings.themeSystem')),
                icon: const Icon(Icons.brightness_auto_rounded, size: 15),
              ),
              ButtonSegment(
                value: 'dark',
                label: Text(l10n.t('settings.themeDark')),
                icon: const Icon(Icons.dark_mode_rounded, size: 15),
              ),
              ButtonSegment(
                value: 'light',
                label: Text(l10n.t('settings.themeLight')),
                icon: const Icon(Icons.light_mode_rounded, size: 15),
              ),
            ],
            selected: {session.themeMode},
            onSelectionChanged: (value) => session.setThemeMode(value.first),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: l10n.t('settings.connection'),
          icon: Icons.bluetooth_connected_rounded,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: session.autoReconnect,
            onChanged: session.setAutoReconnect,
            title: Text(
              l10n.t('settings.autoReconnect'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: l10n.t('settings.language'),
          icon: Icons.translate_rounded,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'zh', label: Text('中文')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {session.locale},
            onSelectionChanged: (value) => session.setLocale(value.first),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: l10n.t('settings.model'),
          icon: Icons.headphones_rounded,
          subtitle: l10n.t('settings.modelBody'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    kMyHeadsetName,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  StatusChip(
                    label: l10n.t('settings.singleModel'),
                    color: FitColors.success,
                    icon: Icons.verified_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FitTheme.faint(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.t('settings.modelEvidence'),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: l10n.t('settings.myDevice'),
          icon: Icons.link_rounded,
          subtitle: l10n.t('settings.myDeviceBody'),
          child: _TargetMacEditor(session: session),
        ),
        const SizedBox(height: 14),
        // 开发者：头像 + 署名。整块只用静态资源，离线也正常显示。
        SectionCard(
          title: l10n.t('settings.developer'),
          icon: Icons.person_outline_rounded,
          child: Row(
            children: [
              const _Avatar(asset: avatarAsset),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'infinite',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 19,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(
                          label: l10n.t('settings.author'),
                          color: FitColors.gold,
                          icon: Icons.auto_awesome_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      l10n.t('settings.developerRole'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: l10n.t('settings.about'),
          icon: Icons.info_outline_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t('settings.aboutBody'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.55),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    '${l10n.t('settings.version')} $kAppVersion',
                    style: theme.textTheme.labelMedium?.copyWith(color: muted),
                  ),
                  const Spacer(),
                  StatusChip(
                    label: l10n.t('settings.protocol'),
                    color: FitTheme.accentOf(context),
                    icon: Icons.menu_book_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: l10n.t('settings.quit'),
          icon: Icons.power_settings_new_rounded,
          subtitle: l10n.t('settings.quitBody'),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              // 直接退出，不再弹二次确认：用户要的就是「点了就走」。
              onPressed: () => quitApp(session),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(l10n.t('settings.quit')),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.35)),
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}

/// 圆环渐变描边的圆形头像；资源加载失败时退回品牌渐变 + 人形图标。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.asset, this.size = 56});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FitColors.accentLight, FitColors.accentDeep],
        ),
      ),
      child: Icon(Icons.person_rounded, size: size * 0.5, color: Colors.white),
    );

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FitColors.accent, FitColors.gold],
        ),
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            // 头像最大只显示 56 逻辑像素，解码到 224 足够，别把整张原图放进内存。
            cacheWidth: 224,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => fallback,
          ),
        ),
      ),
    );
  }
}


/// 固定设备：输入 MAC，直接连，不扫描。
class _TargetMacEditor extends StatefulWidget {
  const _TargetMacEditor({required this.session});

  final Session session;

  @override
  State<_TargetMacEditor> createState() => _TargetMacEditorState();
}

class _TargetMacEditorState extends State<_TargetMacEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.session.targetMac ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveAndConnect() async {
    final session = widget.session;
    final text = _controller.text.trim();
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await session.connectByAddress(text);
    if (!mounted) return;
    setState(() => _busy = false);
    final l10n = session.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l10n.t('settings.macSaved', {'mac': session.targetMac ?? text})
              : (session.lastError ?? l10n.t('common.failed')),
        ),
      ),
    );
    // 连上之后地址会被归一化，输入框跟着刷新成平台用的形式。
    final mac = session.targetMac;
    if (mac != null) _controller.text = mac;
  }

  Future<void> _forget() async {
    await widget.session.setTargetMac(null);
    if (!mounted) return;
    setState(() => _controller.clear());
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final l10n = session.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: l10n.t('settings.macLabel'),
            hintText: 'AA:BB:CC:DD:EE:FF',
            helperText: l10n.t('settings.macHelper'),
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _saveAndConnect,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.link_rounded, size: 17),
              label: Text(l10n.t('settings.macConnect')),
            ),
            // 控制服务在部分固件上要求加密链路：给一个手动配对入口，
            // 自动配对失败时用户能自己再试一次。
            if (session.targetMac != null)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final ok = await session.pairTarget();
                        if (!mounted) return;
                        setState(() => _busy = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.t(ok ? 'settings.pairOk' : 'settings.pairFail'),
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.bluetooth_connected_rounded, size: 16),
                label: Text(l10n.t('settings.pair')),
              ),
            if (session.targetMac != null)
              TextButton.icon(
                onPressed: _busy ? null : _forget,
                icon: const Icon(Icons.link_off_rounded, size: 16),
                label: Text(l10n.t('settings.macForget')),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
        if (session.targetMac?.toLowerCase() == kMyHeadsetBleMac ||
            session.targetMac?.toLowerCase() == kMyHeadsetClassicMac) ...[
          const SizedBox(height: 10),
          Text(
            l10n.t('settings.macPreset'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
