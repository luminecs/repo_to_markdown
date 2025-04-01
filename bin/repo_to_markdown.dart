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
    ..addOption('skip-dirs', // 新增：跳过目录选项
        abbr: 'e', // 'e' for exclude
        defaultsTo: '',
        help: '需要跳过的目录列表，以逗号分隔 (例如 "build,dist,.idea")。')
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
  final currentDirectory = Directory.current;

  // 解析并规范化要跳过的目录
  final Set<String> skipDirs = skipDirsRaw
      .split(',')
      .map((d) => d.trim()) // 去除首尾空格
      .where((d) => d.isNotEmpty) // 过滤掉空字符串
      .map((d) => p.normalize(d).replaceAll('\\', '/')) // 规范化路径并统一使用 /
      .toSet(); // 使用 Set 以提高查找效率

  print('开始分析目录: ${currentDirectory.path}');
  print('项目类型: ${projectType ?? '未指定'}');
  print('输出文件: $outputFile');
  if (skipDirs.isNotEmpty) {
    print('将跳过以下目录及其内容: ${skipDirs.join(', ')}');
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
      // 检查 pom.xml 是否在要跳过的目录中
      final relativePomPath =
          p.relative(pomFile.path, from: currentDirectory.path);
      final normalizedRelativePomPath =
          p.normalize(relativePomPath).replaceAll('\\', '/');
      bool skipPom = false;
      for (final skipDir in skipDirs) {
        if (normalizedRelativePomPath == skipDir ||
            normalizedRelativePomPath.startsWith('$skipDir/')) {
          skipPom = true;
          print('警告: pom.xml 位于被跳过的目录中，将不被处理: $normalizedRelativePomPath');
          break;
        }
      }

      if (!skipPom &&
          !isIgnored(normalizedRelativePomPath, gitignorePatterns)) {
        // 同时检查gitignore
        await processFile(
            pomFile, currentDirectory.path, outputBuffer, gitignorePatterns);
        processedFiles.add(p.normalize(pomFile.path)); // 记录已处理
      } else if (!skipPom) {
        print('警告: pom.xml 被 .gitignore 规则忽略，将不被处理。');
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
    // 统一路径分隔符为 / 以便进行一致性检查
    final normalizedRelativePath =
        p.normalize(relativePath).replaceAll('\\', '/');

    // --- 新增：检查是否应跳过此路径（目录或文件） ---
    bool skip = false;
    for (final skipDir in skipDirs) {
      // 检查路径是否等于要跳过的目录，或者是否以 "要跳过的目录/" 开头
      if (normalizedRelativePath == skipDir ||
          normalizedRelativePath.startsWith('$skipDir/')) {
        skip = true;
        // print('Skipping path due to --skip-dirs: $normalizedRelativePath'); // 可选的调试输出
        break; // 找到一个匹配即可跳过
      }
    }
    if (skip) {
      continue; // 跳过当前实体（文件或目录）
    }
    // --- 跳过逻辑结束 ---

    if (entity is File) {
      final normalizedAbsolutePath = p.normalize(entity.path); // 使用绝对路径进行处理记录检查
      // 如果文件已被特殊处理过（例如 pom.xml），则跳过
      if (processedFiles.contains(normalizedAbsolutePath)) {
        continue;
      }
      // 使用上面计算好的 normalizedRelativePath 进行处理
      await processFile(entity, currentDirectory.path, outputBuffer,
          gitignorePatterns, normalizedRelativePath);
    }
    // 如果需要，以后可以在这里处理目录本身
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

// 打印使用说明
void printUsage(ArgParser parser) {
  print('用法: dart <脚本文件名>.dart [选项]');
  print('\n选项:');
  print(parser.usage);
}

// 加载 .gitignore 文件并返回正则表达式模式列表
Future<List<RegExp>> loadGitignore(
    Directory rootDir, String outputFileName) async {
  final gitignoreFile = File(p.join(rootDir.path, '.gitignore'));
  final patterns = <RegExp>[];
  // 始终忽略 .git 目录和输出文件本身
  patterns.add(createGitignoreRegExp('.git/')); // 忽略 .git 目录
  patterns.add(createGitignoreRegExp(outputFileName)); // 忽略输出文件本身

  if (await gitignoreFile.exists()) {
    try {
      final lines = await gitignoreFile.readAsLines();
      for (var line in lines) {
        line = line.trim();
        // 忽略空行和注释行
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

/// 将 gitignore 模式基础转换为 RegExp。
/// 这是一个简化的实现，可能无法覆盖所有边缘情况。
/// 为了完全兼容，建议使用像 `gitignore` 这样的专用包。
RegExp createGitignoreRegExp(String pattern) {
  // 1. 转义 RegExp 特殊字符
  var regexString =
      pattern.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (match) {
    return '\\${match.group(0)}'; // 在特殊字符前加反斜杠
  });

  // 2. 处理通配符 '*' 和 '**'
  // 将 '**/` 替换为 '.*/?' (匹配任意层级目录，包括零层) - 改进：用 `(?:.*/)?` 更精确
  regexString = regexString.replaceAll('**/', '(?:.*/)?');
  // 将 '**' 替换为 '.*' (匹配路径中的任何字符) - 需要小心处理，此简化替换可能不完美
  regexString = regexString.replaceAll('**', '.*');
  // 将单个 '*' 替换为 '[^/]*' (匹配除路径分隔符外的任意字符)
  regexString = regexString.replaceAll('*', '[^/]*');
  // 处理 '?' 通配符 (匹配单个非路径分隔符字符) - gitignore 规范中有，这里添加
  regexString = regexString.replaceAll('?', '[^/]');

  // 3. 处理开头/结尾的斜杠和目录匹配
  bool dirOnly = pattern.endsWith('/');
  if (dirOnly) {
    regexString = regexString.substring(
        0, regexString.length - '\\/'.length); // 移除结尾的转义斜杠
  }

  // 根据模式中是否包含斜杠来调整匹配行为
  if (!pattern.contains('/')) {
    // 如果模式中没有斜杠 (例如 'log.txt'), 它应该匹配任何目录下的同名文件或目录
    // (?:^|/) 确保它匹配路径的开头或紧跟在斜杠后面
    regexString = '(?:^|/)$regexString';
    // 如果是目录模式，确保它匹配目录（以 / 结尾或整个路径）
    if (dirOnly) {
      regexString += '/'; // 要求匹配以斜杠结尾
    } else {
      // 如果不是目录模式，它可以匹配文件或目录名
      regexString += '(?:/|\$)'; // 匹配斜杠或路径末尾
    }
  } else if (pattern.startsWith('/')) {
    // 如果模式以斜杠开头 (例如 '/log.txt'), 它只从项目根目录开始匹配
    regexString = '^${regexString.substring('\\/'.length)}'; // 从根开始匹配
    if (dirOnly) {
      regexString += '/';
    } else {
      regexString += '(?:/|\$)';
    }
  } else {
    // 如果模式包含斜杠但不以斜杠开头 (例如 'logs/debug.log')
    // 它可以在任何子目录中匹配
    regexString = '(?:^|/)$regexString'; // 允许在路径中的任何位置匹配
    if (dirOnly) {
      regexString += '/';
    } else {
      regexString += '(?:/|\$)';
    }
  }

  // print('Gitignore 模式 "$pattern" -> RegExp "$regexString"'); // 调试输出
  try {
    // 添加 (?m) 标记使 ^ 和 $ 匹配行的开始和结束（尽管在路径匹配中通常不需要）
    return RegExp(regexString);
  } catch (e) {
    print("警告: 无法将 gitignore 模式 '$pattern' 编译为 RegExp: $e");
    // 返回一个不匹配任何内容的正则表达式
    return RegExp(r'^$');
  }
}

// 检查给定的相对路径是否被 .gitignore 规则忽略
bool isIgnored(String relativePath, List<RegExp> gitignorePatterns) {
  // 再次规范化以确保安全，并使用 /
  relativePath = p.normalize(relativePath).replaceAll('\\', '/');
  // 移除开头的 / (如果存在) 因为模式通常不包含它
  if (relativePath.startsWith('/')) {
    relativePath = relativePath.substring(1);
  }

  // 检查完整路径是否匹配
  for (final regex in gitignorePatterns) {
    if (regex.hasMatch(relativePath)) {
      // print('Ignoring "$relativePath" due to pattern: ${regex.pattern}'); // 调试输出
      return true;
    }
    // 检查是否需要匹配目录（模式以 / 结尾）
    // 注意：上面的 `createGitignoreRegExp` 已经尝试将此逻辑纳入正则本身
  }

  // 如果路径是目录（例如 a/b/），也要检查是否有匹配非目录模式（例如 a/b）
  // 但这在纯粹基于文件路径字符串的正则匹配中很难完美实现，gitignore 包会处理得更好
  if (relativePath.endsWith('/')) {
    String pathWithoutTrailingSlash =
        relativePath.substring(0, relativePath.length - 1);
    for (final regex in gitignorePatterns) {
      // 重新检查不带尾部斜杠的路径，但需要确保正则不是只匹配目录的
      // 这是一个复杂点，简化处理：如果原始模式不以 / 结尾，则检查
      // if (!regex.pattern.endsWith('/\$') && regex.hasMatch(pathWithoutTrailingSlash)) { // 简化检查
      //     return true;
      // }
    }
  }

  return false;
}

// 处理单个文件：检查是否忽略、是否文本、读取内容、移除注释并添加到缓冲区
// 添加了 normalizedRelativePath 参数以避免重复计算
Future<void> processFile(File file, String rootDir, StringBuffer buffer,
    List<RegExp> gitignorePatterns,
    [String? normalizedRelativePath]) async {
  // 如果未提供，则计算相对路径
  normalizedRelativePath ??=
      p.normalize(p.relative(file.path, from: rootDir)).replaceAll('\\', '/');

  // 1. 检查是否被 .gitignore 规则忽略
  if (isIgnored(normalizedRelativePath, gitignorePatterns)) {
    // print('Skipping ignored file: $normalizedRelativePath'); // 可选调试输出
    return;
  }

  // 2. 检查是否可能是文本文件
  if (!isLikelyTextFile(file.path)) {
    print('跳过非文本文件: $normalizedRelativePath');
    return;
  }

  // 3. 读取内容并移除注释
  try {
    // 首先读取为字节，以检测潜在的非 UTF-8 问题
    final bytes = await file.readAsBytes();
    // 对二进制文件进行基本检查（例如，是否存在空字节）
    if (bytes.contains(0)) {
      print('跳过可能是二进制的文件 (包含空字节): $normalizedRelativePath');
      return;
    }

    String content;
    try {
      content = utf8.decode(bytes); // 尝试 UTF-8 解码
    } catch (e) {
      print('跳过解码错误的文件 (可能不是 UTF-8 文本): $normalizedRelativePath. 错误: $e');
      return;
    }

    final cleanedContent = removeComments(content, file.path);

    // 避免添加（注释移除后）空文件
    if (cleanedContent.trim().isEmpty) {
      print('跳过（注释移除后）空文件: $normalizedRelativePath');
      return;
    }

    final language = getMarkdownLanguage(file.path);

    // 4. 追加到缓冲区
    print('添加文件: $normalizedRelativePath');
    buffer.writeln('---'); // 分隔符
    buffer.writeln();
    // 在 Markdown 中使用正斜杠以保持一致性
    buffer.writeln('**$normalizedRelativePath**');
    buffer.writeln();
    buffer.writeln('```$language');
    buffer.writeln(cleanedContent.trim()); // 去除首尾空白
    buffer.writeln('```');
    buffer.writeln();
  } catch (e) {
    // 处理潜在的读取错误（权限等）
    print('错误：读取文件 $normalizedRelativePath 失败: $e');
  }
}

// 判断文件是否可能是文本文件（基于扩展名或文件名）
bool isLikelyTextFile(String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  final filename = p.basename(filePath).toLowerCase();

  // 检查常见文本文件扩展名
  if (textFileExtensions.contains(extension)) {
    return true;
  }
  // 通过名称检查常见的无扩展名文本文件
  if (textFileExtensions.contains(filename)) {
    return true;
  }

  // 基本检查：没有扩展名的文件可能是文本文件，但我们采取保守策略
  // if (extension.isEmpty) {
  //   // 可以检查文件的前几个字节是否为文本字符，但暂时保持简单
  // }

  return false;
}

// 根据文件路径获取 Markdown 代码块的语言标识符
String getMarkdownLanguage(String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  switch (extension) {
    case '.java':
      return 'java';
    case '.xml':
      return 'xml';
    case '.md':
      return 'markdown';
    case '.dart':
      return 'dart';
    case '.js':
      return 'javascript';
    case '.ts':
      return 'typescript';
    case '.jsx':
      return 'jsx';
    case '.tsx':
      return 'tsx';
    case '.py':
      return 'python';
    case '.rb':
      return 'ruby';
    case '.php':
      return 'php';
    case '.yaml':
    case '.yml':
      return 'yaml';
    case '.json':
      return 'json';
    case '.html':
      return 'html';
    case '.css':
      return 'css';
    case '.scss':
      return 'scss';
    case '.less':
      return 'less';
    case '.sh':
      return 'shell'; // 或者 bash
    case '.sql':
      return 'sql';
    case '.gradle':
      return 'groovy'; // 如果是 .kts 文件则应为 kotlin
    case '.kt':
    case '.kts':
      return 'kotlin';
    case '.c':
      return 'c';
    case '.cpp':
      return 'cpp';
    case '.h':
    case '.hpp':
      return 'cpp'; // C++ 的高亮通常也适用于 C 头文件
    case '.cs':
      return 'csharp';
    case '.go':
      return 'go';
    case '.rs':
      return 'rust';
    case '.properties':
      return 'properties';
    case '.groovy':
      return 'groovy';
    case '.scala':
      return 'scala';
    case '.bat':
      return 'batch'; // 或者 bat
    case '.txt':
      return 'text'; // 或者 plaintext
    default:
      // 对于没有扩展名的文件，检查文件名
      final filename = p.basename(filePath).toLowerCase();
      if (filename == 'dockerfile') return 'dockerfile';
      if (filename == 'makefile') return 'makefile';
      if (filename == 'jenkinsfile') return 'groovy'; // 通常是 Groovy
      // 明确处理 pom.xml，以防扩展名逻辑遗漏
      if (filename == 'pom.xml') return 'xml';
      return 'plaintext'; // 默认回退
  }
}

// 根据文件类型移除代码注释
String removeComments(String content, String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  final filename = p.basename(filePath).toLowerCase();
  String cleanedContent = content;

  try {
    // C 风格注释 (Java, JS, Dart, C++, C#, 等)
    if (const {
      '.java',
      '.js',
      '.ts',
      '.dart',
      '.c',
      '.cpp',
      '.h',
      '.hpp',
      '.cs',
      '.go',
      '.rs',
      '.scala',
      '.kt',
      '.groovy'
    }.contains(extension)) {
      // 移除块注释 /* ... */ (非贪婪模式)
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'/\*.*?\*/', multiLine: true, dotAll: true),
          ''); // 使用 dotAll 匹配换行符
      // 移除单行注释 // ...
      cleanedContent =
          cleanedContent.replaceAll(RegExp(r'//.*'), ''); // multiLine 默认行为即可
    }
    // XML/HTML 注释 <!-- ... -->
    else if (const {'.xml', '.html', '.md', '.vue'}.contains(extension) ||
        filename == 'pom.xml') {
      // 明确包含 pom.xml
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'<!--.*?-->', multiLine: true, dotAll: true), '');
      // 如果是 Markdown 文件，也要移除代码块中可能存在的 C 风格注释
      if (extension == '.md') {
        // 注意：这可能会误伤 Markdown 文本中出现的 // 或 /* */
        // 更安全的做法是仅在代码块内移除，但这需要更复杂的解析
        // cleanedContent = cleanedContent.replaceAll(RegExp(r'/\*.*?\*/', multiLine: true, dotAll: true), '');
        // cleanedContent = cleanedContent.replaceAll(RegExp(r'//.*'), '');
      }
    }
    // 井号注释 (Python, Ruby, Shell, Yaml, Dockerfile, 等)
    else if (const {
          '.py',
          '.rb',
          '.sh',
          '.yaml',
          '.yml',
          '.properties',
          '.gitignore'
        }.contains(extension) ||
        const {'dockerfile', 'makefile'}.contains(filename)) {
      // 重要：仅匹配行首或空白字符后的 '#'，以避免移除 URL 或其他字符串中的 '#'
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'^\s*#.*|(?<=\s)#.*', multiLine: true), '');
    }
    // SQL 注释 -- ... 和 /* ... */
    else if (extension == '.sql') {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'/\*.*?\*/', multiLine: true, dotAll: true), '');
      cleanedContent = cleanedContent.replaceAll(RegExp(r'--.*'), '');
    }
    // Batch 文件注释 REM 或 ::
    else if (extension == '.bat') {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'^\s*::.*|^\s*REM\s.*',
              caseSensitive: false, multiLine: true),
          '');
    }

    // 移除因删除注释而产生的空行
    cleanedContent = cleanedContent
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  } catch (e) {
    print("警告: 从 $filePath 移除注释时出错 (正则表达式可能无效或过于复杂): $e");
    // 出错时返回原始内容
    return content;
  }

  return cleanedContent;
}
