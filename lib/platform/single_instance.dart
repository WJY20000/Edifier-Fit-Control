import 'dart:io';

/// 同一台机器上只允许跑一个实例。
///
/// 第二个实例会和第一个抢同一只耳机：Windows 上表现为「显示已断开、
/// 一直重连、但耳机其实还连在旧进程上」。
///
/// 判定方式：系统临时目录里的一个文件 + 排他文件锁。
/// 进程结束（包括被强杀）时操作系统会自动释放锁，所以不会出现
/// 「上次没退干净，这次永远起不来」。
///
/// 任何「判断不了」的情况都放行（返回 true）——不能因为锁的问题让应用打不开。
class SingleInstance {
  static RandomAccessFile? _handle;

  /// 拿到锁返回 true；已经有实例在跑返回 false。
  static bool acquire({String name = 'edifier_fit_control.lock'}) {
    // Android / iOS 由系统保证只有一个前台实例，不需要文件锁。
    if (Platform.isAndroid || Platform.isIOS) return true;

    final path = '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
    final RandomAccessFile handle;
    try {
      // append：文件不存在就创建，存在也不截断（不会破坏别的实例写的内容）。
      handle = File(path).openSync(mode: FileMode.append);
    } on FileSystemException catch (error) {
      // Windows 上另一种实例可能用「不共享」的方式打开着这个文件，
      // 此时连 open 都会失败（ERROR_SHARING_VIOLATION = 32 / LOCK_VIOLATION = 33）。
      final code = error.osError?.errorCode;
      if (code == 32 || code == 33) return false;
      // 其它原因（没有临时目录、权限不够……）：放行。
      return true;
    }

    try {
      // 非阻塞排他锁：拿不到就抛异常，不会傻等。
      handle.lockSync(FileLock.exclusive);
    } on FileSystemException catch (error) {
      try {
        handle.closeSync();
      } catch (_) {
        // 关不掉也无所谓，进程马上就退。
      }
      // 只有「确实被别人锁着」才算已经在运行：
      //   POSIX  EACCES(13) / EAGAIN(11)
      //   Windows ERROR_SHARING_VIOLATION(32) / ERROR_LOCK_VIOLATION(33)
      // 其它错误（文件系统不支持锁、权限、杀软干扰……）一律放行 ——
      // 宁可漏掉一次互斥，也不能让应用永远打不开。
      const contended = {11, 13, 32, 33};
      return !contended.contains(error.osError?.errorCode);
    } catch (_) {
      // 其它意外（平台不支持等）：同样放行，不能因为互斥让应用打不开。
      try {
        handle.closeSync();
      } catch (_) {}
      return true;
    }

    // 记下 PID，方便排障时确认是谁占着锁（写失败不影响锁本身）。
    // 只在文件为空时写，避免每次启动都往后追加。
    try {
      if (handle.lengthSync() == 0) {
        handle.writeStringSync('$pid\n');
        handle.flushSync();
      }
    } catch (_) {}

    _handle = handle;
    return true;
  }

  /// 主动释放（正常退出时由操作系统回收，这里主要给测试用）。
  static void release() {
    final handle = _handle;
    _handle = null;
    if (handle == null) return;
    try {
      handle.unlockSync();
    } catch (_) {}
    try {
      handle.closeSync();
    } catch (_) {}
  }
}
