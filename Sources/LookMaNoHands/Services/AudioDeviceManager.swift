import Foundation
import AVFoundation
import CoreAudio

/// Represents an audio input device
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isDefault: Bool

    static let systemDefault = AudioInputDevice(id: 0, name: "System Default", isDefault: true)
}

/// Manager for audio input devices
/// Handles enumeration and selection of microphone inputs
class AudioDeviceManager: ObservableObject {

    // MARK: - Published Properties

    @Published var availableDevices: [AudioInputDevice] = []
    @Published var selectedDevice: AudioInputDevice = .systemDefault

    // MARK: - Initialization

    init() {
        refreshDevices()
    }

    // MARK: - Device Enumeration

    /// Refresh the list of available audio input devices
    func refreshDevices() {
        var devices: [AudioInputDevice] = [.systemDefault]

        // Get all audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard result == kAudioHardwareNoError else {
            print("AudioDeviceManager: Error getting device list size")
            availableDevices = devices
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)

        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &audioDevices
        )

        guard result == kAudioHardwareNoError else {
            print("AudioDeviceManager: Error getting device list")
            availableDevices = devices
            return
        }

        // Get default input device
        let defaultDeviceID = getDefaultInputDevice()

        // Filter for input devices and get their names
        for deviceID in audioDevices {
            if isInputDevice(deviceID), let name = getDeviceName(deviceID) {
                let isDefault = (deviceID == defaultDeviceID)
                devices.append(AudioInputDevice(id: deviceID, name: name, isDefault: isDefault))
            }
        }

        availableDevices = devices
        print("AudioDeviceManager: Found \(devices.count - 1) input devices")
    }

    // MARK: - Device Selection

    /// Set the selected input device for the app
    /// Note: This doesn't change the system default, it just marks our preference
    func selectDevice(_ device: AudioInputDevice) {
        selectedDevice = device
        print("AudioDeviceManager: Selected device: \(device.name)")
    }

    /// Get the AVAudioEngine input node configuration for the selected device
    func configureAudioEngine(_ audioEngine: AVAudioEngine) throws {
        // If using system default, no need to change anything
        guard selectedDevice.id != 0 else { return }

        // For specific device selection, we need to set the input device
        // This requires stopping and reconfiguring the audio engine
        let inputNode = audioEngine.inputNode

        // Note: AVAudioEngine doesn't directly support device selection in the same way
        // as lower-level Core Audio. For a complete implementation, you'd need to:
        // 1. Create an AudioUnit with the specific device
        // 2. Attach it to the audio engine
        // For now, we'll use the system default and rely on users setting it in System Preferences

        print("AudioDeviceManager: Configured audio engine (device selection via system default)")
    }

    // MARK: - Helper Methods

    private func getDefaultInputDevice() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return result == kAudioHardwareNoError ? deviceID : 0
    }

    private func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let result = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard result == kAudioHardwareNoError else { return false }

        var bufferList = AudioBufferList()
        var bufferListSize = dataSize

        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &bufferListSize,
            &bufferList
        )

        return bufferList.mNumberBuffers > 0
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
        var name: CFString = "" as CFString

        let result = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        return result == kAudioHardwareNoError ? (name as String) : nil
    }
}
