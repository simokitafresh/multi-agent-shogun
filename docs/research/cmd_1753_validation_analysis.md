# cmd_1753 偵察C: Admin保存バリデーション分析

調査者: kotaro
対象: backend/app/api/portfolios.py L63-152 + backend/app/schemas/models.py
注記: 参考ファイル `docs/research/cmd_1751_admin_validation.md` は存在しなかった（L558: ファイル不在を報告して作業継続）

---

## AC1: normalize_lookback_weights() のALM時挙動とdiff概案

### コード確認 (portfolios.py L63-96)

```python
def normalize_lookback_weights(periods: List[LookbackPeriod]) -> List[LookbackPeriod]:
    if not periods:  # L72
        return [LookbackPeriod(months=0, days=252, weight=1.0, use_calendar=False)]
```

`lookback_periods=[]`（空配列）の場合: `[LookbackPeriod(months=0, days=252)]`を返す（デフォルト252日強制）。

### normalize呼出し条件 (portfolios.py L146-150)

```python
if portfolio.type != "fof":
    portfolio.lookback_periods = normalize_lookback_weights(portfolio.lookback_periods)
else:
    portfolio.lookback_periods = []
```

- ALMがtype="standard"なら`normalize_lookback_weights()`が呼ばれる
- ALMのlookback_periodsが空でも252日デフォルトが強制挿入される

### buffer計算対応要否

ALMエンジンが`lookback_periods`を参照するか`pipeline_config.alm_config`のみ参照するかによる。
ALMエンジン内部はこのタスクスコープ外（未確認）。対応要否はALMエンジン確認後に決定すべき。

### diff概案（ALMエンジン確認後に適用判断せよ）

```python
# portfolios.py L146-150（変更案）
if portfolio.type != "fof":
    alm_config = (portfolio.pipeline_config or {}).get("alm_config")
    if not alm_config:
        # 通常standardのみnormalize
        portfolio.lookback_periods = normalize_lookback_weights(portfolio.lookback_periods)
    # ALMの場合: lookback_periodsはそのまま維持（pipeline_config.alm_configを優先）
else:
    portfolio.lookback_periods = []
```

**前提条件**: ALMエンジンが`lookback_periods`を無視し`pipeline_config.alm_config`のみ参照することの確認が必要。
前提未確認のままdiffを適用すると、ALMのlookback設定が欠落する可能性がある。

---

## AC2: _validate_portfolio() のMTD混入判定+ALM安全性

### _validate_portfolio()の全処理 (portfolios.py L99-152)

1. ID生成（L112-113）
2. relative_assets重複除去（L116）
3. rebalance_trigger検証（L119-134）: signal_change禁止、ALLOWED_REBALANCE_TRIGGERS外を拒否
4. FoFはmonthly固定（L132-134）
5. relative_assets必須チェック（L138-142）: type!="fof"時に適用
6. lookback_periods正規化（L146-150）

**→ alm_configを拒否/検証するロジックは存在しない。**

### MTD混入判定

MTD（Month-To-Date）関連の処理は`_validate_portfolio()`内に**存在しない**。

### ALM安全性

- `_validate_portfolio()`はALMポートフォリオを特別扱いしない
- ALMポートフォリオ（type="standard"）にもrelative_assetsチェックが適用（L138）
  → ALMがrelative_assetsなしで動作する場合、保存時ValidationErrorが発生する可能性
- `pipeline_config.alm_config`の内容は全く検証されない

---

## AC3: BE保存バリデーション問題有無

### Pydanticスキーマ確認 (schemas/models.py L136-139)

```python
pipeline_config: Optional[Dict[str, Any]] = Field(
    default=None,
    description="パイプライン設定（Modular Engine用）"
)
```

- `Optional[Dict[str, Any]]`で型が緩い（任意のキーと値を受け入れる）
- `alm_config`キーを含む任意の辞書を通過させる
- **alm_configのPydanticバリデーションはなし**

### validate_portfolio_type model_validator (schemas/models.py L145-166)

```python
@model_validator(mode='after')
def validate_portfolio_type(self) -> 'Portfolio':
    if self.type == PortfolioType.FOF:
        ...  # FoFのみ検証（component_portfolios>=2, pipeline_config必須, terminal_block必須）
    return self
```

- **type="fof"以外（ALM含むstandard）には適用されない**
- ALMポートフォリオのpipeline_configに対してモデルバリデーションは動作しない

### BE保存バリデーション問題

**問題あり**: `pipeline_config`が`Dict[str, Any]`のため、alm_configの必須フィールド欠落・型不一致等が検出されずDBに保存される経路が存在する。

---

## AC4: FE保存ロジック混入リスク有無

### SavePortfoliosRequest確認 (schemas/models.py L257-270)

```python
class SavePortfoliosRequest(BaseModel):
    portfolios: List[Portfolio] = Field(default_factory=list)
    changes: Optional[List[PortfolioChange]] = Field(default=None, ...)
```

- FEからの入力は`Portfolio`モデルでバリデーションされる
- ただし`pipeline_config`は`Dict[str, Any]`で型が緩い

### FE保存ロジック混入リスク（BEスキーマ観点）

- **リスクあり**: FEが意図しない構造のalm_configを送信してもBEで拒否されない
- FEからの任意のalm_config構造が直接DBに保存される
- FEコードの詳細確認は本タスクのスコープ外（対象ファイルはBEのみ）

---

## サマリー

| AC | 判断 | 根拠 |
|---|---|---|
| AC1: buffer計算対応要否 | **要確認** | ALMエンジンのlookback_periods参照有無が未確認。diff概案は提示済み |
| AC1: 空配列挙動 | 252日デフォルト強制挿入 | portfolios.py L72-73 |
| AC2: alm_config拒否箇所 | **なし** | _validate_portfolio()にalm_config処理ゼロ |
| AC2: MTD混入 | **なし** | MTD関連ロジックは存在しない |
| AC2: ALM安全性 | **未検証** | alm_configは全く検証されない |
| AC3: Pydanticブロック | **なし** | `Dict[str, Any]`で通過 |
| AC4: FE混入リスク | **あり** | Dict緩さによりFEからの不正alm_configが通過 |

---

## 確認ファイル

| ファイル | 確認行 |
|---|---|
| `backend/app/api/portfolios.py` | L63-152（normalize_lookback_weights + _validate_portfolio全体） |
| `backend/app/schemas/models.py` | Portfolio, LookbackPeriod, SavePortfoliosRequest, validate_portfolio_type |
