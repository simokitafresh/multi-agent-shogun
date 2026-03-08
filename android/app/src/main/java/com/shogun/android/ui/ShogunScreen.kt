package com.shogun.android.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import com.shogun.android.ui.theme.*
import com.shogun.android.util.Defaults
import com.shogun.android.util.PrefsKeys
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shogun.android.R
import com.shogun.android.viewmodel.ShogunViewModel
import kotlinx.coroutines.launch

@Composable
fun ShogunScreen(
    viewModel: ShogunViewModel = viewModel()
) {
    val context = LocalContext.current
    val paneContent by viewModel.paneContent.collectAsState()
    val isConnected by viewModel.isConnected.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    var inputTextValue by remember { mutableStateOf(TextFieldValue("")) }
    var isListening by remember { mutableStateOf(false) }
    var isInputExpanded by remember { mutableStateOf(false) }
    var isInputFocused by remember { mutableStateOf(false) }

    val focusManager = LocalFocusManager.current
    val density = LocalDensity.current
    val horizontalPaddingPx = with(density) { 16.dp.toPx() }
    val imeVisible = WindowInsets.ime.getBottom(density) > 0

    LaunchedEffect(imeVisible) {
        if (!imeVisible && isInputFocused) {
            focusManager.clearFocus()
        }
    }

    val prefs = remember { context.getSharedPreferences(PrefsKeys.PREFS_NAME, android.content.Context.MODE_PRIVATE) }
    var termFontSize by remember { mutableFloatStateOf(prefs.getFloat(PrefsKeys.FONT_SIZE, Defaults.FONT_SIZE_DEFAULT)) }
    var softWrapEnabled by remember { mutableStateOf(prefs.getBoolean(PrefsKeys.SOFT_WRAP, Defaults.SOFT_WRAP_DEFAULT)) }

    val listState = rememberLazyListState()
    val verticalScrollState = rememberScrollState()
    val horizontalScrollState = rememberScrollState()
    val zoomState = rememberTerminalZoomState()
    val coroutineScope = rememberCoroutineScope()
    val lines = remember(paneContent) { paneContent.lines() }
    val parsedPaneContent = remember(paneContent) { parseAnsiColors(paneContent) }

    DisposableEffect(prefs) {
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { sharedPrefs, key ->
            when (key) {
                PrefsKeys.FONT_SIZE -> {
                    termFontSize = sharedPrefs.getFloat(PrefsKeys.FONT_SIZE, Defaults.FONT_SIZE_DEFAULT)
                }
                PrefsKeys.SOFT_WRAP -> {
                    softWrapEnabled = sharedPrefs.getBoolean(PrefsKeys.SOFT_WRAP, Defaults.SOFT_WRAP_DEFAULT)
                }
            }
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }

    val speechRecognizer = remember {
        if (SpeechRecognizer.isRecognitionAvailable(context))
            SpeechRecognizer.createSpeechRecognizer(context)
        else null
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted && speechRecognizer != null) {
            startContinuousListening(speechRecognizer, { isListening }) { result ->
                val newText = if (inputTextValue.text.isEmpty()) result else "${inputTextValue.text} $result"
                inputTextValue = TextFieldValue(text = newText, selection = TextRange(newText.length))
            }
            isListening = true
        }
    }

    // Auto-connect on composition
    LaunchedEffect(Unit) {
        val prefs = context.getSharedPreferences(PrefsKeys.PREFS_NAME, android.content.Context.MODE_PRIVATE)
        val host = prefs.getString(PrefsKeys.SSH_HOST, Defaults.SSH_HOST) ?: Defaults.SSH_HOST
        val port = prefs.getString(PrefsKeys.SSH_PORT, Defaults.SSH_PORT_STR)?.toIntOrNull() ?: Defaults.SSH_PORT
        val user = prefs.getString(PrefsKeys.SSH_USER, "") ?: ""
        val keyPath = prefs.getString(PrefsKeys.SSH_KEY_PATH, "") ?: ""
        val password = prefs.getString(PrefsKeys.SSH_PASSWORD, "") ?: ""
        viewModel.connect(host, port, user, keyPath, password)
    }

    // Pause refresh when app is in background
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    viewModel.resumeRefresh()
                    if (isListening && speechRecognizer != null) {
                        startContinuousListening(speechRecognizer, { isListening }) { result ->
                            val newText = if (inputTextValue.text.isEmpty()) result else "${inputTextValue.text} $result"
                            inputTextValue = TextFieldValue(text = newText, selection = TextRange(newText.length))
                        }
                    }
                }
                Lifecycle.Event.ON_PAUSE -> {
                    viewModel.pauseRefresh()
                    speechRecognizer?.cancel()
                }
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    var wasAtBottomLazy by remember { mutableStateOf(true) }
    var wasAtBottomScroll by remember { mutableStateOf(true) }

    LaunchedEffect(softWrapEnabled) {
        zoomState.clearContentWidth()
        zoomState.reset()
        wasAtBottomLazy = true
        wasAtBottomScroll = true
    }

    LaunchedEffect(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset, softWrapEnabled) {
        if (!softWrapEnabled) return@LaunchedEffect

        val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index
        val totalItems = listState.layoutInfo.totalItemsCount
        wasAtBottomLazy = lastVisible == null || totalItems == 0 || lastVisible >= totalItems - 2
    }

    LaunchedEffect(verticalScrollState.value, softWrapEnabled) {
        if (softWrapEnabled) return@LaunchedEffect

        wasAtBottomScroll = verticalScrollState.maxValue == 0 ||
            verticalScrollState.value >= verticalScrollState.maxValue - 50
    }

    LaunchedEffect(lines.size, softWrapEnabled, zoomState.isZoomed) {
        if (softWrapEnabled && lines.isNotEmpty() && !zoomState.isZoomed && wasAtBottomLazy) {
            listState.scrollToItem(lines.size - 1)
        }
    }

    LaunchedEffect(paneContent, verticalScrollState.maxValue, softWrapEnabled, zoomState.isZoomed) {
        if (!softWrapEnabled && !zoomState.isZoomed && wasAtBottomScroll) {
            verticalScrollState.scrollTo(verticalScrollState.maxValue)
        }
    }

    val showScrollToBottomFab = if (softWrapEnabled) !wasAtBottomLazy else !wasAtBottomScroll

    ScreenBackground(imageResId = R.drawable.bg_shogun) {
        Column(modifier = Modifier.fillMaxSize()) {
        // 陣幕バー — 未接続時のみ赤警告バー表示
        AnimatedVisibility(visible = !isConnected) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Kurenai)
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.Center
            ) {
                Text(
                    text = "未接続",
                    color = Color.White,
                    fontSize = 12.sp
                )
            }
        }

        // Pane content display with LazyColumn
        BoxWithConstraints(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .terminalZoom(zoomState)
        ) {
            val desktopWidthModifier = if (!softWrapEnabled && zoomState.scale < 1f) {
                Modifier.width(maxWidth * zoomState.layoutWidthMultiplier)
            } else {
                Modifier.fillMaxWidth()
            }

            if (errorMessage != null) {
                Text(
                    text = "エラー: $errorMessage",
                    color = Kurenai,
                    fontFamily = FontFamily.Monospace,
                    fontSize = termFontSize.sp,
                    modifier = Modifier.padding(8.dp)
                )
            } else {
                if (softWrapEnabled) {
                    LazyColumn(
                        state = listState,
                        userScrollEnabled = !zoomState.isZoomed,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        items(lines) { line ->
                            SelectionContainer {
                                Text(
                                    text = parseAnsiColors(line),
                                    color = Zouge,
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = termFontSize.sp,
                                    softWrap = true
                                )
                            }
                        }
                    }
                } else {
                    SelectionContainer {
                        Text(
                            text = parsedPaneContent,
                            color = Zouge,
                            fontFamily = FontFamily.Monospace,
                            fontSize = termFontSize.sp,
                            softWrap = false,
                            onTextLayout = { result ->
                                val maxLineWidth = (0 until result.lineCount).maxOfOrNull {
                                    result.getLineRight(it) - result.getLineLeft(it)
                                } ?: 0f
                                zoomState.updateContentWidth(maxLineWidth + horizontalPaddingPx)
                            },
                            modifier = Modifier
                                .then(desktopWidthModifier)
                                .fillMaxHeight()
                                .verticalScroll(verticalScrollState, enabled = !zoomState.isZoomed)
                                .horizontalScroll(horizontalScrollState, enabled = !zoomState.isZoomed)
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }
                }
            }

            androidx.compose.animation.AnimatedVisibility(
                visible = showScrollToBottomFab,
                enter = fadeIn() + slideInVertically { it / 2 },
                exit = fadeOut() + slideOutVertically { it / 2 },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 16.dp, bottom = 12.dp)
            ) {
                SmallFloatingActionButton(
                    onClick = {
                        coroutineScope.launch {
                            if (softWrapEnabled) {
                                wasAtBottomLazy = true
                                if (lines.isNotEmpty()) {
                                    listState.animateScrollToItem(lines.lastIndex)
                                }
                            } else {
                                wasAtBottomScroll = true
                                verticalScrollState.animateScrollTo(verticalScrollState.maxValue)
                            }
                        }
                    },
                    modifier = Modifier.size(40.dp),
                    containerColor = Sumi.copy(alpha = 0.72f),
                    contentColor = Kinpaku
                ) {
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowDown,
                        contentDescription = "最下部へ戻る"
                    )
                }
            }
        }

        AnimatedVisibility(visible = isInputFocused) {
            SpecialKeysRow(onSendKey = { viewModel.sendCommand(it) })
        }

        // Input area
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = inputTextValue,
                onValueChange = { inputTextValue = it },
                modifier = Modifier
                    .weight(1f)
                    .onFocusChanged { isInputFocused = it.isFocused },
                placeholder = { Text("コマンドを入力", color = TextMuted) },
                singleLine = !isInputExpanded,
                maxLines = if (isInputExpanded) 6 else 1,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Zouge,
                    unfocusedTextColor = Zouge,
                    focusedBorderColor = BorderFocus,
                    unfocusedBorderColor = BorderStandard,
                    cursorColor = Kinpaku,
                    focusedContainerColor = Surface4,
                    unfocusedContainerColor = Surface4,
                )
            )

            Spacer(modifier = Modifier.width(4.dp))

            // Expand/collapse text button
            IconButton(
                onClick = { isInputExpanded = !isInputExpanded },
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    imageVector = if (isInputExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                    contentDescription = "展開",
                    tint = Kinpaku
                )
            }

            // Voice input button (manual ON/OFF — stays on until user taps again)
            IconButton(
                onClick = {
                    if (speechRecognizer == null) return@IconButton
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                        == PackageManager.PERMISSION_GRANTED
                    ) {
                        if (isListening) {
                            speechRecognizer.cancel()
                            isListening = false
                        } else {
                            startContinuousListening(speechRecognizer, { isListening }) { result ->
                                val newText = if (inputTextValue.text.isEmpty()) result else "${inputTextValue.text} $result"
                                inputTextValue = TextFieldValue(text = newText, selection = TextRange(newText.length))
                            }
                            isListening = true
                        }
                    } else {
                        permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                    }
                }
            ) {
                Icon(
                    imageVector = Icons.Default.Mic,
                    contentDescription = "音声入力",
                    tint = if (isListening) Kurenai else Kinpaku
                )
            }

            Spacer(modifier = Modifier.width(4.dp))

            // Send button
            IconButton(
                onClick = {
                    if (inputTextValue.text.isNotBlank()) {
                        viewModel.sendCommand(inputTextValue.text)
                        inputTextValue = TextFieldValue("")
                    }
                },
                enabled = inputTextValue.text.isNotBlank() && isConnected && !isListening
            ) {
                Icon(
                    imageVector = Icons.Default.Send,
                    contentDescription = "送信",
                    tint = if (inputTextValue.text.isNotBlank() && isConnected && !isListening) Kinpaku else TextMuted
                )
            }
        } // Row (input area)
        } // Column (main)
    }
}

@Composable
fun SpecialKeysRow(onSendKey: (String) -> Unit) {
    // Ordered by usage frequency for tmux + Claude Code workflow
    val specialKeys = listOf(
        "↵" to "\n",        // Enter — most used (confirm commands, send input)
        "C-c" to "\u0003",  // Interrupt — stop running process
        "C-b" to "\u0002",  // tmux prefix — pane control (C-b C-b for background)
        "↑" to "\u001b[A",  // History up
        "↓" to "\u001b[B",  // History down
        "Tab" to "\t",      // Autocomplete
        "ESC" to "\u001b",  // Cancel / exit mode
        "C-o" to "\u000f",  // Accept line in Claude Code
        "C-d" to "\u0004",  // EOF / exit
        "/clear" to "/clear\n"  // Clear Claude Code session
    )
    LazyRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        items(specialKeys) { (label, value) ->
            OutlinedButton(
                onClick = { onSendKey(value) },
                modifier = Modifier.height(32.dp),
                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
                border = BorderStroke(1.dp, BorderFocus),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = Surface4,
                    contentColor = Zouge
                )
            ) {
                Text(
                    text = label,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
    }
}

/**
 * Continuous listening — auto-restarts after each result.
 * Checks isActive() before restarting to respect user's OFF toggle.
 * Caller should use cancel() (not stopListening()) to stop cleanly.
 */
fun startContinuousListening(
    speechRecognizer: SpeechRecognizer,
    isActive: () -> Boolean,
    onResult: (String) -> Unit
) {
    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ja-JP")
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 5000L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 5000L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 2000L)
    }
    speechRecognizer.setRecognitionListener(object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onError(error: Int) {
            if (!isActive()) return
            when (error) {
                SpeechRecognizer.ERROR_AUDIO,
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                    // Fatal — do not restart
                }
                else -> {
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        if (isActive()) {
                            try { speechRecognizer.startListening(intent) } catch (_: Exception) {}
                        }
                    }, 300)
                }
            }
        }
        override fun onResults(results: Bundle?) {
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            if (!matches.isNullOrEmpty()) {
                onResult(matches[0])
            }
            if (isActive()) {
                speechRecognizer.startListening(intent)
            }
        }
        override fun onPartialResults(partialResults: Bundle?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    })
    speechRecognizer.startListening(intent)
}
