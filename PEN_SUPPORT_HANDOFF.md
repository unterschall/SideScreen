# Pen / Pressure Support — Session Handoff

> **Why this file exists:** work on pressure-sensitive pen support was done in a
> Claude Code session on a Linux machine (which has no Swift/Cocoa or Android
> toolchain, so **nothing was compiled or run**). This file lets a fresh Claude
> Code session on the Mac resume with full context. Delete it once the feature
> is merged.
>
> To resume: open Claude Code in this repo and say *"Read PEN_SUPPORT_HANDOFF.md
> and continue the pen support work — start by building both apps."*

Feature branch base: `main` @ `0.11.1`. All changes below are **uncommitted** in
the working tree (they travel with a folder copy; `git status` should show the 5
modified files + `MacHost/PenSpike/`).

---

## Goal

Let an Android stylus drive a **pressure-sensitive pen** on the macOS host, so a
drawing app on the Mac reacts to pen pressure, tilt, eraser, and barrel button.
Scope agreed with the user: **full stylus** (pressure + tilt + barrel-button +
eraser + palm rejection), **USB-C first** (wireless inherits the same TCP path).

---

## Status

| Phase | What | State |
|---|---|---|
| **0** | De-risk spike — prove synthesized macOS tablet pressure reaches a drawing app | **PASS** (2026-07-24, Affinity). Photoshop showed constant-width (Photoshop-specific quirk — it doesn't honor synthesized tablet CGEvents; not a systemic limitation). `MacHost/PenSpike/pen_spike.swift` |
| **1** | Wire protocol + capability negotiation (msgs 12/13/14) | Written, **compiles clean** (`swift build`, no errors) |
| **2** | Android capture (stylus routing, tilt, palm rejection, hover) | Written, **compiles clean** (`./gradlew assembleDebug`, no errors) |
| **3** | macOS injection (tablet events) + settings toggle | Written, **compiles clean** (part of MacHost build above) |

**Phase 0 passed against Affinity** — synthesized `CGEvent` tablet pressure
does vary stroke width in a real drawing app, confirming `handlePen`'s approach
is viable. Note: Photoshop specifically did not respond to the same synthetic
events; treat Photoshop as an app-specific gap, not evidence the mechanism is
broken. Both MacHost (`swift build`) and AndroidClient (`./gradlew
assembleDebug`) now build with zero errors.

```bash
# Phase 0 gating test (open a pressure-aware drawing app first, brush size = pen pressure):
swift MacHost/PenSpike/pen_spike.swift
# PASS = stroke tapers thin->thick.  FAIL = constant width (see file header).
# You may need to grant Terminal Accessibility permission.
```

---

## Files changed

### macOS host (`MacHost/`)
- **`Sources/StreamingServer.swift`** — added wire messages `penEvent = 12`,
  `clientSupportsPen = 13`, `penEnabled = 14`; a host `penEnabled` gate + an
  `onPenEvent` callback; parsing of type 12 (23-byte frame) and type 13; sends
  type 14 in `finishProtocolStartup` only when the client opted in AND the host
  setting is on; `handlePenMessage` decodes the payload.
- **`Sources/AppDelegate.swift`** — `settings.$penEnabled` observer; sets
  `streamingServer.penEnabled` at start; wires `onPenEvent` → new **`handlePen`**
  which **bypasses the gesture state machine** and synthesizes tablet events via
  `penProximity` / `penPost` (proximity enter/exit + `tabletPoint` subtype with
  `mouseEventPressure` / `tabletEventPointPressure` / tilt). Eraser → eraser
  proximity pointer type; barrel-primary → right-click.
- **`Sources/SettingsWindow.swift`** — `@Published var penEnabled` (persisted,
  default `true`), reset handling, and a "Pressure-Sensitive Pen" toggle in the
  Touch Control group.
- **`PenSpike/pen_spike.swift`** — the Phase 0 spike (throwaway; not part of the
  app target).

### Android client (`AndroidClient/`)
- **`.../StreamClient.kt`** — message constants 12/13/14; a `penEnabled`
  capability flag + `onPenEnabled` callback; `advertisePenSupport()` (sent before
  type 8, like the AVC/decoder-limit opt-ins); handles incoming type 14; and
  **`sendPen(...)`** which no-ops until the host advertised pen support.
- **`.../MainActivity.kt`** — `routeInput` splits stylus vs finger; `handleStylus`
  + `handleHover` + `sendPenSample` read pressure / `AXIS_TILT` /
  `AXIS_ORIENTATION` / barrel buttons and **bypass `InputPredictor`**;
  `stylusActive` drives **palm rejection**; hover listeners added to both video
  views. Finger touch path is unchanged.

---

## Wire format (authoritative)

All little-endian. Client→host unless noted. Numbers are the type byte.

- **12 — pen event** (23 bytes): `[type][flags:u8][x:f32][y:f32][pressure:f32][tiltX:f32][tiltY:f32][action:u8]`
  - `flags`: bit0 = eraser, bit1 = barrel-primary, bit2 = barrel-secondary
  - `action`: 0 down · 1 move · 2 up · 3 hover-move · 4 hover-enter · 5 hover-exit
  - `pressure` 0..1; `tiltX`/`tiltY` −1..1 (macOS convention)
- **13 — client-supports-pen** (1 byte, payload-free): client opt-in
- **14 — pen-enabled** (1 byte, payload-free, **host→client**): sent only to
  clients that sent 13 and only when the host `penEnabled` setting is on

**Compatibility contract:** the client must never send type 12 before receiving
type 14. Old hosts never send 14 → the client stays on the finger touch path →
no byte-stream desync. Keep this invariant if you touch the handshake.

Constants must stay in sync: `StreamingServer.swift` `enum WireMessage`
(Mac) ↔ `StreamClient.kt` `companion object` (Android).

---

## Build & test

```bash
# Host
cd MacHost && swift build            # or open in Xcode
# Client
cd AndroidClient && ./gradlew assembleDebug
```

End-to-end (USB-C, lowest latency for drawing):
1. Run Phase 0 spike — must PASS.
2. Launch host, connect the tablet, ensure "Pressure-Sensitive Pen" is on.
3. Open a pressure-aware drawing app on the **virtual display**.
4. Draw with the pen and verify: (a) width/opacity tracks pressure, (b) tilt
   affects tilt-aware brushes, (c) barrel button = right-click, (d) eraser tip
   erases, (e) resting a palm mid-stroke emits no stray marks.
5. Backward-compat: new client against an **unmodified/old host** build must
   silently fall back to touch with no desync.

**Device test done (2026-07-24), Lenovo TB361FU tablet + USB-C, Android 16:**
- (a) pressure — **PASS**, stroke width tracks pressure in Affinity.
- (b) tilt — **PASS**, tilt-aware brush responds correctly.
- (c) barrel button — **untested**, this stylus has no barrel button.
- (d) eraser tip — **untested**, this stylus has no eraser tip.
- (e) palm rejection — **PASS**, resting a palm mid-stroke produced no stray
  marks and didn't interrupt the ongoing stylus stroke.
- (5) backward-compat — **PASS**. Built the pre-pen-support commit (`a651a81`)
  in a separate worktree, ran it in place of the new host, reconnected the new
  client: clean reconnect, no desync, finger touch worked normally.

Barrel button and eraser remain unverified against real hardware — revisit
with a stylus that has them before calling this fully done.

---

## Known caveats & TODO (pick up here)

1. ~~Not compiled anywhere yet~~ — **done.** Both apps build clean with zero
   compiler errors (`swift build`, `./gradlew assembleDebug`); 40/40 host
   tests pass (`swift test`, requires full Xcode — CLT alone lacks XCTest).
2. **Tilt conversion is approximate** — `sendPenSample` maps Android
   `AXIS_TILT`+`AXIS_ORIENTATION` to macOS `tiltX/tiltY` with
   `tiltX = sin(orient)·frac`, `tiltY = −cos(orient)·frac`. Verify against a real
   pen; also does not yet account for display rotation.
3. ~~Unit test not added~~ — **done.** Extracted the 23-byte decode into
   `WirePenMessage.decode` (`MacHost/Sources/PenEventCodec.swift`), used by
   `StreamingServer.handlePenMessage`; covered by
   `MacHost/Tests/SideScreenTests/PenEventCodecTests.swift`.
4. ~~Multi-pointer edge case~~ — **fixed.** `MainActivity.kt`'s `routeInput`
   now tracks `fingerActive` and calls `endOrphanedFingerGesture` to send a
   synthetic finger-UP before switching to the stylus path, so a finger drag
   already in progress when a stylus lands gets a clean UP on the host instead
   of leaving the gesture state machine (and a real synthesized mouse button)
   stuck. Also fixed two related stuck-state bugs found in review:
   `StreamingServer`/`AppDelegate.handlePen` now let an up/hover-exit frame
   through even if the pen setting was toggled off mid-stroke (was previously
   dropped, stranding `penIsDown`), and `AppDelegate.resetPenState()` closes
   out any open stroke/proximity on client disconnect (was previously never
   reset at all). Remaining lower-confidence item from review: rapid
   stylus-lift-then-new-pointer within a single `MotionEvent` batch could
   theoretically hand `handleStylus` a mismatched pointer's data
   (`stylusPointerIndex` matches by tool type + index, not identity) —
   unverified against real hardware, revisit if stroke boundaries look glitchy.
5. **Mid-session toggle** — flipping the host pen setting only advertises at
   connect time; a reconnect is needed for the client to start/stop emitting pen
   frames. The host still gates dispatch live.
6. **CHANGELOG.md untouched** — add an entry once the feature builds and is
   verified.
7. **Cleanup deferred** — code review also flagged three duplication/reuse
   items, deliberately left unfixed pending a decision: `sendPenSample`'s
   coordinate-flip logic triplicates `handleTouch`'s (no shared helper);
   `handlePen`'s up/hover-exit cases duplicate the same stroke-end block;
   `StreamClient.kt`'s two connect paths hand-copy the same startup
   advertisement sequence a third time.

Full original plan (also outside the repo on the Linux box) is reproduced in
`docs/pen-support-plan.md`.
