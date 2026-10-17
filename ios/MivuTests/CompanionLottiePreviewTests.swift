import Lottie
import UIKit
import XCTest
@testable import Mivu

@MainActor final class CompanionLottiePreviewTests: XCTestCase {
    func testApprovedIllustrationRendersAndGreetingRepeatsOnCoreAnimation() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "pip", withExtension: "json", subdirectory: "Characters/pip"))
        let animation = try LottieAnimation.from(data: Data(contentsOf: url))
        let player = LottieAnimationView(animation: animation,
            imageProvider: try CompanionArtworkImageProvider(artworkURL: url.deletingLastPathComponent().appendingPathComponent("pip-artwork.png"),
                matteURL: url.deletingLastPathComponent().appendingPathComponent("pip-artwork-alpha.png")),
            configuration: LottieConfiguration(renderingEngine: .specific(.coreAnimation)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        let controller = UIViewController()
        window.rootViewController = controller
        player.frame = window.bounds
        controller.view.addSubview(player)
        window.isHidden = false
        defer { player.stop(); window.isHidden = true }
        player.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(player.currentRenderingEngine, .coreAnimation)

        for dark in [false, true] {
            player.backgroundColor = dark ? UIColor(red: 0.055, green: 0.075, blue: 0.08, alpha: 1) : .white
            for name in ["resting", "attentive", "thinking", "saved", "reviewed", "recovery", "greeting", "coach-resting", "coach-blink"] {
                let start = try XCTUnwrap(animation.frameTime(forMarker: name))
                let duration = try XCTUnwrap(animation.durationFrameTime(forMarker: name))
                player.currentFrame = start + duration / 2
                try await Task.sleep(for: .milliseconds(50))
                let image = snapshot(player)
                XCTAssertGreaterThan(orangePixelCount(image), 200, "Missing original artwork for \(name)")
                let attachment = XCTAttachment(image: image)
                attachment.name = "Pip Lottie \(name) \(dark ? "dark" : "light")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        let blink = try XCTUnwrap(animation.frameTime(forMarker: "blink"))
        player.currentFrame = blink
        try await Task.sleep(for: .milliseconds(40))
        let openEyes = snapshot(player).cgImage?.cropping(to: CGRect(x: 350, y: 175, width: 180, height: 100))
        player.currentFrame = blink + 8
        try await Task.sleep(for: .milliseconds(40))
        let closedEyes = snapshot(player)
        XCTAssertNotEqual(openEyes.flatMap { UIImage(cgImage: $0).pngData() },
            closedEyes.cgImage?.cropping(to: CGRect(x: 350, y: 175, width: 180, height: 100)).flatMap { UIImage(cgImage: $0).pngData() },
            "The actual blink must close Pip's eyes, not just advance a named timeline")
        let blinkAttachment = XCTAttachment(image: closedEyes)
        blinkAttachment.name = "Pip Lottie blink closed dark"
        blinkAttachment.lifetime = .keepAlways
        add(blinkAttachment)

        for iteration in 1...2 {
            player.currentFrame = try XCTUnwrap(animation.frameTime(forMarker: "greeting"))
            try await Task.sleep(for: .milliseconds(40))
            let firstImage = presentationSnapshot(player)
            let first = firstImage.pngData()
            var finished = false
            let began = Date()
            player.play(marker: "greeting", loopMode: .playOnce) { finished = $0 }
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(player.isAnimationPlaying)
            let movingImage = presentationSnapshot(player)
            XCTAssertGreaterThan(player.realtimeAnimationFrame,
                                 try XCTUnwrap(animation.frameTime(forMarker: "greeting")) + 6)
            for (label, image) in [("first", firstImage), ("250ms", movingImage)] {
                let attachment = XCTAttachment(image: image)
                attachment.name = "Greeting \(iteration) \(label)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertNotEqual(movingImage.pngData(), first, "Greeting \(iteration) must visibly advance")
            while !finished && Date().timeIntervalSince(began) < 2.2 {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(finished, "Greeting \(iteration) must complete without a host timer")
            XCTAssertFalse(player.isAnimationPlaying)
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(began), MivuMotion.greeting - 0.05)
        }
    }

    func testBodyMotionIsReadableAtPhoneSizeAndSubmitStartsPromptly() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let player = try XCTUnwrap(runtime.player)
        let animation = try XCTUnwrap(player.animation)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 148, height: 148)
        window.rootViewController = UIViewController()
        player.frame = window.bounds
        window.rootViewController?.view.addSubview(player)
        window.isHidden = false
        defer { runtime.stop(); window.isHidden = true }
        player.layoutIfNeeded()

        for prefix in ["", "coach-"] {
            player.backgroundColor = .white
            let resting = try XCTUnwrap(animation.frameTime(forMarker: prefix + "resting"))
            player.currentFrame = resting
            try await Task.sleep(for: .milliseconds(60))
            let neutral = snapshot(player)
            player.currentFrame = resting + 120
            try await Task.sleep(for: .milliseconds(60))
            let inhale = snapshot(player)
            // Below the eyes: a blink alone cannot satisfy body-motion acceptance.
            let body = prefix.isEmpty ? CGRect(x: 20, y: 82, width: 108, height: 48)
                : CGRect(x: 20, y: 78, width: 108, height: 29)
            XCTAssertGreaterThan(changedPaintPixels(neutral, inhale, in: body), 30,
                                 "Breathing must be readable below the eyes at the actual 148-point canvas")
            for (label, image) in [("neutral", neutral), ("inhale", inhale)] {
                let attachment = XCTAttachment(image: image)
                attachment.name = "Pip phone-size \(prefix)\(label)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }

            let submitted = try XCTUnwrap(animation.frameTime(forMarker: prefix + "submitted"))
            XCTAssertEqual(try XCTUnwrap(animation.durationFrameTime(forMarker: prefix + "submitted")), 48)
            var first: UIImage?
            for frame in [0, 3, 6, 12, 24, 36, 48] {
                player.currentFrame = submitted + Double(frame)
                try await Task.sleep(for: .milliseconds(50))
                let image = snapshot(player)
                if frame == 0 { first = image }
                if frame == 6 {
                    XCTAssertGreaterThan(changedPaintPixels(try XCTUnwrap(first), image, in: body), 25,
                                         "Submit must visibly move the body by 100 ms, even without eye motion")
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Pip phone-size \(prefix)submit \(frame) frames"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func changedPaintPixels(_ first: UIImage, _ second: UIImage, in region: CGRect) -> Int {
        let width = 296, height = 296
        func rgba(_ image: UIImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { memory in
                let context = CGContext(data: memory.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return bytes
        }
        let before = rgba(first), after = rgba(second)
        var changed = 0
        for y in Int(region.minY * 2)..<Int(region.maxY * 2) {
            for x in Int(region.minX * 2)..<Int(region.maxX * 2) {
                let index = (y * width + x) * 4
                let painted = Int(before[index]) - Int(before[index + 2]) > 30
                    || Int(after[index]) - Int(after[index + 2]) > 30
                if painted && (0..<3).contains(where: { abs(Int(before[index + $0]) - Int(after[index + $0])) > 20 }) {
                    changed += 1
                }
            }
        }
        return changed
    }

    func testRestAndQuietTypingKeepMovingWithoutRestartingAndStopWhenHidden() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let player = try XCTUnwrap(runtime.player)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 240, height: 240)
        window.rootViewController = UIViewController()
        player.frame = window.bounds
        window.rootViewController?.view.addSubview(player)
        window.isHidden = false
        defer { runtime.stop(); window.isHidden = true }
        player.layoutIfNeeded()
        for surface in [CompanionSurface.today, .coach] {
            for pose in [CompanionPose.resting, .attentive] {
                let output = CompanionOutput(pose: pose, playback: .animated, reactionID: nil, nextDeadline: nil)
                await runtime.apply(output, darkMode: false, surface: surface)
                try await Task.sleep(for: .milliseconds(450))
                XCTAssertTrue(player.isAnimationPlaying, "Eligible idle and quiet typing must stay alive")
                let before = player.realtimeAnimationFrame
                let image = presentationSnapshot(player).pngData()
                await runtime.apply(output, darkMode: true, surface: surface)
                try await Task.sleep(for: .milliseconds(650))
                XCTAssertGreaterThan(player.realtimeAnimationFrame, before, "Appearance updates must not restart the living loop")
                XCTAssertNotEqual(presentationSnapshot(player).pngData(), image, "Breathing must move painted parts, not only the timeline")
                XCTAssertEqual(runtime.displayedPose, pose)
            }
        }
        await runtime.apply(CompanionOutput(pose: .resting, playback: .animated, reactionID: nil, nextDeadline: nil), darkMode: true, surface: .coach)
        try await Task.sleep(for: .seconds(8.4))
        XCTAssertTrue(player.isAnimationPlaying, "Living idle must continue beyond a complete eight-second cycle")
        let loopFrame = player.realtimeAnimationFrame
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertGreaterThan(player.realtimeAnimationFrame, loopFrame)
        await runtime.attach(eligible: false)
        let stopped = player.realtimeAnimationFrame
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(player.isAnimationPlaying)
        XCTAssertEqual(player.realtimeAnimationFrame, stopped)
    }

    func testCoachTransitionsNeverExposeUnrelatedAtlasPoses() async throws {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let player = try XCTUnwrap(runtime.player)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        window.rootViewController = UIViewController()
        player.frame = window.bounds
        player.backgroundColor = .black
        window.rootViewController?.view.addSubview(player)
        window.isHidden = false
        defer { runtime.stop(); window.isHidden = true }
        player.layoutIfNeeded()
        let mask = pixels(try XCTUnwrap(UIImage(named: "PipCoach")))
        for pose in [CompanionPose.greeting, .resting, .attentive, .resting, .saved, .resting] {
            let output = CompanionOutput(pose: pose, playback: .animated,
                reactionID: [.greeting, .saved].contains(pose) ? UUID() : nil, nextDeadline: nil)
            await runtime.apply(output, darkMode: true, surface: .coach)
            for _ in 0..<4 {
                try await Task.sleep(for: .milliseconds(65))
                let image = snapshot(player)
                let actual = pixels(image)
                var leaked = 0
                for y in 0..<128 { for x in 0..<128 {
                    let p = (y * 128 + x) * 4
                    guard Int(actual[p]) - Int(actual[p + 2]) > 35 else { continue }
                    let covered = (max(0,y-3)...min(127,y+3)).contains { yy in
                        (max(0,x-3)...min(127,x+3)).contains { xx in mask[(yy*128+xx)*4+3] > 20 }
                    }
                    if !covered { leaked += 1 }
                }}
                if leaked > 12 {
                    let attachment = XCTAttachment(image: image); attachment.name = "Unrelated pose leaked during Coach transition"
                    attachment.lifetime = .keepAlways; add(attachment)
                }
                XCTAssertLessThanOrEqual(leaked, 12, "A view transition must not reveal other paintings from the source atlas")
            }
        }
    }

    func testCoachFoodEntryBodyGesturesAtCompactAndFullSizes() async throws {
        let (runtime, player, window) = try await mountedTodayRuntime()
        defer { runtime.stop(); window.isHidden = true }
        let animation = try XCTUnwrap(player.animation)
        for size in [88.0, 148.0] {
            window.frame = CGRect(x: 0, y: 0, width: size, height: size)
            player.frame = window.bounds
            player.layoutIfNeeded()
            for dark in [false, true] {
                player.backgroundColor = dark ? UIColor(red: 0.055, green: 0.075, blue: 0.08, alpha: 1) : .white
                for name in ["submitted", "saved", "reviewed"] {
                    let marker = "coach-" + name
                    let start = try XCTUnwrap(animation.frameTime(forMarker: marker))
                    let duration = try XCTUnwrap(animation.durationFrameTime(forMarker: marker))
                    var first: UIImage?
                    var maximumBodyChange = 0
                    for offset in [0.0, 3, 6, 12, 18, 24, 36, duration] {
                        player.currentFrame = start + offset
                        await PipDisplayFrameSampler.waitForFrames(2)
                        let image = presentationSnapshot(player)
                        XCTAssertGreaterThan(orangePixelCount(image), 200, "The original painting must remain present")
                        if let first {
                            maximumBodyChange = max(maximumBodyChange, changedPaintPixels(first, image,
                                in: CGRect(x: 20, y: 78, width: 108, height: 29)))
                        } else { first = image }
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "Coach acting \(Int(size))pt \(dark ? "dark" : "light") \(name) frame \(Int(offset))"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                    XCTAssertGreaterThan(maximumBodyChange, 30,
                        "\(marker) at \(size)pt must visibly move the painted body below the eyes")
                }
            }
        }
    }

    func testTodayGreetingCompletionAndNearbyDeadlinesNeverFlashAnotherPainting() async throws {
        let (reference, referencePlayer, referenceWindow) = try await mountedTodayRuntime()
        defer { reference.stop(); referenceWindow.isHidden = true }
        let allowed = try await allowedTodayPaint(in: referencePlayer, markers: ["greeting", "resting"])
        try await assertMaskRejectsAnotherPainting(allowed, in: referencePlayer)

        for deadlineOffset in [Optional<Double>.none, -0.08, 0.08] {
            let (runtime, player, window) = try await mountedTodayRuntime()
            defer { runtime.stop(); window.isHidden = true }
            let duration = try markerDuration("greeting", in: player)
            await runtime.apply(CompanionOutput(pose: .greeting, playback: .animated,
                reactionID: UUID(), nextDeadline: nil), darkMode: false, surface: .today)
            let deadline = deadlineOffset.map { offset in
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(duration + offset))
                    guard !Task.isCancelled else { return }
                    await runtime.apply(CompanionOutput(pose: .resting, playback: .animated,
                        reactionID: nil, nextDeadline: nil), darkMode: false, surface: .today)
                }
            }
            defer { deadline?.cancel() }
            let frames = await PipDisplayFrameSampler.capture(player: player, runtime: runtime,
                duration: duration + MivuMotion.companionTransition + 0.25)
            let label = deadlineOffset.map { "deadline \($0)s from completion" } ?? "automatic completion"
            assertAllowedPaint(frames, mask: allowed, label: label)
            XCTAssertEqual(runtime.displayedPose, .resting, label)
            XCTAssertTrue(player.isAnimationPlaying, "\(label): the settled pose must remain alive")
        }
    }

    func testTodayIdleLoopBoundaryNeverFlashesAnotherPainting() async throws {
        let (runtime, player, window) = try await mountedTodayRuntime()
        defer { runtime.stop(); window.isHidden = true }
        let allowed = try await allowedTodayPaint(in: player, markers: ["resting"])
        try await assertMaskRejectsAnotherPainting(allowed, in: player)
        // Start at the actual clip's beginning, rather than seeking past the suspected boundary.
        player.currentFrame = try XCTUnwrap(player.animation?.frameTime(forMarker: "resting"))
        await PipDisplayFrameSampler.waitForFrames(2)
        let duration = try markerDuration("resting", in: player)
        await runtime.apply(CompanionOutput(pose: .resting, playback: .animated,
            reactionID: nil, nextDeadline: nil), darkMode: false, surface: .today)
        // Record the whole untouched first cycle: its built-in blink at 5 seconds matters too.
        let frames = await PipDisplayFrameSampler.capture(player: player, runtime: runtime, duration: duration + 0.4)
        assertAllowedPaint(frames, mask: allowed, label: "Today untouched breathing and loop boundary")
        XCTAssertTrue(frames.contains { (300...318).contains($0.animationFrame) }, "Record the embedded blink")
        XCTAssertTrue(frames.contains { $0.animationFrame > 450 }, "Record the end of the eight-second loop")
        XCTAssertTrue(frames.contains { $0.elapsed > duration && $0.animationFrame < 40 }, "Record the beginning of its next iteration")
    }

    private func mountedTodayRuntime() async throws -> (CompanionRuntime, LottieAnimationView, UIWindow) {
        let runtime = CompanionRuntime()
        await runtime.select(CharacterCatalog.bundled.resolve("pip"))
        await runtime.attach(eligible: true)
        let player = try XCTUnwrap(runtime.player)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        window.rootViewController = UIViewController()
        player.frame = window.bounds
        player.backgroundColor = .black
        window.rootViewController?.view.addSubview(player)
        window.isHidden = false
        player.layoutIfNeeded()
        await PipDisplayFrameSampler.waitForFrames(2)
        return (runtime, player, window)
    }

    private func markerDuration(_ marker: String, in player: LottieAnimationView) throws -> Double {
        let animation = try XCTUnwrap(player.animation)
        return try XCTUnwrap(animation.durationFrameTime(forMarker: marker)) / animation.framerate
    }

    private func allowedTodayPaint(in player: LottieAnimationView, markers: [String]) async throws -> [Bool] {
        var mask = [Bool](repeating: false, count: 64 * 64)
        let animation = try XCTUnwrap(player.animation)
        for marker in markers {
            let start = try XCTUnwrap(animation.frameTime(forMarker: marker))
            let duration = try XCTUnwrap(animation.durationFrameTime(forMarker: marker))
            // Dense native reference samples cover the real motion, including the last valid frame.
            // A single pixel of tolerance at 64px accommodates antialiasing between reference samples.
            let step = marker == "resting" ? 12.0 : 3.0
            for offset in stride(from: 0.0, through: duration, by: step) {
                player.currentFrame = start + offset
                await PipDisplayFrameSampler.waitForFrames(2)
                let pixels = PipDisplayFrameSampler.paintedPixels(in: PipDisplayFrameSampler.image(of: player))
                for index in pixels.indices where pixels[index] {
                    let x = index % 64, y = index / 64
                    for yy in max(0, y - 1)...min(63, y + 1) {
                        for xx in max(0, x - 1)...min(63, x + 1) { mask[yy * 64 + xx] = true }
                    }
                }
            }
        }
        XCTAssertGreaterThan(mask.filter { $0 }.count, 200, "Reference masks must contain the painted character")
        return mask
    }

    private func assertMaskRejectsAnotherPainting(_ mask: [Bool], in player: LottieAnimationView) async throws {
        player.currentFrame = try XCTUnwrap(player.animation?.frameTime(forMarker: "coach-resting"))
        await PipDisplayFrameSampler.waitForFrames(2)
        let image = PipDisplayFrameSampler.image(of: player)
        let pixels = PipDisplayFrameSampler.paintedPixels(in: image)
        let outside = pixels.indices.filter { pixels[$0] && !mask[$0] }.count
        if outside <= 20 {
            let attachment = XCTAttachment(image: image)
            attachment.name = "Mask positive control: unrelated seated painting"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertGreaterThan(outside, 20, "The allowed union must reject an unrelated seated painting; an overbroad mask cannot validate a flash")
    }

    private func assertAllowedPaint(_ frames: [PipPaintFrame], mask: [Bool], label: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(frames.count, 2, "\(label): collect actual display frames", file: file, line: line)
        guard let index = frames.firstIndex(where: { frame in
            let pixels = PipDisplayFrameSampler.paintedPixels(in: frame.image)
            return pixels.filter { $0 }.count < 80
                || pixels.indices.filter { pixels[$0] && !mask[$0] }.count > 6
        }) else { return }
        for position in max(0, index - 1)...min(frames.count - 1, index + 1) {
            let frame = frames[position]
            let attachment = XCTAttachment(image: frame.image)
            attachment.name = "\(label) sample \(position) t=\(frame.elapsed) timeline=\(frame.animationFrame) pose=\(frame.pose)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let telemetry = frames.map { frame in
            let pixels = PipDisplayFrameSampler.paintedPixels(in: frame.image)
            let outside = pixels.indices.filter { pixels[$0] && !mask[$0] }.count
            return "\(frame.elapsed): frame=\(frame.animationFrame), pose=\(frame.pose), painted=\(pixels.filter { $0 }.count), outside=\(outside)"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: telemetry)
        attachment.name = "\(label) display-frame timeline"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("\(label): a displayed frame loses Pip or contains another painting outside the permitted pose mask", file: file, line: line)
    }

    private func pixels(_ image: UIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
        bytes.withUnsafeMutableBytes { memory in
            let context = CGContext(data: memory.baseAddress, width: 128, height: 128, bitsPerComponent: 8,
                bytesPerRow: 128*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 128, height: 128))
        }
        return bytes
    }

    private func snapshot(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    private func presentationSnapshot(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            // Playing Core Animation lives in the presentation tree; drawHierarchy can return its held model pose.
            (view.layer.presentation() ?? view.layer).render(in: context.cgContext)
        }
    }

    private func orangePixelCount(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let size = 96
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        bytes.withUnsafeMutableBytes { memory in
            let context = CGContext(data: memory.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        return stride(from: 0, to: bytes.count, by: 4).filter {
            Int(bytes[$0]) - Int(bytes[$0 + 2]) > 30 && bytes[$0 + 3] > 128
        }.count
    }
}

private struct PipPaintFrame {
    let image: UIImage
    let elapsed: TimeInterval
    let animationFrame: Double
    let pose: Int
}

@MainActor private final class PipDisplayFrameSampler: NSObject {
    private var link: CADisplayLink?
    private var finish: (() -> Void)?
    private var onFrame: ((TimeInterval) -> Bool)?
    private var firstTimestamp: TimeInterval?

    static func waitForFrames(_ count: Int) async {
        let sampler = PipDisplayFrameSampler()
        var remaining = count
        await sampler.run { _ in remaining -= 1; return remaining <= 0 }
    }

    static func capture(player: LottieAnimationView, runtime: CompanionRuntime, duration: TimeInterval) async -> [PipPaintFrame] {
        let sampler = PipDisplayFrameSampler()
        var frames: [PipPaintFrame] = []
        await sampler.run { elapsed in
            frames.append(PipPaintFrame(image: image(of: player), elapsed: elapsed,
                animationFrame: player.realtimeAnimationFrame, pose: runtime.displayedPose.rawValue))
            return elapsed >= duration
        }
        return frames
    }

    static func image(of view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            context.cgContext.scaleBy(x: 64 / view.bounds.width, y: 64 / view.bounds.height)
            (view.layer.presentation() ?? view.layer).render(in: context.cgContext)
        }
    }

    static func paintedPixels(in image: UIImage) -> [Bool] {
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        bytes.withUnsafeMutableBytes { memory in
            let context = CGContext(data: memory.baseAddress, width: 64, height: 64,
                bitsPerComponent: 8, bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        return (0..<(64 * 64)).map { index in
            let p = index * 4
            return Int(bytes[p]) - Int(bytes[p + 2]) > 30 && bytes[p + 3] > 20
        }
    }

    private func run(onFrame: @escaping (TimeInterval) -> Bool) async {
        await withCheckedContinuation { continuation in
            self.onFrame = onFrame
            finish = { continuation.resume() }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            self.link = link
            link.add(to: .main, forMode: .common)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if firstTimestamp == nil { firstTimestamp = link.timestamp }
        if onFrame?(link.timestamp - (firstTimestamp ?? link.timestamp)) == true {
            link.invalidate()
            self.link = nil
            onFrame = nil
            let finish = finish
            self.finish = nil
            finish?()
        }
    }
}
