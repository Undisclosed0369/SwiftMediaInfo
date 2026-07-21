<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/Logo.png" alt="SwiftMediaInfo Logo" width="320">
</p>

# SwiftMediaInfo

![macOS](https://img.shields.io/badge/macOS-26+-blue)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
![Homebrew](https://img.shields.io/badge/Homebrew-Available-success)
![Status](https://img.shields.io/badge/status-Stable-success)
![License](https://img.shields.io/badge/license-MIT-green)
![AI Built](https://img.shields.io/badge/Built%20With-AI-purple)

[![Download for macOS](https://img.shields.io/badge/Download-macOS-blue?style=for-the-badge&logo=apple)](https://github.com/Undisclosed0369/SwiftMediaInfo/releases)

**SwiftMediaInfo** is a lightweight macOS application for viewing detailed media file information in a clean and modern interface.

It provides multiple ways to inspect media metadata, including structured views, raw output, HTML-rendered layouts, side-by-side comparison tools, and advanced export options.

Built entirely with **SwiftUI** for macOS.

---

## 💡 Your Feedback Matters!

I'm actively improving SwiftMediaInfo and would love your feedback.

If you have an idea for a new feature, workflow improvement, or UI enhancement or if you just want to talk about your experience with the app, please submit it here:

[Feedback Form](https://forms.gle/ZoDwomdm5asgfj386) (~ 90 seconds avg. depending on answers)

Every submission is read and considered for future releases. Thank you for helping shape SwiftMediaInfo!

---

# Features

* 📄 **Easy View** – Browse media metadata in an organized tree layout
* 📝 **Text View** – Read media information in a simplified text-focused layout
* 📝 **Raw Text View** – Inspect the Full MediaInfo output directly
* 🌐 **Webkit-Powered HTML View** – Rewritten HTML rendering using WKWebView with custom CSS themes, smooth zooming, and injected search match highlights
* ⚖️ **Compare View** – Compare two media files side-by-side in split screen mode with split status bar details and marquee scrolling filenames
* 🌐 **Share Online** – Upload metadata directly to paste services (`pb.plz.ac` for text/code or `up.sb` for ZIP bundles) and instantly copy shareable links
* 🔍 **Floating Search & Fuzzy Matching** – Non-intrusive global search (`⌘F`) with match counts, navigation arrows, and space-normalized fuzzy terms (e.g. "bitrate" matches "Bit Rate")
* ⚖️ **Difference Highlighting** – Color-coded field and line comparison (`⌘D`) with track-level difference count badges in Compare Mode
* 🎨 **Native macOS Interface** – Built using SwiftUI and modern macOS design principles
* 🎨 **Liquid Glass UI** – Modern, sleek, translucent interface designed strictly for macOS with zero-overhead background animation pause logic
* 🛠 **Finder Context Menu** – Right-click any file in Finder to instantly open it directly in SwiftMediaInfo
* 🛠 **Dependency Diagnostic Check** – Automatically checks for `mediainfo`, `curl`, and `zip` on launch with one-click installation prompts
* 📂 **Unified Open Action** – Smart, single-button workflow for opening both files and folders seamlessly
* 🕒 **Recent Files** – Quickly re-open and access recently inspected media assets
* 📂 **Open in Default App** – Instantly open media files in their associated applications
* 🔎 **Zoom In / Zoom Out** – Adjust text size dynamically for easier readability with capsule pill zoom badges
  *(Zoom using CMD + Plus and CMD + Minus)*
* ⌨️ **Keyboard Shortcuts & Quick Reference** – Full keyboard navigation plus an interactive reference window (`⌘K`)
* 📤 **Export Function** – Export metadata in multiple formats or ZIP bundles
* ⚡ **Lazy Loading & Thread Offloading Support** – Improved performance while parsing large complex media files on background tasks
* 🧠 **UTF-8 Filename Support** – Improved compatibility with special characters and non-English filenames
* ⚡ **Fast & Lightweight** – Optimized and cleaned codebase for rapid, resource-efficient performance

---

# Screenshots

### Easy View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC1_EasyView.png" width="600">
</p>

### Text View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC2_TextView.png" width="600">
</p>

### Compare View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC3_CompareView.png" width="600">
</p>

### Highlight Difference in Compare View (works in Easy, Text and Raw Text View)

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC4_HighlightDifferences.png" width="600">
</p>

### Search Function

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC5_Search.png" width="600">
</p>

### HTML View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC6_HTMLView.png" width="600">
</p>

### Share Function

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC7_Share.png" width="600">
</p>

### Light Mode

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC8_LightMode.png" width="600">
</p>

---

# Feature Comparison

| Feature | SwiftMediaInfo | Official MediaInfo |
| --- | --- | --- |
| **Native macOS UI & Swift Code** | ✅ | ❌ |
| **Liquid Glass UI** | ✅ | ❌ |
| **Online Sharing & Links** | ✅ | ❌ |
| **Global Fuzzy Search Bar** | ✅ | ❌ |
| **Difference Highlighting** | ✅ | ❌ |
| **Compare View** | ✅ | ❌ |
| **Open in Default App** | ✅ | ❌ |
| **Zoom In / Zoom Out** | ✅ | ❌ |
| **Keyboard Shortcuts Reference** | ✅ | ❌ |
| **Lazy Loading & Background Parsing** | ✅ | ❌ |
| **Structured Metadata Tree** | ✅ | ✅ |
| **HTML Rendering** | ✅ | ✅ |
| **Text View** | ✅ | ✅ |
| **Recent Files** | ✅ | ✅ |
| **Raw Output** | ✅ | ✅ |
| **Multiple Export Formats** | ✅ | ✅ |
| **Lightweight UI** | ✅ | ✅ |
| **Open Source** | ✅ | ✅ |

SwiftMediaInfo focuses on providing a **modern macOS-native interface** for MediaInfo functionality.

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
| **CMD + F** | Search / Filter Bar |
| **CMD + D** | Toggle Difference Highlighting |
| **CMD + B** | Toggle Animated Background |
| **CMD + K** | Keyboard Shortcuts Reference |
| **CMD + M** | Cycle Appearance (Light → Dark → System) |
| **CMD + 0** | Reset Zoom to 100% |
| **CMD + E** | Export |


Too many Keyboard Shortcuts to remember? You can now use **CMD + K** to open the Keyboard Shortcuts Panel in the app!

---

# Export Formats

SwiftMediaInfo allows exporting media information into several formats:

| Format   | Description                          |
| -------- | ------------------------------------ |
| **TXT** | Plain text MediaInfo output          |
| **HTML** | Styled HTML export                   |
| **JSON** | Structured metadata format           |
| **XML** | Machine-readable metadata            |
| **CSV** | Spreadsheet-friendly metadata format |
| **ZIP** | Export all formats together          |

This makes it useful for both **human inspection and automated workflows**.

---

# Prerequisites

SwiftMediaInfo relies on the **MediaInfo CLI tool**.

You must install it before using the app.

### Install MediaInfo via Homebrew

```bash
brew install mediainfo

```

If you do not have **Homebrew**, install it first:

```bash
/bin/bash -c "$(curl -fsSL [https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh](https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh))"

```

---

# Installation & Management

## Option 1 — Via Homebrew (Recommended)

SwiftMediaInfo is officially available as a Homebrew Cask. You can manage the application lifecycle entirely from your terminal.

### Install

```bash
brew tap Undisclosed0369/swiftmediainfo
brew install --cask swiftmediainfo

```

### Update

To update SwiftMediaInfo to the latest stable release:

```bash
brew update
brew upgrade --cask swiftmediainfo

```

### Uninstall

If you ever need to completely remove the application and its associated files:

```bash
brew uninstall swiftmediainfo

```

## Option 2 — Manual Download Release

Download the latest pre-compiled application bundle directly from the **[Releases](https://github.com/Undisclosed0369/SwiftMediaInfo/releases)** section.

## Option 3 — Build from Source

1. Clone the repository:

```bash
git clone https://github.com/Undisclosed0369/SwiftMediaInfo.git

```

2. Create a new macOS project in **Xcode**.
3. Move all files from the cloned **SwiftMediaInfo folder** into your Xcode project hierarchy.
4. Build and run the app (`CMD + R`).

---

# macOS Security Notice

Because SwiftMediaInfo is currently **not code-signed** (when manually downloading or building from source), macOS Gatekeeper may show a warning such as:

> *“SwiftMediaInfo is damaged and can’t be opened.”*

This does **not mean the app is actually damaged**. You can resolve this issue quickly by clearing the quarantine attributes using your terminal:

```bash
xattr -cr SwiftMediaInfo.app

```

After running the command, open the app again and it should launch normally.

---

# Requirements

* macOS 26 (older versions not tested)
* Xcode (only required for building from source)

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

See the [LICENSE](https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/LICENSE) file for details.

---

# Author

**Undisclosed / Data Lass**

GitHub
https://github.com/Undisclosed0369

Discord
`flabbergastedindividual`

---

# Project Status

Version **1.6 Final Release**

More improvements may come in future updates.
