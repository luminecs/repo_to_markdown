import 'dart:convert'; // For utf8 decoding
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

// --- Configuration ---
const String outputFileName = 'project_content.md';
// Add more text file extensions as needed
const Set<String> textFileExtensions = {
  '.txt',
  '.md',
  '.markdown',
  '.java',
  '.groovy',
  '.scala',
  '.kt',
  // JVM
  '.xml',
  '.yaml',
  '.yml',
  '.json',
  '.properties',
  '.gradle',
  // Config/Data
  '.dart',
  '.js',
  '.ts',
  '.jsx',
  '.tsx',
  // Web/Dart
  '.py',
  '.rb',
  '.php',
  // Scripting
  '.c',
  '.cpp',
  '.h',
  '.hpp',
  '.cs',
  // C-like
  '.go',
  '.rs',
  // Others
  '.html',
  '.css',
  '.scss',
  '.less',
  // Web frontend
  '.sh',
  '.bat',
  // Shell
  '.sql',
  // Add files with no extension that are often text (like Dockerfile, Jenkinsfile)
  'dockerfile',
  'jenkinsfile',
  'makefile',
  'pom',
  // Check filename itself
  '.gitignore',
  '.gitattributes',
  // Git specific text files
};

// --- Main Logic ---
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('type',
        abbr: 't', help: 'Specify the project type (e.g., java-maven).')
    ..addOption('output',
        abbr: 'o',
        defaultsTo: outputFileName,
        help: 'Output Markdown file name.')
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Show this help message.');

  ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } catch (e) {
    print('Error parsing arguments: ${e}');
    printUsage(parser);
    exit(1);
  }

  if (argResults['help'] as bool) {
    printUsage(parser);
    exit(0);
  }

  final projectType = argResults['type'] as String?;
  final outputFile = argResults['output'] as String;
  final currentDirectory = Directory.current;

  print('Starting analysis in directory: ${currentDirectory.path}');
  print('Project type: ${projectType ?? 'Not specified'}');
  print('Output file: $outputFile');

  final gitignorePatterns = await loadGitignore(currentDirectory);
  final outputBuffer = StringBuffer();
  final processedFiles = <String>{}; // Keep track of files already added

  // --- Project Type Specific Handling ---
  if (projectType == 'java-maven') {
    print('Processing as java-maven project...');
    final pomFile = File(p.join(currentDirectory.path, 'pom.xml'));
    if (await pomFile.exists()) {
      print('Found pom.xml, adding it first.');
      await processFile(
          pomFile, currentDirectory.path, outputBuffer, gitignorePatterns);
      processedFiles.add(p.normalize(pomFile.path));
    } else {
      print(
          'Warning: Project type is java-maven, but pom.xml not found in the root.');
    }
  }

  // --- Recursive File Traversal ---
  print('Scanning files...');
  await for (final entity
      in currentDirectory.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      final normalizedPath = p.normalize(entity.path);
      // Skip if already processed (like pom.xml)
      if (processedFiles.contains(normalizedPath)) {
        continue;
      }
      await processFile(
          entity, currentDirectory.path, outputBuffer, gitignorePatterns);
    }
    // Optionally handle directories if needed later
  }

  // --- Write Output ---
  final outFile = File(p.join(currentDirectory.path, outputFile));
  try {
    await outFile.writeAsString(outputBuffer.toString());
    print('\nSuccessfully wrote project content to ${outFile.path}');
  } catch (e) {
    print('\nError writing output file: $e');
    exit(1);
  }
}

// --- Helper Functions ---

void printUsage(ArgParser parser) {
  print('Usage: dart bin/project_lister.dart [options]');
  print('\nOptions:');
  print(parser.usage);
}

Future<List<RegExp>> loadGitignore(Directory rootDir) async {
  final gitignoreFile = File(p.join(rootDir.path, '.gitignore'));
  final patterns = <RegExp>[];
  // Always ignore .git directory and the output file itself
  patterns.add(createGitignoreRegExp('.git/')); // Ignore .git directory
  patterns.add(createGitignoreRegExp(outputFileName)); // Ignore the output file

  if (await gitignoreFile.exists()) {
    try {
      final lines = await gitignoreFile.readAsLines();
      for (var line in lines) {
        line = line.trim();
        // Ignore empty lines and comments
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        patterns.add(createGitignoreRegExp(line));
      }
      print('Loaded .gitignore patterns.');
    } catch (e) {
      print('Warning: Could not read .gitignore file: $e');
    }
  } else {
    print('No .gitignore file found in the root directory.');
  }
  return patterns;
}

/// Basic conversion of gitignore pattern to RegExp.
/// This is a simplified implementation and may not cover all edge cases.
/// For full compliance, a dedicated package like `gitignore` is recommended.
RegExp createGitignoreRegExp(String pattern) {
  // 1. Escape RegExp special characters
  var regexString =
      pattern.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (match) {
    return '\\${match.group(0)}';
  });

  // 2. Handle wildcards '*' and '**'
  // Replace '**/' with '.*/?' (match any directory including none)
  regexString = regexString.replaceAll('**/', '.*/?');
  // Replace '**' not at start/end with '.*' (match anything within path)
  // Be careful not to replace things like `a**b` -> `a.*b` correctly. A simple replace might be okay for now.
  regexString = regexString.replaceAll('**', '.*');
  // Replace single '*' with '[^/]*' (match any char except path sep)
  regexString = regexString.replaceAll('*', '[^/]*');

  // 3. Handle leading/trailing slashes and directory matching
  bool dirOnly = pattern.endsWith('/');
  if (dirOnly) {
    regexString = regexString.substring(
        0, regexString.length - 1); // Remove trailing / for regex
  }

  if (!pattern.contains('/')) {
    // If no slash, match anywhere in the path
    // Example: 'log.txt' -> match 'log.txt', 'subdir/log.txt'
    // We need to check basename or add prefix `(^|/)`
    // Let's keep it simpler: match if the pattern is contained within the relative path segment
    // This isn't perfect gitignore behaviour but simpler to implement.
    // Better: Check if relativePath.endsWith(pattern) or contains('/' + pattern)
    regexString =
        '(^|/)$regexString(/|\$)'; // Crude attempt to match filename part
  } else if (pattern.startsWith('/')) {
    // Starts with '/', match only from root
    regexString = '^${regexString.substring(1)}';
  } else {
    // Contains slash but not starting with it, match anywhere
    // Example 'logs/debug.log' -> match 'logs/debug.log', 'a/logs/debug.log'
    // The basic regex might work okay here if '*' handled correctly.
    // Add (^|/) to be slightly more robust?
    regexString = '(^|/)$regexString';
  }

  // If dirOnly, ensure it matches a directory (ends with / or is the whole path)
  // This is tricky to enforce perfectly with regex on the file path alone.
  // We'll rely on checking entity type later if needed, or ignore for now.

  // print('Gitignore pattern "$pattern" -> RegExp "$regexString"'); // Debugging
  try {
    return RegExp(regexString);
  } catch (e) {
    print(
        "Warning: Could not compile gitignore pattern '$pattern' to RegExp: $e");
    // Return a regex that matches nothing
    return RegExp(r'^$');
  }
}

bool isIgnored(String relativePath, List<RegExp> gitignorePatterns) {
  // Normalize path separators for consistency, although Dart usually handles this
  relativePath = p.normalize(relativePath).replaceAll('\\', '/');
  if (relativePath.startsWith('/')) {
    relativePath = relativePath.substring(1);
  }

  for (final regex in gitignorePatterns) {
    if (regex.hasMatch(relativePath)) {
      // print('Ignoring "$relativePath" due to pattern: ${regex.pattern}'); // Debugging
      return true;
    }
  }
  return false;
}

Future<void> processFile(File file, String rootDir, StringBuffer buffer,
    List<RegExp> gitignorePatterns) async {
  final relativePath = p.relative(file.path, from: rootDir);
  final normalizedRelativePath =
      p.normalize(relativePath).replaceAll('\\', '/');

  // 1. Check if ignored by .gitignore
  if (isIgnored(normalizedRelativePath, gitignorePatterns)) {
    // print('Skipping ignored file: $relativePath');
    return;
  }

  // 2. Check if it's likely a text file
  if (!isLikelyTextFile(file.path)) {
    print('Skipping non-text file: $relativePath');
    return;
  }

  // 3. Read content and remove comments
  try {
    // Read as bytes first to detect potential non-UTF8 issues
    final bytes = await file.readAsBytes();
    // Basic check for binary files (e.g., presence of null bytes)
    if (bytes.contains(0)) {
      print('Skipping likely binary file (contains null bytes): $relativePath');
      return;
    }

    String content;
    try {
      content = utf8.decode(bytes); // Try UTF-8 decoding
    } catch (e) {
      print(
          'Skipping file with decoding error (likely not UTF-8 text): $relativePath. Error: $e');
      return;
    }

    final cleanedContent = removeComments(content, file.path);

    // Avoid adding empty files (after comment removal)
    if (cleanedContent.trim().isEmpty) {
      print('Skipping empty file (after comment removal): $relativePath');
      return;
    }

    final language = getMarkdownLanguage(file.path);

    // 4. Append to buffer
    print('Adding file: $relativePath');
    buffer.writeln('---'); // Separator
    buffer.writeln();
    buffer.writeln(
        '**${relativePath.replaceAll('\\', '/')}**'); // Use forward slashes for Markdown consistency
    buffer.writeln();
    buffer.writeln('```$language');
    buffer.writeln(cleanedContent.trim()); // Trim leading/trailing whitespace
    buffer.writeln('```');
    buffer.writeln();
  } catch (e) {
    // Handle potential read errors (permissions, etc.)
    print('Error reading file $relativePath: $e');
  }
}

bool isLikelyTextFile(String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  final filename = p.basename(filePath).toLowerCase();

  // Check common text extensions
  if (textFileExtensions.contains(extension)) {
    return true;
  }
  // Check common extensionless text files by name
  if (textFileExtensions.contains(filename)) {
    return true;
  }

  // Basic check: files without extensions could be text, but let's be conservative
  // if (extension.isEmpty) {
  //   // Could check first few bytes for text characters, but keep it simple for now
  // }

  return false;
}

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
      return 'shell'; // or bash
    case '.sql':
      return 'sql';
    case '.gradle':
      return 'groovy'; // or kotlin if .kts
    case '.kt':
    case '.kts':
      return 'kotlin';
    case '.c':
      return 'c';
    case '.cpp':
      return 'cpp';
    case '.h':
    case '.hpp':
      return 'cpp'; // Often C++ highlighting works for C headers
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
      return 'batch'; // or bat
    case '.txt':
      return 'text'; // or plaintext
    default:
      // For files without extension, check filename
      final filename = p.basename(filePath).toLowerCase();
      if (filename == 'dockerfile') return 'dockerfile';
      if (filename == 'makefile') return 'makefile';
      if (filename == 'jenkinsfile') return 'groovy'; // Often Groovy
      if (filename == 'pom.xml')
        return 'xml'; // Explicitly handle pom.xml if extension logic missed it
      return 'plaintext'; // Default fallback
  }
}

String removeComments(String content, String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  String cleanedContent = content;

  try {
    // C-style comments (Java, JS, Dart, C++, C#, etc.)
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
      // Remove block comments /* ... */ (non-greedy)
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
      // Remove single-line comments // ...
      cleanedContent =
          cleanedContent.replaceAll(RegExp(r'//.*', multiLine: true), '');
    }
    // XML/HTML comments <!-- ... -->
    else if (const {'.xml', '.html', '.md', '.vue'}.contains(extension) ||
        p.basename(filePath).toLowerCase() == 'pom.xml') {
      // Include pom.xml here explicitly
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'<!--[\s\S]*?-->', multiLine: true), '');
      // Also remove // and /* */ if it's markdown, as code blocks inside might use them
      if (extension == '.md') {
        cleanedContent = cleanedContent.replaceAll(
            RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
        cleanedContent =
            cleanedContent.replaceAll(RegExp(r'//.*', multiLine: true), '');
      }
    }
    // Hash comments (Python, Ruby, Shell, Yaml, Dockerfile, etc.)
    else if (const {
          '.py',
          '.rb',
          '.sh',
          '.yaml',
          '.yml',
          '.properties',
          '.gitignore'
        }.contains(extension) ||
        const {'dockerfile', 'makefile'}
            .contains(p.basename(filePath).toLowerCase())) {
      // Important: Match '#' only at the beginning of a line or after whitespace
      // to avoid removing parts of URLs or other strings.
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'^\s*#.*|(?<=\s)#.*', multiLine: true), '');
    }
    // SQL comments -- ... and /* ... */
    else if (extension == '.sql') {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
      cleanedContent =
          cleanedContent.replaceAll(RegExp(r'--.*', multiLine: true), '');
    }
    // Batch file comments REM or ::
    else if (extension == '.bat') {
      cleanedContent = cleanedContent.replaceAll(
          RegExp(r'^\s*::.*|^\s*REM\s.*',
              caseSensitive: false, multiLine: true),
          '');
    }

    // Remove empty lines that might result from comment removal
    cleanedContent = cleanedContent
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  } catch (e) {
    print(
        "Warning: Error removing comments from $filePath (Regex might be invalid or too complex): $e");
    // Return original content on error
    return content;
  }

  return cleanedContent;
}
