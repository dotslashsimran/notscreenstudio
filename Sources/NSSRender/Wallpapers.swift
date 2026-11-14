import Foundation
import NSSCore

/// Built-in procedural wallpapers for `Background.wallpaper(name:)`. Each one is a handful of colour
/// control points blended smoothly in OKLab by the shader (no image assets, no asset catalog).
public enum Wallpapers {
    struct Preset: Sendable {
        var points: [(x: Double, y: Double, color: RGBAColor)]
        var warp: Double
    }

    /// Names accepted by `Background.wallpaper(name:)`. Unknown names fall back to the first one.
    public static let names: [String] = ["aurora", "sunset", "ocean", "forest", "midnight", "peach"]

    static func preset(named name: String) -> Preset {
        switch name.lowercased() {
        case "sunset":
            return Preset(points: [
                (0.1, 0.1, RGBAColor(r: 0.98, g: 0.45, b: 0.35)),
                (0.9, 0.2, RGBAColor(r: 0.99, g: 0.75, b: 0.40)),
                (0.2, 0.9, RGBAColor(r: 0.60, g: 0.20, b: 0.55)),
                (0.85, 0.85, RGBAColor(r: 0.95, g: 0.35, b: 0.50)),
            ], warp: 0.05)
        case "ocean":
            return Preset(points: [
                (0.0, 0.0, RGBAColor(r: 0.05, g: 0.25, b: 0.55)),
                (1.0, 0.1, RGBAColor(r: 0.10, g: 0.60, b: 0.80)),
                (0.3, 1.0, RGBAColor(r: 0.15, g: 0.75, b: 0.70)),
                (0.9, 0.9, RGBAColor(r: 0.05, g: 0.35, b: 0.65)),
            ], warp: 0.04)
        case "forest":
            return Preset(points: [
                (0.1, 0.2, RGBAColor(r: 0.10, g: 0.35, b: 0.25)),
                (0.8, 0.1, RGBAColor(r: 0.45, g: 0.70, b: 0.40)),
                (0.5, 0.9, RGBAColor(r: 0.15, g: 0.50, b: 0.35)),
                (0.95, 0.75, RGBAColor(r: 0.75, g: 0.85, b: 0.50)),
            ], warp: 0.05)
        case "midnight":
            return Preset(points: [
                (0.0, 0.0, RGBAColor(r: 0.05, g: 0.05, b: 0.15)),
                (0.7, 0.3, RGBAColor(r: 0.20, g: 0.15, b: 0.45)),
                (0.2, 0.8, RGBAColor(r: 0.08, g: 0.10, b: 0.30)),
                (1.0, 1.0, RGBAColor(r: 0.35, g: 0.20, b: 0.55)),
            ], warp: 0.03)
        case "peach":
            return Preset(points: [
                (0.1, 0.1, RGBAColor(r: 1.00, g: 0.85, b: 0.75)),
                (0.9, 0.3, RGBAColor(r: 0.98, g: 0.70, b: 0.65)),
                (0.3, 0.9, RGBAColor(r: 0.95, g: 0.80, b: 0.90)),
                (0.95, 0.95, RGBAColor(r: 1.00, g: 0.90, b: 0.70)),
            ], warp: 0.05)
        default:  // "aurora"
            return Preset(points: [
                (0.0, 0.1, RGBAColor(r: 0.20, g: 0.15, b: 0.55)),
                (0.6, 0.0, RGBAColor(r: 0.25, g: 0.70, b: 0.85)),
                (1.0, 0.5, RGBAColor(r: 0.55, g: 0.30, b: 0.85)),
                (0.3, 1.0, RGBAColor(r: 0.20, g: 0.80, b: 0.60)),
                (0.85, 0.95, RGBAColor(r: 0.90, g: 0.45, b: 0.70)),
            ], warp: 0.06)
        }
    }
}

/// sRGB / OKLab helpers used to prepare uniforms on the CPU.
enum ColorMath {
    static func srgbToLinear(_ c: Double) -> Double {
        let v = max(0, min(1, c))
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func linear(_ c: RGBAColor) -> SIMD3<Double> {
        SIMD3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b))
    }

    static func oklab(_ c: RGBAColor) -> SIMD3<Double> {
        let lin = linear(c)
        let l = 0.4122214708 * lin.x + 0.5363325363 * lin.y + 0.0514459929 * lin.z
        let m = 0.2119034982 * lin.x + 0.6806995451 * lin.y + 0.1073969566 * lin.z
        let s = 0.0883024619 * lin.x + 0.2817188376 * lin.y + 0.6299787005 * lin.z
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return SIMD3(
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }
}
