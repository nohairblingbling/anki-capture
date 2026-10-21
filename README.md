<div align="center">

# Anki Capture

**Keep reading. Turn a selection into an Anki card.**

A native Mac app powered by your own **Codex · Claude Code · Gemini CLI**.

[English](README.md) · [简体中文](README.zh-CN.md)

[Download for Mac](https://github.com/nohairblingbling/anki-capture/releases/download/v0.5.1/AnkiCapture-0.5.1-macOS-universal.dmg) · [Releases](https://github.com/nohairblingbling/anki-capture/releases) · [Feedback](https://github.com/nohairblingbling/anki-capture/issues)

![macOS](https://img.shields.io/badge/macOS-14%2B-333333?logo=apple)
![License](https://img.shields.io/badge/license-MIT-56846A)

</div>

![Anki Capture with sample vocabulary](assets/capture-en.png)

Select a word or phrase while reading a paper, web page, or document, then press **⌃⌥⌘A**. Anki Capture uses your chosen AI to generate a card and add it to your selected Anki deck. You can also enter text manually.

## What it does

- **Capture without leaving your reading flow.** A configurable global shortcut, menu bar access, and an optional Dock icon.
- **Create useful cards with AI.** Generate meanings, definitions, pronunciation, and examples for words, phrases, and short concepts.
- **Choose or create your deck.** Create a deck or a nested subdeck directly in Preferences and use it as the capture destination.
- **Use your own AI account.** Connect Codex, Claude Code, or Gemini independently and choose a model through the official CLI installed on your Mac.
- **Learn across languages.** Automatically detect the term’s language. Choose English, Chinese, or Japanese explanations independently of the interface language, with optional study-language and learning-level preferences.
- **Review uncertain results.** Ambiguous languages or meanings wait for your confirmation. Preview and edit cards before adding them, or enable automatic adding for clear results.
- **Keep captures available.** A local queue preserves generated cards when Anki is offline, reuses them on retry, and checks for duplicates. Open saved cards in Anki or undo newly added cards that have no review history.

The interface supports **English, Simplified Chinese, and Japanese**, follows system light/dark appearance, and includes a companion CLI.

Download the DMG, drag **Anki Capture** to **Applications**, then open it. No Xcode or build tools are needed. A ZIP and SHA-256 checksums are also available in [Releases](https://github.com/nohairblingbling/anki-capture/releases/tag/v0.5.1).

Requires macOS 14+, Anki Desktop with AnkiConnect (add-on code **2055492159**), and at least one supported AI CLI. The universal build contains Apple Silicon and Intel executables; Apple Silicon is tested, Intel hardware has not been tested yet.

This is a development preview and is **not Apple-notarized**. If macOS blocks the first launch and you trust this release, go to **System Settings → Privacy & Security → Open Anyway** after trying to open it. See [Apple's instructions](https://support.apple.com/en-us/102445). Grant Accessibility access when prompted to enable selection capture.

[MIT License](LICENSE). An independent project.
