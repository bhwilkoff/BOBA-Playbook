package com.bobaplaybook.app.navigation

/**
 * String-typed Navigation Compose routes.
 *
 * One source of truth for the route patterns + argument keys. Avoids
 * stringly-typed sprinkles like `"card_detail/$bobaId"` scattered
 * across screens.
 *
 * Nav3's typed-route API is wired in the version catalog for future
 * adoption; today we use the proven Navigation Compose 2.x pattern.
 */
object NavRoutes {

    // Tab roots
    const val FIND       = "find"
    const val LEARN      = "learn"
    const val DECKS      = "decks"
    const val COLLECTION = "collection"
    const val PURCHASE   = "purchase"

    // Push destinations (depth 2)
    const val ARG_BOBA_ID            = "bobaId"
    const val CARD_DETAIL_PATTERN    = "card/{$ARG_BOBA_ID}"
    fun cardDetail(bobaId: String)   = "card/$bobaId"

    // Decks editor + secondary surfaces (depth 2 inside Decks tab)
    const val DECK_EDITOR  = "decks/editor"
    const val DECK_MANAGE  = "decks/manage"
    const val DECK_RULES   = "decks/rules"
    const val DECK_LEGALITY = "decks/legality"

    // Collection secondary surfaces (depth 2 inside Collection tab)
    const val COLLECTION_RAINBOWS = "collection/rainbows"
    const val COLLECTION_SHOWS    = "collection/shows"

    // Rainbow detail (per-hero or custom)
    const val ARG_RAINBOW_KIND = "kind"
    const val ARG_RAINBOW_ID   = "rid"
    const val RAINBOW_DETAIL_PATTERN = "collection/rainbow/{$ARG_RAINBOW_KIND}/{$ARG_RAINBOW_ID}"
    fun rainbowDetail(kind: String, id: String) = "collection/rainbow/$kind/${java.net.URLEncoder.encode(id, "UTF-8")}"

    // Collection card detail (multi-copy + designation switcher)
    const val COLLECTION_CARD_DETAIL_PATTERN = "collection/card/{$ARG_BOBA_ID}"
    fun collectionCardDetail(bobaId: String) = "collection/card/$bobaId"

    // Profile (full-screen destination — Find-only entry)
    const val PROFILE = "profile"

    // Practice executor (admin-gated; DECISIONS.md #048)
    const val PRACTICE = "practice"

    // Learn category (depth 2 inside Learn tab — one bespoke page per category)
    const val ARG_CATEGORY = "category"
    const val LEARN_CATEGORY_PATTERN = "learn/{$ARG_CATEGORY}"
    fun learnCategory(category: String) = "learn/$category"
}
