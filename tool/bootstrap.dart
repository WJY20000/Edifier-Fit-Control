// 生成缺失的平台目录，并把 Android / Windows 的配置改成这个应用需要的值。
//
// 为什么需要这一步：本仓库的作者环境里没有 Flutter SDK，android/ 与 windows/
// 是按「模板 + 补丁」的方式在构建机上生成的：先用 flutter create 在临时目录
// 生成与当前 Flutter 版本完全匹配的模板，再只拷贝仓库里不存在的文件，
// 这样既不会覆盖仓库内容，也不会出现「手写模板和 SDK 版本对不上」的问题。
//
// 用法：
//   dart tool/bootstrap.dart                        # android + windows
//   dart tool/bootstrap.dart --platforms=android    # 只生成 Android（CI 用）
//   dart tool/bootstrap.dart --platforms=windows    # 只生成 Windows（CI 用）
//   dart tool/bootstrap.dart --force                # 已存在的平台文件也重新生成
//
// 该脚本只依赖 dart:io，无需先跑 pub get。

import 'dart:io';

const String appLabel = 'EDIFIER Fit';
const String appTitle = 'EDIFIER Fit Control';
const String binaryName = 'EdifierFitControl';

Future<void> main(List<String> args) async {
  final root = Directory.current;
  final force = args.contains('--force');
  final platformArg = args
      .firstWhere((a) => a.startsWith('--platforms='), orElse: () => '--platforms=android,windows')
      .split('=')
      .last;
  final platforms = platformArg
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('请在仓库根目录运行：dart tool/bootstrap.dart');
    exitCode = 2;
    return;
  }

  print('==> 生成平台模板（Flutter 版本：${await _flutterVersion()}）');
  final tmp = Directory.systemTemp.createTempSync('edifier_scaffold_');
  try {
    final result = await Process.run(
      'flutter',
      [
        'create',
        '--no-pub',
        '--platforms=${platforms.join(',')}',
        '--project-name',
        'edifier_fit',
        '--org',
        'dev.edifierfit',
        tmp.path,
      ],
      runInShell: true,
    );
    if (result.exitCode != 0) {
      stderr.writeln('flutter create 失败：\n${result.stdout}\n${result.stderr}');
      exitCode = 1;
      return;
    }

    for (final folder in platforms) {
      final from = Directory('${tmp.path}/$folder');
      final to = Directory('${root.path}/$folder');
      if (!from.existsSync()) {
        stderr.writeln('模板里没有 $folder/，跳过');
        continue;
      }
      final copied = _copyMissing(from, to, force: force);
      print('==> $folder/：补齐 $copied 个文件');
    }
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }

  _patchAndroidManifest(root);
  _patchAndroidIcons(root);
  _patchAndroidGradle(root);
  _patchWindows(root);
  _patchWindowsIcon(root);

  print('==> 完成。现在可以 flutter pub get && flutter build windows --release');
}

Future<String> _flutterVersion() async {
  try {
    final result = await Process.run('flutter', ['--version'], runInShell: true);
    final text = '${result.stdout}';
    final first = text.split('\n').firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    return first.trim();
  } catch (_) {
    return 'unknown';
  }
}

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

int _copyMissing(Directory from, Directory to, {required bool force}) {
  var count = 0;
  if (!to.existsSync()) to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final targetPath = '${to.path}${Platform.pathSeparator}${_baseName(entity.path)}';
    if (entity is Directory) {
      count += _copyMissing(entity, Directory(targetPath), force: force);
    } else if (entity is File) {
      final target = File(targetPath);
      if (force || !target.existsSync()) {
        target.parent.createSync(recursive: true);
        entity.copySync(targetPath);
        count++;
      }
    }
  }
  return count;
}

/// 把 Gradle wrapper 的下载源换掉。
///
/// Flutter 3.47 的模板把 `distributionUrl` 指向 GitHub Releases
/// （`github.com/gradle/gradle-distributions/...`），构建机上偶尔会吃到 504；
/// Gradle wrapper 自己不会重试，一次抖动就让整次构建失败。
/// 换成官方 CDN 的 `-bin` 包：只有运行时、没有源码和文档，体积约 `-all` 的一半，
/// 下载更快也更不容易超时。
///
/// 版本号不写死，从模板自带的 URL 里解析 —— 换 Flutter 版本时跟着走。
void _patchAndroidGradle(Directory root) {
  final wrapper =
      File('${root.path}/android/gradle/wrapper/gradle-wrapper.properties');
  if (!wrapper.existsSync()) {
    stderr.writeln('找不到 gradle-wrapper.properties，跳过 Gradle 下载源改写');
    return;
  }
  var text = wrapper.readAsStringSync();
  final match = RegExp(r'gradle-([0-9][0-9.]*)-(?:all|bin)\.zip').firstMatch(text);
  if (match == null) {
    stderr.writeln('没能从 distributionUrl 解析 Gradle 版本，保持原样');
    return;
  }
  final version = match.group(1);
  // 整份重写，而不是只替换 distributionUrl：
  // 这样即使模板以后又换回别的源、或者少了重试参数，构建机上也一定是这一份。
  wrapper.writeAsStringSync(
    'distributionBase=GRADLE_USER_HOME\n'
    'distributionPath=wrapper/dists\n'
    'zipStoreBase=GRADLE_USER_HOME\n'
    'zipStorePath=wrapper/dists\n'
    'distributionUrl=https\\://services.gradle.org/distributions/gradle-$version-bin.zip\n'
    'networkTimeout=120000\n'
    // Gradle 8.9+ 的 wrapper 自己会重试：5 次、3 秒起步的指数退避。
    'retries=5\n'
    'retryBackOffMs=3000\n',
  );
  print('==> gradle-wrapper.properties：改用 services.gradle.org（$version, -bin, retries=5）');
}

void _patchAndroidManifest(Directory root) {
  final manifest = File('${root.path}/android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('找不到 AndroidManifest.xml，跳过权限注入');
    return;
  }
  var text = manifest.readAsStringSync();

  const permissions = '''
    <!-- 蓝牙扫描 / 连接（Android 12+ 改为运行时权限） -->
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <!-- API 30 及以下扫描 BLE 需要定位权限 -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
''';

  if (!text.contains('android.permission.BLUETOOTH_SCAN')) {
    if (text.contains('<application')) {
      text = text.replaceFirst('<application', '$permissions<application');
    } else {
      stderr.writeln('manifest 结构异常，未找到 <application>');
    }
  }

  text = text.replaceAll(RegExp(r'android:label="[^"]*"'), 'android:label="$appLabel"');
  manifest.writeAsStringSync(text);
  print('==> AndroidManifest.xml：已写入蓝牙权限与显示名');
}

void _patchAndroidIcons(Directory root) {
  const icons = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in icons.entries) {
    final source = File('${root.path}/tool/icons/ic_launcher_${entry.value}.png');
    if (!source.existsSync()) continue;
    final dir = Directory('${root.path}/android/app/src/main/res/mipmap-${entry.key}');
    dir.createSync(recursive: true);
    source.copySync('${dir.path}/ic_launcher.png');
  }
  print('==> Android 启动图标：已替换为耳机图标');
}

void _patchWindows(Directory root) {
  final mainCpp = File('${root.path}/windows/runner/main.cpp');
  if (mainCpp.existsSync()) {
    var text = mainCpp.readAsStringSync();
    text = text.replaceAll(RegExp(r'window\.Create\(L"[^"]*"'), 'window.Create(L"$appTitle"');
    text = text.replaceAll(
      RegExp(r'Win32Window::Size size\([^)]*\)'),
      'Win32Window::Size size(1120, 820)',
    );
    mainCpp.writeAsStringSync(text);
  }

  final cmake = File('${root.path}/windows/CMakeLists.txt');
  if (cmake.existsSync()) {
    final text = cmake
        .readAsStringSync()
        .replaceAll(RegExp(r'set\(BINARY_NAME "[^"]*"\)'), 'set(BINARY_NAME "$binaryName")');
    cmake.writeAsStringSync(text);
  }

  final rc = File('${root.path}/windows/runner/Runner.rc');
  if (rc.existsSync()) {
    var text = rc.readAsStringSync();
    text = text.replaceAll(RegExp(r'VALUE "ProductName", "[^"]*"'), 'VALUE "ProductName", "$appTitle"');
    text = text.replaceAll(
      RegExp(r'VALUE "FileDescription", "[^"]*"'),
      'VALUE "FileDescription", "$appTitle"',
    );
    text = text.replaceAll(RegExp(r'VALUE "InternalName", "[^"]*"'), 'VALUE "InternalName", "$binaryName"');
    text = text.replaceAll(
      RegExp(r'VALUE "OriginalFilename", "[^"]*"'),
      'VALUE "OriginalFilename", "$binaryName.exe"',
    );
    rc.writeAsStringSync(text);
  }
  print('==> Windows runner：窗口标题 / 可执行文件名已更新');
}

void _patchWindowsIcon(Directory root) {
  final source = File('${root.path}/assets/branding/app_icon.ico');
  final target = File('${root.path}/windows/runner/resources/app_icon.ico');
  if (!source.existsSync() || !target.parent.existsSync()) return;
  source.copySync(target.path);
  print('==> Windows 图标：已替换');
}
