# automatic-potato

RHEL 8 system-wide installer plus environment-independent Bash utilities.

- `setup.sh` installs system packages; do not run it on the developer's Mac.
- `shell.sh` is sourced, never executed: recursively loads regular `utils/**/*.sh`.
- Utilities must define reusable functions without credentials or top-level actions.
- Preserve caller working directory and shell options when changing the loader.
- Test with `bash tests/shell-loader.sh`, ShellCheck, and the rootless UBI tests
  when changing the corresponding behavior.

## graphify

Read `graphify-out/GRAPH_REPORT.md` before source exploration when it exists.
If `graphify-out/wiki/index.md` exists, prefer navigating it. If the graph is
missing or stale, use the graphify skill to regenerate it, or explicitly note
that limitation before inspecting source directly. Prefer graphify query/path/
explain for relationships already represented in the graph.

This repository is predominantly Bash. The current graphify AST updater does
not parse `.sh`; `graphify update .` alone does not map these utilities. Use
semantic extraction of Bash and documentation through the graphify skill and
refresh the graph after changes. Keep graphify-out and extraction caches ignored.
Do not run graphify or install dependencies while sourcing shell.sh.
