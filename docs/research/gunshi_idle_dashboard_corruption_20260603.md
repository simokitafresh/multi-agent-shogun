# dashboard.md 0バイト化 根因分析

## 分析日時
2026-06-03T21:50+09:00

## 事象
karo_workarounds直近2件でdashboard.mdが0バイト化:
1. cmd_training_backlinks_saizo_20260602: 引数なし失敗後、cmd_id指定の2件目で0 bytes化
2. cmd_3145 (2026-06-03): dashboard.mdが0バイト化→dashboard_update.shが'## 最新更新'不在で失敗

いずれもdashboard.md.bakから手動復元(家老workaround)。resolved_by_cmd: '' — 根因修正未実施。

## 根因
dashboard_update.shのStep 5 (L411) / Step 6.7 (L510) が `open(DASHBOARD, 'w')` で直接上書き:
1. `open(file, 'w')` はファイルを**即時truncate**(0バイト化)してから書込みを開始
2. truncateと`f.write(content)`の間にプロセスが中断されると、ファイルは0バイトのまま残る
3. WSL2 NTFSはI/O中断が発生しやすい環境(LG016で実証済み)

## 証拠
- dashboard_auto_section.sh (L1276-1278): 既にatomic write(`> tmp` + `mv tmp DASHBOARD`)を実装 → 0バイト化報告なし
- dashboard_update.sh Step 5/6.7: 直接`open('w')` → 0バイト化2件

## 影響
- 家老のworkaround: .bakから手動復元(CTX消費+作業中断)
- dashboard壊れた状態で次のdashboard_update.shが失敗し連鎖エラー

## 対策
dashboard_update.shの3箇所の書込みをatomic write化:

### 修正1: Step 5 (L411-412)
```python
# Before
with open(DASHBOARD, 'w') as f:
    f.write(content)

# After
import tempfile
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(DASHBOARD), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w') as f:
        f.write(content)
    os.replace(tmp_path, DASHBOARD)
except:
    os.unlink(tmp_path)
    raise
```

### 修正2: Step 6.7 (L510-511)
同上のパターンを適用。

### 修正3: Step 7 sed -i (L585-588)
sed -iはGNU版では内部でtmp+renameだが、WSL2 NTFS上の挙動は不確実。
代替: pythonでの処理に統合、またはsed結果をtmpに書いてmv。

## 効果予測
- atomic write(tmp+rename)はOS atomicityを保証 → truncate-then-write問題が構造的に排除
- dashboard_auto_section.shが既に同パターンで0バイト化ゼロ件 = 実績あり

## セルフレビュー
1. 数値検算: 書込み箇所3箇所(L411, L510, L585-588)は`grep -n "open.*'w'\|sed.*-i" dashboard_update.sh`で実測確認
2. 前提検証: flock保護はあるが同一プロセス内のcrash対策にはならない。WSL2 NTFS I/O不安定はLG016で実証済み
3. 事前検死: (a)tmp作成失敗→except句で元ファイル不変 (b)os.replace失敗→tmpが残るだけ、元ファイル不変 (c)ディスク空き不足→tmpへのwrite失敗→元ファイル不変

## cmd提案
- 対象: scripts/dashboard_update.sh (Step 5/6.7/7の3箇所)
- 規模: 1ファイル約15行変更
- テスト: bats test_dashboard_update.bats (既存テスト)
- 優先度: HIGH(2日連続WA。家老の手動復元負荷)
