# Bash Conventions (ランブック)

## §1 while read変数名の衝突防止

### ルール
`scripts/lib/` 配下のライブラリ関数で `while read` ループの変数名には、必ずプレフィックスを付けること。

```bash
# BAD: 呼出元のlocal変数 line と衝突する
while IFS= read -r line; do
  echo "$line"
done < "$file"

# GOOD: プレフィックス _ac_ で衝突回避
while IFS= read -r _ac_line; do
  echo "$_ac_line"
done < "$file"
```

### 理由
bashの変数スコープは**動的スコープ**。`local` 宣言された変数でも、呼び出された関数内で同名の変数が使われると値が上書きされる。

ライブラリ関数は多数のスクリプトから呼ばれるため、呼出元の変数名と衝突するリスクが特に高い。

### プレフィックス命名規則
関数名やファイル名に基づく短い接頭辞を使う:
- `agent_config.sh` の関数 → `_ac_`
- `pane_lookup.sh` の関数 → `_pl_`
- その他 → ファイル名の頭文字2-3文字を `_XX_` 形式で

### 関連
- 教訓: L263 (cmd_1136)
- 不変量: PI-INFRA-001 (`projects/infra.yaml`)
- 修正済みファイル: `scripts/lib/agent_config.sh`

## §2 計測指標の分母フィルタリング

### ルール
計測指標(inject_rate_pct等)の分母には、意図的にスキップされるタスク種別(recon/scout等)を含めないこと。分母定義を変更した際は、上流の分類ロジック(detect_task_type等)の精度も合わせて確認すること。

### 理由
分母にスキップ対象が含まれると指標が実態より低く算出される。また上流のtask_type分類にunknown等が混在していると、除外フィルタが不完全になり正確な計測ができない。

### 関連
- 教訓: L276 (cmd_1168)
- 不変量: PI-INFRA-002 (`projects/infra.yaml`)

## §3 YAML構造体(list/dict)のJSON中間変換禁止

### ルール
YAML値がリストやdictの場合、`json.dumps()` でJSON文字列に変換してからawkに渡してはならない。`isinstance()` でlist/dictを判定し、Pythonフォールバック(`USE_PYTHON=1`)に直接ルーティングすること。

```bash
# BAD: json.dumpsでJSON文字列化→awkに渡す
value=$(python3 -c "import json,yaml; d=yaml.safe_load(open('$file')); print(json.dumps(d['$key']))")
echo "$value" | awk '{ ... }'  # awkがコロン検出→ダブルクォート包装→文字列化

# GOOD: list/dictはPythonフォールバックに直接回す
if python3 -c "import yaml; d=yaml.safe_load(open('$file')); exit(0 if isinstance(d['$key'],(list,dict)) else 1)"; then
  USE_PYTHON=1  # Pythonフォールバックでそのまま処理
else
  echo "$value" | awk '{ ... }'  # スカラー値のみawkで処理
fi
```

### 理由
`json.dumps()` がYAML構造体をJSON文字列(`[...]` や `{...}`)に変換すると、下流のawk処理がコロン(`:`)を検出してダブルクォート包装を行い、構造体全体が文字列として扱われる。結果としてYAMLの型情報が失われ、不正なデータが生成される。

YAML構造体はPythonが直接扱うのが正しい経路であり、bash/awkを経由させる中間変換は型破壊の原因となる。

### 関連
- 教訓: L287 (cmd_1184)
- 修正済みファイル: `scripts/report_field_set.sh`
