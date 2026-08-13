# Contributing to VimAction

Thanks for your interest in VimAction! Here is how contributions work in this project.

## The short version

- **Bug reports and feature requests are the most valuable contribution.** Please open an [issue](https://github.com/pilyang/vim-action/issues/new/choose) — the templates ask for exactly what makes a report actionable.
- **Pull requests: please open an issue first** to discuss what you want to change. Typo and documentation fixes are fine to send directly.

## How this project is maintained

VimAction is maintained by a solo developer, and most of the code is written in collaboration with an AI coding agent (Claude Code). A human reviews, tests, and decides everything that ships. Two practical consequences:

- Response times vary — this is a nights-and-weekends project.
- An accepted idea may land as a fresh implementation rather than through your PR. Discussing in an issue first avoids wasted work on both sides.

AI-assisted contributions are welcome — it would be odd to object here — as long as you have run the tests and can explain the change yourself. Please don't send untested machine-generated PRs.

## Why issues first?

VimAction intercepts every keystroke system-wide, so small changes can have an outsized blast radius, and the Vim vocabulary is deliberately curated — [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md) lists what is planned and what is intentionally out of scope. An issue conversation settles *whether* and *how* before you invest in code.

## Development setup

You need macOS 14 or later and a recent Xcode.

```sh
# Engine tests — pure Swift, no macOS APIs, fastest feedback loop
swift test --package-path Packages/VimActionCore

# App unit tests
xcodebuild test -project VimAction.xcodeproj -scheme VimAction \
  -destination 'platform=macOS' -only-testing:VimActionTests

# Build (CI-equivalent, unsigned)
xcodebuild build -project VimAction.xcodeproj -scheme VimAction \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

CI runs the engine tests and the unsigned build on every PR. The build warning baseline is **zero** — new warnings are treated as failures to fix on the spot.

Running the app itself needs the Accessibility permission. With default ad-hoc signing, every rebuild changes the code signature and silently invalidates the previous grant; if motions stop working after a rebuild, run `tccutil reset Accessibility dev.pilyang.VimAction` and re-grant in System Settings.

## Conventions

- **Commit messages**: lowercase English [conventional commits](https://www.conventionalcommits.org) — `feat(scope): …`, `fix(scope): …`. (Older history uses a different style; follow this one.)
- **Architecture invariant**: interpretation and execution stay separated. The engine in `Packages/VimActionCore` is pure Swift with no macOS dependency — it decides *what* a key means, never *how* to perform it.
- **Tests** must not touch the real `~/.config` or post real keyboard events — inject the in-memory file systems and event collectors the existing tests use.
