# lesson useful_rate 低下原因偵察レポート (2026-07-24)
<!-- cmd_4150_scout | kagemaru | 2026-07-24 -->

## 実測METRIC

```
gate_lesson_health.sh 実行 (2026-07-24 11:46以降)
METRIC: status=WARN useful_rate=42.9% useful=12/total_feedback=28 window_cmds=10
```

前提値 (11:32実測): useful_rate=42.3%(useful=11/total_feedback=26) — 時刻差による微増。両方ともWARN閾値50%未満。

---

## AC1: 直近評価window useful=no評価全件

### 直近10cmd（window）

| # | cmd_id | project | task_type |
|---|--------|---------|-----------|
| 1 | cmd_4105_full | infra | full |
| 2 | cmd_4133_full | dm-signal | full |
| 3 | cmd_4135_full | dm-signal | full |
| 4 | cmd_4139_full | dm-signal | full |
| 5 | cmd_4141_full | dm-signal | full |
| 6 | cmd_4142_full | dm-signal | full |
| 7 | cmd_4144_full | dm-signal | full |
| 8 | cmd_4145_full | dm-signal | full |
| 9 | cmd_4146_full | dm-signal | full |
| 10 | cmd_4147_full | dm-signal | full |

### feedback全件リスト（matureフィルタ通過済み）

**mature判定**: 全期間feedback >= LESSON_EFFECT_USEFUL_MIN(=2)件の教訓のみ計算対象

| lesson_id | 評価元cmd | 評価結果 | 評価理由 |
|-----------|-----------|---------|---------|
| L1291 | cmd_4135_full | NOT_USEFUL | infra教訓(context freshness)がdm-signal UI taskに無関連で注入 |
| L1292 | cmd_4135_full | NOT_USEFUL | infra教訓(Bats fixture)がdm-signal UI taskに無関連で注入 |
| L1291 | cmd_4133_full | NOT_USEFUL | 同上 |
| L1290 | cmd_4133_full | NOT_USEFUL | infra教訓(context参照repo root)がdm-signal UI taskに無関連で注入 |
| L1292 | cmd_4133_full | NOT_USEFUL | 同上L1292 |
| L1292 | cmd_4139_full | NOT_USEFUL | 同上L1292 |
| L1291 | cmd_4139_full | NOT_USEFUL | 同上L1291 |
| L1290 | cmd_4139_full | NOT_USEFUL | 同上L1290 |
| L1291 | cmd_4141_full | NOT_USEFUL | 同上L1291 |
| L1292 | cmd_4141_full | NOT_USEFUL | 同上L1292 |
| L1290 | cmd_4141_full | NOT_USEFUL | 同上L1290 |
| L551  | cmd_4146_full | NOT_USEFUL | ALMディスコン教訓(alm/parity)がdm-signal UI taskに無関連で注入 |
| L584  | cmd_4146_full | NOT_USEFUL | 自動生成draft教訓(how='2026-04-08'のみ)がdm-signal UI taskに無関連で注入 |
| L551  | cmd_4147_full | NOT_USEFUL | 同上L551 |
| L584  | cmd_4147_full | NOT_USEFUL | 同上L584 |
| L547  | cmd_4105_full | NOT_USEFUL | infra教訓(パラメータ空間縮小禁止)がinfra scout taskに無関連で注入 |

**NOT_USEFUL合計: 16件**

### matureフィルタで除外された教訓（計算対象外）

| lesson_id | cmd | 全期間feedback | 除外理由 |
|-----------|-----|----------------|---------|
| L227 | cmd_4144_full | 1件 | mature未満(閾値2) |
| L255 | cmd_4144_full | 1件 | mature未満(閾値2) |
| L910 | cmd_4145_full | 1件 | mature未満(閾値2) |
| L488 | cmd_4105_full | 1件 | mature未満(閾値2) |

除外4件により: raw feedback 32件 → mature通過 28件 = METRIC total_feedback値と一致

### 件数検証

```
USEFUL:
  L625: cmd_4135, cmd_4145 = 2件
  L311: cmd_4133, cmd_4139, cmd_4145, cmd_4146, cmd_4147 = 5件
  L251: cmd_4144, cmd_4145 = 2件
  L703: cmd_4146, cmd_4147 = 2件
  L1042: cmd_4105 = 1件
  計: 12件

NOT_USEFUL: 16件（上表参照）

total_feedback = 12 + 16 = 28件 ← METRIC値と一致
useful_rate = 12/28 = 42.86% ← METRIC値42.9%と一致
```

---

## AC2: 教訓注入の選定経路（選定基準 + コード位置）

### 選定経路: deploy_task.sh `inject_related_lessons` 関数

**ファイル**: `scripts/deploy_task.sh`
**関数開始行**: 6456 (`inject_related_lessons()`)

#### 主要選定フロー（行番号付き）

| ステップ | 判定基準 | 行番号 |
|---------|---------|--------|
| 1. キーワードスコア計算 | `title×3 + (summary+content+when+how)×1` | 7641-7645 |
| 2. NO_WHEN_PENALTY | `when未設定 → score -= NO_WHEN_PENALTY` | 7651-7652 |
| 3. semantic boost | `keyword_score>0の場合のみboost適用` | 7658-7659 |
| 4. target_path boost | `keyword_score>0 + target_path matchで加算` | 7668-7669 |
| 5. MIN_KEYWORD_SCORE フィルタ | `default=2, impl=6, exact=4` | 6485-6489, 7674-7676 |
| 6. project一致ボーナス | `同PJ教訓+2` | 7679-7680 |
| 7. **useful_rate フィルタ** | `useful_rate < 0.40 かつ feedback>=1件 → 除外` | 7744-7756 |
| 8. greedy dedup | `類似度DEDUP_THRESHOLD=0.25で重複除去` | 7764 |
| 9. helpful_count tiebreaker | `同スコアならhelpful_count順` | 7769-7773 |

#### useful_rate フィルタの定数（ファイル: deploy_task.sh 行番号）

| 定数 | 値 | 行番号 |
|------|-----|--------|
| `USEFUL_RATE_THRESHOLD` | 0.40（40%未満で除外） | 6481 |
| `USEFUL_RATE_MIN_SAMPLES` | 1（feedback1件以上で対象） | 6579 |
| `ENABLE_ZERO_USEFUL_AUTO_DEPRECATE` | `'0'`（デフォルトOFF） | 6618 |
| `ZERO_USEFUL_DEPRECATE_MIN_SAMPLES` | 1 | 6617 |

#### useful=no評価が最多の教訓群が選定された判定条件

**L1290/L1291/L1292（infra → dm-signal cmdに注入）**:

- 3教訓はいずれも `tags: [context, gate, testing]` 系のinfra教訓
- dm-signal full cmdのAC・description文には "context" / "gate" / "test" 等の語が頻出
- `keyword_score > 0` → `MIN_KEYWORD_SCORE(=2)` 通過 → 注入対象
- **初回注入時点では全期間feedback=0件** → `useful_rates` 辞書にエントリなし → フィルタ適用外
- 最初のcmd(4133, 4135)でNOT_USEFULを受けた後はuseful_rate=0% → フィルタが機能しwithHeld
- しかし過去のNOT_USEFULは10cmdウィンドウに残り続け、useful_rateを引き下げ続ける

**L551（dm-signal ALMディスコン教訓 → dm-signal cmdに注入）**:
- `tags: [alm, parity]`、cmd_4146/4147のAC/descriptionに alm/parity 語マッチ可能性
- 初回注入時(cmd_4146)はfeedback=0 → フィルタ素通り → NOT_USEFULが2件蓄積
- ALMはディスコン(殿裁定2026-05-10)だが教訓はactive残存

**L584（dm-signal 自動生成draft教訓 → dm-signal cmdに注入）**:
- `how: '2026-04-08'`（日付のみ、内容なし）
- target_files: tasks/lessons.md が dm-signal cmdとのbasename matchに使用された可能性
- 初回注入時feedback=0 → フィルタ素通り

**根本メカニズム**: 初回注入時に feedback=0 の新規教訓はUSEFUL_RATE_MIN_SAMPLES(=1)未満のためフィルタを素通りする「BootstrapギャップNOT_USEFUL量産構造」

---

## AC3: 淘汰候補教訓ID一覧と選定基準是正案

### 淘汰候補教訓一覧

| lesson_id | プロジェクト | タイトル(要約) | 全期間useful_rate | feedback件数 | 淘汰優先度 |
|-----------|------------|--------------|-----------------|------------|----------|
| L1292 (infra) | infra | Bats fixtureは共有lockもtest rootへ隔離する | 0.0% | 0/4 | 高 |
| L1291 (infra) | infra | context freshness cacheはproject overrideをidentityへ含める | 0.0% | 0/4 | 高 |
| L1290 (infra) | infra | context参照は単一repo rootで解決しない | 0.0% | 0/3 | 高 |
| L551 (dm-signal) | dm-signal | ALM batch統合ではobjective単位fallbackでparityを守る | 0.0% | 0/2 | 高（ALMディスコン） |
| L584 (dm-signal) | dm-signal | [自動生成] draft教訓の査読を怠った: cmd_1796 | 0.0% | 0/2 | 中（how=日付のみで低品質） |
| L547 (infra) | infra | パラメータ空間をサイレント縮小するな | 0.0% | 0/2 | 中（内容は有効だが注入精度低） |

---

### 変更対象ファイル

| ファイル | 変更内容 | 対象lesson |
|---------|---------|-----------|
| `projects/infra/lessons.yaml` | L1290/L1291/L1292/L547 を `deprecated: true` に変更 | 4件 |
| `projects/dm-signal/lessons.yaml` | L551/L584 を `deprecated: true` に変更 | 2件 |
| `scripts/deploy_task.sh` | 選定基準是正（下記参照） | inject_related_lessons 関数 |

### 波及先ファイル

| 波及先 | 内容 |
|--------|------|
| `logs/lesson_impact.tsv` | deprecated教訓は以降の injection/feedback が記録されなくなる |
| `scripts/gates/gate_lesson_health.sh` | deprecated教訓はactive_fileから除外 → useful_rate計算対象外 |
| `scripts/deploy_task.sh:7367-7389` | `inject_related_lessons` の `active_file` 生成処理がdeprecated除外 |
| `projects/infra/lessons.yaml` のcontext合流マーカー | 変更なし（deprecationのみで合流マーカー不要） |

### 関連テスト有無

- **現状**: lessonsのdeprecationを直接テストするbats testは存在しない（`tests/unit/`以下 `grep -r deprecated tests/` で0件確認）
- **既存coverage**: `gate_lesson_health.sh` 自体のユニットテストは未確認
- **テスト不要理由**: deprecation=フラグ追記のみ。実害なし。gate_lesson_health.sh再実行で効果即確認可能

### エッジケース

| エッジケース | 影響 | 対処 |
|------------|------|------|
| L547「パラメータ空間縮小禁止」はGLOBAL/普遍的内容 | deprecated後に有用な文脈で注入されなくなる | `helpful_count`/`when`を再精査し、dm-signal以外での実績確認後に判断 |
| L551 (ALM教訓)が非ALM文脈でparity教訓として有用な可能性 | ALMディスコンのため事実上不要 | ALMはdm-signal.yaml/forbidden_topicsにてディスコン確定 → 淘汰は安全 |
| L1290-L1292がinfraのCI修正cmdで必要な可能性 | infra-to-infra注入では有用な場合あり | lesson_impact.tsvのinfra cmd feedbackを確認後に判断（現在全件NOT_USEFULはdm-signal文脈） |

### 依存順序

1. 事前確認: `grep -c "L1290\|L1291\|L1292" logs/lesson_impact.tsv` で全feedback確認
2. deprecated追記: `projects/infra/lessons.yaml` と `projects/dm-signal/lessons.yaml` への `deprecated: true` 追記
3. 効果確認: `bash scripts/gates/gate_lesson_health.sh` を再実行してuseful_rateの変化を確認
4. （任意）選定基準是正: deploy_task.shのbootstrap gap修正（別cmd推奨）

---

### 選定基準是正案

#### 是正1: Bootstrapギャップ解消（最優先）

**問題**: `USEFUL_RATE_MIN_SAMPLES=1` → 初回注入時feedback=0件の教訓はフィルタ素通り
**是正**: 全期間feedback=0件の新規教訓に対して、`MIN_KEYWORD_SCORE` を高く設定（例: `keyword_score < 5` ならwithHold）または注入数上限から除外
**コード位置**: `scripts/deploy_task.sh:7674-7676` (MIN_KEYWORD_SCOREフィルタ)

#### 是正2: cross-project注入の精度向上

**問題**: infra教訓(L1290-L1292)がdm-signal cmdに keyword_score(=+2 project bonus)だけで選ばれる
**是正**: project不一致教訓の `MIN_KEYWORD_SCORE` を高く設定（例: `cross_project_score` 閾値を引き上げ）
**コード位置**: `scripts/deploy_task.sh:7661-7663` (cross_project_score logic)

#### 是正3: ENABLE_ZERO_USEFUL_AUTO_DEPRECATE 有効化

**問題**: `ENABLE_ZERO_USEFUL_AUTO_DEPRECATE='0'`（デフォルトOFF）のため全期間useful_rate=0%の教訓が自動淘汰されない
**是正**: `ENABLE_ZERO_USEFUL_AUTO_DEPRECATE=1` かつ `ZERO_USEFUL_DEPRECATE_MIN_SAMPLES=3`（最低3件以上のNOT_USEFUL確認後に自動deprecate）へ変更
**コード位置**: `scripts/deploy_task.sh:6617-6618`

---

## grep検証コマンド

```bash
# AC1: NOT_USEFUL件数確認
grep -c "NOT_USEFUL" docs/research/lesson_useful_rate_recon_20260724.md

# AC3: 5要件見出し確認
grep -c "^### 変更対象ファイル\|^### 波及先ファイル\|^### 関連テスト有無\|^### エッジケース\|^### 依存順序" docs/research/lesson_useful_rate_recon_20260724.md
```
