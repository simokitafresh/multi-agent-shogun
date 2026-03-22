package com.shogun.android.util

import com.shogun.android.data.MemoEntity
import org.junit.Assert.assertTrue
import org.junit.Test

class MemoSyncFormatterTest {
    @Test
    fun `yaml entry keeps multiline body and metadata`() {
        val memo = MemoEntity(
            id = "memo-1",
            title = "改善案",
            body = "1行目\n2行目",
            createdAt = 1_710_000_000_000,
            updatedAt = 1_710_000_000_000,
            synced = false,
        )

        val entry = buildMemoYamlEntry(memo, syncedAtMillis = 1_710_000_123_000)

        assertTrue(entry.contains("  - id: \"memo-1\""))
        assertTrue(entry.contains("    title: \"改善案\""))
        assertTrue(entry.contains("    body: |-"))
        assertTrue(entry.contains("      1行目\n      2行目"))
        assertTrue(entry.contains("    created_at: \""))
        assertTrue(entry.contains("    synced_at: \""))
    }

    @Test
    fun `append command targets lord memos file`() {
        val memo = MemoEntity(
            id = "memo-2",
            title = "sync",
            body = "body",
            createdAt = 1_710_000_000_000,
            updatedAt = 1_710_000_000_000,
            synced = false,
        )

        val command = buildMemoAppendCommand("/srv/shogun", memo, syncedAtMillis = 1_710_000_123_000)

        assertTrue(command.contains("Path('/srv/shogun/queue/lord_memos.yaml')"))
        assertTrue(command.contains("path.write_text(\"memos:\\n\", encoding=\"utf-8\")"))
        assertTrue(command.contains("base64.b64decode"))
    }
}
