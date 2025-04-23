import 'logger.dart';

/// 这是一个Logger类使用示例
/// 展示如何初始化和使用增强后的日志系统
void initializeLogger() async {
  // 初始化日志系统
  await Logger.init(
    level: LogLevel.debug, // 设置日志级别为debug，记录所有级别的日志
    logDir: 'logs', // 日志目录，默认为'logs'
    logFileName: 'magicpdf.log', // 日志文件名，默认为'app.log'
    maxLogFiles: 5, // 最大日志文件数量，默认为5
    maxLogSizeBytes: 2 * 1024 * 1024, // 单个日志文件最大大小，默认为1MB
    enableFileLogging: true, // 启用文件日志记录
  );
  
  // 记录不同级别的日志
  Logger.d('这是一条调试日志');
  Logger.i('这是一条信息日志');
  Logger.w('这是一条警告日志');
  Logger.e('这是一条错误日志');
  
  // 在应用中使用Logger的示例
  try {
    // 模拟一些操作
    final result = await performOperation();
    Logger.i('操作成功完成: $result');
  } catch (e) {
    // 记录异常
    Logger.e('操作失败: $e');
  }
}

// 模拟异步操作
Future<String> performOperation() async {
  // 模拟一些耗时操作
  await Future.delayed(Duration(seconds: 1));
  Logger.d('操作正在执行中...');
  return '操作结果';
}

/// 在应用启动时初始化日志系统的示例
/// 
/// ```dart
/// void main() async {
///   // 初始化日志系统
///   await Logger.init(
///     level: Logger.Level.info,
///     enableFileLogging: !kDebugMode, // 在生产环境启用文件日志
///   );
///   
///   Logger.i('应用启动');
///   runApp(MyApp());
/// }
/// ```