<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/Logo.png" alt="SwiftMediaInfo Logo" width="250">
</p>

# SwiftMediaInfo

![macOS](https://img.shields.io/badge/macOS-26+-blue)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
![Status](https://img.shields.io/badge/status-Stable-success)
![License](https://img.shields.io/badge/license-MIT-green)
![AI Built](https://img.shields.io/badge/Built%20With-AI-purple)

[![Download for macOS](https://img.shields.io/badge/Download-macOS-blue?style=for-the-badge\&logo=apple)](https://github.com/Undisclosed0369/SwiftMediaInfo/releases)

**SwiftMediaInfo** is a lightweight macOS application for viewing detailed media file information in a clean and modern interface.

It provides multiple ways to inspect media metadata, including structured views, raw output, HTML-rendered layouts, side-by-side comparison tools, and advanced export options.

Built entirely with **SwiftUI** for macOS.

---

# Features

* 📄 **Easy View** – Browse media metadata in an organized tree layout
* 📝 **Text View** – Read media information in a simplified text-focused layout
* 📝 **Raw Text View** – Inspect the Full MediaInfo output directly
* 🌐 **HTML View** – Render MediaInfo output in a styled HTML interface
* ⚖️ **Compare View** – Compare two media files side-by-side in split screen mode
* 📂 **Open in Default App** – Instantly open media files in their associated applications
* 🔎 **Zoom In / Zoom Out** – Adjust text size dynamically for easier readability
  *(Zoom using CMD + Plus and CMD + Minus)*
* ⌨️ **Keyboard Shortcuts** – Quickly switch between views and actions using keyboard shortcuts
* 📤 **Export Function** – Export metadata in multiple formats or ZIP bundles
* ⚡ **Lazy Loading Support** – Improved performance while opening large media files
* 🧠 **UTF-8 Filename Support** – Improved compatibility with special characters and non-English filenames
* ⚡ **Fast & Lightweight** – Minimal overhead with a responsive UI
* 🎨 **Native macOS Interface** – Built using SwiftUI and modern macOS design principles

---

# Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| **CMD + 1** | Easy View *(or Add File A in Compare Mode)* |
| **CMD + 2** | Text View *(or Add File B in Compare Mode)* |
| **CMD + 3** | Raw Text View |
| **CMD + 4** | HTML View |
| **CMD + 5** | XML View |
| **CMD + 6** | JSON View |
| **SHIFT + CMD + C** | Open Compare Mode |
| **CMD + Return** | Open File in Default App |
| **CMD + E** | Export |

---

# Export Formats

SwiftMediaInfo allows exporting media information into several formats:

| Format   | Description                          |
| -------- | ------------------------------------ |
| **TXT**  | Plain text MediaInfo output          |
| **HTML** | Styled HTML export                   |
| **JSON** | Structured metadata format           |
| **XML**  | Machine-readable metadata            |
| **CSV**  | Spreadsheet-friendly metadata format |
| **ZIP**  | Export all formats together          |

This makes it useful for both **human inspection and automated workflows**.

---

# Screenshots

### Easy View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/EasyView.png" width="450">
</p>

### Text View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/TextView.png" width="450">
</p>

### Compare View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/CompareView.png" width="450">
</p>

### HTML View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/HTMLView.png" width="450">
</p>

### Light Mode

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/LightMode.png" width="450">
</p>

---

# Prerequisites

SwiftMediaInfo relies on the **MediaInfo CLI tool**.

You must install it before using the app.

### Install MediaInfo via Homebrew

```bash
brew install mediainfo
````

If you do not have **Homebrew**, install it first:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

# Installation

## Option 1 — Download Release

Download the latest release from the **[Releases](https://github.com/Undisclosed0369/SwiftMediaInfo/releases)** section.

## Option 2 — Build from Source

1. Clone the repository

```bash
git clone https://github.com/Undisclosed0369/SwiftMediaInfo.git
```

2. Create a project in **Xcode**

3. Move all the files from the **SwiftMediaInfo folder** into your Xcode project

4. Build and run the app

---

# macOS Security Notice

Because SwiftMediaInfo is currently **not code-signed**, macOS Gatekeeper may show a warning such as:

> *“SwiftMediaInfo is damaged and can’t be opened.”*

This does **not mean the app is actually damaged**.

You can fix this quickly by running:

```bash
xattr -cr SwiftMediaInfo.app
```

After running the command, open the app again and it should launch normally.

---

# Requirements

* macOS 26 (older versions not tested)
* Xcode (for building from source)

---

# Feature Comparison

| Feature                  | SwiftMediaInfo | Official MediaInfo |
| ------------------------ | -------------- | ------------------ |
| Native macOS UI          | ✅              | ❌                  |
| Native Swift Code        | ✅              | ❌                  |
| Structured Metadata Tree | ✅              | ✅                  |
| HTML Rendering           | ✅              | ✅                  |
| Text View                | ✅              | ✅                  |
| Compare View             | ✅              | ❌                  |
| Raw Output               | ✅              | ✅                  |
| Open in Default App      | ✅              | ❌                  |
| Zoom In / Zoom Out       | ✅              | ❌                  |
| Multiple Export Formats  | ✅              | ✅                  |
| Keyboard Shortcuts       | ✅              | ❌                  |
| Lightweight UI           | ✅              | ✅                  |
| Lazy Loading             | ✅              | ❌                  |
| Open Source              | ✅              | ✅                  |

SwiftMediaInfo focuses on providing a **modern macOS-native interface** for MediaInfo functionality.

---

# About This Project

This project was created by **Undisclosed / Data Lass**.

It was developed with the assistance of AI tools:

* ChatGPT
* Google Gemini
* Claude

Fun fact:

> I have not typed a SINGLE line of code for this app.

---

# Easter Egg

Try clicking the **app icon repeatedly in the About window**.

You might discover something.

There may also be additional hidden surprises elsewhere.

---

# FAQ

## 1. Why does the app say it is damaged?

SwiftMediaInfo is currently **not code-signed**.

[Click here for the fix](https://github.com/Undisclosed0369/SwiftMediaInfo/tree/main#macos-security-notice)

## 2. Why do I need MediaInfo CLI installed?

SwiftMediaInfo is a frontend/interface for the official **MediaInfo CLI** tool.

The app uses the official MediaInfo backend for extracting metadata while providing a modern native macOS interface built with SwiftUI.

## 3. Does SwiftMediaInfo modify my files?

No.

SwiftMediaInfo is a **read-only metadata viewer**.

It does not edit, re-encode, modify, or touch your media files in any way.

## 4. What file formats are supported?

Any format supported by the official MediaInfo CLI tool should work inside SwiftMediaInfo.

This includes common formats such as:

* MKV
* MP4
* AVI
* MOV
* FLAC
* MP3
* WAV

and many more.

## 5. Why are there multiple view modes?

Different users prefer different workflows.

Some users prefer structured layouts, while others want raw or machine-readable output.

This makes the app suitable for both casual inspection and advanced workflows.

## 6. Is SwiftMediaInfo open source?

Yes.

The project is fully open source and available on GitHub.

## 7. Is this an official MediaInfo application?

No.

SwiftMediaInfo is an independent third-party frontend/interface for MediaInfo built specifically for macOS using SwiftUI.

However, it still uses the **official MediaInfo binary/backend** internally and simply presents the information in a more modern and native macOS interface.

## 8. Why does the app contain easter eggs?

Because software should be fun sometimes.

Also, the easter eggs are probably not even 2 KiB combined.

## 9. I spotted a bug / I have suggestions for new features for the app

You can either:

* Open an issue here:
  https://github.com/Undisclosed0369/SwiftMediaInfo/issues

or

* Contact me directly on Discord:
  `flabbergastedindividual`

Feedback, bug reports, and suggestions are always welcome.

## 10. Why are you doing this?

Honestly, I originally made this for myself.

But whenever I build something useful and have free time, I upload it publicly because there is a good chance somebody else might find it useful too.

## 11. Why can't you package the official MediaInfo binary with the app?

Good question.

The official MediaInfo binary gets updated fairly often.

Bundling it directly with SwiftMediaInfo would require me to constantly rebuild and re-release the app whenever MediaInfo updates.

Using the Homebrew version instead ensures that your MediaInfo installation can stay independently up to date (assuming you regularly update Homebrew).

## 12. Do you take donations?

Technically... no.

I intentionally avoid traditional payment methods because they reveal personal banking information.

If you *really* want to support the project, Steam gift cards are probably the easiest option.

Please contact me on Discord first though.

## 13. Did you pay for the AI chatbots used to build this app?

Absolutely not.

Only free accounts were used.

That is also probably why updates sometimes take longer than expected.

---

# License

This project is licensed under the MIT License.

See the [LICENSE](LICENSE) file for details.

---

# Author

**Undisclosed / Data Lass**

GitHub
https://github.com/Undisclosed0369

Discord
`flabbergastedindividual`

---

# Project Status

Version **1.3 Final Release**

More improvements may come in future updates.
