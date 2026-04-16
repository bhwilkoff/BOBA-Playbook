//
//  CachedAsyncCardImage.swift
//  BOBAPlaybook
//
//  Lightweight cached image loader for card images in practice battle and
//  deck builder views. Uses the same shared NSCache as CardImageView.
//  Does NOT require CardStore in the environment.
//

import SwiftUI

struct CachedAsyncCardImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    @State private var image: UIImage? = nil
    @State private var failed = false
    @State private var loadID = 0

    var body: some View {
        // Always maintain card aspect ratio (5:7) so loading/failed states
        // don't cause layout shifts or squished frames
        Color.clear
            .aspectRatio(5.0/7.0, contentMode: .fit)
            .overlay {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    } else if failed {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Design.Colors.glass.opacity(0.3))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Design.Colors.surface)
                            ProgressView()
                                .tint(Design.Colors.textMuted)
                        }
                    }
                }
            }
            .clipped()
            .task(id: loadID) {
                await loadImage()
            }
            .onAppear {
                if failed || (image == nil && cardImageCache.object(forKey: url as NSURL) == nil) {
                    failed = false
                    loadID += 1
                } else if image == nil, let cached = cardImageCache.object(forKey: url as NSURL) {
                    image = cached
                }
            }
    }

    private func loadImage() async {
        let key = url as NSURL
        if let cached = cardImageCache.object(forKey: key) {
            image = cached
            return
        }
        // Debounce: skip cells that scroll past quickly (matches CardImageView)
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }
        if let cached = cardImageCache.object(forKey: key) {
            image = cached
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, _) = try await cardImageSession.data(for: request)
            guard !Task.isCancelled else { return }
            if let loaded = UIImage(data: data) {
                cardImageCache.setObject(loaded, forKey: key, cost: data.count)
                image = loaded
            } else {
                failed = true
            }
        } catch {
            let cancelled = Task.isCancelled
                || (error as? URLError)?.code == .cancelled
                || error is CancellationError
            if !cancelled { failed = true }
        }
    }
}
