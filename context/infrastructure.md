# インフラコンテキスト
<!-- last_updated: 2026-02-23 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。
> 詳細: `docs/research/infra-details.md`

## コンテキスト管理

全て外部インフラが自動処理。エージェントは何もするな。忍者=/clear、家老=/clear(陣形図付き)、将軍=殿判断。
閾値: ソフト50%（外部トリガー）、ハード90%（AUTOCOMPACT）。CLI差異は`config/settings.yaml`参照。
→ `docs/research/infra-details.md` §1

## 直近改善（cmd_181〜cmd_255）

| cmd | 改善 | 結論 |
|-----|------|------|
| 181 | acknowledged status | assigned→acknowledged→in_progress遷移でゴースト配備誤判定解消 |
| 183 | ペイン消失検知 | remain-on-exit=on + ninja_monitor自動回復 |
| 188 | inbox re-nudge | @inbox_unread表示 + monitor自動再ナッジ |
| 189 | inbox_mark_read.sh | flock+atomic writeで既読化経路統一（Edit tool禁止） |
| 191 | idle家老auto-nudge | pending cmd検知時にmonitorが家老へ自動ナッジ |
| 192 | grep -c改行バグ | awk代替で単一数値返却に統一 |
| PD-016/239 | 裁定伝播遅延検出 | context_synced:false自動付与→gate WARNING（非ブロッキング） |
| PD-017/239 | 知識鮮度警告 | deploy時last_updated検査→14日超WARNING（非ブロッキング） |

→ `docs/research/infra-details.md` §2

## ninja_monitor.sh

idle検知+/clear送信、is_task_deployed二重チェック、STALE-TASK検出、CLEAR_DEBOUNCE=300s、karo_snapshot自動生成、状態遷移検知(cmd_255)。
→ `docs/research/infra-details.md` §3

## inbox_watcher.sh

inotifywait検知→`inboxN`短ナッジ送信。symlink注意。fingerprint dedup(cmd_255)。
→ `docs/research/infra-details.md` §4

## ntfy.sh

`bash scripts/ntfy.sh "msg"` のみ。引数追加厳禁。topic=shogun-simokitafresh。
→ `docs/research/infra-details.md` §5

## tmux設定

prefix=Ctrl+A。session=shogun、W1=将軍、W2=agents(家老+忍者9ペイン)。形式: shogun:2.{pane}
上忍: hayate kagemaru hanzo saizo kotaro tobisaru / 下忍: sasuke kirimaru。CLI→`config/settings.yaml`

| pane | 名前 | pane | 名前 | pane | 名前 |
|------|------|------|------|------|------|
| 1 | karo | 4 | hayate | 7 | saizo |
| 2 | sasuke | 5 | kagemaru | 8 | kotaro |
| 3 | kirimaru | 6 | hanzo | 9 | tobisaru |

→ `docs/research/infra-details.md` §6-7

## WSL2固有

inotifywait不可(/mnt/c)→statポーリング。.wslconfigミスで全凍死注意。→ §8

## Infra教訓索引

| ID | 結論 | 区分 | 出典 |
|---|---|---|---|
| L001 | Write前Read必須 | CLI | cmd_125 |
| L002 | FG bashでnudge不可 | inbox | cmd_125 |
| L003 | MD更新=稼働中反映なし | CTX | cmd_125 |
| L004 | pane変数空≠未配備 | tmux | cmd_092 |
| L005 | ashigaru→roles/参照 | build | cmd_134 |
| L006 | lesson重複チェック欠如 | 教訓 | cmd_134 |
| L007 | whitelist gitignore注意 | git | cmd_140 |
| L008 | WSL2新sh→CRLF混入 | WSL2 | cmd_143 |
| L009 | commit前git status確認 | git | cmd_143 |
| L010 | status行^先頭マッチ | 報告 | cmd_145 |
| L011 | core.hooksPath確認 | git | cmd_147 |
| L012 | aliasでpipeブロック不可 | bash | cmd_147 |
| L013 | L005のkaro版 | build | cmd_150 |
| L014 | grep exclude WSL2不安定 | WSL2 | cmd_151 |
| L015 | CONFIG_DIR切替 | OAuth | saizo |
| L016 | OAuthトークン競合 | OAuth | tobisaru |
| L017 | 入口門番→再配備自己ブロック | 配備 | cmd_158 |
| L018 | Edit tool flock未対応 | inbox | cmd_189 |
| L019 | grep -c‖echo 0二重出力 | bash | cmd_192 |
| L020 | 設定パス環境変数共有 | script | cmd_208 |
| L021 | declare -A→-gA scope | bash | cmd_208 |
| L022 | flock内python retry誤発動 | script | cmd_220 |
| L023 | 自動化は報告スキーマ先行 | 教訓 | cmd_231 |
| L024 | 報告アーカイブ不在 | 報告 | cmd_231 |
| L025 | =L027 draft版 | 報告 | cmd_236 |
| L026 | 14%陳腐化→deprecation | 知識 | cmd_237 |
| L027 | 統合タスクでreport上書き | 報告 | cmd_236 |
| L028 | CI Run#とSHA整合確認 | CI | cmd_248 |
| L029 | nudge嵐=二重経路合流 | inbox | cmd_255 |
| L030 | current_project死コード | 知識 | cmd_258 |
| L031 | PJ固有=CLAUDE.mdの4% | 知識 | cmd_258 |
| L032 | PJセクション境界=## | 知識 | cmd_258 |
| L033 | confirmed時status欠落 | 教訓 | cmd_262 |
| L034 | YAMLインデント変動 | ゲート | cmd_279 |
| L035 | gate検証で副作用発火 | ゲート | cmd_279 |
