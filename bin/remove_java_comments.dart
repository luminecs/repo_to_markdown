import 'dart:io';
import 'dart:convert'; // 明确使用 UTF-8 编码

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

  print('开始在目录中移除注释 (带所有规则): $repoPath');
  print('---');

  int filesProcessed = 0; // 已处理文件计数
  int filesModified = 0;  // 已修改文件计数

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
          print('  -> 注释已移除并完成清理。');
          filesModified++;
        } else {
          print('  -> 无需更改。');
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
/// 保留字符串和字符字面量。
/// 保留 // @formatter:off 和 // @formatter:on。
/// 如果 // 前面紧邻非空白字符，且 // 后面在本行无其他非空白字符，则保留 (例如 URL 中的 //)。
/// 移除注释后，若行变为空白（仅含空格/tab），则删除该行内容（通过后续清理实现）。
/// 移除单行注释时，同时移除其前导空格（通过行尾清理实现）。
String removeComments(String code) {
  // 第一步：移除注释内容，应用特殊保留规则

  final commentRegex = RegExp(
      r'("(\\.|[^"\\])*")'              // 分组 1 & 2: 字符串字面量
      r"|('(\\.|[^'\\])*')"              // 分组 3 & 4: 字符字面量
      r'|(//[^\n\r]*)'                   // 分组 5: 单行注释 (直到行尾)
      r'|(/\*(?:[^*]|\*+[^*/])*\*+/)'    // 分组 6: 多行注释 (更健壮的模式)
      , multiLine: true                // 启用多行模式，影响 ^、$ 和 . 的行为
  );

  String result = code.replaceAllMapped(commentRegex, (match) {
    // --- 处理单行注释 ---
    if (match.group(5) != null) {
      String singleLineComment = match.group(5)!; // 匹配到的 '//...' 文本
      int matchStart = match.start;              // 匹配项在代码中的起始索引

      // --- 检查特殊的 "URL类似" 情况 ---
      bool precededByNonSpace = false; // 标记 // 前面是否是非空白字符
      if (matchStart > 0) { // 确保不是文件开头
        String charBefore = code[matchStart - 1]; // 获取 // 前面的字符
        // 检查 // 前面的字符是否不是空格或制表符
        if (charBefore != ' ' && charBefore != '\t') {
          // 考虑添加其他空白字符的检查？目前仅检查空格和制表符。
          // if (!RegExp(r'\s').hasMatch(charBefore)) { // 更通用的空白检查
          precededByNonSpace = true;
        }
      }

      // 检查 '//' 之后是否没有有效内容（只有空白或空）
      String contentAfterDoubleSlash = singleLineComment.substring(2); // 获取 // 之后的内容
      bool nothingMeaningfulAfter = contentAfterDoubleSlash.trim().isEmpty; // 检查去除前后空白后是否为空

      // 如果 // 前是紧邻的非空白字符，并且 // 之后无有效内容，则保留
      if (precededByNonSpace && nothingMeaningfulAfter) {
        // 条件满足 (例如 http://, file://)：保留这个 "注释"
        return singleLineComment;
      }
      // --- 特殊情况检查结束 ---

      // 否则，按常规注释或 formatter 指令处理
      String trimmedComment = singleLineComment.trim(); // 去除注释两端空白
      if (trimmedComment == "// @formatter:off" || trimmedComment == "// @formatter:on") {
        return singleLineComment; // 保留 formatter 指令
      } else {
        // 移除其他常规单行注释 (暂时保留前面的空格，由后续步骤处理)
        return '';
      }

      // --- 处理多行注释 ---
    } else if (match.group(6) != null) {
      return ''; // 移除多行注释
      // --- 处理字面量 ---
    } else {
      // 匹配到了字符串或字符字面量
      return match.group(0)!; // 保持字面量不变
    }
  });

  // --- 第二步：行清理 ---

  // 1. 移除每行末尾的空格和制表符。
  //    这也会处理掉原本在被移除的 // 注释之前的空格。
  result = result.replaceAll(RegExp(r'[ \t]+$', multiLine: true), '');

  // 2. 将多个连续的空行压缩为单个空行。
  //    这会处理因注释移除或空白行清理而产生的连续空行。
  result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  // 3. 移除文件开头可能存在的多余空行。
  result = result.trimLeft();

  // 4. 移除文件末尾可能存在的多余空白（包括换行符）。
  result = result.trimRight();

  // 5. 可选: 确保非空文件末尾总是有且只有一个换行符。
  if (result.isNotEmpty && !result.endsWith('\n')) {
    result += '\n';
  }

  return result;
}
