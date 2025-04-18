import 'dart:io';
import 'dart:convert'; // 如果需要指定编码

// 重要提示：在运行此脚本前请务必备份您的代码仓库！
// 此脚本会就地修改文件。

void main(List<String> arguments) {
  if (arguments.length != 1) {
    print('用法: remove_java_comments <repository_path>');
    print('示例: remove_java_comments /path/to/your/java/project');
    exit(1);
  }

  final repoPath = arguments[0];
  final directory = Directory(repoPath);

  if (!directory.existsSync()) {
    print('错误: 目录未找到: $repoPath');
    exit(1);
  }

  print('开始在目录中移除注释 (保留 formatter 指令): $repoPath');
  print('---');

  int filesProcessed = 0;
  int filesModified = 0;

  try {
    // 递归查找所有文件
    directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>() // 只保留 File 对象
        .where((file) => file.path.toLowerCase().endsWith('.java')) // 筛选出 .java 文件
        .forEach((file) {
      filesProcessed++;
      print('正在处理: ${file.path}');
      try {
        // 明确使用 UTF-8 读写，避免编码问题
        String originalContent = file.readAsStringSync(encoding: utf8);
        String modifiedContent = removeComments(originalContent);

        // 仅当内容实际发生更改时才写回文件
        if (originalContent != modifiedContent) {
          file.writeAsStringSync(modifiedContent, encoding: utf8);
          print('  -> 注释已移除 (保留 formatter 指令)。');
          filesModified++;
        } else {
          print('  -> 未找到可移除的注释或无需更改。');
        }
      } catch (e) {
        print('  -> 处理文件 ${file.path} 时出错: $e');
        // exit(1); // 取消注释可以在遇到第一个错误时停止脚本
      }
    });

    print('---');
    print('处理完成。');
    print('共找到 .java 文件: $filesProcessed');
    print('已修改文件数: $filesModified');

  } on FileSystemException catch (e) {
    print('\n访问文件系统时出错: $e');
    exit(1);
  } catch (e) {
    print('\n发生意外错误: $e');
    exit(1);
  }
}

/// 从字符串中移除 Java 风格的注释。
/// 处理单行注释 (//) 和多行注释 (/* */)。
/// 尝试保留字符串和字符字面量中的注释（或类似注释的模式）。
/// 特别保留 // @formatter:off 和 // @formatter:on 注释。
String removeComments(String code) {
  // 正则表达式解释 (保持不变):
  // "(\\.|[^"\\])*"          : 匹配字符串字面量。处理转义引号 \"
  // '(\\.|[^'\\])*'          : 匹配字符字面量。处理转义引号 \'
  // //[^\n\r]*               : 匹配到行尾的单行注释 (直到行结束符)
  // /\*(?:[^*]|\*+[^*/])*\*+/: 匹配多行注释的更健壮模式

  final commentRegex = RegExp(
      r'("(\\.|[^"\\])*")'              // 分组 1 & 2: 字符串字面量
      r"|('(\\.|[^'\\])*')"              // 分组 3 & 4: 字符字面量
      r'|(//[^\n\r]*)'                   // 分组 5: 单行注释 (直到行尾)
      r'|(/\*(?:[^*]|\*+[^*/])*\*+/)'    // 分组 6: 多行注释 (更健壮的模式)
      , multiLine: true // 启用多行模式
  );

  // 使用 replaceAllMapped 来根据匹配到的内容决定替换为什么
  String result = code.replaceAllMapped(commentRegex, (match) {
    if (match.group(5) != null) {
      // 匹配到了单行注释 (//...)
      String singleLineComment = match.group(5)!; // 获取完整的单行注释文本

      // 检查是否是需要保留的 formatter 指令 (去除前后空格后判断)
      String trimmedComment = singleLineComment.trim();
      if (trimmedComment == "// @formatter:off" || trimmedComment == "// @formatter:on") {
        return singleLineComment; // 保留这个 formatter 指令
      } else {
        return ''; // 移除其他所有单行注释
      }
    } else if (match.group(6) != null) {
      // 匹配到了多行注释 (/*...*/)
      return ''; // 移除多行注释
    } else {
      // 匹配到了字符串或字符字面量 (分组 1 或 3)
      return match.group(0)!; // 保持原始的字符串/字符字面量不变
    }
  });

  // 可选：清理因移除注释而可能产生的过多空行
  // 1. 移除完全是空白的行 (^\s+$) - 注释掉，以防误删 formatter 指令所在的空行
  // result = result.replaceAll(RegExp(r'^\s+$', multiLine: true), '');

  // 2. 将多个连续的空行压缩为单个空行 (保留 formatter 指令之间的空行)
  //    替换3个或更多换行符为2个，这通常比较安全。
  result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  // 3. 移除文件开头可能留下的多余空行
  result = result.trimLeft();
  // 4. 移除文件末尾可能留下的多余空白（包括换行符）
  result = result.trimRight();
  // 如果希望确保文件末尾总是有且只有一个换行符:
  // if (result.isNotEmpty && !result.endsWith('\n')) { // 检查是否为空且是否已存在换行符
  //  result += '\n';
  // }

  return result;
}
