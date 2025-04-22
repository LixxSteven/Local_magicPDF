import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

enum ConversionType {
  markdown, // 暂时只支持Markdown
  // docx, // MinerU API 目前不直接支持
  // html  // MinerU API 目前不直接支持
}

class MineruService {
  // 默认MinerU API地址，用户可能需要根据实际情况修改
  final String baseUrl;

  MineruService({this.baseUrl = 'http://localhost:8888'}); // 更新端口为 8888

  /// 将PDF文件转换为指定格式 (目前仅支持Markdown)
  Future<String> convertPdf(File pdfFile, ConversionType type) async {
    // 检查是否为支持的类型
    if (type != ConversionType.markdown) {
      throw Exception('当前仅支持转换为Markdown格式');
    }

    try {
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

      // 添加其他参数 (根据需要调整，例如请求返回Markdown内容)
      // 假设API通过某个字段返回Markdown，例如 'return_markdown': 'true'
      // 或者直接在返回的JSON中查找内容
      // request.fields['return_markdown'] = 'true'; // 示例参数
      request.fields['return_content_list'] = 'true'; // 尝试获取内容列表

      // 发送请求
      final response = await request.send();

      // 检查响应状态
      if (response.statusCode == 200) {
        // 读取响应内容
        final responseData = await response.stream.bytesToString();
        final jsonData = json.decode(responseData);

        // 根据API返回格式提取结果
        // *** 重要: 需要根据实际 MinerU /file_parse API 的返回JSON结构调整这里的提取逻辑 ***
        // 假设Markdown内容在 'markdown_content' 字段或类似结构中
        // 这是一个示例，可能需要查看API的实际输出来确定正确的字段
        if (jsonData['content_list'] != null && jsonData['content_list'] is List) {
          // 尝试将 content_list 拼接成 Markdown
          return (jsonData['content_list'] as List).map((item) => item.toString()).join('\n\n');
        } else if (jsonData['result'] != null) {
           return jsonData['result'].toString(); // 备用提取
        } else {
          // 如果找不到特定字段，返回整个JSON字符串供调试
          // throw Exception('无法从API响应中提取Markdown内容: $responseData');
           return responseData; // 返回原始JSON字符串
        }

      } else {
         final errorBody = await response.stream.bytesToString();
        throw Exception('转换失败: ${response.statusCode} - ${response.reasonPhrase} - $errorBody');
      }
    } catch (e) {
      throw Exception('PDF转换过程中出错: $e');
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
}