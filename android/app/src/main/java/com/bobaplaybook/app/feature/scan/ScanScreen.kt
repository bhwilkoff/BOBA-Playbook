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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size as GSize
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.PhotoCameraFront
import androidx.compose.material.icons.filled.PhotoLibrary
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
import androidx.compose.runtime.saveable.rememberSaveable
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
import com.bobaplaybook.core.ui.components.BOBAIconTooltip
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

    // iOS-parity layout (ScanView.swift):
    //  • Camera fills the screen edge-to-edge
    //  • 140dp top gradient (65% black → transparent) shades the
    //    status bar + wordmark area without occluding the guide
    //  • 220dp bottom gradient (transparent → 75% black) shades
    //    the mode pills + detection chip area
    //  • Back + queue counter ride the top gradient
    //  • BOBAWordmark centered in the top chrome
    //  • Mode pills + (when a card is matched) detection chip
    //    ride the bottom gradient
    // Scan mode — SINGLE commits open the matched card immediately;
    // MULTI queues the card and stays in-frame so the user can scan
    // the next one without leaving the screen. iOS ScanView.modePill
    // toggles between these two same modes.
    var scanMode by rememberSaveable { mutableStateOf(ScanMode.SINGLE) }

    Box(modifier = modifier.fillMaxSize()) {
        if (hasPermission) {
            ScanViewfinder(
                scanMode = scanMode,
                onAutoQueue = { bobaId ->
                    // MULTI-mode auto-queue path. Append to the
                    // session queue and DON'T navigate; the user
                    // keeps scanning the next card.
                    android.util.Log.i(
                        "ScanScreen",
                        "onAutoQueue(bobaId=$bobaId) — appending to queue (sizeBefore=${queueHolder.queue.entries.value.size})",
                    )
                    queueHolder.queue.append(bobaId)
                    android.util.Log.i(
                        "ScanScreen",
                        "onAutoQueue done (sizeAfter=${queueHolder.queue.entries.value.size})",
                    )
                },
                onChipTap = { bobaId ->
                    // User explicitly tapped the detection chip —
                    // ALWAYS open the matched card (both modes).
                    android.util.Log.i("ScanScreen", "onChipTap(bobaId=$bobaId) — appending + forwarding to onMatch")
                    runCatching { queueHolder.queue.append(bobaId) }
                        .onFailure { android.util.Log.e("ScanScreen", "queue.append threw", it) }
                    runCatching { onMatch(bobaId) }
                        .onFailure { android.util.Log.e("ScanScreen", "outer onMatch threw", it) }
                },
                modifier = Modifier.fillMaxSize(),
            )

            // Top gradient — 140dp, 65% black → transparent
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(140.dp)
                    .background(
                        androidx.compose.ui.graphics.Brush.verticalGradient(
                            colors = listOf(
                                androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.65f),
                                androidx.compose.ui.graphics.Color.Transparent,
                            ),
                        ),
                    ),
            )
            // Top bar — back + centered BOBAWordmark + queue counter
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = androidx.compose.ui.graphics.Color.White,
                        )
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    if (queueEntries.isNotEmpty()) {
                        androidx.compose.material3.TextButton(
                            onClick = { reviewSheetOpen = true },
                        ) {
                            Text(
                                "Queue · ${queueEntries.size}",
                                color = androidx.compose.ui.graphics.Color.White,
                            )
                        }
                    } else {
                        // Visual balance — keep the wordmark centered
                        // even when no queue button is showing.
                        Spacer(modifier = Modifier.width(48.dp))
                    }
                }
                Box(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(top = 4.dp),
                ) {
                    com.bobaplaybook.core.ui.components.BOBAWordmark()
                }
            }

            // Bottom gradient — 220dp, transparent → 75% black
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(220.dp)
                    .align(Alignment.BottomCenter)
                    .background(
                        androidx.compose.ui.graphics.Brush.verticalGradient(
                            colors = listOf(
                                androidx.compose.ui.graphics.Color.Transparent,
                                androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.75f),
                            ),
                        ),
                    ),
            )

            // Mode pills — iOS ScanView.bottomControls. SINGLE +
            // MULTI; Grid is the deferred follow-up (#52).
            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 32.dp)
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                ScanModePill(
                    label = "SINGLE",
                    icon = Icons.Default.PhotoCameraFront,
                    selected = scanMode == ScanMode.SINGLE,
                    onClick = { scanMode = ScanMode.SINGLE },
                )
                ScanModePill(
                    label = "MULTI",
                    icon = Icons.Default.PhotoLibrary,
                    selected = scanMode == ScanMode.MULTI,
                    onClick = { scanMode = ScanMode.MULTI },
                )
            }
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
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            BOBAEmptyState(
                icon = Icons.Default.CameraAlt,
                headline = "Camera access needed",
                body = "BOBA Playbook uses the camera to recognize printed card numbers on-device. Photos never leave your phone.",
                actionLabel = "Allow",
                onAction = { launcher.launch(Manifest.permission.CAMERA) },
                modifier = Modifier.fillMaxSize(),
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
                                // Tick 426 — BOBAIconTooltip for hover/long-press
                                // affordance hint. Particularly useful here since
                                // the X icon in a list-row trailing slot can be
                                // mistaken for "close the sheet" — the tooltip
                                // clarifies "Remove this scan only".
                                BOBAIconTooltip("Remove from queue") {
                                    IconButton(onClick = { onRemove(entry.bobaId) }) {
                                        Icon(
                                            imageVector = Icons.Default.Close,
                                            contentDescription = "Remove from queue",
                                        )
                                    }
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

/** SINGLE = commit → user taps chip → open card detail. MULTI = commit
 *  → auto-queue + reset → keep scanning the next card without leaving. */
enum class ScanMode { SINGLE, MULTI }

/**
 * iOS-parity mode pill — icon + label, orange when selected, glass
 * when not. Mirrors iOS ScanView.modePill (single / multi / grid /
 * show). Grid is the deferred follow-up (#52).
 */
@Composable
private fun ScanModePill(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        color = if (selected) Color(0xFFFF4D00) else Color.Black.copy(alpha = 0.55f),
        shape = RoundedCornerShape(20.dp),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.width(16.dp).height(16.dp),
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = Color.White,
                letterSpacing = 1.sp,
            )
        }
    }
}

@Composable
private fun ScanViewfinder(
    scanMode: ScanMode,
    onAutoQueue: (bobaId: String) -> Unit,
    onChipTap: (bobaId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val cardRepository: CardRepository = remember { ScanModuleAccess.cardRepository }
    val matcher = remember { ScanCardMatcher { cardRepository.cards.value } }
    val stabilizer = remember { ScanFrameStabilizer() }
    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current
    // bobaId, not displayName — two distinct cards can share a display
    // name (Maverick base + Maverick battlefoil + Maverick alt-art all
    // render as "Maverick"). Deduplicating on displayName silently
    // dropped the second / third variant when the user scanned them
    // in sequence; the user saw the chip never update and assumed the
    // matcher had stalled. bobaId is the catalog's canonical
    // disambiguator (CLAUDE.md "One ID per Card") so we dedupe on it.
    var lastMatchedBobaId by remember { mutableStateOf<String?>(null) }
    var scanState by remember { mutableStateOf<ScanFrameStabilizer.State>(ScanFrameStabilizer.State.Idle) }
    // Most-recent committed match — drives the detection chip + the
    // guide-frame element-coloured stroke. Declared BEFORE the
    // analyzer setup so the analyzer closure captures it.
    var detectedCard by remember { mutableStateOf<com.bobaplaybook.core.domain.model.Card?>(null) }
    // rememberUpdatedState — analyzer closure binds once but reads
    // the CURRENT scanMode on every fire. Without this, the closure
    // captures the initial SINGLE value and toggling MULTI in the UI
    // doesn't reach the auto-queue branch. Ben 2026-05-22: "multi-scan
    // does not queue any cards." Same pattern for the callbacks so
    // late-passed lambdas aren't lost either.
    val currentScanMode by androidx.compose.runtime.rememberUpdatedState(scanMode)
    val currentOnAutoQueue by androidx.compose.runtime.rememberUpdatedState(onAutoQueue)

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
                if (stable != null && lastMatchedBobaId != stable.card.bobaId) {
                    lastMatchedBobaId = stable.card.bobaId
                    // Set the detection chip card on every commit
                    // (both modes). MULTI also auto-queues; SINGLE
                    // waits for the user to tap the chip. Reads
                    // currentScanMode (rememberUpdatedState) so a
                    // late toggle to MULTI does fire the auto-queue.
                    detectedCard = stable.card
                    android.util.Log.i(
                        "ScanViewfinder",
                        "Committed match: ${stable.card.displayName} (${stable.card.bobaId}) mode=$currentScanMode",
                    )
                    // Haptic on commit — physical confirmation that
                    // the matcher landed on a card. iOS uses a similar
                    // success-style haptic on the scan commit moment.
                    // LongPress maps to a single short pulse on Android
                    // — close to the iOS UIImpactFeedbackGenerator
                    // (.medium) feel without needing platform-specific
                    // tuning.
                    haptic.performHapticFeedback(
                        androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress
                    )
                    if (currentScanMode == ScanMode.MULTI) {
                        currentOnAutoQueue(stable.card.bobaId)
                    }
                }
            },
        )
        onDispose {
            android.util.Log.i("ScanViewfinder", "onDispose — clearing analyzer + closing ML Kit recognizer (background)")
            // Clear the analyzer first (synchronous, fast). The ML Kit
            // recognizer.close() releases native resources and can block
            // for tens of ms; defer to a background dispatcher so we
            // don't compete with the simultaneous Compose navigation
            // that happens right after a chip tap (Ben's "app
            // quits/crashes on chip tap" — the prior logcat showed
            // Activity pause-timeout, classic main-thread blocking).
            runCatching { controller.clearImageAnalysisAnalyzer() }
                .onFailure { android.util.Log.e("ScanViewfinder", "clearImageAnalysisAnalyzer threw", it) }
            kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                runCatching { recognizer.close() }
                    .onFailure { android.util.Log.e("ScanViewfinder", "recognizer.close threw", it) }
            }
        }
    }

    // Auto-clear the detection chip in MULTI mode after 1.6s so the
    // user sees they can scan the next card. SINGLE mode keeps the
    // chip visible until the user taps it (or scans a different card).
    LaunchedEffect(detectedCard, scanMode) {
        if (detectedCard != null && scanMode == ScanMode.MULTI) {
            kotlinx.coroutines.delay(1600)
            // Reset stabilizer so the next commit re-fires the chip.
            stabilizer.reset()
            lastMatchedBobaId = null
            detectedCard = null
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

        // Guide overlay — element-coloured stroke when a card is
        // committed (iOS swaps from orange → weapon colour). Default
        // is BOBA orange.
        val accent = detectedCard?.let { c ->
            com.bobaplaybook.core.ui.theme.BobaElements.forElement(c.element.uppercase())
        } ?: Color(0xFFFF4D00)
        ScanGuideOverlay(
            modifier = Modifier.fillMaxSize(),
            accentColor = accent,
        )

        // Bottom detection chip — only renders on a committed match
        // (per ScanFrameStabilizer). The verbose "Scoring N/M" /
        // "Ready" / "Scanning…" mid-frame status text was the
        // "misfires (card not found)" leakage Ben flagged — those
        // states no longer show, only the final committed card.
        val committed = detectedCard
        if (committed != null) {
            ScanDetectionChip(
                card = committed,
                onTap = { onChipTap(committed.bobaId) },
                // Pin to ~96dp above the bottom (clears the mode
                // pills row that lives in the parent at 32dp from
                // bottom).
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 96.dp)
                    .align(Alignment.BottomCenter),
            )
        }
    }
}

/**
 * Bottom detection chip — mirrors iOS ScanDetectionChipView.
 * Renders the matched card's thumbnail + name + weapon · power
 * caption with a tap-to-open arrow. Quick-save (+ quantity)
 * deferred to follow-up; the tap-to-open path is enough for the
 * first cut.
 */
@Composable
private fun ScanDetectionChip(
    card: com.bobaplaybook.core.domain.model.Card,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.clickable { onTap() },
        color = Color.Black.copy(alpha = 0.78f),
        shape = RoundedCornerShape(14.dp),
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val thumb = com.bobaplaybook.core.network.CDN.thumbUrl(card)
            coil3.compose.AsyncImage(
                model = thumb,
                contentDescription = null,
                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                modifier = Modifier
                    .width(44.dp)
                    .height(62.dp)
                    .clip(RoundedCornerShape(4.dp)),
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    card.displayName,
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                )
                val caption = listOfNotNull(
                    card.element.takeIf { it.isNotBlank() }?.uppercase(),
                    card.power?.takeIf { it > 0 }?.let { "⚡$it" },
                    card.cardNumber.takeIf { it.isNotBlank() },
                ).joinToString(" · ")
                if (caption.isNotBlank()) {
                    Text(
                        caption,
                        style = MaterialTheme.typography.labelMedium,
                        color = Color.White.copy(alpha = 0.72f),
                    )
                }
            }
        }
    }
}

/**
 * Card guide overlay matching iOS ScanView.cardGuideFrame:
 *  • 5:7 aspect rounded rect centered on screen (with a vertical
 *    offset upward so the bottom controls don't crowd the guide)
 *  • Dimmed surround (35% black) outside the guide, cut out via
 *    Canvas band-rects rather than alpha masks (Compose doesn't
 *    have luminanceToAlpha)
 *  • 2px element-coloured stroke around the guide — orange when
 *    no detection, weapon-coloured when a card is detected
 *  • Four corner accent marks (L-shaped) at the guide's corners
 *  • Tilt hint below the guide ("TILT PHONE SLIGHTLY FOR GLOSSY
 *    CARDS"), faint-white
 */
@Composable
private fun ScanGuideOverlay(
    modifier: Modifier = Modifier,
    accentColor: Color = Color(0xFFFF4D00),  // BOBA orange — iOS default when no detection
) {
    Box(modifier = modifier) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height
            val cardW = w * 0.75f
            val cardH = cardW * 7f / 5f
            val finalW: Float; val finalH: Float
            if (cardH > h * 0.62f) {
                finalH = h * 0.62f
                finalW = finalH * 5f / 7f
            } else {
                finalW = cardW
                finalH = cardH
            }
            val left = (w - finalW) / 2f
            val top = (h - finalH) / 2f - h * 0.04f

            val dim = Color.Black.copy(alpha = 0.35f)
            drawRect(color = dim, topLeft = Offset(0f, 0f), size = GSize(w, top))
            drawRect(color = dim, topLeft = Offset(0f, top + finalH), size = GSize(w, h - top - finalH))
            drawRect(color = dim, topLeft = Offset(0f, top), size = GSize(left, finalH))
            drawRect(color = dim, topLeft = Offset(left + finalW, top), size = GSize(w - left - finalW, finalH))

            // Element-coloured stroke (transitions on detection)
            drawRoundRect(
                color = accentColor,
                topLeft = Offset(left, top),
                size = GSize(finalW, finalH),
                cornerRadius = CornerRadius(28f, 28f),
                style = Stroke(width = 5f),
            )

            // Four corner accent marks (L-shapes ~22dp). Matches iOS
            // CornerMark — short legs pointing inward from each
            // guide corner.
            val markLen = 28f
            val markStroke = 4f
            val accent = accentColor
            // TL
            drawLine(accent, Offset(left, top + markLen), Offset(left, top), strokeWidth = markStroke)
            drawLine(accent, Offset(left, top), Offset(left + markLen, top), strokeWidth = markStroke)
            // TR
            drawLine(accent, Offset(left + finalW - markLen, top), Offset(left + finalW, top), strokeWidth = markStroke)
            drawLine(accent, Offset(left + finalW, top), Offset(left + finalW, top + markLen), strokeWidth = markStroke)
            // BL
            drawLine(accent, Offset(left, top + finalH - markLen), Offset(left, top + finalH), strokeWidth = markStroke)
            drawLine(accent, Offset(left, top + finalH), Offset(left + markLen, top + finalH), strokeWidth = markStroke)
            // BR
            drawLine(accent, Offset(left + finalW - markLen, top + finalH), Offset(left + finalW, top + finalH), strokeWidth = markStroke)
            drawLine(accent, Offset(left + finalW, top + finalH), Offset(left + finalW, top + finalH - markLen), strokeWidth = markStroke)
        }

        // Tilt hint below the guide — iOS ScanView line 170.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(240.dp))
            Text(
                text = "TILT PHONE SLIGHTLY FOR GLOSSY CARDS",
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.5f),
                letterSpacing = 1.sp,
            )
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
