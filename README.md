<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/Logo.png" alt="SwiftMediaInfo Logo" width="250">
</p>

# SwiftMediaInfo

![macOS](https://img.shields.io/badge/macOS-26+-blue)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
![Status](https://img.shields.io/badge/status-Stable-success)
![AI Built](https://img.shields.io/badge/Built%20With-AI-purple)

[![Download for macOS](https://img.shields.io/badge/Download-macOS-blue?style=for-the-badge\&logo=apple)](https://github.com/Undisclosed0369/SwiftMediaInfo/releases)

**SwiftMediaInfo** is a lightweight macOS application for viewing detailed media file information in a clean and modern interface.

It provides multiple ways to inspect media metadata, including structured views, raw output, and an HTML-rendered layout.

Built entirely with **SwiftUI** for macOS.

---

# Features

* 📄 **Structured View** – Browse media metadata in an organized tree layout
* 🌐 **HTML View** – Render MediaInfo output in a styled HTML interface
* 📝 **Raw Text View** – Inspect the original MediaInfo output directly
* 🔎 **Zoom In / Zoom Out** – Adjust text size dynamically for easier readability
* 📤 **Export Function** – Export metadata in multiple formats
* ⚡ **Fast & Lightweight** – Minimal overhead with a responsive UI
* 🎨 **Native macOS Interface** – Built using SwiftUI and modern macOS design principles

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

This makes it useful for both **human inspection and automated workflows**.

---

# Screenshots

*(Screenshots coming soon)*

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
| Raw Output               | ✅              | ✅                  |
| Zoom In / Zoom Out       | ✅              | ❌                  |
| Multiple Export Formats  | ✅              | ✅                  |
| Lightweight UI           | ✅              | ✅                  |
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

---

# License

uhh idc so idk lol

---

# Author

**Undisclosed / Data Lass**

GitHub
https://github.com/Undisclosed0369

Discord
flabbergastedindividual

---

# Project Status

Version **1.0 Final Release**

More improvements may come in future updates.
