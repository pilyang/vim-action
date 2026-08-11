# VimAction Keybindings

System-wide Vim keybindings for macOS. This document is the reference for
what VimAction supports today and what is planned — it describes the
*vocabulary* (which keys mean what), not the implementation, and not the
implementation order.

> **Development status note.** VimAction is under active development.
> Everything marked ✅ below is interpreted by the engine **and executed
> end-to-end** inside apps. Execution delegates to each app's native editing
> commands (and Accessibility APIs where enabled), so the exact result of an
> action can still vary between apps.

> **Status legend**
>
> | Mark | Meaning |
> |:----:|---------|
> | ✅ | Supported |
> | 🚧 | Partially supported — see Notes |
> | 📅 | Planned |
> | ❌ | Not planned |

## Modes at a Glance

VimAction starts in **Insert mode** — your normal typing is untouched until
you explicitly enter Normal mode. `Ctrl-[` is a full alias for `Esc`
everywhere.

| From | Key | To | Status | Notes |
|------|-----|----|:------:|-------|
| Insert | `Esc` | Normal | ✅ | |
| Normal | `i` `a` `I` `A` `o` `O` | Insert | ✅ | See [Normal Mode](#normal-mode) |
| Normal | `v` / `V` | Visual (char / line) | ✅ | |
| Visual | `Esc` | Normal | ✅ | Clears the selection |
| Visual | `v` / `V` (same kind again) | Normal | ✅ | |
| Normal / Visual | *modifier shortcut* (e.g. `Cmd+Space`) | Insert | ✅ | Unmapped `Cmd`/`Opt` shortcuts pass through **and** escape to Insert, so typing right after Spotlight/Raycast just works. Configurable. |
| Insert | `jk` | Normal | ❌ | Explored, deferred indefinitely |

## Insert Mode

Insert mode is transparent: every key passes through to the app unchanged,
except `Esc` (and `Ctrl-[`) which enters Normal mode.

## Normal Mode

### Motions

Motions move the cursor. Every motion accepts a `[count]` prefix
(`3w` = three words forward; counts are capped at 1,000).

| Key | Motion | Status | Notes |
|-----|--------|:------:|-------|
| `h` `j` `k` `l` | Left / down / up / right | ✅ | |
| `w` / `b` / `e` | Word forward / back / to word end | ✅ | |
| `0` / `^` / `$` | Line start / first non-blank / line end | ✅ | A `0` typed after count digits is part of the count (`10j`) |
| `gg` / `G` | Document start / end | ✅ | Counts are ignored — `3gg` does **not** jump to line 3 |
| `f` `F` `t` `T` | Find character in line | ❌ | Not in the v1 vocabulary or the backlog |

### Actions

| Key | Action | Status | Notes |
|-----|--------|:------:|-------|
| `x` | Delete character(s) under cursor | ✅ | `3x` deletes 3 characters as one edit |
| `D` / `C` | Delete / change to end of line | ✅ | Shorthand for `d$` / `c$`; `C` finishes in Insert mode. A count (`3D`) is invalid — Vim's multi-line meaning is not supported |
| `p` / `P` | Paste after / before | ✅ | Uses the system clipboard; `3p` pastes 3 copies as one edit |
| `u` | Undo | ✅ | Delegates to the app's native undo; `3u` undoes 3 times |
| `Ctrl-r` | Redo | ✅ | Delegates to the app's native redo |
| `Ctrl-d` / `Ctrl-u` | Scroll half page down / up | ✅ | Scroll counts are capped at 33 |
| `Ctrl-f` / `Ctrl-b` | Scroll full page down / up | ✅ | Scroll counts are capped at 33 |
| `Ctrl-e` / `Ctrl-y` | Scroll line down / up | 📅 | |

### Operators — the composable grammar

Operators (`d` delete, `c` change, `y` yank) don't act alone; they combine
with a *target*:

    [count] operator [count] (motion | text object | doubled key)

Reading a few examples:

| You type | Meaning |
|----------|---------|
| `dw` | Delete to the next word |
| `d3w` / `3dw` / `2d3w` | Delete 3 (or 2×3 = 6) words — counts multiply |
| `dd` / `3dd` | Delete line(s) — doubling the operator targets whole lines |
| `diw` | Delete inner word (cursor can be anywhere in the word) |
| `ci"` | Change inside the surrounding `"…"` quotes, then enter Insert |
| `dgg` / `dG` | Delete whole lines from the cursor to the document start / end |

An invalid sequence (e.g. `dq`) is discarded silently, like in Vim.
`c` always finishes by entering Insert mode (`cc`, `c$`, `ciw`, …).

> **Clipboard warning.** Delete and change (`x`, `D`, `C`, `d…`, `c…`, and
> their Visual-mode forms) cut through the **system clipboard** — the removed
> text overwrites whatever you had copied. This is by design: the clipboard
> acts as Vim's unnamed register, so `p` pastes what you last deleted.

#### Operator × Target support matrix

Each cell answers: can this operator take this target?

| Target ↓ / Operator → | `d` delete | `c` change | `y` yank |
|---|:---:|:---:|:---:|
| `w` `b` `e` (word motions) | ✅ | ✅ | ✅ |
| `h` `l` `0` `^` `$` (character motions) | ✅ | ✅ | ✅ |
| `j` `k` (whole lines, relative) | ✅ | ✅ | ✅ |
| `gg` `G` (whole lines, to document start/end) | ✅ | ✅ | ✅ |
| Doubled key `dd` `cc` `yy` (whole lines) | ✅ | ✅ | ✅ |
| `iw` / `aw` (word text object) | ✅ | ✅ | ✅ |
| `i"` `i'` `` i` `` / `a…` (quote text objects) | ✅ | ✅ | ✅ |
| `i(` `i[` `i{` `i<` / `a…` (pair text objects) | ✅ | ✅ | ✅ |

**Count rules** (per row):

- Motions: counts multiply — `2d3w` deletes 6 words.
- `gg` / `G` targets: any count makes the command invalid (absolute line
  targets like Vim's `d3G` are not supported).
- Text objects: counts are not accepted (`d2iw` is invalid).

**Note on `cw`:** as in Vim, `cw` is special-cased — it changes to the *end*
of the word under the cursor (like `ce`), not to where `dw` would delete
(on whitespace it changes just the remaining whitespace, also like Vim).

#### Text object keys

Text objects come after an operator plus `i` (inner) or `a` (around):

| Key | Object | Status | Notes |
|-----|--------|:------:|-------|
| `w` | Word | ✅ | |
| `"` `'` `` ` `` | Quoted string | ✅ | |
| `(` `)` `b` | Parentheses | ✅ | Opening, closing, and alias keys are equivalent |
| `[` `]` | Brackets | ✅ | |
| `{` `}` `B` | Braces | ✅ | |
| `<` `>` | Angle brackets | ✅ | |

## Visual Mode (char & line)

Enter with `v` (character-wise) or `V` (line-wise) from Normal mode. Motions
extend the selection instead of moving the cursor; operators act on the
selection immediately — there is no operator-pending state, so a leading
count before an operator is simply ignored (`3d` deletes the selection).

| Key | Action | Status | Notes |
|-----|--------|:------:|-------|
| *(any motion)* | Extend selection | ✅ | Same motion set and counts as Normal mode |
| `v` / `V` | Switch char ↔ line, or exit if already in that kind | ✅ | The selection anchor is kept when switching |
| `d` / `x` | Delete selection → Normal | ✅ | |
| `c` | Change selection → Insert | ✅ | |
| `y` | Yank selection → Normal | ✅ | The selection highlight is cleared, like in Vim |
| `Esc` | Clear selection → Normal | ✅ | |

Text objects (`iw`, `i(`, …) are not available in Visual mode.

## Planned — v2+ backlog

These are backlog candidates. They are **not** commitments with a
timeline, but you can expect them to be considered after v1:

- **Search** — `/`, `?`, `n`, `N` (where the host app exposes the needed
  accessibility queries).
- **Marks** — `m{a-z}`, backtick / `'` jumps.
- **Registers** — `"a`–`"z`. Until then, the system clipboard is the only
  register.
- **Macros** — `q` / `@`.

## Not Planned

Explicitly out of scope (deliberate decisions, not oversights):

- **Ex commands** (`:w`, `:q`, `:%s/…/…`) — VimAction is a modal layer over
  existing apps, not a text editor.
- **Buffers, split windows, `.vimrc` parsing** — same reason: VimAction is
  not a full Vim emulator.
- **`f` / `F` / `t` / `T`** — not part of the curated vocabulary.
- **`jk` escape mapping** — explored and deferred indefinitely.
