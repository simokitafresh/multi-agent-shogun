package com.shogun.android.data

data class GistFile(
    val filename: String,
    val language: String,
    val size: Int,
    val rawUrl: String,
    val truncated: Boolean,
    val content: String,
)
