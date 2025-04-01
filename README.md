A sample command-line application with an entrypoint in `bin/`, library code
in `lib/`, and example unit test in `test/`.

```shell
dart compile exe bin/repo_to_markdown.dart -o bin/repo_to_markdown
sudo mv bin/repo_to_markdown /usr/local/bin/
bin/repo_to_markdown --type java-maven
bin/repo_to_markdown --output my_project.md
bin/repo_to_markdown --help
```
