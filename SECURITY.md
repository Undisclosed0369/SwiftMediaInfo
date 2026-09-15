# Security

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Two private routes, either is fine:

**GitHub private reporting** — go to the [Security tab](https://github.com/Undisclosed0369/SwiftMediaInfo/security) and choose *Report a vulnerability*. This opens a thread only you and I can see. Preferred, because it keeps everything in one place and nothing is exposed until it is fixed.

**Discord** — `flabbergastedindividual`. Say it is a security report and I will move it somewhere private.

I am one person, not a company with an on-call rotation. Expect an acknowledgement within a few days. If a week passes with no reply, nudge me through the other channel — it means I missed it, not that I am ignoring you.

---

## Supported versions

| Version | Supported |
| --- | --- |
| 2.0 and above | Yes |
| 1.6 and earlier | No |

Fixes go into the next release. There are no backports — this is a small app maintained in spare time, and asking people to update to the current version is the honest policy rather than pretending otherwise.

---

## What is worth reporting

The app reads files and runs one external binary, so the interesting surface is small but real:

- Anything that makes SwiftMediaInfo **write to, modify or delete** a file it was only supposed to read — apart from the rename and move-to-Trash actions, which are deliberate and ask first
- **Command injection** through a filename, path or MediaInfo output
- Anything that causes data to **leave the machine** without the user asking — the share feature is the only thing that should ever upload, and only after the user has seen the report
- A way to make the **privacy sanitiser** miss a file path in a report that is about to be uploaded
- Anything in the **Finder extension** that escalates what it can reach
- **Dependency installation** being redirected somewhere other than Homebrew

---

## What is already known, and not a vulnerability

Reporting these is welcome as a discussion, but they are deliberate and documented:

**The app is unsigned.** No Apple Developer certificate, so macOS warns on first launch and the quarantine flag has to be cleared manually or skipped at install. This is a cost decision, stated openly in the [README](README.md) and on the [download page](https://undisclosed0369.app/swiftmediainfo/download.html).

**Shared reports are public.** The share feature uploads to public paste services. Anyone with the link can read the report. This is stated in the app before anything is uploaded, and on the [privacy page](https://undisclosed0369.app/swiftmediainfo/privacy.html).

**MediaInfo is a separate project.** Vulnerabilities in MediaInfo itself belong with [MediaArea](https://mediaarea.net). If one affects how this app uses it, that part is mine — tell me.

**The app runs unsandboxed.** It has to read files anywhere you point it, including ones handed over by the Finder extension.

---

## Disclosure

Report privately, give me a reasonable chance to fix it, and I will credit you in the release notes unless you would rather I did not.

If I have gone quiet for a month and the problem is real, publish. A maintainer who disappears should not be able to keep a vulnerability secret by doing nothing.
