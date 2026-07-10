# GA-216/GA-217 dm-signal lesson→context未合流6件 — 原因調査と還流記録

- cmd: cmd_karo_hotfix_ga216_lesson_context_reflux_202607101555_normal
- 記録者: kagemaru
- 日付: 2026-07-10
- 関連alert: GA-216 (logs/gate_alerts.yaml, detected_at 2026-07-10T15:54:45+0900), GA-217 (同 16:00:24+0900, 同一fingerprint再発)

## 1. 一次確認（AC1前半）

`bash scripts/gates/gate_lesson_health.sh dm-signal` 実行結果（修正前・GA-216検知時点と同値）:

```
ALERT: dm-signalのlesson→context未合流6件(total:847,synced:L857,max:L863)
```

- `total_lessons` = 847（`projects/dm-signal/lessons.yaml` の非deprecated件数、awk一括集計）
- `max` = L863（同ファイル内lessonの最大id。SSOT `/mnt/c/Python_app/DM-signal/tasks/lessons.md` には既にL864も存在するが、YAMLキャッシュ側の非同期sync未反映のため本cmd実行時点では未反映。L864自体は本AC1スコープ外だが§3で扱う）
- `synced` = L857（`context/dm-signal.md` の `<!-- last_synced_lesson: L857 -->` マーカー）
- 未合流6件 = L858, L859, L860, L861, L862, L863

## 2. L858-L863 個別調査

各lessonの技術的サマリと、「なぜgateが未合流と判定したか」の直接原因・根本原因・横展開候補。
6件は**同一の根本原因を共有**しており、内容面ではなく合流経路の設計に原因がある。

### L858
- 内容: パリティ残存乖離の原因は推測せず3点突合(本番/ライブ実行/GS)で必ず切り分けよ（cmd_3816, subdomain=fe）
- 直接原因: `subdomain: fe` のため `resolve_lesson_context_route()`（scripts/lesson_write.sh）が `context/dm-signal-frontend.md` へルーティング。実際に同ファイルへ合流済み（`context/dm-signal-frontend.md:329`、marker `L861`）。しかし旧gate_lesson_health.shは `context/dm-signal.md` の `last_synced_lesson`(L857) のみを見ており、frontend.md側の合流を認識できなかった。
- 根本原因: §3参照（共通）
- 横展開候補: §3参照

### L859
- 内容: PipelineEngine検証スクリプトはrebalance_triggerを無視した固定target_dateだと非monthlyリバランスPFを誤って乖離判定する（cmd_3818, subdomain=gs）
- 直接原因: `subdomain: gs` → `context/dm-signal-ops.md`（§33アンカー）へルーティング済み・合流済み（`context/dm-signal-ops.md:810`、marker `L864`）。gateはops.md側を見ていなかった。
- 根本原因/横展開候補: §3参照（共通）

### L860
- 内容: PostgreSQL binary COPYは列名タグを持たない位置ベース形式。source/target列順不一致がUTF8デコードエラー等を生む（cmd_3819, subdomain=gs）
- 直接原因: L859と同型（gs→ops.md、`context/dm-signal-ops.md:811`に合流済み）
- 根本原因/横展開候補: §3参照

### L861
- 内容: 非決定性偵察はDB再クエリの前に既存分析成果物(outputs/analysis/*.json)を横断確認せよ（cmd_karo_recon2_cmd3824_mechanism_202607101223, subdomain=fe）
- 直接原因: L858と同型（fe→frontend.md、`context/dm-signal-frontend.md:330`に合流済み、同ファイルmarkerがL861まで進んでいることを確認）
- 根本原因/横展開候補: §3参照

### L862
- 内容: cmd_3771 archive payloadとsnapshotの復元正本を区別する（cmd_3826, subdomain=be）
- 直接原因: `subdomain: be` → `context/dm-signal-ops.md`（§6-7アンカー）へルーティング済み・合流済み（`context/dm-signal-ops.md:88`）
- 根本原因/横展開候補: §3参照

### L863
- 内容: LayerTimerは新規Layer追加時にLAYER_ORDER+layer()登録を怠ると壁時計TOTALだけ正しく内訳が誤解を招く（cmd_3831, subdomain=gs）
- 直接原因: L859/L860と同型（gs→ops.md、`context/dm-signal-ops.md:812`に合流済み）
- 根本原因/横展開候補: §3参照

## 3. 根本原因（共通）— gate_lesson_health.shとlesson_write.shの「合流先」認識の乖離

`scripts/lesson_write.sh` は書込み時、lessonの `subdomain` に応じて実際の合流先を振り分ける
（`resolve_lesson_context_route()`）:

| proj_id:subdomain | 合流先 |
|---|---|
| dm-signal:fe | context/dm-signal-frontend.md |
| dm-signal:be | context/dm-signal-ops.md (§6-7) |
| dm-signal:gs | context/dm-signal-ops.md (§33) |
| dm-signal:infra / infra:infra | context/infrastructure.md |
| infra:* | context/infrastructure.md |
| (該当なし) | `config/projects.yaml` の project既定 `context_file`（dm-signalなら context/dm-signal.md） |

一方 `scripts/gates/gate_lesson_health.sh` は `config/projects.yaml` の単一 `context_file`
（dm-signalなら `context/dm-signal.md` のみ）の `last_synced_lesson` マーカーだけを見て
「project全lessonのうち、このマーカーを超えるid」を機械的に未合流とカウントしていた。

L858-L863は全件 `subdomain` が fe/be/gs のいずれかであり、`resolve_lesson_context_route()` の
ルールにより**最初からdm-signal.mdへは合流しない設計**だった。実際にはfrontend.md/ops.mdへ
正しく合流し、両ファイルの `last_synced_lesson` マーカーもそれぞれ最新（frontend.md=L861,
ops.md=L864）まで正しく進んでいた。つまり**教訓の合流自体は成功しており、gate側の
判定ロジックが実態を見落としていた偽陽性（false positive）**というのが根本原因。

書込み側（lesson_write.sh）とチェック側（gate_lesson_health.sh）が同じ「どこへ合流したか」を
別々に判断していた（ルーティング表がlesson_write.sh内にのみinline実装されていた）ことが
構造的な原因であり、これは典型的な二重実装によるドリフトである。

### 横展開候補

1. **他project**: 現時点でsubdomainルーティングを持つのはdm-signal(fe/be/gs)とinfra(infra)のみ。
   今後別projectにsubdomainルーティングを追加した場合、gate側を追随修正しなければ同じ偽陽性が
   再発する構造だった → 本cmdの修正で解消（§5）。
2. **GA-ID増殖（karo指摘、GA-217として同一fingerprintが再発）**: `scripts/gate_improvement_trigger.sh`
   の重複排除ロジック（`dedup_alert_lines_24h`）を調査した結果、別系統の実バグを発見した。
   - `dedup_key_for_alert_line()` は `^(WARN|ALERT):` で始まる行しかdedup対象と認識しない。
   - `gate_lesson_health.sh` の `emit_actionable()` は `ALERT: ...` 行と `action: ...` 行の
     2行1組で出力する。`extract_alert_lines()` はこの2行を1つのalert_lines文字列として拾うが、
     `dedup_alert_lines_24h()` は**1行ずつ独立に**dedup判定する。
   - 結果: 24時間以内の再実行で `ALERT: ...` 行は正しくdedup(skip)されるが、ペアの
     `action: ...` 行は `dedup_key_for_alert_line` が正規表現不一致で判定自体をスキップする
     ため**無条件にkept_lines入りする**。これが `alert_lines_have_file_alert_key()` でも
     キー無しと判定され、`check_idempotent()` の状態文字列比較でも前回状態
     （2行フルテキスト）と一致しないため「状態遷移あり」とみなされ、**新しいGA-IDが
     発行される**（実際に `logs/gate_alerts.yaml` のGA-217エントリは `alert_detail` が
     `"action: context 側へ未合流教訓を反映し、last_synced_lesson を更新せよ。"` のみで、
     本来のALERT行を欠いた不完全な内容だった＝この経路の直接証拠）。
   - 影響範囲: `emit_actionable()` / `echo "action: ..."` パターンを使う全gate
     （`grep -rl "emit_actionable\|echo \"action:" scripts/gates/*.sh` で確認）:
     `gate_cmd_state.sh`, `gate_context_freshness.sh`, `gate_lesson_health.sh`,
     `gate_shogun_memory.sh`, `gate_silent_fallback.sh` の5gate全てが同じ経路でGA-ID増殖しうる。
   - **scope外につき本cmdでは未修正**: `scripts/gate_improvement_trigger.sh` は本taskの
     `scope.allowed`（`scripts/lesson_write.sh`, `scripts/gates`, `tests/unit`, `context`,
     `docs/research/ga216_lesson_context_reflux.md`, dm-signal `tasks/lessons.md`）に含まれない
     （`scripts/gates/` 配下ではなく `scripts/` 直下）。家老へdecision_candidateとして提起する
     （§6）。

## 4. AC2 — 全6件のcontext反映確認

L858-L863は**技術的内容としては既に**それぞれの正しい合流先ファイルへ反映済みだった
（lesson_write.sh書込み時の自動追記が正しく機能していたため）:

| lesson | subdomain | 合流先 | 反映箇所 |
|---|---|---|---|
| L858 | fe | context/dm-signal-frontend.md | L329 |
| L859 | gs | context/dm-signal-ops.md (§33) | L810 |
| L860 | gs | context/dm-signal-ops.md (§33) | L811 |
| L861 | fe | context/dm-signal-frontend.md | L330 |
| L862 | be | context/dm-signal-ops.md (§6-7) | L88 |
| L863 | gs | context/dm-signal-ops.md (§33) | L812 |

`context/dm-signal-frontend.md` の `last_synced_lesson` は既にL861、`context/dm-signal-ops.md`
は既にL864まで進んでいた。`context/dm-signal.md`（gateが見ていた唯一のファイル）は
L858-L863のいずれのsubdomainにも該当しないため、そもそもマーカーを進める対象ではない
（進めると「dm-signal.mdへ合流した」という虚偽の記録になるため、本cmdではdm-signal.mdの
markerは意図的にL857のまま変更していない）。

必要だったのは「反映」ではなく「gate側の判定ロジックをlesson_write.shの実ルーティングと
一致させること」＝§5のgate修正。修正後の実測は§5参照。

## 5. AC3 — 実装した防御層

### 5.1 ルーティング表のSSOT化

`scripts/lesson_write.sh` にinline実装されていた `resolve_lesson_context_route()` を
`scripts/gates/lesson_context_routes.sh`（新規）へ抽出し、`lesson_write.sh` と
`scripts/gates/gate_lesson_health.sh` の両方から `source` する構成に変更。
これにより「書込み側がどこへsyncしたか」と「gateがどこを見るべきか」の認識が
構造的に同一のコードから導出される（二重実装によるドリフトを構造的に防止）。

- `scripts/gates/lesson_context_routes.sh`: ルーティング表本体 + 既知subdomainキー一覧
  (`LESSON_CONTEXT_ROUTE_KNOWN_SUBDOMAINS=(fe be gs infra)`)
- `scripts/lesson_write.sh`: inline定義を削除し `source` に置換。sourceファイル欠落時は
  fail-closed（`exit 1`。他cmdのreview_feedbackにあった「script欠落時fail-openをBLOCKへ」の
  原則に合わせた）
- `scripts/gates/gate_lesson_health.sh`: 同様に `source`。project毎のloop内で
  `LESSON_CONTEXT_ROUTE_KNOWN_SUBDOMAINS` の各subdomainについて
  `resolve_lesson_context_route` を呼び、既定context_fileと異なるファイルへ
  ルーティングされる場合はそのファイル自身の `last_synced_lesson` markerを取得。
  `_compute_lesson_stats()`（lessons.yaml一括awk集計）へ `subdomain:route_marker` のmapを
  渡し、各lessonは**自分のsubdomainが実際にルーティングされたファイルのmarker**と
  比較して未合流判定する（ルーティング対象外のsubdomain/projectは従来通りdefault
  markerと比較 = 完全後方互換）。

### 5.2 実測（修正前→修正後）

```
# 修正前（GA-216検知時と同一）
ALERT: dm-signalのlesson→context未合流6件(total:847,synced:L857,max:L863)

# 修正後
OK: dm-signalのlesson統合状況は健全(未合流0件,total:847,synced:L857)
```

`bash scripts/gates/gate_lesson_health.sh`（全project走査）を修正後に実行し、exit code=0、
dm-signal含め全project ALERTなしを確認（`infra`/`database`/`auto-ops`/`google-classroom`/
`clinic-expense-tracker` 等、ルーティング表を持たない/持つ双方のprojectで既存挙動を維持）。

### 5.3 回帰テスト

- `tests/unit/test_gate_lesson_health.bats`: setup()で新規 `scripts/gates/lesson_context_routes.sh`
  をコピーするよう追加（sourceのfail-closed化により既存テストが揃って壊れるのを防止）。
  既存20 testケース全PASS（回帰なし）。
- `tests/unit/test_lesson_write.bats`: setup_file()で同様に新規ファイルをコピー追加。
  既存43 testケース全PASS。
- `tests/unit/test_lesson_context_routes.bats`（新規）: SSOT関数自体の単体テスト
  （§5.1のルーティング表がdm-signal:fe/be/gs/infra, infra:infra, 該当なしのケースで
  期待どおりのCONTEXT_ROUTE_FILE/ANCHORを返すこと、および
  `LESSON_CONTEXT_ROUTE_KNOWN_SUBDOMAINS` に定義済み全subdomainキーが含まれること）。
- `tests/unit/test_gate_lesson_health_subdomain_routing.bats`（新規）: GA-216/GA-217の
  再現シナリオ（RED→GREEN）。「defaultファイルのmarkerは古いが、subdomain routed
  ファイルのmarkerは新しい」状態を構築し、旧ロジックなら誤ALERTになる状況で
  ALERTが出ないこと・total/synced数値が正しいことを検証。

## 6. 家老への申し送り（decision_candidate）

`scripts/gate_improvement_trigger.sh` のALERT+action 2行ペアのdedup漏れ（§3横展開候補2番）は
本cmdのscope外（`scripts/gates/` ではなく `scripts/` 直下のため）。5gate
（cmd_state/context_freshness/lesson_health/shogun_memory/silent_fallback）全てが
影響を受ける可能性があり、24時間以内の再検知のたびにGA-IDが1つずつ増殖し続ける
（家老inbox・ntfy通知も都度発火）。修正方針案: `dedup_alert_lines_24h()` を
「ALERT行+続くaction/METRIC行」を1ブロックとして扱うよう変更し、ブロック全体を
ALERT行のキーでdedup判定する。別cmdでの対応を推奨。
