package com.shogun.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

private fun darkScheme(palette: SengokuPalette) = darkColorScheme(
    primary = palette.kinpaku,
    onPrimary = palette.shikkoku,
    primaryContainer = palette.surface2,
    onPrimaryContainer = palette.zouge,
    secondary = palette.shuaka,
    onSecondary = palette.zouge,
    secondaryContainer = palette.surface1,
    onSecondaryContainer = palette.zouge,
    tertiary = palette.matsuba,
    onTertiary = palette.zouge,
    tertiaryContainer = palette.surface1,
    onTertiaryContainer = palette.zouge,
    error = palette.kurenai,
    onError = palette.zouge,
    errorContainer = palette.surface2,
    onErrorContainer = palette.zouge,
    background = palette.surface0,
    onBackground = palette.textSecondary,
    surface = palette.surface1,
    onSurface = palette.textSecondary,
    surfaceVariant = palette.surface2,
    onSurfaceVariant = palette.textTertiary,
    outline = palette.borderStandard,
    outlineVariant = palette.borderEmphasis,
    scrim = palette.shikkoku,
    inverseSurface = palette.zouge,
    inverseOnSurface = palette.shikkoku,
    inversePrimary = palette.sumi,
)

private fun lightScheme(palette: SengokuPalette) = lightColorScheme(
    primary = palette.kinpaku,
    onPrimary = palette.surface1,
    primaryContainer = palette.surface2,
    onPrimaryContainer = palette.zouge,
    secondary = palette.shuaka,
    onSecondary = palette.surface1,
    secondaryContainer = palette.surface2,
    onSecondaryContainer = palette.zouge,
    tertiary = palette.matsuba,
    onTertiary = palette.surface1,
    tertiaryContainer = palette.surface2,
    onTertiaryContainer = palette.zouge,
    error = palette.kurenai,
    onError = palette.surface1,
    errorContainer = palette.surface2,
    onErrorContainer = palette.zouge,
    background = palette.surface0,
    onBackground = palette.textSecondary,
    surface = palette.surface1,
    onSurface = palette.textSecondary,
    surfaceVariant = palette.surface2,
    onSurfaceVariant = palette.textTertiary,
    outline = palette.borderStandard,
    outlineVariant = palette.borderEmphasis,
    scrim = palette.textSecondary,
    inverseSurface = DarkSengokuPalette.surface1,
    inverseOnSurface = DarkSengokuPalette.zouge,
    inversePrimary = palette.shuaka,
)

@Composable
fun ShogunTheme(
    themeMode: ThemeMode = ThemeMode.SYSTEM,
    content: @Composable () -> Unit,
) {
    val useDarkPalette = when (themeMode) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.DARK -> true
        ThemeMode.LIGHT -> false
        ThemeMode.BLACK -> true
    }
    val palette = when (themeMode) {
        ThemeMode.LIGHT -> LightSengokuPalette
        ThemeMode.BLACK -> BlackSengokuPalette
        ThemeMode.SYSTEM -> if (useDarkPalette) DarkSengokuPalette else LightSengokuPalette
        ThemeMode.DARK -> DarkSengokuPalette
    }
    val colorScheme = if (useDarkPalette && themeMode != ThemeMode.LIGHT) {
        darkScheme(palette)
    } else {
        lightScheme(palette)
    }

    CompositionLocalProvider(LocalSengokuPalette provides palette) {
        MaterialTheme(
            colorScheme = colorScheme,
            content = content,
        )
    }
}
