package com.bobaplaybook.core.domain.model

/**
 * User collection designations (DECISIONS.md #023 + DESIGN.md §8.4).
 *
 * Five mutually-exclusive designations a user can apply to any card
 * they've added to their collection. Order matches iOS Picker order:
 *  Personal → Sale → Trade → Wanted → Grails
 *
 * The string `key` is the Supabase column value — stable across
 * iOS / web / Android. NEVER refactor without coordinating with the
 * other platforms (mirrors the Element UPPERCASE rule in
 * DECISIONS.md #010).
 */
enum class Designation(val key: String, val label: String, val shortLabel: String) {
    PERSONAL ("personal", "Personal Collection", "Personal"),
    FOR_SALE ("for_sale", "For Sale",            "Sale"),
    FOR_TRADE("for_trade","For Trade",           "Trade"),
    WANTED   ("wanted",   "Wanted",              "Wanted"),
    GRAILS   ("grails",   "Grails",              "Grails");

    companion object {
        fun fromKey(key: String): Designation? = entries.firstOrNull { it.key == key }
    }
}

/**
 * A user's owned card (Supabase `user_cards` row).
 *
 * Mirrors the iOS `UserCard` model. `cardBobaId` foreign-keys into the
 * static catalog (`cards.json`); `userId` foreign-keys into Supabase
 * `auth.users.id`.
 *
 * `estimatedValue` is the cached market estimate (DECISIONS.md #013) —
 * value-summary header reads from here so the grid doesn't re-fetch
 * pricing on every render.
 */
data class UserCard(
    val id: String,
    val userId: String,
    val cardBobaId: String,
    val designation: Designation,
    val quantity: Int = 1,
    val purchasePrice: Double? = null,
    val askingPrice: Double? = null,
    val estimatedValue: Double? = null,
    /** Mint / Near Mint / Excellent / Good / Poor — surfaced in Edit. */
    val condition: String? = null,
    /** Tick 239 — third-party grade (e.g. "10", "9.5", "8.5"). Captured
     *  at add-time; previously dropped on the domain boundary. */
    val grade: String? = null,
    /** Tick 239 — grading authority: PSA / BGS / SGC / CGC / etc. */
    val gradingCompany: String? = null,
    val notes: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    /** Server-side `user_cards.acquired_at` ISO timestamp. Null when
     *  Supabase didn't return it (legacy rows). Surfaced as the
     *  "Added [time]" subtitle in the Collection list — iOS parity. */
    val acquiredAtIso: String? = null,
)
