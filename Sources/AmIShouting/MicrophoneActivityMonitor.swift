import AppKit
import CoreAudio
import Darwin
import Foundation

/// Reports whether some *other* process is capturing audio input — in
/// practice, whether you are in a call.
///
/// CoreAudio's per-process API is polled rather than observed: a listener would
/// have to be added and removed as processes come and go, while one property
/// read every couple of seconds costs nothing and cannot leak registrations.
final class MicrophoneActivityMonitor {

    /// Called on the main queue whenever the answer changes.
    var onChange: ((Bool) -> Void)?

    private(set) var isOtherProcessRecording = false
    private var timer: Timer?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Older macOS 14 builds do not expose the process object list. Callers
    /// have to fall back to listening all the time rather than going deaf.
    var isSupported: Bool { processObjectIDs() != nil }

    func start(pollInterval: TimeInterval = 2) {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Keep polling while a menu is tracking, otherwise the state freezes
        // for as long as the popover is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isOtherProcessRecording {
            isOtherProcessRecording = false
            onChange?(false)
        }
    }

    private func refresh() {
        guard let recording = anotherProcessIsRecording(), recording != isOtherProcessRecording else {
            return
        }
        isOtherProcessRecording = recording
        onChange?(recording)
    }

    /// Whether a process belongs to a real, user-facing application — either
    /// it is one, or it was spawned by one.
    ///
    /// The parent walk is what makes browsers work: a Meet or Zoom call in
    /// Chrome is captured by a helper process (`com.google.Chrome.helper`)
    /// that is not an application in its own right, while its parent Chrome
    /// is. Testing only the process itself missed every browser call.
    ///
    /// It still excludes what it has to. System daemons like CoreSpeech —
    /// which grabs the input the moment anything else records, and would keep
    /// this app awake long after a call ended — descend from launchd, not from
    /// an app.
    static func belongsToUserFacingApp(_ pid: pid_t) -> Bool {
        var current = pid
        // Deep enough for a browser's helper-of-a-helper, bounded so a cycle
        // or a reparented process cannot spin here.
        for _ in 0..<8 {
            guard current > 1 else { return false }
            if NSRunningApplication(processIdentifier: current)?.activationPolicy == .regular {
                return true
            }
            guard let parent = parentPID(of: current), parent != current else { return false }
            current = parent
        }
        return false
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// nil when the query is unavailable, which is not the same as "nobody is
    /// recording".
    private func anotherProcessIsRecording() -> Bool? {
        guard let processes = processObjectIDs() else { return nil }
        for process in processes {
            let processPID = pid(of: process)
            guard processPID != ownPID,
                  Self.belongsToUserFacingApp(processPID),
                  isRunningInput(process) else { continue }
            return true
        }
        return false
    }

    private func processObjectIDs() -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return nil
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return nil
        }
        return ids
    }

    private func pid(of process: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else {
            return -1
        }
        return value
    }

    private func isRunningInput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }
}
