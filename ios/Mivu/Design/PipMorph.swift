import CoreGraphics

/// Blends one drawing of a part into another. Each head view draws the same named parts, so a turn is every shape
/// flowing from its outline in one view to its outline in the next, not a cut between drawings.
enum PipMorph {
    /// Points per outline: enough to keep an ear tip sharp while it moves, cheap enough to rebuild on a turn.
    static let samples = 96

    /// Both paths redrawn with the same points in matching order, so Core Animation can interpolate between them.
    /// Outlines pair off by size; a drawing's extra small outline sits the turn out.
    static func matched(_ from: CGPath, _ to: CGPath) -> (from: CGPath, to: CGPath)? {
        let sources = contours(of: from).sorted { length($0) > length($1) }
        let targets = contours(of: to).sorted { length($0) > length($1) }
        guard !sources.isEmpty, !targets.isEmpty else { return nil }
        let start = CGMutablePath(), end = CGMutablePath()
        for (source, target) in zip(sources, targets) {
            let points = resampled(source)
            start.addLines(between: points)
            start.closeSubpath()
            end.addLines(between: aligned(resampled(target), to: points))
            end.closeSubpath()
        }
        return (start, end)
    }

    /// The closed outlines of a path, with its curves flattened.
    static func contours(of path: CGPath) -> [[CGPoint]] {
        var contours: [[CGPoint]] = []
        var current: [CGPoint] = []
        func flush() {
            if current.count > 2 { contours.append(current) }
            current = []
        }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                flush()
                current = [points[0]]
            case .addLineToPoint:
                current.append(points[0])
            case .addQuadCurveToPoint:
                guard let a = current.last else { return }
                for step in 1...8 {
                    let t = CGFloat(step) / 8, u = 1 - t
                    current.append(CGPoint(x: u * u * a.x + 2 * u * t * points[0].x + t * t * points[1].x,
                                           y: u * u * a.y + 2 * u * t * points[0].y + t * t * points[1].y))
                }
            case .addCurveToPoint:
                guard let a = current.last else { return }
                for step in 1...10 {
                    let t = CGFloat(step) / 10, u = 1 - t
                    current.append(CGPoint(x: u * u * u * a.x + 3 * u * u * t * points[0].x + 3 * u * t * t * points[1].x + t * t * t * points[2].x,
                                           y: u * u * u * a.y + 3 * u * u * t * points[0].y + 3 * u * t * t * points[1].y + t * t * t * points[2].y))
                }
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        flush()
        return contours
    }

    private static func length(_ contour: [CGPoint]) -> CGFloat {
        zip(contour, contour.dropFirst() + contour.prefix(1)).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// `samples` points evenly spaced round a closed outline.
    private static func resampled(_ contour: [CGPoint]) -> [CGPoint] {
        let loop = contour + [contour[0]]
        let step = length(contour) / CGFloat(samples)
        var points: [CGPoint] = []
        var segment = 0, walked: CGFloat = 0
        for n in 0..<samples {
            let target = step * CGFloat(n)
            while segment < loop.count - 2 {
                let span = hypot(loop[segment + 1].x - loop[segment].x, loop[segment + 1].y - loop[segment].y)
                guard walked + span < target else { break }
                walked += span
                segment += 1
            }
            let a = loop[segment], b = loop[segment + 1]
            let span = max(hypot(b.x - a.x, b.y - a.y), 0.0001), t = min(1, max(0, (target - walked) / span))
            points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return points
    }

    private static func area(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst() + points.prefix(1)).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }
    }

    private static func centre(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Winds `target` the same way as `source` and starts it at the point that moves the outline least, measured with
    /// both centred so a part that travels across the head still lines up.
    private static func aligned(_ target: [CGPoint], to source: [CGPoint]) -> [CGPoint] {
        let points = area(target) * area(source) < 0 ? target.reversed() : target
        let a = centre(source), b = centre(points)
        func cost(_ shift: Int) -> CGFloat {
            source.indices.reduce(0) { total, i in
                let p = points[(i + shift) % points.count]
                let dx = source[i].x - a.x - p.x + b.x, dy = source[i].y - a.y - p.y + b.y
                return total + dx * dx + dy * dy
            }
        }
        // Every third start is close enough at this density, and turns the search from thousands of sums to hundreds.
        let best = stride(from: 0, to: points.count, by: 3).min { cost($0) < cost($1) } ?? 0
        return points.indices.map { points[($0 + best) % points.count] }
    }
}
