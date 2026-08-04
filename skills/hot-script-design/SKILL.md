---
name: hot-script-design
argument-hint: "弾番号 開始順位-終了順位"
user-invocable: true
description: |
  ホットスクリプト集中高速化の設計書を自動生成し、gist同期まで一括実行するスキル。
  直近24時間のledgerから指定順位範囲のボトルネックを計測し、第九弾と同じスタイル・粒度で設計書を起草→commit→/gist-shareでVERIFIED同期する。
  TRIGGER: /hot-script-design、ホットスクリプト設計書、速度改善設計書作成、第N弾の設計書を作ろう、ホットスクリプトの設計書を作成、以前の設計書を参考にして同じスタイルで
  DO NOT TRIGGER: レーン配備(→家老へ下知)、是正実装(→忍者)、wave checkpoint検分(→将軍手動)、既存設計書の進捗更新のみ
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# Hot Script Design — ホットスクリプト設計書自動生成+gist同期

## 入力

引数: `<弾番号> <開始順位>-<終了順位>`
例: `13 26-35` → 第十三弾、累積課税26-35位を標的

弾番号と順位範囲は殿が指示する。

## 手順

### Phase 1: 計測(Tier 2)

1. 直近24時間のledgerから全source:check_id別に累積・中央値・p95・max・呼出数を算出する

```bash
python3 -c "
import json
from collections import defaultdict
from datetime import datetime, timedelta

cutoff = datetime.now() - timedelta(hours=24)
totals = defaultdict(lambda: {'sum_s': 0.0, 'count': 0, 'max_s': 0.0, 'vals': []})

with open('logs/defense_overhead.jsonl') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
            ts = e.get('ts','')
            if ts and datetime.fromisoformat(ts.replace('Z','+00:00')).replace(tzinfo=None) < cutoff.replace(tzinfo=None):
                continue
            src = e.get('source','')
            cid = e.get('check_id','')
            key = f'{src}:{cid}' if src and cid else (cid or src)
            dur = float(e.get('duration_ms', e.get('wall_ms', 0))) / 1000
            if dur > 0 and key:
                totals[key]['sum_s'] += dur
                totals[key]['count'] += 1
                totals[key]['max_s'] = max(totals[key]['max_s'], dur)
                totals[key]['vals'].append(dur)
        except: pass

ranked = sorted(totals.items(), key=lambda x: -x[1]['sum_s'])
ranked = [(n,v) for n,v in ranked if 'durable_trigger_missing' not in n]

for i, (name, v) in enumerate(ranked, 1):
    vals = sorted(v['vals'])
    med = vals[len(vals)//2] if vals else 0
    p95 = vals[int(len(vals)*0.95)] if len(vals) > 20 else v['max_s']
    typ = '恒常' if med > 1.0 else ('外れ値' if v['max_s']/max(med,0.01) > 50 else '砂粒' if v['count'] > 1000 else '混合')
    print(f'{i}|{name}|{v[\"sum_s\"]:.0f}|{v[\"count\"]}|{med:.2f}|{p95:.1f}|{v[\"max_s\"]:.1f}|{typ}')
"
```

2. 指定順位範囲(例: 26-35)の行を抽出する
3. 各標的の上位弾との関係(子区分か独立か)を前弾設計書から特定する

### Phase 2: 設計書生成

以下のテンプレート構造で設計書を `docs/research/hot-script-speedup-round{弾番号}-asis-tobe-5w1h_{日付}.md` に作成する。

**必須セクション**(第九弾と同一粒度):
- §-1 スコープと境界(数と原理を先に固定) — 標的定義・二段計測・前弾境界・writer構造・品質2原則・スコープ外・レーン方式・lane最小AC二層契約
- §0 序列SSOT — 取得方法(行数明記)・累積課税序列テーブル(順/source:check_id/累積/n/median/p95/max/型/上位弾関係)・**読み**(lettered observations)
- §1 計測境界 — 既存台帳のみ・same check_id比較・ノイズ判定・Tier 1/2定義・型別判定基準
- §2 To-Be(9項目) — 1標的1弾・品質底線・仮説在庫・反復サイクル・read-only冗長・選択実行・完了宣言・レーン方式・二層契約
- 提案弾台帳 — #/標的/型/現状/手筋候補/上位弾依存
- §2.5 進捗台帳 — 初版は全て未着手
- §3 decision ledger — 起動・snapshot・弾数固定・依存条件・品質境界
- §4 5W1H — WHY/WHAT/WHEN/WHERE/WHO/HOW
- §5 因果リンク — 前弾・姉妹弾・憲法・レーン型元・origin chain

**品質チェック**(生成後に自己検証):
- [ ] 全セクション(§-1〜§5)が存在するか
- [ ] 序列テーブルに累積・n・median・p95・max・型の全列があるか
- [ ] 弾台帳に型・現状・手筋候補・上位弾依存の全列があるか
- [ ] decision ledgerに裁可状態が記載されているか
- [ ] 因果リンクにorigin chainがあるか

### Phase 3: commit + gist同期

1. `bash scripts/ninja_scope_commit.sh -m "docs: 第{弾番号}弾設計書v1.0起草" -- {設計書path}`
2. `bash scripts/gist_share.sh {設計書path}` → GIST_CREATED_PENDING_COMMIT
3. メタ行追加されたファイルを再commit: `bash scripts/ninja_scope_commit.sh -m "docs: 第{弾番号}弾設計書へgist-masterメタ行埋込" -- {設計書path}`
4. `bash scripts/gist_share.sh {設計書path}` → GIST_SHARED + VERIFIED

### Phase 4: 報告

以下を出力して完了:
- 設計書path
- gist URL
- sha256一致確認
- 標的数と順位範囲

## 契約

- 設計書のスタイル・粒度は第九弾(`docs/research/hot-script-speedup-round9-asis-tobe-5w1h_20260804.md`)を正本とする
- 二段計測(Tier 1劣化検知+Tier 2ボトルネック特定)は全弾に適用(殿設計2026-08-04)
- 品質2原則(正本突合判定+境界fixture)は全弾で堅持
- gist同期は/gist-shareスキル経由でVERIFIED証跡を残す(殿裁定2026-08-04)
- 弾番号・順位範囲は殿が指示する。将軍が勝手に決めない
