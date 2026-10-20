import UIKit

/// Layout B: a one-page summary for a clinician, then every saved meal grouped by day.
extension DiaryReport {
    func pdfData() -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842), margin: CGFloat = 40, width = page.width - 2 * margin
        // Print colors stay light-mode regardless of the device appearance.
        func color(_ hex: Int) -> UIColor { UIColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
        let ink = color(0x142023), secondary = color(0x53646B), accent = color(0x006D75), over = color(0xB33143), rule = color(0xD5DFE1), tile = color(0xEAF5F3)
        func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont { .systemFont(ofSize: size, weight: weight) }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Mivu food log", kCGPDFContextCreator as String: "Mivu"]
        // Footers say "Page n of N", so a first pass counts the pages.
        var pages = 0
        func render(_ total: Int) -> Data { pages = 0; return UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { context in
            var y = margin
            func draw(_ text: String, _ font: UIFont, _ color: UIColor, in rect: CGRect, align: NSTextAlignment = .left) {
                let style = NSMutableParagraphStyle(); style.alignment = align; style.lineBreakMode = .byTruncatingTail
                (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
            }
            func newPage() {
                context.beginPage(); pages += 1; y = margin
                rule.setFill(); UIRectFill(CGRect(x: margin, y: page.height - 28, width: width, height: 0.5))
                draw("Made with Mivu · values are logged estimates", font(8), secondary, in: CGRect(x: margin, y: page.height - 24, width: width / 2, height: 12))
                draw("Page \(pages) of \(total)", font(8), secondary, in: CGRect(x: margin + width / 2, y: page.height - 24, width: width / 2, height: 12), align: .right)
            }
            func ensure(_ height: CGFloat) { if y + height > page.height - margin { newPage() } }
            func line() { rule.setFill(); UIRectFill(CGRect(x: margin, y: y - 3, width: width, height: 0.5)) }
            /// Columns after the first are right-aligned numbers of equal width.
            func row(_ cells: [String], first: CGFloat, colors: [Int: UIColor] = [:], header: Bool = false) {
                ensure(16)
                let rest = (width - first) / CGFloat(cells.count - 1)
                for (index, cell) in cells.enumerated() {
                    let x = index == 0 ? margin : margin + first + rest * CGFloat(index - 1)
                    draw(cell, header ? font(8.5, .semibold) : font(9.5), colors[index] ?? (header ? secondary : ink),
                         in: CGRect(x: x, y: y, width: index == 0 ? first - 6 : rest, height: 14), align: index == 0 ? .left : .right)
                }
                y += 16; line()
            }

            // Summary page
            newPage()
            let band = CGRect(x: 0, y: 0, width: page.width, height: 112), white = UIColor.white
            accent.setFill(); UIRectFill(band)
            draw("MIVU", font(9, .heavy), white.withAlphaComponent(0.85), in: CGRect(x: margin, y: 30, width: width - 120, height: 12))
            draw("Food log", font(22, .bold), white, in: CGRect(x: margin, y: 44, width: width - 120, height: 28))
            draw("\(profileName) · \(rangeTitle) · prepared for your clinician", font(10), white.withAlphaComponent(0.85), in: CGRect(x: margin, y: 76, width: width - 120, height: 14))
            if let pip = UIImage(named: "PipCoach") {
                // Pip's portrait is cropped at the chest, so it sits on the band's edge and peeks up from behind it.
                context.cgContext.saveGState(); UIRectClip(band)
                pip.draw(in: CGRect(x: page.width - margin - 104, y: band.maxY - 104, width: 104, height: 104))
                context.cgContext.restoreGState()
            }
            y = band.maxY + 24

            let tileWidth = (width - 18) / 4
            for (index, tileText) in summaryTiles.enumerated() {
                let rect = CGRect(x: margin + CGFloat(index) * (tileWidth + 6), y: y, width: tileWidth, height: 58)
                tile.setFill(); UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
                let inner = rect.insetBy(dx: 8, dy: 7)
                draw(tileText.title, font(8.5, .semibold), secondary, in: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 12))
                draw(tileText.value, font(15, .bold), ink, in: CGRect(x: inner.minX, y: inner.minY + 13, width: inner.width, height: 20))
                draw(tileText.detail, font(8.5), secondary, in: CGRect(x: inner.minX, y: inner.minY + 33, width: inner.width, height: 12))
            }
            y += 70

            let trend = weights.filter { $0.entry.unit == weights.first?.entry.unit }
            if trend.count > 1, let low = trend.map(\.entry.value).min(), let high = trend.map(\.entry.value).max() {
                draw("Weight trend (\(trend[0].entry.unit))", font(8.5, .semibold), secondary, in: CGRect(x: margin, y: y, width: width, height: 12)); y += 14
                let chart = CGRect(x: margin, y: y, width: width, height: 56)
                tile.setFill(); UIBezierPath(roundedRect: chart, cornerRadius: 8).fill()
                let plot = chart.insetBy(dx: 10, dy: 8), start = trend[0].entry.measuredAt, span = max(trend.last!.entry.measuredAt.timeIntervalSince(start), 1)
                let path = UIBezierPath()
                for (index, weight) in trend.enumerated() {
                    let point = CGPoint(x: plot.minX + plot.width * weight.entry.measuredAt.timeIntervalSince(start) / span,
                                        y: plot.maxY - plot.height * (high == low ? 0.5 : (weight.entry.value - low) / (high - low)))
                    index == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                accent.setStroke(); path.lineWidth = 1.5; path.lineJoinStyle = .round; path.stroke()
                y += 68
            }

            draw("Daily totals", font(12, .semibold), ink, in: CGRect(x: margin, y: y, width: width, height: 16)); y += 20
            row(["Day", "kcal", "Target", "Protein g", "Carbs g", "Fat g", "Weight"], first: 120, header: true)
            for day in days {
                let isOver = (day.totals.kcal ?? 0) > (day.target?.kcal ?? .infinity)
                row([Self.dayTitle(day.localDate), whole(day.totals.kcal), whole(day.target?.kcal), whole(day.totals.protein), whole(day.totals.carbs), whole(day.totals.fat),
                     day.weight.map { "\(number($0.value)) \($0.unit)" } ?? "—"], first: 120, colors: isOver ? [1: over] : [:])
            }
            y += 8
            draw("Red calories are above that day’s target. “—” means unknown.", font(8), secondary,
                 in: CGRect(x: margin, y: y, width: width, height: 12))

            // Meal pages
            newPage()
            draw("Meals", font(16, .bold), ink, in: CGRect(x: margin, y: y, width: width, height: 22)); y += 28
            for day in days where !day.meals.isEmpty {
                ensure(40); y += 6
                draw(Self.dayTitle(day.localDate), font(11, .semibold), ink, in: CGRect(x: margin, y: y, width: width / 2, height: 15))
                draw("\(whole(day.totals.kcal)) kcal", font(10, .semibold), (day.totals.kcal ?? 0) > (day.target?.kcal ?? .infinity) ? over : accent,
                     in: CGRect(x: margin + width / 2, y: y, width: width / 2, height: 15), align: .right)
                y += 20
                row(["Meal", "kcal", "Protein g", "Carbs g", "Fat g"], first: 275, header: true)
                for meal in day.meals {
                    row([[meal.time, meal.name].filter { !$0.isEmpty }.joined(separator: "  "), whole(meal.totals.kcal), whole(meal.totals.protein),
                         whole(meal.totals.carbs), whole(meal.totals.fat)], first: 275)
                }
            }
            if days.allSatisfy(\.meals.isEmpty) { draw("No saved meals in this range.", font(10), secondary, in: CGRect(x: margin, y: y, width: width, height: 14)) }
        } }
        _ = render(0)
        return render(pages)
    }

    private var summaryTiles: [(title: String, value: String, detail: String)] {
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let logged = days.filter { !$0.meals.isEmpty }, target = days.last?.target
        let first = weights.first?.entry, last = weights.last?.entry
        let change: String = if let first, let last, weights.count > 1, first.unit == last.unit {
            "\(last.value < first.value ? "−" : "+")\(number(abs(last.value - first.value))) \(last.unit)"
        } else { "—" }
        return [
            ("Avg calories", whole(average(logged.compactMap(\.totals.kcal))), target?.kcal.map { "target \(whole($0))" } ?? "no target"),
            ("Avg protein", average(logged.compactMap(\.totals.protein)).map { "\(whole($0)) g" } ?? "—", target?.protein.map { "target \(whole($0)) g" } ?? "no target"),
            ("Days logged", "\(logged.count) / \(days.count)", "days with saved meals"),
            ("Weight change", change, first.map { first in last.map { "\(number(first.value)) → \(number($0.value))" } ?? "" } ?? "no weigh-ins"),
        ]
    }
    private var rangeTitle: String {
        guard let first = days.first?.localDate, let last = days.last?.localDate else { return "No days in range" }
        return first == last ? Self.dayTitle(first) : "\(Self.dayTitle(first)) – \(Self.dayTitle(last))"
    }
    private func whole(_ value: Double?) -> String { value.map { Int($0.rounded()).formatted() } ?? "—" }
    private static func dayTitle(_ localDate: String) -> String {
        guard let date = try? Date(localDate + "T00:00:00Z", strategy: .iso8601) else { return localDate }
        return date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).weekday(.abbreviated).month(.abbreviated).day().year())
    }
}
