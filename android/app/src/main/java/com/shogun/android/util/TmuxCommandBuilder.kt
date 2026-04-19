package com.shogun.android.util

internal object TmuxCommandBuilder {

    fun pasteBufferSendCommand(target: String, text: String): String {
        val quotedTarget = shellSingleQuote(target)
        val quotedText = shellSingleQuote(text)
        val quotedBuffer = shellSingleQuote(bufferName(target))
        return buildString {
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
            append(" Enter")
        }
    }

    internal fun shellSingleQuote(text: String): String {
        return "'${text.replace("'", "'\"'\"'")}'"
    }

    private fun bufferName(target: String): String {
        return "android_send_" + target.replace(Regex("[^A-Za-z0-9_]"), "_")
    }
}
