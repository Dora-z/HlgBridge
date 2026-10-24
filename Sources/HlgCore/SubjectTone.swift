import Foundation
import CoreImage

/// A display-oriented SDR rendering, not Panasonic's proprietary MODE2 transform.
/// Evaluate luminance directly instead of using an interpolated 3D LUT, which can
/// introduce colored shadows along the neutral axis.
package enum SubjectTone {
    // The system's source kernel compiler works with Command Line Tools alone;
    // a precompiled Metal kernel would require the full Xcode Metal toolchain.
    private static let kernel = CIColorKernel(source: """
        kernel vec4 subjectTone(__sample s, float power) {
            vec3 rgb = max(unpremultiply(s).rgb, vec3(0.0));
            float y = dot(rgb, vec3(0.2627, 0.6780, 0.0593));
            float target = pow(clamp(y, 0.0, 1.0), power);
            vec3 result = rgb * (target / max(y, 0.000001));
            float peak = max(result.r, max(result.g, result.b));
            if (peak > 1.0) {
                float saturation = (1.0 - target) / max(peak - target, 0.000001);
                result = vec3(target) + saturation * (result - vec3(target));
            }
            return premultiply(vec4(result, s.a));
        }
        """)
    package static func apply(_ image: CIImage, strength: Double) throws -> CIImage {
        let amount = strength.isFinite ? min(1, max(0, strength)) : 0
        guard amount > 0 else { return image }
        guard let kernel,
              let result = kernel.apply(extent: image.extent, arguments: [image, 1 - 0.6 * amount]) else {
            throw BridgeError("系统无法运行主体提亮，请切换到系统映射后重试。")
        }
        return result
    }
}
