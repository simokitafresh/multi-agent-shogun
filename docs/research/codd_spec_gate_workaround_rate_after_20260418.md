# gate_workaround_rate.sh After設計書（R2リファクタリング後）

- **作成**: 2026-04-18 hanzo (cmd_2092)
- **対象**: `scripts/gates/gate_workaround_rate.sh`
- **最終計測**: cold median 20ms (before: 36ms, -44.4%, 1.80x)

---

## 最適化履歴

| cmd | 実施者 | Before | After | 手法 |
|-----|--------|--------|-------|------|
| cmd_1970 | tobisaru | 50ms | 26ms (-44%) | python3+awk3本 → awk1本統合 |
| cmd_2092 | hanzo | 36ms | 20ms (-44%) | BEGIN getline from tac, early-exit, wa_seen_false除去 |

---

## 現在の構造

### 処理フロー

```
bash起動 + 変数設定 (~6ms)
├─ gate_log存在? → has_gate=true
└─ has_gate=false (fallback)

awk -v has_gate -v gate_log -v last_n WA_FILE (~14ms)
  BEGIN {
    if has_gate:
      tac gate_log | getline line → N件でbreak → close(cmd)  [~3ms]
      clear_set構築
  }
  main_pass: karo_workarounds.yaml 1パース
    /^- cmd_id:/  → flush_item(), cur_cmd設定
    /^  workaround:/ → cur_wa設定
    /^  category:/ → cur_cat設定
  END {
    gate_path: item vs clear_set で WA率計算
    fallback: 直近N件でWA率計算
    printf LEVEL|RATE|WA_COUNT|TOTAL|CATS|SOURCE
  }

IFS read + echo (~1ms)
```

### 変更された関数/ロジック（R2で変更）

| 変更箇所 | Before | After | 理由 |
|---------|--------|-------|------|
| gate_log処理 | FNR==NR全量スキャン (21ms) | BEGIN getline from tac, N件でbreak (~3ms) | 末尾から読むことで99%の行を読まずに済む |
| wa_seen_false | あり（デッドコード） | 除去 | wa_count/catsに影響しない未使用配列 |

---

## 最適化パターン（再利用すべき仕組み）

### getline from tac (早期終了ファイル末尾読込)

```awk
# 使う場面: ファイル末尾からN件ユニークエントリを取得したい
# なぜ速いか: tacがOS seekで末尾チャンクのみI/O → early breakでSIGPIPE → 全量I/O回避
BEGIN {
    cmd = "tac \"" gate_log "\""
    while ((cmd | getline line) > 0) {
        n = split(line, f, "\t")
        if (f[3] == "CLEAR" && !seen[f[2]]++) {
            clear_set[f[2]] = 1
            if (++clear_count >= last_n) break  # breakでSIGPIPEへ
        }
    }
    close(cmd)  # SIGPIPE確実送信
}
```

**実測**: 21ms(全量) → 3ms(tac+early exit)。**-86%**

**適用条件**:
- ファイルが時系列順（新しいものが末尾）
- 必要なのが末尾N件のみ
- ファイルが大きく全量読込コストが支配的

---

## 禁止パターン（やってはいけないこと+理由）

| NG | 理由 | 正しい方法 |
|----|------|-----------|
| 複数プロセス(tac+awk1+grep+awk2) | WSL2はプロセス起動コスト ~5ms/process → 3-4プロセスで20ms追加 | 1 awkのBEGIN内でtac getlineを使い1プロセスに収める |
| 変数に大量データを渡して`split()` | split()のオーバーヘッド+文字列変換コスト | getlineでBEGIN内処理し、clear_setを直接構築 |
| `seen[$2]++`全量重複排除 → 末尾N件 | 重複排除で全行処理が必要 | tac + early-break で実質的に末尾N件のみ処理 |

---

## 計測値（劣化検知のベースライン）

- **cold median (gate_log present)**: 20ms（これを超えたらリグレッション）
- **環境**: WSL2 NTFS `/mnt/c`, gate_metrics.log 115K/958行, karo_workarounds.yaml 74K/2349行
- **fallback path (gate_log不在)**: karo_workarounds.yamlのみ = ~16ms

---

## WSL2制約（L508教訓）

WSL2 NTFS上のI/Oはシリアライズが支配的。以下を維持せよ:
- ファイルread回数を最小化（今は karo_workarounds.yaml 1回 + tac(gate_log) 部分的）
- プロセス起動を最小化（1 awk + tac = 2プロセス）
- キャッシュを使う場合は warm run のみ有効と理解すること（L507）
