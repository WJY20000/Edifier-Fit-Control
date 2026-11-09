import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../protocol/engine.dart';
import '../protocol/opcodes.dart';
import '../state/session.dart';
import 'widgets.dart';

/// 实验室：手动发命令、看原始收发。
class LabPage extends StatefulWidget {
  const LabPage({super.key, required this.session});

  final Session session;

  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> {
  final TextEditingController _command = TextEditingController(text: 'D0');
  final TextEditingController _payload = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _command.dispose();
    _payload.dispose();
    super.dispose();
  }

  List<int>? _parse(String text) {
    final cleaned = text.replaceAll(RegExp(r'[\s,;:]'), '');
    if (cleaned.isEmpty) return <int>[];
    if (cleaned.length.isOdd) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) return null;
    return [
      for (var i = 0; i < cleaned.length; i += 2)
        int.parse(cleaned.substring(i, i + 2), radix: 16),
    ];
  }

  Future<void> _send([int? fixedCommand, List<int> payload = const []]) async {
    final session = widget.session;
    final commandText = fixedCommand != null ? fixedCommand.toRadixString(16) : _command.text;
    final commandBytes = _parse(commandText);
    if (commandBytes == null || commandBytes.length != 1) {
      setState(() => _error = session.l10n.t('lab.invalidHex'));
      return;
    }
    final data = fixedCommand != null ? payload : _parse(_payload.text);
    if (data == null) {
      setState(() => _error = session.l10n.t('lab.invalidHex'));
      return;
    }
    setState(() => _error = null);
    await session.sendRaw(commandBytes.first, data);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final l10n = session.l10n;
    final theme = Theme.of(context);
    final logs = session.logs;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!session.connected)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link_off_rounded, size: 16, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.t('lab.notConnected'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  SizedBox(
                    width: 86,
                    child: TextField(
                      controller: _command,
                      decoration: InputDecoration(
                        labelText: l10n.t('lab.command'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                        LengthLimitingTextInputFormatter(2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _payload,
                      decoration: InputDecoration(
                        labelText: l10n.t('lab.payload'),
                        hintText: '00 01 …',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        errorText: _error,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F ,;:]')),
                        LengthLimitingTextInputFormatter(120),
                      ],
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: session.connected ? _send : null,
                    child: Text(l10n.t('lab.sendRaw')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.t('lab.note'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // 未连接时全部禁用：以前点了会静默什么都不做，很容易误判成耳机没反应。
              _Quick(
                label: '0xD0 · ${l10n.t('device.battery')}',
                onTap: session.connected ? () => _send(Op.batteryGet) : null,
              ),
              _Quick(
                label: '0xC6 · FW',
                onTap: session.connected ? () => _send(Op.firmwareGet) : null,
              ),
              _Quick(
                label: '0xC9 · ${l10n.t('device.name')}',
                onTap: session.connected ? () => _send(Op.nameGet) : null,
              ),
              // 0xC8（MAC）不会出现在这里：Fit900 的抓包里官方 App 从未发过它，
              // 对这台耳机发未知命令有风险，需要时可以在上面手动输入。
              _Quick(
                label: '0xCC · ANC',
                onTap: session.connected ? () => _send(Op.noiseGet) : null,
              ),
              _Quick(
                label: '0x08 · ${l10n.t('scene.title')}',
                onTap: session.connected ? () => _send(Op.sceneGet) : null,
              ),
              _Quick(
                label: '0xD5 · EQ',
                onTap: session.connected ? () => _send(Op.soundEffectGet) : null,
              ),
              _Quick(
                label: '0x91 · LDAC',
                onTap: session.connected ? () => _send(Op.settingGet) : null,
              ),
              _Quick(
                label: '0xD8 · FP',
                onTap: session.connected ? () => _send(Op.fingerprint) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  child: Row(
                    children: [
                      Text(
                        l10n.t('lab.log'),
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.t('lab.logSize', {'n': logs.length}),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: logs.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: logs
                                        .map((e) => '${e.stamp}  ${e.direction.name.toUpperCase().padRight(5)}  ${e.text}')
                                        .join('\n'),
                                  ),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.t('lab.copied'))),
                                );
                              },
                        icon: const Icon(Icons.copy_all_rounded, size: 16),
                        label: Text(l10n.t('lab.copy')),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: logs.isEmpty
                      ? Center(
                          child: Text(
                            l10n.t('lab.emptyLog'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            final entry = logs[logs.length - 1 - index];
                            return _LogRow(entry: entry);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Row(
            children: [
              Text(
                '${session.engine?.framing.name ?? '-'} · 0x2F',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: session.reread,
                icon: const Icon(Icons.radar_rounded, size: 16),
                label: Text(l10n.t('lab.reread')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.label, required this.onTap});

  final String label;

  /// 传 null 表示当前不可用（未连接）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        onPressed: onTap,
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (entry.direction) {
      LogDirection.tx => const Color(0xFF4C8DF6),
      LogDirection.rx => const Color(0xFF30A46C),
      LogDirection.error => theme.colorScheme.error,
      LogDirection.info => theme.colorScheme.onSurfaceVariant,
    };
    final tag = switch (entry.direction) {
      LogDirection.tx => 'TX',
      LogDirection.rx => 'RX',
      LogDirection.error => 'ERR',
      LogDirection.info => 'INFO',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              entry.stamp,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              tag,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              entry.text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: entry.direction == LogDirection.tx ? color : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
