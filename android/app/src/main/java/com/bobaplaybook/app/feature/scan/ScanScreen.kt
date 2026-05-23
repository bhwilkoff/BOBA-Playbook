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
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FlashOn
import androidx.compose.material.icons.filled.FlashOff
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size as GSize
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.PhotoCameraFront
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.KeyboardArrowUp
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
    // iOS-parity scan-save toast: top-anchored Surface card with a
    // checkmark / exclamation icon + message, replacing the bottom
    // Snackbar used previously. iOS uses an overlay(.top) chip (see
    // ScanView.swift quickSaveToast block ~line 105). The bottom
    // Snackbar competed visually with the mode pills + detection
    // chip area; the top toast frames the "Saved" confirmation as
    // a heads-up event without crowding the controls.
    var scanToastMessage by remember { mutableStateOf<String?>(null) }
    var scanToastIsError by remember { mutableStateOf(false) }
    // Torch state for shiny-card recovery. Direct phone light
    // overpowers ambient reflections on glow / holographic prints
    // (DEKAP GGL-779 class) where AE biases toward the bright
    // shimmer and washes out the printed text. Off by default —
    // dark cards don't need flash and most non-shiny scans don't
    // either. Lifted to ScanScreen so the top-bar IconButton can
    // toggle it; passed into ScanViewfinder which applies it to
    // the LifecycleCameraController via LaunchedEffect.
    var torchEnabled by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(scanToastMessage) {
        if (scanToastMessage != null) {
            kotlinx.coroutines.delay(2000)
            scanToastMessage = null
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        if (hasPermission) {
            ScanViewfinder(
                scanMode = scanMode,
                torchEnabled = torchEnabled,
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
                onSaveToast = { msg, isError ->
                    scanToastMessage = msg
                    scanToastIsError = isError
                },
                onChipTap = { bobaId ->
                    // User tapped the detection chip → open the
                    // matched card. Do NOT append to the queue here:
                    //  • MULTI mode already auto-queued at commit
                    //    time (line ~647 currentOnAutoQueue), so a
                    //    chip-tap append would double-count if the
                    //    user is faster than the 1.6s auto-clear.
                    //  • SINGLE mode never queues; tap just opens
                    //    detail (iOS parity — ScanView.swift onTap
                    //    sets selectedCard + scanner.resetDetection,
                    //    no queue mutation).
                    android.util.Log.i("ScanScreen", "onChipTap(bobaId=$bobaId) — forwarding to onMatch")
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
                        // Asymmetric padding: extra 12dp on the right
                        // so the queue badge's offset has breathing
                        // room. On Pixel 8a (small bezels, 5.85" 1080×
                        // 2400) the prior symmetric 4dp clipped the
                        // badge's top-right corner. 16dp trailing
                        // keeps the badge inside the safe area on
                        // every phone we'd realistically ship to.
                        .padding(start = 4.dp, end = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = androidx.compose.ui.graphics.Color.White,
                        )
                    }
                    // Torch toggle for shiny / holographic card recovery
                    // (DEKAP GGL-779 class). AE on glow prints biases
                    // toward the bright shimmer and washes out the
                    // printed text — direct phone light overpowers
                    // ambient reflections and lets the camera see real
                    // contrast. Tinted orange when on so it's obvious.
                    IconButton(onClick = { torchEnabled = !torchEnabled }) {
                        Icon(
                            imageVector = if (torchEnabled)
                                Icons.Default.FlashOn
                            else
                                Icons.Default.FlashOff,
                            contentDescription = if (torchEnabled)
                                "Turn flashlight off"
                            else
                                "Turn flashlight on for shiny cards",
                            tint = if (torchEnabled)
                                androidx.compose.ui.graphics.Color(0xFFFF4D00)
                            else
                                androidx.compose.ui.graphics.Color.White,
                        )
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    // iOS-parity queue affordance — tray icon w/ small
                    // orange circle badge top-right showing the count.
                    // Only renders when MULTI mode AND queue is non-
                    // empty (matches iOS ScanView.swift:243). SINGLE
                    // mode opens cards directly so the queue stays
                    // empty + the tray would only confuse.
                    if (scanMode == ScanMode.MULTI && queueEntries.isNotEmpty()) {
                        // Accessibility: merge the icon + badge into a
                        // single semantic node so TalkBack reads
                        // "Review scan queue, 3 cards" rather than two
                        // disjoint utterances. Icon + Text inner
                        // contentDescription is cleared since the
                        // IconButton's semantics carry the label.
                        val queueCount = queueEntries.size
                        IconButton(
                            onClick = { reviewSheetOpen = true },
                            modifier = Modifier.semantics(mergeDescendants = true) {
                                contentDescription =
                                    "Review scan queue, $queueCount card" +
                                        if (queueCount == 1) "" else "s"
                            },
                        ) {
                            Box(contentAlignment = Alignment.TopEnd) {
                                Icon(
                                    imageVector = Icons.Default.Inventory2,
                                    contentDescription = null,
                                    tint = androidx.compose.ui.graphics.Color.White,
                                    modifier = Modifier.width(22.dp).height(22.dp),
                                )
                                androidx.compose.material3.Surface(
                                    shape = androidx.compose.foundation.shape.CircleShape,
                                    color = androidx.compose.ui.graphics.Color(0xFFFF4D00),
                                    modifier = Modifier
                                        // Smaller offset so the badge
                                        // mostly overlaps the icon
                                        // corner rather than spilling
                                        // past the IconButton bounds.
                                        // Combined with the Row's 16dp
                                        // trailing padding (above), no
                                        // device clips the badge.
                                        .offset(x = 4.dp, y = (-4).dp)
                                        .defaultMinSize(minWidth = 18.dp, minHeight = 18.dp),
                                ) {
                                    Text(
                                        text = "$queueCount",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = androidx.compose.ui.graphics.Color.White,
                                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                                        modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
                                    )
                                }
                            }
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

            // iOS-parity scan-save toast — top-anchored, surface-card
            // style, green check / red exclamation icon. Renders ABOVE
            // the gradient + top bar so it's clearly visible. Auto-
            // dismisses via LaunchedEffect at the top of the function.
            androidx.compose.animation.AnimatedVisibility(
                visible = scanToastMessage != null,
                enter = androidx.compose.animation.slideInVertically(initialOffsetY = { -it }) +
                    androidx.compose.animation.fadeIn(),
                exit = androidx.compose.animation.slideOutVertically(targetOffsetY = { -it }) +
                    androidx.compose.animation.fadeOut(),
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(top = 60.dp, start = 16.dp, end = 16.dp),
            ) {
                val msg = scanToastMessage ?: return@AnimatedVisibility
                androidx.compose.material3.Surface(
                    color = androidx.compose.ui.graphics.Color(0xFF1A1A24),
                    shape = RoundedCornerShape(12.dp),
                    border = androidx.compose.foundation.BorderStroke(
                        1.dp,
                        androidx.compose.ui.graphics.Color.White.copy(alpha = 0.18f),
                    ),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(
                            imageVector = if (scanToastIsError)
                                Icons.Default.ErrorOutline
                            else
                                Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = if (scanToastIsError)
                                androidx.compose.ui.graphics.Color(0xFFC0392B)
                            else
                                androidx.compose.ui.graphics.Color(0xFF4CAF50),
                            modifier = Modifier.width(20.dp).height(20.dp),
                        )
                        Text(
                            text = msg,
                            style = MaterialTheme.typography.bodyMedium,
                            color = androidx.compose.ui.graphics.Color.White,
                        )
                    }
                }
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

    // Coroutine scope for bulk save — survives sheet close so a long
    // batch insert keeps writing even if the user dismisses the sheet
    // mid-flight (the queue is cleared optimistically, write-failures
    // surface via the toast).
    val bulkSaveScope = androidx.compose.runtime.rememberCoroutineScope()
    // Saving-spinner state. iOS shows "Saving…" + ProgressView during
    // the loop (ScanQueueView.swift saveAllLabel). Android matches by
    // disabling the CTA + swapping the label while bulkSaveInProgress.
    var bulkSaveInProgress by remember { mutableStateOf(false) }
    if (reviewSheetOpen) {
        ScanReviewSheet(
            entries = queueEntries,
            cardRepository = queueHolder.cardRepository,
            onTap = { bobaId ->
                reviewSheetOpen = false
                onMatch(bobaId)
            },
            onRemove = { bobaId -> queueHolder.queue.remove(bobaId) },
            onSetQuantity = { bobaId, qty -> queueHolder.queue.setQuantity(bobaId, qty) },
            onClearAll = { queueHolder.queue.clear(); reviewSheetOpen = false },
            saveAllInProgress = bulkSaveInProgress,
            onSaveAll = {
                // iOS-parity bulk save (ScanQueueView.swift
                // saveAllToCollection). Snapshot entries first, then
                // loop: for each row, insert `quantity` user_card rows
                // — matches the iOS pattern of one row per physical
                // copy (DECISIONS.md user_cards is the row-per-copy
                // table). Designation defaults to Personal; future
                // iters can add a designation picker.
                val snapshot = queueEntries
                val totalCopies = snapshot.sumOf { it.quantity }
                // Build an O(1) bobaId→Card lookup ONCE before the
                // coroutine launches. Prior code did O(N) `firstOrNull`
                // per entry — 25 entries × 17k catalog = ~425k
                // iterations on every Save tap. Catalog is also
                // snapshotted here so a mid-flight refresh doesn't
                // shift the lookup target.
                val catalogByBobaId = queueHolder.cardRepository.cards.value
                    .associateBy { it.bobaId }
                bulkSaveScope.launch {
                    bulkSaveInProgress = true
                    try {
                    val auth = ScanModuleAccess.authManager.authState.first()
                    val userId = (auth as? com.bobaplaybook.app.auth.AuthState.SignedIn)?.userId
                    if (userId == null) {
                        scanToastMessage = "Sign in to save $totalCopies card${if (totalCopies == 1) "" else "s"}"
                        scanToastIsError = true
                        return@launch
                    }
                    var firstError: String? = null
                    for (entry in snapshot) {
                        // Look the card up in the catalog for the
                        // canonical cardNumber. The prior code's
                        // `bobaId.substringBefore('-')` was WRONG for
                        // any cardNumber containing a dash (e.g.
                        // "BHBF-37" → it returned "BHBF" instead of
                        // "BHBF-37"). bobaId format is
                        // `{cardNumber}-{hero}-{treatment}-{variation}`
                        // and reverse-parsing is ambiguous since
                        // cardNumbers can themselves contain dashes.
                        // The Card object holds the canonical string.
                        val card = catalogByBobaId[entry.bobaId]
                        val cardNumber = card?.cardNumber.orEmpty()
                            .ifEmpty { entry.bobaId.substringBefore('-') }
                        repeat(entry.quantity.coerceIn(1, 99)) {
                            try {
                                ScanModuleAccess.collectionRepository.add(
                                    cardBobaId = entry.bobaId,
                                    cardNumber = cardNumber,
                                    designation = com.bobaplaybook.core.domain.model.Designation.PERSONAL,
                                    userId = userId,
                                )
                            } catch (t: Throwable) {
                                if (firstError == null) firstError = t.message ?: t.javaClass.simpleName
                            }
                        }
                    }
                    if (firstError == null) {
                        scanToastMessage =
                            "Saved $totalCopies card${if (totalCopies == 1) "" else "s"} to Personal"
                        scanToastIsError = false
                        queueHolder.queue.clear()
                        reviewSheetOpen = false
                    } else {
                        scanToastMessage = "Save failed: $firstError"
                        scanToastIsError = true
                    }
                    } finally {
                        // Clear the in-progress flag no matter how the
                        // save resolves — success, signed-out early
                        // return, or a Throwable bubbling from
                        // collectionRepository.add(). Without finally
                        // a thrown exception would leave the CTA
                        // permanently disabled.
                        bulkSaveInProgress = false
                    }
                }
            },
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
    onSetQuantity: (bobaId: String, quantity: Int) -> Unit,
    onClearAll: () -> Unit,
    saveAllInProgress: Boolean,
    onSaveAll: () -> Unit,
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
                LazyColumn(modifier = Modifier.weight(1f)) {
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
                            headlineContent = {
                                // iOS-parity "×N" quantity suffix when the
                                // queue collapsed multiple scans of the
                                // same card into one row (Whatnot box-
                                // break workflow). Subtle — only appears
                                // when quantity > 1.
                                val name = card?.displayName ?: entry.bobaId
                                Text(
                                    text = if (entry.quantity > 1)
                                        "$name  ×${entry.quantity}"
                                    else name,
                                )
                            },
                            supportingContent = {
                                val sub = listOfNotNull(
                                    card?.cardNumber,
                                    card?.hero?.takeIf { it.isNotBlank() },
                                ).joinToString(" · ")
                                if (sub.isNotBlank()) Text(sub)
                            },
                            trailingContent = {
                                // iOS-parity quantity stepper + remove.
                                // ScanQueueView.swift renders a −/+ pill
                                // next to the trash button on every row.
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(0.dp),
                                ) {
                                    IconButton(
                                        onClick = {
                                            if (entry.quantity > 1) {
                                                onSetQuantity(entry.bobaId, entry.quantity - 1)
                                            }
                                        },
                                        enabled = entry.quantity > 1,
                                        modifier = Modifier.width(28.dp).height(28.dp),
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Remove,
                                            contentDescription = "Decrement quantity",
                                        )
                                    }
                                    Text(
                                        text = "${entry.quantity}",
                                        style = MaterialTheme.typography.titleSmall,
                                        modifier = Modifier.width(22.dp),
                                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                                    )
                                    IconButton(
                                        onClick = {
                                            if (entry.quantity < 99) {
                                                onSetQuantity(entry.bobaId, entry.quantity + 1)
                                            }
                                        },
                                        enabled = entry.quantity < 99,
                                        modifier = Modifier.width(28.dp).height(28.dp),
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Add,
                                            contentDescription = "Increment quantity",
                                        )
                                    }
                                    // Tick 426 — BOBAIconTooltip clarifies
                                    // "remove this scan, not the sheet".
                                    BOBAIconTooltip("Remove from queue") {
                                        IconButton(onClick = { onRemove(entry.bobaId) }) {
                                            Icon(
                                                imageVector = Icons.Default.Close,
                                                contentDescription = "Remove from queue",
                                                tint = androidx.compose.ui.graphics.Color(0xFFC0392B)
                                                    .copy(alpha = 0.8f),
                                            )
                                        }
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
                // iOS-parity bulk save (ScanQueueView.swift
                // saveAllButton at line ~366). Full-width orange CTA
                // pinned below the list. Disabled state isn't needed —
                // the button only renders when entries.isNotEmpty(),
                // so this only ever shows with ≥1 card to save.
                val totalCopies = entries.sumOf { it.quantity }
                Button(
                    onClick = onSaveAll,
                    enabled = !saveAllInProgress,
                    colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                        containerColor = androidx.compose.ui.graphics.Color(0xFFFF4D00),
                        contentColor = androidx.compose.ui.graphics.Color.White,
                        disabledContainerColor = androidx.compose.ui.graphics.Color(0xFFFF4D00)
                            .copy(alpha = 0.6f),
                        disabledContentColor = androidx.compose.ui.graphics.Color.White
                            .copy(alpha = 0.85f),
                    ),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp, bottom = 8.dp),
                ) {
                    if (saveAllInProgress) {
                        androidx.compose.material3.CircularProgressIndicator(
                            color = androidx.compose.ui.graphics.Color.White,
                            strokeWidth = 2.dp,
                            modifier = Modifier.width(18.dp).height(18.dp),
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "Saving…",
                            style = MaterialTheme.typography.labelLarge,
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Default.Inventory2,
                            contentDescription = null,
                            modifier = Modifier.width(18.dp).height(18.dp),
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "Save $totalCopies to Personal",
                            style = MaterialTheme.typography.labelLarge,
                        )
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
    torchEnabled: Boolean,
    onAutoQueue: (bobaId: String) -> Unit,
    onChipTap: (bobaId: String) -> Unit,
    onSaveToast: (message: String, isError: Boolean) -> Unit,
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
            // CameraX defaults to ~640×480 for ImageAnalysis to keep
            // per-frame CPU low. ML Kit Text Recognition needs more
            // pixels to read printed card numbers cleanly — 720p
            // doubles the linear resolution for ~4x the OCR detail
            // without putting the matcher under sustained pressure
            // (analyzer still runs at 15-30 fps on modern devices).
            // Tuned in iter 13.
            setImageAnalysisResolutionSelector(
                androidx.camera.core.resolutionselector.ResolutionSelector.Builder()
                    .setResolutionStrategy(
                        androidx.camera.core.resolutionselector.ResolutionStrategy(
                            android.util.Size(1280, 720),
                            androidx.camera.core.resolutionselector.ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                        )
                    )
                    .build()
            )
        }
    }
    // Drive the camera torch from the lifted state in ScanScreen.
    // Restart when the lifecycle owner rebinds so the torch state
    // persists across re-binds.
    LaunchedEffect(torchEnabled, lifecycleOwner) {
        runCatching {
            // enableTorch returns a ListenableFuture; we don't need
            // to await — torch state applies asynchronously.
            controller.enableTorch(torchEnabled)
            android.util.Log.i(
                "ScanViewfinder",
                "Torch -> $torchEnabled",
            )
        }.onFailure {
            android.util.Log.w("ScanViewfinder", "enableTorch threw", it)
        }
    }
    // Iter 51: bias auto-exposure toward UNDER-EXPOSURE in scan
    // mode. On shiny / holographic prints the camera AE biases
    // toward the bright shimmer / specular highlights, blowing out
    // the printed text and making OCR worthless. Mild underexposure
    // (-1 EV) preserves highlight detail at the cost of slightly
    // darker mid-tones. Most BoBA cards have high-contrast printed
    // text on the card face that's still readable when slightly
    // underexposed — but shiny ones become DRAMATICALLY more
    // readable. Applied once the lifecycle binds + camera is
    // available. The cameraControl reference may be null briefly
    // during binding; the LaunchedEffect's loop catches that.
    LaunchedEffect(lifecycleOwner) {
        // Wait up to a second for cameraControl to be non-null
        // (LifecycleCameraController.cameraControl returns null
        // until the camera has actually opened).
        repeat(20) {
            val control = controller.cameraControl
            if (control != null) {
                val range = controller.cameraInfo?.exposureState?.exposureCompensationRange
                if (range != null && range.contains(-2)) {
                    // -2 EV clicks if the device supports it (most do —
                    // typical range is ±6 in 1/3-stop clicks).
                    runCatching {
                        control.setExposureCompensationIndex(-2)
                        android.util.Log.i(
                            "ScanViewfinder",
                            "Set exposure compensation -2 clicks (≈ -2/3 EV)",
                        )
                    }.onFailure {
                        android.util.Log.w("ScanViewfinder", "setExposureCompensationIndex threw", it)
                    }
                }
                return@LaunchedEffect
            }
            kotlinx.coroutines.delay(50)
        }
    }
    // PreviewView dimensions for top-left-quadrant detection. The
    // MlKitAnalyzer maps text-block bounds into VIEW-REFERENCED
    // coordinates, so frameWidth/Height is the PreviewView size.
    // Throttle state for the ShinyScanDiag log — write at most once
    // per second so logcat stays readable when running 15-30 fps.
    var lastShinyDiagLogMs by remember { mutableStateOf(0L) }
    // Iter 53: cross-frame token aggregation buffer. Real-world finding
    // from DEKAP GGL-779 logcat: OCR catches `DEKAP` consistently +
    // `80` (power) consistently + chrome text ("POWER", "BATTLE",
    // "FIRST EDITION") BUT the discriminating cardNumber tokens
    // (`GGL`, `779`) appear only intermittently across frames. The
    // matcher's per-frame view can't commit because no single frame
    // has all the signal. Aggregating tokens over the last ~5 frames
    // gives the matcher a UNION view: even if `GGL` only landed in
    // frame N and `779` only in frame N+2, the union has both.
    //
    // Mutable list rather than Compose state — the analyzer closure
    // captures it and we mutate in place. Cleared after any commit
    // (lastMatchedBobaId change) so the buffer can't pollute a new
    // card scan with stale tokens.
    val recentTokenBatches = remember { java.util.ArrayDeque<List<ScanTextToken>>() }
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
                val allTokens = text.textBlocks.flatMap { block ->
                    block.lines.mapNotNull { line ->
                        val bbox = line.boundingBox ?: return@mapNotNull null
                        ScanTextToken.fromRect(
                            text = line.text,
                            rect = bbox,
                            frameWidth = previewW,
                            frameHeight = previewH,
                        )
                    }
                }
                if (allTokens.isEmpty()) return@MlKitAnalyzer

                // iOS-parity ROI gate: filter out OCR tokens whose
                // bounding box falls entirely outside the card-guide
                // rect (plus a 5% bleed). iOS uses Vision's regionOfInterest
                // to skip background pixels entirely — cheaper on Android
                // to crop the token set after OCR than to crop frames
                // before. Removes false-positive cardNumber matches from
                // text printed on table/hands/signage, and reduces noise
                // tokens that dilute the matcher's confidence floor.
                // previewW/H default to 1 until the PreviewView measures;
                // when unmeasured, skip the filter so the first frames
                // still scan.
                // ROI gate via the shared ScanGuideMath helpers — same
                // rect as the visible ScanGuideOverlay so the matcher's
                // input stays in lockstep with what the user sees. Pure
                // functions + JVM-tested in ScanGuideMathTest.
                val guide = scanGuideRect(previewW, previewH)
                val filteredTokens = if (guide != null) {
                    allTokens.filter { it.intersectsScanGuide(guide) }
                } else {
                    allTokens
                }

                // Two-pass match for shiny / sparkly cards (iter 43):
                // glow / holographic prints often force the user to
                // tilt the card to dodge specular highlights, which
                // pushes the cardNumber strip outside the guide rect.
                // The ROI-filtered set then misses the cardNumber
                // entirely and the matcher returns null. Fall back to
                // the unfiltered set whenever the filtered match
                // fails. The hero veto (DECISIONS.md #035 strict-
                // substring guard) is what protects the unfiltered
                // path from background-text noise — a stray cardNumber
                // on a sign won't beat a real DEKAP top-left.
                val perFrameTokens = filteredTokens.takeIf { it.isNotEmpty() } ?: allTokens
                if (perFrameTokens.isEmpty()) return@MlKitAnalyzer

                // Iter 53: aggregate the last 5 frames' tokens into a
                // union and feed THAT to the matcher. Each frame's
                // sparse OCR contributes to a richer signal pool —
                // even if `GGL` only landed in frame N and `779` only
                // in frame N+2, the matcher sees BOTH at frame N+2.
                // Dedupe by uppercase text so identical re-reads don't
                // bloat the pool. Capped at 5 frames (matches the
                // stabilizer window) so a new card swap ages out the
                // old card's tokens in ~1/3 second at 15 fps. The
                // buffer also clears on every successful commit so
                // the next scan starts fresh.
                recentTokenBatches.addLast(perFrameTokens)
                while (recentTokenBatches.size > 5) recentTokenBatches.removeFirst()
                // Dedupe by uppercase text; when the same text appears
                // in multiple frames, prefer the top-left occurrence
                // so the hero-veto signal (which depends on top-left
                // positioning) isn't lost to a frame that happened to
                // catch the same text in a different position.
                val tokens = recentTokenBatches
                    .flatten()
                    .groupBy { it.text.uppercase() }
                    .map { (_, dupes) ->
                        dupes.firstOrNull { it.isTopLeft } ?: dupes.first()
                    }
                val firstPass = matcher.match(tokens)
                // Enriched diagnostic (iter 49). Captures every token
                // + the matcher's top-pick score + reasons, throttled
                // to once per second. Tagged ShinyScanDiag —
                //   adb logcat -s ShinyScanDiag
                // while scanning DEKAP GGL-779 will show whether the
                // problem is (a) tokens are missing, (b) tokens
                // present but score below 1.4, (c) score above 1.4
                // but margin below 0.3, or (d) wrong card winning.
                run {
                    val now = System.currentTimeMillis()
                    val sinceLast = now - lastShinyDiagLogMs
                    if (sinceLast > 1000) {
                        lastShinyDiagLogMs = now
                        val tokSnippet = tokens.take(12).joinToString(" | ") { it.text }
                        val matchInfo = firstPass?.let { r ->
                            "MATCH=${r.card.displayName} score=${"%.2f".format(r.score)} margin=${"%.2f".format(r.margin)} via [${r.reasons.joinToString(", ")}]"
                        } ?: run {
                            // No commit — show what was ALMOST committed
                            // so we can target the right gap (sub-floor
                            // confidence vs sub-floor margin vs wrong
                            // candidate winning).
                            val debug = matcher.debugTop(tokens)
                            debug?.let { d ->
                                "no-commit; debug-top=${d.card.displayName} (${d.card.cardNumber}) reasons=${d.reasons.joinToString(", ")}"
                            } ?: "no-commit; no candidates"
                        }
                        android.util.Log.i(
                            "ShinyScanDiag",
                            "tokens(${tokens.size}/${allTokens.size}): $tokSnippet ;; $matchInfo",
                        )
                    }
                }
                val perFrame = if (firstPass == null && tokens !== allTokens) {
                    val secondPass = matcher.match(allTokens)
                    if (secondPass != null) {
                        android.util.Log.i(
                            "ScanViewfinder",
                            "Shiny-card recovery: ROI-filtered ${tokens.size} tokens → null; full ${allTokens.size} → ${secondPass.card.displayName} score=${"%.2f".format(secondPass.score)}",
                        )
                    }
                    secondPass
                } else {
                    firstPass
                }
                // Push every frame (including misses) through the
                // stabilizer so the de-dupe gate sees the gaps.
                val stable = stabilizer.push(perFrame)
                scanState = stabilizer.state
                if (stable != null && lastMatchedBobaId != stable.card.bobaId) {
                    lastMatchedBobaId = stable.card.bobaId
                    // Iter 53: clear the aggregation buffer on commit
                    // so the next scan starts with a fresh token pool.
                    // Otherwise stale tokens from the previous card
                    // would contaminate the new scan's signal.
                    recentTokenBatches.clear()
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
        // Cache the last-rendered chip card so the AnimatedVisibility
        // exit transition has content to draw. Without this, when the
        // user taps X (or MULTI auto-clears at 1.6s), `detectedCard`
        // flips to null → the content lambda is re-invoked with null
        // → early return → chip vanishes instantly. The cache holds
        // the previous Card during the ~250ms exit slide so the
        // animation actually plays out.
        var lastShownChipCard by remember { mutableStateOf<com.bobaplaybook.core.domain.model.Card?>(null) }
        androidx.compose.runtime.LaunchedEffect(committed) {
            if (committed != null) lastShownChipCard = committed
        }
        // AnimatedVisibility — slide-from-bottom + opacity fade,
        // matching iOS's .transition(.move(edge:.bottom).combined(.opacity)).
        // The chip render moves into the AnimatedVisibility block so
        // the same animator handles both enter (committed -> non-null)
        // and exit (committed -> null on dismiss / auto-clear).
        androidx.compose.animation.AnimatedVisibility(
            visible = committed != null,
            enter = androidx.compose.animation.slideInVertically(initialOffsetY = { it }) +
                androidx.compose.animation.fadeIn(),
            exit = androidx.compose.animation.slideOutVertically(targetOffsetY = { it }) +
                androidx.compose.animation.fadeOut(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 96.dp)
                .align(Alignment.BottomCenter),
        ) {
            // Use the cached `lastShownChipCard` so the exit
            // transition has content to render even after the parent
            // flipped `detectedCard` to null. Falls through to
            // `committed` if the cache hasn't filled yet (first chip
            // ever). The early return is a paranoid no-content guard
            // that should never fire in practice once a chip has
            // shown.
            val card = (lastShownChipCard ?: committed) ?: return@AnimatedVisibility
            // Quick-Save plumbing — chip's "+" button writes the
            // matched card to the user's Personal designation
            // without leaving the scanner. iOS chip has the
            // equivalent button. Auth state is read at tap time so
            // signed-out users get a feedback snackbar instead of
            // a silently-rejected RLS write.
            val scope = androidx.compose.runtime.rememberCoroutineScope()
            ScanDetectionChip(
                card = card,
                onTap = { onChipTap(card.bobaId) },
                onQuickSave = { qty ->
                    scope.launch {
                        val auth = ScanModuleAccess.authManager.authState
                            .first()
                        val userId = (auth as? com.bobaplaybook.app.auth.AuthState.SignedIn)?.userId
                        if (userId == null) {
                            // Signed-out: keep the chip visible so
                            // the user can sign in + tap Add again
                            // without re-scanning. Just toast the
                            // error.
                            onSaveToast(
                                "Sign in to save ${card.displayName}",
                                true,
                            )
                            return@launch
                        }
                        // iOS-parity optimistic dismiss — clear the
                        // chip + reset the stabilizer BEFORE the save
                        // loop runs (iOS does the equivalent right
                        // after the auth gate). Two wins:
                        //   • User can't double-tap "Add" during the
                        //     1-2s of sequential Supabase inserts.
                        //   • Camera is immediately free for the next
                        //     card (Whatnot box-break loop). Save
                        //     runs invisibly in this coroutine; toast
                        //     confirms result asynchronously.
                        stabilizer.reset()
                        lastMatchedBobaId = null
                        detectedCard = null
                        val cardNumber = card.cardNumber
                            .ifEmpty { card.bobaId.substringBefore('-') }
                        // iOS-parity batch add: one row per copy. The
                        // user picks N via the stepper, the chip emits
                        // one quickSave callback, we loop N inserts.
                        // CollectionRepository.add() accepts a quantity
                        // param but currently ignores it (one row per
                        // call) — the loop here is the chip's
                        // canonical contract regardless.
                        repeat(qty.coerceIn(1, 99)) {
                            ScanModuleAccess.collectionRepository.add(
                                cardBobaId = card.bobaId,
                                cardNumber = cardNumber,
                                designation = com.bobaplaybook.core.domain.model.Designation.PERSONAL,
                                userId = userId,
                            )
                        }
                        // Keep the card name in the toast for both
                        // singular + multi-copy — collectors want
                        // confirmation of *which* card landed, not
                        // just "Saved 3". iOS uses "Saved N to {dest}"
                        // (without the name); we read better with it.
                        val message = if (qty > 1) {
                            "Saved $qty × ${card.displayName} to Personal"
                        } else {
                            "Saved ${card.displayName} to Personal"
                        }
                        onSaveToast(message, false)
                    }
                },
                onDismiss = {
                    // User-initiated chip clear (the "X" affordance).
                    // iOS uses a swipe-down gesture for the same. Reset
                    // the stabilizer so the next commit fires fresh —
                    // including for the same card the user just
                    // dismissed (deliberate re-scan).
                    stabilizer.reset()
                    lastMatchedBobaId = null
                    detectedCard = null
                },
                isSingleMode = currentScanMode == ScanMode.SINGLE,
                // AnimatedVisibility owns the position + padding +
                // alignment now; the chip itself is just full-width.
                modifier = Modifier.fillMaxWidth(),
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
    onQuickSave: (Int) -> Unit,
    onDismiss: () -> Unit,
    isSingleMode: Boolean,
    modifier: Modifier = Modifier,
) {
    // Chip-owned quantity stepper state — iOS parity. SINGLE mode lets
    // the user pre-set N (1–99) and commit once; MULTI mode auto-queues
    // each commit (no stepper). Reset to 1 whenever the matched card
    // changes so a new chip starts at qty=1.
    var quantity by androidx.compose.runtime.remember(card.bobaId) {
        androidx.compose.runtime.mutableStateOf(1)
    }
    // Element-coloured accent stripe + outline — iOS ScanDetectionChipView
    // tints the chip with the matched card's weapon colour so a quick
    // glance at the screen tells the user "FIRE / ICE / etc." without
    // reading the caption. Stripe is 3dp wide on the left edge; outline
    // is 1dp around the whole chip for the same colour.
    val accent = com.bobaplaybook.core.ui.theme.BobaElements.forElement(
        card.element.uppercase()
    )
    Surface(
        modifier = modifier
            // Swipe-down gesture to dismiss — iOS ScanDetectionChipView
            // uses `.simultaneousGesture(DragGesture).onEnded { ... }`
            // with a 30pt threshold. Android equivalent: accumulate the
            // vertical drag amount; trigger onDismiss when the user
            // pulls down ≥ 60 px. Lives BEFORE the inner row's
            // clickable so the drag detector consumes the gesture
            // before tap propagation (tap stays usable as long as
            // the user doesn't drag past the threshold).
            .pointerInput(Unit) {
                var dy = 0f
                detectVerticalDragGestures(
                    onDragStart = { _: androidx.compose.ui.geometry.Offset -> dy = 0f },
                    onDragEnd = {
                        if (dy >= 60f) onDismiss()
                    },
                    onDragCancel = { dy = 0f },
                ) { _: androidx.compose.ui.input.pointer.PointerInputChange, dragAmount: Float ->
                    dy += dragAmount
                }
            },
        color = Color.Black.copy(alpha = 0.78f),
        shape = RoundedCornerShape(14.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.55f)),
    ) {
      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier
                .clickable { onTap() }
                .padding(end = 4.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Element-coloured accent stripe — full-height left edge.
            // No top/bottom padding here so the stripe extends to the
            // chip edges (Row padding doesn't apply on the .start
            // edge), giving a clean continuous coloured band.
            Box(
                modifier = Modifier
                    .width(3.dp)
                    .height(62.dp)
                    .background(accent),
            )
            val thumb = com.bobaplaybook.core.network.CDN.thumbUrl(card)
            // iOS-parity element glow on the thumbnail. iOS uses
            // `.elementGlow(card.element)` which renders a soft
            // element-coloured shadow under the thumb. Android Box
            // wrapper applies `shadow(elevation, ambient, spot)` with
            // the element accent so the same hint of colour bleeds out
            // from behind the card art.
            Box(
                modifier = Modifier
                    .shadow(
                        elevation = 8.dp,
                        shape = RoundedCornerShape(4.dp),
                        ambientColor = accent,
                        spotColor = accent,
                    ),
            ) {
                coil3.compose.AsyncImage(
                    model = thumb,
                    contentDescription = null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier
                        .width(44.dp)
                        .height(62.dp)
                        .clip(RoundedCornerShape(4.dp)),
                )
            }
            // iOS-parity caption layout: name / card-number / power
            // on three separate lines (vs Android's prior single
            // muted caption). cardNumber renders in BOBA orange mono
            // and power in the element accent — collectors recognise
            // the layout from the rest of the app.
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(1.dp),
            ) {
                Text(
                    text = card.displayName,
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                )
                if (card.cardNumber.isNotBlank()) {
                    Text(
                        text = card.cardNumber,
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(0xFFFF4D00),
                    )
                }
                card.power?.takeIf { it > 0 }?.let { p ->
                    Text(
                        text = "PWR $p",
                        style = MaterialTheme.typography.labelSmall,
                        color = accent,
                    )
                }
            }
            // iOS-parity right-side affordance:
            //   • SINGLE → quantity stepper (- N +); paired with the
            //     full-width "Add N to Collection" button rendered
            //     BELOW the row.
            //   • MULTI  → minimal chevron-up + "VIEW" label (auto-
            //     queue handles the save; tapping opens detail).
            if (isSingleMode) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    IconButton(
                        onClick = { if (quantity > 1) quantity -= 1 },
                        enabled = quantity > 1,
                        modifier = Modifier.width(28.dp).height(28.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Remove,
                            contentDescription = "Decrement quantity",
                            tint = if (quantity > 1) Color.White
                                   else Color.White.copy(alpha = 0.35f),
                        )
                    }
                    Text(
                        text = "$quantity",
                        style = MaterialTheme.typography.titleMedium,
                        color = Color.White,
                        modifier = Modifier.width(22.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                    IconButton(
                        onClick = { if (quantity < 99) quantity += 1 },
                        enabled = quantity < 99,
                        modifier = Modifier.width(28.dp).height(28.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Add,
                            contentDescription = "Increment quantity",
                            tint = if (quantity < 99) Color.White
                                   else Color.White.copy(alpha = 0.35f),
                        )
                    }
                }
            } else {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                    modifier = Modifier.width(44.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowUp,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.7f),
                    )
                    Text(
                        text = "VIEW",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.White.copy(alpha = 0.7f),
                    )
                }
            }
            // Dismiss "X" — clears the chip + resets the stabilizer
            // so the user can re-scan without leaving the screen.
            // iOS uses a swipe-down gesture; Android takes the more
            // discoverable tap-X affordance (Material 3 norm for
            // dismissable surfaces).
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.width(36.dp).height(36.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Dismiss",
                    tint = Color.White.copy(alpha = 0.72f),
                )
            }
        }
        // SINGLE-mode commit button — iOS-parity full-width orange CTA
        // ("Add to Collection" / "Add N to Collection") rendered below
        // the row. Tap fires onQuickSave(quantity). MULTI mode hides
        // this — the auto-queue flow doesn't ask for a quantity since
        // each commit is one card and the queue review surface owns
        // any multi-copy editing.
        if (isSingleMode) {
            Button(
                onClick = { onQuickSave(quantity) },
                colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                    containerColor = Color(0xFFFF4D00),
                    contentColor = Color.White,
                ),
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 12.dp, end = 12.dp, bottom = 10.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = null,
                    modifier = Modifier.width(16.dp).height(16.dp),
                )
                androidx.compose.foundation.layout.Spacer(Modifier.width(6.dp))
                Text(
                    text = if (quantity == 1) "Add to Collection"
                           else "Add $quantity to Collection",
                    style = MaterialTheme.typography.labelLarge,
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
            // Source of truth lives in ScanGuideMath.scanGuideRect so
            // the analyzer's ROI filter rect and the visible guide
            // can't drift apart. `scanGuideRect` returns null when the
            // Canvas hasn't been measured yet; fall back to the inline
            // math for that one frame.
            val rect = scanGuideRect(w.toInt(), h.toInt())
            val finalW: Float
            val finalH: Float
            val left: Float
            val top: Float
            if (rect != null) {
                finalW = rect.width
                finalH = rect.height
                left = rect.left
                top = rect.top
            } else {
                val cardW = w * 0.75f
                val cardH = cardW * 7f / 5f
                if (cardH > h * 0.62f) {
                    finalH = h * 0.62f
                    finalW = finalH * 5f / 7f
                } else {
                    finalW = cardW
                    finalH = cardH
                }
                left = (w - finalW) / 2f
                top = (h - finalH) / 2f - h * 0.04f
            }

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
    lateinit var collectionRepository: com.bobaplaybook.core.data.collection.CollectionRepository
    lateinit var authManager: com.bobaplaybook.app.auth.AuthManager
}

/**
 * Hilt entry-point wired at Activity level — `MainActivity` sets the
 * static accessor at app start so the Composable can read it without
 * threading a Hilt dependency through `AndroidView`.
 *
 * Added collectionRepository + authManager in iter 11 so the chip's
 * Quick-Save (+) action can write to user_cards without rerouting
 * through onMatch (which dismisses Scan).
 */
class ScanModuleAccessSeeder @Inject constructor(
    cardRepository: CardRepository,
    collectionRepository: com.bobaplaybook.core.data.collection.CollectionRepository,
    authManager: com.bobaplaybook.app.auth.AuthManager,
) {
    init {
        ScanModuleAccess.cardRepository = cardRepository
        ScanModuleAccess.collectionRepository = collectionRepository
        ScanModuleAccess.authManager = authManager
    }
}
