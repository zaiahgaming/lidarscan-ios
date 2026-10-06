import Foundation
import ARKit
import Darwin

public enum DeviceUtils {
    public static var supportsLiDAR: Bool {
        guard ARWorldTrackingConfiguration.isSupported else { return false }
        return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) &&
               ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    public static var supportsClassification: Bool {
        return ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    public static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "iPhone-LiDAR" : identifier
    }

    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
