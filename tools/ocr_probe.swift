#!/usr/bin/env swift
// OCR probe — runs the SAME Vision text-recognition pathway the iOS scanner
// uses (CardScanner.swift) on local card art, so we can observe what the
// printed card number actually reads as and whether the catalog-validated
// extraction resolves it. macOS Vision == iOS Vision (same framework/rev).
//
// Usage: swift tools/ocr_probe.swift <catalog.json> <thumbs-dir> [N]
//   prints, per sampled card: expected cardNumber, OCR lines (top tokens),
//   strict-regex hit, pure-number hit, and final MATCH/miss vs catalog.

import Foundation
import Vision
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: ocr_probe <catalog> <thumbs> [N]\n", stderr); exit(1) }
let catalogPath = args[1], thumbsDir = args[2]
let sampleN = args.count >= 4 ? Int(args[3]) ?? 60 : 60

struct Card: Decodable { let cardNumber: String?; let bobaId: String?; let imageFile: String?; let set: String?; let hero: String? }
let raw = try! Data(contentsOf: URL(fileURLWithPath: catalogPath))
let all = try! JSONDecoder().decode([Card].self, from: raw)
let tecmo = all.filter { $0.set == "Tecmo Bowl Edition" && ($0.imageFile?.isEmpty == false) }
let cardNumberSet = Set(all.compactMap { $0.cardNumber }.filter { !$0.isEmpty })
let cardNumbers = Array(cardNumberSet)

// CURRENT (hyphen-required) vs PROPOSED (hyphen-optional) strict regex.
let strictCurrent  = try! NSRegularExpression(pattern: #"#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)"#)
let strictProposed = try! NSRegularExpression(pattern: #"#?([A-Z]{1,6}-?[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)"#)
let cyr: [Character:Character] = ["А":"A","В":"B","Е":"E","К":"K","М":"M","Н":"H","О":"O","Р":"P","С":"C","Т":"T","Х":"X","У":"Y","І":"I","Ј":"J","Ѕ":"S","а":"A","е":"E","о":"O","р":"P","с":"C","у":"Y","х":"X"]
func normCyr(_ s: String) -> String { String(s.map { cyr[$0] ?? $0 }) }

func extractWith(_ strict: NSRegularExpression, _ rawText: String) -> (strict: String?, pureNum: String?) {
    let text = normCyr(rawText)
    let range = NSRange(text.startIndex..., in: text)
    var strictHit: String? = nil
    if let m = strict.firstMatch(in: text, range: range), let r = Range(m.range(at: 1), in: text) {
        let c = String(text[r]); if cardNumberSet.contains(c) { strictHit = c }
    }
    var pureHit: String? = nil
    let words = text.components(separatedBy: .whitespacesAndNewlines)
        .map { $0.trimmingCharacters(in: .punctuationCharacters).uppercased() }.filter { !$0.isEmpty }
    for w in words where w.count >= 1 && w.count <= 4 && w.allSatisfy({ $0.isNumber }) {
        if cardNumberSet.contains(w) { pureHit = w; break }
    }
    return (strictHit, pureHit)
}

func ocr(_ url: URL) -> [String] {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return [] }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = false
    req.recognitionLanguages = ["en-US"]
    req.minimumTextHeight = 0.015
    req.customWords = cardNumbers
    let handler = VNImageRequestHandler(cgImage: img, options: [:])
    try? handler.perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}

// Sample across number formats: pure-numeric, alpha-no-hyphen, alpha-hyphen.
func fmt(_ cn: String) -> String {
    if cn.range(of: #"^\d+$"#, options: .regularExpression) != nil { return "pure-num" }
    if cn.range(of: #"^[A-Za-z]+-"#, options: .regularExpression) != nil { return "alpha-hyphen" }
    if cn.range(of: #"^[A-Za-z]+\d"#, options: .regularExpression) != nil { return "alpha-NOhyphen" }
    return "other"
}
var byFmt: [String: [Card]] = [:]
for c in tecmo { byFmt[fmt(c.cardNumber ?? ""), default: []].append(c) }
var sample: [Card] = []
for (_, cards) in byFmt { sample.append(contentsOf: cards.prefix(sampleN / max(1, byFmt.count) + 5)) }

var curHits = 0, propHits = 0, total = 0
var fmtStats: [String: (cur: Int, prop: Int, n: Int)] = [:]
for c in sample.prefix(sampleN) {
    guard let f = c.imageFile else { continue }
    let url = URL(fileURLWithPath: thumbsDir).appendingPathComponent(f)
    guard FileManager.default.fileExists(atPath: url.path) else { continue }
    let lines = ocr(url)
    let joined = lines.joined(separator: " ")
    let (sc, pc) = extractWith(strictCurrent, joined)
    let (sp, pp) = extractWith(strictProposed, joined)
    let curM  = (sc == c.cardNumber) || (pc == c.cardNumber)
    let propM = (sp == c.cardNumber) || (pp == c.cardNumber)
    total += 1; if curM { curHits += 1 }; if propM { propHits += 1 }
    let format = fmt(c.cardNumber ?? "")
    var st = fmtStats[format] ?? (0,0,0); st.n += 1; if curM { st.cur += 1 }; if propM { st.prop += 1 }; fmtStats[format] = st
    let flag = (!curM && propM) ? "FIXED" : (propM ? "ok   " : "miss ")
    print("[\(flag)] \(format)  expect=\(c.cardNumber ?? "?")  proposed-strict=\(sp ?? "-")")
}
print("\n=== card-number match: current \(curHits)/\(total)  →  proposed \(propHits)/\(total) ===")
for (f, st) in fmtStats.sorted(by: { $0.key < $1.key }) {
    print("   \(f): current \(st.cur)/\(st.n) → proposed \(st.prop)/\(st.n)")
}
