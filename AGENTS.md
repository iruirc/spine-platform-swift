# AGENTS.md — spine-platform-swift

Read `.claude/CLAUDE.md` first; it is the shared development guide for this repository.

## Codex compatibility

- Keep `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` aligned on `name`, `version`,
  `author.name`, and `repository`. Never move `version` by hand: a release goes through
  `spine-ops: scripts/release.sh`, which moves it in both. Never commit the `+codex.<cachebuster>`
  suffix Codex's local reinstall flow writes into `version`.
- `skills/`, `scripts/`, `templates/`, and `conventions/` are shared by Claude Code and Codex.
  Shared skill instructions must resolve support files through `<platform-root>`, never solely
  through a host-specific environment variable.
- `agents/` and `commands/` are Claude Code components. Do not claim they are available in Codex
  unless they are explicitly ported to Codex skills or workflows.
- The Codex manifest intentionally omits the Claude dependency declaration, and `spine-toolkit` has
  no Codex manifest yet. A skill that only `spine-toolkit` or a Claude Code component can drive
  carries `policy.allow_implicit_invocation: false` in its `skills/<name>/agents/openai.yaml` and no
  `default_prompt`. This prevents automatic selection but does not disable explicit `$skill` use.
- Run the full foundation suite and the Codex plugin validator after changing plugin metadata or
  shared skills.
