# Brief: Timer, Weather, System

> **Shipped on 8 August 2026.** All three tabs run on real stores now:
> `TimerStore`, `WeatherStore`, `SystemStore`, plus `ClaudeLimitStore` behind
> the timer. Three parts of the brief below were overruled by the owner after
> seeing the mocks on screen, and the code follows the newer decision:
>
> - **Weather** has no CoreLocation and no typed-in city. It carries three fixed
>   cities — Moscow, Astana, Almaty — switched by hovering their names, and
>   shows the whole week at 08:00, 12:00, 16:00 and 22:00 with temperature and
>   chance of precipitation. No location permission is asked for at all.
> - **System** leads with batteries rather than three equal rings: the Mac and
>   whatever is paired with it over Bluetooth, read out of `system_profiler`
>   because IORegistry only carries a charge while a device is connected.
>   Memory moved below them with the three heaviest apps named under it, and a
>   Clear button that runs `purge` — which needs root, so macOS puts up its own
>   password prompt. Disk shrank to the footnote next to uptime.
> - **Timer** presets are 30 minutes, 1 hour and 3 hours, and the tab also shows
>   when the current Claude Code five-hour window resets.
>
> A phone's battery was asked for and is not here: nothing outside Apple's own
> apps can read it. Bluetooth does not carry it and there is no public API.
> Spotify's next track is missing for the same kind of reason — AppleScript
> exposes the current track and nothing of the queue.

The original brief follows.

## Ground rules for all three

- **The layout is settled.** Replace the frozen sample struct with an
  `@ObservedObject` store and bind the same fields. Do not reshape the view. If
  a real value genuinely cannot fit the space the mock gives it, say so and
  change the layout deliberately, rather than letting it drift.
- **Every colour, corner and font comes from `Theme`.** No new literals. A new
  semantic token in `Theme.swift` is fine; a raw `Color(red:…)` in a view is not.
- **Nothing runs while its tab is closed.** The Spotify tab already sets the
  precedent: polling starts when the tab appears and stops when it goes away.
  A timer that is counting down is the one exception — see below.
- **No permission prompt at launch.** Calendar asks when Today is first opened;
  location and notifications must behave the same way.
- **Stores live in `AppModel`, views stay dumb.** A view reads published values
  and calls methods. It does not own a URLSession, an IOKit handle or a `Timer`.

---

## Timer

**Goal.** Start a focus block without leaving what you are doing: hover the
notch, click a preset, get back to work. The point is that it costs one gesture,
not that it has features.

**Data.** None external. All state is the app's own.

**Tasks.**

1. `TimerStore: ObservableObject` — published `phase` (`.idle`, `.focus`,
   `.rest`), `remaining` seconds, `isRunning`, `preset`. One repeating 1-second
   tick for the whole app, created when a run starts and torn down when it ends.
   Not one per view appearance.
2. Presets 25 / 50 / 15 minutes. Remember the last one chosen in `UserDefaults`.
3. Controls: play-pause, reset to the top of the current phase, skip to the next
   phase.
4. When a focus block ends, post a `UNUserNotification` and play a sound. Ask
   for notification permission the first time a timer is started, not at launch.
5. Count blocks finished today and the total time; roll the counter over at
   local midnight, not 24 hours after launch.
6. **The timer keeps counting while the panel is closed.** This is the one thing
   that must survive the tab going away, because it is the entire point. The
   store belongs to `AppModel` and has no idea whether anything is on screen.
7. Optional, only if it is clean: the tray icon shows the remaining time while a
   block is running. The notch itself cannot show it — it is a hole in the
   display, nothing lights up there.

**Done when.** Start 25 minutes, close the panel, do something else: the
notification arrives on time, once, and the "sessions today" line has gone up by
one. Pause and reopen: the same number is still there.

**Not in scope.** History beyond today, charts, a custom-duration editor,
syncing anywhere.

---

## Weather

**Goal.** The temperature at a glance, without a browser tab or reaching for a
phone.

**Data.** [Open-Meteo](https://open-meteo.com) — `api.open-meteo.com/v1/forecast`.
No API key, no account, no OAuth. Current conditions plus hourly.

**Tasks.**

1. `WeatherStore` — fetch when the tab appears, cache the result, and refuse to
   refetch more often than every 15 minutes. Never touch the network while the
   tab is not on screen. The refresh glyph in the top right is already wired to
   nothing; give it the forced refetch.
2. Location through CoreLocation, asked for the first time the Weather tab is
   opened. Add `NSLocationWhenInUseUsageDescription` to the Info.plist that
   `build.sh` writes. If location is refused, fall back to a city typed by hand —
   reuse `AddRow`, do not invent a second form.
3. Map Open-Meteo's WMO weather codes to SF Symbols, with day and night
   variants. This mapping is the only fiddly part of the tab; keep it in one
   table, not scattered through the view.
4. Six hourly slots starting at the next whole hour.
5. Offline, refused, or a failed request → `MessageView` with a retry action.
   Never a blank panel and never a stale number with no indication it is stale.
6. Celsius and m/s, fixed. No settings screen.

**Done when.** Opening the tab shows the real temperature for the real location
within about two seconds; closing and reopening inside 15 minutes makes no
network request; airplane mode shows the error state with a working retry.

**Not in scope.** Multi-day forecast, several cities at once, weather alerts,
radar.

---

## System

**Goal.** Battery, disk and memory in one hover, instead of three different
places in the OS.

**Data.** All local. No permissions needed for any of it.

**Tasks.**

1. Battery — `IOPSCopyPowerSourcesInfo`: percentage, time remaining, charging
   flag. While plugged in, the caption reads "Charging", not a time estimate.
2. Disk — `volumeAvailableCapacityForImportantUsage` on `/`. That is the number
   Finder shows; `volumeAvailableCapacity` is not, and the two disagree by tens
   of gigabytes.
3. Memory — `host_statistics64`. Define "used" as Activity Monitor's *Memory
   Used* (app memory + wired + compressed) so the figure matches what the user
   can check it against.
4. Poll every 5 seconds while the tab is visible, and not at all otherwise.
5. Footnote: uptime from `sysctl kern.boottime`. The CPU temperature next to it
   needs SMC access — **if that turns out to need a private API or an
   entitlement, drop the temperature and ship uptime alone.** Do not add a
   helper binary or a shell-out for it.
6. Ring colour stays the single accent. The one exception: when a value is
   actually critical (battery under 10%, disk under 5% free), tint that one ring
   and leave the others alone.

**Done when.** Every figure agrees with Activity Monitor and System Settings to
within rounding, and the app uses no measurable CPU while the tab is closed.

**Not in scope.** Per-process lists, network throughput, fan or thermal control,
history graphs.
