<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/Logo.png" alt="SwiftMediaInfo" width="300">
</p>

<h1 align="center">SwiftMediaInfo</h1>

<p align="center"><em>The Power of MediaInfo, Beautifully Reimagined for macOS.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white" alt="macOS 26 or later">
  <img src="https://img.shields.io/badge/Apple%20silicon-required-000000?logo=apple&logoColor=white" alt="Apple silicon required">
  <img src="https://img.shields.io/badge/SwiftUI-F05138?logo=swift&logoColor=white" alt="Built with SwiftUI">
  <img src="https://img.shields.io/badge/licence-MIT-2ea44f" alt="MIT licence">
  <img src="https://img.shields.io/badge/version-2.1-8d42f5" alt="Version 2.1">
</p>

<p align="center">
  <a href="https://undisclosed0369.app/swiftmediainfo/"><strong>Website</strong></a> ·
  <a href="https://undisclosed0369.app/swiftmediainfo/download"><strong>Download</strong></a> ·
  <a href="https://undisclosed0369.app/swiftmediainfo/features"><strong>Features</strong></a> ·
  <a href="https://undisclosed0369.app/swiftmediainfo/faq"><strong>FAQ</strong></a> ·
  <a href="https://undisclosed0369.app/swiftmediainfo/online"><strong>Online</strong></a> ·
  <a href="https://undisclosed0369.app/swiftmediainfo/changelog"><strong>Changelog</strong></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC1-Overview.png" width="820" alt="SwiftMediaInfo showing a video file in Easy View, with the Overview card summarising its video, audio and subtitles">
</p>

<p align="center">
  <strong>A native macOS front-end for <a href="https://mediaarea.net/en/MediaInfo">MediaInfo</a>.</strong><br>
  Read what is actually inside a media file — and never write a byte back.
</p>

<table>
<tr>
<td width="33%" valign="top">

**🗂 Tabs**

Every file in its own tab, and a folder as one tab with its media files beside the report.

</td>
<td width="33%" valign="top">

**⚖️ Compare two files**

Any two open tabs, side by side, with every difference marked.

</td>
<td width="33%" valign="top">

**🔎 An Overview of every file**

Video, main audio and subtitles at a glance, before the details.

</td>
</tr>
<tr>
<td valign="top">

**🩺 Media Health**

Common problems found, and explained in plain language.

</td>
<td valign="top">

**▶️ Preview with Space**

MKV included, with every subtitle track — Blu-ray PGS too.

</td>
<td valign="top">

**✨ Siri AI**

Ask what a file is, or which copy is better. Answered on your Mac.

</td>
</tr>
<tr>
<td valign="top">

**📖 ~70 fields explained**

Plain language, inline, for the ones nobody remembers.

</td>
<td valign="top">

**📄 Eight export formats**

PDF and Markdown among them, or all of them in a ZIP.

</td>
<td valign="top">

**🎨 Yours to look at**

Liquid Glass, three background modes, colours you pick.

</td>
</tr>
</table>

> [!NOTE]
> **New in 2.1** — tabs and folder tabs, a Compare Mode rebuilt around them, the Overview card, Media Health, previews with Space, Siri AI, PDF and Markdown reports, syntax highlighting, favorites, and an app that scrolls at a steady 100 fps on a fraction of the power. **[Read the release notes →](https://github.com/Undisclosed0369/SwiftMediaInfo/releases/latest)**

---

## Your feedback matters

I am actively improving SwiftMediaInfo and would like to hear from you.

If you have an idea for a feature, a workflow improvement, a UI change, or you simply want to say how you have found it, the form below takes about ninety seconds:

**[Feedback form](https://forms.gle/ZoDwomdm5asgfj386)**

Every submission is read and considered for a future release.

---

## Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [SwiftMediaInfo and MediaInfo for Mac](#swiftmediainfo-and-mediainfo-for-mac)
- [Requirements](#requirements)
- [Installing](#installing)
- [If macOS won't open the app](#if-macos-wont-open-the-app)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Export formats](#export-formats)
- [Privacy](#privacy)
- [How this was built](#how-this-was-built)
- [FAQ](#faq)
- [Easter egg](#easter-egg)
- [Licence](#licence)
- [Author](#author)
- [Project status](#project-status)

---

## Features

### 🗂 Opening files

<table>
<tr>
<td width="50%" valign="top">

**Tabs, Safari-style**

Every file opens in a tab. `⌘T` for a new one, drag to reorder, or drag a tab out onto another app to open the original there. Opening a file that is already open switches to its tab.

</td>
<td width="50%" valign="top">

**Folder tabs**

Drop a folder for one tab named after it, with a sidebar of its media files — subfolders included. Only the file you pick is analysed; `⌥⌘↓` / `⌥⌘↑` step through them.

</td>
</tr>
<tr>
<td valign="top">

**Drag-and-drop that does what you mean**

One file opens a tab, two open a comparison, three or more open a tab each, a folder opens a folder tab — onto the window, the panes or the Dock icon.

</td>
<td valign="top">

**Finder, and the website**

Right-click files, a folder or several items in Finder to open them here — switched on for you the first time the app opens. And **Open in SwiftMediaInfo** on the [Online page](https://undisclosed0369.app/swiftmediainfo/online) finds the same file on your Mac.

</td>
</tr>
<tr>
<td valign="top">

**Favorites**

A star on every tab. Favorites sit on the start screen, in File › Favorites, and wherever you pick a file to compare.

</td>
<td valign="top">

**A start screen worth landing on**

Favorites, recent files, the time you have spent in the app, and fifty fun facts about it.

</td>
</tr>
</table>

### 🔎 Reading a file

<table>
<tr>
<td width="50%" valign="top">

**The Overview card**

Video codec, resolution, frame rate, bit rate, colour and HDR; the main audio track; every subtitle track — with colour-coded highlights that stay visible when the card is folded.

</td>
<td width="50%" valign="top">

**Six views of the same report**

Easy View, Text, Raw Text, HTML, XML and JSON. Switch with `⌃⌘1` – `⌃⌘6`. JSON and XML are syntax-highlighted.

</td>
</tr>
<tr>
<td valign="top">

**Around 70 fields explained**

Hover a field name for plain language — for anyone who has wondered what chroma subsampling actually is.

</td>
<td valign="top">

**Search and copy anything**

`⌘F` searches every field at once, and `bitrate` finds `Bit Rate`. Copy a value, a field, a whole track as Markdown, or the Overview.

</td>
</tr>
</table>

### 🩺 Checking a file

<table>
<tr>
<td width="50%" valign="top">

**Media Health (`⇧⌘H`)**

Checks the container, the format and its extension, the streams, track IDs, variable frame rate, HDR metadata, language tags and durations — and says what each problem means and what to do about it.

</td>
<td width="50%" valign="top">

**SHA-256 checksums**

Computed when you ask, cached, and carried into reports when you want them — so an archive copy can be checked against the original years later.

</td>
</tr>
<tr>
<td valign="top">

**Siri AI (`⇧⌘I`)**

Ask what a file is, whether it is healthy, or which of two copies is better. Apple's on-device model reads the text report — never the file — and nothing leaves your Mac.

</td>
<td valign="top">

**Knows what is normal**

A song without video, or an untagged music file, is not a problem — and is not flagged as one.

</td>
</tr>
</table>

### ⚖️ Comparing two files

<table>
<tr>
<td width="50%" valign="top">

**Any two tabs**

`⌘`-click a tab, right-click → **Compare With**, or `⌘⇧C`. File A is the selected tab and File B another one, so nothing is read twice.

</td>
<td width="50%" valign="top">

**Differences marked**

`⌘D` highlights what changed at field *and* line level, with a summary panel that jumps to each difference.

</td>
</tr>
<tr>
<td valign="top">

**Swap the sides**

Click File B's tab, press `⌘⇧S`, or use the control on the divider.

</td>
<td valign="top">

**Drop to compare**

Drop two files at once, or hold `⌥` while dragging a second file onto one already open.

</td>
</tr>
</table>

### ▶️ Previewing a file

<table>
<tr>
<td width="50%" valign="top">

**Space, as in Finder**

Files macOS can play open in Quick Look. **MKV, AVI, WebM, TS** and the rest open in SwiftMediaInfo's own preview — 4K, HDR and Dolby Vision included.

</td>
<td width="50%" valign="top">

**Every subtitle track**

Text subtitles play in macOS's player; picture subtitles — **Blu-ray PGS**, DVD, DVB — are drawn exactly as on the disc, in full screen too.

</td>
</tr>
<tr>
<td valign="top">

**A filmstrip of the whole file**

Hover for a time, click or drag to play from anywhere, or skip ten seconds with ← / →.

</td>
<td valign="top">

**Your file is never changed**

Short clips are cut from the original and deleted the moment the preview closes. Uses ffmpeg, which the app installs in one click.

</td>
</tr>
</table>

### 📤 Exporting and sharing

<table>
<tr>
<td width="50%" valign="top">

**Eight formats**

Text, Raw Text, HTML, **PDF** and **Markdown** for people; CSV, JSON and XML for tools. One at a time, all eight, or a ZIP.

</td>
<td width="50%" valign="top">

**Share as a web page**

HTML and PDF become a page on ship.page, Markdown a rendered page on markdown.page — or a plain link for the text formats.

</td>
</tr>
<tr>
<td valign="top">

**Review before upload**

Every report is shown first, with what will be removed — paths are stripped by default, and the checksum stays out unless you say otherwise.

</td>
<td valign="top">

**Light or dark, as you see it**

HTML and PDF follow the app's appearance at the moment you export, and HTML looks exactly like the in-app view.

</td>
</tr>
</table>

### 🎨 The interface

<table>
<tr>
<td width="50%" valign="top">

**Liquid Glass**

Built on macOS 26 and written entirely in SwiftUI. Not a web view in a window.

</td>
<td width="50%" valign="top">

**Fast and light**

A steady 100 fps scroll, a fraction of the GPU and CPU, and less memory — with the same look.

</td>
</tr>
<tr>
<td valign="top">

**A background you own**

Off, static or animated, in three colours you choose or four ready-made palettes — and with Static, you place the colours yourself.

</td>
<td valign="top">

**Seven panes of settings**

General, Appearance, Analysis, Tools, Siri AI, Privacy and Advanced — with scaling that zooms the whole layout, not just the text.

</td>
</tr>
<tr>
<td valign="top">

**Accessibility throughout**

VoiceOver on every control, built into the shared components. Reduce Motion and Reduce Transparency honoured everywhere.

</td>
<td valign="top">

**Complete keyboard control**

Every action reachable from the keyboard, with a reference window at `⌘K`.

</td>
</tr>
</table>

---

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC2-Tabs.png" width="700" alt="SwiftMediaInfo with several files open in tabs, and a folder tab listing its media files">
  <br><em>Tabs, and a folder opened as a single tab</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC3-Compare.png" width="700" alt="SwiftMediaInfo comparing two open tabs side by side, with the differences highlighted">
  <br><em>Compare Mode — two of your open tabs, with every difference marked</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC4-MediaHealth.png" width="700" alt="The Media Health window listing its checks and explaining a warning">
  <br><em>Media Health — common problems found, and what to do about them</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC5-Preview.png" width="700" alt="The SwiftMediaInfo preview playing an MKV film with its subtitles and a filmstrip of the whole file">
  <br><em>Preview with Space — MKV included, with every subtitle track</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC6-SiriAI.png" width="700" alt="The Siri AI window answering a question about a video file">
  <br><em>Siri AI — answered on your Mac</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC7-PDFReport.png" width="700" alt="A PDF report exported from SwiftMediaInfo, with the overview and a table for each track">
  <br><em>A PDF report, ready to send</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC8-FieldExplanations.png" width="700" alt="Plain-language explanation of a MediaInfo field in SwiftMediaInfo">
  <br><em>Around seventy fields explained in plain language</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC9-StartScreen.png" width="700" alt="The SwiftMediaInfo start screen with favorites, recent files and the time spent in the app">
  <br><em>The start screen — favorites, recent files, and the time you have spent</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC10-Settings.png" width="700" alt="SwiftMediaInfo settings on macOS">
  <br><em>Seven panes of settings</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/SC11-LightCustomBG.png" width="700" alt="SwiftMediaInfo in light appearance with a custom background">
  <br><em>Light appearance, with a custom background</em>
</p>

---

## SwiftMediaInfo and MediaInfo for Mac

MediaArea make their own Mac application. It is good, it has been maintained for years, and it does several things this one does not. Here is the honest comparison — the last four rows are theirs.

| | SwiftMediaInfo | MediaInfo for Mac |
| --- | --- | --- |
| **Price** | Free | The tool is free; the Mac app is paid, plus an in-app purchase |
| **Licence** | MIT, open source | The MediaInfo library is BSD; the Mac app is sold |
| **Interface** | Liquid Glass, written entirely in SwiftUI | Shared across five platforms |
| **Side-by-side comparison** | Included | Requires the in-app purchase |
| **Difference highlighting** | Field and line level, with per-track counts | — |
| **Field explanations** | Around 70 fields | — |
| **SHA-256 checksums** | Yes | — |
| **Tabs** | Every file in a tab, folders as a single tab | — |
| **Media health checks** | Common problems found and explained | — |
| **Preview** | Space to preview, MKV included, with subtitles | — |
| **AI explanations** | Siri AI, on device | — |
| **Search** | Global fuzzy search across every field | — |
| **Share online** | Upload a report and get a link | — |
| **Interface zoom** | Scales the whole interface | — |
| **Keyboard shortcuts** | Full, with a reference window | — |
| **Finder integration** | Context menu for files, folders and several files at once, Compare from the menu, drag-and-drop, and ⌥-drag to compare directly | Context menu and drag-and-drop |
| **Export formats** | TXT, Raw TXT, HTML, PDF, Markdown, CSV, JSON and XML — one at a time, all eight separately, or bundled as a ZIP | Text, XML, JSON, EBUCore and more |
| **Appearance** | Light, dark or system, with an off, static or animated background in colours you choose | Follows the system |
| **Platforms** | macOS 26 and later | macOS, Windows, Linux, Android, iOS |
| **Languages** | English | 37 languages |
| **Signed and notarised** | No | Yes, via the App Store |

If you need Windows, Linux, a language other than English, or a signed application, theirs is the better choice and you should use it.

---

## Requirements

| | |
| --- | --- |
| **macOS** | 26 or later |
| **Mac** | Apple silicon |
| **MediaInfo** | Required — the app checks for it on launch and offers to install it for you |
| **ffmpeg** | Optional — only for previewing MKV and other formats macOS cannot play. Offered the first time you need it |
| **Siri AI** | A Mac that supports Apple Intelligence, running macOS 27 or later, with Apple Intelligence turned on |

Neither tool is bundled with the app, so that your copies can be updated independently. If you would rather install them yourself:

```bash
brew install mediainfo ffmpeg
```

And if you do not have Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

## Installing

### Homebrew — recommended

```bash
brew trust undisclosed0369/swiftmediainfo && brew install --cask swiftmediainfo
```

One command. The first half tells Homebrew you are willing to install from this project's repository — since Homebrew 6.0, a tap that is not one of the official ones has to be trusted before Homebrew will read anything inside it. The second half installs the app.

MediaInfo is declared as a dependency, so Homebrew installs it for you if you do not already have it. And because Homebrew clears macOS's download mark itself, the app opens straight away — no warning.

### Disk image

Download `SwiftMediaInfo-2.1.dmg` from [Releases](https://github.com/Undisclosed0369/SwiftMediaInfo/releases/latest) and drag the app into Applications.

macOS will refuse to open it the first time. That is expected — see the next section.

### Building from source

```bash
git clone https://github.com/Undisclosed0369/SwiftMediaInfo.git
cd SwiftMediaInfo/SwiftMediaInfo
open SwiftMediaInfo.xcodeproj
```

Then build and run with `⌘R`. You will need Xcode 26 or later.

Two notes. The project has two targets — the app and the Finder extension — and both need a signing team set; "Sign to Run Locally" is enough for your own machine. And a locally built copy is unsigned, so the section below applies to it too.

---

## If macOS won't open the app

SwiftMediaInfo is not signed with an Apple Developer certificate, which costs $99 a year. So the first time you open the disk image's copy, macOS stops it:

> **"SwiftMediaInfo.app" Not Opened**
> Apple could not verify "SwiftMediaInfo.app" is free of malware that may harm your Mac or compromise your privacy.

That is the message for any app without a certificate — not a sign that anything is wrong with this one. To open it:

1. Choose **Done** — not Move to Trash.
2. Open **System Settings › Privacy & Security** and scroll down to **Security**.
3. Next to *"SwiftMediaInfo.app" was blocked to protect your Mac*, choose **Open Anyway**, and confirm with your password or Touch ID.
4. Open the app again. If macOS asks once more, choose **Open Anyway**.

From then on it opens normally. A new version downloaded by hand is checked again, once.

**Prefer Terminal?** This removes the download mark from this one app and nothing else, and it opens without the dialog at all:

```bash
xattr -dr com.apple.quarantine /Applications/SwiftMediaInfo.app
```

Installing through Homebrew avoids all of this: the cask runs that same command for you once the app is in place, and prints a note saying it did. Homebrew used to offer a `--no-quarantine` flag for the job; it was removed in 4.7, which is why the work moved into the cask.

> [!IMPORTANT]
> Both routes tell macOS to stop checking a file, and you should not do that for anything you do not have a reason to trust. The reason to trust this one is that the source is public — read it, or build it yourself and skip the question. The [download page](https://undisclosed0369.app/swiftmediainfo/download) explains what the warning actually means in more detail.

---

## Updating

Update everything Homebrew installed — SwiftMediaInfo, MediaInfo, ffmpeg and the rest:

```bash
brew update && brew upgrade
```

Or SwiftMediaInfo alone:

```bash
brew update && brew upgrade --cask swiftmediainfo
```

Your settings, favorites and the time you have spent in the app carry over. Quit SwiftMediaInfo first, so the new version is the one that opens next.

Installed the disk image by hand? Download the new one and replace the app in Applications. macOS checks the new copy once, as it did the first time.

---

## Uninstalling

Remove the app and keep your settings — your colours, zoom level, favorites, recent files and time spent — ready for if you reinstall:

```bash
brew uninstall --cask swiftmediainfo
```

Or remove everything SwiftMediaInfo wrote, settings and caches included:

```bash
brew uninstall --cask --zap swiftmediainfo
```

Installed by hand? Drag the app to the Trash. To remove its settings and caches too:

```bash
defaults delete app.undisclosed0369.SwiftMediaInfo
rm -rf ~/Library/Application\ Support/SwiftMediaInfo
```

Neither touches your media — SwiftMediaInfo only ever reads it. MediaInfo and ffmpeg stay installed too, since other software may be using them.

---

## Keyboard shortcuts

Press `⌘K` in the app for this list at any time.

<details open>
<summary><strong>File</strong></summary>

| Shortcut | Action |
| --- | --- |
| `⌘T` | New tab, showing the start screen |
| `⌘O` | Open a file or folder in a new tab |
| `⌘W` | Close the tab — closes the window once no tabs are open |
| `⌥⌘W` | Close the window |
| `⌘⇧]` / `⌘⇧[` | Next / previous tab — or `⌃⇥` / `⌃⇧⇥` |
| `⌥⌘↓` / `⌥⌘↑` | Next / previous file in a folder tab |
| Middle-click | Close a tab — or open a recent file in a background tab |
| `⌘⏎` | Open the file in its default app |

</details>

<details open>
<summary><strong>Tabs</strong></summary>

| Shortcut | Action |
| --- | --- |
| `⌘1` – `⌘8` | Show that tab |
| `⌘9` | Show the last tab |

In Compare Mode, `⌘1` and `⌘2` choose File A and File B.

</details>

<details open>
<summary><strong>File actions</strong></summary>

| Shortcut | Action |
| --- | --- |
| `⌘⇧R` | Reveal in Finder |
| `⌥⌘C` | Copy the full file path |
| `⌘⌫` | Move the file to the Trash |

</details>

<details open>
<summary><strong>View modes</strong></summary>

| Shortcut | Action |
| --- | --- |
| `⌃⌘1` | Easy View |
| `⌃⌘2` | Text View |
| `⌃⌘3` | Raw Text View |
| `⌃⌘4` | HTML View |
| `⌃⌘5` | XML View |
| `⌃⌘6` | JSON View |

</details>

<details open>
<summary><strong>Compare</strong></summary>

| Shortcut | Action |
| --- | --- |
| `⌘⇧C` | Turn Compare Mode on or off |
| `⌘⇧S` | Swap File A and File B |
| `⌘D` | Highlight differences |
| `⌘` click a tab | Compare it with the current one |
| `⌥` drag | Drop a second file onto an open one to compare |

</details>

<details open>
<summary><strong>Display</strong></summary>

| Shortcut | Action |
| --- | --- |
| `⌘+` | Zoom in |
| `⌘−` | Zoom out |
| `⌘0` | Reset zoom to 100% |
| `⌘M` | Cycle appearance — light, dark, system |
| `⌘B` | Cycle the background — off, static, animated |

</details>

<details open>
<summary><strong>Tools</strong></summary>

| Shortcut | Action |
| --- | --- |
| `Space` | Preview the current file |
| `←` / `→` | Skip back or forward 10 seconds in the preview |
| `⌘F` | Search and filter |
| `⌘E` | Export |
| `⇧⌘H` | Check Media Health |
| `⇧⌘I` | Ask Siri AI — Macs that support Apple Intelligence, macOS 27 or later |
| `⌘R` | Ask a stopped Siri AI question again |
| `⌘,` | Settings |
| `⌘K` | Keyboard shortcuts reference |
| `⌘/` | Open the website |
| `⌘I` | About SwiftMediaInfo |

</details>

---

## Export formats

| Format | What it is | Shared as |
| --- | --- | --- |
| **Text** | MediaInfo's standard text output | A link on pb.plz.ac (24 hours) |
| **Raw Text** | The complete, unedited output | A link on pb.plz.ac (24 hours) |
| **HTML** | Looks exactly like the in-app HTML view, in light or dark | A web page on ship.page |
| **PDF** *(new)* | An A4 report — overview, highlights, a table per track, clickable links. Real, searchable text | A web page on ship.page |
| **Markdown** *(new)* | Headings, the Overview, a table per track and chapters — ready for the pastebin of your choice | A rendered page on markdown.page |
| **CSV** | Spreadsheet-friendly | A link on pb.plz.ac (24 hours) |
| **JSON** | Structured, for scripts and tooling | A link on pb.plz.ac (24 hours) |
| **XML** | Machine-readable | A link on pb.plz.ac (24 hours) |
| **ZIP** | All eight bundled together | A link on up.sb |

A SHA-256 checksum you have computed is included only if you choose to — **Settings › Privacy**.

---

## Privacy

SwiftMediaInfo reads files. It does not modify them, and it does not phone home — there is no analytics, no telemetry, and no account.

A few things leave your machine, and only when you ask for them:

- **Sharing a report** uploads it — HTML and PDF to `ship.page`, Markdown to `markdown.page`, text formats to `pb.plz.ac`, ZIP bundles to `up.sb`. Anyone with the link can read it. The report is shown to you in full first; file paths are stripped by default and the checksum is left out unless you say otherwise.
- **Installing MediaInfo or ffmpeg** through the app runs Homebrew, which talks to Homebrew's servers.
- **Opening a link** — the website, this repository, the donate page — hands the URL to your browser.

And a few things that sound like they might, but do not:

- **Siri AI** runs entirely on your Mac, with Apple's on-device model. It reads MediaInfo's text report — never the file — with paths removed.
- **Open in SwiftMediaInfo** on the website hands the app a file's name, size and date, from your browser to the app. The app finds the file on your Mac itself.
- **Previews** are cut on your Mac by ffmpeg, into a temporary folder that is emptied when the preview closes.

The full detail is on the [privacy page](https://undisclosed0369.app/swiftmediainfo/privacy).

---

## How this was built

The code was written by Claude, under my direction and review.

I say so plainly because the source is public — you do not have to take any of it on trust. Read it, build it yourself, or have someone you trust look at it.

What that means in practice: I decide what the app should do and how it should behave, I test every change, and I reject the ones that are wrong. The typing is not the part that makes something good.

---

## FAQ

More questions, answered at greater length, on the [FAQ page](https://undisclosed0369.app/swiftmediainfo/faq).

<details>
<summary><strong>Why won't macOS open the app?</strong></summary>
<br>

The app is unsigned, not damaged. [The fix is above.](#if-macos-wont-open-the-app) Installing with Homebrew avoids the question entirely.

</details>

<details>
<summary><strong>Why do I need MediaInfo installed separately?</strong></summary>
<br>

SwiftMediaInfo is a front-end. MediaInfo does the actual reading, and it is updated often — bundling a copy would mean re-releasing this app every time they release theirs, and your copy would always be slightly behind. Installing it separately means it stays current on its own.

</details>

<details>
<summary><strong>Do I need ffmpeg?</strong></summary>
<br>

Only to preview MKV and other formats macOS cannot play. Everything else works without it, and the app offers to install it the first time you need it.

</details>

<details>
<summary><strong>Does it modify my files?</strong></summary>
<br>

No. It is read-only. It does not edit, re-encode, rename or touch your media in any way — except when you explicitly use the rename or move-to-Trash actions, which are the only two things in the app that write anything, and both ask first. Previews are cut into temporary copies; the original is never touched.

</details>

<details>
<summary><strong>Does Siri AI send my files anywhere?</strong></summary>
<br>

No. It uses Apple's on-device model, so nothing leaves your Mac — and it only ever reads MediaInfo's text report, never the file itself. It appears on Macs that support Apple Intelligence, running macOS 27 or later; everywhere else it stays out of the way.

</details>

<details>
<summary><strong>What file formats are supported?</strong></summary>
<br>

Anything MediaInfo supports, which is most things — MKV, MP4, MOV, AVI, FLAC, MP3, WAV and several hundred others.

For each one it shows what MediaInfo reads: codec and profile, bitrate, resolution, frame rate, HDR format, colour information, audio channels and sample rate, languages, subtitles, chapters, and the encoder settings when the file records them.

</details>

<details>
<summary><strong>Can I try it without installing anything?</strong></summary>
<br>

Yes. [SwiftMediaInfo Online](https://undisclosed0369.app/swiftmediainfo/online) runs MediaInfo in your browser, on any computer, Mac or not. The file is read on your own machine and never uploaded. It has the Text, HTML, XML and JSON views — and on a Mac with the app, **Open in SwiftMediaInfo** takes you from there to the full picture.

</details>

<details>
<summary><strong>Is this an official MediaInfo application?</strong></summary>
<br>

No. It is an independent front-end, built for macOS, using MediaInfo's own binary underneath. MediaArea made the hard part; this is the window onto it.

</details>

<details>
<summary><strong>Why are there six view modes?</strong></summary>
<br>

Because people work differently. Some want to just glance it easily, some want the raw output, and some want JSON to feed into something else. It costs little to offer all of them.

</details>

<details>
<summary><strong>Is it open source?</strong></summary>
<br>

Yes, MIT licensed. All of it, including the website.

</details>

<details>
<summary><strong>Why is there an easter egg?</strong></summary>
<br>

Because software should be fun occasionally.

</details>

<details>
<summary><strong>I found a bug, or I have a suggestion</strong></summary>
<br>

Either [open an issue](https://github.com/Undisclosed0369/SwiftMediaInfo/issues) or find me on Discord at `flabbergastedindividual`. The [feedback form](https://forms.gle/ZoDwomdm5asgfj386) is above and works too.

</details>

<details>
<summary><strong>Why did you make this?</strong></summary>
<br>

I made it for myself first. When something turns out useful and I have the time, I put it up publicly — there is a reasonable chance somebody else has the same problem.

</details>

<details>
<summary><strong>Do you take donations?</strong></summary>
<br>

Not money, no. Traditional payment methods reveal banking details, which defeats the point of being pseudonymous.

There is a [donate page](https://undisclosed0369.app/swiftmediainfo/donate) with a wishlist on it, if you would like to. Nothing in the app changes either way, nothing is locked, and there is no nagging. Everything is free and stays free.

</details>

<details>
<summary><strong>Did you pay for the AI used to build this?</strong></summary>
<br>

Yes — $20 a month for Claude.

In version 1.6 this answer said I used only free accounts, and that was true at the time. It is also why version 1.6 took as long as it did.

</details>

---

## Easter egg

Click the app icon in the About window a few times.

---

## Licence

This project is licensed under the MIT License.

See the [LICENSE](https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/LICENSE) file for details.

> **Built on MediaInfo.**
> Every number this app shows you was read by [MediaInfo](https://mediaarea.net/en/MediaInfo), a separate project by [MediaArea](https://mediaarea.net), maintained for two decades and licensed under its own BSD-style terms. They wrote the hard part. This is the window onto it, and it would not exist without them.
>
> **Previews by FFmpeg.** The clips in the preview window are cut and converted by [FFmpeg](https://ffmpeg.org), installed separately and used under its own licence.

---

## Author

**Undisclosed / Data Lass**

- Website — [undisclosed0369.app](https://undisclosed0369.app)
- GitHub — [@Undisclosed0369](https://github.com/Undisclosed0369)
- Discord — `flabbergastedindividual`

---

## Project status

**Version 2.1** — tabs, Media Health, previews, Siri AI and new reports, in an app made faster and lighter without changing its look.

Read the [release notes](https://github.com/Undisclosed0369/SwiftMediaInfo/releases/latest) or the [full changelog](https://undisclosed0369.app/swiftmediainfo/changelog).
