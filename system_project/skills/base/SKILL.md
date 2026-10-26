# Base skill

Work in small, verifiable steps.

1. Locate the code with `fsearch` before changing it. Read the surrounding file.
2. Pick the narrowest edit tool: `lsp_rename` for symbols, `sd` for one literal change, `dasel` for a
   structured field, `ast-grep` for a repeated pattern, `git apply` for a multi-hunk diff.
3. After an edit, re-read the changed region and check diagnostics from the attached language server.
4. Keep an open task list in your answer. Mark items done as you finish them, so a handoff summary
   can carry the remaining items into a child context.
5. Stop and ask when a step needs a tool your mode refuses.
