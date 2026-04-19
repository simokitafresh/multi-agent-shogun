package com.shogun.android.util

import org.junit.Assert.assertEquals
import org.junit.Test

class TmuxCommandBuilderTest {

    @Test
    fun pasteBufferSendCommand_escapesSingleQuotesAndTargets() {
        val tmux = Defaults.TMUX
        val command = TmuxCommandBuilder.pasteBufferSendCommand("shogun:main", "don't stop")

        assertEquals(
            "$tmux set-buffer -b 'android_send_shogun_main' 'don'\"'\"'t stop' && " +
                "$tmux paste-buffer -d -b 'android_send_shogun_main' -t 'shogun:main' && " +
                "$tmux send-keys -t 'shogun:main' Enter",
            command
        )
    }

    @Test
    fun pasteBufferSendCommand_preservesDoubleQuotesBackslashesAndJapanese() {
        val tmux = Defaults.TMUX
        val command = TmuxCommandBuilder.pasteBufferSendCommand(
            "shogun:agents.3",
            "say \"hi\" \\\\ 日本語"
        )

        assertEquals(
            "$tmux set-buffer -b 'android_send_shogun_agents_3' 'say \"hi\" \\\\ 日本語' && " +
                "$tmux paste-buffer -d -b 'android_send_shogun_agents_3' -t 'shogun:agents.3' && " +
                "$tmux send-keys -t 'shogun:agents.3' Enter",
            command
        )
    }
}
