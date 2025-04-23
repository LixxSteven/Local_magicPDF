import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

// 日志级别枚举
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 日志工具类，用于替代直接使用print的方式
/// 支持不同级别的日志记录，并可以根据环境控制日志输出
class Logger {

  // 当前日志级别，默认为info
  static LogLevel _currentLevel = LogLevel.info;
  
  // 日志文件配置
  static String _logDir = 'logs';
  static String _logFileName = 'app.log';
  static int _maxLogFiles = 5;
  static int _maxLogSizeBytes = 1024 * 1024; // 1MB
  static bool _enableFileLogging = false;
  static File? _currentLogFile;
  
  /// 初始化日志系统
  static Future<void> init({
    LogLevel level = LogLevel.info,
    String? logDir,
    String? logFileName,
    int? maxLogFiles,
    int? maxLogSizeBytes,
    bool enableFileLogging = false,
  }) async {
    _currentLevel = level;
    if (logDir != null) _logDir = logDir;
    if (logFileName != null) _logFileName = logFileName;
    if (maxLogFiles != null) _maxLogFiles = maxLogFiles;
    if (maxLogSizeBytes != null) _maxLogSizeBytes = maxLogSizeBytes;
    _enableFileLogging = enableFileLogging;
    
    if (_enableFileLogging) {
      await _initLogFile();
    }
  }
  
  // 初始化日志文件
  static Future<void> _initLogFile() async {
    try {
      // 创建日志目录
      final Directory dir = Directory(_logDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 设置当前日志文件
      _currentLogFile = File(path.join(_logDir, _logFileName));
      
      // 检查日志文件大小，如果超过限制则进行轮转
      if (await _currentLogFile!.exists()) {
        final int size = await _currentLogFile!.length();
        if (size > _maxLogSizeBytes) {
          await _rotateLogFiles();
        }
      }
      
      i('日志系统初始化完成，日志文件: ${_currentLogFile!.path}');
    } catch (e) {
      // 在开发模式下输出错误
      if (kDebugMode) {
        print('日志系统初始化失败: $e');
      }
      _enableFileLogging = false;
    }
  }
  
  // 日志文件轮转
  static Future<void> _rotateLogFiles() async {
    try {
      // 删除最旧的日志文件（如果存在）
      final oldestLogFile = File(path.join(_logDir, '$_logFileName.$_maxLogFiles'));
      if (await oldestLogFile.exists()) {
        await oldestLogFile.delete();
      }
      
      // 重命名现有的日志文件，从最旧到最新
      for (int i = _maxLogFiles - 1; i >= 1; i--) {
        final File currentFile = File(path.join(_logDir, '$_logFileName.$i'));
        if (await currentFile.exists()) {
          final File newFile = File(path.join(_logDir, '$_logFileName.${i + 1}'));
          await currentFile.rename(newFile.path);
        }
      }
      
      // 重命名当前日志文件为 .1
      if (await _currentLogFile!.exists()) {
        final File newFile = File(path.join(_logDir, '$_logFileName.1'));
        await _currentLogFile!.rename(newFile.path);
      }
      
      // 创建新的日志文件
      _currentLogFile = File(path.join(_logDir, _logFileName));
      await _currentLogFile!.create();
      
      i('日志文件已轮转');
    } catch (e) {
      if (kDebugMode) {
        print('日志文件轮转失败: $e');
      }
    }
  }

  // 设置日志级别
  static void setLevel(LogLevel level) {
    _currentLevel = level;
  }

  // 记录调试信息
  static void d(String message) {
    if (_shouldLog(LogLevel.debug)) {
      _log('DEBUG', message);
    }
  }

  // 记录一般信息
  static void i(String message) {
    if (_shouldLog(LogLevel.info)) {
      _log('INFO', message);
    }
  }

  // 记录警告信息
  static void w(String message) {
    if (_shouldLog(LogLevel.warning)) {
      _log('WARNING', message);
    }
  }

  // 记录错误信息
  static void e(String message) {
    if (_shouldLog(LogLevel.error)) {
      _log('ERROR', message);
    }
  }

  // 判断是否应该记录该级别的日志
  static bool _shouldLog(LogLevel level) {
    return level.index >= _currentLevel.index;
  }

  // 实际的日志记录方法
  static void _log(String levelName, String message) {
    // 格式化日志消息，添加时间戳
    final DateTime now = DateTime.now();
    final String formattedDate = '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}';
    final String formattedTime = '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}.${_threeDigits(now.millisecond)}';
    final String formattedMessage = '[$formattedDate $formattedTime] [$levelName] $message';
    
    // 在开发模式下输出到控制台
    if (kDebugMode) {
      print(formattedMessage);
    }
    
    // 在生产环境写入日志文件
    if (_enableFileLogging && _currentLogFile != null) {
      _writeToLogFile(formattedMessage);
    }
  }
  
  // 将日志写入文件
  static void _writeToLogFile(String message) async {
    try {
      // 检查日志文件是否存在，不存在则创建
      if (!await _currentLogFile!.exists()) {
        await _currentLogFile!.create(recursive: true);
      }
      
      // 检查日志文件大小，如果超过限制则进行轮转
      final int size = await _currentLogFile!.length();
      if (size > _maxLogSizeBytes) {
        await _rotateLogFiles();
      }
      
      // 写入日志消息，添加换行符
      await _currentLogFile!.writeAsString('$message\n', mode: FileMode.append);
    } catch (e) {
      if (kDebugMode) {
        print('写入日志文件失败: $e');
      }
    }
  }
  
  // 格式化为两位数字
  static String _twoDigits(int n) {
    if (n >= 10) return '$n';
    return '0$n';
  }
  
  // 格式化为三位数字
  static String _threeDigits(int n) {
    if (n >= 100) return '$n';
    if (n >= 10) return '0$n';
    return '00$n';
  }
}