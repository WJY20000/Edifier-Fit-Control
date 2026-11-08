/// 极简 i18n：不引入 intl / 代码生成，避免多一层构建依赖。
class L10n {
  const L10n(this.code);

  /// 'zh' 或 'en'
  final String code;

  static const List<String> supported = ['zh', 'en'];

  String t(String key, [Map<String, Object>? params]) {
    final entry = _values[key];
    if (entry == null) return key;
    var text = entry[code] ?? entry['en'] ?? key;
    if (params == null) return text;
    params.forEach((name, value) {
      text = text.replaceAll('{$name}', '$value');
    });
    return text;
  }

  String get languageName => code == 'zh' ? '中文' : 'English';

  static const Map<String, Map<String, String>> _values = {
    'app.title': {'zh': '漫步者 Fit 控制台', 'en': 'EDIFIER Fit Control'},
    'app.subtitle': {'zh': 'Fit900NB Turbo', 'en': 'Fit900NB Turbo'},
    'tab.device': {'zh': '设备', 'en': 'Device'},
    'tab.scan': {'zh': '扫描', 'en': 'Scan'},
    'tab.lab': {'zh': '实验室', 'en': 'Lab'},
    'tab.settings': {'zh': '设置', 'en': 'Settings'},

    'status.idle': {'zh': '未连接', 'en': 'Not connected'},
    'status.connecting': {'zh': '连接中…', 'en': 'Connecting…'},
    'status.connected': {'zh': '已连接', 'en': 'Connected'},
    'status.disconnected': {'zh': '已断开', 'en': 'Disconnected'},
    'status.scanning': {'zh': '扫描中…', 'en': 'Scanning…'},
    'status.reconnecting': {'zh': '正在重连…', 'en': 'Reconnecting…'},

    'scan.title': {'zh': '附近的设备', 'en': 'Nearby devices'},
    'scan.start': {'zh': '开始扫描', 'en': 'Start scan'},
    'scan.stop': {'zh': '停止', 'en': 'Stop'},
    'scan.all': {'zh': '显示全部蓝牙设备', 'en': 'Show all Bluetooth devices'},
    'scan.empty': {'zh': '还没有发现设备。请确认耳机已开机并处于配对模式。', 'en': 'No devices yet. Make sure the headphones are on and in pairing mode.'},
    'scan.hint': {'zh': '提示：耳机需要先在系统里断开，才能被本应用连接。', 'en': 'Tip: disconnect the headphones from the system first so this app can connect.'},
    'scan.permission': {'zh': '需要蓝牙权限', 'en': 'Bluetooth permission required'},
    'scan.connect': {'zh': '连接', 'en': 'Connect'},
    'scan.onlyEdifier': {'zh': '只看漫步者', 'en': 'EDIFIER only'},
    'scan.sourceScan': {'zh': '蓝牙扫描', 'en': 'BLE scan'},
    'scan.sourceSystem': {'zh': '系统设备', 'en': 'System devices'},
    'scan.systemEmpty': {
      'zh': '系统里没有已连接的蓝牙设备。耳机先用 Windows 连上，再回这里刷新。',
      'en': 'No connected Bluetooth device in the system. Connect the headphones in Windows first, then refresh here.',
    },
    'scan.systemNote': {
      'zh': '这里是 Windows 当前已连接的设备（不受广播影响），最适合耳机已经被系统占用的情况。',
      'en': 'Devices Windows currently has connected (independent of advertising). Best when the headphones are already taken by the system.',
    },
    'scan.unknownDevice': {'zh': '未命名设备', 'en': 'Unnamed device'},
    'scan.rawCount': {'zh': '未过滤 {n} 台', 'en': '{n} before filtering'},
    'scan.macTitle': {'zh': '按 MAC 地址直连', 'en': 'Connect by address'},
    'scan.mac': {'zh': 'MAC 直连', 'en': 'By address'},
    'scan.macBody': {
      'zh': '不扫描，直接连这个地址。耳机被 Windows 占着、不广播时，这是唯一可靠的办法。',
      'en': 'Skip scanning and connect straight to this address. The only reliable way when Windows holds the headphones and they stop advertising.',
    },
    'scan.connectMine': {'zh': '连接我的耳机', 'en': 'Connect my headphones'},
    'scan.winHint': {
      'zh': 'Windows 上的 BLE 和经典蓝牙是两套。系统里连上了，不代表 BLE 侧也绑定了；'
          '直连失败时，先在「蓝牙和设备」里删除这台耳机，再重新配对一次。',
      'en': 'On Windows, BLE and classic Bluetooth are separate. A classic connection does not '
          'mean the BLE side is bonded; if a direct connection fails, remove the headphones '
          'in Bluetooth & devices and pair them again.',
    },
    'settings.macPreset': {
      'zh': '已预填这台耳机的地址，直接点「保存并连接」即可。换耳机就在这里改。',
      'en': 'Prefilled with this headset\'s address. Just tap Save & connect; edit it for another device.',
    },
    'scan.macInvalid': {
      'zh': '格式不对，应该是 AA:BB:CC:DD:EE:FF 这种六段地址。',
      'en': 'Invalid address. Use the six-part form AA:BB:CC:DD:EE:FF.',
    },
    'settings.myDevice': {'zh': '我的耳机', 'en': 'My headphones'},
    'settings.myDeviceBody': {
      'zh': '固定一台设备后，扫描不到也能直接连；下次启动会优先用它。',
      'en': 'Pin one device: it can be connected even when scanning finds nothing, and it is used first on the next launch.',
    },
    'settings.macLabel': {'zh': 'MAC 地址', 'en': 'MAC address'},
    'settings.macHelper': {
      'zh': 'Windows：设置 → 蓝牙和设备 → 设备和打印机 → 右键耳机 → 属性 → 唯一标识符',
      'en': 'Windows: Settings → Bluetooth & devices → Devices & printers → right-click the headphones → Properties → Unique identifier',
    },
    'settings.macConnect': {'zh': '保存并连接', 'en': 'Save & connect'},
    'settings.macForget': {'zh': '取消固定', 'en': 'Unpin'},
    'settings.macSaved': {'zh': '已固定 {mac}', 'en': 'Pinned {mac}'},
    'device.connectMine': {'zh': '连接我的耳机', 'en': 'Connect my headphones'},

    'device.battery': {'zh': '电量', 'en': 'Battery'},
    'device.unknown': {'zh': '未知', 'en': 'Unknown'},
    'device.noise': {'zh': '降噪模式', 'en': 'Noise control'},
    'device.noiseUnsupported': {'zh': '未探测到降噪控制。打开「深度探测」后重试。', 'en': 'Noise control was not detected. Enable deep probing and retry.'},
    'device.ambientLevel': {'zh': '环境声等级', 'en': 'Ambient level'},
    'device.eq': {'zh': '音效预设', 'en': 'Sound effect'},
    'device.ldac': {'zh': 'LDAC 编码', 'en': 'LDAC codec'},
    'device.info': {'zh': '设备信息', 'en': 'Device info'},
    'device.firmware': {'zh': '固件版本', 'en': 'Firmware'},
    'device.mac': {'zh': 'MAC 地址', 'en': 'MAC address'},
    'device.name': {'zh': '设备名称', 'en': 'Device name'},
    'device.rename': {'zh': '重命名', 'en': 'Rename'},
    'device.renameHint': {'zh': '新的蓝牙名称（最多 30 字节）', 'en': 'New Bluetooth name (max 30 bytes)'},
    'device.protocol': {'zh': '协议', 'en': 'Protocol'},
    'device.framing': {'zh': '帧格式', 'en': 'Framing'},
    'device.ancDialect': {'zh': '降噪方言', 'en': 'ANC dialect'},
    'device.service': {'zh': '服务 UUID', 'en': 'Service UUID'},
    'device.mtu': {'zh': 'MTU', 'en': 'MTU'},
    'device.renegotiate': {'zh': '重新协商', 'en': 'Re-negotiate'},
    'device.refresh': {'zh': '刷新电量', 'en': 'Refresh battery'},
    'device.disconnect': {'zh': '断开连接', 'en': 'Disconnect'},
    'device.powerOff': {'zh': '关闭耳机', 'en': 'Power off headphones'},
    'device.reset': {'zh': '恢复出厂设置', 'en': 'Factory reset'},
    'device.resetConfirm': {'zh': '确定要让耳机恢复出厂设置？这会清除配对信息。', 'en': 'Factory reset the headphones? This clears pairing information.'},
    'device.unverified': {'zh': '该型号的协议尚未在真机验证', 'en': 'Protocol for this model is not verified on hardware'},
    'device.unverifiedBody': {
      'zh': '控制项按同代型号推断。若某项无效或连接掉线，请到「实验室」导出抓包并反馈。',
      'en': 'Controls are inferred from sibling models. If something fails or the link drops, export a capture from the Lab.',
    },

    'noise.deep': {'zh': '深度降噪', 'en': 'Deep ANC'},
    'noise.comfort': {'zh': '舒适降噪', 'en': 'Comfort ANC'},
    'noise.wind': {'zh': '防风噪', 'en': 'Anti-wind'},
    'noise.ambient': {'zh': '环境声', 'en': 'Ambient'},
    'noise.off': {'zh': '关闭', 'en': 'Off'},
    'noise.deeplike': {'zh': '降噪', 'en': 'ANC'},
    'noise.shortDeep': {'zh': '深度', 'en': 'Deep'},
    'noise.shortComfort': {'zh': '舒适', 'en': 'Comfort'},
    'noise.shortWind': {'zh': '防风', 'en': 'Wind'},
    'noise.shortAmbient': {'zh': '环境', 'en': 'Ambient'},
    'noise.shortOff': {'zh': '关闭', 'en': 'Off'},
    'noise.deepHint': {'zh': '最强的压制，地铁与机舱', 'en': 'Maximum isolation for transit and flights'},
    'noise.comfortHint': {'zh': '柔和一些，久戴不压耳', 'en': 'Softer isolation for long sessions'},
    'noise.windHint': {'zh': '压住风噪，户外通话更清楚', 'en': 'Tames wind noise for calls outdoors'},
    'noise.ambientHint2': {'zh': '放大周围声音，不用摘耳机', 'en': 'Let the outside in without removing them'},
    'noise.offHint': {'zh': '只靠耳罩隔音，最省电', 'en': 'Passive isolation only, easiest on battery'},

    'eq.classic': {'zh': '经典', 'en': 'Classic'},
    'eq.pop': {'zh': '流行', 'en': 'Pop'},
    'eq.classical': {'zh': '古典', 'en': 'Classical'},
    'eq.rock': {'zh': '摇滚', 'en': 'Rock'},

    'lab.title': {'zh': '协议实验室', 'en': 'Protocol lab'},
    'lab.hex': {'zh': '十六进制命令（不需要校验位）', 'en': 'Hex command (checksum added for you)'},
    'lab.send': {'zh': '发送', 'en': 'Send'},
    'lab.quick': {'zh': '快捷命令', 'en': 'Quick commands'},
    'lab.log': {'zh': '收发日志', 'en': 'Traffic log'},
    'lab.clear': {'zh': '清空', 'en': 'Clear'},
    'lab.copy': {'zh': '复制全部', 'en': 'Copy all'},
    'lab.copied': {'zh': '已复制到剪贴板', 'en': 'Copied to clipboard'},
    'lab.deepProbe': {'zh': '深度探测（会发送未验证的控制命令）', 'en': 'Deep probing (sends unverified control commands)'},
    'lab.rawHint': {'zh': '格式：命令字节 + 数据，例如 CC 1B 或 D0', 'en': 'Format: command byte + data, e.g. CC 1B or D0'},

    'settings.title': {'zh': '设置', 'en': 'Settings'},
    'settings.language': {'zh': '语言', 'en': 'Language'},
    'settings.theme': {'zh': '外观', 'en': 'Appearance'},
    'settings.themeSystem': {'zh': '跟随系统', 'en': 'System'},
    'settings.themeDark': {'zh': '深色', 'en': 'Dark'},
    'settings.themeLight': {'zh': '浅色', 'en': 'Light'},
    'settings.deepProbe': {'zh': '连接时深度探测', 'en': 'Deep probe on connect'},
    'settings.deepProbeBody': {
      'zh': '关闭时只读取电量与设备信息，不发送任何控制命令。',
      'en': 'When off, only battery and identity are read; no control commands are sent.',
    },
    'settings.autoReconnect': {'zh': '启动时重连上次设备', 'en': 'Reconnect last device on launch'},
    'settings.about': {'zh': '关于', 'en': 'About'},
    'settings.aboutBody': {
      'zh': '非官方工具，与漫步者无任何关联。协议来自社区逆向工程，按现状提供。',
      'en': 'Unofficial tool, not affiliated with EDIFIER. Protocol data comes from community reverse engineering, provided as-is.',
    },
    'settings.protocol': {'zh': '协议说明', 'en': 'Protocol notes'},
    'settings.version': {'zh': '版本', 'en': 'Version'},
    'settings.deepProbeEnable': {'zh': '启用深度探测', 'en': 'Enable deep probing'},
    'settings.developer': {'zh': '开发者', 'en': 'Developer'},
    'settings.developerRole': {
      'zh': '独立开发者 · 界面与协议整理',
      'en': 'Independent developer · UI and protocol notes',
    },
    'settings.author': {'zh': '作者', 'en': 'Author'},

    'scan.count': {'zh': '发现 {n} 台', 'en': '{n} found'},
    'scan.searching': {'zh': '正在搜索…', 'en': 'Searching…'},

    'device.connectFirst': {'zh': '还没有连接耳机', 'en': 'No headphones connected'},
    'device.connectFirstBody': {
      'zh': '到「扫描」页选择你的 Fit900NB Turbo。若系统已占用蓝牙连接，请先在系统设置里断开。',
      'en': 'Open the Scan tab and pick your Fit900NB Turbo. If the OS already holds the link, disconnect it in system settings first.',
    },
    'device.goScan': {'zh': '去扫描', 'en': 'Go to Scan'},
    'device.signal': {'zh': '信号', 'en': 'Signal'},
    'device.deepProbeNow': {'zh': '立即探测控制项', 'en': 'Probe controls now'},
    'device.noiseHidden': {
      'zh': '没有拿到降噪回读，控件已隐藏。点下面的按钮做一次深度探测。',
      'en': 'No noise-control reply, so the controls stay hidden. Run a deep probe below.',
    },
    'device.ambientHint': {
      'zh': '环境声等级用旧版命令字读取，仅在 v1 方言下开放。',
      'en': 'Ambient level is only exposed for the legacy (v1) dialect.',
    },
    'device.renameTitle': {'zh': '重命名耳机', 'en': 'Rename headphones'},
    'device.renameDone': {'zh': '已改名，重新连接后生效', 'en': 'Renamed — takes effect after reconnecting'},
    'device.manage': {'zh': '管理', 'en': 'Manage'},
    'device.options': {'zh': '可用控制', 'en': 'Available controls'},
    'device.ldacHint': {
      'zh': '切换 LDAC 会让耳机重新配对，链路会短暂断开。',
      'en': 'Switching LDAC re-pairs the headphones; the link drops briefly.',
    },
    'device.mtuValue': {'zh': '每包 {n} 字节', 'en': '{n} bytes / packet'},

    'scene.title': {'zh': '场景', 'en': 'Sound scene'},
    'scene.music': {'zh': '音乐', 'en': 'Music'},
    'scene.game': {'zh': '游戏', 'en': 'Game'},
    'scene.spatial': {'zh': '空间音效', 'en': 'Spatial audio'},
    'scene.hint': {
      'zh': '游戏与空间音效会接管音效预设，此时音效不可调。',
      'en': 'Game and Spatial audio take over the EQ presets; sound effect is locked.',
    },
    'scene.musicHint': {'zh': '原声，不做额外处理', 'en': 'Untouched, no extra processing'},
    'scene.gameHint': {'zh': '降低延迟，音画同步', 'en': 'Lower latency for games'},
    'scene.spatialHint': {'zh': '虚拟环绕声场', 'en': 'Virtual surround field'},
    'eq.hint': {
      'zh': '六组调音，按官方 App 的顺序排列。',
      'en': 'Six tunings, in the same order as the official app.',
    },
    'device.advanced': {'zh': '高级', 'en': 'Advanced'},
    'device.advancedHint': {
      'zh': 'LDAC 编码、设备信息与管理操作',
      'en': 'LDAC codec, device info and maintenance',
    },
    'device.refreshHint': {'zh': '刷新电量', 'en': 'Refresh battery'},
    'ldac.off': {'zh': '关闭', 'en': 'Off'},
    'ldac.auto': {'zh': '44.1 / 48 kHz', 'en': '44.1 / 48 kHz'},
    'ldac.hires': {'zh': '96 kHz', 'en': '96 kHz'},
    'ldac.offShort': {'zh': '关闭', 'en': 'Off'},
    'ldac.autoShort': {'zh': '44.1/48k', 'en': '44.1/48k'},
    'ldac.hiresShort': {'zh': '96k', 'en': '96k'},
    'ambient.vocal': {'zh': '突出人声', 'en': 'Vocal'},
    'ambient.balanced': {'zh': '平衡', 'en': 'Balanced'},
    'ambient.background': {'zh': '突出背景声', 'en': 'Ambience'},
    'ambient.vocalHint': {'zh': '对话更清楚', 'en': 'Clearer speech'},
    'ambient.balancedHint': {'zh': '自然通透', 'en': 'Natural' },
    'ambient.backgroundHint': {'zh': '保留环境氛围', 'en': 'More surroundings'},
    'device.connectedTo': {'zh': '当前设备', 'en': 'CURRENT DEVICE'},
    'device.verifiedShort': {'zh': '真机验证', 'en': 'Verified'},
    'eq.vocal': {'zh': '人声', 'en': 'Vocal'},
    'eq.bass': {'zh': '低音增强', 'en': 'Bass boost'},
    'eq.dynamic': {'zh': '动感', 'en': 'Dynamic'},
    'eq.pure': {'zh': '纯正', 'en': 'Pure'},
    'eq.treble': {'zh': '高音增强', 'en': 'Treble boost'},
    'eq.audiophile': {'zh': '发烧友', 'en': 'Audiophile'},
    'eq.locked': {
      'zh': '先把场景切回「音乐」才能调整音效。',
      'en': 'Switch the scene back to Music to change the sound effect.',
    },

    'lab.notConnected': {'zh': '未连接：先到扫描页连上耳机。', 'en': 'Not connected: pair from the Scan tab first.'},
    'lab.command': {'zh': '命令字', 'en': 'Command'},
    'lab.payload': {'zh': '数据（十六进制）', 'en': 'Payload (hex)'},
    'lab.sendRaw': {'zh': '发送', 'en': 'Send'},
    'lab.invalidHex': {'zh': '十六进制格式不对', 'en': 'Invalid hex'},
    'lab.emptyLog': {'zh': '还没有收发记录。', 'en': 'No traffic yet.'},
    'lab.note': {
      'zh': '这里发送的字节按当前协商到的帧格式封装，不做校验重试。乱发命令有可能让耳机断开，这是正常的。',
      'en': 'Bytes are wrapped in the negotiated framing, without retries. An unknown command may drop the link — that is expected.',
    },
    'lab.logSize': {'zh': '{n} 条', 'en': '{n} entries'},
    'lab.direction.tx': {'zh': '发送', 'en': 'TX'},
    'lab.direction.rx': {'zh': '接收', 'en': 'RX'},
    'lab.direction.info': {'zh': '信息', 'en': 'INFO'},
    'lab.direction.error': {'zh': '错误', 'en': 'ERR'},

    'eq.preset5': {'zh': '预设 5', 'en': 'Preset 5'},
    'eq.preset6': {'zh': '预设 6', 'en': 'Preset 6'},
    'noise.adaptive': {'zh': '自适应', 'en': 'Adaptive'},

    'settings.model': {'zh': '目标型号', 'en': 'Target model'},
    'settings.modelBody': {
      'zh': '本工具只针对 Fit900NB Turbo 调校，同时保留其他漫步者型号的兼容档案。',
      'en': 'Tuned for the Fit900NB Turbo, while keeping compatibility profiles for other EDIFIER models.',
    },
    'settings.unverified': {'zh': '协议未在真机验证', 'en': 'Protocol not verified on hardware'},

    'common.cancel': {'zh': '取消', 'en': 'Cancel'},
    'common.ok': {'zh': '确定', 'en': 'OK'},
    'common.on': {'zh': '开', 'en': 'On'},
    'common.off': {'zh': '关', 'en': 'Off'},
    'common.failed': {'zh': '操作失败', 'en': 'Operation failed'},
    'common.retry': {'zh': '重试', 'en': 'Retry'},
    'common.close': {'zh': '关闭', 'en': 'Close'},
  };
}
