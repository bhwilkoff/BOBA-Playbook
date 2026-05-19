package com.bobaplaybook.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.bobaplaybook.app.auth.AuthManager
import com.bobaplaybook.app.feature.scan.ScanModuleAccessSeeder
import com.bobaplaybook.app.ui.BOBAApp
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Single-Activity host.
 *
 * Compose handles the entire UI tree from [BOBAApp] down. The Activity's
 * job is purely:
 *  - install the splash screen (Android 12+ Splash Screen API)
 *  - enable edge-to-edge rendering (mandatory on targetSdk >= 35)
 *  - dispatch deep links to the navigation layer
 *
 * Deep-link routing mirrors iOS `routeIncoming(_:)` — switch on scheme,
 * not on URL shape (ANDROID-DEV.md §14.3). The Supabase OAuth callback
 * detector lives in the same place as the route dispatcher.
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    /**
     * Injected purely for its constructor side-effect: seeds the
     * static `ScanModuleAccess.cardRepository` so the Compose Scan
     * viewfinder can read the catalog without threading Hilt through
     * an `AndroidView` factory. See ScanScreen.kt for the rationale.
     */
    @Inject lateinit var scanModuleAccessSeeder: ScanModuleAccessSeeder
    @Inject lateinit var authManager: AuthManager

    override fun onCreate(savedInstanceState: Bundle?) {
        // Splash screen MUST be installed before super.onCreate.
        installSplashScreen()
        super.onCreate(savedInstanceState)
        // Edge-to-edge per ANDROID-DESIGN.md §4.14. Required on targetSdk >= 35.
        enableEdgeToEdge()

        // Dispatch any deep link that launched the activity.
        handleIncomingIntent(intent)

        setContent {
            BOBAApp(authManager = authManager)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    /**
     * Two-step dispatch by scheme — same architecture as iOS
     * `routeIncoming(_:)` (see BOBAPlaybookApp.swift).
     *
     *  - `https://bobaplaybook.com/...` — App Link (verified) →
     *    [routeUniversalLink] parses the path and pushes onto the nav graph.
     *  - `bobaplaybook://...` — custom scheme (OAuth callbacks + same-app
     *    deep links) → [routeDeepLink].
     *
     * Supabase OAuth handler will be wired here once supabase-kt is
     * installed (M7). For M0 this dispatcher is a stub.
     */
    private fun handleIncomingIntent(intent: Intent?) {
        val uri: Uri = intent?.data ?: return
        when (uri.scheme) {
            "https" -> routeUniversalLink(uri)
            "bobaplaybook" -> routeDeepLink(uri)
        }
    }

    private fun routeUniversalLink(uri: Uri) {
        // TODO(M0+): parse pathSegments and push onto NavController.
        // Wire when M1 stands up the NavHost.
    }

    private fun routeDeepLink(uri: Uri) {
        // TODO(M7): supabase.handleDeeplinks(intent) for OAuth callbacks.
    }
}
