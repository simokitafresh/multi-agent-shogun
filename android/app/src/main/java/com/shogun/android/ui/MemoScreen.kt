package com.shogun.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shogun.android.R
import com.shogun.android.data.GistFile
import com.shogun.android.data.MemoEntity
import com.shogun.android.ui.theme.Kinpaku
import com.shogun.android.ui.theme.Kurenai
import com.shogun.android.ui.theme.Matsuba
import com.shogun.android.ui.theme.Shuaka
import com.shogun.android.ui.theme.Surface1
import com.shogun.android.ui.theme.TextMuted
import com.shogun.android.ui.theme.Zouge
import com.shogun.android.util.formatMemoDisplayTime
import com.shogun.android.viewmodel.MemoViewModel

@Composable
fun MemoScreen(viewModel: MemoViewModel = viewModel()) {
    val memos by viewModel.memos.collectAsState()
    val isSyncing by viewModel.isSyncing.collectAsState()
    val syncMessage by viewModel.syncMessage.collectAsState()
    val gistFiles by viewModel.gistFiles.collectAsState()
    val isGistLoading by viewModel.isGistLoading.collectAsState()
    val gistError by viewModel.gistError.collectAsState()
    val gistFileContent by viewModel.gistFileContent.collectAsState()
    val isGistContentLoading by viewModel.isGistContentLoading.collectAsState()

    var editingMemo by remember { mutableStateOf<MemoEntity?>(null) }
    var showCreateDialog by remember { mutableStateOf(false) }
    var deletingMemo by remember { mutableStateOf<MemoEntity?>(null) }
    var viewingGistFile by remember { mutableStateOf<GistFile?>(null) }

    LaunchedEffect(Unit) {
        viewModel.requestSync()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        ScreenBackground(imageResId = R.drawable.bg_castle) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Card(
                    colors = CardDefaults.cardColors(containerColor = Surface1.copy(alpha = 0.92f)),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                text = "開発アイデア帳",
                                style = MaterialTheme.typography.titleLarge,
                                color = Kinpaku,
                            )
                            Text(
                                text = syncMessage,
                                style = MaterialTheme.typography.bodyMedium,
                                color = Zouge,
                            )
                        }
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            if (isSyncing) {
                                Text(
                                    text = "同期中",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = Kinpaku,
                                )
                            }
                            IconButton(onClick = { viewModel.requestSync() }) {
                                Icon(
                                    imageVector = Icons.Default.Sync,
                                    contentDescription = "同期",
                                    tint = Kinpaku,
                                )
                            }
                        }
                    }
                }

                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    item {
                        GistFilesSection(
                            gistFiles = gistFiles,
                            isLoading = isGistLoading,
                            error = gistError,
                            onRefresh = { viewModel.refreshGist() },
                            onFileClick = { gistFile ->
                                viewingGistFile = gistFile
                                viewModel.loadGistFileContent(gistFile)
                            },
                        )
                    }

                    if (memos.isEmpty()) {
                        item {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 32.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    text = "まだメモはありません。\n右下のボタンから追加できます。",
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = Zouge,
                                )
                            }
                        }
                    } else {
                        items(memos, key = { it.id }) { memo ->
                            MemoCard(
                                memo = memo,
                                onEdit = { editingMemo = memo },
                                onDelete = { deletingMemo = memo },
                            )
                        }
                    }
                }
            }
        }

        FloatingActionButton(
            onClick = { showCreateDialog = true },
            containerColor = Shuaka,
            contentColor = Zouge,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(20.dp),
        ) {
            Icon(Icons.Default.Add, contentDescription = "メモを追加")
        }
    }

    if (showCreateDialog) {
        MemoEditorDialog(
            title = "新しいメモ",
            initialTitle = "",
            initialBody = "",
            onDismiss = { showCreateDialog = false },
            onSave = { title, body ->
                viewModel.createMemo(title, body)
                showCreateDialog = false
            },
        )
    }

    editingMemo?.let { memo ->
        MemoEditorDialog(
            title = "メモを編集",
            initialTitle = memo.title,
            initialBody = memo.body,
            onDismiss = { editingMemo = null },
            onSave = { title, body ->
                viewModel.updateMemo(memo, title, body)
                editingMemo = null
            },
        )
    }

    deletingMemo?.let { memo ->
        AlertDialog(
            onDismissRequest = { deletingMemo = null },
            containerColor = Surface1,
            title = { Text(text = "メモを削除", color = Kinpaku) },
            text = {
                Text(
                    text = "「${memo.title.ifBlank { "無題メモ" }}」を削除します。",
                    color = Zouge,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteMemo(memo)
                        deletingMemo = null
                    },
                ) {
                    Text("削除", color = Kurenai)
                }
            },
            dismissButton = {
                TextButton(onClick = { deletingMemo = null }) {
                    Text("戻る", color = Kinpaku)
                }
            },
        )
    }

    viewingGistFile?.let { gistFile ->
        GistFileContentDialog(
            gistFile = gistFile,
            content = gistFileContent,
            isLoading = isGistContentLoading,
            onDismiss = {
                viewingGistFile = null
                viewModel.clearGistFileContent()
            },
        )
    }
}

@Composable
private fun GistFilesSection(
    gistFiles: List<GistFile>,
    isLoading: Boolean,
    error: String?,
    onRefresh: () -> Unit,
    onFileClick: (GistFile) -> Unit,
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Surface1.copy(alpha = 0.92f)),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Gist共有ファイル",
                    style = MaterialTheme.typography.titleMedium,
                    color = Kinpaku,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.height(18.dp).padding(end = 4.dp),
                            strokeWidth = 2.dp,
                            color = Kinpaku,
                        )
                    }
                    IconButton(onClick = onRefresh) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = "Gist更新",
                            tint = Kinpaku,
                        )
                    }
                }
            }

            when {
                error != null -> {
                    Text(
                        text = error,
                        style = MaterialTheme.typography.bodySmall,
                        color = Kurenai,
                    )
                }
                !isLoading && gistFiles.isEmpty() -> {
                    Text(
                        text = "ファイルなし（URLを設定画面で確認してください）",
                        style = MaterialTheme.typography.bodySmall,
                        color = TextMuted,
                    )
                }
                else -> {
                    gistFiles.forEach { gistFile ->
                        GistFileCard(gistFile = gistFile, onClick = { onFileClick(gistFile) })
                    }
                }
            }
        }
    }
}

@Composable
private fun GistFileCard(
    gistFile: GistFile,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(containerColor = Surface1.copy(alpha = 0.7f)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = gistFile.filename,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Zouge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = buildString {
                        if (gistFile.language.isNotBlank()) append(gistFile.language)
                        if (gistFile.language.isNotBlank()) append(" · ")
                        append(formatFileSize(gistFile.size))
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = TextMuted,
                )
            }
        }
    }
}

private fun formatFileSize(bytes: Int): String = when {
    bytes < 1024 -> "${bytes}B"
    bytes < 1024 * 1024 -> "${bytes / 1024}KB"
    else -> "${bytes / (1024 * 1024)}MB"
}

@Composable
private fun GistFileContentDialog(
    gistFile: GistFile,
    content: String?,
    isLoading: Boolean,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Surface1,
        title = {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = gistFile.filename,
                    color = Kinpaku,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (gistFile.language.isNotBlank()) {
                    Text(
                        text = gistFile.language,
                        style = MaterialTheme.typography.labelSmall,
                        color = TextMuted,
                    )
                }
            }
        },
        text = {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(400.dp),
                contentAlignment = Alignment.Center,
            ) {
                when {
                    isLoading -> CircularProgressIndicator(color = Kinpaku)
                    content != null -> {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState()),
                        ) {
                            Text(
                                text = content,
                                color = Zouge,
                                fontFamily = FontFamily.Monospace,
                                fontSize = 12.sp,
                            )
                        }
                    }
                    else -> {
                        Text(text = "内容を読み込み中...", color = TextMuted)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("閉じる", color = Kinpaku)
            }
        },
    )
}

@Composable
private fun MemoCard(
    memo: MemoEntity,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Surface1.copy(alpha = 0.9f)),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = memo.title.ifBlank { "無題メモ" },
                        style = MaterialTheme.typography.titleMedium,
                        color = Kinpaku,
                    )
                    Text(
                        text = "更新: ${formatMemoDisplayTime(memo.updatedAt)}",
                        style = MaterialTheme.typography.labelMedium,
                        color = TextMuted,
                    )
                }
                Row {
                    IconButton(onClick = onEdit) {
                        Icon(
                            imageVector = Icons.Default.Edit,
                            contentDescription = "編集",
                            tint = Kinpaku,
                        )
                    }
                    IconButton(onClick = onDelete) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "削除",
                            tint = Kurenai,
                        )
                    }
                }
            }

            Text(
                text = memo.body.ifBlank { "本文なし" },
                style = MaterialTheme.typography.bodyMedium,
                color = Zouge,
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
            )

            Text(
                text = if (memo.synced) "WSL同期済み" else "未同期",
                style = MaterialTheme.typography.labelMedium,
                color = if (memo.synced) Matsuba else Kinpaku,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MemoEditorDialog(
    title: String,
    initialTitle: String,
    initialBody: String,
    onDismiss: () -> Unit,
    onSave: (String, String) -> Unit,
) {
    var memoTitle by remember(initialTitle) { mutableStateOf(initialTitle) }
    var memoBody by remember(initialBody) { mutableStateOf(initialBody) }
    val canSave = memoTitle.isNotBlank() || memoBody.isNotBlank()

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Surface1,
        title = { Text(text = title, color = Kinpaku) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = memoTitle,
                    onValueChange = { memoTitle = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("タイトル") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = memoBody,
                    onValueChange = { memoBody = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(180.dp),
                    label = { Text("本文") },
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(memoTitle, memoBody) },
                enabled = canSave,
            ) {
                Text("保存", color = Kinpaku)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("閉じる", color = TextMuted)
            }
        },
    )
}
