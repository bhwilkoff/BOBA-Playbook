import Foundation

enum CDN {
    static let base = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev"

    static func thumb(for imageFile: String) -> URL {
        URL(string: "\(base)/thumbs/\(imageFile)")!
    }

    static func full(for imageFile: String) -> URL {
        URL(string: "\(base)/full/\(imageFile)")!
    }
}
