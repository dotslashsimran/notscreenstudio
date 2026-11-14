import Foundation

public struct GradientStop: Codable, Sendable, Equatable {
    public var location: Double
    public var color: RGBAColor
    public init(location: Double, color: RGBAColor) {
        self.location = location
        self.color = color
    }
}

public enum Background: Codable, Sendable, Equatable {
    case solid(RGBAColor)
    /// Linear gradient; `angleDegrees` 0 = left->right, 90 = top->bottom.
    case gradient(stops: [GradientStop], angleDegrees: Double)
    /// Image file inside the project bundle (relative name) or an absolute path.
    case image(file: String)
    /// Built-in wallpaper identified by name (resolved by the renderer/UI).
    case wallpaper(name: String)
}

public struct Shadow: Codable, Sendable, Equatable {
    /// Blur radius as a fraction of output height (0...~0.1).
    public var radius: Double
    public var opacity: Double
    /// Offset as a fraction of output height.
    public var offsetX: Double
    public var offsetY: Double
    public init(radius: Double = 0.03, opacity: Double = 0.4, offsetX: Double = 0, offsetY: Double = 0.012) {
        self.radius = radius
        self.opacity = opacity
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

public enum AspectRatio: String, Codable, Sendable, Equatable, CaseIterable {
    case r16x9, r1x1, r9x16

    /// width / height
    public var ratio: Double {
        switch self {
        case .r16x9: 16.0 / 9.0
        case .r1x1: 1
        case .r9x16: 9.0 / 16.0
        }
    }

    /// Output pixel size; the shorter side equals `resolution.shortSide`.
    /// 16:9 -> 1920x1080 / 3840x2160; 1:1 -> 1080x1080 / 2160x2160; 9:16 -> 1080x1920 / 2160x3840.
    public func outputSize(for resolution: ExportResolution) -> PixelSize {
        let short = resolution.shortSide
        switch self {
        case .r16x9: return PixelSize(width: short * 16 / 9, height: short)
        case .r1x1: return PixelSize(width: short, height: short)
        case .r9x16: return PixelSize(width: short, height: short * 16 / 9)
        }
    }
}

public struct CursorStyle: Codable, Sendable, Equatable {
    /// Multiplier on the default cursor size (1 = native size).
    public var size: Double
    /// 0 = raw cursor, 1 = heavy smoothing.
    public var smoothing: Double
    /// 0 = none, 1 = strong.
    public var motionBlur: Double
    public var clickRipples: Bool
    public var hideWhenIdle: Bool
    public init(size: Double = 1.5, smoothing: Double = 0.5, motionBlur: Double = 0.4, clickRipples: Bool = true, hideWhenIdle: Bool = false) {
        self.size = size
        self.smoothing = smoothing
        self.motionBlur = motionBlur
        self.clickRipples = clickRipples
        self.hideWhenIdle = hideWhenIdle
    }
}

public enum CameraShape: Codable, Sendable, Equatable {
    case circle
    /// `radius` normalized to the bubble's shorter side (0...0.5).
    case roundedRect(radius: Double)
    case squircle
    case rectangle
}

public struct CameraBorder: Codable, Sendable, Equatable {
    /// Width as a fraction of output height.
    public var width: Double
    public var color: RGBAColor
    public init(width: Double = 0.004, color: RGBAColor = .white) {
        self.width = width
        self.color = color
    }
}

public struct CameraBubble: Codable, Sendable, Equatable {
    public var visible: Bool
    public var shape: CameraShape
    /// Center of the bubble in normalized OUTPUT space (0...1, origin top-left).
    public var position: NormalizedPoint
    /// Bubble width as a fraction of output width; height follows the camera aspect (or 1:1 for circle/squircle).
    public var size: Double
    public var border: CameraBorder?
    public var mirror: Bool
    public init(
        visible: Bool = true,
        shape: CameraShape = .circle,
        position: NormalizedPoint = NormalizedPoint(x: 0.88, y: 0.82),
        size: Double = 0.18,
        border: CameraBorder? = CameraBorder(),
        mirror: Bool = true
    ) {
        self.visible = visible
        self.shape = shape
        self.position = position
        self.size = size
        self.border = border
        self.mirror = mirror
    }
}

public struct Style: Codable, Sendable, Equatable {
    public var background: Background
    /// Padding around the screen content as a fraction of output height (0...~0.2).
    public var padding: Double
    /// Corner radius of the screen content as a fraction of output height.
    public var cornerRadius: Double
    public var shadow: Shadow
    public var aspectRatio: AspectRatio
    public var cursor: CursorStyle
    public var camera: CameraBubble

    public init(
        background: Background = .gradient(
            stops: [
                GradientStop(location: 0, color: RGBAColor(r: 0.36, g: 0.30, b: 0.85)),
                GradientStop(location: 1, color: RGBAColor(r: 0.93, g: 0.42, b: 0.55)),
            ],
            angleDegrees: 45
        ),
        padding: Double = 0.06,
        cornerRadius: Double = 0.018,
        shadow: Shadow = Shadow(),
        aspectRatio: AspectRatio = .r16x9,
        cursor: CursorStyle = CursorStyle(),
        camera: CameraBubble = CameraBubble()
    ) {
        self.background = background
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.aspectRatio = aspectRatio
        self.cursor = cursor
        self.camera = camera
    }

    /// A representative flat color for the background (first gradient stop / solid color / mid-gray for images).
    public var backgroundFallbackColor: RGBAColor {
        switch background {
        case .solid(let c): c
        case .gradient(let stops, _): stops.first?.color ?? .black
        case .image, .wallpaper: RGBAColor(r: 0.5, g: 0.5, b: 0.5)
        }
    }
}

// Forward compatibility: fields added after v1 decode with defaults when absent (see PLAN.md).
extension Style {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Style()
        background = try c.decodeIfPresent(Background.self, forKey: .background) ?? d.background
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? d.padding
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        shadow = try c.decodeIfPresent(Shadow.self, forKey: .shadow) ?? d.shadow
        aspectRatio = try c.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio) ?? d.aspectRatio
        cursor = try c.decodeIfPresent(CursorStyle.self, forKey: .cursor) ?? d.cursor
        camera = try c.decodeIfPresent(CameraBubble.self, forKey: .camera) ?? d.camera
    }
}

extension CursorStyle {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CursorStyle()
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? d.smoothing
        motionBlur = try c.decodeIfPresent(Double.self, forKey: .motionBlur) ?? d.motionBlur
        clickRipples = try c.decodeIfPresent(Bool.self, forKey: .clickRipples) ?? d.clickRipples
        hideWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .hideWhenIdle) ?? d.hideWhenIdle
    }
}

extension CameraBubble {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CameraBubble()
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? d.visible
        shape = try c.decodeIfPresent(CameraShape.self, forKey: .shape) ?? d.shape
        position = try c.decodeIfPresent(NormalizedPoint.self, forKey: .position) ?? d.position
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        // v1 field, optional: a missing key means nil (border off), not the default.
        border = try c.decodeIfPresent(CameraBorder.self, forKey: .border)
        mirror = try c.decodeIfPresent(Bool.self, forKey: .mirror) ?? d.mirror
    }
}
