import 'package:flutter/material.dart';

import '../ble/ble_controller.dart';
import '../state/session.dart';
import 'theme.dart';
import 'widgets.dart';

/// 扫描页：列出附近的漫步者设备，点一下就连。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.session, required this.onConnected});

  final Session session;
  final VoidCallback onConnected;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final devices = session.devices;
    final scanning = session.ble.isScanning;

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
                    Text(
                      l10n.t('scan.title'),
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scanning
                          ? l10n.t('scan.count', {'n': devices.length})
                          : l10n.t('scan.hint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (scanning)
                OutlinedButton.icon(
                  onPressed: session.stopScan,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: Text(l10n.t('scan.stop')),
                )
              else
                FilledButton.icon(
                  onPressed: () => session.startScan(all: _showAll),
                  icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
                  label: Text(l10n.t('scan.start')),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
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
                  child: Text(
                    l10n.t('scan.all'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Switch(
                  value: _showAll,
                  onChanged: (value) {
                    setState(() => _showAll = value);
                    if (scanning) session.startScan(all: value);
                  },
                ),
              ],
            ),
          ),
        ),
        if (scanning) ...[
          const SizedBox(height: 6),
          const LinearProgressThin(value: null),
        ],
        Expanded(
          child: devices.isEmpty
              ? _Empty(scanning: scanning, text: l10n.t('scan.empty'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return _DeviceTile(
                      device: device,
                      session: session,
                      onTap: () async {
                        await session.connect(device);
                        if (session.connected) widget.onConnected();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scanning, required this.text});

  final bool scanning;
  final String text;

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
    final connecting =
        session.phase == SessionPhase.connecting && session.deviceId == device.id;
    final isCurrent = session.deviceId == device.id && session.connected;
    final name = device.name?.isNotEmpty == true
        ? device.name!
        : (device.id.length > 17 ? '${device.id.substring(0, 17)}…' : device.id);

    return Card(
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
                  device.looksLikeEdifier
                      ? Icons.headphones_rounded
                      : Icons.bluetooth_rounded,
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
                        SignalIcon(rssi: device.rssi),
                        const SizedBox(width: 6),
                        Text(
                          '${device.rssi} dBm',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
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
