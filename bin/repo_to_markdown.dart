import 'dart:convert'; // 用于 utf8 解码
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

// --- 配置 ---
const String outputFileNameDefault = 'project_content.md'; // 默认输出文件名
// 根据需要添加更多文本文件扩展名
const Set<String> textFileExtensions = {
  '.txt',
  '.md',
  '.markdown',
  '.java',
  '.groovy',
  '.scala',
  '.kt',
  // JVM 相关
  '.xml',
  '.yaml',
  '.yml',
  '.json',
  '.properties',
  '.gradle',
  // 配置/数据文件
  '.dart',
  '.js',
  '.ts',
  '.jsx',
  '.tsx',
  // Web/Dart 相关
  '.py',
  '.rb',
  '.php',
  // 脚本语言
  '.c',
  '.cpp',
  '.h',
  '.hpp',
  '.cs',
  // C 风格语言
  '.go',
  '.rs',
  // 其他流行语言
  '.html',
  '.css',
  '.scss',
  '.less',
  // Web 前端
  '.sh',
  '.bat',
  // Shell 脚本
  '.sql',
  // SQL 文件
  // 添加一些通常是文本但没有扩展名的文件（例如 Dockerfile, Jenkinsfile）
  'dockerfile',
  'jenkinsfile',
  'makefile',
  'pom', // 检查文件名本身
  '.gitignore',
  '.gitattributes', // Git 特定文本文件
};

// --- 主要逻辑 ---
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('type', abbr: 't', help: '指定项目类型 (例如, java-maven)。')
    ..addOption('output',
        abbr: 'o',
        defaultsTo: outputFileNameDefault, // 使用默认值
        help: '输出 Markdown 文件名。')
    ..addOption('skip-dirs', // 跳过目录选项
        abbr: 'e', // 'e' for exclude
        defaultsTo: '',
        help: '需要跳过的目录列表，以逗号分隔 (例如 "build,dist,.idea")。')
    ..addOption('skip-extensions', // 新增：跳过后缀选项
        abbr: 'x', // 'x' for extensions
        defaultsTo: '',
        help: '需要跳过的文件后缀列表，以逗号分隔，带点 (例如 ".kt,.log")。')
    ..addOption('skip-patterns', // 新增：跳过通配符模式选项
        abbr: 'p', // 'p' for patterns
        defaultsTo: '',
        help: '需要跳过的文件名通配符模式列表，以逗号分隔 (例如 "Test*.java,*.tmp")。')
    ..addFlag('help', abbr: 'h', negatable: false, help: '显示此帮助信息。');

  ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } catch (e) {
    print('错误：解析参数失败: ${e}');
    printUsage(parser);
    exit(1);
  }

  if (argResults['help'] as bool) {
    printUsage(parser);
    exit(0);
  }

  final projectType = argResults['type'] as String?;
  final outputFile = argResults['output'] as String;
  final skipDirsRaw = argResults['skip-dirs'] as String;
  final skipExtensionsRaw = argResults['skip-extensions'] as String; // 获取原始后缀字符串
  final skipPatternsRaw = argResults['skip-patterns'] as String; // 获取原始模式字符串
  final currentDirectory = Directory.current;

  // 解析并规范化要跳过的目录
  final Set<String> skipDirs = skipDirsRaw
      .split(',')
      .map((d) => d.trim())
      .where((d) => d.isNotEmpty)
      .map((d) => p.normalize(d).replaceAll('\\', '/')) // 规范化并统一斜杠
      .toSet();

  // 解析要跳过的后缀 (确保它们以 '.' 开头并转为小写)
  final Set<String> skipExtensions = skipExtensionsRaw
      .split(',')
      .map((ext) => ext.trim().toLowerCase())
      .where((ext) => ext.isNotEmpty)
      .map((ext) => ext.startsWith('.') ? ext : '.$ext') // 确保有前导点
      .toSet();

  // 解析并转换通配符模式为正则表达式
  final List<RegExp> skipPatternsRegex = [];
  if (skipPatternsRaw.isNotEmpty) {
    final patterns = skipPatternsRaw.split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);
    for (final pattern in patterns) {
      try {
        skipPatternsRegex.add(_wildcardToRegExp(pattern));
      } catch (e) {
        print("警告: 无法将通配符模式 '$pattern' 转换为正则表达式: $e");
      }
    }
  }


  print('开始分析目录: ${currentDirectory.path}');
  print('项目类型: ${projectType ?? '未指定'}');
  print('输出文件: $outputFile');
  if (skipDirs.isNotEmpty) {
    print('将跳过以下指定目录及其内容: ${skipDirs.join(', ')}');
  }
  if (skipExtensions.isNotEmpty) { // 打印要跳过的后缀
    print('将跳过以下后缀的文件: ${skipExtensions.join(', ')}');
  }
  if (skipPatternsRegex.isNotEmpty) { // 打印要跳过的模式
    print('将跳过匹配以下模式的文件: ${skipPatternsRaw}'); // 打印原始模式更易读
  }

  // 加载 .gitignore 规则，并始终忽略输出文件本身和 .git 目录
  final gitignorePatterns = await loadGitignore(currentDirectory, outputFile);
  final outputBuffer = StringBuffer();
  final processedFiles = <String>{}; // 跟踪已添加的文件，避免重复

  // --- 特定项目类型处理 (例如 pom.xml) ---
  // 这个逻辑保持不变，但需要确保它发生在递归遍历之前
  if (projectType == 'java-maven') {
    print('正在处理 java-maven 项目...');
    final pomFile = File(p.join(currentDirectory.path, 'pom.xml'));
    if (await pomFile.exists()) {
      print('找到 pom.xml，优先处理。');
      final relativePomPath = p.relative(pomFile.path, from: currentDirectory.path);
      final normalizedRelativePomPath = p.normalize(relativePomPath).replaceAll('\\', '/');
      // 检查 pom.xml 是否需要跳过
      if (!shouldSkip(normalizedRelativePomPath, skipDirs, gitignorePatterns, skipExtensions, skipPatternsRegex, isDirectory: false)) {
        await processFile(
            pomFile, currentDirectory.path, outputBuffer, gitignorePatterns, skipExtensions, skipPatternsRegex, normalizedRelativePomPath);
        processedFiles.add(p.normalize(pomFile.path)); // 记录已处理
      } else {
        print('注意: pom.xml 根据跳过规则被跳过。');
      }
    } else {
      print('警告: 项目类型为 java-maven，但在根目录未找到 pom.xml。');
    }
  }

  // --- **修改点：使用手动递归遍历** ---
  print('正在扫描文件 (使用手动递归)...');
  await processDirectoryRecursively(
      currentDirectory, // 起始目录
      currentDirectory.path, // 根目录路径
      outputBuffer,
      skipDirs,
      gitignorePatterns,
      skipExtensions,
      skipPatternsRegex,
      processedFiles // 传递已处理集合，避免重复处理 (如 pom.xml)
  );

  // --- 写入输出 ---
  final outFile = File(p.join(currentDirectory.path, outputFile));
  try {
    await outFile.writeAsString(outputBuffer.toString());
    print('\n成功将项目内容写入到 ${outFile.path}');
  } catch (e) {
    print('\n错误：写入输出文件失败: $e');
    exit(1);
  }
}

/// **新增：手动递归处理目录**
Future<void> processDirectoryRecursively(
    Directory directory,
    String rootDir,
    StringBuffer buffer,
    Set<String> skipDirs,
    List<RegExp> gitignorePatterns,
    Set<String> skipExtensions,
    List<RegExp> skipPatternsRegex,
    Set<String> processedFiles // 跟踪已处理文件
    ) async {

  final relativeDirPath = p.relative(directory.path, from: rootDir);
  final normalizedRelativeDirPath = p.normalize(relativeDirPath).replaceAll('\\', '/');

  // **关键点：在尝试列出目录内容之前检查是否应跳过此目录**
  if (shouldSkip(normalizedRelativeDirPath, skipDirs, gitignorePatterns, null, null, isDirectory: true)) {
    if (normalizedRelativeDirPath.isNotEmpty) { // 不打印根目录被跳过的消息
      print('跳过目录 (根据 --skip-dirs 或 .gitignore): $normalizedRelativeDirPath/');
    }
    return; // 跳过此目录，不再递归
  }

  Stream<FileSystemEntity> entities;
  try {
    // 使用非递归 list，并捕获可能的权限错误
    entities = directory.list(recursive: false, followLinks: false);
  } on FileSystemException catch (e) {
    // 如果列出目录失败（例如权限问题），打印警告并跳过此目录
    print('警告: 无法列出目录 $normalizedRelativeDirPath 的内容，跳过。错误: $e');
    return;
  }

  await for (final entity in entities) {
    final relativePath = p.relative(entity.path, from: rootDir);
    final normalizedRelativePath = p.normalize(relativePath).replaceAll('\\', '/');
    final isDir = entity is Directory;

    if (isDir) {
      // 对于子目录，递归调用
      await processDirectoryRecursively(
          entity as Directory,
          rootDir,
          buffer,
          skipDirs,
          gitignorePatterns,
          skipExtensions,
          skipPatternsRegex,
          processedFiles);
    } else if (entity is File) {
      final normalizedAbsolutePath = p.normalize(entity.path);
      // 如果文件已被特殊处理过（例如 pom.xml），则跳过
      if (processedFiles.contains(normalizedAbsolutePath)) {
        continue;
      }

      // 检查文件是否应被跳过
      if (!shouldSkip(normalizedRelativePath, null, gitignorePatterns, skipExtensions, skipPatternsRegex, isDirectory: false)) {
        // 处理文件
        await processFile(entity, rootDir, buffer, gitignorePatterns, skipExtensions, skipPatternsRegex, normalizedRelativePath);
      } else {
        // print('Skipping file due to rules: $normalizedRelativePath'); // 可选调试输出
      }
    }
  }
}


/// **新增：统一的跳过逻辑检查函数**
/// relativePath: 规范化后的相对路径 (相对于项目根目录)
/// skipDirs: --skip-dirs 参数解析后的集合 (仅在 isDirectory 为 true 时检查)
/// gitignorePatterns: .gitignore 解析后的正则列表
/// skipExtensions: --skip-extensions 参数解析后的集合 (仅在 isDirectory 为 false 时检查)
/// skipPatternsRegex: --skip-patterns 参数解析后的正则列表 (仅在 isDirectory 为 false 时检查)
/// isDirectory: 当前检查的是目录还是文件
bool shouldSkip(
    String normalizedRelativePath,
    Set<String>? skipDirs,
    List<RegExp> gitignorePatterns,
    Set<String>? skipExtensions,
    List<RegExp>? skipPatternsRegex,
    {required bool isDirectory})
{
  if (normalizedRelativePath.isEmpty) return false; // 根目录本身不跳过

  // 1. 检查 .gitignore (对文件和目录都适用)
  if (isIgnored(normalizedRelativePath, gitignorePatterns, isDirectory: isDirectory)) {
    return true;
  }

  // 2. 如果是目录，检查 --skip-dirs
  if (isDirectory && skipDirs != null) {
    // 精确匹配或作为父目录匹配
    for (final skipDir in skipDirs) {
      if (normalizedRelativePath == skipDir || normalizedRelativePath.startsWith('$skipDir/')) {
        return true;
      }
    }
  }
  // 3. 如果是文件，检查 --skip-extensions 和 --skip-patterns
  else if (!isDirectory) {
    final filename = p.basename(normalizedRelativePath);
    final extension = p.extension(filename).toLowerCase();

    // 检查后缀
    if (skipExtensions != null && skipExtensions.contains(extension)) {
      return true;
    }

    // 检查通配符模式
    if (skipPatternsRegex != null) {
      for (final regex in skipPatternsRegex) {
        if (regex.hasMatch(filename)) {
          return true;
        }
      }
    }
  }

  return false; // 默认不跳过
}


// --- 辅助函数 ---

/// 将简单的文件名通配符模式转换为正则表达式。
/// 支持 '*' (匹配零个或多个非斜杠字符) 和 '?' (匹配一个非斜杠字符)。
RegExp _wildcardToRegExp(String wildcard) {
  // (之前的实现保持不变)
  String regexString = wildcard.replaceAllMapped(
      RegExp(r'[.+^${}()|[\]\\]'),
          (match) => '\\${match.group(0)}');
  regexString = regexString.replaceAll('*', '.*');
  regexString = regexString.replaceAll('?', '.');
  return RegExp('^$regexString\$');
}


// 打印使用说明
void printUsage(ArgParser parser) {
  // (之前的实现保持不变)
  print('用法: dart <脚本文件名>.dart [选项]');
  print('\n扫描当前目录中的文本文件并生成 Markdown 输出。\n');
  print('选项:');
  print(parser.usage);
}

// 加载 .gitignore 文件并返回正则表达式模式列表
Future<List<RegExp>> loadGitignore(
    Directory rootDir, String outputFileName) async {
  // (之前的实现保持不变, 但添加了 .git/ 的忽略)
  final gitignoreFile = File(p.join(rootDir.path, '.gitignore'));
  final patterns = <RegExp>[];
  // 始终忽略 .git 目录和输出文件本身
  patterns.add(createGitignoreRegExp('.git/')); // 明确忽略 .git 目录
  patterns.add(createGitignoreRegExp(outputFileName));

  if (await gitignoreFile.exists()) {
    try {
      final lines = await gitignoreFile.readAsLines();
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        patterns.add(createGitignoreRegExp(line));
      }
      print('已加载 .gitignore 模式。');
    } catch (e) {
      print('警告: 无法读取 .gitignore 文件: $e');
    }
  } else {
    print('在根目录未找到 .gitignore 文件，将仅忽略 .git/ 和输出文件。');
  }
  return patterns;
}

// 将 gitignore 模式基础转换为 RegExp
// **修改：稍微调整以更好地区分文件和目录模式**
RegExp createGitignoreRegExp(String pattern) {
  // 1. 转义 RegExp 特殊字符
  var regexString =
  pattern.replaceAllMapped(RegExp(r'[.+^${}()|[\]\\]'), (match) {
    return '\\${match.group(0)}'; // 在特殊字符前加反斜杠
  });

  // 处理特殊字符 '!' (否定模式) - 简单处理，不支持复杂否定
  bool isNegation = pattern.startsWith('!');
  if (isNegation) {
    regexString = regexString.substring(1); // 移除开头的 '!'
    pattern = pattern.substring(1); // 原始模式也移除
  }

  // 2. 处理通配符 '*' 和 '**'
  // '/**/' 匹配零或多个目录
  regexString = regexString.replaceAll('\\/\\*\\*\\/', '(?:\\/|\\/.*\\/)?');
  // '**/': 匹配路径中的任意位置的零或多个目录
  regexString = regexString.replaceAll('\\*\\*\\/', '(?:.*\\/)?');
  // '/**': 匹配路径末尾的任意字符
  regexString = regexString.replaceAll('\\/\\*\\*', '\\/.*');
  // '**': 匹配任意字符 (如果不在路径分隔符旁) - 简化处理
  // 注意：更精确的 '**' 处理很复杂，这里简化
  regexString = regexString.replaceAll('\\*\\*', '.*');
  // '*': 匹配除 '/' 外的任意字符零次或多次
  regexString = regexString.replaceAll('\\*', '[^/]*');
  // '?': 匹配除 '/' 外的任意单个字符
  regexString = regexString.replaceAll('\\?', '[^/]');


  // 3. 处理路径分隔符和锚点
  bool dirOnly = pattern.endsWith('/');
  if (dirOnly) {
    // 如果模式以 / 结尾，则只匹配目录
    regexString = regexString.substring(0, regexString.length - '\\/'.length); // 移除结尾的转义斜杠
  }

  if (!pattern.startsWith('/') && !pattern.contains('/')) {
    // 模式不含 '/', 匹配任何目录层级的同名文件/目录
    // 例如 'build' 匹配 'build', 'src/build'
    regexString = '(?:^|\\/)' + regexString; // 匹配开头或 / 之后
  } else if (pattern.startsWith('/')) {
    // 模式以 / 开头，仅匹配项目根目录下的文件/目录
    regexString = '^' + regexString.substring('\\/'.length); // 从根开始匹配
  } else {
    // 模式包含 / 但不以 / 开头，例如 'src/build'
    regexString = '(?:^|\\/)' + regexString; // 可以在任何层级匹配
  }

  // 4. 处理结尾
  if (dirOnly) {
    // 如果是目录模式，确保匹配以 / 结尾或整个路径就是该目录名
    regexString += '\\/?\$'; // 匹配 dir 或 dir/
    // 更严格的是 regexString += '\\/\$'; 但可能需要匹配根下的目录
  } else if (!pattern.endsWith('/')) {
    // 如果是文件模式 (或不确定模式)，可以匹配文件或目录
    // '/?' 使其也能匹配同名目录， $ 确保匹配到结尾
    // (?:\\/|\$) 匹配路径结束或者后面是/
    regexString += '(?:\\/|\$)';
  }


  // 否定模式的处理可以在 isIgnored 中完成，这里只返回基础正则
  // 注意：gitignore 的精确实现非常复杂，特别是否定模式和优先级。
  // 这个实现涵盖了常见情况，但可能在边缘情况失效。
  try {
    // print("Pattern: '$pattern' -> RegExp: '$regexString'"); // Debug 输出
    // 返回包含否定标志的元组或对象可能更好，但为简单起见，暂时只返回 RegExp
    return RegExp(regexString);
  } catch (e) {
    print("警告: 无法将 gitignore 模式 '$pattern' 编译为 RegExp: $e");
    // 返回一个永远不匹配的正则
    return RegExp(r'^\b$'); // 使用 \b 来确保不意外匹配任何东西
  }
}


// 检查给定的相对路径是否被 .gitignore 规则忽略
// **修改：添加 isDirectory 参数以辅助匹配**
bool isIgnored(String relativePath, List<RegExp> gitignorePatterns, {required bool isDirectory}) {
  // (之前的实现有修改)
  relativePath = p.normalize(relativePath).replaceAll('\\', '/');
  if (relativePath.startsWith('/')) {
    relativePath = relativePath.substring(1);
  }

  // 如果是目录，确保路径以 '/' 结尾，以便与目录模式 ('dir/') 匹配
  String pathToMatch = relativePath;
  if (isDirectory && !pathToMatch.endsWith('/') && pathToMatch.isNotEmpty) {
    pathToMatch += '/';
  }

  bool ignored = false;
  // 注意：Gitignore 规则是最后匹配的优先。但简单起见，这里只要匹配就忽略。
  // 真正的 Gitignore 实现还需要考虑否定规则 (!) 和优先级。
  for (final regex in gitignorePatterns) {
    // 尝试匹配原始路径 (用于文件或非斜杠结尾的目录模式)
    if (regex.hasMatch(relativePath)) {
      // print("Match found for '$relativePath' with pattern ${regex.pattern}"); // Debug
      ignored = true;
      // 在简单实现中，第一个匹配就返回 true
      // 如果要支持否定，需要继续检查
      // break; // 如果不处理否定，可以在此中断
    }
    // 如果是目录，也尝试匹配加了斜杠的路径 (用于 'dir/' 这样的模式)
    if (isDirectory && regex.hasMatch(pathToMatch)) {
      // print("Directory match found for '$pathToMatch' with pattern ${regex.pattern}"); // Debug
      ignored = true;
      // break; // 如果不处理否定，可以在此中断
    }
  }

  // TODO: 实现否定规则 (!) 处理。
  // 如果需要支持否定，需要记录最后匹配的规则，并检查它是否是否定规则。

  return ignored;
}


// 处理单个文件：检查是否文本、读取内容、移除注释并添加到缓冲区
// 参数略有调整，移除了 redundant 的 skipXXX 检查，因为它们在调用前已完成
Future<void> processFile(
    File file,
    String rootDir,
    StringBuffer buffer,
    List<RegExp> gitignorePatterns, // 仍然需要检查单个文件的 gitignore 规则
    Set<String> skipExtensions, // 保留用于isLikelyTextFile和语言确定可能需要
    List<RegExp> skipPatternsRegex, // 保留，以防万一
    [String? normalizedRelativePath]) async { // 可选的相对路径

  // 如果未提供，则计算相对路径 (理论上总会被提供)
  normalizedRelativePath ??=
      p.normalize(p.relative(file.path, from: rootDir)).replaceAll('\\', '/');

  // 1. 再次检查 .gitignore (可能某个模式只针对这个文件)
  // 注意：这里的 isIgnored 调用 isDirectory: false
  if (isIgnored(normalizedRelativePath, gitignorePatterns, isDirectory: false)) {
    // print('Skipping ignored file (in processFile): $normalizedRelativePath');
    return;
  }

  // 2. 检查是否可能是文本文件
  if (!isLikelyTextFile(file.path)) {
    // print('跳过非文本文件: $normalizedRelativePath'); // 信息已在主逻辑打印，这里可选
    return;
  }

  // 3. 读取内容并移除注释
  try {
    // 读取前先检查文件大小，避免读取巨大文件（可选）
    // final fileStat = await file.stat();
    // if (fileStat.size > 10 * 1024 * 1024) { // 例如，跳过大于 10MB 的文件
    //   print('跳过大文件 (>10MB): $normalizedRelativePath');
    //   return;
    // }

    final bytes = await file.readAsBytes();
    // 检查是否包含 NULL 字节，这通常表明是二进制文件
    if (bytes.contains(0)) {
      print('跳过可能是二进制的文件 (包含空字节): $normalizedRelativePath');
      return;
    }

    String content;
    try {
      // 尝试 UTF-8 解码
      content = utf8.decode(bytes, allowMalformed: false); // 不允许错误格式，更严格
    } on FormatException catch (e) {
      print('跳过解码错误的文件 (不是有效的 UTF-8 文本): $normalizedRelativePath. 错误: $e');
      return; // 跳过无法解码的文件
    }

    // 移除注释
    final cleanedContent = removeComments(content, file.path);

    // 如果移除注释后内容为空，则跳过
    if (cleanedContent.trim().isEmpty) {
      // print('跳过（注释移除后）空文件: $normalizedRelativePath');
      return;
    }

    // 获取 Markdown 语言标识符
    final language = getMarkdownLanguage(file.path);

    // 4. 追加到缓冲区
    print('添加文件: $normalizedRelativePath'); // 确认添加
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('**$normalizedRelativePath**'); // 文件路径作为标题
    buffer.writeln();
    buffer.writeln('```$language'); // 代码块开始，指定语言
    buffer.writeln(cleanedContent.trim()); // 清理后的内容
    buffer.writeln('```'); // 代码块结束
    buffer.writeln(); // 添加空行分隔
  } on FileSystemException catch (e) {
    // 捕获读取文件时可能发生的其他文件系统错误
    print('错误：读取文件 $normalizedRelativePath 失败: $e');
  } catch (e) {
    // 捕获其他意外错误
    print('错误：处理文件 $normalizedRelativePath 时发生未知错误: $e');
  }
}

// 判断文件是否可能是文本文件
bool isLikelyTextFile(String filePath) {
  // (之前的实现保持不变)
  final extension = p.extension(filePath).toLowerCase();
  final filename = p.basename(filePath).toLowerCase();
  // 优先检查已知文本文件扩展名
  if (textFileExtensions.contains(extension)) {
    return true;
  }
  // 检查无扩展名的已知文本文件名
  if (textFileExtensions.contains(filename)) {
    return true;
  }
  // 可以添加更复杂的检查，例如读取文件开头一小部分判断，但目前保持简单
  return false;
}

// 根据文件路径获取 Markdown 代码块的语言标识符
String getMarkdownLanguage(String filePath) {
  // (之前的实现保持不变)
  final extension = p.extension(filePath).toLowerCase();
  switch (extension) {
    case '.java': return 'java';
    case '.xml': return 'xml';
    case '.md': return 'markdown';
    case '.dart': return 'dart';
    case '.js': return 'javascript';
    case '.ts': return 'typescript';
    case '.jsx': return 'jsx';
    case '.tsx': return 'tsx';
    case '.py': return 'python';
    case '.rb': return 'ruby';
    case '.php': return 'php';
    case '.yaml': case '.yml': return 'yaml';
    case '.json': return 'json';
    case '.html': return 'html';
    case '.css': return 'css';
    case '.scss': return 'scss';
    case '.less': return 'less';
    case '.sh': return 'shell';
    case '.sql': return 'sql';
    case '.gradle': return 'groovy'; // .gradle 文件通常是 Groovy
    case '.kt': case '.kts': return 'kotlin';
    case '.c': return 'c';
    case '.cpp': return 'cpp';
    case '.h': case '.hpp': return 'cpp'; // .h 和 .hpp 通常用于 C/C++
    case '.cs': return 'csharp';
    case '.go': return 'go';
    case '.rs': return 'rust';
    case '.properties': return 'properties';
    case '.groovy': return 'groovy';
    case '.scala': return 'scala';
    case '.bat': return 'batch';
    case '.txt': return 'text';
    default:
    // 处理无扩展名的常见文件
      final filename = p.basename(filePath).toLowerCase();
      if (filename == 'dockerfile') return 'dockerfile';
      if (filename == 'makefile') return 'makefile';
      if (filename == 'jenkinsfile') return 'groovy'; // Jenkinsfile 通常是 Groovy
      if (filename == 'pom.xml') return 'xml'; // pom.xml 明确是 xml
      if (filename == '.gitignore') return 'gitignore'; // .gitignore 本身
      // 默认或未知类型
      return 'plaintext';
  }
}

// 根据文件类型移除代码注释
String removeComments(String content, String filePath) {
  // (之前的实现保持不变)
  final extension = p.extension(filePath).toLowerCase();
  final filename = p.basename(filePath).toLowerCase();
  String cleanedContent = content;

  try {
    // C 风格注释 (Java, JS, TS, Dart, C, C++, C#, Go, Rust, Scala, Kotlin, Groovy)
    if (const {
      '.java', '.js', '.ts', '.dart', '.c', '.cpp', '.h', '.hpp', '.cs',
      '.go', '.rs', '.scala', '.kt', '.groovy'
    }.contains(extension)) {
      // 移除块注释 /* ... */ (非贪婪匹配)
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'/\*.*?\*/', multiLine: true, dotAll: true), '');
      // 移除行注释 // ...
      cleanedContent = cleanedContent.replaceAll(RegExp(r'(?<!:)\/\/.*'), '');
    }
    // XML/HTML/Markdown 注释 <!-- ... -->
    else if (const {'.xml', '.html', '.md', '.vue'}.contains(extension) ||
        filename == 'pom.xml') { // pom.xml 是 XML
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'<!--.*?-->', multiLine: true, dotAll: true), '');
    }
    // Shell/Python/Ruby/YAML/Properties/Dockerfile/Makefile 注释 # ...
    else if (const {
      '.py', '.rb', '.sh', '.yaml', '.yml', '.properties', '.gitignore'
    }.contains(extension) ||
        const {'dockerfile', 'makefile'}.contains(filename)) {
      // 匹配行首的 # (允许前面有空格) 或 行内空格后的 #
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'^\s*#.*|(?<=\s)#.*', multiLine: true), '');
    }
    // SQL 注释 -- ... 和 /* ... */
    else if (extension == '.sql') {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'/\*.*?\*/', multiLine: true, dotAll: true), '');
      cleanedContent = cleanedContent.replaceAll(RegExp(r'--.*'), '');
    }
    // Batch (.bat) 注释 REM ... 或 :: ...
    else if (extension == '.bat') {
      // 忽略大小写匹配行首的 REM 或 ::
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'^\s*(?:REM\s|::).*', caseSensitive: false, multiLine: true), '');
    }

    // 移除所有注释后，去除可能产生的完全空行
    cleanedContent = cleanedContent
        .split('\n') // 按行分割
        .where((line) => line.trim().isNotEmpty) // 保留非空行
        .join('\n'); // 重新组合
  } catch (e) {
    // 如果移除注释过程中发生错误，打印警告并返回原始内容
    print("警告: 从 $filePath 移除注释时出错: $e");
    return content;
  }
  return cleanedContent;
}
