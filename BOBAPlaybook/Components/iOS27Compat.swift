//
//  iOS27Compat.swift
//  BOBAPlaybook
//
//  iOS 27 additive-adoption helpers. The app targets iOS 26.4 as its
//  deployment floor (CLAUDE.md / DECISIONS.md #066) but builds against the
//  iOS 27 SDK, so every iOS-27-only API is adopted *additively* behind
//  `if #available(iOS 27, *)` with the iOS 26 behavior preserved as the
//  fallback. These view-level wrappers keep that gate in one place so call
//  sites stay readable. ToolbarContent-level adoptions (visibilityPriority,
//  topBarPinnedTrailing, contentMarginsRemoved) can't be expressed as a
//  generic modifier and are gated inline at their call sites instead.
//

import SwiftUI

extension View {
    /// Minimizes the navigation bar as the person scrolls down a dense grid
    /// (Find / Collection / Decks browser), matching the iOS 27 system motion
    /// the tab bar already uses during search. No-op on iOS 26.
    @ViewBuilder
    func bobaMinimizeNavBarOnScroll() -> some View {
        #if IOS27_SDK
        if #available(iOS 27, *) {
            self.toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Routes the `AsyncImage` views in this subtree through the app's tuned
    /// `URLSession`, so non-card images (avatars, Discord, Whatnot / YouTube
    /// thumbnails) share the 100 MB / 500 MB `URLCache.shared` persistent
    /// cache instead of the framework's smaller default loader cache. On
    /// iOS 26 `AsyncImage` keeps its existing behavior; on iOS 27 the
    /// catalog's repeat-view loads come from disk. Card-catalog images are
    /// unaffected — they use the bespoke `CardImageView` / `CachedAsyncCardImage`
    /// loaders, which already layer an NSCache + scroll debounce on top.
    @ViewBuilder
    func bobaSharedImageCache() -> some View {
        #if IOS27_SDK
        if #available(iOS 27, *) {
            self.asyncImageURLSession(BOBAImageCache.session)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Enables `swipeActions` on rows inside a non-`List` scrollable container
    /// (a `ScrollView` with a `VStack` / `LazyVStack` / `LazyVGrid`). Before
    /// iOS 27, `swipeActions` outside a `List` is silently a no-op; this marks
    /// the container so the per-row swipe works. No-op on iOS 26 (rows remain
    /// reachable through their other affordances).
    @ViewBuilder
    func bobaSwipeActionsContainer() -> some View {
        #if IOS27_SDK
        if #available(iOS 27, *) {
            self.swipeActionsContainer()
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Presents an alert driven by an optional value, passing the unwrapped
    /// value to the `actions` / `message` builders. On iOS 27 this is the
    /// native `alert(_:item:)` shape; on iOS 26 it falls back to the
    /// `isPresented:` + `presenting:` form with a derived Bool binding, so
    /// every call site reads as a single optional-driven alert regardless of
    /// OS. Prefer this over a hand-rolled `Binding(get:set:)` wrapper.
    @ViewBuilder
    func bobaItemAlert<T, A: View, M: View>(
        _ title: LocalizedStringKey,
        item: Binding<T?>,
        @ViewBuilder actions: @escaping (T) -> A,
        @ViewBuilder message: @escaping (T) -> M
    ) -> some View {
        #if IOS27_SDK
        if #available(iOS 27, *) {
            self.alert(title, item: item, actions: actions, message: message)
        } else {
            self.alert(
                title,
                isPresented: Binding(
                    get: { item.wrappedValue != nil },
                    set: { if !$0 { item.wrappedValue = nil } }
                ),
                presenting: item.wrappedValue,
                actions: actions,
                message: message
            )
        }
        #else
        self.alert(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue,
            actions: actions,
            message: message
        )
        #endif
    }
}

/// Shared image `URLSession` for `AsyncImage` subtrees (see
/// `bobaSharedImageCache()`). Backed by `URLCache.shared`, which the app
/// configures at launch to 100 MB memory / 500 MB disk.
enum BOBAImageCache {
    nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = .shared
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()
}
