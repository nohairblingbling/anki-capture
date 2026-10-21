<div align="center">

# Anki Capture

**Keep reading. Turn a selection into a useful Anki card.**

A native Mac app and CLI that use your own **Codex · Claude Code · Gemini CLI**.

[English](README.md) · [简体中文](README.zh-CN.md)

[Download preview](https://github.com/nohairblingbling/anki-capture/releases) · [Quick start](#quick-start) · [Report an issue](https://github.com/nohairblingbling/anki-capture/issues)

![macOS](https://img.shields.io/badge/macOS-14%2B-333333?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-56846A)

</div>

![The capture window with sample vocabulary](docs/images/capture-en.png)

Select a word while reading a paper, browsing the web, or using a PDF reader. Press **⌃⌥⌘A**. Anki Capture generates a card in the background and adds clear results to your chosen deck. Uncertain languages or meanings wait for your review. You can also type a word or phrase manually.

## Why use it?

- **Stay in your reading flow.** A configurable global shortcut, menu bar access, and an optional Dock icon.
- **Use the CLI accounts you already have.** Connect Codex, Claude Code, or Gemini separately and choose a model. No shared account or separate backend.
- **Learn across languages.** English, Simplified Chinese, and Japanese UI, with system detection and immediate manual switching. Source vocabulary can be in other languages too.
- **Make it fit your learning.** Confirm English, Chinese, or Japanese explanations once. This choice stays independent of the interface. Optional study languages and a learning level help tailor explanations. Japanese readings can use kana.
- **Keep your captures.** A persistent local queue retains generated cards when Anki is offline. Retries reuse completed generation; duplicate checks reduce accidental repeats.
- **Keep uncertainty visible.** Ambiguous cards require review even with automatic adding enabled. Preview and edit cards, open them in Anki, or undo newly added cards that have no review history.

Words and phrases are the main focus. Short concepts such as **opportunity cost / 机会成本** also work: the prompt adapts the meaning and explanation, while the same Anki note template is retained.

## Quick start

### 1. Install

Download the Apple Silicon **macOS preview ZIP** from [Releases](https://github.com/nohairblingbling/anki-capture/releases), unzip it, and move **Anki Capture.app** to `~/Applications`.

Requires **macOS 14+**, Anki Desktop, and at least one installed official AI CLI. The current binary is **arm64**; Intel builds have not been verified.

> This is a development preview and is **not Apple-notarized**. If macOS blocks the downloaded app, build from source with your own signing identity. Do not disable system security protections.

### 2. Connect your AI

Open **AI Connections**, install a supported CLI if needed, and click **Sign in**. Complete sign-in in Terminal and the official website, then return to refresh or test the connection.

| Provider | Official CLI | Sign-in |
| --- | --- | --- |
| Codex | [Setup](https://developers.openai.com/codex/cli) | `codex login` |
| Claude Code | [Setup](https://code.claude.com/docs/en/setup) | `claude auth login` |
| Gemini CLI | [Setup](https://geminicli.com/docs/get-started/installation/) | Run `gemini`, choose **Sign in with Google**, then `/quit` |

Expand **Model & connection** to select a model, enter a custom model ID, or choose an executable path. **Test connection** makes one small AI request and never writes a card to Anki. Gemini needs this explicit test because it has no separate official authentication-status command.

![Independent provider connections, shown with demo statuses](docs/images/connections-en.png)

### 3. Connect Anki

In Anki: **Tools → Add-ons → Get Add-ons**, enter **`2055492159`** ([AnkiConnect](https://ankiweb.net/shared/info/2055492159)), install, and **restart Anki**.

In Anki Capture: **Preferences → Add to Anki → Anki connection & setup**, refresh decks, choose an existing deck, and save. Keep Anki open while adding cards. The dedicated note type is created automatically on the first write.

### 4. Choose languages and capture

On first use, **Preferences → Learning preferences** asks which language explanations should use. Confirm once before capturing. The initial selection is a suggestion; the app does not infer your native language. Your choice is saved independently: a Japanese interface can keep Chinese explanations. **Preferences → Language** changes the interface immediately, with an optional system default.

Expand **More learning preferences (optional)** to choose common study languages or a learning level. Leave them empty/Automatic if you prefer. These are hints, not restrictions; vocabulary in other languages still works. Save later changes with **⌘S**.

Each capture detects its source language using the term and supplied context. An uncertain AI result, an unknown language, or a short Han-only term without context waits at **Review & confirm**, even with automatic adding enabled. The preview shows the reason and detected language; check and edit the meaning and examples, then explicitly add it. Providing the original sentence reduces ambiguity. Detection can still make mistakes, so you can require preview for every card by turning automatic adding off.

![First-use language confirmation with demo settings](docs/images/learning-en.png)

Allow **Accessibility** for Anki Capture when prompted. Select a word or phrase in a reader, then press **Control + Option + Command + A**. Change the shortcut in Preferences if needed.

**Edge has been verified with a real global shortcut on the development machine. Chrome and PDF Expert are intended targets; behavior can vary with the page or PDF and still needs broader testing. Scanned PDFs require OCR.**

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌃⌥⌘A` | Capture selected text globally, configurable |
| `⌘1` / `⌘2` / `⌘3` | Capture / AI Connections / Preferences |
| `⌘↩` | Submit a manual capture |
| `⌘S` | Save preferences |
| `Esc` | Close a card preview |

The app follows system light/dark appearance, retains native focus indicators, exposes status and actions to accessibility tools, and adds no decorative animation. Full manual VoiceOver acceptance is still pending.

## CLI

The app bundles `Contents/MacOS/anki-capture`. Building and running `scripts/install.sh` also links it into `~/.local/bin`.

```bash
anki-capture doctor
anki-capture connections
anki-capture configure --deck 'Reading' --provider codex
anki-capture configure --language system --explanation-language zh-Hans
anki-capture configure --study-languages en,ja --learning-level intermediate
anki-capture configure --provider gemini --model flash
anki-capture generate '折り合い' --context '互いに歩み寄って、折り合いをつけた。'
anki-capture add 'in light of' --preview
anki-capture jobs
anki-capture retry JOB_ID
anki-capture run --watch
```

Set `--explanation-language en`, `zh-Hans`, or `ja` before the first `generate` or `add`; `system` is only an interface setting. `generate` only returns JSON, including `source_language`, `needs_review`, and `review_reason`. `add --preview` always waits for confirmation, while uncertain cards also wait in normal automatic mode. Inspect `jobs`, then `retry JOB_ID` explicitly confirms a reviewed card. `add --queue-only` only persists a capture. Data commands accept `--data-dir PATH` for an isolated workspace. Use `--help` for all commands.

## Data and privacy

- Settings and queued cards stay in `~/Library/Application Support/AnkiCapture/`. The release archive contains no personal configuration, queue, or login tokens.
- Your selected text, context, and supplied source are sent through the chosen official CLI to its configured model service. Model inference generally happens in the cloud.
- Login credentials, quotas, subscriptions, API keys, and billing remain under the CLI's configuration. CLI subscription access depends on your account; using an API key may incur separate charges.
- The app reads selections only when invoked. It may use a copy-shortcut fallback and restores the clipboard when safe; it does not continuously monitor the clipboard.
- Generated fields are plain text and escaped before writing to Anki. AnkiConnect is restricted to local HTTP addresses. AI subprocesses are configured without tool access.

Changing languages does not translate existing cards. New captures remember their explanation language and learning hints. Upgrading keeps existing explicit explanation choices; the former “Same as interface” setting asks for one independent confirmation. Pre-0.3 queued captures retain their original Chinese explanation behavior. Historical JSON names such as `meaning_zh` and `example_en` remain for compatibility and do **not** restrict card languages. Confirmed reviews and edited content survive Anki outages and restarts without regenerating.

## Build and contribute

Requires **Xcode 16+ / Swift 6**. SQLite is provided by macOS.

```bash
git clone https://github.com/nohairblingbling/anki-capture.git
cd anki-capture
swift test
python3 scripts/check-localizations.py
scripts/build-app.sh
scripts/install.sh
```

To retain Accessibility approval between builds, put your local signing identity in a Git-ignored `.signing-identity` file, or set `ANKI_CAPTURE_SIGNING_IDENTITY`. Otherwise the build uses ad-hoc signing and a rebuild may require renewed permission.

Translations live in `App/Translations.json`. After editing, run `python3 scripts/check-localizations.py --write`. The checker validates coverage and format arguments. `scripts/render-ui.sh` creates isolated demo previews for all three languages, both appearances, and narrow windows; it does not connect to AI or Anki. Screenshots above show demo content, not a user's collection.

- [Architecture](docs/architecture.md) · [Validation](docs/validation.md) · [AI connections](docs/connections.md)
- [Product principles](PRODUCT.md) · [Design conventions](DESIGN.md)
- [Sharing guide and launch drafts](docs/sharing.md)

Bug reports, language corrections, and testing on different readers are welcome. If this helps your reading workflow, a GitHub star helps others find it.

## License

[MIT](LICENSE). This is an independent project, not an official Anki, OpenAI, Anthropic, or Google application.
