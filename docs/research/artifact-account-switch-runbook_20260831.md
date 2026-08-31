<!-- gist-master: 2caac114df25ac75dbfae8fc400851fb artifact-account-switch-runbook_20260831.md -->
# Artifact アカウント切替継続 runbook — 殿指示 2026-08-31 17:48『アカウントを変えてもアーティファクトを同様に続けられるようにせよ』

> 原理: **artifact URL はアカウント所有・repo の HTML 正本はアカウント非依存。** URL は使い捨ての「窓」、正本と生成パイプラインが本体。ゆえにアカウント切替時は「窓を開け直して索引を差し替える」だけで同一運用が続く。

## §1 正本と生成系(アカウント非依存・repo 管理済み)

| artifact | HTML 正本 | SSOT/生成 | favicon |
|---|---|---|---|
| 将軍todo map | `docs/dashboard/shogun-todo-map.html` | `queue/shogun_todo_map.md` → `python3 scripts/todo_map_render.py` | 🗺️ |
| 戦況dashboard | `docs/dashboard/shogun-dashboard.html` | 将軍が直接 Edit | 🏯 |

- どちらも repo に commit されるため、**新アカウント・新マシンでも git clone だけで最新内容を再公開できる**。
- 他の一回性 artifact(設計書ビュー等)も全て `docs/dashboard/*.html` に正本があり同様。

## §2 切替手順(新アカウントの将軍セッションで実施、5 分)

1. 正本の鮮度確認: `python3 scripts/todo_map_render.py`(SSOT から再生成。git pull 済みであること)
2. **URL 無指定で publish**: Artifact ツールに `file_path=docs/dashboard/shogun-todo-map.html`、`favicon=🗺️`(**旧と同じ絵文字を維持**)。→ 新 URL が発行される
3. 索引 3 箇所を新 URL へ差し替える:
   - `queue/shogun_todo_map.md` 冒頭の `# artifact:` 行
   - MEMORY.md「Meta」節の戦況 artifact URL 行(dashboard 切替時)
   - 記憶DB: `bash scripts/memory_db_knowledge_write.sh "artifact URL 更新: todo map=<新URL>(旧<旧URL>はアカウント切替で更新不能化)" "artifact_url_rotate"`
4. dashboard(🏯)も同様に publish→MEMORY.md Meta 節を更新
5. 検証: 新セッションで `/artifacts` に新 URL が見える ∧ 30分loop の再公開が同 URL に当たる(loop は `file_path` 同一で再公開するため、**同一会話内なら URL 指定不要**)

## §3 禁則・注意

- **旧 URL は旧アカウント所有のため新アカウントから更新不能**。差し替え漏れがあると loop が「refused」で止まる → §2-3 の 3 箇所差し替えを省くな
- favicon を変えるな(殿がタブで見分ける識別子。切替後も 🗺️/🏯 を維持)
- 30分loop の手順文(`artifact 5da62854 再公開`)に旧 ID が残る場合、殿の loop 指示文も新 ID へ更新が要る → 切替時に将軍から殿へ新 ID を 1 行報告する
- HTML 正本を Edit せず artifact 側だけ更新する運用は禁止(正本=SSOT、URL=窓)

## §4 いま出来ていること / 追加した保険

- [x] HTML 正本 repo 管理(§1) — 従来から
- [x] SSOT→render の再生成パイプライン — 従来から
- [x] 本 runbook(切替手順の永続化、gist 共有)
- [x] MEMORY.md Meta 節へ本 runbook のポインタ追記 → 次セッションの将軍が自動ロードで手順に到達

origin: `[[殿指示_artifact_account切替継続_20260831_1748]] -> [[HTML正本repo管理]] -> [[artifact_account_switch_runbook]]`
