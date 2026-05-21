@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.practice

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.bobaplaybook.core.ui.components.BOBAEmptyState

/**
 * Practice executor entry-point (DECISIONS.md #048).
 *
 * Admin-gated per DECISIONS.md #033: hidden from production users
 * until role check passes. M5.5 ships the placeholder; the full
 * port of iOS's PracticeStore engine (DECISIONS.md #030 —
 * PersistentEffect arrays, firePersistentTriggers, applyHDRecover
 * pipeline, scope vocabulary) is a multi-session effort scheduled
 * post-v1.
 *
 * When that port lands, this file gets replaced with the real
 * PracticeSetupView → ActiveBattleView screen graph. The Composable
 * signature stays the same.
 */
@Composable
fun PracticeScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Battle Practice") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { padding ->
        BOBAEmptyState(
            icon = Icons.Default.SportsEsports,
            headline = "Battle practice — coming soon",
            body = "Practice the BoBA state machine against a CPU coach. The Android port is in progress; use the iOS app for now, or check back in a few releases.",
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        )
    }
}
