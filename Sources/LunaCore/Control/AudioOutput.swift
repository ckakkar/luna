import CoreAudio
import Foundation

/// The Mac's current sound output, to decide whether the volume keys should drive a monitor's speakers over
/// DDC. macOS can't change the volume of HDMI or DisplayPort audio itself; that's when Luna steps in.
public struct AudioOutput: Sendable {
    public var name: String
    public var isDisplayAudio: Bool
    public var canSetVolume: Bool

    public static func current() -> AudioOutput? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
                == noErr,
            device != 0
        else { return nil }

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        let deviceName =
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr
            ? (name?.takeRetainedValue() as String?) ?? "" : ""

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        let isDisplay = transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort

        return AudioOutput(name: deviceName, isDisplayAudio: isDisplay, canSetVolume: Self.canSetVolume(device))
    }

    private static func canSetVolume(_ device: AudioDeviceID) -> Bool {
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable: DarwinBoolean = false
            if AudioObjectHasProperty(device, &address),
                AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
            {
                return true
            }
        }
        return false
    }
}
