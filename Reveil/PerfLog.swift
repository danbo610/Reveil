//
//  PerfLog.swift
//  Reveil
//
//  Temporary instrumentation for tracking down a stall when the About tab appears. The device's
//  own HangTracer reports the stalls but not what runs during them, and this app cannot be
//  sampled from outside — library validation kills the process when an agent is injected. So a
//  watchdog thread inside the app catches the main thread in the act: when the run loop stops
//  ticking it suspends the main thread, walks its frame pointers, resumes it, and only then
//  symbolises what it found. Nothing is allocated while the thread is suspended, or the logging
//  itself could deadlock against a malloc lock the main thread was holding.
//
//  Remove once the stall is understood.
//

import Darwin
import Foundation

enum PerfLog {
    private static let stallThreshold: TimeInterval = 0.4
    private static let maxFrames = 40
    private static let maxReports = 8

    private static var mainThread: mach_port_t = 0
    private static var observer: CFRunLoopObserver?
    private static var watchdogStarted = false
    private static var reportsMade = 0

    private static var lastTick = CFAbsoluteTimeGetCurrent()
    private static var marker = "launch"
    private static var reportedThisStall = false
    private static let stateLock = NSLock()

    // Filled while the main thread is suspended, so it must exist beforehand.
    private static let frameBuffer = UnsafeMutablePointer<UInt64>.allocate(capacity: maxFrames)

    /// Names whatever the app did last, so a stall can be attributed to it.
    static func mark(_ value: String) {
        stateLock.lock()
        marker = value
        stateLock.unlock()
        NSLog("[reveil-perf] mark %@", value)
    }

    /// Reports how long a piece of work took, when it is long enough to matter.
    static func record(_ label: String, since started: CFAbsoluteTime) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
        if elapsed > 20 {
            NSLog("[reveil-perf] %@ took %.0f ms", label, elapsed)
        }
    }

    static func start() {
        guard observer == nil else { return }
        mainThread = mach_thread_self()

        let created = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.allActivities.rawValue, true, 0
        ) { _, activity in
            let now = CFAbsoluteTimeGetCurrent()
            stateLock.lock()
            let elapsed = now - lastTick
            lastTick = now
            reportedThisStall = false
            let lastMark = marker
            stateLock.unlock()
            if elapsed > 0.25 {
                NSLog("[reveil-perf] main thread blocked %.0f ms before activity %lu; last mark: %@",
                      elapsed * 1000, activity.rawValue, lastMark)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), created, .commonModes)
        observer = created

        startWatchdog()
    }

    private static func startWatchdog() {
        guard !watchdogStarted else { return }
        watchdogStarted = true
        let thread = Thread {
            while true {
                Thread.sleep(forTimeInterval: 0.05)
                stateLock.lock()
                let silentFor = CFAbsoluteTimeGetCurrent() - lastTick
                let alreadyReported = reportedThisStall
                let lastMark = marker
                stateLock.unlock()

                guard silentFor > stallThreshold, !alreadyReported, reportsMade < maxReports else {
                    continue
                }
                stateLock.lock()
                reportedThisStall = true
                stateLock.unlock()
                reportsMade += 1
                captureMainStack(silentFor: silentFor, marker: lastMark)
            }
        }
        thread.name = "reveil-perf-watchdog"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private static func captureMainStack(silentFor: TimeInterval, marker: String) {
        var frames = 0

        // Everything between suspend and resume is allocation free.
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return }

        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size
        )
        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(mainThread, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            frameBuffer[0] = state.__pc
            frames = 1
            var framePointer = state.__fp
            while frames < maxFrames, framePointer != 0, framePointer % 8 == 0 {
                var pair = (UInt64(0), UInt64(0))
                var read = vm_size_t(0)
                // Reading through the kernel rather than dereferencing: a frame pointer that has
                // walked off the end of the chain returns an error here instead of a crash.
                let ok = withUnsafeMutablePointer(to: &pair) {
                    vm_read_overwrite(
                        mach_task_self_, vm_address_t(framePointer), 16,
                        vm_address_t(UInt(bitPattern: $0)), &read
                    )
                }
                guard ok == KERN_SUCCESS, read == 16, pair.1 != 0 else { break }
                frameBuffer[frames] = pair.1
                frames += 1
                guard pair.0 > framePointer else { break }
                framePointer = pair.0
            }
        }

        thread_resume(mainThread)

        NSLog("[reveil-perf] --- main thread stuck %.0f ms after %@; %d frames ---",
              silentFor * 1000, marker, frames)
        for index in 0 ..< frames {
            let address = frameBuffer[index]
            var info = Dl_info()
            if dladdr(UnsafeRawPointer(bitPattern: UInt(address)), &info) != 0 {
                let image = info.dli_fname.map {
                    (String(cString: $0) as NSString).lastPathComponent
                } ?? "?"
                let symbol = info.dli_sname.map { String(cString: $0) } ?? "?"
                let offset = UInt(address) - UInt(bitPattern: info.dli_saddr)
                NSLog("[reveil-perf]   %2d  %@  %@ + %lu", index, image, symbol, offset)
            } else {
                NSLog("[reveil-perf]   %2d  0x%llx", index, address)
            }
        }
    }
}
