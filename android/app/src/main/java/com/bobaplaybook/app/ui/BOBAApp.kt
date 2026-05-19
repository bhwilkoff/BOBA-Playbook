package com.bobaplaybook.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.bobaplaybook.core.ui.components.BOBAWordmark
import com.bobaplaybook.core.ui.theme.BobaTheme

/**
 * Root Composable.
 *
 * M0 deliberately renders only the wordmark + tagline — proves the theme
 * + typography + edge-to-edge stack all wire up. M1 replaces this with
 * the `NavigationSuiteScaffold` + Find tab.
 */
@Composable
fun BOBAApp() {
    BobaTheme {
        Scaffold(modifier = Modifier.fillMaxSize()) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                BOBAWordmark()
                Text(
                    text = "Search. Scan. Collect. Play.",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF080810)
@Composable
private fun PreviewBOBAApp() {
    BOBAApp()
}
