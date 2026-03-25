package com.shogun.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.shogun.android.ui.theme.*
import com.shogun.android.util.Defaults
import com.shogun.android.util.PrefsKeys
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shogun.android.util.AppLogger
import com.shogun.android.BuildConfig
import com.shogun.android.viewmodel.SettingsViewModel

@Composable
fun SettingsScreen(settingsViewModel: SettingsViewModel = viewModel()) {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)

    var host by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_HOST, Defaults.SSH_HOST) ?: Defaults.SSH_HOST) }
    var port by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_PORT, Defaults.SSH_PORT_STR) ?: Defaults.SSH_PORT_STR) }
    var user by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_USER, "") ?: "") }
    var keyPath by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_KEY_PATH, "") ?: "") }
    var password by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_PASSWORD, "") ?: "") }
    var projectPath by remember { mutableStateOf(prefs.getString(PrefsKeys.PROJECT_PATH, Defaults.PROJECT_PATH) ?: Defaults.PROJECT_PATH) }
    var shogunSession by remember { mutableStateOf(prefs.getString(PrefsKeys.SHOGUN_SESSION, Defaults.SHOGUN_SESSION) ?: Defaults.SHOGUN_SESSION) }
    var agentsSession by remember { mutableStateOf(prefs.getString(PrefsKeys.AGENTS_SESSION, Defaults.AGENTS_SESSION) ?: Defaults.AGENTS_SESSION) }
    var backgroundStyle by remember {
        mutableStateOf(
            prefs.getString(PrefsKeys.BACKGROUND_STYLE, Defaults.BACKGROUND_STYLE)
                ?: Defaults.BACKGROUND_STYLE
        )
    }
    var fontSizePref by remember {
        mutableFloatStateOf(prefs.getFloat(PrefsKeys.FONT_SIZE, Defaults.FONT_SIZE_DEFAULT))
    }
    var softWrapEnabled by remember {
        mutableStateOf(prefs.getBoolean(PrefsKeys.SOFT_WRAP, Defaults.SOFT_WRAP_DEFAULT))
    }
    val themeMode by settingsViewModel.themeMode.collectAsState()

    var saved by remember { mutableStateOf(false) }
    var tapCount by remember { mutableIntStateOf(0) }
    var showDebugLog by remember { mutableStateOf(false) }

    // Debug log dialog
    if (showDebugLog) {
        DebugLogDialog(onDismiss = { showDebugLog = false })
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Shikkoku)
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            "SSH設定",
            style = MaterialTheme.typography.titleLarge,
            color = Kinpaku,
            modifier = Modifier.clickable {
                tapCount++
                if (tapCount >= 7) {
                    showDebugLog = true
                    tapCount = 0
                }
            }
        )

        OutlinedTextField(
            value = host,
            onValueChange = { host = it },
            label = { Text("SSHホスト") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        OutlinedTextField(
            value = port,
            onValueChange = { port = it },
            label = { Text("SSHポート") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
        )

        OutlinedTextField(
            value = user,
            onValueChange = { user = it },
            label = { Text("SSHユーザー") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        OutlinedTextField(
            value = keyPath,
            onValueChange = { keyPath = it },
            label = { Text("SSH秘密鍵パス") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("SSHパスワード（鍵なし時に使用）") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            visualTransformation = PasswordVisualTransformation()
        )

        HorizontalDivider(color = TextMuted.copy(alpha = 0.3f))

        Text("プロジェクト設定", style = MaterialTheme.typography.titleMedium, color = Kinpaku)

        OutlinedTextField(
            value = projectPath,
            onValueChange = { projectPath = it },
            label = { Text("プロジェクトパス（サーバー側）") },
            placeholder = { Text("/path/to/multi-agent-shogun") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        HorizontalDivider(color = TextMuted.copy(alpha = 0.3f))

        Text("セッション設定", style = MaterialTheme.typography.titleMedium, color = Kinpaku)

        OutlinedTextField(
            value = shogunSession,
            onValueChange = { shogunSession = it },
            label = { Text("将軍セッション名") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        OutlinedTextField(
            value = agentsSession,
            onValueChange = { agentsSession = it },
            label = { Text("エージェントセッション名") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        HorizontalDivider(color = TextMuted.copy(alpha = 0.3f))

        Text("外観", style = MaterialTheme.typography.titleMedium, color = Kinpaku)

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("テーマ", style = MaterialTheme.typography.bodyMedium, color = Zouge)
            Text(
                "System / Dark / Light / Black AMOLED を即時切替します",
                style = MaterialTheme.typography.bodySmall,
                color = TextMuted
            )
            ThemeModeOption(
                label = "System default",
                description = "端末設定に追従",
                selected = themeMode == ThemeMode.SYSTEM,
                onSelect = { settingsViewModel.setThemeMode(ThemeMode.SYSTEM) }
            )
            ThemeModeOption(
                label = "Dark",
                description = "現行の漆黒",
                selected = themeMode == ThemeMode.DARK,
                onSelect = { settingsViewModel.setThemeMode(ThemeMode.DARK) }
            )
            ThemeModeOption(
                label = "Light",
                description = "白壁の城",
                selected = themeMode == ThemeMode.LIGHT,
                onSelect = { settingsViewModel.setThemeMode(ThemeMode.LIGHT) }
            )
            ThemeModeOption(
                label = "Black AMOLED",
                description = "真夜中の陣",
                selected = themeMode == ThemeMode.BLACK,
                onSelect = { settingsViewModel.setThemeMode(ThemeMode.BLACK) }
            )

            Spacer(modifier = Modifier.height(4.dp))

            Text("フォントサイズ", style = MaterialTheme.typography.bodyMedium, color = Zouge)
            Text(
                "ターミナル出力テキストのサイズ（現在: ${fontSizePref.toInt()}sp）",
                style = MaterialTheme.typography.bodySmall,
                color = TextMuted
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                listOf("小" to 10f, "中" to 13f, "大" to 17f, "特大" to 22f).forEach { (label, size) ->
                    val selected = fontSizePref == size
                    OutlinedButton(
                        onClick = { fontSizePref = size },
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = if (selected) Shuaka else Color.Transparent,
                            contentColor = if (selected) Color.White else Zouge
                        ),
                        shape = RoundedCornerShape(4.dp)
                    ) {
                        Text(label)
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text("テキスト折り返し", style = MaterialTheme.typography.bodyMedium, color = Zouge)
                    Text(
                        "OFFにすると長い行を横スクロールで確認できます",
                        style = MaterialTheme.typography.bodySmall,
                        color = TextMuted
                    )
                }
                Switch(
                    checked = softWrapEnabled,
                    onCheckedChange = { softWrapEnabled = it }
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            Text("背景スタイル", style = MaterialTheme.typography.bodyMedium, color = Zouge)
            BackgroundStyleOption(
                label = "無地",
                selected = backgroundStyle == Defaults.BACKGROUND_STYLE_SOLID,
                onSelect = { backgroundStyle = Defaults.BACKGROUND_STYLE_SOLID }
            )
            BackgroundStyleOption(
                label = "画像",
                selected = backgroundStyle == Defaults.BACKGROUND_STYLE_IMAGE,
                onSelect = { backgroundStyle = Defaults.BACKGROUND_STYLE_IMAGE }
            )
        }

        HorizontalDivider(color = TextMuted.copy(alpha = 0.3f))

        VoiceDictionarySection()

        HorizontalDivider(color = TextMuted.copy(alpha = 0.3f))

        NtfySettingsSection(viewModel = settingsViewModel)

        HorizontalDivider(color = TextMuted.copy(alpha = 0.3f))

        Button(
            onClick = {
                prefs.edit()
                    .putString(PrefsKeys.SSH_HOST, host)
                    .putString(PrefsKeys.SSH_PORT, port)
                    .putString(PrefsKeys.SSH_USER, user)
                    .putString(PrefsKeys.SSH_KEY_PATH, keyPath)
                    .putString(PrefsKeys.SSH_PASSWORD, password)
                    .putString(PrefsKeys.PROJECT_PATH, projectPath)
                    .putString(PrefsKeys.SHOGUN_SESSION, shogunSession)
                    .putString(PrefsKeys.AGENTS_SESSION, agentsSession)
                    .putString(PrefsKeys.BACKGROUND_STYLE, backgroundStyle)
                    .putFloat(PrefsKeys.FONT_SIZE, fontSizePref)
                    .putBoolean(PrefsKeys.SOFT_WRAP, softWrapEnabled)
                    .apply()
                saved = true
            },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = Shuaka,
                contentColor = Color.White
            ),
            shape = RoundedCornerShape(4.dp)
        ) {
            Text("保存")
        }

        if (saved) {
            Text(
                text = "設定を保存しました",
                color = MaterialTheme.colorScheme.primary
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "v${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
            color = TextMuted,
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace,
            modifier = Modifier.fillMaxWidth(),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
    }
}

@Composable
private fun BackgroundStyleOption(
    label: String,
    selected: Boolean,
    onSelect: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        RadioButton(
            selected = selected,
            onClick = onSelect,
            colors = RadioButtonDefaults.colors(
                selectedColor = Kinpaku,
                unselectedColor = TextMuted
            )
        )
        Text(label, color = Zouge)
    }
}

@Composable
private fun ThemeModeOption(
    label: String,
    description: String,
    selected: Boolean,
    onSelect: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        RadioButton(
            selected = selected,
            onClick = onSelect,
            colors = RadioButtonDefaults.colors(
                selectedColor = Kinpaku,
                unselectedColor = TextMuted
            )
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, color = Zouge)
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = TextMuted
            )
        }
    }
}

@Composable
fun DebugLogDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val entries = remember { AppLogger.getEntries() }
    val listState = rememberLazyListState()

    LaunchedEffect(entries.size) {
        if (entries.isNotEmpty()) listState.scrollToItem(entries.size - 1)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Shikkoku,
        title = {
            Text("Debug Log (${entries.size})", color = Kinpaku)
        },
        text = {
            Column {
                // Copy to clipboard button
                TextButton(onClick = {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = ClipData.newPlainText("debug_log", entries.joinToString("\n"))
                    clipboard.setPrimaryClip(clip)
                    Toast.makeText(context, "ログをコピーしました", Toast.LENGTH_SHORT).show()
                }) {
                    Text("Copy All", color = Kinpaku)
                }
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(380.dp)
                ) {
                    items(entries) { entry ->
                        Text(
                            text = entry,
                            color = if (entry.contains("FAIL") || entry.contains("ERROR"))
                                Color(0xFFCC3333) else Color(0xFFAABBCC),
                            fontFamily = FontFamily.Monospace,
                            fontSize = 10.sp,
                            modifier = Modifier.padding(vertical = 1.dp)
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                AppLogger.clear()
                onDismiss()
            }) {
                Text("Clear & Close", color = Kinpaku)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Close", color = Color(0xFF888888))
            }
        }
    )
}
