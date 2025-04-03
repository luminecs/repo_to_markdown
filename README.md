A sample command-line application with an entrypoint in `bin/`, library code
in `lib/`, and example unit test in `test/`.

```shell
dart compile exe bin/repo_to_markdown.dart -o bin/repo_to_markdown
sudo mv bin/repo_to_markdown /usr/local/bin/
repo_to_markdown --type java-maven
repo_to_markdown --output my_project.md
repo_to_markdown --help
repo_to_markdown --skip-dirs=build,node_modules --output my_project.md
# 或者使用缩写
repo_to_markdown -e build,node_modules
# 如果还想指定输出文件名
repo_to_markdown -e build,node_modules -o my_project_dump.md

# 跳过所有 .log 和 .tmp 文件
repo_to_markdown --skip-extensions .log,.tmp -o repo.md
# 跳过所有以 Test 开头的 Java 文件 (Test*.java)
repo_to_markdown --skip-patterns "Test*.java" -o repo.md
# 跳过所有以 _backup 结尾的任何文件 (*_backup.*) 和所有 .cache 文件
repo_to_markdown --skip-patterns "*_backup.*,*.cache" -o repo.md
# 跳过 build 目录、.class 文件以及所有 Example*.java 文件
repo_to_markdown --skip-dirs build --skip-extensions .class --skip-patterns "Example*.java" -o repo.md
```
