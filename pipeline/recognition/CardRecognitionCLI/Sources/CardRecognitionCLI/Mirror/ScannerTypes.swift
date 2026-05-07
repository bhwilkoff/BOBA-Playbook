// EXTRACTED from BOBAPlaybook/Views/Scan/CardScanner.swift
//
// CardScanner.swift's full file imports UIKit + AVFoundation (the live
// camera path) and won't compile on macOS-only targets. This file
// extracts the iOS-agnostic types that ScanMatching depends on:
//   - struct ScanObservation
//   - final class FeaturePrintIndex
//
// ONE deviation from the iOS source: `loadFromBundle()` is replaced by
// `load(from url: URL)` so the CLI can point at a feature-prints.bin
// file passed as a command-line argument. The parsing logic is byte-
// identical to the iOS version.
//
// Sync rule: see _MIRROR.md. When CardScanner.swift's ScanObservation
// or FeaturePrintIndex changes, re-run sync_mirror.sh.

import Foundation
import Vision
import CoreImage
import Accelerate

// MARK: - ScanObservation
//
// All text extracted from one scan cycle, split by card corner region.
// `cgImage` is the cropped guide region. CGImage is immutable + Sendable
// in Swift 6 — safe to ferry across actor boundaries.
struct ScanObservation: @unchecked Sendable {
    let cardNumber:   String   // primary identifier — bottom-left corner
    let rawName:      String   // top-left  — card title
    let rawPower:     String   // top-right — power number
    let rawVariation: String   // bottom-right — treatment / variation
    let fullText:     String   // all detected text joined
    let cgImage:      CGImage? // for image-similarity tiebreak
}

// MARK: - FeaturePrintIndex
//
// In-memory image fingerprint database. Constructed once per CLI run by
// loading feature-prints.bin (BFPI v1 or v2 format) from disk.
//
// Distance lookup: `distances(in:)` runs Vision feature-print extraction
// on a query image and returns L2-squared distance to every catalog
// entry, keyed by bobaId. ScanMatching consumes this dictionary to seed
// its top-30 candidate pool.
//
// Annotated `@MainActor` to match the iOS source's annotation. When
// invoked from main.swift's @main + @MainActor entry, lookups run on
// the main thread.
@MainActor
final class FeaturePrintIndex {

    static let shared = FeaturePrintIndex()

    private(set) var isLoaded: Bool = false
    private(set) var entryCount: Int = 0
    private(set) var elementCount: Int = 0

    private var bobaIds: [String] = []
    private var flatVectors: [Float] = []

    /// CLI variant of the iOS `loadFromBundle()` — takes an explicit
    /// file URL instead of looking the file up in the app bundle.
    /// The parsing logic below is identical to the iOS version.
    func load(from url: URL) {
        guard !isLoaded else { return }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return
        }
        guard parse(bfpi: data) else {
            bobaIds.removeAll(keepingCapacity: false)
            flatVectors.removeAll(keepingCapacity: false)
            entryCount = 0
            elementCount = 0
            return
        }
        isLoaded = true
    }

    /// Search the index for the closest matching cards. Returns up to
    /// `topK` (bobaId, distance) pairs sorted by ascending distance.
    func searchNearest(in cgImage: CGImage,
                       topK: Int = 5) async -> [(bobaId: String, distance: Float)] {
        let all = await computeAllDistances(in: cgImage)
        guard !all.isEmpty else { return [] }
        var indexed = (0..<all.count).map { (i: $0, d: all[$0]) }
        indexed.sort { $0.d < $1.d }
        return indexed.prefix(topK).map { (bobaIds[$0.i], $0.d) }
    }

    /// One Vision feature-print pass + every-entry distance. Returns a
    /// dictionary keyed by bobaId with L2-squared distances. Empty
    /// dictionary on any failure.
    func distances(in cgImage: CGImage) async -> [String: Float] {
        let all = await computeAllDistances(in: cgImage)
        guard !all.isEmpty else { return [:] }
        var out: [String: Float] = [:]
        out.reserveCapacity(all.count)
        for i in 0..<all.count {
            if out[bobaIds[i]] == nil { out[bobaIds[i]] = all[i] }
        }
        return out
    }

    private func computeAllDistances(in cgImage: CGImage) async -> [Float] {
        guard isLoaded, entryCount > 0 else { return [] }

        let request = VNGenerateImageFeaturePrintRequest()
        // .scaleFit must match the indexer
        // (scripts/build_feature_print_index.swift). Switched from
        // .centerCrop in 1.950 — see the comment there for why
        // (treatment-distinguishing borders were getting cropped off).
        request.imageCropAndScaleOption = .scaleFit
        // Match the indexer's revision exactly. Different revisions
        // produce incompatible vectors; without this pin a future iOS
        // default revision change would silently fall through.
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        guard let query = request.results?.first as? VNFeaturePrintObservation,
              query.elementCount == elementCount,
              query.elementType == .float
        else { return [] }

        var queryVec = [Float](repeating: 0, count: elementCount)
        let byteCount = elementCount * MemoryLayout<Float>.size
        guard query.data.count == byteCount else { return [] }
        queryVec.withUnsafeMutableBufferPointer { dst in
            _ = query.data.copyBytes(to: dst)
        }

        // Compute L2-squared distance from query to each entry. vDSP
        // batches per-entry distance — absence of square root preserves
        // ordering, which is all we need for top-K.
        var distances = [Float](repeating: 0, count: entryCount)
        let n = vDSP_Length(elementCount)
        flatVectors.withUnsafeBufferPointer { allBase in
            queryVec.withUnsafeBufferPointer { qBase in
                for i in 0..<entryCount {
                    var d: Float = 0
                    let entryStart = allBase.baseAddress!.advanced(by: i * elementCount)
                    vDSP_distancesq(qBase.baseAddress!, 1,
                                    entryStart, 1,
                                    &d, n)
                    distances[i] = d
                }
            }
        }
        return distances
    }

    // MARK: - Parser

    private func parse(bfpi data: Data) -> Bool {
        let headerLen = 4 + 4 * 4
        guard data.count >= headerLen else { return false }
        let magic = data.prefix(4)
        guard magic == Data("BFPI".utf8) else { return false }

        // `loadUnaligned` is the alignment-safe primitive — the BFPI
        // format interleaves variable-length bobaId strings with raw
        // numeric blocks, so most read offsets aren't aligned to the
        // type's natural size. `assumingMemoryBound` would be UB.
        func readU32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { raw in
                UInt32(littleEndian:
                    raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }
        func readU16(_ offset: Int) -> UInt16 {
            data.withUnsafeBytes { raw in
                UInt16(littleEndian:
                    raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            }
        }
        let version      = readU32(4)
        let entries      = Int(readU32(8))
        let elementCount = Int(readU32(12))
        let elementSize  = Int(readU32(16))
        guard entries > 0, elementCount > 0 else { return false }
        // v1 = Float32 raw, v2 = int8 + per-vector Float32 scale.
        let isV1 = (version == 1 && elementSize == 4)
        let isV2 = (version == 2 && elementSize == 1)
        guard isV1 || isV2 else { return false }

        let perEntryFloats = elementCount
        var ids: [String] = []
        ids.reserveCapacity(entries)
        var flat = [Float](repeating: 0, count: entries * perEntryFloats)

        var cursor = headerLen
        for i in 0..<entries {
            guard cursor + 2 <= data.count else { return false }
            let idLen = Int(readU16(cursor)); cursor += 2
            guard cursor + idLen <= data.count else { return false }
            let idData = data.subdata(in: cursor..<(cursor + idLen))
            guard let id = String(data: idData, encoding: .utf8) else { return false }
            ids.append(id)
            cursor += idLen

            let dstStart = i * perEntryFloats

            if isV1 {
                let printBytes = perEntryFloats * 4
                guard cursor + printBytes <= data.count else { return false }
                data.withUnsafeBytes { srcRaw in
                    flat.withUnsafeMutableBufferPointer { dst in
                        let dstPtr = UnsafeMutableRawPointer(dst.baseAddress!)
                            .advanced(by: dstStart * 4)
                        let srcPtr = srcRaw.baseAddress!.advanced(by: cursor)
                        dstPtr.copyMemory(from: srcPtr, byteCount: printBytes)
                    }
                }
                cursor += printBytes
            } else {
                guard cursor + 4 + perEntryFloats <= data.count else { return false }
                let scaleBits = readU32(cursor); cursor += 4
                let scale = Float(bitPattern: scaleBits)
                data.withUnsafeBytes { srcRaw in
                    let i8Ptr = srcRaw.baseAddress!.advanced(by: cursor)
                        .assumingMemoryBound(to: Int8.self)
                    flat.withUnsafeMutableBufferPointer { dst in
                        let dstPtr = dst.baseAddress!.advanced(by: dstStart)
                        vDSP_vflt8(i8Ptr, 1, dstPtr, 1, vDSP_Length(perEntryFloats))
                        var s = scale
                        vDSP_vsmul(dstPtr, 1, &s, dstPtr, 1, vDSP_Length(perEntryFloats))
                    }
                }
                cursor += perEntryFloats
            }
        }

        self.bobaIds = ids
        self.flatVectors = flat
        self.entryCount = entries
        self.elementCount = elementCount
        return true
    }
}
