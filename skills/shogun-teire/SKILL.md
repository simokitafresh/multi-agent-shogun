---
name: shogun-teire
argument-hint: ""
quality_metric: "将軍系: 棚卸しcmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  知識基盤の定期棚卸し（8観点監査）。Memory MCP・CLAUDE.md・
  instructions・context・projects・lessons の7層を横断的に監査し、
  衛生状態・整合性・鮮度を検査する。
  TRIGGER: /shogun-teire、棚卸し、知識の状態は、7層監査、大型cmd完了後の知識チェック
  DO NOT TRIGGER: MEMORY.md+MCPだけの棚卸し（→/dream）、
  教訓の振り分け（→lesson-sort）、PD→context反映確認（→shogun-pd-sync）、
  /clear前準備（→shogun-clear-prep）、パラメータ過適合判定（→shogun-param-neighbor-check）
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - mcp__memory__read_graph
  - mcp__memory__add_observations
  - mcp__memory__delete_observations
  - mcp__memory__delete_entities
  - mcp__memory__create_entities
  - Edit
---

# /shogun-teire — 知識基盤の定期棚卸し（8観点監査）

7層知識基盤を横断的に監査し、衛生状態・整合性・鮮度を検査する。殿の承認なしに変更を実行してはならない。

---

## When to Use

- 殿から「知識の状態は？」「棚卸しせよ」と指示された時
- 大型cmd完了後（知識の大量追加・変更があった場合）
- 月1回の定期監査

---

## 知識7層定義

CLAUDE.md Knowledge Mapと一致する7層構造。L3はVercelスタイルの2層構造（索引層+詳細層）を1層として扱う:

| 層 | パス | 書き込み権限 | 消費者 | 役割 |
|----|------|------------|--------|------|
| L1 | CLAUDE.md | 家老のみ | 全員(自動ロード) | 圧縮索引・恒久ルール |
| L2 | instructions/*.md | 家老のみ | 全員 | 役割別恒久ルール |
| L3 | context/*.md → docs/research/*.md | 家老のみ | 全員 | 索引層+詳細層(下記参照) |
| L4 | projects/{id}.yaml | 家老のみ | 忍者・家老 | PJ核心知識(ルール/UUID/DB) |
| L5 | projects/{id}/lessons.yaml | 家老のみ(lesson_write.sh) | 忍者・家老 | PJ教訓(過去の失敗・発見) |
| L6 | queue/ + dashboard + reports | 各担当 | 家老・忍者・将軍 | タスク指示・状態・報告 |
| L7 | MCP Memory | 将軍のみ | 将軍のみ | 殿の好み・将軍教訓 |

**L3の2層構造**:
- `context/*.md` = **索引層**（結論1-2行+参照先パスのみ。散文禁止）
- `docs/research/*.md` = **詳細層**（データテーブル・経緯・調査過程の恒久保存先）
- 普段はcontext結論だけで判断。深掘り時のみdocs/research/を読む（Design for Retrieval）

---

## 8観点 監査手順

### 観点① Memory MCP衛生

**目的**: Memory MCPに「殿の好み」「将軍の教訓」「殿の裁定」以外が混入していないか

**手順**:

1. `mcp__memory__read_graph` で全エンティティ取得
2. 全エンティティを確認（2026-03-23時点で8エンティティ）:
   - **shogun_core**: 殿の好み+運用ルール → ✅正当
   - **dm_signal_decisions**: 殿の裁定(PJ固有) → ✅正当
   - **deterioration_probability_design**: 殿の設計書 → ✅正当
   - **pending_decisions**: 保留事項 → ✅正当（但し陳腐化チェック要）
   - **shogun_lessons**: 将軍の教訓 → ✅正当
   - **passive_context_philosophy**: Vercel知見 → ✅正当（設計哲学）
   - **ACE_Principle**: ACE設計思想 → ✅正当（設計哲学）
   - **コリ先生**: karma-oss参照 → ✅正当（将来参照用）
3. 各observationを分類:
   - ✅ 殿の好み / ✅ 殿の裁定 / ✅ 将軍の教訓
   - ❌ 事実・ポインタ → projects/*.yaml or context/*.md
   - ❌ PJ詳細 → projects/*.yaml
   - ❌ インフラ事実 → context/infrastructure.md
   - ❌ 時限データ → 削除 or queue/
4. 重複チェック: 同じ情報がL1-L6にもあるか

**出力**: エンティティ × observation × 判定(✅/❌/⚠️) + 移動先提案

---

### 観点② 層間整合性

**目的**: 7層間で情報が正しく階層化されているか

**手順**:

1. CLAUDE.md Knowledge Mapの各エントリと実ファイルの対応確認
2. 上方漏出: context/*.mdの詳細がCLAUDE.mdに重複していないか
3. 下方重複: CLAUDE.mdの要約がcontext/*.mdにコピペされていないか
4. projects/{id}.yamlとcontext/{id}.mdの役割分担:
   - yaml = 核心知識(ルール/UUID/DBルール)
   - md = 詳細(手順/根拠/構造)
5. instructions/*.mdとCLAUDE.mdの分担:
   - instructions = 役割別恒久ルール
   - CLAUDE.md = 全員共通

**出力**: 層間の不整合一覧 + 修正提案

---

### 観点③ 鮮度検査

**目的**: 知識文書が最新のcmd成果を反映しているか

**手順**:

1. `git log --oneline -20` で直近cmds特定
2. 各知識文書の最終更新日(`git log -1 {file}`)
3. 直近cmdの成果(新知見/決定/変更)が反映済みか照合
4. 陳腐化判定: 重要変更が未反映の文書にフラグ
5. pending_decisions / deferred_* の棚卸し: 解決済みなのに残っている項目はないか
6. pending_decisions.yamlの行数チェック: 500行超 → ⚠️ resolved未アーカイブの疑い
7. cmd-chronicle.mdの空欄チェック: title/key_resultが空のcmd行 → ⚠️ 自動補完漏れ

**出力**: 各文書 × 最終更新 × 未反映cmd一覧

---

### 観点④ 教訓サイクル健全性

**目的**: 教訓の注入→確認→参照→蓄積サイクルが回っているか

**手順** — ゲートスクリプト出力を入力として使用:

1. **合流状態チェック** — `bash scripts/gates/gate_lesson_health.sh`（引数なし=全project走査）
   - OK: lesson→context合流は健全（未合流N件）
   - ALERT: 未合流5件超 → context未反映の教訓が蓄積（context反映 + last_synced_lesson更新）
   - 未振り分け教訓数もチェック（UNSORTED_THRESHOLD=10超でALERT）
   - SSOT lessons.md の conflict marker / ssot_path 不備、when/how欠落、注入10回以上かつ helpful_count=0 の教訓を併せて確認
   - lesson effectiveness / useful率を確認（WARN=50%未満、ALERT=30%未満）
2. **YAML整合性チェック** — `bash scripts/gates/gate_yaml_status.sh <cmd_id> --dry-run`（直近完了cmdを対象）
   - ALREADY_OK: status=completed（正常）
   - DRY-RUN出力でstatus未更新cmdを検出
3. **PD→context反映チェック** — resolved PDごとに `bash scripts/gates/gate_pd_sync.sh <pd_id>`
   - SYNCED: context反映済み
   - NOT_SYNCED: 裁定済みだがcontext未反映 → /shogun-pd-syncで修正推奨
4. **ゲート通過率** — `bash scripts/count_gate_metrics.sh`
   - CLEAR/BLOCK比率でデプロイゲートの健全性を確認
   - BLOCK率が高い場合はBLOCK理由内訳からボトルネック特定
5. **TSVデータ存在確認** — `logs/lesson_tracking.tsv`の状態チェック
   ```bash
   # lesson_tracking.tsvの存在とデータ行数を確認
   TSV="logs/lesson_tracking.tsv"
   if [ -f "$TSV" ]; then
     DATA_LINES=$(grep -cv '^\s*#\|^\s*$\|^timestamp' "$TSV" 2>/dev/null || echo 0)
     echo "lesson_tracking.tsv: ${DATA_LINES}件のデータ行"
     # 直近5件の記録を表示
     tail -5 "$TSV"
   else
     echo "WARNING: lesson_tracking.tsv が存在しない（cmd_complete_gate.shの自動記録が未稼働の可能性）"
   fi
   ```
   - 0件: cmd_complete_gate.shのTSV追記機能が未稼働 or ゲート未通過 → ⚠️
   - 1件以上: 正常稼働中 → ✅
6. **タグ付与率チェック** — tags未設定の教訓を検出
   ```bash
   # 全プロジェクトのlessons.yamlからtags未設定を検出
   for f in projects/*/lessons.yaml; do
     project=$(basename $(dirname "$f"))
     echo "=== $project ==="
     python3 -c "
import yaml, sys
with open('$f') as fh:
    data = yaml.safe_load(fh)
if not data or 'lessons' not in data: sys.exit(0)
total = len(data['lessons'])
no_tags = [l for l in data['lessons'] if not l.get('tags')]
print(f'  total: {total}, tags未設定: {len(no_tags)}')
for l in no_tags:
    print(f\"    {l.get('id','?')} - {l.get('title','?')[:50]}\")
" 2>/dev/null || true
   done
   ```
   - タグ未設定率が高い場合、教訓注入の精度が低い可能性（全教訓一括注入）→ ⚠️

7. **PI原理率チェック** — 個別事実PIと原理PIの比率を確認
   ```bash
   # projects/dm-signal.yaml の PI entries を抽出し、原理レベルか確認
   python3 -c "
import yaml, sys
with open('projects/dm-signal.yaml') as f:
    data = yaml.safe_load(f)
pi = data.get('production_invariants',{}).get('entries',[])
total = len(pi)
# 原理PIの判定: implicationに '全て' '原���' '任意' '信頼境界' が含まれるか
principle_keywords = ['全て', '原理', '適用される', '信頼境界', '任意の']
principles = [p for p in pi if any(k in p.get('implication','') for k in principle_keywords)]
print(f'PI総数: {total}, 原理レベル: {len(principles)} ({100*len(principles)//total}%)')
print(f'個別事実: {total-len(principles)} ({100*(total-len(principles))//total}%)')
if len(principles) < total * 0.3:
    print('⚠️ 原理率30%未満。共通の根を持つPI群がないか確認推奨')
else:
    print('✅ 原理率30%以上')
for p in principles:
    print(f\"  原理: {p['id']} — {p.get('fact','')[:60]}\")
" 2>/dev/null || true
   ```
   - 原理率30%未満 → ⚠️ 新PIが個別事実に偏っている（「個別の例か原理か？」の問いを習慣化推奨）
   - 原理率30%以上 → ✅ 学習ループが原理抽出を含んでいる

**出力**: ゲート出力サマリ（合流状態 + YAML整合性 + PD反映 + ゲート通過率 + TSVデータ有無 + タグ付与率 + PI原理率）

---

### 観点⑤ 欠落検出

**目的**: 記録すべき情報が未記録でないか

**手順**:

1. Memory MCPのdm_signal_decisionsと殿の直近裁定を照合
2. dashboard.md 🚨要対応の棚卸し(放置されていないか)
3. CLAUDE.md Forbidden actionsの棚卸し(追加すべきルールはないか)
4. Destructive Operation Safetyの棚卸し(新パターンはないか)
5. 新プロジェクトがconfig/projects.yamlに追加されているか

**出力**: 未記録決定一覧 + 陳腐化した保留事項一覧

---

### 観点⑥ 重複・矛盾検出

**目的**: 同じ情報が複数箇所に異なる表現で存在していないか

**手順**:

1. Memory MCPの各observationのキーワードで7層を横断grep
2. 3箇所以上に同じ情報 → 重複フラグ
3. 同じ主題で異なる結論 → 矛盾フラグ
4. 「削るな圧縮せよ」原則に基づき統合提案

**出力**: 重複マップ + 矛盾一覧 + 統合提案

---

### 観点⑦ Vercel整合性

**目的**: Vercelスタイル（索引層+詳細層）の2層構造が正しく維持されているか

**手順** — 4検査項目:

**(a) 索引⇔詳細リンク検証**: context/*.mdの参照先が実在するか

1. context/*.md内のリンク参照を抽出:
   ```bash
   grep -rn 'docs/research/' context/*.md
   grep -rn '→.*\.md' context/*.md
   ```
2. 抽出した各パスが実在するか確認:
   ```bash
   # 例: docs/research/cmd_270_slope-analysis.md が存在するか
   ls -la <抽出パス>
   ```
3. リンク切れ（参照先不在）→ ❌ 報告

**(b) Brevity Bias検出**: 結論のみで参照先リンクがないエントリの検出

1. context/*.mdの各セクションを走査し、結論行はあるがリンク参照（`→`/`docs/`/バッククォート囲みパス）がない箇所を検出:
   ```bash
   # 各contextファイルのセクション(##)ごとに、docs/research参照の有無を確認
   awk '/^##/{sec=$0; has_link=0} /docs\/research|→.*\.md/{has_link=1} /^##/{if(prev_sec && !prev_link) print FILENAME": "prev_sec; prev_sec=sec; prev_link=has_link; has_link=0}' context/*.md
   ```
2. 参照先なしで詳細情報を含むエントリ → ⚠️ Brevity Bias（「リンク先なき圧縮 = 禁止」違反の候補）

**(c) Context Collapse検出**: git logで全体書き換え（大量行変更）の痕跡を検出

1. context/*.mdの直近変更を確認:
   ```bash
   git log --oneline --stat -10 -- context/*.md
   ```
2. 1コミットで大量行(+50/-50以上)の変更があるファイル → ⚠️ Context Collapse候補
3. 追加のみ(+N/-0)なら正常（Delta Updates準拠）

**(d) Delta Updates検証**: 直近の更新が追記型かどうか

1. 直近5コミットのcontext変更をdiffで確認:
   ```bash
   git log --oneline -5 -- context/*.md | while read hash msg; do
     echo "=== $hash $msg ==="
     git diff "${hash}^..${hash}" --stat -- context/*.md
   done
   ```
2. 追加行 >> 削除行 → ✅ Delta Updates準拠
3. 削除行 >= 追加行 → ⚠️ 全体書き換えの可能性（Context Collapse確認要）
4. 大量削除を伴う変更は、リンク先(docs/research/)への移動が先行しているか確認

**出力**: Vercel整合性レポート（リンク切れ + Brevity Bias + Context Collapse + Delta Updates）

---

### 観点⑧ 教訓効果監査

**目的**: 教訓の注入→参照サイクルの実効性を定量検証し、効果のない教訓の淘汰判断を殿に提示する

**前提スクリプト**:
- `scripts/knowledge_metrics.sh` — TSVから淘汰候補+Δ算出（cmd_348で実装）
- `scripts/lesson_deprecate.sh` — 教訓の非活性化（deprecated: true付与）
- `logs/lesson_tracking.tsv` — 注入・参照ログ（deploy_task.sh + cmd_complete_gate.shが自動記録）

**手順**:

1. **メトリクス取得** — `bash scripts/knowledge_metrics.sh`
   - 淘汰候補（注入≥5回 かつ 参照0回）のリスト
   - Δ（教訓あり/なしのCLEAR率差分）
   - サンプル不足警告（N<10の場合）
   ```bash
   # テキスト出力（殿への提示用）
   bash scripts/knowledge_metrics.sh
   # JSON出力（プログラム連携用）
   bash scripts/knowledge_metrics.sh --json
   # 閾値変更（デフォルト5）
   bash scripts/knowledge_metrics.sh --threshold 3
   # 期間指定（特定日以降のデータのみ）
   bash scripts/knowledge_metrics.sh --since 2026-02-20
   ```

2. **既存deprecated教訓一覧** — 過去の監査で非活性化済みの教訓を確認
   ```bash
   # 全プロジェクトのdeprecated教訓を一覧表示
   for f in projects/*/lessons.yaml; do
     project=$(basename $(dirname "$f"))
     echo "=== $project ==="
     python3 -c "
import yaml, sys
with open('$f') as fh:
    data = yaml.safe_load(fh)
if not data or 'lessons' not in data: sys.exit(0)
deprecated = [l for l in data['lessons']
              if l.get('deprecated') or l.get('status') == 'deprecated']
if not deprecated:
    print('  (deprecated教訓なし)')
else:
    for l in deprecated:
        reason = l.get('deprecated_reason', l.get('deprecated_by', 'N/A'))
        at = l.get('deprecated_at', 'N/A')
        print(f\"  {l.get('id','?')} - {l.get('title','?')[:50]}\")
        print(f\"    reason: {reason}  deprecated_at: {at}\")
" 2>/dev/null || true
   done
   ```
   - 淘汰候補(Step 3)と既存deprecated IDが重複していないか確認
   - deprecated理由が妥当か（再評価が必要な場合は殿に提示）

3. **淘汰候補を殿に提示** — メトリクス出力の「淘汰候補」セクションをそのまま提示
   - 各候補: lesson_id, project, 注入回数, 参照回数, 注入先忍者
   - 「注入N回されたが一度も参照されていない」= 効果がない可能性

4. **Δを殿に提示** — CLEAR率の差分で教訓全体の効果を評価
   - 教訓あり CLEAR率 vs 教訓なし CLEAR率
   - Δ > 0 = 教訓注入に正の効果あり
   - Δ ≤ 0 = 教訓の質 or 配り方に問題の可能性
   - サンプル不足警告がある場合はその旨を明記

5. **殿の判断を仰ぐ** — 各淘汰候補について3択
   - **deprecate**: 非活性化（注入対象から除外。教訓本体は保持）
   - **keep**: 現状維持（もう少し様子を見る）
   - **retag**: タグを変更して配り先を改善（参照されないのはミスマッチが原因の可能性）

6. **殿の決定を実行**
   - deprecate → `bash scripts/lesson_deprecate.sh <project> <lesson_id> "<reason>"`
     ```bash
     # 例: 注入12回・参照0回の教訓を非活性化
     bash scripts/lesson_deprecate.sh dm-signal L044 "注入12回・参照0回。殿裁定により淘汰"
     ```
   - retag → lesson_write.shでtags更新（手動編集 or 再登録）
   - keep → 記録のみ（次回監査で再評価）

7. **タグ付与率チェック** — tags未設定の教訓を検出
   ```bash
   # 全プロジェクトのlessons.yamlからtags未設定を検出
   for f in projects/*/lessons.yaml; do
     project=$(basename $(dirname "$f"))
     echo "=== $project ==="
     grep -B1 'tags:.*\[\]' "$f" 2>/dev/null || echo "(tags空リストなし)"
     # tagsフィールド自体がない教訓も検出
     python3 -c "
import yaml, sys
with open('$f') as fh:
    data = yaml.safe_load(fh)
if not data or 'lessons' not in data: sys.exit(0)
for lesson in data['lessons']:
    if not lesson.get('tags'):
        print(f\"  tags未設定: {lesson.get('id','?')} - {lesson.get('title','?')[:40]}\")
" 2>/dev/null || true
   done
   ```

**出力**: 教訓効果レポート（deprecated一覧 + 淘汰候補 + Δ + タグ付与率 + 殿の判断結果）

---

## 出力フォーマット

```
# /shogun-teire 監査結果 — {date}

## サマリ
| 観点 | 検出数 | 重大(❌) | 注意(⚠️) | 正常(✅) |

## 観点① Memory MCP衛生
### エンティティ: {name} ({type}) — {N} observations
| # | 内容(要約) | 判定 | 理由 | 移動先 |

## 観点② 層間整合性
{不整合一覧}

## 観点③ 鮮度検査
| 文書 | 最終更新 | 未反映cmd | 陳腐化判定 |

## 観点④ 教訓サイクル健全性
| チェック | スクリプト | 結果 | 判定 |
| 合流状態 | gate_lesson_health.sh | 未合流{N}件 / total:{N} | OK/ALERT |
| 未振り分け | gate_lesson_health.sh | 未振り分け{N}件 | OK/ALERT |
| SSOT整合 | gate_lesson_health.sh | conflict marker / ssot_path | OK/WARN/ALERT |
| when/how充足 | gate_lesson_health.sh | when:{N}/{M} how:{N}/{M} | OK/WARN |
| 教訓効果率 | gate_lesson_health.sh | referenced/injected, useful/feedback | OK/WARN/ALERT |
| 注入過多 | gate_lesson_health.sh | injection>=10 and helpful=0 | OK/WARN |
| YAML整合性 | gate_yaml_status.sh --dry-run | {status} | OK/要更新 |
| PD反映 | gate_pd_sync.sh | {SYNCED/NOT_SYNCED} | OK/WARNING |
| ゲート通過率 | count_gate_metrics.sh | CLEAR:{N} BLOCK:{N} ({%}) | 健全/要改善 |
| TSVデータ | logs/lesson_tracking.tsv | データ{N}行 | ✅(1+行)/⚠️(0行) |
| タグ付与率 | lessons.yaml走査 | tags未設定{N}件 / 全{M}件 | ✅(0件)/⚠️(1+件) |

## 観点⑤ 欠落検出
| 未記録の決定/ルール | 根拠 | 記録先候補 |

## 観点⑥ 重複・矛盾検出
| 情報 | 存在箇所 | 種別(重複/矛盾) | 統合提案 |

## 観点⑦ Vercel整合性
| 検査 | 対象 | 結果 | 判定 |
| (a) リンク検証 | context/*.md → docs/research/ | 切れ{N}件 / 正常{N}件 | ✅/❌ |
| (b) Brevity Bias | context/*.md各セクション | 参照なし{N}件 | ✅/⚠️ |
| (c) Context Collapse | git log context/*.md | 大量変更{N}件 | ✅/⚠️ |
| (d) Delta Updates | 直近5commit | 追記型{N}/{total} | ✅/⚠️ |

## 観点⑧ 教訓効果監査
| 検査 | スクリプト | 結果 | 判定 |
| deprecated一覧 | lessons.yaml走査 | deprecated済{N}件 | (現況記録) |
| 淘汰候補 | knowledge_metrics.sh | 注入≥5・参照0の教訓{N}件 | ✅(0件)/⚠️(1+件) |
| Δ(CLEAR率差分) | knowledge_metrics.sh | 教訓あり{X}% vs なし{Y}% Δ={Z}pp | ✅(Δ>0)/⚠️(Δ≤0) |
| タグ付与率 | lessons.yaml走査 | tags未設定{N}件 / 全{M}件 | ✅(0件)/⚠️(1+件) |
| 殿の判断 | — | deprecate:{N} / keep:{N} / retag:{N} | (記録) |

## 変更提案一覧
| # | 何を | どこから | どこへ | 原則 |

## 統計
| 指標 | 変更前 | 変更後予測 | 改善率 |
```

---

## ガイドライン

1. **削るな圧縮せよ** — 情報を消すな。適切な層に移動・圧縮
2. **受動的 > 能動的** — CLAUDE.md(自動ロード) > Memory MCP(判断2回)
3. **100年後の人が読めるか** — 暗黙知排除、略語禁止
4. **MCP操作は将軍のみ** — 起動時read_graphはしない(コスト削減)。棚卸し時のみread_graph。ファイル操作は家老に委任
5. **変更提案は殿の承認後** — 監査結果を報告し、承認を得てから実行。allowed-toolsにEdit・MCP write系を含むのは承認後の同セッション内実行のため（two-phase single-invocation設計）
6. **旧ドライラン(054_teire_dryrun.md)は参考のみ** — 構造を踏襲するな
7. **ACE原則に従え** — 下記参照

### ACE + Vercelスタイル（知識管理の上位思想）

**ACE（Agentic Context Engineering）= Why**（なぜ知識を包括的に保つか）:
- コンテキストは簡潔な要約ではなく「進化するPlaybook」として扱え
- **Brevity Bias**（簡潔化→性能低下）を防げ — 安易な圧縮は知識損失
- **Context Collapse**（反復書き換え→情報損失）を防げ — Delta Updates（追記のみ・全体書き換え禁止）が核心
- **リンク先なき圧縮 = 削除 = 禁止**（殿直伝）。先にリンク先を作り、確認してから圧縮

**Vercelスタイル = How**（どう構造化するか）:
- 索引層(context/*.md) + 詳細層(docs/research/*.md)の2層分離
- Design for Retrieval: 普段は結論だけで判断、深掘り時のみリンク先を読む

**3役割分離**（監査観点として活用）:
- **Generator** = 忍者（知識を生成 — 報告YAML・lesson_candidate）
- **Reflector** = 家老（品質を検査・査読 — lesson confirm/reject・context整合チェック）
- **Curator** = lesson_write.sh等のスクリプト（自動整理・登録・context索引追記）
- 監査時: 各役割が機能しているか（生成→査読→整理のサイクルが回っているか）を検査
