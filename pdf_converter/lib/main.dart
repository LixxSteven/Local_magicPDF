import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
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
      title: 'PDF转换工具',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PdfConverterPage(title: 'PDF转换工具'),
    );
  }
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
  String? _outputPath;
  ConversionType _conversionType = ConversionType.markdown;
  bool _isConverting = false;
  String? _conversionResult;
  String? _errorMessage;

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
          _conversionResult = null;
          _errorMessage = null;
          _outputPath = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '选择文件时出错: $e';
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

    setState(() {
      _isConverting = true;
      _errorMessage = null;
      _conversionResult = null;
    });

    try {
      // 获取文件扩展名
      String extension;
      switch (_conversionType) {
        case ConversionType.markdown:
          extension = 'md';
          break;
        case ConversionType.docx:
          extension = 'docx';
          break;
        case ConversionType.html:
          extension = 'html';
          break;
      }

      // 转换文件
      final result = await _mineruService.convertPdf(_selectedFile!, _conversionType);
      
      // 保存结果
      final directory = await getApplicationDocumentsDirectory();
      final fileName = path.basenameWithoutExtension(_selectedFile!.path);
      final outputFile = File('${directory.path}/$fileName.$extension');
      
      // 对于docx格式，结果可能是二进制数据，需要特殊处理
      if (_conversionType == ConversionType.docx) {
        // 假设MinerU API返回的是可以直接保存的内容
        await _mineruService.saveConversionResult(result, outputFile.path);
        setState(() {
          _conversionResult = '转换完成，文件已保存至: ${outputFile.path}';
          _outputPath = outputFile.path;
        });
      } else {
        // 对于文本格式，可以显示预览
        await _mineruService.saveConversionResult(result, outputFile.path);
        setState(() {
          _conversionResult = result;
          _outputPath = outputFile.path;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '转换过程中出错: $e';
      });
    } finally {
      setState(() {
        _isConverting = false;
      });
    }
  }

  // 打开转换后的文件
  Future<void> _openOutputFile() async {
    if (_outputPath != null) {
      final uri = Uri.file(_outputPath!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        setState(() {
          _errorMessage = '无法打开文件: $_outputPath';
        });
      }
    }
  }

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件选择区域
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '选择PDF文件',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.file_upload),
                          label: const Text('选择文件'),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 转换选项区域
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '转换选项',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<ConversionType>(
                      decoration: const InputDecoration(
                        labelText: '转换格式',
                        border: OutlineInputBorder(),
                      ),
                      value: _conversionType,
                      items: const [
                        DropdownMenuItem(
                          value: ConversionType.markdown,
                          child: Text('Markdown'),
                        ),
                        DropdownMenuItem(
                          value: ConversionType.docx,
                          child: Text('DOCX'),
                        ),
                        DropdownMenuItem(
                          value: ConversionType.html,
                          child: Text('HTML'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _conversionType = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isConverting ? null : _convertFile,
                        icon: _isConverting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.transform),
                        label: Text(_isConverting ? '转换中...' : '开始转换'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // 错误信息
            if (_errorMessage != null) ...[  
              const SizedBox(height: 16),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            // 转换结果
            if (_conversionResult != null && _outputPath != null) ...[  
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '转换结果',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            TextButton.icon(
                              onPressed: _openOutputFile,
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('打开文件'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _conversionType == ConversionType.docx
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.description, size: 48),
                                      const SizedBox(height: 16),
                                      Text('文件已保存至: ${path.basename(_outputPath!)}'),
                                      const SizedBox(height: 8),
                                      ElevatedButton(
                                        onPressed: _openOutputFile,
                                        child: const Text('打开文件'),
                                      ),
                                    ],
                                  ),
                                )
                              : SingleChildScrollView(
                                  child: Text(_conversionResult!),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            
            // 加载指示器
            if (_isConverting) ...[  
              const SizedBox(height: 16),
              const Center(
                child: Column(
                  children: [
                    SpinKitWave(
                      color: Colors.blue,
                      size: 30.0,
                    ),
                    SizedBox(height: 16),
                    Text('正在转换，请稍候...'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
