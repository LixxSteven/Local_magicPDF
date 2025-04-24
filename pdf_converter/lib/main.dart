import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:async';
import 'services/mineru_service.dart';
import 'utils/logger.dart';

void main() async {
  // 捕获未处理的异常，防止应用崩溃
  runZonedGuarded(() async {
    try {
      // 确保Flutter绑定初始化
      WidgetsFlutterBinding.ensureInitialized();
      
      // 初始化日志系统
      await Logger.init(
        level: LogLevel.debug,
        enableFileLogging: true,
        logDir: path.join(Directory.current.path, 'logs'),
      );
      
      Logger.i('应用启动');
      
      // 设置错误处理
      FlutterError.onError = (FlutterErrorDetails details) {
        Logger.e('Flutter错误: ${details.exception}');
        Logger.e('堆栈跟踪: ${details.stack}');
        FlutterError.presentError(details);
      };
      
      runApp(const MyApp());
    } catch (e, stackTrace) {
      Logger.e('启动时发生错误: $e');
      Logger.e('$stackTrace');
      
      // 尝试初始化简单日志
      try {
        final logDir = path.join(Directory.current.path, 'logs');
        await Directory(logDir).create(recursive: true);
        final logFile = File(path.join(logDir, 'crash_${DateTime.now().millisecondsSinceEpoch}.log'));
        await logFile.writeAsString('启动时发生错误: $e\n$stackTrace');
      } catch (_) {
        // 忽略日志错误
      }
      
      // 显示错误UI
      runApp(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 64),
                  SizedBox(height: 16),
                  Text('应用启动时发生错误', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('$e', style: TextStyle(color: Colors.red)),
                  SizedBox(height: 16),
                  Text('请尝试以管理员身份重新启动应用', style: TextStyle(fontSize: 16)),
                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => exit(0),
                    child: Text('关闭应用'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }
  }, (error, stackTrace) {
    // 处理未捕获的异步错误
    Logger.e('未捕获的错误: $error');
    Logger.e('$stackTrace');
    
    // 尝试记录到文件
    try {
      final logDir = path.join(Directory.current.path, 'logs');
      final logFile = File(path.join(logDir, 'uncaught_${DateTime.now().millisecondsSinceEpoch}.log'));
      logFile.writeAsStringSync('未捕获的错误: $error\n$stackTrace');
    } catch (_) {
      // 忽略日志错误
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF 转换工具',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PdfConverterPage(title: 'PDF 转换工具'),
    );
  }
}

// 定义转换历史记录项
class ConversionHistoryItem {
  final String inputPath;
  final String outputPath;
  final DateTime timestamp;

  ConversionHistoryItem({
    required this.inputPath,
    required this.outputPath,
    required this.timestamp,
  });
}

class PdfConverterPage extends StatefulWidget {
  const PdfConverterPage({super.key, required this.title});

  final String title;

  @override
  State<PdfConverterPage> createState() => _PdfConverterPageState();
}

class _PdfConverterPageState extends State<PdfConverterPage> {
  // MinerU服务状态
  bool _isServiceRunning = false;
  final MineruService _mineruService = MineruService();
  String? _selectedOutputDir;
  bool _isConverting = false;
  String? _errorMessage;
  String? _statusMessage;
  final List<ConversionHistoryItem> _history = [];
  List<File> _selectedFiles = [];
  final Map<String, double> _fileProgress = {};
  final Map<String, String?> _fileStatus = {};
  final Map<String, String?> _filePreview = {};
  final Map<String, int> _estimatedTimes = {}; // 存储每个文件的预估转换时间（秒）
  final Map<String, DateTime> _startTimes = {}; // 存储每个文件开始转换的时间
  
  @override
  void initState() {
    super.initState();
    // 应用启动时检查服务状态
    _checkServiceStatus();
    
    // 记录当前工作目录，便于调试
    Logger.i('当前工作目录: ${Directory.current.path}');
  }
  
  // 检查MinerU服务状态
  Future<void> _checkServiceStatus() async {
    final isAvailable = await _mineruService.checkServiceAvailability();
    setState(() {
      _isServiceRunning = isAvailable;
    });
  }
  
  // 显示MinerU服务配置帮助对话框
  void _showMineruSetupHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('MinerU服务配置指南'),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '本应用现已支持自动配置MinerU服务环境。点击"启动MinerU服务"按钮即可自动检测和配置所需环境。',
                          style: TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                _buildSetupStep(
                  '1',
                  '安装Conda环境',
                  [
                    '• 下载并安装Miniconda或Anaconda',
                    '• Windows用户: 从官方网站下载安装包并运行',
                    '• 安装时勾选"添加到PATH"选项',
                    '• 安装完成后重启终端或命令提示符',
                    '• 验证安装: 在命令行中输入 conda --version'
                  ],
                  'https://docs.conda.io/en/latest/miniconda.html',
                  '下载Miniconda'
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // 构建设置步骤UI组件
  Widget _buildSetupStep(String stepNumber, String title, List<String> steps, String linkUrl, String linkText) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(26),
            spreadRadius: 1,
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      stepNumber,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...steps.map((step) => Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(step),
                    )),
                SizedBox(height: 8),
                if (linkUrl.isNotEmpty && linkText.isNotEmpty)
                  TextButton.icon(
                    icon: Icon(Icons.open_in_new, size: 16),
                    label: Text(linkText),
                    onPressed: () async {
                      // 这里可以添加打开URL的逻辑
                      // 例如使用url_launcher包
                      // await launch(linkUrl);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // 启动MinerU服务
  Future<void> _startMineruService() async {
    try {
      // 显示进度对话框
      showDialog(
        context: context,
        barrierDismissible: false, // 用户不能通过点击外部关闭对话框
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.blue),
                    SizedBox(width: 10),
                    Text('MinerU服务配置与启动'),
                  ],
                ),
                content: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                      SizedBox(height: 20),
                      Text('正在启动MinerU服务...', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      Container(
                        height: 150,
                        width: 400,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        padding: EdgeInsets.all(8),
                        child: SingleChildScrollView(
                          child: Text(_statusMessage ?? '准备启动MinerU服务...'),
                        ),
                      ),
                      SizedBox(height: 10),
                      ExpansionTile(
                        title: Text('环境配置清单', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('基础环境:', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('• Python 3.9 (Conda环境)'),
                                SizedBox(height: 8),
                                Text('核心依赖:', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('• API服务: uvicorn, fastapi, python-multipart'),
                                Text('• PDF解析: PyMuPDF, pdfminer.six'),
                                Text('• 语言检测: fast-langdetect'),
                                Text('• 工具库: numpy, boto3, loguru'),
                                Text('• 机器学习: torch, torchvision, transformers'),
                                SizedBox(height: 8),
                                Text('系统要求:', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('• Windows 10/11'),
                                Text('• 至少16GB内存（推荐32GB）'),
                                Text('• 至少20GB可用磁盘空间'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      ExpansionTile(
                        title: Text('安装进度参考', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('1. 创建应用程序数据目录 (✓)', style: TextStyle(
                                  decoration: _statusMessage?.contains('创建应用程序数据目录') == true 
                                      ? TextDecoration.lineThrough : TextDecoration.none
                                )),
                                Text('2. 检查Conda是否已安装 (✓)', style: TextStyle(
                                  decoration: _statusMessage?.contains('检测到现有Conda安装') == true 
                                      ? TextDecoration.lineThrough : TextDecoration.none
                                )),
                                Text('3. 下载并安装Miniconda (可能需要几分钟)', style: TextStyle(
                                  decoration: _statusMessage?.contains('Miniconda安装成功') == true 
                                      ? TextDecoration.lineThrough : TextDecoration.none
                                )),
                                Text('4. 创建MinerU环境 (Python 3.9)', style: TextStyle(
                                  decoration: _statusMessage?.contains('MinerU环境创建成功') == true 
                                      ? TextDecoration.lineThrough : TextDecoration.none
                                )),
                                Text('5. 安装基础依赖 (可能需要几分钟)', style: TextStyle(
                                  decoration: _statusMessage?.contains('正在安装PDF解析所需的高级依赖') == true 
                                      ? TextDecoration.lineThrough : TextDecoration.none
                                )),
                                Text('6. 安装PDF解析高级依赖 (可能需要10-20分钟)', style: TextStyle(
                                  decoration: _statusMessage?.contains('MinerU依赖安装成功') == true 
                                      ? TextDecoration.lineThrough : TextDecoration.none
                                )),
                                Text('7. 配置MinerU源代码'),
                                Text('8. 创建启动脚本'),
                                Text('9. 启动MinerU服务'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text('取消'),
                  ),
                ],
              );
            },
          );
        },
      );

      setState(() {
        _statusMessage = '正在启动MinerU服务...';
        _errorMessage = null; // 清除之前的错误信息
      });
      
      // 使用修改后的startMineruService方法，添加进度回调
      final result = await _mineruService.startMineruService(
        onError: (String errorMsg) {
          setState(() {
            // 显示详细错误信息
            _errorMessage = '启动MinerU服务失败: $errorMsg';
            _isServiceRunning = false; // 更新服务状态
          });
          // 关闭进度对话框
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            
            // 显示错误对话框
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red),
                    SizedBox(width: 10),
                    Text('MinerU服务启动失败'),
                  ],
                ),
                content: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('启动MinerU服务时遇到以下错误：', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      Container(
                        height: 200,
                        width: 480,
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        padding: EdgeInsets.all(8),
                        child: SingleChildScrollView(
                          child: Text(errorMsg, style: TextStyle(color: Colors.red[800])),
                        ),
                      ),
                      SizedBox(height: 10),
                      ExpansionTile(
                        title: Text('常见问题解决方案', style: TextStyle(fontWeight: FontWeight.bold)),
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber[50],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('1. 以管理员身份运行', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('   右键点击应用图标，选择"以管理员身份运行"'),
                                SizedBox(height: 5),
                                Text('2. 检查网络连接', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('   安装过程需要从互联网下载组件'),
                                SizedBox(height: 5),
                                Text('3. 检查磁盘空间', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('   确保C盘至少有20GB可用空间'),
                                SizedBox(height: 5),
                                Text('4. 暂时禁用杀毒软件', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('   部分杀毒软件可能阻止安装过程'),
                                SizedBox(height: 5),
                                Text('5. 检查路径中是否有特殊字符', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('   应用路径中应避免中文或特殊字符'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text('关闭'),
                  ),
                  TextButton(
                    onPressed: _showMineruSetupHelp,
                    child: Text('查看配置指南'),
                  ),
                ],
              ),
            );
          }
        },
        onProgress: (String progressMsg) {
          if (mounted) {
            setState(() {
              _statusMessage = progressMsg;
            });
          }
        }
      );
      
      // 更新服务状态
      await _checkServiceStatus();
      
      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        
        setState(() {
          if (result) {
            _statusMessage = 'MinerU服务已成功启动';
            _errorMessage = null;
            
            // 显示成功对话框
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 10),
                      Text('MinerU服务启动成功'),
                    ],
                  ),
                  content: Text('MinerU服务已成功启动，现在您可以开始转换PDF文件了。'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text('确定'),
                    ),
                  ],
                ),
              );
            }
          } else {
            // 如果onError回调没有设置错误信息，则显示一般性错误
            _errorMessage ??= 'MinerU服务启动失败，请检查conda环境配置和MinerU安装';
          }
        });
      }
      
      // 启动定期检查服务状态的定时器
      if (result) {
        // 每30秒检查一次服务状态
        Future.delayed(Duration(seconds: 30), () {
          if (mounted) {
            _checkServiceStatus();
          }
        });
      }
    } catch (e) {
      // 处理UI异常，防止黑屏
      Logger.e('UI异常: $e');
      if (mounted) {
        // 关闭可能打开的对话框
        Navigator.of(context, rootNavigator: true).pop();
        
        // 显示友好的错误信息
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 10),
                Text('应用发生错误'),
              ],
            ),
            content: Text('应用发生未知错误: $e\n\n请尝试重启应用'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  // 选择输出目录
  Future<void> _pickOutputDirectory() async {
    String? selectedDir = await FilePicker.platform.getDirectoryPath();
    if (selectedDir != null) {
      setState(() {
        _selectedOutputDir = selectedDir;
        _errorMessage = null;
        _statusMessage = '已选择输出目录: ${path.basename(selectedDir)}';
      });
    }
  }

  // 批量选择PDF文件
  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );
      if (result != null) {
        setState(() {
          _selectedFiles = result.paths.whereType<String>().map((p) => File(p)).toList();
          _fileProgress.clear();
          _fileStatus.clear();
          _filePreview.clear();
          _errorMessage = null;
          _statusMessage = '已选择${_selectedFiles.length}个文件';
        });
      } else {
        setState(() {
          _statusMessage = '未选择文件';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '选择文件时出错: $e';
        _statusMessage = null;
      });
    }
  }

  // 批量转换PDF文件
  Future<void> _convertFiles() async {
    if (_selectedFiles.isEmpty) {
      setState(() {
        _errorMessage = '请先选择PDF文件';
      });
      return;
    }
    if (_selectedOutputDir == null) {
      setState(() {
        _errorMessage = '请先选择输出目录';
      });
      return;
    }
    setState(() {
      _isConverting = true;
      _errorMessage = null;
      _statusMessage = '正在批量转换...';
    });
    for (int i = 0; i < _selectedFiles.length; i++) {
      final file = _selectedFiles[i];
      setState(() {
        _fileStatus[file.path] = '转换中';
        _startTimes[file.path] = DateTime.now(); // 记录开始时间
      });
      try {
        // 获取预估转换时间
        final fileSize = await file.length();
        final estimatedTimeInSeconds = (fileSize / 1024 / 1024 * 2).round(); // 假设每MB需要2秒钟
        setState(() {
          _estimatedTimes[file.path] = estimatedTimeInSeconds;
        });
        
        final result = await _mineruService.convertPdf(file, ConversionType.markdown, (currentPage, totalPages) {
          setState(() {
            _fileProgress[file.path] = totalPages > 0 ? currentPage / totalPages : 0.0;
          });
        });
        final fileName = path.basenameWithoutExtension(file.path);
        final outputFile = File(path.join(_selectedOutputDir!, '$fileName.md'));
        await _mineruService.saveConversionResult(result, outputFile.path);
        setState(() {
          _fileStatus[file.path] = '转换完成';
          _filePreview[file.path] = result.length > 500 ? '${result.substring(0, 500)}...' : result;
          _history.insert(0, ConversionHistoryItem(
            inputPath: file.path,
            outputPath: outputFile.path,
            timestamp: DateTime.now(),
          ));
        });
      } catch (e) {
        setState(() {
          _fileStatus[file.path] = '转换失败: $e';
        });
      }
    }
    setState(() {
      _isConverting = false;
      _statusMessage = '批量转换完成';
    });
  }

  Widget _buildBatchFileList() {
    return Expanded(
      child: ListView.builder(
        itemCount: _selectedFiles.length,
        itemBuilder: (context, index) {
          final file = _selectedFiles[index];
          final progress = _fileProgress[file.path] ?? 0.0;
          final status = _fileStatus[file.path] ?? '';
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: ListTile(
              leading: Icon(Icons.picture_as_pdf, color: Colors.red),
              title: Text(path.basename(file.path)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: progress),
                  Row(
                    children: [
                      Text('状态: $status'),
                      if (progress > 0 && progress < 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('进度: ${(progress * 100).toStringAsFixed(1)}%'),
                        ),
                    ],
                  ),
                  // 显示预估时间信息
                  if (_estimatedTimes.containsKey(file.path) && progress > 0 && progress < 1) 
                    Row(
                      children: [
                        Icon(Icons.timer, size: 14),
                        SizedBox(width: 4),
                        Text('预估总时间: ${_estimatedTimes[file.path]}秒'),
                        SizedBox(width: 8),
                        if (_startTimes.containsKey(file.path)) 
                          Text('已用时间: ${DateTime.now().difference(_startTimes[file.path]!).inSeconds}秒'),
                        SizedBox(width: 8),
                        if (progress > 0)
                          Text('预计剩余: ${((1 - progress) * _estimatedTimes[file.path]!).round()}秒'),
                      ],
                    ),
                ],
              ),
              trailing: IconButton(
                icon: Icon(Icons.compare_arrows),
                tooltip: '对比原文与转换后',
                onPressed: _filePreview[file.path] != null
                    ? () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('对比: ${path.basename(file.path)}'),
                            content: SizedBox(
                              width: 800,
                              height: 500,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('原文（PDF预览）', style: TextStyle(fontWeight: FontWeight.bold)),
                                        Expanded(
                                          child: SingleChildScrollView(
                                            child: Text('（此处可集成PDF预览控件）'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  VerticalDivider(),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('转换后（Markdown预览）', style: TextStyle(fontWeight: FontWeight.bold)),
                                        Expanded(
                                          child: SingleChildScrollView(
                                            child: Text(_filePreview[file.path] ?? ''),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      }
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey[50],
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    icon: Icon(Icons.upload_file),
                    label: Text('批量选择PDF'),
                    onPressed: _isConverting ? null : _pickFiles,
                  ),
                  SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: Icon(Icons.folder_open),
                    label: Text('选择输出目录'),
                    onPressed: _isConverting ? null : _pickOutputDirectory,
                  ),
                  SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: Icon(Icons.play_arrow),
                    label: Text('批量转换'),
                    onPressed: _isConverting ? null : _convertFiles,
                  ),
                  SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: Icon(Icons.power_settings_new),
                    label: Text('启动MinerU服务'),
                    onPressed: _startMineruService,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  // 服务状态指示器
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isServiceRunning ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isServiceRunning ? Colors.green.shade200 : Colors.red.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isServiceRunning ? Icons.check_circle : Icons.error_outline,
                          color: _isServiceRunning ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          _isServiceRunning ? 'MinerU服务运行中' : 'MinerU服务未运行',
                          style: TextStyle(
                            color: _isServiceRunning ? Colors.green.shade700 : Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  if (_statusMessage != null)
                    Text(_statusMessage!, style: TextStyle(color: Colors.blue)),
                ],
              ),
            ),
            _buildBatchFileList(),
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.all(8.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text('错误信息', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        Spacer(),
                        if (_errorMessage != null && _errorMessage!.contains('MinerU服务'))
                          TextButton.icon(
                            icon: Icon(Icons.help_outline),
                            label: Text('配置帮助'),
                            onPressed: _showMineruSetupHelp,
                          ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(_errorMessage!, style: TextStyle(color: Colors.red.shade800)),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('转换历史', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ..._history.map((item) => ListTile(
                        leading: Icon(Icons.history),
                        title: Text(path.basename(item.inputPath)),
                        subtitle: Text('输出: ${item.outputPath}\n时间: ${item.timestamp}'),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}