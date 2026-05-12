import SwiftUI
import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import Network
import UniformTypeIdentifiers

// MARK: - Constants

enum ShowcaseVideoConstants {
    /// TV output dimensions. 1920×1080 = standard 16:9 HD.
    static let renderWidth: Int = 1920
    static let renderHeight: Int = 1080

    /// Source capture cadence — how often we re-snapshot the SwiftUI
    /// grid view. Apple TV's pipeline judders at unusual frame rates,
    /// so each source frame is repeated 3× during encode to land on a
    /// clean 30 fps stream (per WWDC HLS-on-tvOS guidance).
    static let captureFPS: Int = 10
    static let encodeFPS: Int32 = 30

    /// Segment duration. 6s is Apple's recommended starting point for
    /// HLS (preferredOutputSegmentInterval).
    static let segmentDurationSeconds: Double = 6.0

    /// Sliding-window: keep N most-recent segments in the playlist.
    /// Older segment files are deleted to bound temp storage.
    static let segmentWindowSize: Int = 8

    /// Video bitrate. 4 Mbps is Apple's middle-of-the-road for 1080p
    /// in the HLS Authoring Specification.
    static let bitrate: Int = 4_000_000

    /// Number of source rows × cols of cards in the TV render. Rows
    /// follow session.rows; cols are derived to fill 16:9 at 3:4 aspect.
    static let cardAspect: CGFloat = 0.75
}

// MARK: - ShowcaseVideoStreamer
//
// Renders the Showcase grid at 1920×1080 via ImageRenderer at 10 fps,
// encodes through AVAssetWriter in HLS-fMP4 profile, serves the
// resulting fragments via a localhost HTTP listener, and consumes them
// in a single AVPlayer with AirPlay-Video routing enabled.
//
// The phone-side AVRoutePickerView (with prioritizesVideoDevices=true)
// surfaces the in-app AirPlay-Video picker; picking an Apple TV makes
// AVPlayer route via AirPlay-Video. The phone keeps showing its
// SwiftUI UI (control panel after AirPlay engages) — only the player
// content goes to the TV.
//
// Lifecycle: `start()` spins up server → writer → capture → player.
// `stop()` reverses it. The streamer is safe to start/stop multiple
// times within a Showcase session (e.g., user toggles AirPlay).
//
// Implementation follows the research report: HLS fMP4 via
// AVAssetWriterDelegate (WWDC20 10011), CVPixelBuffer from the
// adaptor's pool (not CVPixelBufferCreate), `expectsMediaDataInRealTime`
// = true with frame-drop policy when !isReadyForMoreMediaData,
// CADisplayLink at 10 fps wrapped in autoreleasepool, and AirPlay-Video
// detection via KVO on AVPlayer.isExternalPlaybackActive.
@MainActor
@Observable
final class ShowcaseVideoStreamer: NSObject {

    // MARK: Public observable state

    /// True when AVPlayer routing reports external playback active —
    /// i.e., AirPlay-Video has taken over and the phone-side view can
    /// swap to the control-panel layout.
    private(set) var isExternalPlaybackActive: Bool = false

    /// True between `start()` and `stop()`.
    private(set) var isRunning: Bool = false

    /// The route picker view should bind to this AVPlayer.
    private(set) var player: AVPlayer = AVPlayer()

    // MARK: Dependencies

    private weak var session: ShowcaseSession?

    // MARK: Encoder

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var displayLink: CADisplayLink?
    private var sourceFrameIndex: Int64 = 0

    // MARK: Playlist + server

    private var segmentDir: URL?
    private var playlist = HLSPlaylistBuilder()
    private var server: LocalHLSServer?

    // MARK: KVO

    private var externalObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?

    // MARK: Init

    init(session: ShowcaseSession) {
        self.session = session
        super.init()

        // Configure player for AirPlay-Video routing per WWDC19 501.
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.isMuted = true   // no audio track in our stream

        externalObserver = player.observe(\.isExternalPlaybackActive, options: [.new, .initial]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isExternalPlaybackActive = player.isExternalPlaybackActive
            }
        }
    }

    // No deinit — Swift 6's deinit is nonisolated and can't access
    // MainActor-isolated stored properties. We clean up in stop()
    // instead, which is always called from onDisappear before the
    // streamer goes out of scope.

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        do {
            try prepareSegmentDir()
            try startServer()
            try startWriter()
            startCapture()
            attachPlayerToPlaylist()
            player.play()
        } catch {
            // Surface the failure by stopping cleanly — caller decides
            // whether to retry.
            #if DEBUG
            print("[ShowcaseVideoStreamer] start failed:", error)
            #endif
            stop()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopCapture()
        finalizeWriter()
        player.pause()
        player.replaceCurrentItem(with: nil)
        server?.stop()
        server = nil
        cleanupSegmentDir()
        externalObserver?.invalidate()
        externalObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
    }

    // MARK: - Segment dir

    private func prepareSegmentDir() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("showcase-hls-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        segmentDir = dir
        playlist = HLSPlaylistBuilder()
    }

    private func cleanupSegmentDir() {
        guard let dir = segmentDir else { return }
        try? FileManager.default.removeItem(at: dir)
        segmentDir = nil
    }

    // MARK: - Server

    private func startServer() throws {
        let server = LocalHLSServer()
        try server.start { [weak self] path in
            guard let self else { return nil }
            return self.serve(path: path)
        }
        self.server = server
    }

    /// Serves the m3u8 (synthesized live) and segment / init files
    /// (from disk). Returns (data, contentType) or nil for 404.
    private nonisolated func serve(path: String) -> (Data, String)? {
        // path is e.g. "/index.m3u8" or "/init.mp4" or "/seg42.m4s"
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path

        // Hop to MainActor to read state. Build the response synchronously.
        let task = DispatchSemaphore(value: 0)
        var result: (Data, String)? = nil
        Task { @MainActor in
            defer { task.signal() }
            if trimmed == "index.m3u8" {
                let body = self.playlist.serialize()
                result = (Data(body.utf8), "application/vnd.apple.mpegurl")
                return
            }
            guard let dir = self.segmentDir else { return }
            let file = dir.appendingPathComponent(trimmed)
            guard let data = try? Data(contentsOf: file) else { return }
            let mime = trimmed.hasSuffix(".m4s") || trimmed.hasSuffix(".mp4")
                ? "video/mp4"
                : "application/octet-stream"
            result = (data, mime)
        }
        task.wait()
        return result
    }

    // MARK: - Writer

    private func startWriter() throws {
        guard let dir = segmentDir else { return }
        let writer = try AVAssetWriter(
            contentType: UTType(AVFileType.mp4.rawValue)!
        )
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(
            seconds: ShowcaseVideoConstants.segmentDurationSeconds,
            preferredTimescale: 1
        )
        writer.initialSegmentStartTime = .zero
        writer.shouldOptimizeForNetworkUse = true
        writer.delegate = self

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: ShowcaseVideoConstants.bitrate,
            AVVideoExpectedSourceFrameRateKey: Int(ShowcaseVideoConstants.encodeFPS),
            AVVideoMaxKeyFrameIntervalKey: Int(ShowcaseVideoConstants.encodeFPS),
            AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoAllowFrameReorderingKey: false
        ]
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: ShowcaseVideoConstants.renderWidth,
            AVVideoHeightKey: ShowcaseVideoConstants.renderHeight,
            AVVideoCompressionPropertiesKey: compression
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        input.mediaTimeScale = ShowcaseVideoConstants.encodeFPS

        let pixelAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: ShowcaseVideoConstants.renderWidth,
            kCVPixelBufferHeightKey as String: ShowcaseVideoConstants.renderHeight,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelAttrs
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "ShowcaseVideoStreamer", code: 1)
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "ShowcaseVideoStreamer", code: 2)
        }
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.videoInput = input
        self.adaptor = adaptor
        self.sourceFrameIndex = 0
        _ = dir  // segment dir already prepared; writer streams via delegate, not file URL
    }

    private func finalizeWriter() {
        videoInput?.markAsFinished()
        writer?.finishWriting { /* ignore */ }
        writer = nil
        videoInput = nil
        adaptor = nil
    }

    // MARK: - Capture

    private func startCapture() {
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 8,
            maximum: 12,
            preferred: Float(ShowcaseVideoConstants.captureFPS)
        )
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    private func stopCapture() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired() {
        autoreleasepool {
            captureAndAppendFrame()
        }
    }

    private func captureAndAppendFrame() {
        guard let session, let adaptor, let input = videoInput else { return }
        guard input.isReadyForMoreMediaData else { return }
        guard let pool = adaptor.pixelBufferPool else { return }

        // Render the SwiftUI TV view to a CGImage at native 1920×1080.
        let renderer = ImageRenderer(content:
            ShowcaseTVRenderView(session: session)
                .frame(
                    width: CGFloat(ShowcaseVideoConstants.renderWidth),
                    height: CGFloat(ShowcaseVideoConstants.renderHeight)
                )
                .background(Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255))
        )
        renderer.scale = 1.0
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else { return }
        guard let pixelBuffer = ShowcaseVideoStreamer.makePixelBuffer(from: cgImage, pool: pool) else { return }

        // Each captured source frame is appended 3× (10 fps → 30 fps).
        // PTS is in encodeFPS timescale.
        for offset in 0..<3 {
            guard input.isReadyForMoreMediaData else { return }
            let pts = CMTime(
                value: sourceFrameIndex * 3 + Int64(offset),
                timescale: ShowcaseVideoConstants.encodeFPS
            )
            adaptor.append(pixelBuffer, withPresentationTime: pts)
        }
        sourceFrameIndex += 1
    }

    // MARK: - Pixel buffer

    /// Production-quality CGImage → CVPixelBuffer via the adaptor's
    /// pool. BGRA + noneSkipFirst + byteOrder32Little matches the
    /// kCVPixelFormatType_32BGRA layout CGContext can write to without
    /// channel swaps. Per the research: this is the verified-correct
    /// pattern from CoreMLHelpers and Apple's "Build a movie from images"
    /// sample.
    nonisolated static func makePixelBuffer(from cgImage: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
            .union(.byteOrder32Little)
        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    // MARK: - Player

    private func attachPlayerToPlaylist() {
        guard let server, let url = URL(string: "http://127.0.0.1:\(server.port)/index.m3u8") else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
    }
}

// MARK: - AVAssetWriterDelegate

extension ShowcaseVideoStreamer: AVAssetWriterDelegate {
    /// AVAssetWriter calls this on a background queue for each fMP4
    /// fragment it produces. We write the bytes to disk and update
    /// the in-memory playlist (which is served live by the HTTP
    /// listener).
    nonisolated func assetWriter(
        _ writer: AVAssetWriter,
        didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType,
        segmentReport: AVAssetSegmentReport?
    ) {
        // Capture the duration before hopping to main actor.
        let duration: Double = {
            if let report = segmentReport,
               let track = report.trackReports.first(where: { $0.mediaType == .video }) {
                return CMTimeGetSeconds(track.duration)
            }
            return ShowcaseVideoConstants.segmentDurationSeconds
        }()
        let dataCopy = segmentData
        let type = segmentType
        Task { @MainActor [weak self] in
            self?.handleSegment(data: dataCopy, type: type, duration: duration)
        }
    }

    private func handleSegment(data: Data, type: AVAssetSegmentType, duration: Double) {
        guard let dir = segmentDir else { return }
        switch type {
        case .initialization:
            let file = dir.appendingPathComponent("init.mp4")
            try? data.write(to: file, options: .atomic)
            playlist.setInitSegment("init.mp4")
        case .separable:
            let name = "seg\(playlist.nextSegmentIndex).m4s"
            let file = dir.appendingPathComponent(name)
            try? data.write(to: file, options: .atomic)
            playlist.appendSegment(name: name, duration: duration)
            // Sliding window: drop old segment files past the window.
            for old in playlist.evictedFiles {
                let url = dir.appendingPathComponent(old)
                try? FileManager.default.removeItem(at: url)
            }
            playlist.clearEvicted()
        @unknown default:
            break
        }
    }
}

// MARK: - HLSPlaylistBuilder
//
// Builds and maintains a sliding-window live HLS playlist. Live media
// playlists omit #EXT-X-ENDLIST so AVPlayer keeps polling for new
// segments. Sliding-window means the playlist's #EXT-X-MEDIA-SEQUENCE
// increments as old segments roll off, and `evictedFiles` lists names
// the streamer should delete from disk after each window slide.
@MainActor
final class HLSPlaylistBuilder {
    private var initSegmentName: String?
    private var entries: [Entry] = []
    private(set) var nextSegmentIndex: Int = 0
    private(set) var mediaSequence: Int = 0
    private(set) var evictedFiles: [String] = []

    struct Entry {
        let name: String
        let duration: Double
    }

    func setInitSegment(_ name: String) {
        initSegmentName = name
    }

    func appendSegment(name: String, duration: Double) {
        entries.append(Entry(name: name, duration: duration))
        nextSegmentIndex += 1
        let window = ShowcaseVideoConstants.segmentWindowSize
        while entries.count > window {
            let removed = entries.removeFirst()
            evictedFiles.append(removed.name)
            mediaSequence += 1
        }
    }

    func clearEvicted() {
        evictedFiles.removeAll()
    }

    func serialize() -> String {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        let maxDuration = entries.map(\.duration).max() ?? ShowcaseVideoConstants.segmentDurationSeconds
        lines.append("#EXT-X-TARGETDURATION:\(Int(ceil(maxDuration)))")
        lines.append("#EXT-X-MEDIA-SEQUENCE:\(mediaSequence)")
        if let initName = initSegmentName {
            lines.append("#EXT-X-MAP:URI=\"\(initName)\"")
        }
        for entry in entries {
            lines.append(String(format: "#EXTINF:%.3f,", entry.duration))
            lines.append(entry.name)
        }
        // No #EXT-X-ENDLIST — this is a live playlist.
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - LocalHLSServer
//
// Minimal localhost HTTP/1.1 server using Network.framework's
// NWListener. Accepts GET requests, calls the resource provider with
// the path, returns the data + content-type. Used to satisfy AVPlayer's
// requirement that HLS playlists be loaded over HTTP (not file://).
//
// No third-party dependencies — CLAUDE.md forbids them. Network.framework
// is Apple-native and the canonical iOS HTTP-server primitive.
final class LocalHLSServer {
    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "playbook.showcase.hls.server")
    private var provider: (@Sendable (String) -> (Data, String)?)?

    func start(handler: @escaping @Sendable (String) -> (Data, String)?) throws {
        self.provider = handler
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        let portReady = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let p = listener.port?.rawValue { self?.port = p }
                portReady.signal()
            case .failed:
                portReady.signal()
            default: break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        _ = portReady.wait(timeout: .now() + 2)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            // Parse "GET /path HTTP/1.1"
            let firstLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }
            let path = String(parts[1])
            if let (body, mime) = self.provider?(path) {
                self.send(connection: connection, body: body, mime: mime)
            } else {
                self.sendNotFound(connection: connection)
            }
        }
    }

    private func send(connection: NWConnection, body: Data, mime: String) {
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(mime)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendNotFound(connection: NWConnection) {
        let header = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - ShowcaseTVRenderView
//
// 1920×1080 16:9 layout of the Showcase grid for the AirPlay-Video
// stream. Reads from the same ShowcaseSession as the phone view so
// content stays in sync, but lays out at the TV's aspect ratio and
// without the phone-side toolbar / pinch gestures.
//
// Note: ImageRenderer captures the CURRENT VALUE of @State / @Observable
// properties when snapshotting, not the SwiftUI-interpolated value
// mid-animation. So tile state changes (image swaps) appear in the TV
// stream, but the animation interpolation between states is not
// captured. The TV ends up displaying a "slideshow" of the grid
// where cards swap discretely; the phone retains its full animation.
struct ShowcaseTVRenderView: View {
    let session: ShowcaseSession

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let rows = max(2, session.rows)
            let cellH = size.height / CGFloat(rows)
            let cellW = cellH * ShowcaseVideoConstants.cardAspect
            let cols = max(1, Int(ceil(size.width / cellW)))
            let totalTiles = rows * cols

            ZStack(alignment: .topLeading) {
                Color(red: 0x08/255, green: 0x08/255, blue: 0x10/255)

                ForEach(0..<totalTiles, id: \.self) { index in
                    if index < session.tiles.count {
                        let row = index / cols
                        let col = index % cols
                        TVCardTile(
                            state: session.tiles[index],
                            width: cellW,
                            height: cellH
                        )
                        .position(
                            x: CGFloat(col) * cellW + cellW / 2,
                            y: CGFloat(row) * cellH + cellH / 2
                        )
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

private struct TVCardTile: View {
    let state: ShowcaseTileState
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let img = state.faceUp ? state.front : state.back {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Color(red: 0x0D/255, green: 0x0D/255, blue: 0x1A/255)
            }
        }
        .frame(width: width, height: height)
    }
}
