package com.shogun.android.util

import com.shogun.android.data.MemoEntity
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Base64

private val memoTimestampFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")

private val memoSyncTimestampFormatter: DateTimeFormatter =
    DateTimeFormatter.ISO_OFFSET_DATE_TIME.withZone(ZoneId.systemDefault())

fun formatMemoDisplayTime(timestamp: Long): String =
    memoTimestampFormatter.format(Instant.ofEpochMilli(timestamp).atZone(ZoneId.systemDefault()))

fun buildMemoYamlEntry(memo: MemoEntity, syncedAtMillis: Long): String {
    val title = memo.title.ifBlank { "無題メモ" }
    val bodyLines = memo.body
        .replace("\r\n", "\n")
        .replace("\r", "\n")
        .lines()
        .ifEmpty { listOf("") }

    val lines = mutableListOf(
        "  - id: \"${escapeYamlDoubleQuoted(memo.id)}\"",
        "    title: \"${escapeYamlDoubleQuoted(title)}\"",
        "    body: |-",
    )
    lines += bodyLines.map { "      $it" }
    lines += listOf(
        "    created_at: \"${formatMemoSyncTime(memo.createdAt)}\"",
        "    synced_at: \"${formatMemoSyncTime(syncedAtMillis)}\"",
        "",
    )
    return lines.joinToString("\n")
}

fun buildMemoAppendCommand(projectPath: String, memo: MemoEntity, syncedAtMillis: Long): String {
    val encodedEntry = Base64.getEncoder()
        .encodeToString(buildMemoYamlEntry(memo, syncedAtMillis).toByteArray(StandardCharsets.UTF_8))
    val escapedPath = shellSingleQuote("$projectPath/queue/lord_memos.yaml")
    return """
python3 - <<'PY'
from pathlib import Path
import base64

path = Path($escapedPath)
entry = base64.b64decode('$encodedEntry').decode('utf-8')
path.parent.mkdir(parents=True, exist_ok=True)
if not path.exists() or path.stat().st_size == 0:
    path.write_text("memos:\n", encoding="utf-8")
with path.open("a", encoding="utf-8") as handle:
    handle.write(entry)
PY
""".trimIndent()
}

private fun formatMemoSyncTime(timestamp: Long): String =
    memoSyncTimestampFormatter.format(Instant.ofEpochMilli(timestamp))

private fun escapeYamlDoubleQuoted(value: String): String =
    value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")

private fun shellSingleQuote(value: String): String =
    "'${value.replace("'", "'\"'\"'")}'"
