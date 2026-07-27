# 忍者auto clear — 恒久是正 設計書 (2026-07-27)【T1-T3 CLOSED / T4のみOPEN(実装中) — §0状態ブロック参照】

- 起案: 軍師(gunshi)
- 殿下問: 2026-07-27 11:16「auto clearの設計書はできたか？」
- 前提資料: 調査書 `docs/research/gunshi_auto_clear_blocked_investigation_20260727.md` (gist e6e289f3・家老LGTM済)
- origin: `[[殿下問_auto_clear_20260727]] -> [[CLEAR-BLOCKED 1136件]] -> [[本設計書]]`

## §0 状態ブロック(2026-07-27 16:35 将軍再構築 — どこまでクローズか)

| 構成要素 | 状態 | 一次証跡 |
|---|---|---|
| **T1 継続検知カウンタ** | ✅ **CLOSED**(実装+稼働実証) | commit `bc151ae6e`(影丸 14:48)。ninja_monitor.sh:868-908 |
| **T2 閾値超過→家老inbox通知** | ✅ **CLOSED**(実装+**発火実証**) | 生ログ `[15:24:08] CLEAR-BLOCKED-NOTIFY: tobisaru count=3` / `[15:29:49] 同 hayate` — 実封鎖2件を検知・通知した |
| **T3 startup gate現況表示** | ✅ **CLOSED**(実装) | gate_karo_startup.sh:2809 + gate_gunshi_startup.sh:1101 + 共通lib clear_blocked_summary.sh + bats |
| **封鎖の即時解消(運用処置)** | ✅ **解消が持続** | 15:49 unstage後、15:50以降のCLEAR-BLOCKED=0件・staged index=0件(16:35将軍実測: `grep+awk`と`git diff --cached`)。15:52:48 飛猿CODEX-RESPAWN実行=auto clear復旧の挙動証拠 |
| **D4 stage残置の発生源(自傷ループ仮説)** | ⚠ **OPEN — 最有力仮説**(確定はT4ログ待ち) | §10。コード現物(全2枝でstderr破棄・rollback 0)+同族4pathの2回再発。生成瞬間・失敗rcは未観測ゆえ「確定」とは言わない(家老レビューblt_155443) |
| **T4 失敗経路の自己回収+観測可能化** | ⚠ **OPEN — 実装中(1回目failed)** | 殿裁可15:59で配備。半蔵task `cmd_karo_hotfix_auto_commit_t4v2`(AC1-5にOID同一内容境界まで含む)が16:10 failed(報告YAML未提出)。家老が検分→再配備の段。**本設計書で唯一の未クローズ実装** |

**∴ 総括: 設計書の本来目的(skipが誰にも届かない38時間沈黙の根絶)=T1-T3でCLOSED。封鎖も解消が持続。残るのは発生源の恒久是正T4のみ(OPEN)。T4完走+D4確定/棄却の報告をもって本設計書は全クローズとなる。**

## §1 設計の対象を1行で

**「auto-commit が保全のためskipしたとき、それを誰かが必ず受け取る構造にする。」**

現状の欠陥は「skipすること」ではない。**skipが1,136件・38時間、誰にも届かなかったこと**である。

## §2 ASIS — 現行設計と欠陥

### 2.1 現行フロー (`scripts/ninja_monitor.sh:1443-1452`)

```
idle検知
 → git status --porcelain -uno -- scripts/ instructions/ config/ context/ CLAUDE.md
 → 変更あり: auto_commit_before_clear()
     ├─ 成功 → /clear 実行
     └─ 失敗(既存stageあり) → log "CLEAR-BLOCKED: …" + return 1   ★ここで終わる
```

### 2.2 欠陥の分解(3層)

| # | 欠陥 | 現状 | 実測 |
|---|------|------|------|
| D1 | **通知先が無い** | logへ書くのみ。inbox・掲示板・startup gateのいずれにも出ない | 1,136件が誰にも届かず |
| D2 | **状態が積算されない** | 毎サイクル同じ行を書くだけで「何回連続で失敗しているか」を持たない | kotaro 88回・同一原因の反復を誰も検知できず |
| D3 | **復旧手順が示されない** | ログ文言は事象のみ。誰が何をすれば解けるか書かれていない | 軍師が復旧を試み2度BLOCK(GA-231c / 部分stage) |

**∴ D1が主因。D2/D3は検知後の実効性を左右する。**

### 2.3 ★当初設計の欠陥(2026-07-27 11:21 自己訂正)

**初版のT1は「K回連続」を検知条件としたが、実データでは連続していない。**

出力行(生):
```
kotaro CLEAR-BLOCKED件数: 12
隣接間隔 中央値: 255.0 秒 / 最小: 47.0 / 最大: 402.0
20-40秒以内(=連続サイクル)の割合: 0.0 %
```

**POLL_INTERVAL=20秒に対し中央値255秒。∴連続サイクルは0%であり「K回連続」は永久に成立しない。初版設計は1度も発火しない。**

### 2.4 ★件数集計の訂正(2026-07-27 11:21)

出力行(生):
```
種類別          → 98 auto-commit / 82 done
auto-commit起因 → 25 kagemaru / 18 saizo / 16 hanzo / 15 hayate / 12 tobisaru / 12 kotaro
```

**1件の定義**: auto-commit起因のログ1行(初版は全CLEAR-BLOCKED行を数えていた)。

**∴初版の「kotaro 88件」は誤り。実際は kotaro 12件・最多は kagemaru 25件。** 本件は4規律(3)違反であり、**軍師が定義せず数え、家老が同じ定義で検算一致したため双方が気づかなかった**。**「検算で一致」は「正しい」を意味しない。**


### 2.5 ★全数再集計と6忍者全員の隣接間隔(将軍実測 2026-07-27 13:56 — §7未計測項目の解消)

集計コマンド: python3で `logs/ninja_monitor.log`(+ローテート.1〜.3)の`CLEAR-BLOCKED`行を正規表現parseし種類別Counter+agent別隣接間隔を算出。

出力行(生):
```
現行ログ総数: 195 / 種類別: {'auto-commit': 195}
log.1: 総数=234 {'auto-commit': 233, 'not idle': 1}
log.2: 総数=288 {'auto-commit': 287, 'not idle': 1}
log.3: 総数=336 {'auto-commit': 335, 'not idle': 1}
== agent別 auto-commit起因(現行ログ): 件数/隣接間隔中央値s/最小/最大
hanzo 29 285.0 / hayate 22 409.0 / kagemaru 50 240.0 / kotaro 28 300.0 / saizo 39 191.5 / tobisaru 27 309.0
最小値レンジ=47〜100s、最大値はidle空白を含み2469〜26808s
```

1件の定義= 正規表現`\[ts\] CLEAR-BLOCKED: agent reason`でparseできたログ1行(grep -c素朴計数277はAUTO-CLEAR-BLOCKED等の別形式を含むため採らない)。網羅範囲=現行+ローテート3本の全数1,053件。

**∴確定事実**: (1)ローテート含む全数の**99.6%(1,050/1,053)がauto-commit起因** — 調査書の推定を全数で確定。(2)6忍者全員の隣接間隔中央値=191.5〜409s。POLL_INTERVAL=20s(ninja_monitor.sh:185実測)に対し10〜20倍であり、**「K回連続サイクル」設計が不成立という§2.3の結論を6名全員で追認**。(3)T1の窓は「直近M=30分にN≥3件」が実測に整合(中央値4〜5分間隔なら持続的封鎖時に30分で6件前後入る。一時的競合の単発は拾わない)。最終値は実装ACで確定。

## §3 TOBE — 原理と設計

### 3.1 原理

**「既に強制されている行動に乗せる」(LG032)。新規gate・新規hook・新規daemonを作らない。**

指揮官は毎起動時に startup gate を必ず読む。忍者は毎ターン inbox を必ず読む。**この2つの既存経路だけで D1-D3 は解ける。**

### 3.2 設計(3点。いずれも既存ファイルへの追加)

#### T1: 未解決状態の継続検知(D2の解消)

**★2026-07-27 11:21 修正。当初の「K回連続」設計は実データで機能しないことが判明した(§2.3参照)。**

- **対象**: `scripts/ninja_monitor.sh` の `auto_commit_before_clear` 失敗経路
- **設計**: agent別に「**直近M分間のCLEAR-BLOCKED件数**」を `/tmp` 上へ保持。成功時に0へリセット
- **契約**: カウンタはログではなく**状態**である。プロセス再起動で消えてよい
- **理由**: 単発のskipは正常な保全動作である。**同一原因が一定時間解けないことが異常**である
- **★M/Nの決め方**: 実装AC1で実測から確定させる。参考実測(2026-07-27 kotaro)=40分間に12件・隣接間隔の中央値255秒。**軍師は値を決め打ちしない**

#### T2: 閾値超過時の家老通知(D1の解消・主軸)

- **対象**: `scripts/ninja_monitor.sh`(検知側) → 既存の `scripts/inbox_write.sh`(通知経路)
- **設計**: T1のカウンタが**閾値K回**に達した時点で家老へ1回だけ inbox 通知。以後カウンタが0へ戻るまで再送しない
- **type**: `infra_anomaly`(既存type。忍者宛の指示ではないため家老の判断を起こす型を使う)
- **本文契約**: 4規律に従い「集計コマンド / 出力行 / 1件の定義 / 網羅範囲」を含める。**加えて復旧手順を明記する**(D3の解消)
- **閾値Kの決め方**: 本設計では**K=3**を提案する。根拠 = ninja_monitorのサイクル間隔から、3回連続は「一時的なstage競合」では説明できない長さになる。★ただしサイクル間隔の実測値を軍師は取っていない。**実装時にACで実測させ、Kを数値で確定させること**

#### T3: startup gate への現況表示(D1の補完)

- **対象**: `scripts/gates/gate_karo_startup.sh` および `scripts/gates/gate_gunshi_startup.sh`
- **設計**: 既存の項目群へ1行追加。「CLEAR-BLOCKED 直近N件 / 対象agent」を表示。0件なら無表示
- **理由**: T2は発生時点の通知であり、**/clear後に着任した指揮官には届かない**。startup gate は「今どうなっているか」を伝える経路であり両者は補完関係にある

### 3.3 3点の関係

```
T1(状態) ──> T2(発生時に家老へ届く) ──> 家老が対処
   └────────> T3(起動時に指揮官が気づく) ──> 交代後も引き継がれる
```

**T1単独では意味がない。T2/T3のいずれか一方だけでも穴が残る**(T2のみ=/clear跨ぎで消える / T3のみ=起動まで気づけない)。

## §4 不変更契約(壊してはならないもの)

| 対象 | 契約 |
|------|------|
| `auto_commit_before_clear` の**skip判断そのもの** | **変更しない。** 他者のstageを巻き込まない設計は正しい(GA-231c と同一思想) |
| `return 1` による /clear 中止 | **変更しない。** commitできない状態でclearすると未commit変更が失われうる |
| 既存の CLEAR-BLOCKED ログ出力 | **残す。** 通知を追加するのであってログを置き換えない |

**★本設計は「止まる仕組み」を一切緩めない。「止まったことが伝わる仕組み」だけを足す。**

## §5 実装ACの骨子(起票時に使う)

1. **前提検証**: `ninja_monitor.sh:1443-1452` の現況を行番号付きで確認。サイクル間隔を実測しKの根拠を数値で示せ
2. **T1実装**: 連続カウンタ。成功時リセットを含む
3. **T2実装**: 閾値到達で `inbox_write.sh` を1回呼ぶ。**本文に4規律+復旧手順を含める**。再送抑止を実装せよ
4. **T3実装**: 家老・軍師の startup gate へ1行追加。0件時は無表示
5. **境界fixture(最低5件)**:
   - (a) skip 1回 → 通知なし
   - (b) skip K回連続 → 通知1件
   - (c) skip K+1回目 → **追加通知なし**(再送抑止)
   - (d) 成功が挟まる → カウンタ0へリセット、次のK回で再び通知
   - (e) **stageが無い通常時 → 一切発火しない**(既存運用の非破壊)
6. **不変更検証**: skip判断・return 1・既存ログの3点が変わっていないことを diff で示せ
7. **追加コスト実測**: 変更前後で ninja_monitor の1サイクル所要を各3回計測し中央値比較(殿裁定07-21「削るな、速くしろ」)

## §6 本設計が扱わないもの(スコープ外) — ★13:58 現況更新

- **staged残置の解消**: ✅ 13:58案A実行で一旦解消 → **★15:45再発を確認**(同族の自動生成4件が再stage)→ 15:49に再度unstage実行(§10参照)。**単発処置では再演することが2回目の実測で確定** — 恒久是正はT4(§10)
- **stageが発生する原因の除去**: ✅ **特定完了(§10 D4)**。stage主体=ninja_monitor.sh自身のbatch context auto-commit失敗経路(:853-856)。「才蔵報告待ち」は不要となった(コード現物+再発実測で確定)
- **部分stage問題**: unstage実行により消滅(indexが空になった時点で--patch対話は不要になった)

## §7 軍師が確認していないこと — ★13:56 将軍実測で全項目解消

- ~~サイクル間隔未実測~~ → ✅ POLL_INTERVAL=20s(ninja_monitor.sh:185)+6忍者全員の隣接間隔実測済み(§2.5)。K=3の代わりに**「M=30分にN≥3件」窓を推奨**(最終値は実装AC1で確定)
- ~~/tmpカウンタのWSL2安定性~~ → ✅ fail-safe論証で決着(将軍指摘11:19: 消えても0から再カウント=通知遅延のみ。損失・誤BLOCKなし)。プロセス跨ぎはファイルベースで担保
- ~~T3起動時間影響~~ → ✅ 見積り: T3=logへのgrep 1回(現行195行・ローテート除く)であり、gate_karo_startupの既存59check計16.2s(本日TIMING実測)に対しms単位の加算。実装後にTIMING行で実測確認
- ~~他5名の隣接間隔・ローテート内訳~~ → ✅ §2.5で全数計測済み(99.6%がauto-commit起因)

## §9 実装状況(将軍再検分 2026-07-27 15:50 — 全項目を実装済み+稼働実証へ更新)

| 項目 | 状態 | 証跡 |
|---|---|---|
| T1(継続検知カウンタ) | ✅ 実装済み+稼働 | commit `bc151ae6e`(影丸 cmd_karo_hotfix_auto_clear_recovery_20260727、14:48)。ninja_monitor.sh:868-869(M=1800s/N=3、§2.5実測を根拠に確定)+`_record_clear_blocked_and_maybe_notify`:872 |
| T2(閾値超過→家老inbox通知) | ✅ 実装済み+**発火実証** | ninja_monitor.sh:885-896(4規律+復旧手順+偽陽性弁別を本文内蔵、再送抑止`CLEAR_BLOCKED_NOTIFIED`)。**稼働実証(生ログ)**: `[15:24:08] CLEAR-BLOCKED-NOTIFY: tobisaru count=3 window_sec=1800 overlap_path=context/infrastructure.md` / `[15:29:49] 同 hayate count=3` — 実封鎖を2件検知し家老へ通知した |
| T3(startup gate現況1行) | ✅ 実装済み | gate_karo_startup.sh:2809-2814 + gate_gunshi_startup.sh:1101-1106 + 共通lib `scripts/gates/lib/clear_blocked_summary.sh`(48行)。0件時無表示 |
| 境界fixture | ✅ | tests/unit/test_ninja_monitor_clear_blocked_notify.bats(50行、§5(a)-(e)対応) |
| 本番到達 | ✅ 挙動証跡で確認 | 15:24/15:29のNOTIFY発火=新コードが稼働中プロセスで実行されている一次証拠(コード存在ではなく挙動で確認。LS-A09(34)) |

## §10 稼働後に発見された残欠陥D4と是正T4(将軍一次調査 2026-07-27 15:50)

**T1-T3は「止まったことが伝わる」を達成した。しかし止まる原因そのものが自家製と判明した。**

### D4: auto-commitの失敗経路がstage残置を作る(自傷ループ — ★家老レビューblt_155443反映で「確定」から「最有力仮説」へ降格・対象を全2枝へ拡張)

`ninja_monitor.sh:853-856`(現物):
```bash
printf '%s\n' "$context_paths" | xargs -d '\n' git add -- 2>/dev/null || true
if printf '%s\n' "$context_paths" | xargs -d '\n' git commit -m "chore: batch context auto-commit before /clear ($agent_name)" -- 2>/dev/null; then
    write_auto_commit_timestamp "$context_last_file"
fi
# ← commit失敗時: git addしたstageを戻さない。失敗理由も2>/dev/nullで捨てる
```

- **★対象は2枝(家老実測)**: `auto_commit_before_clear`内のadd→commit枝は**regular枝(add :836/:840, commit :843)とcontext枝(add :853, commit :854)の2本**あり、**両方**がstderr破棄・rollback 0(家老rg実測)。§10初版のcontext枝1本だけの是正では半分しか塞がらない — **是正は全枝共通helperへの統合**とする
- **機序(最有力仮説)**: `git add`成功→`git commit`失敗(pre-commit hook・lock競合等)→**staged残置**→以後、全agentの`auto_commit_before_clear`が「pre-existing staged files」でskip→**全6忍者のauto clearが封鎖**
- **★確度の訂正(家老指摘3)**: 現行実装はstderrを捨てており、15:45 stageの生成瞬間・失敗rcは観測されていない。∴「コード現物で確定」は論理飛躍で、正しくは**残置4path=context枝のstage対象と一致+残置を作りうるコードの実在による最有力仮説**。確定はT4のFAILログ実装後の再発観測で行う
- **状況証拠(15:24-15:45生ログ)**: 13:58の案A unstage後もstagedが再発生(自動生成4件)し6忍者全員が反復CLEAR-BLOCKED。T2通知のoverlap_path=context/infrastructure.mdがcontext枝のstage対象と一致
- **暫定処置(15:49将軍実行・可逆)**: 該当4pathを`git restore --staged`(案A先例)。実測: `git diff --cached --stat`=0行(index空)・worktree ` M`4件保持=非破壊

### T4: 失敗経路のstage自己回収+失敗理由の観測可能化(★家老レビューblt_155443反映 v2)

- **設計**: (1)regular/context**全2枝**のadd→commitを**共通helper関数へ統合**し、そこで失敗処理を一元実装(枝別パッチ禁止=原理1行>各論パッチ) (2)commit失敗時のstderrを捨てず1行ログへ記録(`AUTO-COMMIT-FAIL: branch=<regular|context> rc=<n> reason=...`) — **D4仮説の確定/棄却はこのログで行う** (3)stage自己回収は**自己所有をOIDで証明できたpathのみ**: add前に`git diff --cached --name-only`のsnapshotに加え、add直後に`git ls-files --cached -s <path>`でstage済みblob OIDを記録し、commit失敗時のcleanup直前に**同一pathの現在stage OIDが自分の記録と一致する場合のみ**`git restore --staged`(★TOCTOU対策: snapshot後に他者が同一pathをstageし直した場合はOID不一致となり触らない=GA-231c維持)。OID照合が実装できない場合はcleanup自体を断念しログのみとする(fail-safe側へ倒す) (4)T1カウンタとは独立(T1は検知網として残す=多層防御)
- **不変更契約への追加**: 他者の既存stagedには一切触れない。回収対象は「同一関数実行内で自分がaddし、かつcleanup時点でOIDが自分のadd結果と一致する」pathに限定
- **境界fixture(最低7件)**: (f)commit成功→stage回収発動なし (g)context枝commit失敗→自分がaddしたpathのみunstage・既存stagedは不変 (h)失敗理由(branch/rc)がログへ1行記録される (i)pre-existing stagedありでadd自体をskipする既存挙動の非破壊 (j)**regular枝commit失敗→同様に回収**(家老指摘1) (k)**snapshot後に他者が同一pathを再stage→OID不一致で他者stage不変**(家老指摘2 TOCTOU) (l)**add部分失敗・commit hookが追加stageを作った場合の帰属**(自分のOID記録に無いstageは触らない)(家老指摘2)
- **実装配備の前提**: 本v2を家老が再レビューしてから配備(blt_155443「反映まで実装配備停止」に従う) → **殿裁可(15:59)で配備実行済み。家老検分は実装レビューへ併合**
- **★OID照合の限界(半蔵task AC3が先鋭化・軍師知見と整合)**: git OIDは**内容hash**であり操作者を含まない(軍師確定知見 knowledge:9511d46a)。∴他者が**同一内容**を再stageした場合はOIDが一致し自己所有を証明できない。実装契約: この境界をfixtureで再現し、OID一致だけでGA-231cを証明できないケースは**回収せずBLOCK報告**(fail-safe側へ倒す)
- **実装状況(16:35)**: 半蔵へ配備(task `cmd_karo_hotfix_auto_commit_t4v2`、AC1=共通helper統合/AC2=AUTO-COMMIT-FAILログ/AC3=OID自己所有回収+同一内容境界/AC4=fixture f-l+境界/AC5=GA-231c・T1-T3独立検証)。**1回目はfailed(16:10、報告YAML未提出)** — 家老が実装FAILか終端契約かを検分し再配備する段

## §8 因果リンク

- → [[gunshi_auto_clear_blocked_investigation_20260727]] 本設計の前提となる調査書
- → [[LG032]] 新しい強制の仕組みを作るな。既に強制されている行動に乗せよ
- → [[GA-231c]] 指揮官のcommit直書き禁止(同じ「他者stage保護」思想)
- → [[実装ありだが効いていない]] 本件の型=検知は出力されるが消費者が不在
