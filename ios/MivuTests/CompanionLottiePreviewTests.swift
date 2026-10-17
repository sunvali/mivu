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
            let first = snapshot(player).pngData()
            var finished = false
            let began = Date()
            player.play(marker: "greeting", loopMode: .playOnce) { finished = $0 }
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(player.isAnimationPlaying)
            XCTAssertNotEqual(snapshot(player).pngData(), first, "Greeting \(iteration) must visibly advance")
            while !finished && Date().timeIntervalSince(began) < 3.2 {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(finished, "Greeting \(iteration) must complete without a host timer")
            XCTAssertFalse(player.isAnimationPlaying)
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(began), 2.15)
        }
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
                let image = snapshot(player).pngData()
                await runtime.apply(output, darkMode: true, surface: surface)
                try await Task.sleep(for: .milliseconds(650))
                XCTAssertGreaterThan(player.realtimeAnimationFrame, before, "Appearance updates must not restart the living loop")
                XCTAssertNotEqual(snapshot(player).pngData(), image, "Breathing must move painted parts, not only the timeline")
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

    private func snapshot(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
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
