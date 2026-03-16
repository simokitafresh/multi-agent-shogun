package com.shogun.android.util

import android.content.SharedPreferences
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.system.measureTimeMillis

class VoiceDictionaryTest {
    @Test
    fun `preset categories keep 20 plus entries each and total exceeds 100`() {
        val counts = VoiceDictionary.presetCategoryCounts()

        assertEquals(4, counts.size)
        counts.values.forEach { count ->
            assertTrue("each category should have at least 20 entries", count >= 20)
        }
        assertTrue("total preset entries should exceed 100", VoiceDictionary.presetSize() >= 100)
    }

    @Test
    fun `preset dictionary corrects representative phrases across categories`() {
        val dictionary = VoiceDictionary(FakeSharedPreferences())

        val corrected = dictionary.applyAll(
            "過労がギットハブでディーエムシグナルを更新し、" +
                "だっしゅぼーどを見た"
        )

        assertEquals(
            "家老がGitHubでDM-Signalを更新し、ダッシュボードを見た",
            corrected
        )
    }

    @Test
    fun `existing corrections remain available alongside new presets`() {
        val dictionary = VoiceDictionary(FakeSharedPreferences())

        assertEquals("家老と四神とコード", dictionary.applyAll("過労と死神とコールド"))
        assertTrue(dictionary.getAll().containsKey("ギットハブ"))
        assertTrue(dictionary.getAll().containsKey("ディーエムシグナル"))
    }

    @Test
    fun `stored entries merge with latest presets while preserving custom entries`() {
        val prefs = FakeSharedPreferences()
        prefs.edit().putString(
            PrefsKeys.VOICE_DICTIONARY,
            JSONObject()
                .put("ギットハブ", "旧GitHub")
                .put("ユーザー独自", "独自変換")
                .toString()
        ).apply()

        val dictionary = VoiceDictionary(prefs)
        val mergedEntries = dictionary.getAll()
        val persistedJson = JSONObject(prefs.getString(PrefsKeys.VOICE_DICTIONARY, "{}"))

        assertEquals("GitHub", mergedEntries["ギットハブ"])
        assertEquals("独自変換", mergedEntries["ユーザー独自"])
        assertTrue(mergedEntries.containsKey("ディーエムシグナル"))
        assertEquals("GitHub", persistedJson.getString("ギットハブ"))
        assertEquals("独自変換", persistedJson.getString("ユーザー独自"))
    }

    @Test
    fun `applyAll stays fast with hundred plus preset entries`() {
        val dictionary = VoiceDictionary(FakeSharedPreferences())
        val text = buildString {
            repeat(40) {
                append("エーピーアイとギットハブとディーエムシグナルとだっしゅぼーど ")
            }
        }

        val elapsedMs = measureTimeMillis {
            val corrected = dictionary.applyAll(text)
            assertTrue(corrected.contains("API"))
            assertTrue(corrected.contains("GitHub"))
            assertTrue(corrected.contains("DM-Signal"))
            assertTrue(corrected.contains("ダッシュボード"))
        }

        assertTrue("dictionary applyAll should finish comfortably under 1s", elapsedMs < 1_000)
    }

    private class FakeSharedPreferences : SharedPreferences {
        private val values = linkedMapOf<String, Any?>()

        override fun getAll(): MutableMap<String, *> = LinkedHashMap(values)

        override fun getString(key: String?, defValue: String?): String? =
            values[key] as? String ?: defValue

        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
            @Suppress("UNCHECKED_CAST")
            ((values[key] as? Set<String>)?.toMutableSet() ?: defValues)

        override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue

        override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue

        override fun getFloat(key: String?, defValue: Float): Float = values[key] as? Float ?: defValue

        override fun getBoolean(key: String?, defValue: Boolean): Boolean =
            values[key] as? Boolean ?: defValue

        override fun contains(key: String?): Boolean = values.containsKey(key)

        override fun edit(): SharedPreferences.Editor = Editor(values)

        override fun registerOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) = Unit

        override fun unregisterOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) = Unit
    }

    private class Editor(
        private val values: LinkedHashMap<String, Any?>
    ) : SharedPreferences.Editor {
        private val staged = linkedMapOf<String, Any?>()
        private var clearRequested = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor = apply {
            staged[key.orEmpty()] = value
        }

        override fun putStringSet(
            key: String?,
            values: MutableSet<String>?
        ): SharedPreferences.Editor = apply {
            staged[key.orEmpty()] = values?.toSet()
        }

        override fun putInt(key: String?, value: Int): SharedPreferences.Editor = apply {
            staged[key.orEmpty()] = value
        }

        override fun putLong(key: String?, value: Long): SharedPreferences.Editor = apply {
            staged[key.orEmpty()] = value
        }

        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor = apply {
            staged[key.orEmpty()] = value
        }

        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor = apply {
            staged[key.orEmpty()] = value
        }

        override fun remove(key: String?): SharedPreferences.Editor = apply {
            staged[key.orEmpty()] = null
        }

        override fun clear(): SharedPreferences.Editor = apply {
            clearRequested = true
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            if (clearRequested) {
                values.clear()
            }
            staged.forEach { (key, value) ->
                if (value == null) {
                    values.remove(key)
                } else {
                    values[key] = value
                }
            }
            staged.clear()
            clearRequested = false
        }
    }
}
