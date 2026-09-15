# Contributing

Thank you for wanting to. Genuinely — most people who find a small app and spot a problem just close the tab.

This page explains what helps, what does not, and why the answer to pull requests is no.

---

## What helps

**Bug reports.** The most useful thing you can send. A file that produces the wrong result, a window that draws badly, a shortcut that does the wrong thing — all of it. [Open an issue.](https://github.com/Undisclosed0369/SwiftMediaInfo/issues/new/choose)

**Feature ideas.** If something about your workflow is awkward, say so. The best features in this app came from noticing an annoyance and refusing to live with it.

**Suggested fixes in words.** If you know *what* is wrong and *how* it should be fixed, describe it. "The timeout should apply per format rather than to the whole run" is enormously useful. Just send the reasoning, not a patch.

**Corrections.** Wrong explanation in the field glossary, mistake on the website, typo in the README. Small, and always worth sending.

**Telling me what works.** Harder to act on, but it does tell me what not to break. The [feedback form](https://forms.gle/ZoDwomdm5asgfj386) takes about ninety seconds.

---

## What I cannot accept

**Pull requests containing code.**

Not because of you, and not because of the code. It is how this project is built.

Every line in this repository was written by Claude, under my direction and review, against a set of decisions I hold in my head and in the comments. Those comments are not decoration — they record *why* something is the way it is, which alternative was tried, and what broke last time. When a change arrives that was not made under that process, I cannot review it to the standard I hold the rest to. I would either merge something I do not fully understand, or spend longer reconstructing the reasoning than the change saved.

So: **describe the fix and I will implement it.** You will be credited in the release notes for the idea. That is not a consolation prize — deciding what should change is the part that requires judgement.

If you would rather take the code and go your own way, please do. It is MIT licensed precisely so you can. Fork it, rename it, ship it.

---

## Before opening an issue

**Check it is not already known.** A quick search of [open issues](https://github.com/Undisclosed0369/SwiftMediaInfo/issues) saves us both time.

**Check the [FAQ](https://undisclosed0369.app/swiftmediainfo/faq.html).** The common ones — why macOS says the app is damaged, why MediaInfo has to be installed separately — are answered there.

**Grab your environment details.** Settings → Advanced → **Copy environment summary** puts everything I will ask for on your clipboard: app version, macOS version, architecture, MediaInfo path and version, and your current settings. Paste it into the issue.

---

## What makes a good bug report

Three things, in this order:

1. **What you expected to happen**
2. **What actually happened**
3. **How to make it happen again**

The third is the one that matters most. A bug I can reproduce is usually fixed the same day; a bug I cannot reproduce can sit for months while I guess.

If it involves a specific file, the format and rough size help — `a 4 GB MKV with three audio tracks and PGS subtitles` is plenty. Do not send me the file unless I ask, and never send anything you would not want on the internet.

Screenshots are welcome. **Check them for anything private first** — file paths usually contain your username, and sometimes a good deal more.

---

## Security problems

Do not open a public issue. [SECURITY.md](SECURITY.md) explains where those go.

---

## Translations

The app is English only, and honestly that is unlikely to change soon — every string would need a translator I trust and a way to keep translations current across releases. If you want to discuss it anyway, open an issue and say so.

---

## Behaviour

Short version: be civil, criticise the work as much as you like, leave people alone. The longer version is in [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

---

## One more thing

If you use this app and it saved you some time, that is enough. There is nothing to buy, nothing to sign up for, and no obligation whatsoever. Reporting a bug is a favour to me, not a debt you owe.
