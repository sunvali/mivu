import CoreGraphics
import Foundation

/// Decoded `pip-rig.json`: Pip's layered vector parts (see design-system/mivu/characters/pip/rig/README.md).
struct PipRigAsset: Decodable {
    enum Error: Swift.Error, Equatable {
        case tooLarge, version, missingPart(String), badPath(String)
    }

    struct Part: Decodable {
        let id: String
        let parent: String?
        let pivot: [CGFloat]
        let z: Int
        let set: String?
        let view: String?
        let shape: String?
        let visible: Bool
        let parallax: CGFloat?
        let fill: String
        let fillDark: String?
        let path: String
        /// On a set's `body`: where the head views sit on it, `[k, tx, ty]` meaning head point × k + t.
        let mount: [CGFloat]?

        /// The id without its `@view` suffix; poses address parts by this name.
        var name: String { String(id.prefix { $0 != "@" }) }
    }

    static let maxBytes = 1_048_576
    private static let requiredPerView = ["head", "eye-l.open", "eye-r.open", "mouth.closedSmile"]

    let version: Int
    let artboard: CGFloat
    let ground: CGFloat
    let parallaxScale: CGFloat
    let frames: [String: CGRect]
    let parts: [Part]

    private enum Key: String, CodingKey { case version, artboard, ground, parallaxScale, frames, parts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        version = try c.decode(Int.self, forKey: .version)
        artboard = try c.decode(CGFloat.self, forKey: .artboard)
        ground = try c.decode(CGFloat.self, forKey: .ground)
        parallaxScale = try c.decodeIfPresent(CGFloat.self, forKey: .parallaxScale) ?? 0
        parts = try c.decode([Part].self, forKey: .parts)
        let raw = try c.decode([String: [CGFloat]].self, forKey: .frames)
        guard raw.values.allSatisfy({ $0.count == 4 }) else {
            throw DecodingError.dataCorruptedError(forKey: .frames, in: c, debugDescription: "frame needs x y w h")
        }
        frames = raw.mapValues { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
    }

    static func load(_ data: Data) throws -> PipRigAsset {
        guard data.count <= maxBytes else { throw Error.tooLarge }
        let asset = try JSONDecoder().decode(PipRigAsset.self, from: data)
        guard asset.version == 2 else { throw Error.version }
        for part in asset.parts { _ = try cgPath(part.path) }
        let ids = Set(asset.parts.map(\.id))
        for view in ["right", "front", "left"] {
            for name in requiredPerView where !ids.contains("\(name)@\(view)") {
                throw Error.missingPart("\(name)@\(view)")
            }
        }
        return asset
    }

    /// Parses absolute `M L C Q Z` commands, the only ones the rig build emits.
    static func cgPath(_ svg: String) throws -> CGPath {
        let path = CGMutablePath()
        let scanner = Scanner(string: svg)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: ", \n\t")
        var command: Character?
        func numbers(_ count: Int) throws -> [CGFloat] {
            try (0..<count).map { _ in
                guard let value = scanner.scanDouble() else { throw Error.badPath(svg) }
                return CGFloat(value)
            }
        }
        while !scanner.isAtEnd {
            if let letter = scanner.scanCharacter(), letter.isLetter { command = letter } else { throw Error.badPath(svg) }
            switch command {
            case "M": let p = try numbers(2); path.move(to: CGPoint(x: p[0], y: p[1]))
            case "L": let p = try numbers(2); path.addLine(to: CGPoint(x: p[0], y: p[1]))
            case "C":
                let p = try numbers(6)
                path.addCurve(to: CGPoint(x: p[4], y: p[5]), control1: CGPoint(x: p[0], y: p[1]), control2: CGPoint(x: p[2], y: p[3]))
            case "Q":
                let p = try numbers(4)
                path.addQuadCurve(to: CGPoint(x: p[2], y: p[3]), control: CGPoint(x: p[0], y: p[1]))
            case "Z": path.closeSubpath()
            default: throw Error.badPath(svg)
            }
        }
        return path
    }
}
