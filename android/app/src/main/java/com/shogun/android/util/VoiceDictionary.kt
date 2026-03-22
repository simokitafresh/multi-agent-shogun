package com.shogun.android.util

import android.content.SharedPreferences
import org.json.JSONObject

class VoiceDictionary(
    private val prefs: SharedPreferences
) {
    private val entries = loadInitialEntries()

    fun getAll(): Map<String, String> = LinkedHashMap(entries)

    fun add(from: String, to: String) {
        if (from.isBlank()) return
        entries[from] = to
        persist()
    }

    fun remove(from: String) {
        if (entries.remove(from) != null) {
            persist()
        }
    }

    fun resetToPreset() {
        entries.clear()
        entries.putAll(presetEntries)
        persist()
    }

    fun apply(text: String): String = applyAll(text)

    fun applyAll(text: String): String {
        if (entries.isEmpty()) return text

        return entries.entries
            .asSequence()
            .filter { it.key.isNotEmpty() }
            .sortedByDescending { it.key.length }
            .fold(text) { current, (from, to) -> current.replace(from, to) }
    }

    private fun loadInitialEntries(): LinkedHashMap<String, String> {
        val stored = prefs.getString(PrefsKeys.VOICE_DICTIONARY, null)
        if (stored.isNullOrBlank()) {
            return LinkedHashMap(presetEntries)
        }

        return try {
            val mergedEntries = mergeWithPreset(JSONObject(stored))
            persistMergedIfNeeded(mergedEntries, stored)
            mergedEntries
        } catch (_: Exception) {
            LinkedHashMap(presetEntries)
        }
    }

    private fun mergeWithPreset(json: JSONObject): LinkedHashMap<String, String> =
        LinkedHashMap<String, String>().apply {
            putAll(presetEntries)
            json.keys().forEach { key ->
                if (key.isNotEmpty() && !presetEntries.containsKey(key)) {
                    put(key, json.optString(key, ""))
                }
            }
        }

    private fun persistMergedIfNeeded(
        mergedEntries: LinkedHashMap<String, String>,
        originalStored: String
    ) {
        val mergedJson = JSONObject().apply {
            mergedEntries.forEach { (from, to) -> put(from, to) }
        }
        if (mergedJson.toString() != originalStored) {
            prefs.edit().putString(PrefsKeys.VOICE_DICTIONARY, mergedJson.toString()).apply()
        }
    }

    private fun persist() {
        val json = JSONObject()
        entries.forEach { (from, to) -> json.put(from, to) }
        prefs.edit().putString(PrefsKeys.VOICE_DICTIONARY, json.toString()).apply()
    }

    companion object {
        private data class PresetCategory(
            val name: String,
            val replacements: LinkedHashMap<String, String>
        )

        private fun replacementsOf(vararg entries: Pair<String, String>): LinkedHashMap<String, String> =
            linkedMapOf(*entries)

        private val presetCategories = listOf(
            PresetCategory(
                name = "shogun_terms",
                replacements = replacementsOf(
                    "しょうぐん" to "将軍",
                    "将軍様" to "将軍",
                    "過労" to "家老",
                    "かろう" to "家老",
                    "忍じゃ" to "忍者",
                    "にんじゃ" to "忍者",
                    "さすけ" to "佐助",
                    "サスケ" to "佐助",
                    "きりまる" to "霧丸",
                    "はやて" to "疾風",
                    "かげまる" to "影丸",
                    "はんぞう" to "半蔵",
                    "さいぞう" to "才蔵",
                    "こたろう" to "小太郎",
                    "とびさる" to "飛猿",
                    "死神" to "四神",
                    "しじん" to "四神",
                    "こまんど" to "cmd",
                    "コマンドID" to "cmd",
                    "シーエムディー" to "cmd",
                    "インボックス" to "inbox",
                    "エヌティーファイ" to "ntfy",
                    "ダッシュボート" to "ダッシュボード",
                    "強訓" to "教訓",
                    "やむる" to "YAML",
                    "コールド" to "コード",
                )
            ),
            PresetCategory(
                name = "technical_terms",
                replacements = replacementsOf(
                    "エーピーアイ" to "API",
                    "エイピーアイ" to "API",
                    "ギットハブ" to "GitHub",
                    "ギット" to "Git",
                    "プルリクエスト" to "PR",
                    "プルリク" to "PR",
                    "ジェイソン" to "JSON",
                    "ジェーソン" to "JSON",
                    "ワイエーエムエル" to "YAML",
                    "ヤムルファイル" to "YAMLファイル",
                    "コトリン" to "Kotlin",
                    "グラドル" to "Gradle",
                    "ジェーユニット" to "JUnit",
                    "エーピーケー" to "APK",
                    "エスキューエル" to "SQL",
                    "ウェブソケット" to "WebSocket",
                    "デバッグビルド" to "debug build",
                    "リリースビルド" to "release build",
                    "ユーアイ" to "UI",
                    "ユーエックス" to "UX",
                    "シーアイ" to "CI",
                    "シーディー" to "CD",
                    "オープンエーアイ" to "OpenAI",
                    "チャットジーピーティー" to "ChatGPT",
                    "コーデックス" to "Codex",
                )
            ),
            PresetCategory(
                name = "dm_signal_terms",
                replacements = replacementsOf(
                    "ディーエムシグナル" to "DM-Signal",
                    "ディーエム" to "DM",
                    "ポートホリオ" to "ポートフォリオ",
                    "ポートフォリよ" to "ポートフォリオ",
                    "シグなる" to "シグナル",
                    "シグナルズ" to "シグナル",
                    "デテリオレション" to "デテリオレーション",
                    "デリテリオレーション" to "デテリオレーション",
                    "ドローダン" to "ドローダウン",
                    "泥ダウン" to "ドローダウン",
                    "シャープレイシオ" to "シャープレシオ",
                    "ソルティノレイシオ" to "ソルティノレシオ",
                    "ボラテリティ" to "ボラティリティ",
                    "バッグテスト" to "バックテスト",
                    "リスク音" to "リスクオン",
                    "リスク夫" to "リスクオフ",
                    "損ぎり" to "損切り",
                    "そんぎり" to "損切り",
                    "利かく" to "利確",
                    "りかく" to "利確",
                    "含み駅" to "含み益",
                    "移動兵器" to "移動平均",
                    "終わりね" to "終値",
                    "はじめね" to "始値",
                    "りばらんす" to "リバランス",
                )
            ),
            PresetCategory(
                name = "general_normalization",
                replacements = replacementsOf(
                    "だっしゅぼーど" to "ダッシュボード",
                    "ぷりせっと" to "プリセット",
                    "ばっくあっぷ" to "バックアップ",
                    "あっぷでーと" to "アップデート",
                    "しょーとかっと" to "ショートカット",
                    "ふぉるだ" to "フォルダ",
                    "ふぁいる" to "ファイル",
                    "ばーじょん" to "バージョン",
                    "せってぃんぐ" to "セッティング",
                    "りりーす" to "リリース",
                    "でぃれくとり" to "ディレクトリ",
                    "さーばー" to "サーバー",
                    "くらいあんと" to "クライアント",
                    "すれっど" to "スレッド",
                    "きゃっしゅ" to "キャッシュ",
                    "ぱふぉーまんす" to "パフォーマンス",
                    "れいてんし" to "レイテンシ",
                    "するーぷっと" to "スループット",
                    "おふらいん" to "オフライン",
                    "おんらいん" to "オンライン",
                    "ろーかる" to "ローカル",
                    "りもーと" to "リモート",
                    "わーくふろー" to "ワークフロー",
                    "ふぃーどばっく" to "フィードバック",
                    "ふぉーまっと" to "フォーマット",
                )
            ),
        )

        private val presetEntries = LinkedHashMap<String, String>().apply {
            presetCategories.forEach { putAll(it.replacements) }
        }

        internal fun presetCategoryCounts(): Map<String, Int> =
            presetCategories.associate { it.name to it.replacements.size }

        internal fun presetSize(): Int = presetEntries.size
    }
}
