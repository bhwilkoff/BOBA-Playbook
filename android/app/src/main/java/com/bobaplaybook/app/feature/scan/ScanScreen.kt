@file:OptIn(ExperimentalMaterial3Api::class)

package com.bobaplaybook.app.feature.scan

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis.COORDINATE_SYSTEM_VIEW_REFERENCED
import androidx.camera.mlkit.vision.MlKitAnalyzer
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.bobaplaybook.core.data.catalog.CardRepository
import com.bobaplaybook.core.ui.components.BOBAEmptyState
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import javax.inject.Inject

/**
 * Scan tab (ANDROID-DESIGN.md §6.5 + DECISIONS.md #043).
 *
 * M3 ships single-card live OCR:
 *  - CameraX `LifecycleCameraController` with image-analysis use case
 *  - ML Kit Text Recognition v2 (bundled Latin model)
 *  - `MlKitAnalyzer` glues frame stream to recognizer + delivers
 *    results on the main executor
 *  - Regex match against the in-memory card catalog
 *  - Bottom card-result tile reveals when a match lands
 *
 * Deferred (DECISIONS.md #043):
 *  - Image fingerprint (MediaPipe Image Embedder) — v2
 *  - Multi-card grid scan (OpenCV) — v2
 *  - Hero-name veto + multi-signal scoring — v2 once a hard case
 *    surfaces
 *
 * Permission flow: requested at first launch only. Denied path
 * surfaces a `BOBAEmptyState` with a settings deep-link.
 */
@Composable
fun ScanScreen(
    onBack: () -> Unit,
    onMatch: (bobaId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        )
    }
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
        onResult = { granted -> hasPermission = granted },
    )

    LaunchedEffect(Unit) {
        if (!hasPermission) launcher.launch(Manifest.permission.CAMERA)
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Scan") },
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
        if (hasPermission) {
            ScanViewfinder(
                onMatch = onMatch,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
        } else {
            BOBAEmptyState(
                icon = Icons.Default.CameraAlt,
                headline = "Camera access needed",
                body = "BOBA Playbook uses the camera to recognize printed card numbers on-device. Photos never leave your phone.",
                actionLabel = "Allow",
                onAction = { launcher.launch(Manifest.permission.CAMERA) },
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
        }
    }
}

@Composable
private fun ScanViewfinder(
    onMatch: (bobaId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val cardRepository: CardRepository = remember { ScanModuleAccess.cardRepository }
    val matcher = remember { ScanCardMatcher { cardRepository.cards.value } }
    var lastMatchedDisplayName by remember { mutableStateOf<String?>(null) }

    val controller = remember {
        LifecycleCameraController(context).apply {
            cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
        }
    }
    DisposableEffect(lifecycleOwner) {
        controller.bindToLifecycle(lifecycleOwner)
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        controller.setImageAnalysisAnalyzer(
            ContextCompat.getMainExecutor(context),
            MlKitAnalyzer(
                listOf(recognizer),
                COORDINATE_SYSTEM_VIEW_REFERENCED,
                ContextCompat.getMainExecutor(context),
            ) { result ->
                val text = result.getValue(recognizer) ?: return@MlKitAnalyzer
                val lines = text.textBlocks
                    .flatMap { block -> block.lines.map { it.text } }
                if (lines.isEmpty()) return@MlKitAnalyzer
                matcher.match(lines)?.let { matched ->
                    if (lastMatchedDisplayName != matched.displayName) {
                        lastMatchedDisplayName = matched.displayName
                        onMatch(matched.bobaId)
                    }
                }
            },
        )
        onDispose {
            controller.clearImageAnalysisAnalyzer()
            recognizer.close()
        }
    }

    Box(modifier = modifier) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx -> PreviewView(ctx).apply { setController(controller) } },
        )

        // Live result chip — appears once a card matches.
        lastMatchedDisplayName?.let { name ->
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
                    .align(Alignment.BottomCenter),
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "Recognized:",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Text(
                        text = name,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
        }
    }
}

/**
 * Tiny static accessor — M3 doesn't yet hoist the ScanViewfinder into
 * a Hilt-injected ViewModel because the CameraX `LifecycleCameraController`
 * needs a Composition-local LifecycleOwner that doesn't survive an
 * extra ViewModel layer cleanly. Pragmatic — refactored when M3.5
 * (queue review) ships.
 */
object ScanModuleAccess {
    lateinit var cardRepository: CardRepository
}

/**
 * Hilt entry-point wired at Activity level — `MainActivity` sets the
 * static accessor at app start so the Composable can read it without
 * threading a Hilt dependency through `AndroidView`.
 */
class ScanModuleAccessSeeder @Inject constructor(
    cardRepository: CardRepository,
) {
    init { ScanModuleAccess.cardRepository = cardRepository }
}
