# system_project

Business logic for the system project at `$COMMON_SCRIPT/system_project`: template, kind detection, catalog, init, and update.
It loads no plugins. `$COMMON_SCRIPT` comes from the environment, else the checkout this config ships from.

## Files under `$COMMON_SCRIPT/system_project/`

- `.nvim_project.json`: the template. Prompt and skill paths are relative to `$COMMON_SCRIPT` (`system_project/prompts/base.md`).
  Shell tool functions use `$COMMON_SCRIPT/system_project/system_function/*.sh`.
- `prompts/base.md` (always copied), `prompts/java.md` (copied for `java`), `prompts/data.md` (copied for `yaml`, `avsc`, `json`, or `sql`).
- `skills/base/SKILL.md`.
- `system_function/`: `fsearch.sh`, `sd.sh`, `dasel.sh`, `ast-grep.sh` wrappers. `fsearch.sh` accepts
  `<pattern> [paths…]` and the `find <pattern> [paths…]` / `find <pattern> -f` form from the base prompt.
- `catalog.json`: `{ "projects": [ { "name", "root" } ] }`. It sits beside the template and is never copied into projects.

`scripts/system_project/install.py [--dry-run]` installs missing `fsearch`, `sd`, `dasel`, `ast-grep`, and Serena.

## New vs existing `.nvim_project.json`

`main.lua` resolves the project root (nearest ancestor with `.nvim_project.json`, else the start directory).

- Missing file: `create_project_file` writes a standalone file with `name`, `lua`, `yaml`, `json`, the detected
  `project_type`, the matching template prompts, every template skill and tool, `models`, `mcp_servers` (`name`, `isActive` only),
  and empty `project_prompt`, `project_skills`, `project_tools`. The project is added to the catalog.
- Existing file: read as stored. Nothing from `$COMMON_SCRIPT` is merged and the file is not rewritten.

Kinds: `java` for `pom.xml`, `build.gradle`, `build.gradle.kts` at the root or `java` already in `project_type`;
`yaml`, `avsc`, `json` (not `.nvim_project.json`), `sql` for any matching file up to depth 8, skipping `.git`, `node_modules`, build output, and virtualenvs.

## Commands

| Command | Effect |
| --- | --- |
| `:SystemProjectInit` | Create `$COMMON_SCRIPT/system_project` where missing, copying missing files from the shipped checkout. Never overwrites. |
| `:SystemProjectUpdate` | For each cataloged project, rewrite `system_prompt` (re-evaluating kind prompts), `system_skills`, `system_tools`, `models`, and `mcp_servers` from the template. `project_*` and other keys are kept. Never runs on open. |
| `:SystemProjectRegister [dir]` | Add an existing project (default: current tab root) to the catalog. |

## Public functions (`system_project`)

- `common_script()`, `root()`, `shipped_root()`, `template_path()`, `catalog_path()`: paths.
- `read_template()`: template table and its path (falls back to the shipped copy).
- `template_values(template, kinds)`: the template-owned keys for a project with `kinds`.
- `new_project(root, base, template)`: the table a new project file gets.
- `create_project_file(root, base)`: write and catalog a new project file; returns the written table.
- `register(root, name?)`: add to the catalog. Returns true when added.
- `init()`: create missing pieces; returns the root and the created paths.
- `ensure()`: `init()` when the template is missing; returns the root.
- `update()`: rewrite cataloged projects; returns updated roots and `{ root, error }` failures.
- `setup()`: register the commands above.
- Fields: `dir_name` (`system_project`), `project_file_name`, `catalog_file_name` (`catalog.json`), `template_keys`
  (the keys `update()` rewrites).

### `system_project.kinds`

- `detect(root, existing_project_type?)`: kinds in order `java`, `yaml`, `avsc`, `json`, `sql`, then any other stored kinds.
- `select_prompts(prompts, kinds)`: template prompts that apply (`java` needs `java`; `data` needs any data kind; others always).
- Fields: `order`, `prompt_kinds`, `java_build_files`, `skip_dirs`, `max_depth` (8), `max_entries` (50000).

### `system_project.catalog`

- `read(path)`, `write(path, data)`, `register(path, root, name?)`.
