package com.shogun.android.ui

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shogun.android.ui.theme.*
import com.shogun.android.util.PrefsKeys
import com.shogun.android.util.VoiceDictionary

@Composable
fun VoiceDictionarySection() {
    val context = LocalContext.current
    val prefs = remember {
        context.getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)
    }
    val dictionary = remember { VoiceDictionary(prefs) }
    var entries by remember { mutableStateOf(dictionary.getAll()) }
    var showAddDialog by remember { mutableStateOf(false) }
    var editingKey by remember { mutableStateOf<String?>(null) }
    var expanded by remember { mutableStateOf(false) }

    if (showAddDialog || editingKey != null) {
        VoiceDictionaryDialog(
            initialFrom = editingKey ?: "",
            initialTo = if (editingKey != null) entries[editingKey] ?: "" else "",
            isEdit = editingKey != null,
            onDismiss = {
                showAddDialog = false
                editingKey = null
            },
            onConfirm = { from, to ->
                if (editingKey != null && editingKey != from) {
                    dictionary.remove(editingKey!!)
                }
                dictionary.add(from, to)
                entries = dictionary.getAll()
                showAddDialog = false
                editingKey = null
            }
        )
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                "音声辞書（${entries.size}件）",
                style = MaterialTheme.typography.titleMedium,
                color = Kinpaku,
                fontWeight = FontWeight.Bold
            )
            Text(
                if (expanded) "▲" else "▼",
                color = TextMuted,
                fontSize = 14.sp
            )
        }

        AnimatedVisibility(
            visible = expanded,
            enter = expandVertically(),
            exit = shrinkVertically()
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "音声入力の誤変換を自動修正します",
                    style = MaterialTheme.typography.bodySmall,
                    color = TextMuted
                )

                entries.forEach { (from, to) ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            "$from → $to",
                            color = Zouge,
                            fontSize = 14.sp,
                            modifier = Modifier.weight(1f)
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            TextButton(onClick = { editingKey = from }) {
                                Text("編集", color = Kinpaku, fontSize = 12.sp)
                            }
                            TextButton(onClick = {
                                dictionary.remove(from)
                                entries = dictionary.getAll()
                            }) {
                                Text("削除", color = Color(0xFFCC3333), fontSize = 12.sp)
                            }
                        }
                    }
                }

                if (entries.isEmpty()) {
                    Text(
                        "辞書エントリがありません",
                        style = MaterialTheme.typography.bodySmall,
                        color = TextMuted
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = { showAddDialog = true },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Kinpaku),
                        shape = RoundedCornerShape(4.dp)
                    ) {
                        Text("追加")
                    }
                    OutlinedButton(
                        onClick = {
                            dictionary.resetToPreset()
                            entries = dictionary.getAll()
                        },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = TextMuted),
                        shape = RoundedCornerShape(4.dp)
                    ) {
                        Text("プリセット復元")
                    }
                }
            }
        }
    }
}

@Composable
private fun VoiceDictionaryDialog(
    initialFrom: String,
    initialTo: String,
    isEdit: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (from: String, to: String) -> Unit
) {
    var from by remember { mutableStateOf(initialFrom) }
    var to by remember { mutableStateOf(initialTo) }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Shikkoku,
        title = {
            Text(
                if (isEdit) "辞書エントリ編集" else "辞書エントリ追加",
                color = Kinpaku
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = from,
                    onValueChange = { from = it },
                    label = { Text("変換元") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                OutlinedTextField(
                    value = to,
                    onValueChange = { to = it },
                    label = { Text("変換先") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { if (from.isNotBlank()) onConfirm(from, to) },
                enabled = from.isNotBlank()
            ) {
                Text("保存", color = if (from.isNotBlank()) Kinpaku else TextMuted)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("キャンセル", color = Color(0xFF888888))
            }
        }
    )
}
