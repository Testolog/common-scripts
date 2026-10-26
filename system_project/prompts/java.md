# Java projects

This project contains Java (`pom.xml`, `build.gradle`, `build.gradle.kts`, or `project_type` includes `java`).

- Rename a Java symbol (class, method, field, variable, package) with `lsp_rename` through the attached
  `jdtls` server. Do not rename with `sd`, sed, or awk.
- Use `ast-grep` for a repeated syntactic rewrite across files, for example
  `sg -p '<pattern>' -l java -r '<rewrite>'`.
- Use `sd` or `git apply` for a one-off text change.
- If `jdtls` is not attached or cannot rename, say so and fall back to `sd`, `dasel`, or `git apply`.
