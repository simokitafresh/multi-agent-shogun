# 家老レビュー — 試行錯誤根治5 commit（2026-09-01）

- 下知: 殿 2026-09-01 12:51「試行錯誤の裏のバグを根治し、将軍レビュー」
- 依頼: `msg_20260901_130253_2487936_0d6c1579`
- 判定: APPROVE 3 / REJECT 2

| commit | 判定 | 理由 |
|---|---|---|
| `2467ded95` | APPROVE | web route除外は明示target matchと実在fileを保持し、`/faq/en/`偽BLOCKのみを除去する。 |
| `3d763cd8e` | APPROVE | index blob不在のstaged削除だけをshell構文検査から除外し、追加・変更blobのfail-closedを維持する。 |
| `559c02538` | REJECT | (1) Codex 0件時の `pgrep -c ... || echo 0` が `0\n0` となり整数比較を壊す。(2) ready regexが`bypass permissions on` footer単独でも成立し偽readyになり得る。(3) `reset_layout.sh`はready timeoutを`|| true`で捨て、その後にrespawn完了を表示する。 |
| `05f1af73d` | APPROVE | Python `\b`の日本語隣接漏れをASCII境界へ変更し、ASCII識別子内の`inbox`は除外しない。 |
| `0e47414a8` | REJECT | Guard4はpure Pythonの `open(..., 'w').write(...)` を、`re.sub` / `.replace` / `awk`が無い場合に見逃す。説明するwrite-capable操作と実装条件が不一致。 |

## 修正要求

1. `559c02538`
   - Codex process数は`pgrep ... || true`後に空値を0へ正規化し、単一整数だけを比較する。
   - ready判定はCLI promptを正本にし、footer単独一致を除外する。usage-limit/update画面の敵対fixtureを追加する。
   - `reset_layout.sh`も失敗paneを累積し、末尾でnonzero。timeout後に「完了」と表示しない。
2. `0e47414a8`
   - Python write pattern単独でBLOCKする。
   - `open(..., w/a/x/+)`、`Path.write_text/write_bytes`の陽性fixtureと、read-only openの陰性fixtureを追加する。

## 証跡

- 旧root stub: 14行、`bash -n` rc=0、新rootへ`exec`。
- 1件の定義: 指定commit 1本。
- 将軍はREJECT 2本をD0修正後、再レビューを依頼すること。
