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
  <img src="https://img.shields.io/badge/version-2.0-8d42f5" alt="Version 2.0">
</p>

<p align="center">
  <a href="https://undisclosed0369.app/swiftmediainfo/"><strong>Website</strong></a> ·
  <a href="https://undisclosed0369.app/swiftmediainfo/download.html"><strong>Download</strong></a> ·
  <a href="https://undisclosed0369.app/swiftmediainfo/features.html"><strong>Features</strong></a> ·
  <a href="https://undisclosed0369.app/swiftmediainfo/faq.html"><strong>FAQ</strong></a> ·
  <a href="https://undisclosed0369.app/swiftmediainfo/changelog.html"><strong>Changelog</strong></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/S1-EasyView.png" width="820" alt="SwiftMediaInfo">
</p>

<p align="center">
  <strong>A native macOS front-end for <a href="https://mediaarea.net/en/MediaInfo">MediaInfo</a>.</strong><br>
  Read what is actually inside a media file — and never write a byte back.
</p>

<table>
<tr>
<td width="33%" valign="top">

**Six views**

Structured tree, plain text, raw output, HTML, XML and JSON.

</td>
<td width="33%" valign="top">

**Compare two files**

Side by side, differences marked at field and line level.

</td>
<td width="33%" valign="top">

**~70 fields explained**

Plain language, inline, for the ones nobody remembers.

</td>
</tr>
<tr>
<td valign="top">

**SHA-256 checksums**

On request, cached, included in exports.

</td>
<td valign="top">

**Six export formats**

Individually, all at once, or bundled as a ZIP.

</td>
<td valign="top">

**Yours to look at**

Liquid Glass, three background modes, colours you pick.

</td>
</tr>
</table>

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
- [If macOS says the app is damaged](#if-macos-says-the-app-is-damaged)
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

### Reading a file

<table>
<tr>
<td width="50%" valign="top">

**Six views of the same report**

Structured tree, plain text, raw output, HTML, XML and JSON. Switch between them with `⌘1` – `⌘6`.

</td>
<td width="50%" valign="top">

**Around 70 fields explained**

Hover a field name for plain language — for anyone who has wondered what chroma subsampling actually is.

</td>
</tr>
<tr>
<td valign="top">

**Global fuzzy search**

`⌘F` searches every field at once. Space-insensitive, so `bitrate` finds `Bit Rate`.

</td>
<td valign="top">

**Copy anything**

A single value, or a field and its value together, from a hover control or the context menu.

</td>
</tr>
</table>

### Comparing two files

<table>
<tr>
<td width="50%" valign="top">

**Side by side**

`⌘⇧C` opens Compare Mode — or hold `⌥` while dragging a second file onto one already open.

</td>
<td width="50%" valign="top">

**Differences marked**

`⌘D` highlights what changed at field *and* line level, with per-track counts.

</td>
</tr>
<tr>
<td valign="top">

**A summary of what changed**

Every difference listed in one panel. Click one to jump straight to that field.

</td>
<td valign="top">

**Swap the sides**

`⌘⇧S`, or the control on the divider. Computed once and symmetrically, so the two sides can never disagree.

</td>
</tr>
</table>

### Verifying a file

<table>
<tr>
<td width="50%" valign="top">

**SHA-256 checksums**

Computed when you ask rather than automatically, because hashing means reading every byte of the file.

</td>
<td width="50%" valign="top">

**Cached, and included in exports**

Hashed once per file. Carried into reports, so an archive copy can be checked against the original years later.

</td>
</tr>
</table>

### Sharing and exporting

<table>
<tr>
<td width="50%" valign="top">

**Six export formats**

TXT, Raw TXT, CSV, HTML, JSON and XML — one at a time, all six separately, or bundled as a ZIP.

</td>
<td width="50%" valign="top">

**Share online**

Upload a report and get a link back, without leaving the window.

</td>
</tr>
<tr>
<td valign="top">

**Review before upload**

The report is shown in full first, with the option to strip file paths — a path usually carries a username.

</td>
<td valign="top">

**Real progress, real cancellation**

Cancelling a long operation stops the work rather than hiding it.

</td>
</tr>
</table>

### The interface

<table>
<tr>
<td width="50%" valign="top">

**Liquid Glass**

Built on macOS 26 and written entirely in SwiftUI. Not a web view in a window.

</td>
<td width="50%" valign="top">

**Six panes of settings**

General, Appearance, Analysis, MediaInfo, Privacy and Advanced — with scaling that zooms the whole layout, not just the text.

</td>
</tr>
<tr>
<td valign="top">

**A background you own**

Off, static or animated. Three custom colours, four palettes, quarter-resolution rendering, and it pauses in Low Power Mode.

</td>
<td valign="top">

**Finder integration**

Right-click any file to open it here — or select two and compare them straight from the Finder menu.

</td>
</tr>
<tr>
<td valign="top">

**Accessibility throughout**

VoiceOver on every control, built into the shared components. Reduce Motion and Reduce Transparency honoured at token level.

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
  <img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/S2-CompareDifference.png" width="700" alt="Compare View">
  <br><em>Compare Mode, with differences highlighted and a summary of what changed</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/S3-FieldExplanations.png" width="700" alt="Field explanations">
  <br><em>Around seventy fields explained in plain language</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/S4-Settings.png" width="700" alt="Settings">
  <br><em>Six panes of settings, and an interface that scales as a whole</em>
</p>

<p align="center">
  <img src="https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/assets/S5-ShareOnline.png" width="700" alt="Share online">
  <br><em>Share a report online — reviewed in full, with paths strippable, before anything is uploaded</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/S6-HTMLView.png" width="700" alt="HTML View">
  <br><em>HTML View, rendered with WebKit</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/S7-Search.png" width="700" alt="Search">
  <br><em>Fuzzy search across every field</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Undisclosed0369/SwiftMediaInfo/main/assets/S8-LightCustomBG.png" width="700" alt="Light appearance">
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
| **Search** | Global fuzzy search across every field | — |
| **Share online** | Upload a report and get a link | — |
| **Interface zoom** | Scales the whole interface | — |
| **Keyboard shortcuts** | Full, with a reference window | — |
| **Finder integration** | Context menu, drag-and-drop, and ⌥-drag to compare directly | Context menu and drag-and-drop |
| **Export formats** | TXT, Raw TXT, CSV, HTML, JSON and XML | Text, XML, JSON, EBUCore and more |
| **Appearance** | Light, dark or system, with an off, static or animated background in colours you choose | Follows the system |
| **Platforms** | macOS 26 and later | macOS, Windows, Linux, Android, iOS |
| **Languages** | English | 37 languages |
| **Signed and notarised** | No | Yes, via the App Store |

If you need Windows, Linux, a language other than English, or a signed application, theirs is the better choice and you should use it.

---

## Requirements

- **macOS 26** or later
- **Apple silicon**
- **MediaInfo CLI** — the app checks for it on launch and offers to install it for you

MediaInfo is not bundled with the app, so that your copy of it can be updated independently. If you would rather install it yourself:

```bash
brew install mediainfo
```

And if you do not have Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

## Installing

### Homebrew

```bash
brew tap undisclosed0369/swiftmediainfo
brew trust undisclosed0369/swiftmediainfo/swiftmediainfo
brew install --cask --no-quarantine swiftmediainfo
```

Three commands rather than two, because Homebrew will not install from a third-party tap it has not been told to trust. The second command is you telling it. The third skips the quarantine flag, which is what would otherwise produce the warning described below.

### Disk image

Download `SwiftMediaInfo-2.0.dmg` from [Releases](https://github.com/Undisclosed0369/SwiftMediaInfo/releases/latest) and drag the app into Applications.

macOS will refuse to open it the first time. That is expected — see the next section.

### Building from source

```bash
git clone https://github.com/Undisclosed0369/SwiftMediaInfo.git
cd SwiftMediaInfo
open SwiftMediaInfo.xcodeproj
```

Then build and run with `⌘R`. You will need Xcode 26 or later.

Two notes. The project has two targets — the app and the Finder extension — and both need a signing team set; "Sign to Run Locally" is enough for your own machine. And a locally built copy is unsigned, so the security notice below applies to it too.

---

## If macOS says the app is damaged

It is not damaged. SwiftMediaInfo is not signed with an Apple Developer certificate, which costs $99 a year, and macOS words that situation badly — it shows the same message whether an app is genuinely corrupted or simply has no certificate.

Clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/SwiftMediaInfo.app
```

Then open it normally.

Installing with `--no-quarantine` through Homebrew avoids this entirely, because the flag is never set in the first place.

**Worth saying plainly:** that command tells macOS to stop checking a file, and you should not run it on anything you do not have a reason to trust. The reason to trust this one is that the source is public — read it, or build it yourself and skip the question. The [download page](https://undisclosed0369.app/swiftmediainfo/download.html) explains what the warning actually means in more detail.

---

## Updating

```bash
brew update
brew upgrade --cask swiftmediainfo
```

If you installed the disk image by hand, download the new one and replace the app in Applications.

---

## Uninstalling

```bash
brew uninstall --cask swiftmediainfo
```

To remove the settings and cached data as well:

```bash
brew uninstall --cask --zap swiftmediainfo
```

Installed by hand? Drag the app to the Trash. To remove its preferences too:

```bash
defaults delete app.undisclosed0369.SwiftMediaInfo
```

---

## Keyboard shortcuts

Press `⌘K` in the app for this list at any time.

### File

| Shortcut | Action |
| --- | --- |
| `⌘O` | Open a file or folder |
| `⌘W` | Close the open file — closes the window when nothing is open |
| `⌥⌘W` | Close the window |
| `⌘⏎` | Open the file in its default app |

### File actions

| Shortcut | Action |
| --- | --- |
| `⌘⇧R` | Reveal in Finder |
| `⌥⌘C` | Copy the full file path |
| `⌘⌫` | Move the file to the Trash |

### View modes

| Shortcut | Action |
| --- | --- |
| `⌘1` | Easy View — adds File A in Compare Mode |
| `⌘2` | Text View — adds File B in Compare Mode |
| `⌘3` | Raw Text View |
| `⌘4` | HTML View |
| `⌘5` | XML View |
| `⌘6` | JSON View |

### Compare

| Shortcut | Action |
| --- | --- |
| `⌘⇧C` | Turn Compare Mode on or off |
| `⌘⇧S` | Swap File A and File B |
| `⌘D` | Highlight differences |
| `⌥ drag` | Drop a second file onto an open one to compare |

### Display

| Shortcut | Action |
| --- | --- |
| `⌘+` | Zoom in |
| `⌘−` | Zoom out |
| `⌘0` | Reset zoom to 100% |
| `⌘M` | Cycle appearance |
| `⌘B` | Cycle the background — off, static, animated |

### Tools

| Shortcut | Action |
| --- | --- |
| `⌘F` | Search and filter |
| `⌘E` | Export |
| `⌘,` | Settings |
| `⌘K` | Keyboard shortcuts reference |
| `⌘/` | Open the website |
| `⌘I` | About SwiftMediaInfo |

---

## Export formats

| Format | What it is |
| --- | --- |
| **TXT** | MediaInfo's standard text output |
| **Raw TXT** | The complete, unedited output |
| **CSV** | Spreadsheet-friendly |
| **HTML** | Styled and readable in a browser |
| **JSON** | Structured, for scripts and tooling |
| **XML** | Machine-readable |
| **ZIP** | All six bundled together |

Checksums, when you have computed them, are included in the export.

---

## Privacy

SwiftMediaInfo reads files. It does not modify them, and it does not phone home — there is no analytics, no telemetry, and no account.

Three things leave your machine, and only when you ask for them:

- **Sharing a report online** uploads it to `pb.plz.ac` (text) or `up.sb` (ZIP bundles). Both are public pastes — anyone with the link can read them. The report is shown to you in full first, with the option to strip file paths.
- **Installing MediaInfo** through the app runs Homebrew, which talks to Homebrew's servers.
- **Opening a link** — the website, this repository, the donate page — hands the URL to your browser.

Nothing else. The full detail is on the [privacy page](https://undisclosed0369.app/swiftmediainfo/privacy.html).

---

## How this was built

The code was written by Claude, under my direction and review.

I say so plainly because the source is public — you do not have to take any of it on trust. Read it, build it yourself, or have someone you trust look at it.

What that means in practice: I decide what the app should do and how it should behave, I test every change, and I reject the ones that are wrong. The typing is not the part that makes something good.

---

## FAQ

More questions, answered at greater length, on the [FAQ page](https://undisclosed0369.app/swiftmediainfo/faq.html).

### Why does macOS say the app is damaged?

It is not. The app is unsigned. [The fix is above.](#if-macos-says-the-app-is-damaged)

### Why do I need MediaInfo installed separately?

SwiftMediaInfo is a front-end. MediaInfo does the actual reading, and it is updated often — bundling a copy would mean re-releasing this app every time they release theirs, and your copy would always be slightly behind. Installing it separately means it stays current on its own.

### Does it modify my files?

No. It is read-only. It does not edit, re-encode, rename or touch your media in any way — except when you explicitly use the rename or move-to-Trash actions, which are the only two things in the app that write anything, and both ask first.

### What file formats are supported?

Anything MediaInfo supports, which is most things — MKV, MP4, MOV, AVI, FLAC, MP3, WAV and several hundred others.

### Is this an official MediaInfo application?

No. It is an independent front-end, built for macOS, using MediaInfo's own binary underneath. MediaArea made the hard part; this is the window onto it.

### Why are there six view modes?

Because people work differently. Some want a structured tree, some want the raw output, and some want JSON to feed into something else. It costs little to offer all three.

### Is it open source?

Yes, MIT licensed. All of it, including the website.

### Why is there an easter egg?

Because software should be fun occasionally. It is under two kilobytes.

### I found a bug, or I have a suggestion

Either [open an issue](https://github.com/Undisclosed0369/SwiftMediaInfo/issues) or find me on Discord at `flabbergastedindividual`. The [feedback form](https://forms.gle/ZoDwomdm5asgfj386) is above and works too.

### Why did you make this?

I made it for myself first. When something turns out useful and I have the time, I put it up publicly — there is a reasonable chance somebody else has the same problem.

### Do you take donations?

Not money, no. Traditional payment methods reveal banking details, which defeats the point of being pseudonymous.

There is a [donate page](https://undisclosed0369.app/swiftmediainfo/donate.html) with a wishlist on it, if you would like to. Nothing in the app changes either way, nothing is locked, and there is no nagging. Everything is free and stays free.

### Did you pay for the AI used to build this?

Yes — $20 a month for Claude.

In version 1.6 this answer said I used only free accounts, and that was true at the time. It is also why version 1.6 took as long as it did.

---

## Easter egg

Click the app icon in the About window a few times.

---

## Licence

This project is licensed under the MIT License.

See the [LICENSE](https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/LICENSE) file for details.

> **Built on MediaInfo.**
> Every number this app shows you was read by [MediaInfo](https://mediaarea.net/en/MediaInfo), a separate project by [MediaArea](https://mediaarea.net), maintained for two decades and licensed under its own BSD-style terms. They wrote the hard part. This is the window onto it, and it would not exist without them.

---

## Author

**Undisclosed / Data Lass**

- Website — [undisclosed0369.app](https://undisclosed0369.app)
- GitHub — [@Undisclosed0369](https://github.com/Undisclosed0369)
- Discord — `flabbergastedindividual`

---

## Project status

**Version 2.0** — the largest release since the app began. Rebuilt from the engine up.

Read the [full changelog](https://undisclosed0369.app/swiftmediainfo/changelog.html).
