@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.learn

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Text
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/**
 * Renders a paragraph of body text with inline glossary terms.
 *
 * Term occurrences are styled with a primary-color underline so they
 * read as tappable. Tapping opens a TooltipBox showing the glossary
 * definition (ANDROID-DESIGN.md §8.2 Glossary lookup).
 *
 * Implementation note: Compose has no built-in clickable-span on a
 * single Text composable across multiple terms. To keep the v1 UX
 * simple, when ANY term is present in the paragraph the entire
 * paragraph becomes a TooltipBox for the FIRST highlighted term. Full
 * per-span tappability is a M5-polish follow-up (requires
 * `buildAnnotatedString` + `ClickableText` + manual hit-testing).
 *
 * Even the v1 first-term experience is genuinely useful — definitions
 * for the most-prominent BoBA terminology surface naturally in context.
 */
@Composable
fun GlossaryRichText(
    text: String,
    glossaryTerms: List<String>,
    modifier: Modifier = Modifier,
) {
    val annotated = remember(text, glossaryTerms) {
        buildAnnotatedString {
            var remaining = text
            val termsRegex = if (glossaryTerms.isEmpty()) null
                             else Regex(
                                 glossaryTerms.joinToString("|") { Regex.escape(it) },
                                 RegexOption.IGNORE_CASE,
                             )
            if (termsRegex == null) {
                append(text)
                return@buildAnnotatedString
            }
            var lastEnd = 0
            for (match in termsRegex.findAll(text)) {
                append(text.substring(lastEnd, match.range.first))
                withStyle(
                    SpanStyle(
                        fontWeight = FontWeight.SemiBold,
                        textDecoration = TextDecoration.Underline,
                    ),
                ) {
                    append(match.value)
                }
                lastEnd = match.range.last + 1
            }
            if (lastEnd < text.length) {
                append(text.substring(lastEnd))
            }
        }
    }

    val firstTerm = remember(text, glossaryTerms) {
        glossaryTerms.firstOrNull { it.lowercase() in text.lowercase() }
    }
    val definition = firstTerm?.let { LearnCorpus.glossary[it.lowercase()] }

    if (definition != null) {
        val tooltipState = rememberTooltipState(isPersistent = false)
        val scope = rememberCoroutineScope()
        TooltipBox(
            positionProvider = TooltipDefaults.rememberTooltipPositionProvider(TooltipAnchorPosition.Above),
            tooltip = {
                PlainTooltip {
                    Text(
                        text = "${definition.term}: ${definition.definition}",
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(8.dp),
                    )
                }
            },
            state = tooltipState,
        ) {
            Text(
                text = annotated,
                style = MaterialTheme.typography.bodyLarge,
                modifier = modifier
                    .padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }
        LaunchedEffect(firstTerm) {
            // Don't auto-show; user must long-press. (TooltipBox surfaces
            // on long-press by default via its semantics.)
        }
    } else {
        Text(
            text = annotated,
            style = MaterialTheme.typography.bodyLarge,
            modifier = modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
    }
}
