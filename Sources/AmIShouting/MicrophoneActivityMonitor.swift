import AppKit
import CoreAudio
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

    /// Only a real, user-facing application counts as a call.
    ///
    /// System daemons hold the input for their own reasons — CoreSpeech grabs
    /// it the moment anything else starts recording, and would otherwise keep
    /// this app awake long after the call ended. Menu bar utilities, including
    /// this one, are not calls either.
    static func isUserFacingApp(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
    }

    /// nil when the query is unavailable, which is not the same as "nobody is
    /// recording".
    private func anotherProcessIsRecording() -> Bool? {
        guard let processes = processObjectIDs() else { return nil }
        for process in processes {
            let processPID = pid(of: process)
            guard processPID != ownPID,
                  Self.isUserFacingApp(processPID),
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
