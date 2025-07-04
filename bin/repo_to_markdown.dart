import 'dart:convert'; // 用于 utf8 解码
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

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
  '.vue',
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
  '.jte', // jte 模板
};

// --- 主要逻辑 ---
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
  // 指定配置文件路径
    ..addOption('config',
        abbr: 'c',
        help: '指定一个 YAML 配置文件路径。如果未指定，将自动尝试加载当前目录的 "repo_config.yml"。')
    ..addOption('type', abbr: 't', help: '指定项目类型 (例如, java-maven)。')
    ..addOption('output',
        abbr: 'o',
        defaultsTo: outputFileNameDefault, // 使用默认值
        help: '输出 Markdown 文件名。')
    ..addOption('skip-dirs', // 跳过目录选项
        abbr: 'e', // 'e' for exclude
        defaultsTo: '',
        help: '需要跳过的目录列表，以逗号分隔 (例如 "build,dist,.idea")。')
    ..addOption('skip-extensions', // 跳过后缀选项
        abbr: 'x', // 'x' for extensions
        defaultsTo: '',
        help: '需要跳过的文件后缀列表，以逗号分隔，带点 (例如 ".kt,.log")。')
    ..addOption('skip-patterns', // 跳过通配符模式选项
        abbr: 'p', // 'p' for patterns
        defaultsTo: '',
        help: '需要跳过的文件名通配符模式列表，以逗号分隔 (例如 "Test*.java,*.tmp")。')
    ..addOption('keep-comments-config',
        abbr: 'k',
        help: '指定一个配置文件(.txt)，文件中的路径（文件或目录）将保留注释。此选项用于向后兼容或补充YAML配置。')
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

  // --- 优化配置文件加载逻辑 ---

  // 1. 决定要加载的配置文件路径
  String? configFilePath;
  bool isDefaultConfigFile = false; // 标记是否正在使用默认配置文件路径

  if (argResults.wasParsed('config')) {
    // 优先级 1: 用户通过命令行明确指定了配置文件
    configFilePath = argResults['config'] as String?;
  } else {
    // 优先级 2: 用户未指定，自动使用默认路径
    configFilePath = 'repo_config.yml';
    isDefaultConfigFile = true;
  }

  // 2. 加载 YAML 配置文件
  final Map<String, dynamic> config = {};
  if (configFilePath != null && configFilePath.isNotEmpty) {
    final configFile = File(configFilePath);
    if (await configFile.exists()) {
      print('正在从配置文件加载设置: $configFilePath');
      try {
        final yamlString = await configFile.readAsString();
        final yamlContent = loadYaml(yamlString);
        if (yamlContent is YamlMap) {
          // 将 YamlMap 转换为标准的 Dart Map
          config.addAll(Map<String, dynamic>.from(yamlContent));
        }
      } catch (e) {
        print('警告: 读取或解析 YAML 配置文件 $configFilePath 时出错: $e');
      }
    } else {
      // 如果文件不存在，根据情况给出不同提示
      if (!isDefaultConfigFile) {
        // 用户明确指定了文件但找不到，这是一个需要提醒的警告
        print('警告: 指定的配置文件 $configFilePath 不存在，将忽略。');
      } else {
        // 默认文件找不到是正常情况，无需警告，可以静默处理或给一个信息提示
        // print('信息: 未在当前目录找到默认配置文件 "repo_config.yml"。');
      }
    }
  }

  // 3. 按优先级确定最终配置值 (此部分逻辑不变)
  // 优先级规则: 命令行参数 > YAML 配置 > 默认值

  // 辅助函数，用于处理从 YAML 读取的列表或字符串
  String _getStringFromConfig(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).join(',');
    }
    return value as String? ?? '';
  }

  // 获取最终配置值
  final projectType = argResults.wasParsed('type')
      ? argResults['type'] as String?
      : config['type'] as String? ?? (argResults['type'] as String?);

  final outputFile = argResults.wasParsed('output')
      ? argResults['output'] as String
      : config['output'] as String? ?? argResults['output'] as String;

  final skipDirsRaw = argResults.wasParsed('skip-dirs')
      ? argResults['skip-dirs'] as String
      : _getStringFromConfig(config['skip-dirs'] ?? argResults['skip-dirs']);

  final skipExtensionsRaw = argResults.wasParsed('skip-extensions')
      ? argResults['skip-extensions'] as String
      : _getStringFromConfig(config['skip-extensions'] ?? argResults['skip-extensions']);

  final skipPatternsRaw = argResults.wasParsed('skip-patterns')
      ? argResults['skip-patterns'] as String
      : _getStringFromConfig(config['skip-patterns'] ?? argResults['skip-patterns']);

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

  // --- 整合所有需要保留注释的路径 (此部分逻辑不变) ---

  // 1. 初始化一个集合来存放所有需要保留注释的路径
  final Set<String> keepCommentsPaths = {};

  // 2. 从 YAML 配置中的 `keep-comments-paths` 列表加载路径
  if (config['keep-comments-paths'] is YamlList) {
    print('正在从 YAML 配置中的 `keep-comments-paths` 加载路径...');
    final List<dynamic> pathsFromYaml = config['keep-comments-paths'];
    for (final path in pathsFromYaml) {
      final trimmedPath = path.toString().trim();
      if (trimmedPath.isNotEmpty) {
        // 规范化路径并添加到集合中
        keepCommentsPaths.add(p.normalize(trimmedPath).replaceAll('\\', '/'));
      }
    }
  }

  // 3. 从 `--keep-comments-config` 文件加载路径 (为了向后兼容和命令行补充)
  // 这个值可能是由命令行参数 `--keep-comments-config` 或旧的YAML键 `keep-comments-config` 提供的。
  final keepCommentsConfigFile = argResults.wasParsed('keep-comments-config')
      ? argResults['keep-comments-config'] as String?
      : config['keep-comments-config'] as String?;

  if (keepCommentsConfigFile != null && keepCommentsConfigFile.isNotEmpty) {
    final configFile = File(keepCommentsConfigFile);
    if (await configFile.exists()) {
      print('正在从文件 $keepCommentsConfigFile 加载额外的保留注释路径...');
      try {
        final lines = await configFile.readAsLines();
        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isNotEmpty && !trimmedLine.startsWith('#')) {
            // 规范化路径并添加到同一个集合中
            keepCommentsPaths.add(p.normalize(trimmedLine).replaceAll('\\', '/'));
          }
        }
      } catch (e) {
        print('警告: 读取或解析保留注释配置文件 $keepCommentsConfigFile 时出错: $e');
      }
    } else {
      print('警告: 指定的保留注释配置文件 $keepCommentsConfigFile 不存在。');
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
  if (keepCommentsPaths.isNotEmpty) {
    print('将对以下路径（及其子路径）保留注释: ${keepCommentsPaths.join(', ')}');
  }


  // 加载 .gitignore 规则，并始终忽略输出文件本身和 .git 目录
  final gitignorePatterns = await loadGitignore(currentDirectory, outputFile, configFilePath);
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
        bool keepCommentsForPom = false;
        for (final keepPath in keepCommentsPaths) {
          if (normalizedRelativePomPath == keepPath) {
            keepCommentsForPom = true;
            break;
          }
        }
        await processFile(
            pomFile, currentDirectory.path, outputBuffer, gitignorePatterns, skipExtensions, skipPatternsRegex, keepCommentsForPom, normalizedRelativePomPath);
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
      processedFiles, // 传递已处理集合，避免重复处理 (如 pom.xml)
      keepCommentsPaths // 传递保留注释的路径集合
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

/// 手动递归处理目录
Future<void> processDirectoryRecursively(
    Directory directory,
    String rootDir,
    StringBuffer buffer,
    Set<String> skipDirs,
    List<RegExp> gitignorePatterns,
    Set<String> skipExtensions,
    List<RegExp> skipPatternsRegex,
    Set<String> processedFiles, // 跟踪已处理文件
    Set<String> keepCommentsPaths // 接收保留注释的路径集合
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
      // 对于子目录，递归调用，并传递路径集合
      await processDirectoryRecursively(
          entity as Directory,
          rootDir,
          buffer,
          skipDirs,
          gitignorePatterns,
          skipExtensions,
          skipPatternsRegex,
          processedFiles,
          keepCommentsPaths); // 在递归中继续传递
    } else if (entity is File) {
      final normalizedAbsolutePath = p.normalize(entity.path);
      // 如果文件已被特殊处理过（例如 pom.xml），则跳过
      if (processedFiles.contains(normalizedAbsolutePath)) {
        continue;
      }

      // 检查文件是否应被跳过
      if (!shouldSkip(normalizedRelativePath, null, gitignorePatterns, skipExtensions, skipPatternsRegex, isDirectory: false)) {
        // 检查此文件是否需要保留注释
        bool shouldPreserveComments = false;
        // 遍历所有需要保留注释的路径规则
        for (final keepPath in keepCommentsPaths) {
          // 检查是精确的文件匹配，还是位于需要保留注释的目录下
          if (normalizedRelativePath == keepPath || normalizedRelativePath.startsWith('$keepPath/')) {
            shouldPreserveComments = true;
            break; // 找到匹配规则后即可中断循环
          }
        }

        // 处理文件，并传入是否保留注释的标志
        await processFile(entity, rootDir, buffer, gitignorePatterns, skipExtensions, skipPatternsRegex, shouldPreserveComments, normalizedRelativePath);
      } else {
        // print('Skipping file due to rules: $normalizedRelativePath'); // 可选调试输出
      }
    }
  }
}


/// 统一的跳过逻辑检查函数
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
  if (isDirectory && skipDirs != null && skipDirs.isNotEmpty) {
    // --- **修改点：实现递归目录排除** ---
    // 将相对路径拆分为各个部分（例如 "a/b/c" -> ["a", "b", "c"]）
    final pathComponents = p.split(normalizedRelativePath);
    // 检查路径的任何一个部分是否在要跳过的目录名集合中
    for (final component in pathComponents) {
      if (skipDirs.contains(component)) {
        // 只要路径中任何一级目录名匹配，就跳过整个目录
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
    Directory rootDir, String outputFileName, String? configFileName) async {
  // (之前的实现保持不变, 但添加了 .git/ 的忽略)
  final gitignoreFile = File(p.join(rootDir.path, '.gitignore'));
  final patterns = <RegExp>[];
  // 始终忽略 .git 目录和输出文件本身
  patterns.add(createGitignoreRegExp('.git/')); // 明确忽略 .git 目录
  patterns.add(createGitignoreRegExp(outputFileName));
  if (configFileName != null && configFileName.isNotEmpty) {
    patterns.add(createGitignoreRegExp(p.basename(configFileName))); // 忽略配置文件本身
  }

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
Future<void> processFile(
    File file,
    String rootDir,
    StringBuffer buffer,
    List<RegExp> gitignorePatterns, // 仍然需要检查单个文件的 gitignore 规则
    Set<String> skipExtensions, // 保留用于isLikelyTextFile和语言确定可能需要
    List<RegExp> skipPatternsRegex, // 保留，以防万一
    bool keepComments, // 是否保留此文件的注释
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

  // 3. 读取内容并根据条件移除注释
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

    // 根据 keepComments 标志决定是否移除注释
    String cleanedContent;
    if (keepComments) {
      // 如果标志为 true，则保留原始内容（包括注释）
      cleanedContent = content;
    } else {
      // 否则，执行移除注释的逻辑
      cleanedContent = removeComments(content, file.path);
    }

    // 如果处理后内容为空，则跳过
    if (cleanedContent.trim().isEmpty) {
      // print('跳过（注释移除后）空文件: $normalizedRelativePath');
      return;
    }

    // 获取 Markdown 语言标识符
    final language = getMarkdownLanguage(file.path);

    // --- 缓冲区写入逻辑修改开始 ---
    // 4. 追加到缓冲区
    if (keepComments) {
      print('添加文件 (保留注释): $normalizedRelativePath'); // 确认添加并指明保留了注释
    } else {
      print('添加文件: $normalizedRelativePath'); // 确认添加
    }

    // 关键点: 仅在缓冲区非空时（即，这不是第一个文件）才添加分隔空行。
    // 这可以同时解决文件开头多一个空行和文件间多一个空行的问题。
    if (buffer.isNotEmpty) {
      buffer.writeln(); // 在文件块之间添加一个空行作为分隔符
    }

    buffer.writeln('**$normalizedRelativePath**'); // 文件路径作为标题
    buffer.writeln(); // 在标题和代码块之间保留一个空行
    buffer.writeln('```$language'); // 代码块开始，指定语言
    buffer.writeln(cleanedContent.trim()); // 清理后的内容
    buffer.writeln('```'); // 代码块结束

    // 之前的代码在这里和文件块的开头都有 buffer.writeln()，导致了重复。
    // 将分隔逻辑统一放到文件块的开头后，此处就不再需要了。
    // --- 缓冲区写入逻辑修改结束 ---

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
    case '.vue': return 'vue'; // 为 Vue 文件指定语言标识符
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
  final extension = p.extension(filePath).toLowerCase();
  final filename = p.basename(filePath).toLowerCase();
  String cleanedContent = content;

  try {
    // 为 Vue 文件提供专门的注释移除逻辑
    if (extension == '.vue') {
      // 1. 移除 HTML 风格的注释 <!-- ... --> (用于 <template>)
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'<!--.*?-->', multiLine: true, dotAll: true), '');
      // 2. 移除 C 风格的块注释 /* ... */ (用于 <script> 和 <style>)
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'/\*.*?\*/', multiLine: true, dotAll: true), '');
      // 3. 移除 C 风格的行注释 // ... (用于 <script>)
      cleanedContent = cleanedContent.replaceAll(RegExp(r'(?<!:)\/\/.*'), '');
    }
    // C 风格注释 (Java, JS, TS, Dart, C, C++, C#, Go, Rust, Scala, Kotlin, Groovy)
    // 注意这里的 'else if' 确保 Vue 文件不会被再次处理
    else if (const {
      '.java', '.js', '.ts', '.dart', '.c', '.cpp', '.h', '.hpp', '.cs',
      '.go', '.rs', '.scala', '.kt', '.groovy'
    }.contains(extension)) {
      // 旧方法会错误地处理字符串中的注释标记，例如在 "a*/*b" 中。
      // 新方法使用一个正则表达式一次性匹配字符串、块注释和行注释。
      // 然后，在替换逻辑中，我们只移除注释，而保留字符串，从而避免问题。
      final cStyleRegex = RegExp(
        // 第1组: 匹配双引号字符串。处理内部的转义字符，例如 \"。
        r'("(?:\\[\s\S]|[^"\\])*")'
        // 第2组: 匹配单引号字符串。同样处理转义字符。
        r"|('(?:\\[\s\S]|[^'\\])*')"
        // 第3组: 匹配C风格的块注释 /* ... */。[\s\S] 用来匹配包括换行符在内的任何字符。
        r'|(/\*[\s\S]*?\*/)'
        // 第4组: 匹配C风格的行注释 // ...。(?<!:)确保不会匹配 "http://"。
        r'|((?<!:)\/\/.*)',
        multiLine: true,
      );

      cleanedContent = cleanedContent.replaceAllMapped(cStyleRegex, (match) {
        // 如果第3组 (块注释) 或第4组 (行注释) 不为null，说明匹配到了注释。
        if (match.group(3) != null || match.group(4) != null) {
          // 是注释，用空字符串替换，即删除。
          return '';
        } else {
          // 是字符串字面量，原样返回。
          return match.group(0)!;
        }
      });
    }
    // XML/HTML/Markdown 注释 <!-- ... -->
    else if (const {'.xml', '.html', '.md'}.contains(extension) ||
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
      // SQL中的块注释 /*...*/ 也存在同样的问题，可能错误地处理字符串中的注释标记。
      final sqlRegex = RegExp(
        // 第1组: 匹配单引号字符串 '...'。SQL使用两个单引号 '' 来表示字符串中的一个单引号。
        r"('(''|[^'])*')"
        // 第2组: 匹配（某些方言中的）双引号标识符 "..."。
        r'|("(""|[^"])*")'
        // 第3组: 匹配C风格的块注释 /* ... */。
        r'|(/\*[\s\S]*?\*/)'
        // 第4组: 匹配SQL风格的行注释 -- ...
        r'|(--.*)',
        multiLine: true,
      );
      cleanedContent = cleanedContent.replaceAllMapped(sqlRegex, (match) {
        // 如果第3组 (块注释) 或第4组 (行注释) 不为null，说明匹配到了注释。
        if (match.group(3) != null || match.group(4) != null) {
          // 是注释，用空字符串替换，即删除。
          return '';
        } else {
          // 是字符串字面量或带引号的标识符，原样返回。
          return match.group(0)!;
        }
      });
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
