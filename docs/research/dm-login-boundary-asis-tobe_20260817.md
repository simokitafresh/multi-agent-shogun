# ログイン境界 AsIs/ToBe — tier境界のデータ漏れを構造で塞ぐ

## 原則（親文書と同じ。殿裁定 2026-08-15）

- ToBeは構造的に不可能でない限り妥協しない。AsIsは現実のコードそのもの。変更履歴は書かない（見出し=版+タイムスタンプ、粒度は末尾注釈）。
- 実装は殿の指示まで行わない（2026-08-17 00:26 殿「これは実装の話ではなくチャット」／00:42「まだ実装には入らず手を進めよう」）。

発端: 殿観測 2026-08-17 00:26 — admin認証→ログアウト→低tierで再ログインすると本来見えないPFのキャッシュが表示され、リロードするまで直らない。
イメージ図: https://claude.ai/code/artifact/1c498f5f-100f-447a-90ce-75d389a51904

## AsIs **v0.1** — 2026-08-17 00:50+09:00（仮説。cmd_4322 read-only棚卸しで現物確定後にv1.0へ）

**AsIs契約表**（cmd_4322 の報告で埋める）

| 層 | 現物（ファイル/関数） | 認証切替の形 | キャッシュキーに主体を含むか | ログアウト時に消えるか |
|---|---|---|---|---|
| 認証(admin) | `frontend/contexts/admin-auth-context.tsx`, `frontend/lib/admin-auth.ts`（実在確認済み・中身未確認） | 要確認 | — | 要確認 |
| 認証(viewer) | `frontend/components/viewer-auth-modal*`（テスト実在）— モーダル=同一ツリー内の疑い | 要確認 | — | 要確認 |
| データ層 | `frontend/contexts/signals-context.tsx`, `frontend/lib/api-cache.ts`, SWR/Context/localStorage(9ファイルで参照) | — | 要確認 | 要確認 |
| HTTP | `backend/app/utils/etag.py`, `backend/app/utils/cache.py`(TTLCache 300s) | — | ETag生成入力に主体を含むか要確認 | — |

仮説の因果列: 同一ツリー内で認証だけ切替 → データ層のキーに主体が無い → ログアウトで認証情報のみ削除 → 低tier再ログインで同キーにヒット → 非公開PF表示 → リロード=ツリー全破棄で正常化。

## ToBe **v0.1** — 2026-08-17 00:50+09:00

- `/login` ルートを境界にする。未認証はデータfetchを走らせない（ルートガード）。
- 認証成功／ログアウトのたびに **ハードリセット**（データ層・store・localStorage/sessionStorage全消去）してから遷移。
- キャッシュキー = `[主体(tier/token hash), endpoint, params]`。別主体は別キー。
- tier依存APIは `Cache-Control: private, no-store` またはETagを主体込みで生成。
- 合否（各実装手の二値）: admin→ログアウト→低tier再ログインで、非公開PFがリロードなしに表示されない。

## 注釈 — 2026-08-17 00:50+09:00

- AsIs注釈: 上表の「要確認」は cmd_4322 の報告で現物名に置き換える。推測を残さない。
- ToBe注釈: ログインページはUIではなく「境界装置」。モーダル方式では消し忘れが意志依存になる。
