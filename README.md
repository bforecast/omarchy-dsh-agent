# omarchy-dsh-agent — install DeepSeek Harness (DSH) as an Omarchy AI agent

GitHub: https://github.com/bforecast/omarchy-dsh-agent

A git-distributable Omarchy plugin package. On any Omarchy machine:

```bash
git clone https://github.com/bforecast/omarchy-dsh-agent.git omarchy-dsh-agent
cd omarchy-dsh-agent
./install.sh --default        # install DSH and register it as the default AI agent
./install.sh                  # install & register only; leave the current default AI untouched
./uninstall.sh                # roll back (restore default, remove wrappers and menu entry)
```

> Note: Omarchy's first-party plugin system (`omarchy plugin add/clone`) only hosts
> QML shell components. Registering an AI agent requires writing `~/.local/bin`
> wrappers, a menu overlay, and the default-agent record, so this package ships as a
> self-contained installer plugin — identical in behavior to a manual install and
> it never touches `/usr/share/omarchy`.

## Layout

```
install.sh              Installer (idempotent, safe to re-run)
uninstall.sh            Uninstaller (safe checks + --dry-run)
files/
  dsh-web               DSH launcher template (idempotent start + open web UI)
  omarchy-default-agent User-level wrapper: supports `omarchy default agent dsh`
  omarchy-agent         User-level wrapper: launches DSH web when default is dsh
  omarchy               Thin CLI wrapper: intercepts `omarchy agent` / `default agent dsh`
  menu-entries.jsonc    Menu snippet (DSH entry in the Default-Agent picker)
  icons/                Official DSH icons (hicolor dsh.png at every size)
```

## What it does

| Target | Details |
| --- | --- |
| DSH source | Auto `git clone https://github.com/deepseek-ai/deepseek-harness.git` into `~/deepseek-harness` when missing (override with `--repo-url` / `--repo-dir`); runs `pnpm install` on a fresh clone unless `--no-bootstrap` |
| `~/.local/bin/dsh-web` | Idempotently starts `dsh web`, then opens `http://127.0.0.1:3080` in an Omarchy app window (log: `~/.local/state/dsh/web.log`) |
| `~/.local/bin/omarchy-*` | Three user-level wrappers so every Omarchy entry point (menu, keybinding, crash diagnosis) understands `dsh`; everything else passes through to the stock binaries |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | Adds the DSH row to the Default-Agent picker (idempotent; backs up `*.dshplugin.bak` first) |
| `~/.config/hypr/bindings.lua` | Appends a `BEGIN/END omarchy-dsh-agent` block rebinding the default-AI key (`SUPER + SHIFT + CTRL + A`) to the wrapper's **absolute path** (skip with `--no-keybinding`) |
| `~/.local/share/applications/dsh.desktop` + hicolor `dsh.png` | Registers DSH as an app with the official icon; the launcher/application search shows a real DSH logo row (icon derived from DSH's official `favicon.svg`) |
| `~/.config/omarchy/defaults/agent` | Written to `dsh` only with `--default`; the previous value is recorded in `~/.local/state/dsh-omarchy-plugin/state` so uninstall can restore it |

## Requirements

- Omarchy (Hyprland + Quickshell), bash, git, curl; DSH needs Node.js >= 22.
- `~/.local/bin` should be on PATH before `/usr/share/omarchy/bin` (Omarchy's default; the installer warns otherwise).
- First `dsh web` start is slow by design (startup wait cap: 90 s, see the log).

## install.sh options

| Option | Description |
| --- | --- |
| `--default` | Make `dsh` the default AI after install (previous default is recorded and restored on uninstall) |
| `--repo-dir PATH` | DSH source directory (default `~/deepseek-harness`; reused if it already exists) |
| `--repo-url URL` | Clone source (default `https://github.com/deepseek-ai/deepseek-harness.git`) |
| `--no-bootstrap` | Skip `pnpm install` |
| `--no-keybinding` | Skip the Hyprland Agent-key rebinding |
| `-n` / `--dry-run` | Print the actions that would be taken, change nothing |

## About the icon

Omarchy **static menu items can only render font glyphs** (no PNGs), so the package
does not put glyph shortcut rows at the menu root. Launching DSH goes through the
**application row with the official logo** (`.desktop` with `Icon=dsh`; search
"DSH" in the launcher), and the Default-Agent picker entry uses a robot glyph,
consistent with the other agents in that picker.

## Verify

```bash
omarchy default agent      # expect: dsh (if you used --default)
omarchy agent              # opens the DSH web app window
dsh-web --no-open          # only ensure the server is running
```

## Uninstall

```bash
./uninstall.sh -n          # dry-run first
./uninstall.sh             # restore default AI, remove wrappers, menu entry, app registration
```

The uninstaller only removes files whose content matches this plugin exactly;
files you have changed are skipped with a warning.

## Notes

- Install/uninstall never modify `/usr/share/omarchy`, so system updates do not overwrite anything.
- Default-AI restore target: when installed with `--default`, the pre-install value is restored; otherwise the `-r` option is used (default `codex`).

## FAQ: Hyprland keybinding does not open DSH (but `omarchy agent` in a terminal works)

Hyprland's exec PATH may not put `~/.local/bin` before `/usr/share/omarchy/bin`, so the
keybinding runs the stock `omarchy-agent`, which reports "Unsupported default agent"
for a `dsh` default — or does nothing.

The installer bakes in the fix: `install.sh` appends a `BEGIN/END omarchy-dsh-agent`
block to `~/.config/hypr/bindings.lua` that rebinds the default-AI key
(`SUPER + SHIFT + CTRL + A`) to the wrapper's **absolute path**
(`$HOME/.local/bin/omarchy-agent --pick`), then tries `hyprctl reload`;
`uninstall.sh` removes the block and restores the Omarchy default. `--no-keybinding`
skips this.

Manual equivalent (append to `~/.config/hypr/bindings.lua`):

```lua
hl.unbind("SUPER + SHIFT + CTRL + A")
o.bind("SUPER + SHIFT + CTRL + A", "Agent", "/home/<your-username>/.local/bin/omarchy-agent --pick")
```

Then run `hyprctl reload`. Note: `SUPER + SHIFT + A` is Omarchy's ChatGPT web-app
binding, not the agent key.
