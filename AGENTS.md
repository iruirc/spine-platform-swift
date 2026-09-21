# AGENTS.md — spine-platform-swift

Read `.claude/CLAUDE.md` first; it is the shared development guide for this repository.

## Codex compatibility

- Keep `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` aligned on `name`, `version`,
  `author.name`, and `repository`.
- `skills/`, `scripts/`, `templates/`, and `conventions/` are shared by Claude Code and Codex.
  Shared skill instructions must resolve support files through `<platform-root>`, never solely
  through a host-specific environment variable.
- `agents/` and `commands/` are Claude Code components. Do not claim they are available in Codex
  unless they are explicitly ported to Codex skills or workflows.
- The Codex manifest intentionally omits the Claude dependency declaration. Codex users must install
  a compatible `spine-toolkit` separately when they need orchestration rather than standalone
  knowledge skills.
- Run the full foundation suite and the Codex plugin validator after changing plugin metadata or
  shared skills.
