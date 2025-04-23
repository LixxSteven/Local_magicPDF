import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'services/mineru_service.dart';

void main() {
  runApp(const MyApp());
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
  
  @override
  void initState() {
    super.initState();
    // 应用启动时检查服务状态
    _checkServiceStatus();
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
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('MinerU服务需要正确配置Conda环境才能运行。请按照以下步骤进行配置：', 
                style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text('1. 安装Conda环境', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('   - 下载并安装Miniconda或Anaconda'),
              Text('   - 确保conda命令可在命令行中使用'),
              SizedBox(height: 12),
              Text('2. 创建MinerU专用环境', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: EdgeInsets.all(8),
                color: Colors.grey.shade100,
                child: SelectableText('conda create -n mineru_env python=3.9'),
              ),
              SizedBox(height: 12),
              Text('3. 激活环境并安装依赖', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: EdgeInsets.all(8),
                color: Colors.grey.shade100,
                child: SelectableText(
                  'conda activate mineru_env\n'
                  'pip install uvicorn fastapi python-multipart\n'
                  'pip install mineru  # 或按MinerU官方文档安装'
                ),
              ),
              SizedBox(height: 12),
              Text('4. 确认MinerU安装位置', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('   - 默认路径: MinerU\\MinerU\\projects\\web_api'),
              Text('   - 如需修改路径，请编辑应用程序配置文件'),
              SizedBox(height: 12),
              Text('5. 常见问题排查', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('   • "Process is detached"错误: conda环境未正确激活'),
              Text('   • 端口占用: 确保8888端口未被其他应用占用'),
              Text('   • 路径错误: 确认MinerU安装路径是否正确'),
              SizedBox(height: 16),
              Text('更多信息请参考MinerU官方文档。', style: TextStyle(fontStyle: FontStyle.italic)),
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

  // 启动MinerU服务
  Future<void> _startMineruService() async {
    setState(() {
      _statusMessage = 'MinerU服务启动中...';
      _errorMessage = null; // 清除之前的错误信息
    });
    
    final result = await _mineruService.startMineruService(
      onError: (String errorMsg) {
        setState(() {
          // 显示详细错误信息
          _errorMessage = '启动MinerU服务失败: $errorMsg';
          _isServiceRunning = false; // 更新服务状态
        });
      }
    );
    
    // 更新服务状态
    await _checkServiceStatus();
    
    setState(() {
      if (result) {
        _statusMessage = 'MinerU服务已成功启动';
        _errorMessage = null;
      } else {
        // 如果onError回调没有设置错误信息，则显示一般性错误
        _errorMessage ??= 'MinerU服务启动失败，请检查conda环境配置和MinerU安装';
      }
    });
    
    // 启动定期检查服务状态的定时器
    if (result) {
      // 每30秒检查一次服务状态
      Future.delayed(Duration(seconds: 30), () {
        if (mounted) {
          _checkServiceStatus();
        }
      });
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