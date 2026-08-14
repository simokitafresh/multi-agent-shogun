# E型統一原理の陽性対照(lens型)検査設計

- 起票: 家老idle依頼 msg_20260725_215610（将軍下知21:50の(3)）
- 対象: 設計書v2.6§2末尾で正本化したE型統一原理
- 作成: 2026-07-25 軍師
- origin: `[[E型統一原理]] -> [[lens型が支配的]] -> [[陽性対照による完成条件]]`

## §1 結論

検知器の完成条件を「実体との突合」から **「陽性対照の検出確認」** へ置き換える。
搭載先は **新規機構を作らず** `scripts/gates/gate_report_format_main.py` の
LG051ブロック（L1090-1132）を拡張する。追加するのは証跡フィールドの必須トークン1つ。

## §2 なぜ「実体との突合」では足りないか

本日のE型6例を機序で割ると次のようになる。

| # | 事例 | 機序 |
|---|---|---|
| 1 | 家老WA検知器（workaround未参照） | lens |
| 2 | GA-PUSH1 index誤判定（HEAD vs worktree） | lens |
| 3 | 半蔵の当初仮説（正本はtask YAML） | lens |
| 4 | 軍師のgrep走査（前置形式7件を落とす） | lens |
| 5 | 家老の教訓検知器（created_atのみ参照） | lens |
| 6 | CIキャッシュ（1時間半前のfailure保持） | staleness |

**staleness 1件に対し lens 5件。** lens型は実体そのものを読んでいる。
軍師は本番 `logs/gate_metrics.log` を、家老は `logs/karo_workarounds.yaml` を直読していた。
∴「判定に使う値は実体か写しか」を問うと常にYESが返り、検査が空回りする。

陽性対照は「何を見ているか」ではなく **「欲しいものが取れるか」** を問うため、
書式仮定にも古い写しにも等しく効く。

## §3 最小形式

```
positive_control: <既知の陽性サンプル1件の識別子> -> detected
```

3要件のみ。

1. **サンプルは実データから採る**（合成しない）。identifier は行番号・event_id・cmd_id 等。
2. **検知器を実際に走らせて検出されたことを示す**（コマンドと出力）。
3. **N=1で足りる**。網羅は求めない。0→1の差が本質であり、1→Nは逓減する。

## §4 搭載先（grep一次確認済み）

| 候補 | 実装 | 判定 |
|---|---|---|
| `gate_report_format_main.py` L1090-1132（LG051） | gate/hook/dispatcher変更時に `causal_verification.evidence` へ `non-test caller count: N` を強制 | **採用** |
| `gunshi_log_append.sh` | `operational_simulation` に command/expected/actual/result を強制（L173-177） | **併用採用**（軍師の走査を捕捉） |
| `cmd_save.sh` Check群 | cmd起票時。検知器の実装前なので陽性対照を出せない | 不採用 |

### 4.1 LG051への相乗り（主）

LG051は既に次を満たす。

- **スコープ述語が同一**: `_caller_scope`（L1106-）が gate/hook/dispatcher 変更を判定。
  才蔵のB16是正（L1098-1105）でトークン境界一致となり、真対象124件中12件の漏れが解消済み。
- **証跡フィールドが同一**: `causal_verification.evidence`
- **強制機構が同一**: `errors.append` + `hints.append`

∴ 同ブロック内に必須トークンを1つ足すだけでよい。新しいgate・新しいフィールド・
新しい状態管理はいずれも不要（LG032/LG023準拠）。

```
LG051-PC: 検知器の新設/改修には陽性対照が必須
FIX: causal_verification.evidence へ
     `positive control: <実データ由来の識別子> -> detected` と
     実際に走らせたコマンドおよびその出力を記録せよ。
     検出できない場合、その検知器は完成していない。
```

### 4.2 `gunshi_log_append.sh` への相乗り（副）

軍師の走査誤り（例4）は報告ではなくレビュー中のad-hoc grepで生じたため、
gate_report_format では捕捉できない。`operational_simulation` は既に
command/expected/actual/result を必須としているので、
**`actual` が「不在・0件」を主張する場合に限り陽性対照を必須**とする。

不在の主張は最も危険な結論である。存在を1件示すのは容易だが、
不在は走査の欠陥と区別がつかない。

## §5 (b) lens型5例への適用判定

| # | 事例 | 検出可否 | 根拠 |
|---|---|---|---|
| 1 | 家老WA検知器 | **yes** | `gate_karo_startup.sh` は gates/ 配下でLG051スコープ内。真のWA1件（`cmd_karo_speed_completion_pipeline_20260725`/疾風）を投入すれば計数に入らないことが即座に判明した |
| 2 | GA-PUSH1 index誤判定 | **yes** | hook配下でスコープ内。worktree側の既知1件を投入すればHEAD参照の誤りが露見した |
| 4 | 軍師のgrep走査 | **yes（§4.2の副搭載で）** | `actual` が「複合行は1件のみ」という実質的な不在主張だった。複合行を1件目視で選び走査に通せば8件を1件と誤認しなかった |
| 5 | 家老の教訓検知器 | **yes** | `gate_lesson_health.sh` 系でスコープ内。merge登録された教訓1件を投入すれば `created_at` のみ参照の欠陥が露見した |
| 3 | 半蔵の当初仮説 | **no** | 検知器を作っていない。「正本はtask YAML側」という前提の取り違えであり、走らせる対象そのものが存在しない |

**4/5が検出可能。** 検出できない例3の理由は明確で、
陽性対照は「作った検知器を試す」手続きであり、**検知器を作らない推論には適用点がない**。
例3の型（正本の所在の取り違え）には別の対処が要る——
これは本日の引用誤り6件と同じ「二次情報を一次確認せずに転記する」型であり、
才蔵B16のAC1が示した **「前提の数値を忍者自身が実測して示す」ACの型** が対応する。

## §6 本日の引用誤りへの横展開

陽性対照はcmd起票側にも適用できる。本日の引用誤り6件はすべて
「引用値を1件、実際に台帳から引けることを確認する」で検出できた。

| 引用 | 実測 | 陽性対照で検出 |
|---|---|---|
| ci_readiness 108件 | 106件 | yes |
| FAIL_VERDICT 6830行 | 6949行 | yes |
| 追加コスト 数百ms | 1844ms | yes |
| deploy 141.6s（典型） | median 1220ms／141.6sは1/494 | yes |
| queue 125,527ファイル | 55,845 | yes |
| `three_layer_ruling_overhead` | 0件（近似名が13件） | yes |
| `publish` 系check_id | 0件 | yes |

加えて重複配備1件（半蔵B21）も、
**「穴リストの各項目が未解決であることを実体で1件確認してから配備する」**
という穴リスト版の陽性対照で防げた。
家老の掲示板 `blt_20260725_220450` は同一投稿の(2)で才蔵の完了を列挙しながら
(3)でB21を配備しており、突合が行われていれば矛盾は投稿前に露見した。

## §7 導入手順（提案）

1. `gate_report_format_main.py` LG051ブロックへ `positive control:` トークン必須を追加
2. `gunshi_log_append.sh` の `operational_simulation` に、
   `actual` が不在主張の場合の陽性対照必須を追加
3. 既存fixtureを拡張（新規test fileを作らない）
4. 導入後、次の検知器改修cmdで発火状況を計測し偽陽性率を報告

いずれも既存の強制点・既存フィールド・既存fixtureの拡張であり、
新規機構は作らない。
