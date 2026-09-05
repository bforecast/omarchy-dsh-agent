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
manifest.json           Omarchy shell-plugin manifest (bar-widget "dsh-launcher")
BarWidget.qml           Bar icon: one-click start + open DSH web UI
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
| `--with-widget` | Also install and enable the top-bar `dsh-launcher` widget via `omarchy plugin add` (full setup in one command) |
| `--widget-url URL` | Widget repo source for `--with-widget` (default `https://github.com/bforecast/omarchy-dsh-agent.git`) |
| `--repo-dir PATH` | DSH source directory (default `~/deepseek-harness`; reused if it already exists) |
| `--repo-url URL` | Clone source (default `https://github.com/deepseek-ai/deepseek-harness.git`) |
| `--no-bootstrap` | Skip `pnpm install` |
| `--no-keybinding` | Skip the Hyprland Agent-key rebinding |
| `-n` / `--dry-run` | Print the actions that would be taken, change nothing |

## Security & privacy notes

- **Pinned DSH source**: `install.sh` prepares DeepSeek Harness by `git init` + fetching
  exactly the pinned 40-hex commit (`DSH_COMMIT`, default `d347e703…`) into a sibling
  temporary directory, detached-checks out and verifies HEAD, then atomically moves it into
  place. Existing non-checkout paths are refused untouched; an existing checkout must sit at
  the pin or be accepted with `--use-existing`. A custom `--repo-url` is refused without an
  explicit `--repo-rev <40-hex>`. Dependencies install with `pnpm install --frozen-lockfile`.
- **`--dry-run` changes nothing**: it performs no writes and creates no directories.
- **Conservative uninstall**: `uninstall.sh` removes only files that are byte-identical to what
  the plugin installed (user modifications are never deleted); it restores the `*.dshplugin.bak` backups taken before overwriting
  wrappers/desktop/icons, deletes icons only when they hash-match ours, keeps the Chromium
  "DeepSeek Harness" PWA unless `--remove-pwa`, edits menu and Hyprland bindings **surgically**
  (plugin marker blocks only, so post-install user edits survive), and never spawns windows.
- **`dsh-solve-error` privacy**: diagnostics are redacted (secrets/keys/tokens/emails) before
  anything is sent; interactive runs ask for confirmation and **non-interactive runs refuse
  unless `-y/--yes`** is passed; the state directory is `0700` and the transcript `0600`; the
  task states the context is untrusted data. The headless run sends the redacted context to
  your **configured model provider** (DSH defaults to the public DeepSeek API), not only
  "local".

## About the icon

Omarchy **static menu items can only render font glyphs** (no PNGs), so the package
does not put glyph shortcut rows at the menu root. Launching DSH goes through the
**application row with the official logo** (`.desktop` with `Icon=dsh`; search
"DSH" in the launcher), and the Default-Agent picker entry uses a robot glyph,
consistent with the other agents in that picker.

## Bar widget (marketplace-ready shell plugin)

The repository root is also a valid Omarchy **shell plugin** (`bar-widget`
kind, id `dsh-launcher`): a bar icon that starts DSH and opens its web UI.

```bash
omarchy plugin add https://github.com/bforecast/omarchy-dsh-agent.git   # clone into ~/.config/omarchy/plugins
omarchy plugin enable dsh-launcher                                      # place the DSH icon in the bar
```

Or let `install.sh` do both at once:

```bash
./install.sh --default --with-widget
```

The widget only launches DSH — full AI-agent registration (PATH wrappers,
default agent, keybinding, desktop entry) is done by `./install.sh`.

## Solve system errors with DSH

When an error log shows up (a crash toast, a journal error, a pasted message),
you can hand it to the local DeepSeek Harness for analysis:

- **Omarchy skills**: the task tells DSH to load the bundled Omarchy skills
  (`omarchy`, and `diagnose-crash` for crashes) from `~/.agents/skills` when applicable.
- **`dsh-solve-error`** (installed by `install.sh`):
  - `dsh-solve-error` or `dsh-solve-error --auto` — collect the recent system/user
    error journal plus core-dump list and let DSH analyze them (headless run);
  - `dsh-solve-error "text of the error"` / `--text …` / `--file path.log` — solve a
    specific error or a log file;
  - `--show-context` previews what will be sent; `--dry-run` shows the DSH command.
- **Crash notification / `omarchy agent crash`**: with `dsh` as the default agent the
  click launches `dsh-solve-error` with the crash facts in a terminal so DSH proposes a
  diagnosis and fix (no extra menu entry needed).

Requires a working DSH checkout (`~/deepseek-harness`, see install.sh) and Node.js >= 22.

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
