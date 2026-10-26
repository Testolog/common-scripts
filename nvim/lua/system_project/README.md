# system_project

Business logic for the system project at `$COMMON_SCRIPT/system_project`: template, kind detection, catalog, init, and update.
It loads no plugins. `$COMMON_SCRIPT` comes from the environment, else the checkout this config ships from.

## Files under `$COMMON_SCRIPT/system_project/`

- `nvim_project.template.json`: the only template. It holds `system_prompt`, `system_skills`, `system_tools`, `models`, and `mcp_servers` (`name` and `isActive` only). Prompt and skill paths are relative to `$COMMON_SCRIPT` (`system_project/prompts/base.md`). Shell tool functions use `$COMMON_SCRIPT/system_project/system_function/*.sh`.
- `.nvim_project.json`: this directory's own project file. It is not the template.
- `prompts/base.md` (always selected), `prompts/java.md` (selected for `java`), `prompts/data.md` (selected for `yaml`, `avsc`, `json`, or `sql`).
- `skills/base/SKILL.md`.
- `system_function/`: `fsearch.sh`, `sd.sh`, `dasel.sh`, `ast-grep.sh` wrappers. `fsearch.sh` accepts
  `<pattern> [paths…]` and the `find <pattern> [paths…]` / `find <pattern> -f` form from the base prompt.
- `catalog.json`: `{ "projects": [ { "name", "root" } ] }`. It sits beside the template and is never copied into projects.

`scripts/system_project/install.py [--dry-run]` installs missing `fsearch`, `sd`, `dasel`, `ast-grep`, and Serena.

## `.nvim_project.json` on open

`main.lua` resolves the project root (nearest ancestor with `.nvim_project.json`, else the start directory).

- Missing file: nothing is written. The in-memory project is the defaults (`name` = directory basename, `lua` / `yaml` / `json`) with `root` set.
- Existing file: read as stored. Opening a project does not merge the template and does not rewrite the file.

`:NvimProjectInit` writes the file. `:SystemProjectUpdate` merges the template into cataloged projects. Neither runs on open.

Kinds: `java` for `pom.xml`, `build.gradle`, `build.gradle.kts` at the root or `java` already in `project_type`;
`yaml`, `avsc`, `json` (not `.nvim_project.json`), `sql` for any matching file up to depth 8, skipping `.git`, `node_modules`, build output, and virtualenvs.

## Merge

`:NvimProjectInit` on an existing file and `:SystemProjectUpdate` on each cataloged project use the same merge. The five template keys are not replaced wholesale. Local keys stay, including `lua`, `yaml`, `json`, `ssh_key`, `arduino`, `project_prompt`, `project_skills`, `project_tools`, and any other key.

For `system_prompt`, `system_skills`, `system_tools`, and `models` when `models` is a named array: union by name. Template-only entries are added, local-only entries stay, and shared entries are refreshed from the template. `system_prompt` entries taken from the template are filtered first by `kinds.select_prompts` (base always, `java` for java, `data` for yaml, avsc, json, or sql). When `models` is an object rather than a named array, keys merge the same way: the template refreshes shared keys and local-only keys stay.

For `mcp_servers`: a server already in the project keeps its local `isActive`. A server only in the template is added with the template `isActive`. Stored objects have only `name` and `isActive`.

A new file from `:NvimProjectInit` gets `name`, `lua`, `yaml`, `json`, the detected `project_type`, that same template merge onto empty lists, and empty `project_prompt`, `project_skills`, and `project_tools`. `name` is the basename of `git rev-parse --show-toplevel` when that succeeds in the directory, otherwise the directory basename. An existing non-empty `name` is left as stored.

## Commands

| Command | Effect |
| --- | --- |
| `:NvimProjectInit [dir]` | Write `.nvim_project.json` in `dir` (default: current tab root, else cwd) and register it in the catalog. Creates the file, or merges the template into an existing one. |
| `:SystemProjectInit` | Create `$COMMON_SCRIPT/system_project` where missing, copying missing files from the shipped checkout. Never overwrites. |
| `:SystemProjectUpdate` | Merge the template into every cataloged project (see Merge). Never runs on open. |
| `:SystemProjectRegister [dir]` | Add an existing project (default: current tab root) to the catalog. |

## Public functions (`system_project`)

- `common_script()`, `root()`, `shipped_root()`, `template_path()`, `catalog_path()`: paths. `template_path()` is `nvim_project.template.json` under the system project.
- `read_template()`: that template and its path. Falls back to the copy shipped with this config. It does not read `.nvim_project.json`.
- `template_values(template, kinds)`: the template side of a merge for a project with `kinds` (prompts already filtered).
- `apply_template(data, template, kinds)`: merge the five template keys into `data` in place.
- `new_project(root, base, template)`: the table a new project file gets.
- `default_name(dir)`: basename of `git rev-parse --show-toplevel` in `dir`, else the directory basename.
- `init_project(dir)`: write `.nvim_project.json` in `dir` and register it. Returns the written table, `nil`, and whether the catalog gained it. On failure: `nil`, error.
- `register(root, name?)`: add to the catalog. Returns true when added.
- `init()`: create missing pieces; returns the root and the created paths.
- `ensure()`: `init()` when the template is missing; returns the root.
- `update()`: merge into cataloged projects; returns updated roots and `{ root, error }` failures.
- `setup()`: register the commands above.
- Fields: `dir_name` (`system_project`), `project_file_name`, `template_file_name` (`nvim_project.template.json`), `catalog_file_name` (`catalog.json`), `template_keys` (the five keys `apply_template` merges).

### `system_project.kinds`

- `detect(root, existing_project_type?)`: kinds in order `java`, `yaml`, `avsc`, `json`, `sql`, then any other stored kinds.
- `select_prompts(prompts, kinds)`: template prompts that apply (`java` needs `java`; `data` needs any data kind; others always).
- Fields: `order`, `prompt_kinds`, `java_build_files`, `skip_dirs`, `max_depth` (8), `max_entries` (50000).

### `system_project.catalog`

- `read(path)`, `write(path, data)`, `register(path, root, name?)`.
