import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:path/path.dart' as path;
// import 'package:path_provider/path_provider.dart'; // Removed unused import
// import 'package:url_launcher/url_launcher.dart'; // 暂时注释掉，如果需要打开文件再启用
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
  final MineruService _mineruService = MineruService();
  File? _selectedFile;
  String? _selectedOutputDir;
  // ConversionType _conversionType = ConversionType.markdown; // 默认且唯一选项
  bool _isConverting = false;
  String? _conversionResultPreview; // 用于显示部分结果
  String? _errorMessage;
  String? _statusMessage;
  final List<ConversionHistoryItem> _history = [];

  // 选择PDF文件
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _conversionResultPreview = null;
          _errorMessage = null;
          _statusMessage = '已选择文件: ${path.basename(_selectedFile!.path)}';
          // _outputPath = null; // 输出路径由用户选择或默认
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

  // 选择输出目录
  Future<void> _pickOutputDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        setState(() {
          _selectedOutputDir = selectedDirectory;
          _statusMessage = '输出目录已选择: $_selectedOutputDir';
        });
      } else {
         setState(() {
          _statusMessage = '未选择输出目录';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '选择输出目录时出错: $e';
         _statusMessage = null;
      });
    }
  }

  // 转换PDF文件
  Future<void> _convertFile() async {
    if (_selectedFile == null) {
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
      _conversionResultPreview = null;
      _statusMessage = '正在转换...';
    });

    try {
      // 获取文件扩展名 (固定为md)
      const String extension = 'md';

      // 转换文件 (固定为Markdown)
      final result = await _mineruService.convertPdf(_selectedFile!, ConversionType.markdown);

      // 确定输出文件路径
      final fileName = path.basenameWithoutExtension(_selectedFile!.path);
      final outputFile = File(path.join(_selectedOutputDir!, '$fileName.$extension'));

      // 保存结果
      await _mineruService.saveConversionResult(result, outputFile.path);

      // 更新历史记录
      final historyItem = ConversionHistoryItem(
        inputPath: _selectedFile!.path,
        outputPath: outputFile.path,
        timestamp: DateTime.now(),
      );

      setState(() {
        _conversionResultPreview = result.length > 500 ? '${result.substring(0, 500)}...' : result; // 显示部分预览
        _statusMessage = '转换完成，文件已保存至: ${outputFile.path}';
        _history.insert(0, historyItem); // 添加到历史记录顶部
        // _outputPath = outputFile.path; // 不再需要单独存储，从历史记录获取
      });

    } catch (e) {
      setState(() {
        _errorMessage = '转换过程中出错: $e';
        _statusMessage = '转换失败';
      });
    } finally {
      setState(() {
        _isConverting = false;
      });
    }
  }

  // // 打开转换后的文件 (暂时禁用，如果需要可以取消注释并添加url_launcher依赖)
  // Future<void> _openOutputFile(String outputPath) async {
  //   if (outputPath.isNotEmpty) {
  //     final uri = Uri.file(outputPath);
  //     try {
  //       if (await canLaunchUrl(uri)) {
  //         await launchUrl(uri);
  //       } else {
  //         setState(() {
  //           _errorMessage = '无法打开文件: $outputPath';
  //         });
  //       }
  //     } catch (e) {
  //        setState(() {
  //           _errorMessage = '打开文件时出错: $e';
  //         });
  //     }
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // 让子项水平填充
          children: [
            // --- 文件选择与输出目录 --- 
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1. 选择文件和输出目录',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('选择PDF'),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            _selectedFile != null
                                ? path.basename(_selectedFile!.path)
                                : '未选择文件',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                     Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickOutputDirectory,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('选择输出目录'),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            _selectedOutputDir ?? '未选择输出目录',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- 转换操作 --- 
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     const Text(
                      '2. 开始转换 (PDF -> Markdown)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Center( // 将按钮和加载指示器居中
                      child: _isConverting
                          ? const SpinKitFadingCircle( // 使用加载动画
                              color: Colors.blue,
                              size: 50.0,
                            )
                          : ElevatedButton.icon(
                              onPressed: (_selectedFile != null && _selectedOutputDir != null) ? _convertFile : null, // 仅在选择文件和目录后启用
                              icon: const Icon(Icons.sync_alt),
                              label: const Text('开始转换'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                                textStyle: const TextStyle(fontSize: 16)
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    // 显示状态或错误信息
                    if (_statusMessage != null)
                      Text(_statusMessage!, style: TextStyle(color: _errorMessage != null ? Colors.red : Colors.green)),
                    if (_errorMessage != null)
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- 结果预览 (可选) ---
            if (_conversionResultPreview != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '转换结果预览 (部分)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 100, // 限制预览区域高度
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(_conversionResultPreview!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // --- 转换历史 --- 
            Expanded( // 让历史记录列表填充剩余空间
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '转换历史',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _history.isEmpty
                            ? const Center(child: Text('暂无历史记录'))
                            : ListView.builder(
                                itemCount: _history.length,
                                itemBuilder: (context, index) {
                                  final item = _history[index];
                                  return ListTile(
                                    leading: const Icon(Icons.history),
                                    title: Text('输入: ${path.basename(item.inputPath)}'),
                                    subtitle: Text('输出: ${item.outputPath}\n时间: ${item.timestamp.toLocal()}'),
                                    isThreeLine: true,
                                    // trailing: IconButton( // 如果需要打开文件，可以添加按钮
                                    //   icon: const Icon(Icons.open_in_new),
                                    //   onPressed: () => _openOutputFile(item.outputPath),
                                    // ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
