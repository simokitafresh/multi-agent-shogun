package com.shogun.android

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.offset
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.IntOffset
import com.shogun.android.ui.theme.*
import com.shogun.android.util.PrefsKeys
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.shogun.android.ui.AgentsScreen
import com.shogun.android.ui.DashboardScreen
import com.shogun.android.ui.SettingsScreen
import com.shogun.android.ui.ShogunScreen
import com.shogun.android.ui.theme.ShogunTheme
import kotlin.math.roundToInt

sealed class Screen(val route: String, val label: String, val icon: ImageVector) {
    object Shogun : Screen("shogun", "将軍", Icons.Default.Star)
    object Agents : Screen("agents", "エージェント", Icons.Default.List)
    object Dashboard : Screen("dashboard", "戦況", Icons.Default.Home)
    object Settings : Screen("settings", "設定", Icons.Default.Settings)
}

val bottomNavItems = listOf(
    Screen.Shogun,
    Screen.Agents,
    Screen.Dashboard,
    Screen.Settings
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        NotificationHelper.initChannels(this)
        setContent {
            ShogunTheme {
                ShogunApp()
            }
        }
        handleShareIntent(intent)
        // Only start NtfyService if notification permission is granted (Android 13+)
        val hasNotifPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else true
        if (hasNotifPerm && getSharedPreferences(PrefsKeys.PREFS_NAME, MODE_PRIVATE)
                .getBoolean(PrefsKeys.NOTIFICATION_ENABLED, true)) {
            try {
                startForegroundService(Intent(this, NtfyService::class.java))
            } catch (_: Exception) {
                // Foreground service start blocked by system — skip silently
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent) {
        val imageUris: List<Uri> = when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                listOfNotNull(uri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                } ?: emptyList()
            }
            else -> return
        }
        if (imageUris.isEmpty()) return

        val prefs = getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)
        val topic = prefs.getString(PrefsKeys.NTFY_TOPIC, com.shogun.android.util.Defaults.NTFY_TOPIC)
            ?.trim()
            .takeUnless { it.isNullOrEmpty() }
            ?: com.shogun.android.util.Defaults.NTFY_TOPIC

        val total = imageUris.size
        Toast.makeText(this, "ntfy送信中... (${total}件)", Toast.LENGTH_SHORT).show()
        lifecycleScope.launch {
            var success = 0
            var failed = 0
            for (uri in imageUris) {
                try {
                    sendImageToNtfy(uri, topic)
                    success++
                } catch (_: Exception) {
                    failed++
                }
            }
            val msg = if (failed == 0) "✅ ${success}件 ntfy送信完了"
                else "✅ ${success}件 完了 / ❌ ${failed}件 失敗"
            Toast.makeText(this@MainActivity, msg, Toast.LENGTH_LONG).show()
        }
    }

    private suspend fun sendImageToNtfy(uri: Uri, topic: String) = withContext(Dispatchers.IO) {
        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw Exception("Cannot open image")
        val mimeType = contentResolver.getType(uri) ?: "image/png"
        val filename = getFilenameFromUri(uri)
            ?: "screenshot_${System.currentTimeMillis()}.png"

        val client = OkHttpClient()
        val requestBody = bytes.toRequestBody(mimeType.toMediaType())
        val request = Request.Builder()
            .url("https://ntfy.sh/$topic")
            .put(requestBody)
            .addHeader("Filename", filename)
            .build()

        val response = client.newCall(request).execute()
        response.use {
            if (!it.isSuccessful) {
                throw Exception("ntfy upload failed: ${it.code}")
            }
        }
    }

    private fun getFilenameFromUri(uri: Uri): String? {
        contentResolver.query(uri, null, null, null, null)?.use { cursor: Cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                return cursor.getString(nameIndex)
            }
        }
        return null
    }
}

@Composable
fun ShogunApp() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val bottomBarHeight = 80.dp
    val bottomBarHeightPx = with(androidx.compose.ui.platform.LocalDensity.current) { bottomBarHeight.roundToPx().toFloat() }
    var bottomBarOffsetHeightPx by remember { mutableFloatStateOf(0f) }
    val nestedScrollConnection = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: androidx.compose.ui.geometry.Offset, source: NestedScrollSource): androidx.compose.ui.geometry.Offset {
                val delta = available.y
                val newOffset = (bottomBarOffsetHeightPx + delta).coerceIn(-bottomBarHeightPx, 0f)
                bottomBarOffsetHeightPx = newOffset
                return androidx.compose.ui.geometry.Offset.Zero
            }
        }
    }

    Scaffold(
        modifier = Modifier
            .fillMaxSize()
            .nestedScroll(nestedScrollConnection),
        bottomBar = {
            NavigationBar(
                modifier = Modifier.offset { IntOffset(0, -bottomBarOffsetHeightPx.roundToInt()) },
                containerColor = Shikkoku,
                contentColor = Kinpaku,
            ) {
                bottomNavItems.forEach { screen ->
                    NavigationBarItem(
                        icon = { Icon(screen.icon, contentDescription = screen.label) },
                        label = { Text(screen.label, fontSize = 10.sp, maxLines = 1) },
                        selected = currentRoute == screen.route,
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = Kinpaku,
                            selectedTextColor = Kinpaku,
                            unselectedIconColor = TextMuted,
                            unselectedTextColor = TextMuted,
                            indicatorColor = Sumi,
                        ),
                        onClick = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Shogun.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Shogun.route) { ShogunScreen() }
            composable(Screen.Agents.route) { AgentsScreen() }
            composable(Screen.Dashboard.route) { DashboardScreen() }
            composable(Screen.Settings.route) { SettingsScreen() }
        }
    }
}
