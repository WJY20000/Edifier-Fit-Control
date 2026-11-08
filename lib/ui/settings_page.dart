import 'package:flutter/material.dart';

import '../app_info.dart';
import '../state/session.dart';
import 'theme.dart';
import 'widgets.dart';

/// 设置：语言、主题、探测策略、型号、开发者与关于。
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
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
          title: l10n.t('settings.deepProbe'),
          icon: Icons.radar_rounded,
          subtitle: l10n.t('settings.deepProbeBody'),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: session.deepProbe,
                onChanged: session.setDeepProbe,
                title: Text(
                  l10n.t('settings.deepProbeEnable'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: session.autoReconnect,
                onChanged: session.setAutoReconnect,
                title: Text(
                  l10n.t('settings.autoReconnect'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
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
                    session.profile.displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  StatusChip(
                    label: session.profile.verified
                        ? l10n.t('device.verifiedShort')
                        : l10n.t('settings.unverified'),
                    color: session.profile.verified ? FitColors.success : FitColors.warning,
                    icon: session.profile.verified
                        ? Icons.verified_rounded
                        : Icons.science_outlined,
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
                  session.profile.evidence,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
                ),
              ),
            ],
          ),
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
      ],
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
