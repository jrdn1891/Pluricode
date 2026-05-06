import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Observation

enum PermissionStatus {
    case granted, denied, notDetermined
}

enum Permission: String, CaseIterable, Identifiable {
    case microphone, screenRecording, camera, accessibility, automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .screenRecording: "Screen & System Audio Recording"
        case .camera: "Camera"
        case .accessibility: "Accessibility"
        case .automation: "Automation (AppleScript)"
        }
    }

    var rationale: String {
        switch self {
        case .microphone:
            "CLIs that record voice — transcription tools, voice agents, meeting recorders."
        case .screenRecording:
            "macOS routes system audio capture through Screen Recording. Required to record what's playing on the Mac."
        case .camera:
            "CLIs that capture video — demo recorders, screen-share helpers."
        case .accessibility:
            "CLIs that synthesize keystrokes, read window state, or drive other apps."
        case .automation:
            "CLIs that talk to other apps via AppleScript or `osascript`."
        }
    }

    var systemSettingsURL: URL {
        let key: String = switch self {
        case .microphone: "Privacy_Microphone"
        case .screenRecording: "Privacy_ScreenCapture"
        case .camera: "Privacy_Camera"
        case .accessibility: "Privacy_Accessibility"
        case .automation: "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(key)")!
    }
}

@Observable
final class PermissionsService {
    var statuses: [Permission: PermissionStatus] = [:]

    init() { refresh() }

    func refresh() {
        for permission in Permission.allCases {
            statuses[permission] = currentStatus(permission)
        }
    }

    func request(_ permission: Permission) {
        switch permission {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in self.refresh() }
            }
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                Task { @MainActor in self.refresh() }
            }
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
            refresh()
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            refresh()
        case .automation:
            NSWorkspace.shared.open(permission.systemSettingsURL)
        }
    }

    func openSystemSettings(_ permission: Permission) {
        NSWorkspace.shared.open(permission.systemSettingsURL)
    }

    private func currentStatus(_ permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone:
            mapAV(AVCaptureDevice.authorizationStatus(for: .audio))
        case .camera:
            mapAV(AVCaptureDevice.authorizationStatus(for: .video))
        case .screenRecording:
            CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .denied
        case .automation:
            .notDetermined
        }
    }

    private func mapAV(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}
