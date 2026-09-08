import AppKit
import SwiftUI

struct DetailView: View {
    @ObservedObject var model: MeterModel

    private var strings: Strings { model.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.permission == .denied {
                permissionDenied
            } else {
                if !model.isCalibrated { calibrationPrompt }
                LevelBar(reading: model.reading, color: barColor)
                numbers
                Divider()
                calibration
                sensitivitySlider
            }
            if let error = model.error {
                Text(strings.message(for: error))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    private var barColor: Color {
        model.isRunning && model.reading.hasSignal ? model.state.color : Color.secondary
    }

    private var headline: String {
        guard model.isRunning else { return strings.paused }
        return model.reading.hasSignal ? strings.title(for: model.state) : strings.noSignal
    }

    private var subhead: String {
        guard model.isRunning else { return strings.notListening }
        return model.reading.hasSignal
            ? strings.detail(for: model.state)
            : strings.noSignalDetail
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(barColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.headline)
                Text(subhead)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    /// Shown until the thresholds have heard this particular voice. Without it
    /// the app looks like it is working while quietly guessing.
    private var calibrationPrompt: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(strings.notCalibrated)
                    .font(.caption.weight(.semibold))
                Text(strings.notCalibratedDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var permissionDenied: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.micDenied)
                .font(.subheadline.weight(.medium))
            Text(strings.micDeniedDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(strings.openPrivacySettings) {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var numbers: some View {
        // While paused there is nothing being measured, so report that rather
        // than a stale "+0 dB" that reads like a real reading.
        let live = model.isRunning
        return VStack(spacing: 4) {
            row(strings.ambientNoise, live ? db(model.reading.floorDb) : "—")
            row(strings.yourLevel, live ? db(model.reading.voiceDb) : "—")
            row(strings.aboveAmbient, live ? relative(model.reading.excessDb) : "—")
            row(strings.shoutThreshold, live ? relative(model.reading.shoutThresholdDb) : "—")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private var calibration: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(strings.calibration)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(strings.normalReference(Int(model.normalExcessDb.rounded())))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                calibrateButton
                    .disabled(!model.isRunning || model.isCalibrating)

                Button(strings.reset) { model.resetCalibration() }
                    .disabled(model.isCalibrating)
            }
            Text(model.calibrationResult.map(strings.calibrationOutcome) ?? strings.calibrationHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var calibrateButton: some View {
        let label = model.isCalibrating
            ? strings.speakNow(model.calibrationRemaining)
            : strings.measureMyVoice
        if model.isCalibrated {
            Button(label) { model.startCalibration() }
        } else {
            Button(label) { model.startCalibration() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var sensitivitySlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(strings.sensitivity)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(model.sensitivity == 0
                     ? "0 dB"
                     : String(format: "%+.0f dB", model.sensitivity))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $model.sensitivity, in: -8...8, step: 1) {
                EmptyView()
            } minimumValueLabel: {
                Text(strings.tolerant).font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(strings.sensitive).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Text(strings.languageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(strings.languageLabel, selection: $model.language) {
                    ForEach(Language.allCases) { language in
                        Text(language.endonym).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            HStack {
                Button(model.isRunning ? strings.pause : strings.resume) { model.toggle() }
                    .disabled(model.permission != .granted)
                Spacer()
                Button(strings.quit) { NSApp.terminate(nil) }
            }
        }
    }

    private func db(_ value: Float) -> String {
        value <= -99 ? "—" : String(format: "%.0f dBFS", value)
    }

    private func relative(_ value: Float) -> String {
        String(format: "%+.0f dB", value)
    }
}

/// The large meter inside the popover, with a tick where shouting starts.
private struct LevelBar: View {
    let reading: Reading
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: max(width * reading.fill, 10))
                Rectangle()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 2, height: 20)
                    .offset(x: width * reading.thresholdMark - 1)
            }
        }
        .frame(height: 14)
        .animation(.linear(duration: 0.08), value: reading.fill)
    }
}
