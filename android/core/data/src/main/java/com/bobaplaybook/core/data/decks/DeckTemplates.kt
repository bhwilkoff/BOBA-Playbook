package com.bobaplaybook.core.data.decks

import android.content.Context
import com.bobaplaybook.core.domain.model.Card
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Deck templates — five pre-built archetype decks. iOS parity port
 * of `BOBAPlaybook/Store/DeckBuilderStore.swift` lines 1421-1476 +
 * `BOBAPlaybook/TemplateDeck.json`.
 *
 * Templates exist so a new user has a starting point that's
 * meaningful (matches the iOS metadata text exactly so the
 * archetype names and descriptions stay aligned). The IDs in
 * TemplateDeck.json are full bobaIds; we expand against the live
 * catalog at load time.
 */
data class DeckTemplate(
    val id: String,
    val name: String,
    val description: String,
    val heroIds: List<String>,
    val playIds: List<String>,
    val bonusPlayIds: List<String>,
    val hotDogIds: List<String>,
) {
    /** Expand the template's bobaId arrays into Cards via the live
     *  catalog. Dual-key lookup: by full bobaId first, then by trailing
     *  cardNumber if no match. The cardNumber fallback recovers cases
     *  where a template's stored bobaId encoding differs subtly from
     *  the catalog's runtime bobaId (curly apostrophes, accents,
     *  whitespace) — silent drops here were the "templates load with
     *  wrong cards" symptom the user reported. */
    fun expand(catalog: List<Card>): List<Card> {
        val byBobaId = catalog.associateBy { it.bobaId }
        val byCardNumber = catalog.groupBy { it.cardNumber }.mapValues { it.value.first() }
        val all = heroIds + playIds + bonusPlayIds + hotDogIds
        return all.mapNotNull { templateId ->
            byBobaId[templateId] ?: run {
                // Fallback: extract the leading cardNumber from the
                // bobaId ("IBF-267-Gaveler-Icon Battlefoil-2026 Edition"
                // → "IBF-267"). cardNumbers themselves contain a hyphen
                // (TREATMENT-DIGITS shape), so find the SECOND hyphen
                // and split there.
                val secondHyphen = templateId.indexOf('-').let { first ->
                    if (first < 0) -1 else templateId.indexOf('-', first + 1)
                }
                val cardNumber = if (secondHyphen > 0)
                    templateId.substring(0, secondHyphen)
                else templateId
                byCardNumber[cardNumber]
            }
        }
    }
}

/**
 * Loads `TemplateDeck.json` from the app's assets bundle. Synchronous
 * read on first call; result memoized for the app lifetime. The
 * bundled file is small (~30 KB) so blocking IO is fine here.
 */
@Singleton
class DeckTemplateLoader @Inject constructor() {

    @Volatile private var cached: List<DeckTemplate>? = null

    fun load(context: Context): List<DeckTemplate> {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val raw = runCatching {
                context.assets.open("TemplateDeck.json").bufferedReader().use { it.readText() }
            }.getOrNull()
            if (raw.isNullOrBlank()) {
                cached = emptyList()
                return emptyList()
            }
            val parsed = runCatching {
                JSON.decodeFromString<Map<String, TemplateJson>>(raw)
            }.getOrDefault(emptyMap())
            val list = METADATA.mapNotNull { meta ->
                val t = parsed[meta.id] ?: return@mapNotNull null
                DeckTemplate(
                    id = meta.id,
                    name = meta.name,
                    description = meta.description,
                    heroIds = t.heroIds,
                    playIds = t.playIds,
                    bonusPlayIds = t.bonusPlayIds,
                    hotDogIds = t.hotDogIds,
                )
            }
            cached = list
            return list
        }
    }

    @Serializable
    private data class TemplateJson(
        val heroIds: List<String> = emptyList(),
        val playIds: List<String> = emptyList(),
        val bonusPlayIds: List<String> = emptyList(),
        val hotDogIds: List<String> = emptyList(),
    )

    companion object {
        // Hoisted — building Json per-call wastes allocation.
        private val JSON = Json { ignoreUnknownKeys = true }

        // Verbatim port of iOS DeckBuilderStore.swift line 1441-1447.
        private val METADATA = listOf(
            Meta("lockdown-locker", "Lockdown Locker", "Steel-anchored disruption. Build hot-dog economy early, then close mid-game with high-DBS lockout plays. Teaches when to hold lockouts for late-battle swings."),
            Meta("frozen-tempo",    "Frozen Tempo",    "Ice synergy + Substitution control + economy denial. Teaches Substitution as a strategic axis, not just a panic button."),
            Meta("draw-and-adapt",  "Draw and Adapt",  "Engine-first deck. Maximum draw, situational answers, recovery loops. Teaches how draw advantage compounds across 7 battles."),
            Meta("glow-sacrifice",  "Glow Sacrifice",  "Spec format: discard-fuel + Glow weapon synergy + bonus-play toolbox. Teaches Spec format constraints + discard-as-fuel pattern."),
            Meta("brawl-beatdown",  "Brawl Beatdown",  "Aggro tempo. Brawl/Fire mix, front-loaded power, win the first 3-4 battles. Teaches tempo-aggro counter-strategy."),
        )

        private data class Meta(val id: String, val name: String, val description: String)
    }
}
