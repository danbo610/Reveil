//
//  PerfLog.swift
//  Reveil
//
//  Temporary instrumentation for tracking down a stall when the About tab appears. The device's
//  own HangTracer reports the stalls but not what runs during them, and this app cannot be
//  sampled with a debugger — library validation kills the process when an agent is injected.
//  So the app times its own main thread instead.
//
//  Remove once the stall is understood.
//

import Foundation

enum PerfLog {
    private static var lastTick = CFAbsoluteTimeGetCurrent()
    private static var marker = "launch"
    private static var observer: CFRunLoopObserver?

    /// Names whatever the app did last, so a stall can be attributed to it.
    static func mark(_ value: String) {
        marker = value
        NSLog("[reveil-perf] mark %@", value)
    }

    /// Reports how long a piece of work took, when it is long enough to matter.
    static func record(_ label: String, since started: CFAbsoluteTime) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
        if elapsed > 20 {
            NSLog("[reveil-perf] %@ took %.0f ms", label, elapsed)
        }
    }

    /// Watches the main run loop and reports any iteration that takes long enough to be seen.
    static func start() {
        guard observer == nil else { return }
        let created = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.allActivities.rawValue, true, 0
        ) { _, activity in
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - lastTick
            lastTick = now
            if elapsed > 0.25 {
                NSLog("[reveil-perf] main thread blocked %.0f ms before activity %lu; last mark: %@",
                      elapsed * 1000, activity.rawValue, marker)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), created, .commonModes)
        observer = created
    }
}
