# WhisperFly Permission & Update Audit

Audit performed 2026-10-07 in response to three user-visible complaints:

1. *Permissions keep resetting* — Microphone / Screen Recording / Accessibility
   flip back to untrusted for no obvious reason, especially after updates.
2. *Permissions "should stick to the Mac no matter the app version."*
3. *The app should be able to update itself from new commits on GitHub.*

This document records what was found, what was changed, and how to verify it.

---

## 1. Why permissions did not stick

### 1.1 TCC keys grants to the *designated requirement*, not the app name

macOS stores each permission grant against the app's **designated requirement
(DR)**. An ad-hoc signed binary (`codesign -`) has no team identity, so its DR
degenerates to a `cdhash` — the hash of that exact binary. Any rebuild changes
the hash, macOS sees a different program, and all three grants silently stop
applying while System Settings keeps showing the old toggles as enabled.

**Diagnosis shipped in-app:** `Core/CodeSignatureInfo.swift` reads the running
process's signature (`SecCodeCopySigningInformation`, the designated
requirement, team identifier, ad-hoc flag) and `persistenceDiagnosis`
translated the situation into one actionable sentence. The Settings →
Permissions tab shows this before the user wastes time toggling switches.

**Fix in the release pipeline:** `scripts/sign-app.sh` signs every build with
an explicit, stable DR:

```
designated => anchor apple generic and identifier "com.dandysuper.WhisperFly"
              and certificate leaf[subject.OU] = <TEAMID>
```

`scripts/build-app.sh` (new) assembles the bundle and routes signing through
that script; an ad-hoc fallback exists for machines with no certificate but
warns loudly that permissions will reset per rebuild.

### 1.2 Stale TCC rows cannot be fixed by toggling

After a re-sign, the grant rows point at a requirement that no longer matches.
The only remedy is removing the row (`tccutil reset <service> <bundle-id>`) and
granting again. **Fix:** `Services/PermissionRepair.swift` wraps `tccutil`, and
Settings → Permissions exposes *Reset and Relaunch*, which clears all three
rows and restarts the app (a detached shell waits for the old process to exit
before reopening the bundle, so no double menu-bar icon). `AppController`
refuses to relaunch when only some rows were cleared.

### 1.3 The permission probes disagreed with each other and with the OS version

The old code kept two independent `Bool`s, probed Screen Recording with
`CGPreflightScreenCaptureAccess()` (cached per process, documented false
negatives), and gated part of the logic behind `#available(macOS 26)` — so
behaviour changed with the OS version instead of with the actual grant.

**Fix:** `Services/PermissionService.swift` is the single authority:

- **Microphone** — `AVCaptureDevice.authorizationStatus` (accurate, distinguishes
  *not determined* from *denied*, the only permission offering an in-app prompt).
- **Screen Recording** — preflight as a hint, then the real
  `SCShareableContent` call as the verdict. `PermissionState(screenCaptureError:)`
  maps `SCStreamError` codes that genuinely mean "not allowed" (including
  `failedToStartAudioCapture`, which is what macOS 15+ returns for a missing
  Screen Recording grant) onto `.denied`; everything transient stays `.unknown`
  so a hiccup never masquerades as a missing grant. Version-independent.
- **Accessibility** — `AXIsProcessTrusted()` caches; a live
  `AXUIElementCopyAttributeValue` on the system-wide element breaks the tie.

States live in one `@Published` dictionary; the menu bar, settings and the
recording pipeline all observe the same source, and re-probing runs whenever
the app becomes active (the moment users return from System Settings).

### 1.4 A failed settings decode silently wiped preferences

`SettingsStore` wrapped decoding in `try?` and fell through to defaults, while
`AppSettings` used the synthesised `Codable` decoder — which throws
`keyNotFound` even when a property has a default, and `dataCorrupted` for an
unknown enum raw value. Net effect: adding one field to `AppSettings` reset
**every** preference, API keys included, on every existing install. The same
shape of bug existed in `TranscriptionHistory` (one bad entry killed the whole
history array).

**Fix:**

- `AppSettings` decodes by hand: every missing/mistyped key falls back to its
  default, out-of-range numbers are re-clamped, and legacy raw values migrate
  (label-based `AudioSource`/`TranscriptionBackend`/`HotkeyPreset` strings from
  the 2.x releases, including the removed `NIM Canary` backend).
- `SettingsStore` keeps the unreadable blob, copies it to a backup key
  (`whisperflow_settings_corrupt_backup`) and continues with defaults instead of
  writing defaults over the user's data.
- `TranscriptionEntry` decodes per field with fallbacks; the history array
  decodes lossily per entry, so at worst one entry is dropped, never the list.
- The `.env` fallback, previously unreachable (it looked at `/Applications/.env`
  and at a working directory of `/`), now walks up from both the bundle and the
  working directory.

### 1.5 Hotkey preference existed but did nothing

`HotkeyMonitor` hard-coded ⌘⇧Space regardless of the stored preset. The picker
now drives registration (`AppSettings.HotkeyPreset` carries the Carbon key code
and modifier mask), re-registration only happens when the preset actually
changed (settings save fires on every keystroke), and registration failures map
to specific, localised messages (shortcut already taken, registration error).

---

## 2. Commit-based self-updater

The app ships from `master`, so a merged commit is the event that matters —
version strings in `Info.plist` lag. The updater therefore compares **commits**:

| Piece | File | Role |
|---|---|---|
| Build stamping | `Core/BuildInfo.swift`, `scripts/build-app.sh` | The build script writes `WhisperFlyCommitSHA`, commit/build dates, repository and branch into `Info.plist`; `swift run` degrades to "unstamped" instead of breaking. |
| GitHub REST layer | `Services/GitHubClient.swift` | Branch head, latest release, ancestor check via the compare endpoint; typed errors incl. rate-limit handling with reset time. |
| State machine | `Services/UpdateService.swift` | `idle → checking → upToDate / updateAvailable / localRevisionUnknown / failed`, periodic checks at a configurable interval, commit-vs-commit comparison (`isAncestor`) so an experimental local build is *not* offered a "downgrade". |
| Download | `Services/UpdateDownloader.swift` | Streams the release DMG with progress (no whole-file buffering). |
| Install | `Services/UpdateInstaller.swift` | Mounts the DMG, verifies the bundle identifier, stages the new bundle beside the old one, swaps only after a verified copy, restores the backup on failure, strips quarantine. Runs off the main thread; the caller owns the relaunch. |
| Source path | `UpdateInstaller.rebuildFromSource` | For checkouts: `git pull --ff-only` + `scripts/build-app.sh`, then relaunch — works even when no release DMG exists. |
| Repair bridge | `Services/PermissionRepair.swift` | Relaunch helper used by both update paths and the permission reset. |

Settings → Updates lets the user point at a different repository/branch, add a
read-only token (rate limit / private fork), and configure check frequency.

---

## 3. Other issues found and fixed

- **Main-thread blocking installs** — `UpdateInstaller` is `async`/nonisolated;
  mount, copy, git and rebuild run off the main actor, with `@MainActor`
  relaunching isolated into `UpdateService`.
- **Panel positioning across displays** — AX caret bounds were converted with
  `NSScreen.main`'s height although AX coordinates are rooted at the *primary*
  screen; multi-monitor setups put the status pill on the wrong screen.
  `Core/ScreenPlacement.swift` now owns the coordinate conversion, picks the
  display under the pointer for fallbacks, centres result/history panels on the
  user's display (not `NSWindow.center()`'s primary screen), flips the pill
  below the caret when it would cross the top edge, and clamps everything
  inside the visible frame.
- **Panel crash on macOS 26** — NSPanel objects are kept alive and only
  `orderOut`ed (never released mid-layout), documented in `FloatingPanel`.
- **macOS 26 silent-audio dropout** — recording tracks whether any non-signal
  sample arrived and warns the user before silence is sent to the API, using
  the *start-time* audio source rather than the (possibly changed) setting.

---

## 4. Verification

```bash
swift build                 # clean build, no warnings from project code
scripts/test.sh             # 28 tests (settings decode, history lossy decode,
                            # GitHub parsing, DMG selection, permission mapping,
                            # signature diagnostics)
scripts/build-app.sh        # assemble + stamp + sign with the stable DR
codesign -d -r- WhisperFly.app   # => anchor apple generic and identifier
                                 #    "com.dandysuper.WhisperFly" and
                                 #    certificate leaf[subject.OU] = <TEAMID>
plutil -p WhisperFly.app/Contents/Info.plist | grep WhisperFly  # stamps
```

`scripts/test.sh` exists because a Command Line Tools–only toolchain ships the
Swift Testing macro plugin in a subdirectory the build system does not scan;
the script passes the path explicitly.

**Manual matrix for the permission claims:**

1. Install a build signed by `scripts/build-app.sh`, grant all three
   permissions, then install a newer build (or run the in-app updater):
   all three toggles must stay granted and working — the DR matches across
   rebuilds.
2. Settings → Permissions → *Reset and Relaunch*: app quits, reopens, all three
   permissions prompt again.
3. Settings → Permissions shows the signature panel; on an ad-hoc build it
   explains exactly why grants will not survive and how to fix it.
