# deterioration_snapshots 偽陽性率分析
cmd: cmd_3429 | 実行日: 2026-06-17 | ninja: saizo

## 目的
deterioration_snapshotsのHIGH以上判定と翌月monthly_returnsを突合し、
HIGH判定後に実際に悪化（月次リターン負）した割合を計算。
cmd_3428の相関乖離偽陽性率(70%)との比較。

---

## ラベル体系（実際のDB値）

タスクYAMLでは `HIGH/VERY_HIGH` と記載されているが、実際のDBラベルは異なる。

| ラベル | 定義（classify_label） | HIGH/VERY_HIGH対応 |
|--------|----------------------|-------------------|
| DETERIORATING | p12>=0.80 AND p24>=0.80 | HIGH相当（最高警戒） |
| WATCH | p12>=0.70 AND p24<0.80 | 中程度 |
| EARLY_WARNING | p6>=0.85 AND p12<0.70 AND p24<0.70 | 初期警告 |
| MIXED | 上記以外 | — |
| GOOD | p12<0.70 AND p24<0.70 | 正常 |

ソース: `backend/app/services/deterioration.py` L268-296

---

## AC1: ラベル別 翌月monthly_return突合

**定義**: 偽陽性(FP) = 悪化判定したが翌月リターンが正（実際には悪化しなかった）

| ラベル | 判定件数 | 欠損(翌月なし) | 有効件数 | 翌月負(悪化) | 翌月正(FP) | FP率 | 平均翌月リターン |
|--------|---------|--------------|---------|------------|----------|------|----------------|
| DETERIORATING | 37 | 13 | 24 | 9 | 15 | **62.5%** | +8.04% |
| WATCH | 7 | 3 | 4 | 3 | 1 | **25.0%** | +10.88% |
| EARLY_WARNING | 5 | 1 | 4 | 3 | 1 | **25.0%** | +3.00% |
| MIXED | 71 | 22 | 49 | 30 | 19 | 38.8% | +0.66% |
| GOOD | 113 | 42 | 71 | 44 | 27 | 38.0% | +7.03% |
| **全体** | **233** | **81** | **152** | **89** | **63** | **41.4%** | **+5.13%** |

※欠損の多くは最新月(2026-03)→翌月(2026-04)データが存在するため確認済み（サンプル参照）

---

## AC2: cmd_3428 相関乖離偽陽性率(70%)との比較

| 指標 | FP率 | 備考 |
|------|------|------|
| 相関乖離 (cmd_3428) | **70.0%** | 短期×長期15パターン総当たり |
| deterioration 全体ベースライン | **41.4%** | 全ラベル含む |
| deterioration DETERIORATING | **62.5%** | 最高警戒ラベル (n=24) |
| deterioration WATCH | **25.0%** | 中程度警戒 (n=4) |
| deterioration EARLY_WARNING | **25.0%** | 初期警告 (n=4) |

**結論**:
- deterioration DETERIORATING(62.5%) < 相関乖離(70.0%) → deteriorationが若干優位
- ただし全体ベースライン(41.4%)比では DETERIORATING は精度低下（FP率高い）

---

## AC3: リフト値（ラベル別 FP率 ÷ 全体ベースライン FP率）

全体ベースライン FP率 = 41.4%

| ラベル | FP率 | リフト値 | 解釈 |
|--------|------|---------|------|
| DETERIORATING | 62.5% | **1.51** | 全体の1.51倍偽陽性 → 悪化予測として逆機能 |
| WATCH | 25.0% | **0.60** | 全体の0.60倍偽陽性 → 悪化予測として有効 |
| EARLY_WARNING | 25.0% | **0.60** | 同上 |
| MIXED | 38.8% | 0.94 | ほぼ全体と同程度 |
| GOOD | 38.0% | 0.92 | ほぼ全体と同程度 |

---

## 主要発見

1. **DETERIORATINGのFP率62.5%はベースライン41.4%より高い（リフト1.51）**
   → 最高警戒ラベルが「翌月悪化予測」として機能していない
   → 理由仮説: p12/p24は長期視点の指標であり、翌1ヶ月の予測には時間スケール不一致

2. **WATCHとEARLY_WARNINGはFP25%（リフト0.60）で優れた予測力**
   → ただしサンプル数がWATCH=4件、EARLY_WARNING=4件と極めて少ない

3. **相関乖離(70%) vs DETERIORATING(62.5%)**
   → 約7.5pp差でdeteriorationが有利
   → しかし両者ともFP率>50%で「ランダムより悪い」または「ランダム同等」水準

4. **データ制約**
   → 全233件中81件(35%)が欠損（翌月データなし）
   → DETERIORATING有効サンプル=24件のみ。統計的信頼性に注意

---

## decision_candidate

タスクYAMLで指定のラベル `HIGH/VERY_HIGH` は実際のDBに存在しない。
実際のラベル体系: `DETERIORATING/WATCH/EARLY_WARNING/MIXED/GOOD`
→ 今後のcmdで `HIGH` という用語を使う場合はマッピングを明示すべき

---

## クエリ実行情報

- 実行日時: 2026-06-17
- DB接続: create_db_engine() (backend/.env)
- テーブル: deterioration_snapshots, monthly_returns
- JOINキー: portfolio_id + year_month+1ヶ月のTO_CHAR/TO_DATE変換
