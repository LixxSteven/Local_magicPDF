import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

enum ConversionType {
  markdown,
  docx,
  html
}

class MineruService {
  // 默认MinerU API地址，用户可能需要根据实际情况修改
  final String baseUrl;
  
  MineruService({this.baseUrl = 'http://localhost:8000'});
  
  /// 将PDF文件转换为指定格式
  Future<String> convertPdf(File pdfFile, ConversionType type) async {
    try {
      // 准备请求URL
      final endpoint = _getEndpointForType(type);
      final url = Uri.parse('$baseUrl$endpoint');
      
      // 创建multipart请求
      var request = http.MultipartRequest('POST', url);
      
      // 添加PDF文件
      request.files.add(await http.MultipartFile.fromPath(
        'file', 
        pdfFile.path,
        filename: path.basename(pdfFile.path)
      ));
      
      // 发送请求
      final response = await request.send();
      
      // 检查响应状态
      if (response.statusCode == 200) {
        // 读取响应内容
        final responseData = await response.stream.bytesToString();
        final jsonData = json.decode(responseData);
        
        // 根据API返回格式提取结果
        // 注意：这里的返回格式可能需要根据实际MinerU API调整
        return jsonData['result'] ?? responseData;
      } else {
        throw Exception('转换失败: ${response.statusCode} - ${response.reasonPhrase}');
      }
    } catch (e) {
      throw Exception('PDF转换过程中出错: $e');
    }
  }
  
  /// 根据转换类型获取对应的API端点
  String _getEndpointForType(ConversionType type) {
    switch (type) {
      case ConversionType.markdown:
        return '/api/pdf2md';
      case ConversionType.docx:
        return '/api/pdf2docx';
      case ConversionType.html:
        return '/api/pdf2html';
    }
  }
  
  /// 保存转换结果到文件
  Future<File> saveConversionResult(String content, String outputPath) async {
    try {
      final file = File(outputPath);
      return await file.writeAsString(content);
    } catch (e) {
      throw Exception('保存转换结果时出错: $e');
    }
  }
}