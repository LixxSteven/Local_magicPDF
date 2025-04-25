import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:math' as math;
import '../utils/logger.dart';

enum ConversionType {
  markdown, // 暂时只支持Markdown
  // docx, // MinerU API 目前不直接支持
  // html  // MinerU API 目前不直接支持
}

class MineruService {
  // 默认MinerU API地址，用户可能需要根据实际情况修改
  final String baseUrl;
  // 重试次数
  final int maxRetries;
  // 重试间隔（秒）
  final int retryInterval;
  // 连接超时时间（秒）
  final int connectionTimeout;
  // 请求超时时间（秒）
  final int requestTimeout;

  MineruService({
    this.baseUrl = 'http://localhost:8888', 
    this.maxRetries = 3, 
    this.retryInterval = 2,
    this.connectionTimeout = 10,
    this.requestTimeout = 30
  });

  /// 检查MinerU API服务是否可用
  Future<bool> checkServiceAvailability() async {
    try {
      final pingUrl = Uri.parse('$baseUrl/ping');
      final pingResponse = await http.get(pingUrl).timeout(Duration(seconds: connectionTimeout));
      return pingResponse.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 估算PDF转换时间（考虑文件大小和复杂度）
  int estimateConversionTime(int fileSize, File pdfFile) {
    // 基础时间：每MB约2秒
    int baseTime = (fileSize / 1024 / 1024 * 2).round();
    
    // 尝试分析PDF复杂度因素
    int complexityFactor = 1;
    try {
      // 文件名包含'scan'或'扫描'可能表示是扫描PDF，处理时间更长
      String fileName = path.basename(pdfFile.path).toLowerCase();
      if (fileName.contains('scan') || fileName.contains('扫描')) {
        complexityFactor = 2; // 扫描文件处理时间约为普通文件的2倍
      }
      
      // 超大文件需要更多处理时间
      if (fileSize > 10 * 1024 * 1024) { // 大于10MB
        complexityFactor = math.max(complexityFactor, 2);
      }
      
      // 极大文件可能需要更多时间
      if (fileSize > 50 * 1024 * 1024) { // 大于50MB
        complexityFactor = math.max(complexityFactor, 3);
      }
    } catch (e) {
      // 分析失败，使用默认复杂度
    }
    
    return baseTime * complexityFactor;
  }

  /// 将PDF文件转换为指定格式 (目前仅支持Markdown)
  Future<String> convertPdf(
    File pdfFile, 
    ConversionType type, // 这个参数现在主要用于函数签名兼容，实际格式由outputFormat决定
    Function(int, int) onProgress, 
    {
      // --- 新增高级选项参数 ---
      bool extractImages = true,
      bool preserveLayout = true,
      String outputFormat = 'markdown',
      bool detectLanguage = true,
      bool supportTables = true,
      // --- 结束新增 ---
    }
  ) async {
    // 检查是否为支持的类型 (根据 outputFormat 检查可能更合适，但为保持兼容性暂时保留)
    // if (type != ConversionType.markdown) {
    //   throw Exception('当前仅支持转换为Markdown格式');
    // }

    // 估算转换时间 (根据文件大小和复杂度估计)
    final fileSize = await pdfFile.length();
    final int estimatedTime = estimateConversionTime(fileSize, pdfFile);
    
    // 在日志中输出预估时间信息
    Logger.i('PDF文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB, 预估转换时间: $estimatedTime秒');
    
    // 首先调用进度回调，表示开始处理
    onProgress(0, 100);
    
    // 实现自动重试机制
    int retryCount = 0;
    while (true) {
      try {
        // 检查MinerU API服务是否可用
        bool isServiceAvailable = await checkServiceAvailability();
        if (!isServiceAvailable) {
          if (retryCount < maxRetries) {
            retryCount++;
            await Future.delayed(Duration(seconds: retryInterval));
            continue; // 重试连接
          } else {
            throw Exception('无法连接到MinerU API服务，已重试$maxRetries次。请确保MinerU服务已启动并运行在端口8888上');
          }
        }
        
        // 准备请求URL - 使用统一的 file_parse 端点
        final url = Uri.parse('$baseUrl/file_parse');

        // 创建multipart请求
        var request = http.MultipartRequest('POST', url);

        // 添加PDF文件
        request.files.add(await http.MultipartFile.fromPath(
          'file', // API期望的文件字段名
          pdfFile.path,
          filename: path.basename(pdfFile.path)
        ));

        // 添加其他参数 (包括高级选项)
        request.fields['return_content_list'] = 'false'; // 一般情况下，直接获取完整结果
        request.fields['extract_images'] = extractImages.toString();
        request.fields['preserve_layout'] = preserveLayout.toString();
        request.fields['output_format'] = outputFormat;
        request.fields['detect_language'] = detectLanguage.toString();
        request.fields['support_tables'] = supportTables.toString();
        
        // 更新进度为10%，表示文件已上传准备处理
        onProgress(10, 100);

        // 发送请求 (使用配置的超时时间)
        final response = await request.send().timeout(
          Duration(seconds: requestTimeout), 
          onTimeout: () {
            throw TimeoutException('连接MinerU API服务超时，请检查服务是否正常运行');
          }
        );
        
        // 更新进度为30%，表示请求已发送
        onProgress(30, 100);

        // 检查响应状态
        if (response.statusCode == 200) {
          // 更新进度为50%，表示开始处理响应数据
          onProgress(50, 100);
          
          // 读取响应内容
          final responseData = await response.stream.bytesToString();
          
          // 更新进度为70%，表示已获取响应数据
          onProgress(70, 100);
          
          final jsonData = json.decode(responseData);
          
          // 更新进度为80%，表示已解析JSON数据
          onProgress(80, 100);

          // 根据API返回格式提取结果
          String result = "";
          if (jsonData['result'] != null) { // 优先使用 'result' 字段
            result = jsonData['result'].toString();
          } else if (jsonData['content_list'] != null && jsonData['content_list'] is List) {
            result = (jsonData['content_list'] as List).map((item) => item.toString()).join('\n\n');
          } else {
            result = responseData; // 返回原始JSON字符串以供调试
          }
          
          // 更新进度为100%，表示处理完成
          onProgress(100, 100);
          return result;

        } else {
          // 处理HTTP错误
          final errorBody = await response.stream.bytesToString();
          if (retryCount < maxRetries && (response.statusCode >= 500 || response.statusCode == 429)) {
            // 服务器错误或请求过多，可以重试
            retryCount++;
            await Future.delayed(Duration(seconds: retryInterval));
            continue;
          }
          throw Exception('转换失败: ${response.statusCode} - ${response.reasonPhrase} - $errorBody');
        }
      } catch (e) {
        // 处理异常
        if (e is TimeoutException && retryCount < maxRetries) {
          retryCount++;
          await Future.delayed(Duration(seconds: retryInterval));
          continue; // 超时重试
        } else if (retryCount < maxRetries && !(e is Exception && e.toString().contains('当前仅支持转换'))) {
          // 对于非格式不支持的错误，进行重试
          retryCount++;
          await Future.delayed(Duration(seconds: retryInterval));
          continue;
        }
        throw Exception('PDF转换过程中出错: $e');
      }
    }
  }

  // _getEndpointForType 不再需要，因为使用统一端点
  // String _getEndpointForType(ConversionType type) { ... }

  /// 保存转换结果到文件 (现在只处理文本内容)
  Future<File> saveConversionResult(String content, String outputPath) async {
    try {
      final file = File(outputPath);
      // 确保父目录存在
      await file.parent.create(recursive: true);
      return await file.writeAsString(content);
    } catch (e) {
      throw Exception('保存转换结果时出错: $e');
    }
  }
  
  /// 通过本地脚本安装MinerU服务和相关环境
  Future<bool> installMineruEnvironment({Function(String)? onProgress, Function(String)? onError}) async {
    try {
      if (onProgress != null) {
        onProgress('正在准备安装MinerU服务环境...');
      }
      
      // 获取应用程序根目录
      final String appDir = Directory.current.path;
      Logger.i('应用程序目录: $appDir');
      
      // 检查是否有足够的磁盘空间（至少需要20GB）
      try {
        var tempDir = Platform.isWindows ? 'C:\\' : '/tmp';
        var result = await Process.run(
          Platform.isWindows ? 'powershell' : 'df',
          Platform.isWindows 
              ? ['-Command', '(Get-PSDrive C).Free'] 
              : ['-h', tempDir],
        );
        
        Logger.i('磁盘空间检查: ${result.stdout}');
        
        if (onProgress != null) {
          onProgress('检查系统环境和磁盘空间...');
        }
        
        // 记录系统环境信息便于调试
        Logger.i('操作系统: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
        Logger.i('Dart版本: ${Platform.version}');
        Logger.i('本地路径: ${Platform.localeName}');
      } catch (e) {
        Logger.w('检查磁盘空间时出错: $e');
      }
      
      // 构建安装脚本路径
      final String installerDir = path.join(appDir, 'resources', 'installer');
      
      // 确保安装脚本存在
      final String scriptPath = Platform.isWindows
          ? path.join(installerDir, 'install_conda_mineru.ps1')
          : path.join(installerDir, 'install_conda_mineru.sh');
          
      if (!File(scriptPath).existsSync()) {
        final errorMsg = '安装脚本不存在: $scriptPath';
        Logger.e(errorMsg);
        if (onError != null) {
          onError(errorMsg);
        }
        return false;
      }
      
      String installerScript;
      List<String> args;
      
      if (Platform.isWindows) {
        installerScript = 'powershell';
        args = ['-ExecutionPolicy', 'Bypass', '-File', scriptPath];
        
        if (onProgress != null) {
          onProgress('正在使用Windows PowerShell脚本安装...');
        }
      } else {
        installerScript = '/bin/bash';
        
        // 确保脚本有执行权限
        await Process.run('chmod', ['+x', scriptPath]);
        args = [scriptPath];
        
        if (onProgress != null) {
          onProgress('正在使用Bash脚本安装...');
        }
      }
      
      // 记录重要信息
      Logger.i('安装脚本: $installerScript');
      Logger.i('安装脚本参数: $args');
      
      // 检查PowerShell执行策略(仅Windows)
      if (Platform.isWindows) {
        try {
          var policyResult = await Process.run(
            'powershell', 
            ['-Command', 'Get-ExecutionPolicy'],
          );
          Logger.i('PowerShell执行策略: ${policyResult.stdout}');
          
          if (policyResult.stdout.toString().trim().toLowerCase() == 'restricted') {
            if (onProgress != null) {
              onProgress('PowerShell执行策略受限，尝试临时更改...');
            }
          }
        } catch (e) {
          Logger.w('检查PowerShell执行策略时出错: $e');
        }
      }
      
      // 启动安装进程，指定工作目录
      final process = await Process.start(
        installerScript,
        args,
        workingDirectory: appDir,
        mode: ProcessStartMode.normal, // 使用normal模式而不是inheritStdio，以便捕获输出
      );
      
      // 收集输出并更新进度
      List<String> outputLines = [];
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        outputLines.add(line);
        Logger.i('安装输出: $line');
        
        if (onProgress != null) {
          // 提取关键进度信息
          if (line.contains('下载') || line.contains('安装') || 
              line.contains('创建') || line.contains('设置') || 
              line.contains('启动')) {
            onProgress(line);
          }
        }
      });
      
      // 收集错误输出
      List<String> errorLines = [];
      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        errorLines.add(line);
        Logger.e('安装错误: $line');
        
        if (onError != null) {
          onError(line);
        }
      });
      
      // 等待进程完成，但设置超时避免无限等待
      bool processFinished = false;
      Timer? timeoutTimer;
      final completer = Completer<int>();
      
      // 设置30分钟超时
      timeoutTimer = Timer(Duration(minutes: 30), () {
        if (!processFinished && !completer.isCompleted) {
          Logger.e('安装进程超时，强制结束');
          process.kill();
          completer.complete(-100); // 特殊退出码表示超时
        }
      });
      
      // 获取实际的进程退出码
      final exitCode = await process.exitCode;
      processFinished = true;
      
      if (timeoutTimer.isActive) {
        timeoutTimer.cancel();
      }
      
      if (!completer.isCompleted) {
        completer.complete(exitCode);
      }
      
      final finalExitCode = await completer.future;
      
      // 检查安装结果
      if (finalExitCode == 0) {
        if (onProgress != null) {
          onProgress('MinerU服务环境安装成功');
        }
        Logger.i('MinerU服务环境安装成功');
        return true;
      } else if (finalExitCode == -100) {
        final errorMsg = '安装超时，请检查系统资源和网络连接';
        Logger.e(errorMsg);
        if (onError != null) {
          onError(errorMsg);
        }
        return false;
      } else {
        final errorMsg = '安装失败，退出代码: $finalExitCode\n错误信息: ${errorLines.join('\n')}\n输出信息: ${outputLines.join('\n')}';
        Logger.e(errorMsg);
        if (onError != null) {
          onError('安装失败，退出代码: $finalExitCode\n错误信息: ${errorLines.join('\n')}');
        }
        return false;
      }
    } catch (e) {
      final errorMsg = '安装MinerU服务环境时出错: $e';
      Logger.e(errorMsg);
      if (onError != null) {
        onError(errorMsg);
      }
      return false;
    }
  }
  
  /// 获取本地安装的MinerU服务脚本路径
  Future<String?> getLocalMineruServiceScript() async {
    try {
      final String localAppDataPath = Platform.isWindows 
          ? path.join(Platform.environment['LOCALAPPDATA']!, 'MagicPDF')
          : path.join(Platform.environment['HOME']!, '.magicpdf');
      
      final String scriptName = Platform.isWindows 
          ? 'start_mineru_service.bat' 
          : 'start_mineru_service.sh';
      
      final String scriptPath = path.join(localAppDataPath, scriptName);
      
      if (await File(scriptPath).exists()) {
        Logger.i('找到本地MinerU服务脚本: $scriptPath');
        return scriptPath;
      } else {
        Logger.w('本地MinerU服务脚本不存在: $scriptPath');
        return null;
      }
    } catch (e) {
      Logger.e('获取本地MinerU服务脚本路径时出错: $e');
      return null;
    }
  }

  /// 启动本地安装的MinerU服务
  Future<bool> startLocalMineruService({Function(String)? onProgress, Function(String)? onError}) async {
    try {
      // 获取本地服务脚本路径
      final scriptPath = await getLocalMineruServiceScript();
      if (scriptPath == null) {
        if (onError != null) {
          onError('未找到本地MinerU服务脚本，请先安装MinerU服务环境\n检查位置: ${Platform.isWindows ? path.join(Platform.environment['LOCALAPPDATA']!, 'MagicPDF') : path.join(Platform.environment['HOME']!, '.magicpdf')}');
        }
        return false;
      }
      
      // 检查脚本是否可执行
      final scriptFile = File(scriptPath);
      if (!await scriptFile.exists()) {
        final errorMsg = '启动脚本文件不存在: $scriptPath';
        Logger.e(errorMsg);
        if (onError != null) {
          onError(errorMsg);
        }
        return false;
      }
      
      // 检查端口8888是否被占用
      try {
        if (Platform.isWindows) {
          var portCheckResult = await Process.run(
            'powershell',
            ['-Command', 'Get-NetTCPConnection -LocalPort 8888 -ErrorAction SilentlyContinue'],
          );
          if (portCheckResult.stdout.toString().trim().isNotEmpty) {
            Logger.w('端口8888已被占用');
            
            // 尝试检查是否是MinerU服务占用
            if (await checkServiceAvailability()) {
              Logger.i('端口被MinerU服务占用，服务已经运行');
              if (onProgress != null) {
                onProgress('MinerU服务已经在运行');
              }
              return true;
            } else {
              if (onError != null) {
                onError('端口8888被其他应用占用，请关闭占用该端口的应用后重试');
              }
              return false;
            }
          }
        } else {
          var portCheckResult = await Process.run(
            'lsof', 
            ['-i:8888'],
          );
          if (portCheckResult.stdout.toString().trim().isNotEmpty) {
            Logger.w('端口8888已被占用');
            
            // 尝试检查是否是MinerU服务占用
            if (await checkServiceAvailability()) {
              Logger.i('端口被MinerU服务占用，服务已经运行');
              if (onProgress != null) {
                onProgress('MinerU服务已经在运行');
              }
              return true;
            } else {
              if (onError != null) {
                onError('端口8888被其他应用占用，请关闭占用该端口的应用后重试');
              }
              return false;
            }
          }
        }
      } catch (e) {
        Logger.w('检查端口占用时出错: $e');
        // 继续执行，不要因为无法检查端口而中断
      }
      
      if (onProgress != null) {
        onProgress('正在通过本地脚本启动MinerU服务...');
      }
      
      // 构建启动命令
      String command;
      List<String> args;
      
      if (Platform.isWindows) {
        command = 'cmd.exe';
        args = ['/c', 'start', '/b', scriptPath];
      } else {
        command = '/bin/bash';
        args = [scriptPath];
      }
      
      // 启动服务进程
      final process = await Process.start(
        command,
        args,
        mode: ProcessStartMode.detached,
        workingDirectory: path.dirname(scriptPath),
      );
      
      Logger.i('MinerU服务进程已启动，PID: ${process.pid}');
      
      // 给服务一些启动时间
      if (onProgress != null) {
        onProgress('MinerU服务启动中，请稍候...');
      }
      
      // 定义最大重试次数和重试间隔
      final maxRetries = 20; // 20次重试，每次1秒，总共等待20秒
      final retryInterval = Duration(seconds: 1);
      
      // 等待服务启动并检查可用性
      for (int i = 0; i < maxRetries; i++) {
        await Future.delayed(retryInterval);
        
        if (onProgress != null && i % 5 == 0) {
          onProgress('MinerU服务启动中 (${(i / maxRetries * 100).round()}%)...');
        }
        
        // 检查服务是否可用
        if (await checkServiceAvailability()) {
          if (onProgress != null) {
            onProgress('MinerU服务已成功启动');
          }
          Logger.i('MinerU服务已通过本地脚本成功启动');
          return true;
        }
      }
      
      // 如果超时但可能服务已启动，再检查一次
      Logger.w('服务启动超时，进行最后一次检查');
      if (await checkServiceAvailability()) {
        if (onProgress != null) {
          onProgress('MinerU服务已成功启动 (延迟响应)');
        }
        Logger.i('MinerU服务已通过本地脚本成功启动（延迟响应）');
        return true;
      }
      
      // 如果进程仍在运行但服务不可用，返回警告
      if (process.kill()) {
        if (onProgress != null) {
          onProgress('MinerU服务已启动，但健康检查超时。请手动验证服务是否可用。');
        }
        Logger.w('MinerU服务已启动，但健康检查超时');
        return true;
      } else {
        if (onError != null) {
          onError('MinerU服务启动失败。可能原因：\n1. 端口8888被占用\n2. Python环境配置问题\n3. 依赖项安装不完整\n\n请查看日志文件获取详细信息。');
        }
        Logger.e('MinerU服务启动失败');
        return false;
      }
    } catch (e) {
      final errorMsg = '启动本地MinerU服务时出错: $e';
      Logger.e(errorMsg);
      if (onError != null) {
        onError(errorMsg);
      }
      return false;
    }
  }
  
  /// 改进的启动MinerU服务方法，增加自动安装功能
  Future<bool> startMineruService({Function(String)? onError, Function(String)? onProgress}) async {
    try {
      // 检查服务是否已经在运行
      if (await checkServiceAvailability()) {
        Logger.i('MinerU服务已经在运行');
        if (onProgress != null) {
          onProgress('MinerU服务已经在运行');
        }
        return true;
      }
      
      // 尝试通过本地脚本启动服务
      final String? scriptPath = await getLocalMineruServiceScript();
      if (scriptPath != null) {
        if (onProgress != null) {
          onProgress('发现本地MinerU服务脚本，尝试启动...');
        }
        
        final started = await startLocalMineruService(
          onProgress: onProgress,
          onError: onError
        );
        
        if (started) {
          return true;
        } else {
          if (onProgress != null) {
            onProgress('通过本地脚本启动失败，尝试安装MinerU服务环境...');
          }
        }
      } else {
      if (onProgress != null) {
          onProgress('未发现本地MinerU服务脚本，将安装MinerU服务环境...');
        }
      }
      
      // 安装MinerU服务环境
      final installed = await installMineruEnvironment(
        onProgress: onProgress,
        onError: onError
      );
      
      if (!installed) {
        final errorMsg = '无法安装MinerU服务环境';
        Logger.e(errorMsg);
        if (onError != null) {
          onError(errorMsg);
        }
        return false;
      }
      
      // 安装成功后启动服务
      final started = await startLocalMineruService(
        onProgress: onProgress,
        onError: onError
      );
      
      if (!started) {
        final errorMsg = '无法启动本地MinerU服务';
          Logger.e(errorMsg);
          if (onError != null) {
            onError(errorMsg);
          }
          return false;
        }
        
          return true;
    } catch (e) {
      final errorMsg = '启动MinerU服务时出错: $e\n'
          '可能原因：\n'
          '1. 系统缺少必要组件\n'
          '2. MinerU服务未正确安装\n'
          '3. 权限不足，无法启动服务';
      
      Logger.e(errorMsg);
      if (onError != null) {
        onError(errorMsg);
      }
      return false;
    }
  }
}