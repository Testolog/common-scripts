# Data files

This project contains yaml, avsc, json, or sql files. Treat them as project files.

- Edit yaml, avsc, json, and sql files with `sd`, `dasel`, or `git apply`.
  - `sd` for one exact literal change (refused when the old text matches more than once).
  - `dasel` for a field change by selector in yaml, json, avsc, toml, xml, or csv. Avsc is JSON.
  - `git apply` for a multi-hunk change.
- Use LSP tools (`lsp_hover`, `lsp_definition`, `lsp_references`, `lsp_rename`) only when a server is
  already attached to that buffer (`yamlls`, `jsonls`). Do not start one.
- SQL has no rename server and no `ast-grep` grammar. Diagnostics and format come from `sqlfluff`
  in Neovim; edit SQL text with `sd` or `git apply`.
