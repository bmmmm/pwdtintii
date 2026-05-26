# Changelog

All notable changes to pwdtintii will be documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] — 2026-05-26

### Added
- zsh plugin (`pwdtintii.plugin.zsh`) with `precmd`-driven OSC 11 emission.
- bash 4+ plugin (`pwdtintii.plugin.bash`) with `PROMPT_COMMAND` hook.
- 37-family palette (`palettes/default.tsv`) covering cool/warm/earth/neutral tones.
- Per-key PID-tracked shade registry — splits in the same dir get distinct shades.
- `pwdtintii_pick` with fzf-based live-preview picker, numbered-menu fallback.
- `pwdtintii_list` / `pwdtintii_reload` / `pwdtintii_apply` public functions.
- `bin/pwdtintii` CLI for the fzf preview pane.
- `scripts/preview.sh` — visual palette dump.
- `scripts/contrast-check.sh` — WCAG check for fg/bg combos.
- `examples/aliases.{zsh,bash}` — opt-in short aliases (`pt`, `ptpick`, …).
- `examples/overrides.tsv` — example named-overrides config.
- Apache-2.0 license.
