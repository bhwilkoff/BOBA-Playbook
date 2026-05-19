package com.bobaplaybook.core.ui.snackbar

import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.compositionLocalOf

/**
 * App-scoped SnackbarHostState provided by [BOBAApp] root so any
 * screen can dispatch a confirmation without owning its own host.
 *
 * Pattern: `LocalAppSnackbar.current.showSnackbar("…")` inside a
 * coroutine scope. Falls back to a per-screen host when not provided
 * (tests, isolated previews).
 */
val LocalAppSnackbar = compositionLocalOf<SnackbarHostState?> { null }
