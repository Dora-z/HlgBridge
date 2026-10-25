import CoreImage

/// Preserve CameraTone's shadow response, transitioning to a detail-preserving
/// C1-continuous shoulder, retaining RGB ratios in bright colors.
package enum CameraHighlightTone {
    private static let kernel = CIColorKernel(source: """
        kernel vec4 cameraHighlightTone(__sample s) {
            vec3 wide = max(unpremultiply(s).rgb, vec3(0.0));
            float y = dot(wide, vec3(0.2627, 0.6780, 0.0593));
            float camera = 3.30 * y / (1.0 + 2.10 * y);
            // Retain the original shadow gain, then transition early enough to
            // preserve bright fabric/paper contrast, not just avoid pure white.
            float protectedY = 3.30 * y / (1.0 + 3.30 * y);
            float blend = smoothstep(0.10, 0.35, y);
            float mapped = mix(camera, protectedY, blend);
            wide *= y > 0.000001 ? mapped / y : 3.30;
            vec3 rgb = max(vec3(
                dot(wide, vec3(1.660491, -0.587641, -0.072850)),
                dot(wide, vec3(-0.124551, 1.132900, -0.008349)),
                dot(wide, vec3(-0.018151, -0.100579, 1.118730))), vec3(0.0));
            // A shoulder on the destination peak retains RGB ratios instead of
            // pulling bright colors toward white. Start before visible clipping.
            float peak = max(rgb.r, max(rgb.g, rgb.b));
            float knee = 0.90;
            float excess = max(peak - knee, 0.0);
            float target = peak <= knee ? peak : knee + (1.0 - knee) * excess / (excess + 1.0 - knee);
            rgb *= peak > 0.000001 ? target / peak : 1.0;
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
