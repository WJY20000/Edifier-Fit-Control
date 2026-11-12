import 'package:flutter/material.dart';

import '../ble/ble_controller.dart';
import '../config.dart';
import '../state/session.dart';
import 'glass.dart';
import 'theme.dart';
import 'widgets.dart';

/// 扫描页：找到并连上耳机。
///
/// 三条路，按可靠性从高到低：
/// 1. 按 MAC 直连 —— 不依赖广播，耳机被系统占着也能连；
/// 2. 系统已连接设备 —— WinRT 直接列出系统握着的设备；
/// 3. 蓝牙扫描 —— 只有耳机在广播时才有结果。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.session, required this.onConnected});

  final Session session;
  final VoidCallback onConnected;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

enum _Source { scan, system }

class _ScanPageState extends State<ScanPage> {
  _Source _source = _Source.scan;

  /// 默认 false：Windows 的广播里经常没有名字，先按「像不像漫步者」筛掉，
  /// 就会出现「耳机在广播、列表却空着」的情况。默认全列，漫步者排最前。
  bool _onlyEdifier = false;

  List<DiscoveredDevice> _systemDevices = const [];
  bool _loadingSystem = false;

  Future<void> _loadSystem() async {
    setState(() {
      _source = _Source.system;
      _loadingSystem = true;
    });
    final list = await widget.session.systemDevices();
    if (!mounted) return;
    setState(() {
      _systemDevices = list;
      _loadingSystem = false;
    });
  }

  Future<void> _connectMac() async {
    final session = widget.session;
    final controller = TextEditingController(text: session.targetMac ?? '');
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(session.l10n.t('scan.macTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.l10n.t('scan.macBody'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'AA:BB:CC:DD:EE:FF'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(session.l10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(session.l10n.t('scan.connect')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || input.isEmpty) return;
    final ok = await session.connectByAddress(input);
    if (!mounted) return;
    if (ok) widget.onConnected();
  }

  Future<void> _connect(DiscoveredDevice device) async {
    await widget.session.connect(device);
    if (!mounted) return;
    if (widget.session.connected) widget.onConnected();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final scanning = session.ble.isScanning;
    final all = session.devices;
    final devices = _onlyEdifier
        ? all.where((d) => d.looksLikeEdifier).toList()
        : all;
    final shown = _source == _Source.scan ? devices : _systemDevices;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.t('scan.title'), style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      _source == _Source.scan && scanning
                          ? '${l10n.t('scan.count', {'n': shown.length})} · '
                              '${l10n.t('scan.rawCount', {'n': all.length})}'
                          : l10n.t('scan.hint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_source == _Source.scan)
                scanning
                    ? OutlinedButton.icon(
                        onPressed: session.stopScan,
                        icon: const Icon(Icons.stop_rounded, size: 18),
                        label: Text(l10n.t('scan.stop')),
                      )
                    : FilledButton.icon(
                        onPressed: () => session.startScan(),
                        icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
                        label: Text(l10n.t('scan.start')),
                      )
              else
                OutlinedButton.icon(
                  onPressed: _loadingSystem ? null : _loadSystem,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l10n.t('common.retry')),
                ),
            ],
          ),
        ),
        // 来源切换 + 过滤（窄屏时允许换行，避免 390px 宽度下挤出边界）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_Source>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: [
                  ButtonSegment(value: _Source.scan, label: Text(l10n.t('scan.sourceScan'))),
                  ButtonSegment(
                    value: _Source.system,
                    label: Text(l10n.t('scan.sourceSystem')),
                  ),
                ],
                selected: {_source},
                onSelectionChanged: (value) {
                  if (value.first == _Source.system) {
                    _loadSystem();
                  } else {
                    setState(() => _source = _Source.scan);
                  }
                },
              ),
              _MacButton(onPressed: _connectMac, label: l10n.t('scan.mac')),
            ],
          ),
        ),
        if (_source == _Source.scan)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: FitTheme.faint(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.t('scan.onlyEdifier'), style: theme.textTheme.bodySmall),
                  ),
                  Switch(
                    value: _onlyEdifier,
                    onChanged: (value) => setState(() => _onlyEdifier = value),
                  ),
                ],
              ),
            ),
          ),
        if (_source == _Source.scan && scanning) ...[
          const SizedBox(height: 6),
          const LinearProgressThin(value: null),
        ],
        Expanded(
          child: shown.isEmpty
              ? _Empty(
                  scanning: _source == _Source.scan && scanning,
                  text: _source == _Source.system
                      ? l10n.t('scan.systemEmpty')
                      : l10n.t('scan.empty'),
                  macLabel: l10n.t('scan.mac'),
                  onMac: _connectMac,
                  pinnedMac: session.targetMac,
                  pinnedLabel: l10n.t('scan.connectMine'),
                  hint: l10n.t('scan.winHint'),
                  onPinned: () async {
                    final mac = session.targetMac;
                    if (mac == null) return;
                    final ok = await session.connectByAddress(mac);
                    if (ok && mounted) widget.onConnected();
                  },
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 124),
                  itemCount: shown.length + (_source == _Source.system ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (_source == _Source.system && index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                        child: Text(
                          l10n.t('scan.systemNote'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            height: 1.5,
                          ),
                        ),
                      );
                    }
                    final device = shown[_source == _Source.system ? index - 1 : index];
                    return _DeviceTile(
                      device: device,
                      session: session,
                      onTap: () => _connect(device),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MacButton extends StatelessWidget {
  const _MacButton({required this.onPressed, required this.label});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      icon: const Icon(Icons.keyboard_alt_outlined, size: 17),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.scanning,
    required this.text,
    required this.macLabel,
    required this.onMac,
    required this.pinnedMac,
    required this.pinnedLabel,
    required this.hint,
    required this.onPinned,
  });

  final bool scanning;
  final String text;
  final String macLabel;
  final VoidCallback onMac;

  /// 已经固定过地址时，空列表里直接给一个「连它」的按钮 —— 扫描不到不代表连不上。
  final String? pinnedMac;
  final String pinnedLabel;
  final String hint;
  final VoidCallback onPinned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: scanning ? 1 : 0.55,
              child: const HeadphonesArt(size: 132),
            ),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            if (pinnedMac != null) ...[
              FilledButton.icon(
                onPressed: onPinned,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(pinnedLabel),
              ),
              const SizedBox(height: 6),
              Text(
                pinnedMac!,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 4),
            ],
            OutlinedButton.icon(
              onPressed: onMac,
              icon: const Icon(Icons.keyboard_alt_outlined, size: 17),
              label: Text(macLabel),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FitTheme.faint(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.session,
    required this.onTap,
  });

  final DiscoveredDevice device;
  final Session session;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final theme = Theme.of(context);
    // 地址比较一律归一：扫描结果与内置常量的字母大小写不一定一致。
    final connecting = session.phase == SessionPhase.connecting &&
        BleController.sameAddress(session.deviceId, device.id);
    final isCurrent =
        session.connected && BleController.sameAddress(session.deviceId, device.id);
    final pinned = BleController.sameAddress(session.targetMac, device.id);
    // 广播名只有「EDIFIER BLE」这种短名（AD 0x08/0x09），
    // 真正好认的是经典侧的名字。既然只支持这一只耳机，认出来就直接显示它，
    // 不要让用户对着「EDIFIER BLE」猜哪个才是自己的。
    final name = device.mine && kMyHeadsetName.isNotEmpty
        ? kMyHeadsetName
        : device.name?.isNotEmpty == true
            ? device.name!
            : l10n.t('scan.unknownDevice');

    // 列表项不套 BackdropFilter：扫描页一屏能有十来项，
    // 每项一块「模糊 + 折射」会拖垮滑动。这里只留染色 + 描边 + 阴影，
    // 观感几乎一样，开销少一个数量级。
    return GlassSurface(
      blur: 0,
      refraction: 0,
      tintAlpha: FitTheme.isDark(context) ? 0.62 : 0.74,
      child: InkWell(
        borderRadius: BorderRadius.circular(FitRadius.card),
        onTap: connecting || isCurrent ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: device.looksLikeEdifier
                      ? FitColors.accent.withValues(alpha: 0.12)
                      : FitTheme.faint(context),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  device.looksLikeEdifier ? Icons.headphones_rounded : Icons.bluetooth_rounded,
                  size: 21,
                  color: device.looksLikeEdifier
                      ? FitTheme.accentOf(context)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (device.hasRssi) ...[
                          SignalIcon(rssi: device.rssi),
                          const SizedBox(width: 6),
                          Text(
                            '${device.rssi} dBm',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // 地址永远显示：名字可能为空，地址才是能拿去直连的东西。
                        Flexible(
                          child: Text(
                            device.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                        if (pinned) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.push_pin_rounded, size: 12, color: FitColors.gold),
                        ],
                        if (device.mine) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: FitColors.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l10n.t('scan.mine'),
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: FitTheme.accentOf(context),
                              ),
                            ),
                          ),
                        ],
                        if (device.looksLikeEdifier) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: FitColors.gold.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'EDIFIER',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: FitColors.gold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (connecting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (isCurrent)
                StatusChip(
                  label: l10n.t('status.connected'),
                  color: FitColors.success,
                  icon: Icons.check_rounded,
                )
              else
                FilledButton.tonal(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    l10n.t('scan.connect'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
