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
  Future<String> convertPdf(File pdfFile, ConversionType type, Function(int, int) onProgress) async {
    // 检查是否为支持的类型
    if (type != ConversionType.markdown) {
      throw Exception('当前仅支持转换为Markdown格式');
    }

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

        // 添加其他参数
        request.fields['return_content_list'] = 'true'; // 尝试获取内容列表
        
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
          if (jsonData['content_list'] != null && jsonData['content_list'] is List) {
            // 尝试将 content_list 拼接成 Markdown
            result = (jsonData['content_list'] as List).map((item) => item.toString()).join('\n\n');
          } else if (jsonData['result'] != null) {
            result = jsonData['result'].toString(); // 备用提取
          } else {
            // 如果找不到特定字段，返回整个JSON字符串供调试
            result = responseData; // 返回原始JSON字符串
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
  
  /// 启动MinerU服务
  /// 返回值: 成功启动返回true，失败返回false
  /// 错误信息: 通过errorMessage参数返回详细错误信息
  Future<bool> startMineruService({Function(String)? onError}) async {
    try {
      // 检查服务是否已经在运行
      if (await checkServiceAvailability()) {
        Logger.i('MinerU服务已经在运行');
        return true;
      }
      
      // 获取MinerU服务路径 - 假设在项目根目录的MinerU文件夹中
      final String mineruPath = Platform.isWindows
          ? 'MinerU\\MinerU\\projects\\web_api'
          : 'MinerU/MinerU/projects/web_api';
      
      // 构建启动命令，包含conda环境激活
      final String command = Platform.isWindows
          ? 'powershell'
          : 'bash';
      
      // 使用conda激活环境后启动服务
      final List<String> arguments = Platform.isWindows
          ? [
              '-Command', 
              '''
              try {
                # 激活conda环境
                conda activate mineru_env 2>&1
                if (\$?) {
                  # 切换到MinerU目录并启动服务
                  cd "$mineruPath"
                  if (\$?) {
                    # 启动服务
                    uvicorn app:app --host 0.0.0.0 --port 8888
                  } else {
                    Write-Error "无法切换到MinerU目录，请确保MinerU已正确安装"
                    exit 1
                  }
                } else {
                  Write-Error "无法激活conda环境'mineru_env'，请确保已正确安装并配置conda环境"
                  exit 1
                }
              } catch {
                Write-Error "启动MinerU服务时出错: \$(\$_.Exception.Message)"
                exit 1
              }
              '''
            ]
          : [
              '-c', 
              '''
              # 激活conda环境
              source \$(conda info --base)/etc/profile.d/conda.sh && 
              conda activate mineru_env && 
              cd "$mineruPath" && 
              uvicorn app:app --host 0.0.0.0 --port 8888
              '''
            ];
      
      // 启动进程，使用inheritStdio模式以便捕获输出
      final process = await Process.start(
        command,
        arguments,
        mode: ProcessStartMode.inheritStdio,
      );
      
      // 收集错误输出
      List<String> errorLines = [];
      process.stderr.transform(utf8.decoder).listen((data) {
        errorLines.add(data);
        Logger.e('MinerU服务错误: $data');
        if (onError != null) {
          onError(data);
        }
      });
      
      // 收集标准输出以便调试
      process.stdout.transform(utf8.decoder).listen((data) {
        Logger.i('MinerU服务输出: $data');
      });
      
      // 等待服务启动
      for (int i = 0; i < 10; i++) { // 增加等待时间
        await Future.delayed(Duration(seconds: 2));
        if (await checkServiceAvailability()) {
          Logger.i('MinerU服务已成功启动');
          return true;
        }
      }
      
      // 如果超时，尝试终止进程
      try {
        process.kill();
      } catch (e) {
        Logger.w('无法终止MinerU进程: $e');
      }
      
      // 返回详细错误信息
      final errorMsg = '服务启动超时。可能原因：\n'
          '1. conda环境未正确配置\n'
          '2. MinerU服务路径不正确\n'
          '3. 端口8888已被占用\n'
          '详细错误: ${errorLines.join('\n')}';
      
      Logger.w(errorMsg);
      if (onError != null) {
        onError(errorMsg);
      }
      return false;
    } catch (e) {
      final errorMsg = '启动MinerU服务时出错: $e\n'
          '可能原因：\n'
          '1. 系统缺少必要组件(如conda、Python)\n'
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