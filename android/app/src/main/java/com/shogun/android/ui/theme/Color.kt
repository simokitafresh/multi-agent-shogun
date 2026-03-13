package com.shogun.android.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

data class SengokuPalette(
    val shikkoku: Color,
    val sumi: Color,
    val kinpaku: Color,
    val zouge: Color,
    val shuaka: Color,
    val matsuba: Color,
    val tetsukon: Color,
    val kurenai: Color,
    val surface0: Color,
    val surface1: Color,
    val surface2: Color,
    val surface3: Color,
    val surface4: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val textMuted: Color,
    val borderStandard: Color,
    val borderEmphasis: Color,
    val borderFocus: Color,
    val linkGold: Color,
)

internal val DarkSengokuPalette = SengokuPalette(
    shikkoku = Color(0xFF1A1A1A),
    sumi = Color(0xFF2D2D2D),
    kinpaku = Color(0xFFC9A94E),
    zouge = Color(0xFFE8DCC8),
    shuaka = Color(0xFFB33B24),
    matsuba = Color(0xFF3C6E47),
    tetsukon = Color(0xFF3A4A5C),
    kurenai = Color(0xFFCC3333),
    surface0 = Color(0xFF1A1A1A),
    surface1 = Color(0xFF2D2D2D),
    surface2 = Color(0xFF363636),
    surface3 = Color(0xFF404040),
    surface4 = Color(0xFF1E1E1E),
    textPrimary = Color(0xFFC9A94E),
    textSecondary = Color(0xFFE8DCC8),
    textTertiary = Color(0xFF8A9BB0),
    textMuted = Color(0xFF888888),
    borderStandard = Color(0x33C9A94E),
    borderEmphasis = Color(0x66C9A94E),
    borderFocus = Color(0x99C9A94E),
    linkGold = Color(0xFFD4B96A),
)

internal val LightSengokuPalette = SengokuPalette(
    shikkoku = Color(0xFFF5EFE3),
    sumi = Color(0xFFFFF9F0),
    kinpaku = Color(0xFF7A5A16),
    zouge = Color(0xFF332A22),
    shuaka = Color(0xFF9B3A2A),
    matsuba = Color(0xFF355F3D),
    tetsukon = Color(0xFF5E564B),
    kurenai = Color(0xFFB53A33),
    surface0 = Color(0xFFF5EFE3),
    surface1 = Color(0xFFFFF9F0),
    surface2 = Color(0xFFE9DDCA),
    surface3 = Color(0xFFE0D2BE),
    surface4 = Color(0xFFF8F1E6),
    textPrimary = Color(0xFF7A5A16),
    textSecondary = Color(0xFF332A22),
    textTertiary = Color(0xFF5E564B),
    textMuted = Color(0xFF6F655A),
    borderStandard = Color(0x337A5A16),
    borderEmphasis = Color(0x667A5A16),
    borderFocus = Color(0x997A5A16),
    linkGold = Color(0xFF8C6A1F),
)

internal val BlackSengokuPalette = SengokuPalette(
    shikkoku = Color(0xFF000000),
    sumi = Color(0xFF0A0A0A),
    kinpaku = Color(0xFFD4B96A),
    zouge = Color(0xFFF5F1E8),
    shuaka = Color(0xFFC24A33),
    matsuba = Color(0xFF4C8A58),
    tetsukon = Color(0xFF8D98A8),
    kurenai = Color(0xFFE05A52),
    surface0 = Color(0xFF000000),
    surface1 = Color(0xFF0A0A0A),
    surface2 = Color(0xFF141414),
    surface3 = Color(0xFF1D1D1D),
    surface4 = Color(0xFF101010),
    textPrimary = Color(0xFFD4B96A),
    textSecondary = Color(0xFFF5F1E8),
    textTertiary = Color(0xFFB9B2A7),
    textMuted = Color(0xFF8E8A84),
    borderStandard = Color(0x33D4B96A),
    borderEmphasis = Color(0x66D4B96A),
    borderFocus = Color(0x99D4B96A),
    linkGold = Color(0xFFE4C97A),
)

internal val LocalSengokuPalette = staticCompositionLocalOf { DarkSengokuPalette }

val Shikkoku: Color
    @Composable get() = LocalSengokuPalette.current.shikkoku

val Sumi: Color
    @Composable get() = LocalSengokuPalette.current.sumi

val Kinpaku: Color
    @Composable get() = LocalSengokuPalette.current.kinpaku

val Zouge: Color
    @Composable get() = LocalSengokuPalette.current.zouge

val Shuaka: Color
    @Composable get() = LocalSengokuPalette.current.shuaka

val Matsuba: Color
    @Composable get() = LocalSengokuPalette.current.matsuba

val Tetsukon: Color
    @Composable get() = LocalSengokuPalette.current.tetsukon

val Kurenai: Color
    @Composable get() = LocalSengokuPalette.current.kurenai

val Surface0: Color
    @Composable get() = LocalSengokuPalette.current.surface0

val Surface1: Color
    @Composable get() = LocalSengokuPalette.current.surface1

val Surface2: Color
    @Composable get() = LocalSengokuPalette.current.surface2

val Surface3: Color
    @Composable get() = LocalSengokuPalette.current.surface3

val Surface4: Color
    @Composable get() = LocalSengokuPalette.current.surface4

val TextPrimary: Color
    @Composable get() = LocalSengokuPalette.current.textPrimary

val TextSecondary: Color
    @Composable get() = LocalSengokuPalette.current.textSecondary

val TextTertiary: Color
    @Composable get() = LocalSengokuPalette.current.textTertiary

val TextMuted: Color
    @Composable get() = LocalSengokuPalette.current.textMuted

val BorderStandard: Color
    @Composable get() = LocalSengokuPalette.current.borderStandard

val BorderEmphasis: Color
    @Composable get() = LocalSengokuPalette.current.borderEmphasis

val BorderFocus: Color
    @Composable get() = LocalSengokuPalette.current.borderFocus

val StatusConnected: Color
    @Composable get() = LocalSengokuPalette.current.matsuba

val StatusDisconnected: Color
    @Composable get() = LocalSengokuPalette.current.kurenai

val StatusReconnecting: Color
    @Composable get() = LocalSengokuPalette.current.kinpaku

val LinkGold: Color
    @Composable get() = LocalSengokuPalette.current.linkGold
