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

It provides multiple ways to inspect media metadata, including structured views, raw output, HTML-rendered layouts, and side-by-side comparison tools.

Built entirely with **SwiftUI** for macOS.

---

# Features

* 📄 **Easy View** – Browse media metadata in an organized tree layout
* 📝 **Text View** – Read media information in a simplified text-focused layout
* 📝 **Raw Text View** – Inspect the Full MediaInfo output directly
* 🌐 **HTML View** – Render MediaInfo output in a styled HTML interface
* ⚖️ **Compare View** – Compare two media files side-by-side in split screen mode
* 🔎 **Zoom In / Zoom Out** – Adjust text size dynamically for easier readability
  *(Zoom using CMD + Plus and CMD + Minus)*
* ⌨️ **Keyboard Shortcuts** – Quickly switch between views and actions using keyboard shortcuts
* 📤 **Export Function** – Export metadata in multiple formats
* ⚡ **Lazy Loading Support** – Improved performance while opening large media files
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

This makes it useful for both **human inspection and automated workflows**.

---

# Screenshots

### Easy View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC1-EasyView1.png" width="450">
</p>

### Text View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC2-TextView.png" width="450">
</p>

### Compare View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC3-CompareView.png" width="450">
</p>

### HTML View

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC4-HTMLView.png" width="450">
</p>

### Light Mode

<p align="center">
<img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/SC5-LightMode.png" width="450">
</p>

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

Version **1.2 Final Release**

More improvements may come in future updates.
