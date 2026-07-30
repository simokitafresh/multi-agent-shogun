---
name: x-thread-fetch
description: |
  Xの投稿URL1つから、そのスレッド(ツリー)全体の本文と画像を1つの知識として取得・保存する。
  syndication API(認証不要・全文正確)+xAI Grok x_search(スレッド全post ID列挙)を組合せ、
  WebFetch要約(haiku経由で原文が失われる)を使わず全文をローカルへ記録する。
  TRIGGER: /x-thread-fetch、Xのスレッド取得、Xツリー全文取得、Xの投稿を知識化、x.com/.../status/リンクの内容を教えて(ツリー込み)
  DO NOT TRIGGER: 単発Xポスト1件だけでよい場合（→scripts/x_thread_fetch.pyを--no-grokで直接実行すれば足りる）、
  Xトレンド調査・話題横断検索（→x-research）、鍵アカ/非公開ポストの取得（不可）
allowed-tools:
  - Bash
  - Read
---

## 何をするか

Xの投稿URL(`https://x.com/.../status/<ID>` または `https://x.com/i/status/<ID>`)を受け取り、
そのスレッド(スレッド主の連続ポスト)全体の本文・画像・投稿順序を1つのMarkdown+JSONへ保存する。

## 実行手順

```bash
python3 scripts/x_thread_fetch.py --url "https://x.com/i/status/<ID>"
```

出力: `data/x-research/thread_<ID>/`
- `thread.md` — 読み物版(各postの全文+画像パス+番号prefix欠番検査)
- `thread.json` — 生データ(id/text/user/created_at/photos URL/local_images)
- `images/NN_J.jpg` — 画像(`?name=large`で原寸取得)

取得後、`thread.md`を**Read toolで自分で読め**。WebFetchでURLを渡すな(haiku要約で原文が失われる。全文記録してから読むのが正=殿の恒久指示)。

## 仕組み(2段構え)

1. **公開syndication API**(`cdn.syndication.twimg.com/tweet-result?id=<ID>&token=x`、認証不要): 起点postの正確な全文・author・画像URLを取得。
2. **xAI Grok x_search**(`config/xai_api.env`のキー使用、`scripts/x_research.py`と共通基盤): 起点postの内容を渡し、同一スレッド(スレッド主の連続post)のIDをGrokに検索・列挙させる。
3. 列挙された全IDをsyndication APIで個別取得し、正確な本文+画像を回収(Grokの要約ではなく実データ)。

`--no-grok`で起点postのみ取得も可能(Grok不要・高速)。

## 精度についての正直な注記

- Grok列挙は取りこぼしうる。`thread.md`末尾の「番号prefix検査」(スレッド主が`1/ 2/ 3/...`と番号を振っている場合、連番の欠番を機械検査)で網羅性を確認せよ。欠番があれば再実行するか、該当IDを`thread.json`へ手動追記する。
- 実測(2026-07-30): 初回実行で14/15件のみ検出→再実行で15/15件・欠番なしを確認。**1回の実行結果を鵜呑みにせず、番号検査がPASSするまで確認する。**
  <!-- example_execution_verified_at: 2026-07-30 -->
  実行例: `python3 scripts/x_thread_fetch.py --url "https://x.com/i/status/1386486318423691264"` → `OK posts=15/15 images=14 out=.../thread_1386486318423691264`、`thread.md`末尾「番号prefix検査: 1..15 欠番=なし」
- 公開ポストのみ対象。鍵アカ・削除済み・凍結アカウントの投稿は取得不可(syndication APIが404/403を返す)。

## 情報源

- syndication API: Xが自社埋め込みウィジェット用に提供する公開JSON API(認証不要、レート制限は緩い)
- Grok x_search: `scripts/x_research.py`と同じxAI Responses API(`https://api.x.ai/v1/responses`, model=`grok-4-1-fast-reasoning`)
