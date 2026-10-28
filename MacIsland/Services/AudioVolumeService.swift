import Foundation
import CoreAudio
import AudioToolbox
import Observation

/// Listens to the default output device's volume and mute state through Core Audio
/// property listeners (no polling). Devices without a software volume (HDMI, some
/// DisplayPort monitors) report `supportsVolume == false`.
@MainActor
@Observable
final class AudioVolumeService {
    struct Snapshot: Equatable {
        var volume: Float = 0
        var isMuted = false
        var supportsVolume = false
        var deviceName = ""
    }

    private(set) var snapshot = Snapshot()
    /// Called with (new, old) whenever the volume or mute state changes.
    @ObservationIgnored var onChange: ((Snapshot, Snapshot) -> Void)?

    @ObservationIgnored private var deviceID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var volumeAddress: AudioObjectPropertyAddress?
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var startedAt = Date()

    nonisolated private static let defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    nonisolated private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    nonisolated private static let nameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        startedAt = Date()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultDeviceChanged() }
        }
        defaultDeviceListener = listener
        var address = Self.defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        attach(to: Self.currentDefaultOutputDevice())
        snapshot = read()
        Log.system.notice("audio: device=\(self.snapshot.deviceName, privacy: .public) volume=\(self.snapshot.volume) muted=\(self.snapshot.isMuted)")
    }

    private func defaultDeviceChanged() {
        attach(to: Self.currentDefaultOutputDevice())
        snapshot = read()
    }

    private func attach(to newDevice: AudioObjectID) {
        detach()
        guard newDevice != kAudioObjectUnknown else { return }
        deviceID = newDevice

        // Prefer the virtual main volume; fall back to channel 1 when the device lacks it.
        var candidate = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(newDevice, &candidate) {
            candidate = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: 1
            )
        }
        volumeAddress = AudioObjectHasProperty(newDevice, &candidate) ? candidate : nil

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.volumeChanged() }
        }
        deviceListener = listener
        if var volumeAddress {
            AudioObjectAddPropertyListenerBlock(newDevice, &volumeAddress, .main, listener)
        }
        var mute = Self.muteAddress
        if AudioObjectHasProperty(newDevice, &mute) {
            AudioObjectAddPropertyListenerBlock(newDevice, &mute, .main, listener)
        }
    }

    private func detach() {
        guard deviceID != kAudioObjectUnknown, let listener = deviceListener else { return }
        if var volumeAddress {
            AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, .main, listener)
        }
        var mute = Self.muteAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &mute, .main, listener)
        deviceListener = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private func volumeChanged() {
        let new = read()
        let old = snapshot
        snapshot = new
        // Some drivers fire once right after registration; ignore the warm-up.
        guard Date().timeIntervalSince(startedAt) > 1.5 else { return }
        if new.volume != old.volume || new.isMuted != old.isMuted {
            onChange?(new, old)
        }
    }

    private func read() -> Snapshot {
        var result = Snapshot()
        guard deviceID != kAudioObjectUnknown else { return result }
        result.deviceName = Self.deviceName(deviceID)
        if var volumeAddress {
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &volume) == noErr {
                result.volume = min(max(volume, 0), 1)
                result.supportsVolume = true
            }
        }
        var mute = Self.muteAddress
        if AudioObjectHasProperty(deviceID, &mute) {
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(deviceID, &mute, 0, nil, &size, &muted) == noErr {
                result.isMuted = muted != 0
            }
        }
        return result
    }

    nonisolated private static func currentDefaultOutputDevice() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = defaultDeviceAddress
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    nonisolated private static func deviceName(_ device: AudioObjectID) -> String {
        var address = nameAddress
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return "" }
        return name as String
    }
}
