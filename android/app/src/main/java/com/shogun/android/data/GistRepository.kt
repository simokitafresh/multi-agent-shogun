package com.shogun.android.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

object GistRepository {
    private val client = OkHttpClient()

    private fun extractGistId(gistUrl: String): String? {
        val trimmed = gistUrl.trimEnd('/')
        val id = trimmed.substringAfterLast('/')
        return id.ifBlank { null }
    }

    suspend fun fetchGist(gistUrl: String): Result<List<GistFile>> = withContext(Dispatchers.IO) {
        try {
            val gistId = extractGistId(gistUrl)
                ?: return@withContext Result.failure(IllegalArgumentException("Invalid Gist URL: $gistUrl"))

            val apiUrl = "https://api.github.com/gists/$gistId"
            val request = Request.Builder()
                .url(apiUrl)
                .header("Accept", "application/vnd.github+json")
                .header("X-GitHub-Api-Version", "2022-11-28")
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                return@withContext Result.failure(Exception("API error: ${response.code}"))
            }

            val body = response.body?.string()
                ?: return@withContext Result.failure(Exception("Empty response from Gist API"))

            val json = JSONObject(body)
            val filesObj = json.getJSONObject("files")
            val files = mutableListOf<GistFile>()

            for (key in filesObj.keys()) {
                val fileObj = filesObj.getJSONObject(key)
                files.add(
                    GistFile(
                        filename = fileObj.optString("filename", key),
                        language = fileObj.optString("language", ""),
                        size = fileObj.optInt("size", 0),
                        rawUrl = fileObj.optString("raw_url", ""),
                        truncated = fileObj.optBoolean("truncated", false),
                        content = fileObj.optString("content", ""),
                    )
                )
            }

            Result.success(files.sortedBy { it.filename })
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun fetchRawContent(rawUrl: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder().url(rawUrl).build()
            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                return@withContext Result.failure(Exception("Raw fetch failed: ${response.code}"))
            }
            val body = response.body?.string() ?: ""
            Result.success(body)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
