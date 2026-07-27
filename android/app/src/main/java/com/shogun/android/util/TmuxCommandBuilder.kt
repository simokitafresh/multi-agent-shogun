package com.shogun.android.util

internal object TmuxCommandBuilder {

    fun pasteBufferSendCommand(target: String, text: String): String {
        return legacyPasteBufferSendCommand(target, text)
    }

    fun pasteBufferSendCommand(
        target: String,
        text: String,
        messageId: String,
        retryCount: Int
    ): String {
        val quotedTarget = shellSingleQuote(target)
        val quotedText = shellSingleQuote(text)
        val quotedBuffer = shellSingleQuote(bufferName(target))
        val quotedMessageId = shellSingleQuote(messageId)
        val quotedRetryCount = shellSingleQuote(retryCount.toString())
        val claimNamespace = bufferName(target)
        return buildString {
            append("claim_root=\"\${XDG_RUNTIME_DIR:-/tmp}/shogun-android-input/")
            append(claimNamespace)
            append("\"")
            append("; message_id=")
            append(quotedMessageId)
            append("; retry_count=")
            append(quotedRetryCount)
            append("; mkdir -p \"\$claim_root\"; claim=\"\$claim_root/\$message_id\"; ")
            // Recover only abandoned, incomplete claims; a completed claim is never reused.
            append("find \"\$claim\" -maxdepth 0 -type d -empty -mmin +2 -delete 2>/dev/null || true; ")
            // Bound completed claim and event-log retention without touching active claims.
            append("find \"\$claim_root\" -mindepth 2 -maxdepth 2 -name completed -mtime +7 -delete 2>/dev/null || true; ")
            append("find \"\$claim_root\" -mindepth 1 -maxdepth 1 -type d -empty -mtime +7 -delete 2>/dev/null || true; ")
            append("if [ -f \"\$claim_root/events.jsonl\" ] && [ \"\$(wc -c < \"\$claim_root/events.jsonl\")\" -gt 1048576 ]; then ")
            append("tail -n 1000 \"\$claim_root/events.jsonl\" > \"\$claim_root/events.jsonl.tmp\" && mv \"\$claim_root/events.jsonl.tmp\" \"\$claim_root/events.jsonl\"; fi; ")
            append("if mkdir \"\$claim\" 2>/dev/null; then ")
            append("if ")
            append(Defaults.TMUX)
            append(" set-buffer -b ")
            append(quotedBuffer)
            append(" ")
            append(quotedText)
            append(" && ")
            append(Defaults.TMUX)
            append(" paste-buffer -d -b ")
            append(quotedBuffer)
            append(" -t ")
            append(quotedTarget)
            append(" && ")
            append(Defaults.TMUX)
            append(" send-keys -t ")
            append(quotedTarget)
            append(" Enter; then ")
            append("printf '%s\\n' \"source=android message_id=\$message_id retry_count=\$retry_count outcome=success\" >> \"\$claim_root/events.jsonl\"; ")
            append("touch \"\$claim/completed\"; printf '%s\\n' ANDROID_INPUT_SUCCESS; ")
            append("else rmdir \"\$claim\" 2>/dev/null || true; ")
            append("printf '%s\\n' \"source=android message_id=\$message_id retry_count=\$retry_count outcome=failure\" >> \"\$claim_root/events.jsonl\"; exit 1; fi; ")
            append("else printf '%s\\n' \"source=android message_id=\$message_id retry_count=\$retry_count outcome=duplicate_suppressed\" >> \"\$claim_root/events.jsonl\"; ")
            append("printf '%s\\n' ANDROID_INPUT_DUPLICATE; fi")
        }
    }

    private fun legacyPasteBufferSendCommand(target: String, text: String): String {
        val quotedTarget = shellSingleQuote(target)
        val quotedText = shellSingleQuote(text)
        val quotedBuffer = shellSingleQuote(bufferName(target))
        return "${Defaults.TMUX} set-buffer -b $quotedBuffer $quotedText && " +
            "${Defaults.TMUX} paste-buffer -d -b $quotedBuffer -t $quotedTarget && " +
            "${Defaults.TMUX} send-keys -t $quotedTarget Enter"
    }

    internal fun shellSingleQuote(text: String): String {
        return "'${text.replace("'", "'\"'\"'")}'"
    }

    private fun bufferName(target: String): String {
        return "android_send_" + target.replace(Regex("[^A-Za-z0-9_]"), "_")
    }
}
