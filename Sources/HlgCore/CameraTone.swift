import Foundation
import CoreImage

/// Empirical DC-L10 rendering from one aligned HLG / in-camera JPEG pair.
/// Two global luminance coefficients; no per-scene statistics or fitted color matrix.
/// Input and output are extended-linear BT.2020, SDR reference white = 1.
package enum CameraTone {
    private static let kernel = CIColorKernel(source: """
        kernel vec4 cameraTone(__sample s) {
            vec3 rgb = max(unpremultiply(s).rgb, vec3(0.0));
            float y = dot(rgb, vec3(0.2627, 0.6780, 0.0593));
            // Raise midtones while rolling off HLG highlights.
            float target = min(3.30 * y / (1.0 + 2.10 * y), 1.0);
            float gain = y > 0.000001 ? target / y : 3.30;
            return premultiply(vec4(rgb * gain, s.a));
        }
        """)
    package static func apply(_ image: CIImage) throws -> CIImage {
        guard let kernel, let output = kernel.apply(extent: image.extent, arguments: [image]) else {
            throw BridgeError("系统无法运行机内近似映射，请切换到系统映射后重试。")
        }
        return output
    }
}
