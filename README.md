# pwdtintii

**Directory-derived terminal background tinting.** Every directory you `cd`
into gets its own background color — deterministically chosen from a 37-family
palette, with a different shade per split/pane in the same directory. No
daemon, no persisted state, PID-tracked, terminal-agnostic via OSC 11.

Status: 0.1.0 · private alpha · works on zsh + bash 4+

```
~/ops              → slate (cool gray-blue)
~/projects/app-a   → rust  (warm earth)
~/projects/app-b   → teal  (cool muted)
                     └── split #2 of app-b → teal, lighter shade
```

## Why

Reading paths from a prompt is slow. Color is instant. After a few days you
just know which workspace you're in by the background tint, and which split
inside it by the shade. Splits in the same repo stay visually related;
unrelated repos stay visually distinct.

This is not a theme. It's per-workspace identity color, sitting underneath
whatever theme you already use.

## Requirements

- A terminal that honors OSC 11 (tested with Ghostty, also works in Alacritty,
  WezTerm, kitty, iTerm2, modern xterm).
- **zsh**, or **bash 4+** (Linux default, macOS needs `brew install bash`).
- `shasum` (macOS) or `sha1sum` (Linux) — for the dir-key hash.
- Optional: `fzf` — for interactive `pwdtintii_pick`. Falls back to a numbered
  menu if missing.

## Install

```sh
git clone https://forgejo.example.com/<owner>/pwdtintii ~/.local/share/pwdtintii
```

### zsh

Add to `~/.zshrc`:

```zsh
source ~/.local/share/pwdtintii/pwdtintii.plugin.zsh
# Optional short aliases:
# source ~/.local/share/pwdtintii/examples/aliases.zsh
```

### bash

Add to `~/.bashrc` (after the `[ -z "$PS1" ] && return` line if present):

```bash
source ~/.local/share/pwdtintii/pwdtintii.plugin.bash
# source ~/.local/share/pwdtintii/examples/aliases.bash
```

Open a fresh shell. Background tint should kick in on the first prompt.

## Usage

| Function          | What it does |
|-------------------|---|
| `pwdtintii_apply` | Re-apply background color (also runs automatically on each prompt) |
| `pwdtintii_pick`  | Pin a family for this shell. No arg → fzf picker with live preview |
| `pwdtintii_list`  | Show the current key, family, shade, plus all available families |
| `pwdtintii_reload`| Re-load the palette TSV |

With `aliases.zsh` / `aliases.bash` sourced, you get `pt`, `ptpick`, `ptlist`,
`ptreload`, `ptpreview`, `ptcontrast`.

## Configuration

Set env vars before sourcing the plugin:

```sh
# Use a custom palette
export PWDTINTII_PALETTE=~/.config/pwdtintii/my-palette.tsv

# Pin specific repos to specific families (overrides the hash)
export PWDTINTII_OVERRIDES_FILE=~/.config/pwdtintii/overrides.tsv

# Where to keep the per-dir PID registry (for shade tracking)
export PWDTINTII_SHADES_DIR=~/.cache/pwdtintii/shades

# Custom function name to resolve $PWD → key (default: git-root or ~/<top>)
export PWDTINTII_DIR_KEY_FN=my_key_resolver
```

The default key resolver walks up to find a `.git` dir; failing that, it uses
the first path component under `$HOME`. Override with `PWDTINTII_DIR_KEY_FN`
if you want a different strategy (e.g. per-tmux-session, per-host).

## Palette

The default palette ships with **37 families × 4 shades each**, grouped into:
cool/saturated (blue, green, teal, purple, yellow, orange, pink),
warm/earthy (plum, mahogany, rust, terracotta, wine, mauve),
calm blues (navy, midnight, slate, denim, steel, indigo),
forest greens (forest, moss, sage, evergreen, olive-dark),
deep teals (petrol, peacock, deepteal),
muted purples (eggplant, royal, violet-dark, lavender-dark),
warm-earth (amber, bronze, ochre),
tinted greys (graphite, charcoal, gunmetal).

See `palettes/README.md` for the format.

Preview every family × shade in your terminal:

```sh
scripts/preview.sh
```

WCAG contrast check vs common foreground colors:

```sh
scripts/contrast-check.sh
```

## How it works

1. **Dir key** — resolve `$PWD` to a stable identifier (git-root or first
   path segment under `$HOME`).
2. **Family** — `shasum(key) % family_count` → deterministic family.
3. **Shade** — per-key registry at `$PWDTINTII_SHADES_DIR/<keyhash>.tsv` holds
   `pid<TAB>shade_idx<TAB>timestamp` lines. Each new shell picks the lowest
   unused shade for its dir; dead PIDs are GC'd. On `cd`, the shell releases
   its old key and picks a fresh shade for the new key.
4. **Emit** — `printf '\e]11;<hex>\a'` (OSC 11) sets the terminal background.
5. **Hooks** — `precmd` (zsh) or `PROMPT_COMMAND` (bash) re-applies on every
   prompt. `zshexit` / `trap EXIT` releases the registry entry.

## Roadmap

- [ ] fish shell support
- [ ] tmux pane-background integration
- [ ] Light-theme palette variants
- [ ] Per-host palette switching (via `PWDTINTII_DIR_KEY_FN`)
- [ ] Demo GIF

## License

Apache-2.0 — see [LICENSE](LICENSE).
