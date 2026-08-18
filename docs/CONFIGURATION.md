# VimAction Configuration

VimAction is configured with plain YAML in **`~/.config/vim-action/`**. On first launch the app seeds that directory with commented defaults; after that the files are yours — VimAction never overwrites an existing file, so the directory is safe to manage as dotfiles.

    ~/.config/vim-action/
    ├── config.yaml            # per-app on/off
    └── profiles/
        └── <bundle-id>.yaml   # optional per-app tuning — one file per app

Edits are applied with **Reload Config** in the menu bar menu — no restart needed. If a reload fails, VimAction keeps the last valid configuration and tells you what went wrong (an alert on reload, a status line in the menu, and the *Apps* tab of the settings window).

## `config.yaml` — per-app on/off

A single map from bundle id to `true`/`false`:

```yaml
apps:
  com.mitchellh.ghostty: false      # terminals interpret keys themselves
  com.microsoft.VSCode: false       # editors usually have a Vim extension
```

- **Apps not listed are on.** You only list apps you want off (or explicitly back on).
- The seeded file ships with terminals (Terminal, iTerm2, Ghostty) and Vim-extension editors (VS Code, Cursor, Windsurf) turned off — double interpretation breaks both sides.
- To find an app's bundle id: focus the app and use **Copy Bundle ID** in the VimAction menu, or run `osascript -e 'id of app "Slack"'`.
- The menu bar's **Disable for This App** toggle edits this file for you as a minimal single-line change — your comments and formatting are preserved.

## Profiles — `profiles/<bundle-id>.yaml`

A profile fine-tunes VimAction inside one app: remap or disable individual motions and actions, pin scroll distances, or pin which execution path the app uses. Most apps don't need one — profiles exist for the exceptions, and the bundled Slack and Notion profiles are the canonical examples.

The file is named after the app's bundle id, one file per app. **Open/Create Profile** in the menu bar creates a fully commented scaffold for the frontmost app, so you don't have to start from scratch.

All fields are optional:

| Field | Purpose |
|-------|---------|
| `name` | Display name — cosmetic only |
| `scroll` | How many lines `Ctrl-d`/`Ctrl-u` and `Ctrl-f`/`Ctrl-b` scroll |
| `motions` | Per-motion key sequence override, or `disabled` |
| `actions` | Replace an action's own key, or `disabled` |
| `strategy` | Which execution path this app uses — `auto` (default), `accessibility`, or `keyboard` |
| `keyboard_family` | Last resort for apps that misreport what kind of element has focus |

### Worked example — Slack

In Slack, `Return` sends the message and `Shift-Return` inserts a line break. Without a profile, `o`/`O` (open a line below/above) would post a half-written message. The bundled profile swaps only the newline key:

```yaml
# ~/.config/vim-action/profiles/com.tinyspeck.slackmacgap.yaml
name: Slack
actions:
  open_line: [shift-return]
```

Only the action's own key is replaced — `o` still means "end of line, then open a new line below"; it just presses `Shift-Return` for the newline part, so `o` and `O` both keep working. The same one-liner fits any app where `Return` submits instead of inserting.

### Key token notation

Key sequences are arrays of tokens, one token per keystroke:

    [modifier-]key        # down · cmd-down · shift-return · ctrl-shift-left

- **Modifiers**: `cmd` `opt` `ctrl` `shift` — any order, joined with `-`.
- **Keys**: `left` `right` `up` `down` `return` `escape` `tab` `home` `end` `page_up` `page_down`.
- **Everything is lowercase.** `Cmd-Down` is not recognized — the entry is warned about and ignored.
- Character keys (`cmd-z` style) are not in the vocabulary yet — they are keyboard-layout-dependent.

### `motions` — remap or disable a motion

Each entry is a motion name mapped to either a key sequence or `disabled`:

```yaml
motions:
  document_end: [cmd-down]       # replace the keys G sends in this app
  line_first_non_blank: disabled # ^ (and d^, c^, …) do nothing in this app
```

| Name | Vim keys | Moves |
|------|----------|-------|
| `char_left` / `char_right` | `h` / `l` | One character left / right |
| `line_up` / `line_down` | `k` / `j` | One line up / down |
| `word_forward` / `word_backward` | `w` / `b` | Next / previous word start |
| `word_end_forward` | `e` | Word end |
| `line_start` | `0` | Line start |
| `line_first_non_blank` | `^` | First non-blank of the line |
| `line_end` | `$` | Line end |
| `document_start` / `document_end` | `gg` / `G` | Document start / end |

An override (or `disabled`) applies **everywhere the motion is used**: as a bare motion (`G`), as an operator target (`dG`, `yG`), and in Visual mode (`vG`) — one entry keeps them all consistent. `a` and `A` follow `char_right` and `line_end`: the line end `A` jumps to is the same concept as `$`.

`disabled` means every binding built on that motion becomes an honest no-op in that app — the keys are still intercepted, they just do nothing.

### `actions` — replace an action's own key, or disable it

```yaml
actions:
  open_line: [shift-return]      # o/O use Shift-Return as the newline key
  undo: disabled                 # u does nothing in this app
```

| Name | Vim keys | Default key sent |
|------|----------|------------------|
| `open_line` | `o` / `O` | `Return` |
| `paste` | `p` / `P` | `Cmd-V` |
| `undo` | `u` | `Cmd-Z` |
| `redo` | `Ctrl-r` | `Shift-Cmd-Z` |
| `scroll` | `Ctrl-d/u/f/b` | *(takes `disabled` only)* |

A sequence replaces **only the action's own key** — cursor positioning still comes from motions. That is why `open_line: [shift-return]` fixes both `o` and `O`: each keeps its own motion prefix and only the newline key changes.

`scroll` accepts only `disabled`: its strokes *are* the `line_up`/`line_down` motions, so remapping belongs in `motions`. And since character keys are not in the token vocabulary yet, `paste`/`undo`/`redo` overrides are mostly useful as `disabled`.

### `scroll` — pin scroll distances

```yaml
scroll:
  half_page_lines: 12   # Ctrl-d / Ctrl-u
  full_page_lines: 24   # Ctrl-f / Ctrl-b
```

Integers from 1 to 200. When absent, VimAction measures the app's visible viewport via Accessibility and falls back to 15/30 where that read fails. When set, the value always wins — which doubles as the workaround for apps that misreport their viewport (Notion reports the whole document as visible; the bundled profile pins 12/24).

### `strategy` — which execution path the app uses

```yaml
strategy: keyboard   # auto (default) | accessibility | keyboard
```

VimAction can carry out an action two ways: writing through the **Accessibility API** (the app's own text ranges, so motions and edit ranges land where Vim would) or **synthesizing keys** (the app's native editing shortcuts, e.g. `w` → `Option-Right`). This field picks between them.

| Value | Meaning |
|-------|---------|
| `auto` | **Default.** A probe decides per app: apps that pass run their edits through the Accessibility API, everything else — including the moment before the probe has answered — synthesizes keys. |
| `accessibility` | Always use the Accessibility API. The app is never probed, so nothing routes edits away when it fails. |
| `keyboard` | Always synthesize keys — the path every app took before automatic detection. |

The probe runs the first time a Vim key actually does something in an app, checks that the focused element exposes a text selection and can deliver it, and caches its verdict for as long as that app is running — quitting and relaunching the app probes again, and so does **Reload Config**. An app that passes but then starts failing at runtime is demoted back to key synthesis for the rest of its run. A few apps whose Accessibility layer reports text it cannot actually deliver are never trusted under `auto`; they are pinned to key synthesis in code (Notion is the current entry), and an explicit `strategy: accessibility` overrides that. **Web browsers are never trusted under `auto` either** — a browser's verdict would come from whatever happened to be focused (the URL bar passes, while a web editor such as Google Docs silently does not), so anything registered as an `https` handler synthesizes keys unless you set `strategy: accessibility` yourself. The probe also rejects focused elements with no visible extent (a hidden 1-pixel input that only relays keystrokes to a canvas editor), because such elements accept caret writes without moving the caret you see.

> **`accessibility` forces, it doesn't prefer.** It removes the fallback that `auto` guarantees, so in an app that reports a text element but doesn't answer Accessibility reads, motions and edits do nothing at all — the keys are intercepted and the screen never moves, with nothing to say why. `auto` already picks the Accessibility path wherever it holds up, so set this only for an app you have checked by hand.

### `keyboard_family` — bypass element detection (last resort)

```yaml
keyboard_family: force_text   # key_mapping (default) | force_text
```

Before synthesizing keys, VimAction asks what kind of element has focus: it picks sequences to match, and in non-text UI it holds edits back entirely — only motions and scrolling are sent. `force_text` drops that detection and always sends the text-area sequences.

| Value | Meaning |
|-------|---------|
| `key_mapping` | **Default.** Match sequences to the focused element, and hold edits back outside text. |
| `force_text` | Always treat the focused element as a text area. |

> **`force_text` can be destructive.** The element check is the only thing keeping editing keys out of non-text UI: without it, `dd` in a file list sends the select-and-cut sequence to the file list itself. It is never chosen automatically — only an explicit profile turns it on — and it exists for one case: an app that really is a text editor but reports its element kind wrongly, leaving edits blocked under `key_mapping`. It applies to key synthesis only; the Accessibility path judges the element on its own.

## How errors are handled

Configuration mistakes never take the whole Vim layer down — the rules are:

- **Unknown things are ignored per entry, with a warning**: an unknown field, motion/action name, or key token drops just that entry, never the file.
- **A broken token discards its whole entry** — you never get a half-applied sequence.
- **An empty sequence `[]` is not a disable** — it is warned about and ignored. Use the keyword `disabled`.
- **Scroll values outside 1…200** are warned about and ignored.
- **A file that fails to parse counts as absent**, and the error is shown. One easy way to trigger this by hand: a *duplicate key* in a map (the same app listed twice in `apps:`) fails that whole file — for `config.yaml` that would mean every app you turned off comes back on, so VimAction surfaces the error instead of continuing silently.
- **On reload, errors keep the last valid configuration** — a bad edit never downgrades a running setup.

Warnings and errors are visible in the settings window (*Apps* tab) and in the menu bar status line.

## File ownership and seeding

- Seeding only creates **missing** files; existing files are never touched, no matter their content. The one exception is the menu bar per-app toggle, which makes a single-line edit to `config.yaml`.
- Because missing files are re-seeded, **deleting a bundled profile doesn't stick** — it returns on next launch. To neutralize one, empty its contents (or comment everything out), or turn the app off in `config.yaml`.
