# NotchShelf

A panel that lives in the MacBook notch: screenshots, clipboard, downloads,
plans, a calculator, converters, a translator, music, weather and what the
machine is doing.

Point at the notch and a slab slides out of the top edge of the screen. Point at
it again and the slab rolls back up. Nothing is on screen while it is shut.

![status](https://img.shields.io/badge/platform-macOS%2014%2B-black)

## Why

Every screenshot tool either buries shots in a folder you have to go dig
through, or leaves a floating thumbnail sitting in the corner of your screen.
NotchShelf puts them in the one piece of screen real estate that is already dead
space, and shows nothing at all until you ask for it.

Then it kept going, because the same dead space answers most of the small
questions that otherwise cost a window: what did I copy, what did I download,
what is 12 km in centimetres, how do I say this in English, why is the internet
slow.

## Tabs

Ten of them, and each one is a *subject*. The two or three tools that belong to
a subject live inside it, as a row of small discs hanging under the panel — a
row of twenty icons across the top would be a menu bar, which is the thing this
replaces.

- **Shelf** — new screenshots arrive as cards by themselves. Drag any file onto
  the notch to park it there; drag a card out into Slack, Figma, a mail draft.
  Delete the file in Finder and its card goes with it. Eight cards, and the
  ninth pushes the oldest into the Trash — but only if it came from the
  screenshots folder in the first place. The area is divided by how many there
  are: one card fills it, two split it, four make a grid.
  Its tools: **Record** the screen or a part of it, convert an image's
  **Format**, **Cut out** the subject from its background, and an eyedropper
  that puts the hex straight on the clipboard.
- **Clipboard** — everything copied, newest first, nothing written to disk.
  Its tool: a **password** generator. Generated passwords go to the login
  keychain and there is no button anywhere that deletes one — the keychain entry
  is the only copy.
- **Downloads** — the last things that landed in `~/Downloads`, draggable out
  the same way shelf cards are.
- **Plans** — the day: calendar events if macOS will give them, otherwise the
  bullets out of `today.md` in a folder you point at, with `goals.md` behind it.
  Ticking a line writes `- [x]` back into the file, which is what Obsidian would
  have written. The month unfolds from the top left corner. On the right, a
  timer that keeps counting with the panel shut, and a switch that keeps the Mac
  awake.
- **Calc** — the field takes the keyboard the moment the tab opens. **The model
  never does arithmetic.** Sums, LaTeX and words all end up as an expression,
  and a parser in `MathStore.swift` works out the number: integrals by Simpson,
  determinants by Gauss, derivatives by central difference, factorials by gamma.
  That split is not fussiness. Asked outright, qwen2.5 says twelve apples less a
  third plus five is 10; asked for the expression it returns `12 - 12/3 + 5`
  every time.
  Its tools: **Graph** — drag to pan, scroll to zoom, crossings ringed in each
  curve's own colour and named when pressed — and **Theorem**, one statement a
  day out of the newest book in a folder you point at (PDF, txt or markdown).
- **Convert** — money, temperature, mass, volume, length. Rates come from
  `open.er-api.com`, which needs no key and republishes once a day. Press Return
  and the sum stays in the list underneath.
- **Translate** — Google's unofficial endpoint while there is a line, and a
  local Ollama model when there is not.
- **Music** — Spotify: artwork, track, and a bar that runs in real time and can
  be dragged to scrub.
- **Weather** — Moscow, Astana and Almaty, at 08:00, 12:00, 16:00 and 22:00,
  with wind and humidity beside each reading.
- **System** — four readings about one computer, one at a time so that only the
  one on screen costs anything: **Machine** (battery here and on whatever is
  paired, memory and the three apps holding most of it), **Line** (router, the
  hop past it and name lookup, each timed separately, plus an hour of history
  drawn as a curve), **VPN**, and **Watching** — whether the microphone and
  camera are in use, and by what.

## Settings

Behind the gear hanging outside the top right corner, not in the row: the row is
what the panel is *for*.

- **Tabs** — which of the ten are in the strip. The last one cannot be switched
  off.
- **Colour** — the one accent the panel spends on live readings, and a quieter
  second for the rare pair of equals. Nine of each, every one of them checked
  for contrast; red is refused because red already means something.
- **Background** — Solid, Veil, Glass, Clear, White. Each row says what it
  costs: the more of the desktop that comes through, the less of the type scale
  survives over a light wallpaper.
- **Folders** — where Plans and Theorem read from. Nothing is set by default and
  nothing is guessed at; until you pick, those two tabs say so and offer the
  button. Nothing outside the two folders is ever read.

## Design

- **Out of the bezel** — the slab is full width from the top pixel of the
  screen, so it covers the menu bar across its own width and the notch is simply
  inside it. Fillets scoop into the top corners so the black looks poured rather
  than pasted.
- **One size** — every tab is the same height. Floating heights were tried for
  half a day: the panel jumped a different distance down the screen on every
  switch and nothing ever stayed where the hand left it.
- **Invisible when idle** — no floating widgets, no badges, nothing in the menu
  bar beyond one tray icon. Shut, the window is exactly the size of the notch,
  so there is no transparent rectangle over the desktop quietly eating clicks.
- **Nothing wakes up early** — the calendar prompt only appears when Plans is
  opened, Spotify is only polled while Music is on screen, and each System
  reading sleeps until it is the one being looked at. The exception is the
  network history, which is only worth anything if it was recorded while nobody
  was watching.
- **Reduce motion and reduce transparency** are both honoured.

## Install

A built copy is attached to every [release][releases]. One line puts it in
`/Applications`, clears the download flag and opens it:

```bash
curl -fsSL https://raw.githubusercontent.com/karazhaniman72-eng/notchshelf/main/scripts/install.sh | bash
```

By hand: download the zip, drag the app into `/Applications`, then
`xattr -dr com.apple.quarantine /Applications/NotchShelf.app`. The app is signed,
but not by Apple — a developer certificate is $99 a year — so macOS would refuse
it until that flag is off. The whole of what it does is in this repository.

Russian walk-through for someone who has not used a terminal before:
[УСТАНОВКА.md](УСТАНОВКА.md).

[releases]: https://github.com/karazhaniman72-eng/notchshelf/releases

## Requirements

- macOS 14 or later, MacBook with a notch (it falls back to a centred strip
  without one)
- Swift 6 toolchain — the Xcode **Command Line Tools** are enough, full Xcode is
  not required
- Optional: [Ollama](https://ollama.com) for worded maths and offline
  translation; Spotify for the Music tab

## Build

```bash
./build.sh release
open NotchShelf.app
```

`build.sh` compiles with SwiftPM, assembles the `.app` bundle and signs it.
`scripts/release.sh` does that and then packs a copy signed ad-hoc into
`dist/NotchShelf-<version>.zip`, which is the file that goes on a release: the
certificate below is trusted on one machine only, so the copy that leaves it
carries no identity at all rather than an unknown one.

> Launch the built `.app`, not the raw binary in `.build/`. macOS grants folder
> access to app bundles; a bare executable started from a terminal inherits the
> terminal's permissions and cannot read the screenshots folder.

**Make yourself a signing certificate.** `codesign --sign -` gives the app no
identity, so macOS keys every privacy grant to the hash of the binary and every
rebuild is a brand new app to it — Calendar, Downloads and the screenshots
folder all have to be granted again. Create a self-signed code-signing
certificate named `NotchShelf` in Keychain Access and `build.sh` will find it
and use it; without one it says so and carries on ad-hoc.

## Usage

| Action | Result |
|---|---|
| Point at the notch | Panel opens after a moment |
| Click the notch | Panel opens at once |
| Point at the notch again | Panel closes — the same movement both ways |
| Point at a tab | Switches to it, no click needed |
| Drag a file onto the notch | Panel opens at once, drop to keep the file |
| Click a card | Opens the file |
| Drag a card | Drags the file out |
| Right-click a card | Open / Reveal in Finder / Pin / Remove |
| Tray icon → Keep Panel Open | Panel stays open until switched off |

Walking the cursor away does **not** close the panel: the notch is the switch,
and nothing else is, so the panel can be left open while you work in the window
underneath it.

The panel follows whatever folder macOS saves screenshots to. To keep it away
from your Desktop, point screenshots at a folder of their own:

```bash
mkdir -p ~/Pictures/Screenshots
defaults write com.apple.screencapture location ~/Pictures/Screenshots
killall SystemUIServer
```

If Shift-Cmd-5 is set to **Save to → Clipboard**, no file is written at all and
the shelf stays empty. `defaults read com.apple.screencapture target` should say
`file`.

## How it works

A borderless, non-activating `NSPanel` pinned to the top edge at window level
`statusBar + 2` = 27: above the menu bar at 24 and the status items at 25, below
the system menus at 101 so their drop-downs still land on top. The notch
rectangle comes from `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`.

While the panel is shut the window is the size of the notch and nothing else.
While it is open it is 688 points wide — a 600-point slab with a transparent
lane down each side for the gear — and `hitTest` cuts three holes in it: the
slab, the row of discs under it, and the gear. Everything else passes clicks
through to whatever is underneath.

The keyboard is borrowed rather than taken. The panel may only become key while
something on it is being typed into, and when it gives the keyboard back it
activates the application it interrupted by name — `NSApp.deactivate()` alone
names no successor, and an agent app with one floating panel has nothing behind
it, so the keystrokes go nowhere.

Screenshots are picked up with a `DispatchSource` watcher on the folder, and
thumbnails come from ImageIO at 400 px rather than full-size images. Any read
outside the sandbox happens on a background queue: when a TCC grant has gone
stale the call does not fail, it *waits* for a dialog that a background app is
never shown, and on the main thread that is a dead panel.

Diagnostics are written to `~/Library/Logs/NotchShelf.log`.

### Checking the layout

The app will draw its own window into a PNG on request — its own view, not the
screen:

```bash
echo "calc/plot?sin(x)*x" > "$TMPDIR/notchshelf-request.txt"
# → $TMPDIR/notchshelf-calc-plot.png
```

`<tab>[/<tool>][?<text to type>]`. There is a **Save Panel Snapshot** item in the
tray menu for the plain version.

## Permissions

Asked for only when the matching tab is opened, never at launch:

- **Calendar** — for Plans.
- **Automation → Spotify** — for Music. NotchShelf drives the Spotify desktop
  app over AppleScript, so there is no developer app to register, no OAuth flow
  and no API keys anywhere.
- **Screen Recording** — only when Record is used.
- **An administrator password** — only if Clear on the System tab is pressed.
  `purge` is root-only; macOS shows its own prompt and the app never sees what
  is typed.

Weather asks for nothing: the three cities are fixed, so there is no location to
request. The Wi-Fi name is not shown because macOS only gives the SSID to an app
with location access, and this one would rather not ask.

## Roadmap

- Apple Music alongside Spotify — blocked: Apple locked the private MediaRemote
  framework behind an entitlement in macOS 15.4, so third-party apps can no
  longer read system now-playing information without a workaround.
- The three weather cities are still fixed in `WeatherStore.swift` — Moscow,
  Astana and Almaty. Changing them is a one-line edit; a proper picker needs a
  place to search for one, which is not written yet.

## License

MIT
