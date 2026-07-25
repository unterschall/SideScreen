// Phase 0 de-risk spike for pressure-sensitive pen support.
//
// This is a THROWAWAY validation tool. It does not touch the app. Its only job
// is to answer one question before we build the Android/wire/host pipeline:
//
//     Does a synthesized macOS tablet-pressure event actually reach a real
//     drawing app and vary stroke width?
//
// If YES  -> proceed with Phases 1-3 in the plan.
// If NO   -> stop; synthesized CGEvents are insufficient and we'd need a
//            DriverKit / IOHIDUserDevice virtual tablet (much heavier).
//
// ── How to run ────────────────────────────────────────────────────────────
//   1. On your Mac: open a pressure-aware drawing app (Krita, Photoshop trial,
//      Clip Studio, etc.). Pick a brush whose SIZE is set to follow pen
//      pressure. Make the canvas the frontmost window.
//   2. In Terminal:  swift MacHost/PenSpike/pen_spike.swift
//   3. You have 4 seconds to click into the drawing canvas so it has focus.
//   4. The spike draws a horizontal stroke across the middle of the MAIN
//      display, ramping pressure 0.0 -> 1.0 left-to-right.
//
//   PASS  = the stroke visibly tapers (thin on the left, thick on the right).
//   FAIL  = the stroke is a constant-width line (pressure ignored).
//
// Grant Accessibility permission to your terminal (System Settings > Privacy &
// Security > Accessibility) or the events are silently dropped.
//
// Optional: pass a target rect to draw inside a specific area, e.g.
//   swift pen_spike.swift 400 500 900   (startX startY endX, same Y)

import Cocoa
import CoreGraphics

// MARK: - Config

let args = CommandLine.arguments
let mainBounds = CGDisplayBounds(CGMainDisplayID())
// Default: a horizontal sweep across the middle third of the main display.
let startX = args.count > 1 ? Double(args[1]) ?? mainBounds.midX - 300 : mainBounds.midX - 300
let y      = args.count > 2 ? Double(args[2]) ?? mainBounds.midY       : mainBounds.midY
let endX   = args.count > 3 ? Double(args[3]) ?? mainBounds.midX + 300 : mainBounds.midX + 300

let steps = 120                     // samples along the stroke
let stepDelay: useconds_t = 8_000   // ~8ms between samples (~125 Hz)

guard let source = CGEventSource(stateID: .hidSystemState) else {
    fputs("Failed to create CGEventSource\n", stderr)
    exit(1)
}

// MARK: - Tablet field helpers
//
// The trick: a normal mouse event is tagged with the tablet-point subtype and
// given the tablet pressure/tilt fields. AppKit then surfaces `NSEvent.pressure`
// to the frontmost app. Pressure is a Double in 0.0...1.0.

let tabletPointSubtype = Int64(NSEvent.EventSubtype.tabletPoint.rawValue)          // 1
let tabletProximitySubtype = Int64(NSEvent.EventSubtype.tabletProximity.rawValue)  // 2

func stampTablet(_ event: CGEvent, pressure: Double, tiltX: Double = 0, tiltY: Double = 0) {
    event.setIntegerValueField(.mouseEventSubtype, value: tabletPointSubtype)
    event.setDoubleValueField(.mouseEventPressure, value: pressure)
    event.setDoubleValueField(.tabletEventPointPressure, value: pressure)
    event.setDoubleValueField(.tabletEventTiltX, value: tiltX)   // -1...1
    event.setDoubleValueField(.tabletEventTiltY, value: tiltY)   // -1...1
    // A device id so the app treats a whole stroke as one pointer.
    event.setIntegerValueField(.tabletEventDeviceID, value: 1)
}

func post(_ type: CGEventType, at p: CGPoint, pressure: Double) {
    guard let e = CGEvent(mouseEventSource: source, mouseType: type,
                          mouseCursorPosition: p, mouseButton: .left) else { return }
    stampTablet(e, pressure: pressure)
    e.post(tap: .cghidEventTap)
}

// Proximity enter/exit tell the app a pen entered/left the sensor. Some apps
// won't switch into "pen mode" (and thus won't read pressure) without it.
func postProximity(entering: Bool, at p: CGPoint) {
    guard let e = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                          mouseCursorPosition: p, mouseButton: .left) else { return }
    e.setIntegerValueField(.mouseEventSubtype, value: tabletProximitySubtype)
    e.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
    e.setIntegerValueField(.tabletProximityEventPointerType, value: 1) // 1 = pen
    e.setIntegerValueField(.tabletProximityEventDeviceID, value: 1)
    e.post(tap: .cghidEventTap)
}

// MARK: - Preflight

if !AXIsProcessTrusted() {
    fputs("""
    ⚠️  Accessibility permission NOT granted for this process (your terminal).
        System Settings > Privacy & Security > Accessibility -> enable Terminal.
        Events will be dropped until you do. Continuing anyway...\n
    """, stderr)
}

print("Main display: \(Int(mainBounds.width))x\(Int(mainBounds.height))")
print("Stroke: (\(Int(startX)), \(Int(y))) -> (\(Int(endX)), \(Int(y)))  pressure 0.0 -> 1.0")
print("Focus your drawing app's canvas now...")
for n in stride(from: 4, through: 1, by: -1) { print("  \(n)"); sleep(1) }
print("Drawing.")

// MARK: - Draw one pressure-ramped stroke

let start = CGPoint(x: startX, y: y)

postProximity(entering: true, at: start)
usleep(20_000)

// Pen down at zero-ish pressure.
post(.leftMouseDown, at: start, pressure: 0.02)
usleep(stepDelay)

for i in 1...steps {
    let t = Double(i) / Double(steps)
    let p = CGPoint(x: startX + (endX - startX) * t, y: y)
    let pressure = max(0.0, min(1.0, t))            // linear 0 -> 1
    post(.leftMouseDragged, at: p, pressure: pressure)
    usleep(stepDelay)
}

let end = CGPoint(x: endX, y: y)
post(.leftMouseUp, at: end, pressure: 0.0)
usleep(20_000)
postProximity(entering: false, at: end)

print("""

Done. Look at your canvas:
  PASS -> stroke tapers thin(left) to thick(right)  => pressure works, proceed.
  FAIL -> constant-width line                        => CGEvent pressure ignored
          by this app; try another app, or plan for a DriverKit virtual tablet.
""")
