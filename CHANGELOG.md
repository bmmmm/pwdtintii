# Changelog

All notable changes to pwdtintii will be documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- `scripts/release.sh` is now a real dry-run: a preview (without `--yes`) no
  longer edits the tracked files in place. It used to flip the CHANGELOG header
  and bump VERSION/README on disk, leaving the tree dirty (and no `[Unreleased]`
  header for a second pass) — so the very `--yes` the dry-run pointed you to
  aborted on the script's own clean-tree precondition. The preview now diffs the
  proposed edits against the current files and writes nothing until `--yes`.
- CI is green on GitHub Actions again: the bash/zsh `doctor` parity test now
  pins `TERM` (runners leave it unset, where bash defaults to `dumb` and zsh
  does not), with two runner-only test failures also fixed. (0.5.0's tag CI was
  red, so its release job was skipped and no 0.5.0 GitHub Release exists — 0.5.1
  is the first green-CI tag since.)

## [0.5.0] — 2026-06-18

### Added
- **`pt version`** — prints the installed version (e.g. `pwdtintii 0.5.0`), read
  from a new single-source `VERSION` file at the repo root. The version lives in
  one place now instead of being mirrored by hand across the docs; zsh, bash, and
  fish each read it and print a byte-identical string.
- **`scripts/release.sh`** — release automation. Given a version it flips the
  CHANGELOG `## [Unreleased]` header to `## [X.Y.Z] — <date>`, syncs the version
  strings (the `VERSION` file and the README status line), and runs the CI release
  job's own CHANGELOG-extraction `awk` as a local preflight — catching the empty-
  section case that would make the release job exit 1, before any tag exists. With
  `--yes` it commits and creates the annotated tag; it never pushes (it prints the
  push commands for you to run).

### Fixed
- The fzf live-preview tint (while `pt pick` or `pt view` is open) is now per-pane
  under tmux, matching the steady-state prompt: the picker/viewer background emits
  route through a tmux-aware helper (`tmux select-pane -P "bg=#..."` when `$TMUX`
  is set, OSC 11 otherwise), so opening a preview no longer repaints every pane in
  the window. Resolves the "Known limitation" noted under [0.4.0].

## [0.4.0] — 2026-06-18

### Added
- **fish shell support** (`pwdtintii.plugin.fish`, requires fish 3.5+) — a full
  native port: resolves identical directory keys, families, shades, and registry
  hashes as the bash/zsh plugins and emits byte-identical OSC-11 hex. Shares the
  same per-dir PID registry, so a fish pane and a bash/zsh pane in the same
  directory still get distinct shades. fzf commands (`pt view`, the picker, the
  hub) force `SHELL=/bin/sh` so fzf's POSIX binds run correctly. Opt-in aliases
  in `examples/aliases.fish`; install is a manual `source` line. Pinned by a new
  `tests/fish.bats` (19 tests) that compares fish output against bash.
- **tmux per-pane tinting** — when `$TMUX` is set, the tint is applied with
  `tmux select-pane -P "bg=#..."` instead of the global OSC-11 sequence, keeping
  each pane's color isolated (OSC 11 would colour the whole terminal, so multiple
  panes in one window would fight over a single background). `pt off` resets the
  pane style (`bg=default`). Known limitation: the fzf live-preview tint (while
  the picker or viewer is open) still uses OSC 11 even inside tmux; the
  steady-state prompt path is per-pane, and the background snaps back to per-pane
  when the picker closes.
- **`pt view`** — a merged list+preview browser: an fzf picker over the families
  with a colored preview pane that `ctrl-t` cycles through swatch and contrast
  views across the dark and light palettes. Read-only — it previews; `pt pick`
  pins. Reachable from the `pt` menu and as `ptview`.
- **APCA in `pt contrast`** — each shade is now scored against the theme text in
  APCA Lc alongside the WCAG ratio. The colored contrast view paints the scores
  in each shade's best-readable foreground (the tone the engine recommends).

### Changed
- The `pt pick` and `pt view` fzf menus are high-contrast over the live tint: the
  family list is colored per-line (`--ansi`) in a tone that contrasts the tinted
  background — light on the dark palette, dark on the light one — so a `ctrl-t`
  toggle reflows the list in place and the focused row is a legible pill.
  Previously the list inherited the terminal's ANSI foreground, with no
  guaranteed contrast against the tint.
- The `pt pick` `ctrl-t` dark/light toggle is flicker-free: it reloads the list,
  preview, and header in place instead of restarting fzf (which redrew the whole
  screen).
- The `pt` hub menu adapts to the terminal width: the list pane is sized to its
  widest action row so the glosses are no longer ellipsized, and the description
  preview reflows to fill its pane instead of being hard-wrapped (the `↳`
  markers). On a terminal too narrow to fit both side by side, the preview stacks
  below the list so each keeps the full width.

### Removed
- `scripts/preview.sh` — the static palette dump is folded into `pt view`'s
  colored browser. `pt preview` stays as a back-compat alias for `pt view`.

### Fixed
- The `ctrl-t` dark/light flip in `pt pick` and `pt view` now repaints the
  terminal background together with the list and swatches instead of lagging a
  keystroke behind (the background used to catch up only on the next arrow key).
  The live tint is routed through fzf's coordinated `execute-silent`, not a raw
  OSC write during the `transform`, which fzf's renderer dropped.
- Closing the picker or viewer (ENTER/ESC) no longer flashes the terminal's
  default background: fzf renders inline (sub-100% height), so its exit never
  repaints the whole frame.
- After a `ctrl-t` toggle to the other group, committing a pick no longer
  disables the `ctrl-t` toggle on the next `pt pick`. The plugin compares palette
  paths by inode (`-ef`, matching the CLI), so a committed `PWDTINTII_PALETTE` in
  a `bin/..` or symlinked form is still recognized as the bundled palette.
- The prompt hook preserves `$?`, so a prompt that shows the last command's exit
  status (zsh `%?`, or a bash prompt reading a captured `$?`) is no longer reset
  to success on every command by the background emit.
- A `PROMPT_COMMAND` array (bash 5.1+) no longer double-registers the hook and
  emits OSC 11 twice per prompt — the install now scans every element.
- A custom palette or overrides file without a trailing newline keeps its last
  row instead of silently dropping it.
- The zsh plugin runs cleanly under a user's `setopt nounset`, matching the bash
  plugin under `set -u`.

## [0.3.0] — 2026-06-15

### Added
- Public GitHub mirror at github.com/bmmmm/pwdtintii — one-way Forgejo→GitHub
  push-mirror, so the project can now be cloned from GitHub.
- **`pt off`** — actually stops tinting: resets the terminal background to its
  default (OSC 111) and makes the prompt hook a no-op until re-enabled via
  `pt pick` / `pt auto` / `pt reload`. Previously `off` was only an alias for
  `auto`/unpin and kept tinting by directory.
- **`pt doctor`** — reports the setup (hash command, fzf, python3, palette,
  terminal) and probes OSC 11 support live, surfacing the otherwise-silent
  failure mode of a terminal that ignores OSC 11. The python3 line flags when
  `pt contrast` is unavailable for lack of its only dependency.
- Install via a plugin manager (oh-my-zsh / zinit / antidote), documented in the
  README — the `pwdtintii.plugin.zsh` naming already followed the convention.
- macOS coverage in CI (`macos-latest`) — exercises the BSD `stat -f` / `shasum`
  / BSD-awk / brew-bash path the project is built around, which the Linux-only
  job never touched — plus a release job that cuts a GitHub Release from the
  matching CHANGELOG section on `v*` tags.
- **Light-theme palette** (`palettes/light.tsv`) — a pale, high-luminance variant
  for light terminal themes. It mirrors `default.tsv`'s families and order, so a
  given directory keeps its hue and only the lightness flips; activate it with
  `PWDTINTII_PALETTE=~/.local/share/pwdtintii/palettes/light.tsv`. Derived from
  `default.tsv` by `scripts/gen-light-palette.py` (hue preserved, shades placed
  on a WCAG-luminance ladder) and verified readable against dark text.
- **Dark/light toggle in the `pt pick` picker** — `ctrl-t` flips between the
  dark and light family groups so both stay reachable without listing all of
  them at once; committing a pick from a group switches this shell to that
  group's palette. No persisted state: it is scoped to the running shell, and an
  explicit `PWDTINTII_PALETTE` in your rc still sets the startup default.

### Changed
- `pt` now self-heals a stale shell: when the plugin file changed on disk since
  the shell sourced it, the next `pt` re-sources the plugin before dispatching
  (carrying over the pinned family, shade, and disabled state) and prints a
  one-line notice — instead of only flagging "plugin changed — re-source" and
  leaving the re-source to you. Re-sourcing is safe to repeat: the prompt hook
  registration dedupes and runtime state lives in globals the load path preserves.
- CI consolidated into a single `.github/workflows/ci.yml`, read by both
  Forgejo (source of truth) and GitHub (mirror); the `.forgejo/` copy was
  removed. `actions/checkout` is pinned to v4 (node20) so the act-based Forgejo
  runner, which has no node24 runtime for checkout@v5, runs it too.
- Install URL and copyright now reference the public GitHub identity.
- Prompt hot-path: the directory key is cached by `$PWD`, skipping the per-prompt
  subshell fork + git-root stat-walk while the directory is unchanged (a fresh
  `git init` in the current dir is picked up on the next `cd`).
- `scripts/contrast-check.sh` is now theme-aware: a light-background palette is
  checked against dark text instead of light (theme auto-detected from mean
  luminance, or forced with a `dark`/`light` second argument). `scripts/preview.sh`
  shows each shade against both a light and a dark text sample, so the dump is
  legible whichever palette it dumps.
- The `pt pick` fzf preview pane is now high-contrast on every shade: the sample
  text and the shadeN/hex label pick a dark tone on a light band and a light tone
  on a dark one (per-band perceived luminance), so the labels stay legible on the
  pale `light.tsv` swatches reached via `ctrl-t`, not just on the dark default.
- The live focus background (the terminal tint while you arrow through the
  picker) is now theme-aware: a dark palette still dims the darkest shade toward
  black, but a light palette lifts the lightest shade toward white instead of
  darkening — so on a light terminal theme the hovered background no longer drops
  to a dark tone under your dark text, while the swatches still stand out. The
  darkest/lightest shade is chosen by perceived luminance, not palette position,
  so a palette that orders its shades light-to-dark still tones the right one.

### Fixed
- Palette loading validates that each family has four `#rrggbb` shades and skips
  any malformed row with a warning, instead of storing it and silently emitting
  nothing on that family.
- A self-reload (`pt` re-sourcing a changed plugin) no longer double-registers
  the bash prompt hook. The append now sits behind a one-shot flag, so a
  `PROMPT_COMMAND` that a framework has reformatted (spaced-out `;` separators)
  can't slip past the substring dedupe guard and get `pwdtintii_apply` appended
  twice — which would emit OSC 11 twice per prompt. zsh was already immune
  (`add-zsh-hook` dedupes by membership).
- A self-reload now parse-checks the plugin (`bash -n` / `zsh -n`) before
  sourcing it, so a reload triggered mid-edit (the file saved half-written) keeps
  the running definitions and reports the failure, instead of partially
  redefining the plugin while still looking like it succeeded.
- `bin/pwdtintii` rejects a malformed shade in a custom palette — the CLI reads
  the palette unvalidated, unlike the plugin loader — instead of crashing the
  `16#` hex arithmetic under `set -e`.

## [0.2.0] — 2026-06-14

### Added
- **`pt` entry point** — bare `pt` opens an fzf action menu listing every
  command (with a live description in the preview pane); selecting one runs it.
  The menu loops: display-only actions (`list`, `preview`, `contrast`) pause
  afterwards — q quits the hub, any other key (including arrow keys) returns to
  the menu. ESC steps back one level: out of the family picker into the menu,
  out of the menu to the shell. The header shows the current family/shade, and
  flags a stale shell when the plugin file has changed on disk since it was
  sourced (`pt help` notes it too). `pt <cmd>` dispatches directly: `pick`,
  `list`, `auto`, `reload`, `preview`, `contrast`, `help`. Without fzf, bare
  `pt` prints a cheat-sheet.
- `bin/pwdtintii actions` / `describe-action` expose the action catalog — the
  single source of truth the shell dispatcher re-runs, so menu and dispatch
  cannot drift (guarded by a test).
- `pwdtintii_pick --auto` clears a pinned family and returns to auto mode.
- bats test harness (`tests/`) coupling the bash and zsh plugins, plus a
  Forgejo CI workflow (shellcheck, `zsh -n`, bats).

### Changed
- The `pt` alias now points at the dispatcher (was `pwdtintii_apply`, a
  visual no-op); `ptpick`/`ptlist`/… remain as direct accelerators.
- Steady-state prompts (same directory) skip all subprocess work and only
  re-emit, cutting ~6 forks per prompt down to the key lookup.
- README rewritten compact, with screenshots of the action hub and the live
  family picker (`docs/`).

### Fixed
- **fzf preview height** — the family preview now stretches to fill the pane
  (`FZF_PREVIEW_LINES`) instead of a fixed ~18 lines that left the lower half
  empty and pushed the fourth shade behind a scrollbar.
- **live focus tone** — hovering a family in the picker emitted shade2 as the
  background, so the shade2 swatch vanished into it; it now emits a dimmed
  family tone (shade0 × 50%), darker than all four shades, so each stays
  distinct.
- **emit under `set -e`** — `emit-family` no longer aborts when there is no
  controlling `/dev/tty` (the failed redirect is fully contained).
- **CLI help leak** — `pwdtintii help` (the CLI) printed `set -euo pipefail`
  from the source below the doc block; it now stops at the first blank line.
- **fzf picker cancel** — pressing ESC no longer captured the restore OSC
  sequence into a variable; the picker now returns only the family and the
  caller restores the background, so cancel correctly reverts the tint.
- **zsh `sha1sum` fallback** — the zsh plugin hardcoded `shasum` and broke on
  Linux systems that only ship `sha1sum`; it now detects either at load (and
  fails loudly if neither is present), matching the bash plugin and the docs.
- **bash key drift** — directories outside `$HOME` collapsed to the whole path
  in bash but the first component in zsh; bash now also uses the first
  component, so both shells tint the same directory identically.
- **cross-shell registry hash** — zsh hashed the key with a trailing newline
  (`print -r`) while bash did not (`printf`), so the two never shared a shade
  registry; zsh now uses `print -rn`.
- **empty palette** — a palette with no families caused a division-by-zero on
  every prompt; `apply` is now a no-op and load warns once.
- **menu bounds** — choice `0` in the numbered picker selected the last family
  via bash negative indexing; out-of-range input is now rejected, and a
  leading-zero choice (`08`, `09`) no longer trips bash octal parsing.
- **root path** — applying at the filesystem root (`/`, empty project name) no
  longer leaks a `bad array subscript` error to the bash prompt.
- **registry race** — the read-modify-write is now guarded by a `mkdir` lock
  (bounded, fail-open) so shells starting concurrently in the same dir don't
  clobber each other's shade.
- **bash symlink resolution** — `_pwdtintii_self` now follows symlinks, so the
  plugin works when sourced via a symlink.
- registry `.t` temp files are cleaned up and emptied registries removed.
- OSC 11 emission validates the hex before emitting (no escape injection from a
  malformed palette).

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
