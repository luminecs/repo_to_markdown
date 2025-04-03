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
      .map((d) => p.normalize(d).replaceAll('\\', '/'))
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
    print('将跳过以下目录及其内容: ${skipDirs.join(', ')}');
  }
  if (skipExtensions.isNotEmpty) { // 打印要跳过的后缀
    print('将跳过以下后缀的文件: ${skipExtensions.join(', ')}');
  }
  if (skipPatternsRegex.isNotEmpty) { // 打印要跳过的模式
    print('将跳过匹配以下模式的文件: ${skipPatternsRaw}'); // 打印原始模式更易读
  }

  // 加载 .gitignore 规则，并始终忽略输出文件本身
  final gitignorePatterns = await loadGitignore(currentDirectory, outputFile);
  final outputBuffer = StringBuffer();
  final processedFiles = <String>{}; // 跟踪已添加的文件，避免重复

  // --- 特定项目类型处理 ---
  if (projectType == 'java-maven') {
    print('正在处理 java-maven 项目...');
    final pomFile = File(p.join(currentDirectory.path, 'pom.xml'));
    if (await pomFile.exists()) {
      print('找到 pom.xml，优先添加。');
      final relativePomPath =
      p.relative(pomFile.path, from: currentDirectory.path);
      final normalizedRelativePomPath =
      p.normalize(relativePomPath).replaceAll('\\', '/');
      bool skipPom = false;
      // 检查是否在跳过目录中
      for (final skipDir in skipDirs) {
        if (normalizedRelativePomPath == skipDir ||
            normalizedRelativePomPath.startsWith('$skipDir/')) {
          skipPom = true;
          print('警告: pom.xml 位于被跳过的目录中，将不被处理: $normalizedRelativePomPath');
          break;
        }
      }
      // 检查是否匹配跳过后缀或模式 (虽然 pom.xml 通常不会被跳过，但逻辑上应检查)
      if (!skipPom) {
        final pomFilename = p.basename(pomFile.path);
        final pomExtension = p.extension(pomFilename).toLowerCase();
        if (skipExtensions.contains(pomExtension)) {
          print('警告: pom.xml 后缀 $pomExtension 在跳过列表中，将不被处理。');
          skipPom = true;
        } else {
          for (final regex in skipPatternsRegex) {
            if (regex.hasMatch(pomFilename)) {
              print('警告: pom.xml 文件名匹配跳过模式 ${regex.pattern}，将不被处理。');
              skipPom = true;
              break;
            }
          }
        }
      }
      // 检查 gitignore
      if (!skipPom && isIgnored(normalizedRelativePomPath, gitignorePatterns)) {
        print('警告: pom.xml 被 .gitignore 规则忽略，将不被处理。');
        skipPom = true;
      }

      if (!skipPom) {
        await processFile(
            pomFile, currentDirectory.path, outputBuffer, gitignorePatterns, skipExtensions, skipPatternsRegex, normalizedRelativePomPath); // 传递新参数
        processedFiles.add(p.normalize(pomFile.path)); // 记录已处理
      }
    } else {
      print('警告: 项目类型为 java-maven，但在根目录未找到 pom.xml。');
    }
  }

  // --- 递归遍历文件 ---
  print('正在扫描文件...');
  await for (final entity
  in currentDirectory.list(recursive: true, followLinks: false)) {
    final relativePath = p.relative(entity.path, from: currentDirectory.path);
    final normalizedRelativePath =
    p.normalize(relativePath).replaceAll('\\', '/');

    // --- 检查是否应跳过此路径（目录） ---
    bool skip = false;
    for (final skipDir in skipDirs) {
      if (normalizedRelativePath == skipDir ||
          normalizedRelativePath.startsWith('$skipDir/')) {
        skip = true;
        // print('Skipping path due to --skip-dirs: $normalizedRelativePath');
        break;
      }
    }
    if (skip) {
      continue;
    }

    // --- 只处理文件 ---
    if (entity is File) {
      final normalizedAbsolutePath = p.normalize(entity.path);
      // 如果文件已被特殊处理过（例如 pom.xml），则跳过
      if (processedFiles.contains(normalizedAbsolutePath)) {
        continue;
      }

      // --- 新增：检查是否应根据后缀或模式跳过此文件 ---
      final filename = p.basename(entity.path);
      final extension = p.extension(filename).toLowerCase();

      // 检查后缀
      if (skipExtensions.contains(extension)) {
        // print('Skipping file due to extension $extension: $normalizedRelativePath'); // 可选调试输出
        continue;
      }

      // 检查通配符模式
      bool skipByPattern = false;
      for (final regex in skipPatternsRegex) {
        if (regex.hasMatch(filename)) {
          // print('Skipping file due to pattern ${regex.pattern}: $normalizedRelativePath'); // 可选调试输出
          skipByPattern = true;
          break;
        }
      }
      if (skipByPattern) {
        continue;
      }
      // --- 跳过逻辑结束 ---


      // 使用上面计算好的 normalizedRelativePath 进行处理
      await processFile(entity, currentDirectory.path, outputBuffer,
          gitignorePatterns, skipExtensions, skipPatternsRegex, normalizedRelativePath); // 传递新参数
    }
  }

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

// --- 辅助函数 ---

/// 将简单的文件名通配符模式转换为正则表达式。
/// 支持 '*' (匹配零个或多个非斜杠字符) 和 '?' (匹配一个非斜杠字符)。
/// 注意：这是一个简化实现，不完全支持复杂的 glob 模式。
RegExp _wildcardToRegExp(String wildcard) {
  // 1. 转义 RegExp 特殊字符 (除了 * 和 ?)
  String regexString = wildcard.replaceAllMapped(
      RegExp(r'[.+^${}()|[\]\\]'), // 注意：移除了 * 和 ?
          (match) => '\\${match.group(0)}');

  // 2. 将通配符 * 替换为 .* (匹配任意字符零次或多次)
  //   更精确的应该是 '[^/]*'，但对于纯文件名匹配 '.*' 通常足够
  regexString = regexString.replaceAll('*', '.*');

  // 3. 将通配符 ? 替换为 . (匹配任意单个字符)
  //   更精确的应该是 '[^/]'
  regexString = regexString.replaceAll('?', '.');

  // 4. 添加锚点，确保匹配整个文件名
  return RegExp('^$regexString\$');
}


// 打印使用说明
void printUsage(ArgParser parser) {
  print('用法: dart <脚本文件名>.dart [选项]');
  print('\n扫描当前目录中的文本文件并生成 Markdown 输出。\n');
  print('选项:');
  print(parser.usage);
}

// 加载 .gitignore 文件并返回正则表达式模式列表
Future<List<RegExp>> loadGitignore(
    Directory rootDir, String outputFileName) async {
  final gitignoreFile = File(p.join(rootDir.path, '.gitignore'));
  final patterns = <RegExp>[];
  patterns.add(createGitignoreRegExp('.git/'));
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
    print('在根目录未找到 .gitignore 文件。');
  }
  return patterns;
}

// 将 gitignore 模式基础转换为 RegExp
RegExp createGitignoreRegExp(String pattern) {
  // (之前的实现保持不变)
  // 1. 转义 RegExp 特殊字符
  var regexString =
  pattern.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (match) {
    return '\\${match.group(0)}'; // 在特殊字符前加反斜杠
  });

  // 2. 处理通配符 '*' 和 '**'
  regexString = regexString.replaceAll('**/', '(?:.*/)?');
  regexString = regexString.replaceAll('**', '.*');
  regexString = regexString.replaceAll('*', '[^/]*');
  regexString = regexString.replaceAll('?', '[^/]');

  // 3. 处理开头/结尾的斜杠和目录匹配
  bool dirOnly = pattern.endsWith('/');
  if (dirOnly) {
    regexString = regexString.substring(
        0, regexString.length - '\\/'.length); // 移除结尾的转义斜杠
  }

  if (!pattern.contains('/')) {
    regexString = '(?:^|/)$regexString';
    if (dirOnly) {
      regexString += '/';
    } else {
      regexString += '(?:/|\$)';
    }
  } else if (pattern.startsWith('/')) {
    regexString = '^${regexString.substring('\\/'.length)}';
    if (dirOnly) {
      regexString += '/';
    } else {
      regexString += '(?:/|\$)';
    }
  } else {
    regexString = '(?:^|/)$regexString';
    if (dirOnly) {
      regexString += '/';
    } else {
      regexString += '(?:/|\$)';
    }
  }

  try {
    return RegExp(regexString);
  } catch (e) {
    print("警告: 无法将 gitignore 模式 '$pattern' 编译为 RegExp: $e");
    return RegExp(r'^$');
  }
}

// 检查给定的相对路径是否被 .gitignore 规则忽略
bool isIgnored(String relativePath, List<RegExp> gitignorePatterns) {
  // (之前的实现保持不变)
  relativePath = p.normalize(relativePath).replaceAll('\\', '/');
  if (relativePath.startsWith('/')) {
    relativePath = relativePath.substring(1);
  }

  for (final regex in gitignorePatterns) {
    if (regex.hasMatch(relativePath)) {
      return true;
    }
    // 检查目录匹配 (简化处理，因为 createGitignoreRegExp 已尝试处理)
    if (relativePath.endsWith('/') && regex.hasMatch(relativePath)) {
      return true;
    }
    // 检查目录路径是否匹配非目录模式 (简化)
    if (!relativePath.endsWith('/') && regex.hasMatch('$relativePath/')) {
      // 如果模式设计为只匹配目录（如 'dir/'），而路径是 'dir'，也可能匹配
      // 但这很难完美处理所有 gitignore 规则，建议使用库
    }
  }
  return false;
}

// 处理单个文件：检查是否忽略、是否文本、读取内容、移除注释并添加到缓冲区
// 添加了 skipExtensions 和 skipPatternsRegex 参数
Future<void> processFile(
    File file,
    String rootDir,
    StringBuffer buffer,
    List<RegExp> gitignorePatterns,
    Set<String> skipExtensions, // 新增
    List<RegExp> skipPatternsRegex, // 新增
    [String? normalizedRelativePath]) async { // 可选的相对路径

  // 如果未提供，则计算相对路径
  normalizedRelativePath ??=
      p.normalize(p.relative(file.path, from: rootDir)).replaceAll('\\', '/');
  final filename = p.basename(file.path);
  final extension = p.extension(filename).toLowerCase();

  // 0. 先检查是否根据后缀或模式跳过 (在主循环里已经检查了，这里是可选的冗余检查)
  // if (skipExtensions.contains(extension)) return;
  // for (final regex in skipPatternsRegex) {
  //   if (regex.hasMatch(filename)) return;
  // }

  // 1. 检查是否被 .gitignore 规则忽略
  if (isIgnored(normalizedRelativePath, gitignorePatterns)) {
    // print('Skipping ignored file: $normalizedRelativePath');
    return;
  }

  // 2. 检查是否可能是文本文件 (现在可以在主循环中提前跳过，这里保留作为最后防线)
  if (!isLikelyTextFile(file.path)) {
    print('跳过非文本文件: $normalizedRelativePath');
    return;
  }

  // 3. 读取内容并移除注释
  try {
    final bytes = await file.readAsBytes();
    if (bytes.contains(0)) {
      print('跳过可能是二进制的文件 (包含空字节): $normalizedRelativePath');
      return;
    }

    String content;
    try {
      content = utf8.decode(bytes);
    } catch (e) {
      print('跳过解码错误的文件 (可能不是 UTF-8 文本): $normalizedRelativePath. 错误: $e');
      return;
    }

    final cleanedContent = removeComments(content, file.path);

    if (cleanedContent.trim().isEmpty) {
      print('跳过（注释移除后）空文件: $normalizedRelativePath');
      return;
    }

    final language = getMarkdownLanguage(file.path);

    // 4. 追加到缓冲区
    print('添加文件: $normalizedRelativePath');
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('**$normalizedRelativePath**');
    buffer.writeln();
    buffer.writeln('```$language');
    buffer.writeln(cleanedContent.trim());
    buffer.writeln('```');
    buffer.writeln();
  } catch (e) {
    print('错误：读取文件 $normalizedRelativePath 失败: $e');
  }
}

// 判断文件是否可能是文本文件
bool isLikelyTextFile(String filePath) {
  // (之前的实现保持不变)
  final extension = p.extension(filePath).toLowerCase();
  final filename = p.basename(filePath).toLowerCase();
  if (textFileExtensions.contains(extension)) {
    return true;
  }
  if (textFileExtensions.contains(filename)) {
    return true;
  }
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
    case '.gradle': return 'groovy';
    case '.kt': case '.kts': return 'kotlin';
    case '.c': return 'c';
    case '.cpp': return 'cpp';
    case '.h': case '.hpp': return 'cpp';
    case '.cs': return 'csharp';
    case '.go': return 'go';
    case '.rs': return 'rust';
    case '.properties': return 'properties';
    case '.groovy': return 'groovy';
    case '.scala': return 'scala';
    case '.bat': return 'batch';
    case '.txt': return 'text';
    default:
      final filename = p.basename(filePath).toLowerCase();
      if (filename == 'dockerfile') return 'dockerfile';
      if (filename == 'makefile') return 'makefile';
      if (filename == 'jenkinsfile') return 'groovy';
      if (filename == 'pom.xml') return 'xml';
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
    if (const {
      '.java', '.js', '.ts', '.dart', '.c', '.cpp', '.h', '.hpp', '.cs',
      '.go', '.rs', '.scala', '.kt', '.groovy'
    }.contains(extension)) {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'/\*.*?\*/', multiLine: true, dotAll: true), '');
      cleanedContent = cleanedContent.replaceAll(RegExp(r'//.*'), '');
    } else if (const {'.xml', '.html', '.md', '.vue'}.contains(extension) ||
        filename == 'pom.xml') {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'<!--.*?-->', multiLine: true, dotAll: true), '');
    } else if (const {
      '.py', '.rb', '.sh', '.yaml', '.yml', '.properties', '.gitignore'
    }.contains(extension) ||
        const {'dockerfile', 'makefile'}.contains(filename)) {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'^\s*#.*|(?<=\s)#.*', multiLine: true), '');
    } else if (extension == '.sql') {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'/\*.*?\*/', multiLine: true, dotAll: true), '');
      cleanedContent = cleanedContent.replaceAll(RegExp(r'--.*'), '');
    } else if (extension == '.bat') {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'^\s*::.*|^\s*REM\s.*', caseSensitive: false, multiLine: true), '');
    }

    cleanedContent = cleanedContent
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  } catch (e) {
    print("警告: 从 $filePath 移除注释时出错: $e");
    return content;
  }
  return cleanedContent;
}
