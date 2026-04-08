# cmd_323 R2-Task1: sync_pane_vars.sh 仕様調査
- **blind_id**: A
- **assigned_to**: hanzo
- **model_under_test**: sonnet (claude-sonnet-4-6)
- **date**: 2026-02-25

---

## §1 全体処理フロー

### 対象ファイル関係図

```
sync_pane_vars.sh (メイン)
├── source scripts/lib/cli_lookup.sh   (CLI種別・プロファイル取得)
└── source scripts/lib/model_detect.sh (実モデル検出)
    └── 依存: cli_lookup.sh (cli_type()使用)
```

設定ファイル参照:
- `config/settings.yaml` → `cli.agents.<name>.type` / `tier` 取得
- `config/cli_profiles.yaml` → `profiles.<cli_type>.<key>` 取得

### sync_pane_vars.sh 処理フロー

```
1. set -e 設定
2. SCRIPT_DIR=$(cd dirname/../..) 解決
3. source cli_lookup.sh  → _CLI_LOOKUP_TYPE/TIER/PROFILE_CACHE 初期化
4. source model_detect.sh → detect_real_model() 関数ロード
5. AGENT_PANES 連想配列定義 (karo=1 ～ tobisaru=9)
6. changed=0 初期化

[将軍ペイン処理]
7. detect_real_model "shogun" "shogun:main"
   └─ 失敗時: shogun_model="Opus" (ハードコード)
8. tmux show-options で現在値取得
9. 差分あり → tmux set-option -p @model_name 更新 + ログ + changed++

[全エージェントループ]
for agent in "${!AGENT_PANES[@]}"; do
10. pane="${AGENT_PANES[$agent]}"  target="shogun:agents.${pane}"
11. cli_profile_get "$agent" "display_name"  → フォールバック値
12.   └─ 空なら cli_type "$agent" でCLI種別をフォールバック値に
13. detect_real_model "$agent" "$target" || real_model=""
14. effective_model="${real_model:-$display_name}"  (優先順位: 実モデル > 定義値)
15. tmux show-options で現在値取得
16. 差分あり → tmux set-option -p @model_name 更新 + source_label(detected/fallback) + changed++
done

[完了報告]
17. changed=0 → "変更なし", else → "{N}ペイン更新完了"
```

### cli_lookup.sh 処理フロー（2段参照）

```
cli_type("hanzo")
  → キャッシュ確認 (_CLI_LOOKUP_TYPE_CACHE["hanzo"])
  → ヒット: 即返却
  → ミス: _cli_lookup_settings_get("hanzo", "type", "claude")
           └─ python3で config/settings.yaml をパース
              └─ cli.agents.hanzo.type → なければ cli.default → なければ "claude"
           → 不正値チェック (claude|codex|copilot|kimi 以外 → "claude")
           → キャッシュ保存 → 返却

cli_profile_get("hanzo", "display_name")
  → キャッシュ確認 (_CLI_LOOKUP_PROFILE_CACHE["hanzo:display_name"])
  → ミス: cli_type("hanzo") → "claude"
           → _cli_lookup_profile_get("claude", "display_name")
              └─ python3で config/cli_profiles.yaml をパース
                 └─ profiles.claude.display_name → "Opus"
           → キャッシュ保存 → "Opus" 返却
```

### model_detect.sh 3段フォールバック構造

```
detect_real_model("hanzo", "shogun:agents.6")
  段1: capture-pane バナー解析
       tmux capture-pane -S -1000
       └─ claude: grep -E '▝▜█████▛▘[[:space:]]+(Opus|Sonnet|Haiku)[[:space:]]+[0-9]+\.[0-9]+[[:space:]]+·'
                  → sed で "▝▜█████▛▘ の後, · の前" を抽出
                  → 成功: @real_model キャッシュ保存 + echo "Sonnet 4.6" + return 0
       └─ codex:  grep -E '│.*model:' → tail -1
                  → sed で "model: の後, /model or │ の前" を抽出
                  → "loading" は失敗扱い
                  → 成功: @real_model キャッシュ保存 + echo モデル名 + return 0
  段2: @real_model キャッシュ参照 (tmux show-options)
       バナーがスクロールオフした場合の安全網
       → キャッシュあり: echo キャッシュ値 + return 0
  段3: return 1 → sync_pane_vars.sh 側で display_name にフォールバック
       effective_model="${real_model:-$display_name}"
```

---

## §2 3段フォールバック構造の詳細解説

| 段 | 方式 | 対象CLI | 成功条件 | キャッシュ更新 |
|----|------|---------|---------|-------------|
| 1 | capture-pane バナー解析 | claude, codex | バナーがスクロール範囲(-1000行)内にある | @real_model に保存 |
| 2 | tmux @real_model キャッシュ | claude, codex | 過去の段1成功があった | なし(参照のみ) |
| 3 | settings.yaml/cli_profiles.yaml定義値 | 全CLI | 常に成功 | なし |

**設計意図**:
- 段1: /model切替後のリアルタイム反映（最高優先）
- 段2: バナーがスクロールオフした後も直前の実測値を維持
- 段3: 起動直後またはキャッシュなし状態での安全網（設定値が正解の前提）

**sync_pane_vars.sh の将軍ペイン vs エージェントループの差異**:
- 将軍: `detect_real_model || shogun_model="Opus"` — 段3フォールバックがハードコード"Opus"
- エージェント: `detect_real_model || real_model=""` → `cli_profile_get`経由でdisplay_name — 段3フォールバックが設定SSOTから取得

---

## §3 エッジケース特定（7件）

### EC-1: 将軍ペインのフォールバック値ハードコード
- **場所**: `sync_pane_vars.sh` L40
- **内容**: `detect_real_model "shogun" ... || shogun_model="Opus"` でフォールバック値が "Opus" にハードコード
- **影響**: 将軍がSonnetやHaikuに切替済みでバナーとキャッシュも消えた場合、"Opus"と誤表示される
- **エージェントループとの非対称性**: 他エージェントは `cli_profile_get` → `config/cli_profiles.yaml` 経由で取得

### EC-2: @real_model キャッシュの陳腐化
- **場所**: `model_detect.sh` 全体
- **内容**: @real_model キャッシュに TTL がない。/model で切替後、バナーがスクロールオフすると古いキャッシュが段2で返る
- **影響**: 切替後のモデル名が更新されずに古い値が長期間表示される可能性
- **条件**: 次回 sync 実行時にバナーが段1で検出されれば自動修正されるため、実害は軽微

### EC-3: `for agent in "${!AGENT_PANES[@]}"` の処理順序不定
- **場所**: `sync_pane_vars.sh` L48
- **内容**: bash 連想配列のキー列挙は挿入順保証なし（bash 4.0+）
- **影響**: ログ出力順が実行ごとに変動し、デバッグ時の可読性が低い
- **機能的影響**: なし（独立したペインを処理するため）

### EC-4: python3 依存のサイレント失敗
- **場所**: `cli_lookup.sh` `_cli_lookup_settings_get()` / `_cli_lookup_profile_get()`
- **内容**: `except Exception: print("${default}")` で全例外をサイレントに握りつぶし
- **影響**: python3 不在、YAML 構文エラー、ファイル不存在時もデフォルト値が返り、根本原因が不明になる
- **条件**: `2>/dev/null` が stderr も抑制しているため診断が困難

### EC-5: `set -e` 環境下での `((changed++))` の挙動
- **場所**: `sync_pane_vars.sh` L45, L72
- **内容**: `((changed++)) || true` の `|| true` は、`changed=0` のときに `((0))` が exit status 1 を返すことへの対策
- **影響**: 現状は問題なし。ただし `changed` が負になるような状況（バグ）では `((changed++))` が 0 以外を返しても `|| true` が隠蔽する

### EC-6: ペイン不存在時の tmux コマンド失敗
- **場所**: `sync_pane_vars.sh` L60, L66, L69 / `model_detect.sh` L36, L50
- **内容**: `tmux capture-pane`, `show-options`, `set-option` は `2>/dev/null || echo ""` で保護されているが...
- **詳細**: `set-option` (L69, L43) には `2>/dev/null` のみで `|| true` なし。`set -e` 環境下でペイン不存在ならスクリプト全体が中断する可能性
- **確認が必要**: L69: `tmux set-option -p -t "$target" @model_name "$effective_model"` — 失敗時の処理なし

### EC-7: Codex "loading" 状態での二重フォールバック
- **場所**: `model_detect.sh` L81
- **内容**: Codex の model が "loading" のとき段1失敗 → 段2(@real_model) にフォールバック
- **影響**: CLI 起動直後の短時間で "loading" → 実モデル名の遷移を sync が挟んだ場合、キャッシュが "loading" に汚染されることはないが、段2での前回値返却により表示が1サイクル遅延する

---

## §4 改善提案（3件）

### 改善案1: 将軍ペインのフォールバックを SSOT 経由に統一
**対象**: `sync_pane_vars.sh` L40

**現状**:
```bash
shogun_model=$(detect_real_model "shogun" "$shogun_target" 2>/dev/null) || shogun_model="Opus"
```

**改善後**:
```bash
shogun_fallback=$(cli_profile_get "shogun" "display_name")
shogun_fallback="${shogun_fallback:-Opus}"
shogun_model=$(detect_real_model "shogun" "$shogun_target" 2>/dev/null) || shogun_model="$shogun_fallback"
```

**効果**: エージェントループと同じフォールバックロジックに統一。将軍のCLI設定を config で変更した際に自動反映される

**注意**: `cli_profiles.yaml` に将軍用エントリが不要。"shogun" の `cli_type` が "claude" に解決されれば `display_name: "Opus"` が返る

---

### 改善案2: @real_model キャッシュに TTL を付加
**対象**: `model_detect.sh` 段2キャッシュ読み出し部

**現状**: キャッシュは永続（tmux セッション終了まで有効）

**改善後**（概念）:
```bash
# キャッシュ保存時にタイムスタンプも記録
tmux set-option -p -t "$pane_target" @real_model "$model" 2>/dev/null
tmux set-option -p -t "$pane_target" @real_model_ts "$(date +%s)" 2>/dev/null

# 読み出し時に TTL チェック (例: 300秒)
local cached_ts
cached_ts=$(tmux show-options -p -t "$pane_target" -v @real_model_ts 2>/dev/null)
if [ -n "$cached" ] && [ -n "$cached_ts" ]; then
    local now elapsed
    now=$(date +%s)
    elapsed=$((now - cached_ts))
    if [ $elapsed -lt 300 ]; then
        echo "$cached"; return 0
    fi
fi
```

**効果**: /model 切替後にバナーがスクロールオフしても最大 300 秒以内に段3フォールバックに降格し、表示のズレを限定できる

**トレードオフ**: tmux 変数が1本増える。TTL 値の調整が必要（短すぎると /clear 直後に段3に落ちる）

---

### 改善案3: ペイン不存在時の `set-option` 失敗を `|| true` で保護
**対象**: `sync_pane_vars.sh` L43, L69 / `model_detect.sh` L50, L82

**現状**:
```bash
tmux set-option -p -t "$target" @model_name "$effective_model"  # 失敗時に set -e でスクリプト中断
```

**改善後**:
```bash
tmux set-option -p -t "$target" @model_name "$effective_model" 2>/dev/null || true
```

**効果**: ペイン不存在（エージェント未配備など）の場合でも残ペインの同期処理を継続。`set -e` 環境での防御的実装

---

## §5 関連教訓との照合

| 教訓 | 関連箇所 | 備考 |
|------|---------|------|
| L034: awk/sedはインデント非依存に | cli_lookup.sh の python3 パース | Python使用でインデント問題は回避済み |
| L020: CLI設定パス環境変数共有 | cli_lookup.sh L22: `${CLI_ADAPTER_SETTINGS:-...}` | 既に CLI_ADAPTER_SETTINGS 対応済み |
| L046: capture-paneバナー解析のfalse positive | model_detect.sh L42: 精密パターン | Opus/Sonnet/Haiku+バージョン番号まで含む精密正規表現で対策済み |
| L049: コードレビューで既存対策見落とし | 上記L020/L046 | いずれも既に対策実装済みであることを確認 |

---

## §6 まとめ

`sync_pane_vars.sh + model_detect.sh + cli_lookup.sh` は 3段フォールバック設計が明確で、全体的に防御的なコードになっている。主要なリスクは EC-6（ペイン不存在時の `set-option` 失敗）と EC-1（将軍ペインのハードコードフォールバック）の2点。改善案1と3は低コストで実施可能な修正。
