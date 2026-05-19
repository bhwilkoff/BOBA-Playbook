package com.bobaplaybook.app.navigation

import kotlinx.serialization.Serializable

/**
 * Type-safe navigation routes for BOBA Playbook.
 *
 * Navigation 3 uses sealed-class keys as the back-stack values
 * (replaces Nav Compose 2.x's string-typed routes). Each route is
 * `@Serializable` for free serialization + restoration through process
 * death.
 *
 * The TopRoute hierarchy mirrors the five binding tabs in
 * ANDROID-DESIGN.md §2.1: Find / Learn / Decks / Collection / Purchase.
 * Inside each tab, push destinations are siblings — the back stack
 * naturally enforces the depth ≤ 2 rule from ANDROID-DESIGN.md §2.2.
 */
sealed interface Route

// ---- Top-level destinations (NavigationSuiteScaffold items) ----

sealed interface TopRoute : Route {
    @Serializable data object Find       : TopRoute
    @Serializable data object Learn      : TopRoute
    @Serializable data object Decks      : TopRoute
    @Serializable data object Collection : TopRoute
    @Serializable data object Purchase   : TopRoute
}

// ---- Push destinations (depth 2) ----

/**
 * Card detail. `bobaId` is the canonical primary key per CLAUDE.md
 * "One ID per Card". CardRepository looks up the live model.
 */
@Serializable
data class CardDetail(val bobaId: String) : Route
