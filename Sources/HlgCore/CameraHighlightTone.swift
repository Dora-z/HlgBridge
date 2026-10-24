import CoreImage

/// Preserve CameraTone's shadows/midtones, replacing its hard white limit with
/// a C1-continuous shoulder. Compress only colors outside the destination gamut.
package enum CameraHighlightTone {
    private static let kernel = CIColorKernel(source: """
        kernel vec4 cameraHighlightTone(__sample s) {
            vec3 wide = max(unpremultiply(s).rgb, vec3(0.0));
            float y = dot(wide, vec3(0.2627, 0.6780, 0.0593));
            float camera = 3.30 * y / (1.0 + 2.10 * y);
            float knee = 0.70;
            float target = camera <= knee ? camera :
                knee + (1.0 - knee) * (1.0 - exp(-(camera - knee) / (1.0 - knee)));
            wide *= y > 0.000001 ? target / y : 3.30;
            vec3 rgb = vec3(
                dot(wide, vec3(1.660491, -0.587641, -0.072850)),
                dot(wide, vec3(-0.124551, 1.132900, -0.008349)),
                dot(wide, vec3(-0.018151, -0.100579, 1.118730)));
            float peak = max(rgb.r, max(rgb.g, rgb.b));
            float low = min(rgb.r, min(rgb.g, rgb.b));
            float chroma = 1.0;
            if (peak > 1.0) {
                chroma = min(chroma, (1.0 - target) / max(peak - target, 0.000001));
            }
            if (low < 0.0) {
                chroma = min(chroma, target / max(target - low, 0.000001));
            }
            rgb = vec3(target) + chroma * (rgb - vec3(target));
            vec3 result = vec3(
                dot(rgb, vec3(0.627404, 0.329282, 0.043314)),
                dot(rgb, vec3(0.069097, 0.919541, 0.011362)),
                dot(rgb, vec3(0.016392, 0.088013, 0.895595)));
            return premultiply(vec4(result, s.a));
        }
        """)
    package static func apply(_ image: CIImage) throws -> CIImage {
        guard let kernel, let output = kernel.apply(extent: image.extent, arguments: [image]) else {
            throw BridgeError("系统无法运行机内高光映射，请切换到其他观感后重试。")
        }
        return output
    }
}
