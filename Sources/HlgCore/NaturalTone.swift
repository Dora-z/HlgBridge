import CoreImage

/// A conservative, scene-independent SDR shoulder. No hard white clipping.
package enum NaturalTone {
    private static let kernel = CIColorKernel(source: """
        kernel vec4 naturalTone(__sample s) {
            vec3 wide = max(unpremultiply(s).rgb, vec3(0.0));
            // Work in the destination gamut so a bright colored channel cannot
            // silently clip during the subsequent sRGB color-space conversion.
            vec3 rgb = max(vec3(
                dot(wide, vec3(1.660491, -0.587641, -0.072850)),
                dot(wide, vec3(-0.124551, 1.132900, -0.008349)),
                dot(wide, vec3(-0.018151, -0.100579, 1.118730))), vec3(0.0));
            float y = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
            float target = (2.0 * y) / (1.0 + 2.0 * y);
            rgb *= y > 0.000001 ? target / y : 2.0;
            float peak = max(rgb.r, max(rgb.g, rgb.b));
            if (peak > 1.0) {
                float chroma = (1.0 - target) / max(peak - target, 0.000001);
                rgb = vec3(target) + chroma * (rgb - vec3(target));
            }
            vec3 result = vec3(
                dot(rgb, vec3(0.627404, 0.329282, 0.043314)),
                dot(rgb, vec3(0.069097, 0.919541, 0.011362)),
                dot(rgb, vec3(0.016392, 0.088013, 0.895595)));
            return premultiply(vec4(result, s.a));
        }
        """)
    package static func apply(_ image: CIImage) throws -> CIImage {
        guard let kernel, let output = kernel.apply(extent: image.extent, arguments: [image]) else {
            throw BridgeError("系统无法运行自然映射，请切换到系统映射后重试。")
        }
        return output
    }
}
