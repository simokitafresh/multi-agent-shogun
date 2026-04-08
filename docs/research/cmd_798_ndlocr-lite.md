# NDL OCR-Lite 深掘り偵察統合

> cmd: cmd_798 | 偵察: 水平4名(影丸/半蔵/才蔵/小太郎) | 統合: 影丸
> 対象: [ndlocr-lite](https://github.com/ndl-lab/ndlocr-lite) v1.1.0+
> ライセンス: CC BY 4.0（商用利用可・帰属表示のみ）
> 作成: 2026-03-11

---

## §1 概要・リポジトリ構造

**結論**: 3段パイプライン(レイアウト検出→読み順整序→文字認識)のONNX推論OCR。モデル同梱150MB、Python 3.10+、CPU動作。

### リポジトリ構成

| パス | 役割 |
|------|------|
| `src/ocr.py` | エントリポイント。CLI引数解析+全パイプライン統合+出力生成 |
| `src/deim.py` | レイアウト検出(DEIMv2)。ONNX推論ラッパー |
| `src/parseq.py` | 文字認識(PARSeq-tiny)。3段カスケードONNX推論 |
| `src/ndl_parser.py` | 検出結果→NDL-XML変換+表認識(LORE-TSR)+HTML/Markdown変換 |
| `src/tablerecog.py` | 表認識(LORE-TSR ONNX)。モデル未同梱のため現状未使用 |
| `src/config/ndl.yaml` | 17検出カテゴリ定義 |
| `src/config/NDLmoji.yaml` | 文字セット(7000+文字: CJK/ひらがな/カタカナ/Latin/Greek等) |
| `src/reading_order/` | XY-Cut読み順整序モジュール(eval.py/block_xy_cut.py/reorder.py等) |
| `src/model/` | ONNXモデル4ファイル(後述) |
| `ndlocr-lite-gui/` | Flet製GUIアプリ(独立パッケージ) |
| `train/` | 学習ユーティリティ(PyTorch→ONNX変換、データ変換) |

### ONNXモデル

| ファイル | サイズ | 用途 | 入力解像度 |
|----------|--------|------|-----------|
| deim-s-1024x1024.onnx | 39MB | レイアウト検出(DEIM-S) | 1024×1024 |
| parseq-ndl-16x256-30-tiny | 35MB | 文字認識(≤30文字) | 16×256 |
| parseq-ndl-16x384-50-tiny | 36MB | 文字認識(≤50文字) | 16×384 |
| parseq-ndl-16x768-100-tiny | 40MB | 文字認識(≤100文字) | 16×768 |

合計: 約150MB（リポジトリ同梱、追加DL不要）。表認識用モデル(ndltsr_*.onnx)は未同梱。

### 主要依存ライブラリ

| ライブラリ | バージョン | 用途 |
|-----------|-----------|------|
| onnxruntime | 1.23.2 | ONNX推論エンジン(CPU/CUDA) |
| opencv-python-headless | 4.11.0.86 | 画像リサイズ・回転 |
| Pillow | 12.1.1 | 画像読込・描画 |
| numpy | 2.2.2 | テンソル操作 |
| lxml | 5.4.0 | XML処理 |
| flet | 0.27.6 | GUI(API化では不要) |

Python要件: >=3.10。ビルド: setuptools。ライセンス: 全依存ライブラリが商用利用可(MIT/Apache2/BSD)。GPLなし。

---

## §2 OCRパイプライン（3モジュール詳細）

**結論**: DEIM→XY-Cut→PARSeqカスケードの5フェーズ。縦書き自動対応。ThreadPoolExecutorで並列認識。

### 処理フロー

```
画像入力(jpg/png/tiff/jp2/bmp)
  │
  ▼ Phase 1: レイアウト検出 (DEIM)
  │ deim.py:DEIM.detect()
  │ 正方形パディング→1024×1024リサイズ→ImageNet正規化→ONNX推論
  │ 出力: [{class_index, confidence, box[x1,y1,x2,y2], pred_char_count, class_name}]
  │ conf>0.25でフィルタ。17カテゴリ検出
  │
  ▼ Phase 2: XML構造生成
  │ ndl_parser.py:convert_to_xml_string3()
  │ 検出結果→NDL-XML形式(PAGE/BLOCK/LINE要素)
  │
  ▼ Phase 3: 読み順整序 (XY-Cut)
  │ reading_order/xy_cut/eval.py:eval_xml()
  │ X/Yヒストグラム→再帰分割→IoUでLINE割当→深さ優先ORDER付与
  │ 縦書き判定(h>w): 右→左。横書き: 上→下
  │
  ▼ Phase 4: 文字認識 (PARSeqカスケード)
  │ ocr.py:process_cascade() + parseq.py:PARSEQ.read()
  │ ★カスケード: pred_char_cnt≤30→256幅、≤50→384幅、他→768幅
  │ ★エスカレーション: 結果≥25文字→384幅再認識、≥45文字→768幅再認識
  │ 縦長行は自動90°回転。ThreadPoolExecutorで並列処理
  │
  ▼ Phase 5: 出力生成
    XML(.xml) / JSON(.json) / TXT(.txt)
    縦書き比率>50%でテキスト逆順出力
```

### 17検出カテゴリ

text_block, line_main, line_caption, line_ad, line_note, line_note_tochu, block_fig, block_ad, block_pillar, block_folio, block_rubi, block_chart, block_eqn, block_cfm, block_eng, block_table, line_title

---

## §3 入出力仕様

**結論**: 入力は画像ファイル(6形式)。出力はXML/JSON/TXTの3形式。PDF非対応。出力先ディレクトリは事前作成必須。

### 入力

| 項目 | 仕様 |
|------|------|
| 対応形式 | jpg/jpeg/png/tiff/tif/jp2/bmp |
| 非対応 | PDF、GIF、マルチページTIFF |
| 読込 | `PIL.Image.open().convert("RGB")` — 単ページ画像前提 |
| ディレクトリ | `--sourcedir`は直下のみ(再帰なし)。viz_*画像も再処理対象になる |
| 出力先 | `--output`は存在するディレクトリ必須(自動作成なし) |

### CLI引数

| 引数 | 用途 | 注意 |
|------|------|------|
| `--sourcedir` | 画像ディレクトリ一括 | `--sourceimg`と排他 |
| `--sourceimg` | 単一画像 | |
| `--output` | 出力先ディレクトリ | 事前作成必須 |
| `--viz` | 可視化画像生成 | ⚠ `type=bool`のため`--viz False`でも真になるバグ |
| `--simple-mode` | カスケードなし | ⚠ 引数定義のみで処理本体で未参照(死に引数) |
| `--device` | cpu/cuda | デフォルト: cpu |
| `--det-weights` | 検出モデル差替 | |
| `--rec-weights/30/50` | 認識モデル差替(3段) | |
| `--det-score/conf/iou-threshold` | 検出しきい値 | |

### 出力形式

| 形式 | 内容 |
|------|------|
| XML | `<OCRDATASET><PAGE>` — LINE要素にSTRING属性で認識文字列 |
| JSON | `{contents, imginfo}` — 行単位配列(boundingBox/text/confidence/id)。⚠ `isVertical`は常に`"true"`固定 |
| TXT | 行連結プレーンテキスト。縦書き比率>50%で逆順 |
| viz画像 | `viz_<元ファイル名>`。jp2時のみ拡張子.jpgに変換 |

### 処理時間実測(CPU, WSL2)

| 画像 | 検出件数 | 推論時間 | 備考 |
|------|---------|---------|------|
| 単画像(A4相当) | 47件 | 3.6s(推論) / 13.9s(起動込み) | モデルロード約10秒 |
| 6枚バッチ | — | 2.4s〜11.7s/枚 | モデル初期化1回 |
| 総wall clock(6枚) | — | 53.3s | |

目安: **100ページ → 5〜25分(CPU)**

---

## §4 サーバーサイド運用設計（API化・Docker・デプロイ）

**結論**: FastAPI+uvicornで容易にAPI化。モデル常駐300-350MB、推論ピーク450-500MB。VPS 2GB($5-10/月)が最安定。

### FastAPI設計

| エンドポイント | メソッド | 機能 |
|---------------|---------|------|
| `/api/v1/ocr` | POST | multipart/form-data画像受信→OCR→JSON/XML/text返却 |
| `/api/v1/health` | GET | モデルロード状態確認 |

- lifespanイベントで4モデル事前ロード
- `format`クエリパラメータでjson/xml/text切替
- GUI依存(flet)は不要。requirements.txtから除外可能
- 完全なFastAPIコード例 → `queue/reports/hanzo_report_cmd_798.yaml` L63-169

### Docker化

```dockerfile
FROM python:3.12-slim
# flet/reportlab/pypdfium2除外、fastapi/uvicorn/python-multipart追加
# イメージサイズ見積り: ~600MB
```

### メモリ/CPU要件

| 項目 | 値 |
|------|-----|
| モデル常駐 | 300-350MB(4モデル展開) |
| 推論時ピーク | 450-500MB(1リクエスト) |
| 推奨RAM | 最低512MB(小画像)、推奨1GB、安全域2GB |
| CPU | 最低1コア、推奨2コア+ |
| ワーカー注意 | N×300MB常駐(マルチワーカー非推奨→キュー方式) |

### デプロイ先比較

| デプロイ先 | RAM | 月額 | 判定 | 備考 |
|-----------|-----|------|------|------|
| Render Free/Starter | 512MB | $0/$7 | ✗ | モデル300MB超、推論時OOM確定 |
| Render Standard | 2GB | $25 | △ | ギリギリ。大画像でOOMリスク |
| Render Pro | 4GB | $85 | ○ | 安定動作 |
| AWS Lambda | 10GB | 従量 | △ | コールドスタート30-90秒が致命的 |
| **VPS(2GB)** | 2GB | **$5-10** | **◎** | **最安定。常時起動でコールドスタートなし** |
| Railway | 柔軟 | $5~ | ○ | Docker対応、メモリ柔軟 |
| 自宅WSL2 | 制限なし | $0 | ◎ | Cloudflare Tunnel等で公開可 |

---

## §5 カスタマイズ性

**結論**: モデル差替・しきい値調整はCLI対応済み。文字認識の信頼度閾値やbeam searchは未公開。言語変更は再学習必須。

| カスタマイズ | 方法 | 難易度 |
|-------------|------|--------|
| 検出モデル差替 | `--det-weights`+`--det-classes` | 低 |
| 認識モデル差替 | `--rec-weights/30/50`+`--rec-classes` | 低 |
| 検出しきい値 | `--det-score/conf/iou-threshold` | 低 |
| 入力サイズ変更 | `deim.py`直接編集(正方パディング+resize固定) | 中 |
| 認識前処理変更 | `parseq.py`直接編集(`/127.5-1.0`正規化固定) | 中 |
| 文字セット変更 | NDLmoji.yaml差替+PARSeq再学習+ONNX変換 | 高 |
| 言語変更 | 文字セットYAML+PARSeqモデル再作成(`train/README.md`) | 高 |
| 認識信頼度閾値 | CLI未公開。コード直接編集が必要 | 中 |
| 表認識有効化 | ndltsr_*.onnxモデルの別途入手が必要 | 中〜高 |

### 学習・ONNX変換

- `train/parseqcode/convert2onnx.py` — PyTorch→ONNX変換
- `train/parseqcode/convertndlocrdata2lmdb.py` — データ変換
- 手順詳細: `train/README.md`

---

## §6 制限事項

**結論**: 活字印刷は高精度(95%+期待)。手書き・数式・PDF・横書きに制約あり。GUI版は日本語パス問題。

### 精度限界

| 対象 | 精度見込み | 備考 |
|------|-----------|------|
| 活字印刷(縦書き) | 95%+ | 主要ターゲット。古典籍〜近代書籍 |
| 活字印刷(横書き) | 良好(未定量) | 処理可能だが縦書き優先設計 |
| 手書き(古典籍崩し字) | 中程度 | tegakiモデルで部分対応 |
| 手書き(現代) | 70-80%(推定) | 学習データが古典籍中心。子供の手書きは未検証 |
| 数式・化学式 | 低 | block_eqn検出あるが文字セット外記号で失敗の可能性 |
| 混在レイアウト | 未検証 | 17クラス検出だがカラー教科書での精度は不明 |
| 1行上限 | 100文字 | カスケード最大モデルの制約 |

### 環境・技術制約

| 制約 | 詳細 |
|------|------|
| PDF非対応 | pypdfium2でページ画像変換が必要(前処理) |
| GIF非対応 | 対応拡張子: jpg/jpeg/png/tiff/tif/jp2/bmpのみ |
| 再帰走査なし | `--sourcedir`は直下のみ |
| GUI日本語パス | flet依存。Issue #4/#26。CLI/API利用で回避可 |
| `--viz False`バグ | `type=bool`のためFalse指定でも真。CLI/API側で回避 |
| `--simple-mode`無効 | 引数定義のみ。処理本体で未参照 |
| `isVertical`固定 | JSON出力で常に`"true"`。実際の縦横判定値ではない |
| CUDA利用 | onnxruntime-gpu別途必要。標準はCPU版のみ |
| 表認識モデル未同梱 | ndltsr_*.onnxが必要だがリポジトリに含まれない |
| テストスイートなし | 自動テスト未同梱 |

### コミュニティ

873スター/42フォーク(公開1ヶ月)。メンテナ(NDLスタッフ)が1-3日でIssue対応。非常にアクティブ。

---

## §7 活用シナリオ（M!LK・汎用）

### (a) 教科書写真→テキスト抽出→学習項目DB化

| Step | 処理 | 備考 |
|------|------|------|
| 1 | 撮影(スマホ) | 正面撮影、十分な照明、1000x1000px+ |
| 2 | 前処理(任意) | 回転補正・余白トリミング。二値化不要 |
| 3 | OCR実行 | `ocr.py --sourceimg photo.jpg --output results/` |
| 4 | テキスト後処理 | LLM(Claude API等)で教科分類+キーワード抽出 |
| 5 | DB格納 | テキスト+メタデータ(ページ番号/教科/撮影日時) |

期待精度: 教科書活字95%+、手書きメモ70-80%

### (b) プリント→問題文抽出→類似問題生成

| Step | 処理 | 備考 |
|------|------|------|
| 1-2 | 撮影+OCR | (a)と同じ |
| 3 | 構造化抽出 | XMLのLINE TYPE属性で分類(line_main/line_title/block_eqn等) |
| 4 | 階層推定 | 位置情報から大問→小問→選択肢構造を推定 |
| 5 | 類似問題生成 | 問題文をLLMに入力。数式は画像でマルチモーダル |

### (c) 汎用バッチ処理

| Step | 処理 | 備考 |
|------|------|------|
| 1 | 入力準備 | `--sourcedir`で画像ディレクトリ指定。PDF→pypdfium2変換 |
| 2 | バッチ実行 | ディレクトリ単位。大量時はprocess()直接import推奨 |
| 3 | エラー処理 | 破損画像: PIL例外スキップ。大画像: リサイズ後リトライ |
| 4 | 結果保存 | .txt→全文検索DB / .json→アプリ連携 / .xml→構造化アーカイブ |

性能: 100ページ5-25分(CPU)。マルチプロセス並列化可(メモリ×N倍)

---

## §8 結論・推奨事項

### 総合評価

| 観点 | 評価 | 根拠 |
|------|------|------|
| 活字OCR精度 | ◎ | NDL古典籍OCRの発展版。17クラス検出+カスケード認識 |
| 手書き対応 | △ | tegakiモデルあるが古典籍中心。現代手書きは要検証 |
| API化容易性 | ◎ | 3関数import+FastAPIで完結。GUI依存なし |
| デプロイ | ○ | Docker化容易。VPS 2GB($5-10/月)で安定稼働 |
| カスタマイズ | ○ | モデル差替・しきい値CLI対応。言語変更は再学習必須 |
| ライセンス | ◎ | CC BY 4.0。帰属表示のみで商用利用可 |
| コミュニティ | ◎ | 873★/42fork。Issue対応1-3日。長期利用可能 |
| 制約 | △ | PDF非対応、手書き限界、テストなし |

### 推奨アクション

1. **M!LK統合**: CLI/API経由で利用(GUI制約回避)。教科書活字は高精度期待
2. **デプロイ**: VPS 2GB($5-10/月)が最安定。自宅WSL2+Cloudflare Tunnelも選択肢
3. **手書き精度**: 現代手書き(特に子供の文字)の精度検証を実施すべき
4. **API実装**: FastAPIコード例は`queue/reports/hanzo_report_cmd_798.yaml`に完備
5. **帰属表示**: 「OCRエンジン: NDL OCR-Lite (国立国会図書館, CC BY 4.0)」をAbout等に表示

---

*偵察ソース: 影丸(構造+パイプライン) / 半蔵(API化+運用) / 才蔵(入出力+カスタマイズ) / 小太郎(制限+活用)*
