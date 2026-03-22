package com.shogun.android.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.shogun.android.data.AppDatabase
import com.shogun.android.data.MemoEntity
import com.shogun.android.ssh.SshManager
import com.shogun.android.util.PrefsKeys
import com.shogun.android.util.VoiceDictionary
import com.shogun.android.util.buildMemoAppendCommand
import java.util.UUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class MemoViewModel(application: Application) : AndroidViewModel(application) {
    private val sshManager = SshManager.getInstance()
    private val prefs = application.getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)
    private val memoDao = AppDatabase.getInstance(application).memoDao()
    private val syncMutex = Mutex()

    private val _memos = MutableStateFlow<List<MemoEntity>>(emptyList())
    val memos: StateFlow<List<MemoEntity>> = _memos.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _syncMessage = MutableStateFlow("オフライン保存中")
    val syncMessage: StateFlow<String> = _syncMessage.asStateFlow()

    private var syncLoopJob: Job? = null

    init {
        viewModelScope.launch {
            memoDao.observeAll().collectLatest { items ->
                _memos.value = items
            }
        }
        syncLoopJob = viewModelScope.launch {
            while (isActive) {
                syncUnsyncedMemos()
                delay(15000)
            }
        }
    }

    fun createMemo(title: String, body: String) {
        val cleanTitle = normalizeVoiceInput(title)
        val cleanBody = normalizeVoiceInput(body)
        if (cleanTitle.isBlank() && cleanBody.isBlank()) return

        viewModelScope.launch {
            val now = System.currentTimeMillis()
            memoDao.insert(
                MemoEntity(
                    id = UUID.randomUUID().toString(),
                    title = cleanTitle,
                    body = cleanBody,
                    createdAt = now,
                    updatedAt = now,
                    synced = false,
                )
            )
            syncUnsyncedMemos()
        }
    }

    fun updateMemo(memo: MemoEntity, title: String, body: String) {
        val cleanTitle = normalizeVoiceInput(title)
        val cleanBody = normalizeVoiceInput(body)
        if (cleanTitle.isBlank() && cleanBody.isBlank()) return

        viewModelScope.launch {
            memoDao.update(
                memo.copy(
                    title = cleanTitle,
                    body = cleanBody,
                    updatedAt = System.currentTimeMillis(),
                    synced = false,
                )
            )
            syncUnsyncedMemos()
        }
    }

    fun deleteMemo(memo: MemoEntity) {
        viewModelScope.launch {
            memoDao.deleteById(memo.id)
            if (_memos.value.isEmpty()) {
                _syncMessage.value = "メモはまだありません"
            }
        }
    }

    fun requestSync() {
        viewModelScope.launch {
            syncUnsyncedMemos()
        }
    }

    private suspend fun syncUnsyncedMemos() {
        if (!sshManager.isConnected()) {
            _syncMessage.value = "オフライン保存中"
            return
        }

        val projectPath = prefs.getString(PrefsKeys.PROJECT_PATH, "")?.trim().orEmpty()
        if (projectPath.isBlank()) {
            _syncMessage.value = "同期には設定画面のプロジェクトパスが必要です"
            return
        }

        syncMutex.withLock {
            val unsynced = memoDao.getUnsynced()
            if (unsynced.isEmpty()) {
                _syncMessage.value = "すべてWSLへ同期済み"
                return
            }

            _isSyncing.value = true
            try {
                var syncedCount = 0
                for (memo in unsynced) {
                    val command = buildMemoAppendCommand(projectPath, memo, System.currentTimeMillis())
                    val result = sshManager.execCommand(command)
                    if (result.isFailure) {
                        _syncMessage.value = "同期失敗: ${result.exceptionOrNull()?.message ?: "unknown error"}"
                        return
                    }
                    memoDao.markSynced(memo.id)
                    syncedCount += 1
                }
                _syncMessage.value = "${syncedCount}件をWSLへ同期"
            } finally {
                _isSyncing.value = false
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        syncLoopJob?.cancel()
    }

    private fun normalizeVoiceInput(text: String): String {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return trimmed
        return VoiceDictionary(prefs).apply(trimmed)
    }
}
