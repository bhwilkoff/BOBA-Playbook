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
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.draw.clip
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size as GSize
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
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
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
    val activity = (context as? android.app.Activity)
    // Scan queue — every successful match also lands in a session-
    // scoped log so the user can review what they've identified.
    // Parity with iOS DESIGN.md §6.5 (.tabViewBottomAccessory →
    // ScanReviewView).
    val queueHolder: ScanQueueHolderViewModel =
        androidx.hilt.navigation.compose.hiltViewModel()
    val queueEntries by queueHolder.queue.entries
        .collectAsStateWithLifecycle()
    var reviewSheetOpen by androidx.compose.runtime.saveable.rememberSaveable {
        mutableStateOf(false)
    }
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        )
    }
    // Track whether we've asked at least once. shouldShowRationale
    // returns false BOTH before the first ask AND after permanent
    // denial — without this guard those two cases look identical.
    var hasBeenAsked by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
        onResult = { granted ->
            hasPermission = granted
            hasBeenAsked = true
        },
    )

    LaunchedEffect(Unit) {
        if (!hasPermission) launcher.launch(Manifest.permission.CAMERA)
    }

    // Permanent denial heuristic: user has been asked, permission still
    // denied, and the system says we can't show the rationale → the
    // launcher will no-op silently. Surface a Settings deep-link
    // instead of an Allow button that doesn't do anything.
    val permanentlyDenied = hasBeenAsked && !hasPermission && activity != null &&
        !androidx.core.app.ActivityCompat.shouldShowRequestPermissionRationale(
            activity, Manifest.permission.CAMERA,
        )

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
                actions = {
                    if (queueEntries.isNotEmpty()) {
                        androidx.compose.material3.TextButton(
                            onClick = { reviewSheetOpen = true },
                        ) {
                            Text("Recent · ${queueEntries.size}")
                        }
                    }
                },
            )
        },
    ) { padding ->
        if (hasPermission) {
            ScanViewfinder(
                onMatch = { bobaId ->
                    // Log every match to the session queue first, then
                    // route via the existing onMatch callback. The
                    // queue is a parallel surface — doesn't change the
                    // single-shot routing flow.
                    queueHolder.queue.append(bobaId)
                    onMatch(bobaId)
                },
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
        } else if (permanentlyDenied) {
            BOBAEmptyState(
                icon = Icons.Default.CameraAlt,
                headline = "Camera access blocked",
                body = "You previously denied camera access. Open Settings to allow BOBA Playbook to use the camera.",
                actionLabel = "Open Settings",
                onAction = {
                    val intent = android.content.Intent(
                        android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        android.net.Uri.fromParts("package", context.packageName, null),
                    ).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                },
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

    if (reviewSheetOpen) {
        ScanReviewSheet(
            entries = queueEntries,
            cardRepository = queueHolder.cardRepository,
            onTap = { bobaId ->
                reviewSheetOpen = false
                onMatch(bobaId)
            },
            onRemove = { bobaId -> queueHolder.queue.remove(bobaId) },
            onClearAll = { queueHolder.queue.clear(); reviewSheetOpen = false },
            onDismiss = { reviewSheetOpen = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScanReviewSheet(
    entries: List<ScanQueueStore.Entry>,
    cardRepository: com.bobaplaybook.core.data.catalog.CardRepository,
    onTap: (bobaId: String) -> Unit,
    onRemove: (bobaId: String) -> Unit,
    onClearAll: () -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val cards by cardRepository.cards.collectAsStateWithLifecycle()
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    "Recent scans · ${entries.size}",
                    style = MaterialTheme.typography.titleMedium,
                )
                if (entries.isNotEmpty()) {
                    TextButton(onClick = onClearAll) {
                        Text("Clear all")
                    }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            if (entries.isEmpty()) {
                Text(
                    "No scans this session yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(
                        items = entries,
                        key = { entry -> entry.bobaId },
                    ) { entry ->
                        val card = cards.firstOrNull { c -> c.bobaId == entry.bobaId }
                        ListItem(
                            leadingContent = {
                                // Tick 224 — card thumbnail (iOS ScanQueueView
                                // parity, ScanQueueView.swift:112). 36x50 thumb
                                // gives the user faster recognition than just
                                // text — same affordance as Find grid cells.
                                val thumb = card?.let {
                                    com.bobaplaybook.core.network.CDN.thumbUrl(it)
                                }
                                if (thumb != null) {
                                    coil3.compose.AsyncImage(
                                        model = thumb,
                                        contentDescription = null,
                                        contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                                        modifier = Modifier
                                            .width(36.dp)
                                            .height(50.dp)
                                            .clip(androidx.compose.foundation.shape.RoundedCornerShape(4.dp)),
                                    )
                                } else {
                                    Box(
                                        modifier = Modifier
                                            .width(36.dp)
                                            .height(50.dp)
                                            .background(
                                                MaterialTheme.colorScheme.surfaceContainerHigh,
                                                androidx.compose.foundation.shape.RoundedCornerShape(4.dp),
                                            )
                                    )
                                }
                            },
                            headlineContent = { Text(card?.displayName ?: entry.bobaId) },
                            supportingContent = {
                                val sub = listOfNotNull(
                                    card?.cardNumber,
                                    card?.hero?.takeIf { it.isNotBlank() },
                                ).joinToString(" · ")
                                if (sub.isNotBlank()) Text(sub)
                            },
                            trailingContent = {
                                IconButton(onClick = { onRemove(entry.bobaId) }) {
                                    Icon(
                                        imageVector = Icons.Default.Close,
                                        contentDescription = "Remove from queue",
                                    )
                                }
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onTap(entry.bobaId) },
                        )
                        HorizontalDivider()
                    }
                }
            }
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
    val stabilizer = remember { ScanFrameStabilizer() }
    var lastMatchedDisplayName by remember { mutableStateOf<String?>(null) }
    var scanState by remember { mutableStateOf<ScanFrameStabilizer.State>(ScanFrameStabilizer.State.Idle) }

    val controller = remember {
        LifecycleCameraController(context).apply {
            cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
        }
    }
    // PreviewView dimensions for top-left-quadrant detection. The
    // MlKitAnalyzer maps text-block bounds into VIEW-REFERENCED
    // coordinates, so frameWidth/Height is the PreviewView size.
    var previewW by remember { mutableStateOf(1) }
    var previewH by remember { mutableStateOf(1) }
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
                if (text.textBlocks.isEmpty()) return@MlKitAnalyzer

                // Build the per-LINE token list with bounding boxes so
                // ScanCardMatcher can apply iOS DECISIONS.md #035's
                // hero-name top-left detection.
                val tokens = text.textBlocks.flatMap { block ->
                    block.lines.mapNotNull { line ->
                        val bbox = line.boundingBox ?: return@mapNotNull null
                        ScanTextToken(
                            text = line.text,
                            frame = bbox,
                            frameWidth = previewW,
                            frameHeight = previewH,
                        )
                    }
                }
                if (tokens.isEmpty()) return@MlKitAnalyzer

                val perFrame = matcher.match(tokens)
                // Push every frame (including misses) through the
                // stabilizer so the de-dupe gate sees the gaps.
                val stable = stabilizer.push(perFrame)
                scanState = stabilizer.state
                if (stable != null && lastMatchedDisplayName != stable.card.displayName) {
                    lastMatchedDisplayName = stable.card.displayName
                    onMatch(stable.card.bobaId)
                }
            },
        )
        onDispose {
            controller.clearImageAnalysisAnalyzer()
            recognizer.close()
        }
    }

    Box(
        modifier = modifier.onSizeChanged { size ->
            previewW = size.width
            previewH = size.height
        },
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx -> PreviewView(ctx).apply { setController(controller) } },
        )

        // iOS-parity overlay: 5:7 aspect guide rectangle with corner
        // hint text below. Always visible — no card on screen = idle
        // state; user needs to know where to aim.
        ScanGuideOverlay(
            modifier = Modifier.fillMaxSize(),
        )

        // First-run hint — "hold steady for ~2s". Permanently
        // dismissible per HintsStore. Renders only before first
        // commit so it doesn't compete with the status chip.
        val hintsViewModel: com.bobaplaybook.app.hints.HintsViewModel =
            androidx.hilt.navigation.compose.hiltViewModel()
        val scanHintDismissed by hintsViewModel
            .isDismissed(com.bobaplaybook.app.hints.HintsStore.Ids.SCAN_HOLD_STEADY)
            .collectAsStateWithLifecycle(initialValue = true)
        if (!scanHintDismissed && lastMatchedDisplayName == null) {
            Box(
                modifier = Modifier.fillMaxSize().padding(top = 16.dp),
                contentAlignment = Alignment.TopCenter,
            ) {
                com.bobaplaybook.core.ui.components.BOBAHintBanner(
                    title = "Hold steady",
                    body = "Frame one card inside the rectangle and keep the phone still for ~2 seconds. BOBA reads the card number and hero name on-device.",
                    onDismiss = {
                        hintsViewModel.dismiss(com.bobaplaybook.app.hints.HintsStore.Ids.SCAN_HOLD_STEADY)
                    },
                )
            }
        }

        // Live status chip — surfaces in-progress scoring AND the
        // committed match, so the user always sees something happening.
        ScanStatusChip(
            state = scanState,
            committedName = lastMatchedDisplayName,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
                .align(Alignment.BottomCenter),
        )
    }
}

/**
 * 5:7 aspect guide rect centered on screen with a dimmed surround
 * (drawn as four rects around the cutout) and a "Position card inside
 * the frame" hint. Mirrors iOS ScanView's guide overlay.
 */
@Composable
private fun ScanGuideOverlay(modifier: Modifier = Modifier) {
    Box(modifier = modifier) {
        // Compute the guide rect once; reuse for shadow + stroke + hint placement
        Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height
            val cardW = w * 0.7f
            val cardH = cardW * 7f / 5f
            val finalW: Float; val finalH: Float
            if (cardH > h * 0.65f) {
                finalH = h * 0.65f
                finalW = finalH * 5f / 7f
            } else {
                finalW = cardW
                finalH = cardH
            }
            val left = (w - finalW) / 2f
            val top = (h - finalH) / 2f - h * 0.04f

            val dim = Color.Black.copy(alpha = 0.50f)
            // Top band
            drawRect(color = dim, topLeft = Offset(0f, 0f), size = GSize(w, top))
            // Bottom band
            drawRect(color = dim, topLeft = Offset(0f, top + finalH), size = GSize(w, h - top - finalH))
            // Left band
            drawRect(color = dim, topLeft = Offset(0f, top), size = GSize(left, finalH))
            // Right band
            drawRect(color = dim, topLeft = Offset(left + finalW, top), size = GSize(w - left - finalW, finalH))

            // Cyan stroke around guide
            drawRoundRect(
                color = Color(0xFF00F5FF),
                topLeft = Offset(left, top),
                size = GSize(finalW, finalH),
                cornerRadius = CornerRadius(20f, 20f),
                style = Stroke(width = 6f),
            )
        }

        // Hint pill — anchored below center
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(200.dp))
            Surface(
                color = Color.Black.copy(alpha = 0.6f),
                shape = RoundedCornerShape(20.dp),
            ) {
                Text(
                    text = "Position card inside the frame",
                    style = MaterialTheme.typography.labelLarge,
                    color = Color.White,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }
}

/** Renders the scoring + committed-match states from the stabilizer. */
@Composable
private fun ScanStatusChip(
    state: ScanFrameStabilizer.State,
    committedName: String?,
    modifier: Modifier = Modifier,
) {
    val (label, body, container) = when {
        committedName != null -> Triple(
            "Recognized",
            committedName,
            MaterialTheme.colorScheme.primaryContainer,
        )
        state is ScanFrameStabilizer.State.Scoring -> Triple(
            "Scoring ${state.agreements}/${state.required}",
            "${state.card.displayName} · ${"%.1f".format(state.avgScore)}",
            MaterialTheme.colorScheme.secondaryContainer,
        )
        state is ScanFrameStabilizer.State.Scanning -> Triple(
            "Scanning…",
            "Hold a card in view",
            MaterialTheme.colorScheme.surfaceContainerHigh,
        )
        // Idle — still show feedback so the user knows the camera is
        // active. Without this the screen looks frozen between scans.
        else -> Triple(
            "Ready",
            "Hold a card inside the frame",
            MaterialTheme.colorScheme.surfaceContainerHigh,
        )
    }
    Surface(modifier = modifier, color = container) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
            )
            Text(
                text = body,
                style = MaterialTheme.typography.titleMedium,
            )
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
