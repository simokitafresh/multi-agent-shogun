# Workaround + Quality Monitor パターン分析 2026-04-13

> 作成: 軍師 2026-04-13 idle自走Step 1
> 対象: karo_workarounds直近15件 + quality_monitor inbox直近6件

---

## §1 karo_workarounds 直近15件

| 区分 | 件数 | 比率 |
|------|------|------|
| clean | 10 | 66.7% |
| workaround | 5 | 33.3% |

### Workaround カテゴリ内訳

| category | 件数 | cmd | 根因 |
|----------|------|-----|------|
| verdict_override | 2 | cmd_1835, cmd_1855 | 研究cmd output未commit / 進行中月差異 |
| stale_ac_contamination | 1 | cmd_1858 | deploy_task.sh stale field汚染(LK021) |
| scout_exempt_missing | 1 | cmd_1859 | 将軍cmd起票時設定漏れ |
| premature_shelve | 1 | cmd_1860 | **軍師no-op誤判定**(タイミング競合) |

### 因果分析

**verdict_override(2件)**: AC/gate設計の構造問題。忍者ミスではない。
- cmd_1835: 研究cmdのoutputファイル(outputs/analysis/ CSV)はcommit対象外→commit binary_checkが一律適用→FAIL
- cmd_1855: AC「全期間」が進行中月含む→GS作成日vs本番更新日の差で常にdiff発生

因果鎖: AC/gateテンプレートが研究cmd/進行中月の例外を未考慮→構造的FAIL→家老verdict_override→workaround計上

**stale_ac_contamination(1件)**: deploy_task.shバグ(LK021)。cmd_1861で修正済み(reset_stale_fields)。

**scout_exempt_missing(1件)**: 将軍のcmd起票プロセス。軍師の管轄外。

**premature_shelve(1件)**: **軍師直接起因**。
因果鎖: 軍師がdraftレビュー(23:50)でgrepでno-op判定→小太郎が3分後にcommit(23:53)→家老もcommit後の状態をgrep→循環検証→shelve→実は有効変更あり

---

## §2 Quality Monitor パターン(cmd_1877 block系)

| 忍者 | FAIL件数 | 主パターン |
|------|---------|-----------|
| kagemaru | 3 | assumption_invalidation欠落, YAML parse, 大量必須フィールドMISSING |
| tobisaru | 1 | lessons_useful空リスト |
| hayate | 1 | YAML parse(バッククォート) |

影丸のFAIL頻度が突出(3/5=60%)。特にblock_25で binary_checks/files_modified/purpose_validation/assumption_invalidation全MISSING + lessons_useful reason空×10 = **報告テンプレートのフィールドを全て無視**した形跡。

因果鎖: 影丸がreport_field_set.sh経由の記入プロセスをスキップ→gate BLOCKで自動差戻し→再提出→再FAIL→累積3回。テンプレート自体は存在(deploy_task.shが生成)→読まない/上書き消去のいずれか

---

## §3 改善提案

### GP-183: 研究cmd用commit check免除フラグ
- verdict_override 2件が研究cmdの構造的FAIL
- AC/gateテンプレートにresearch_cmd: true時はcommit binary_checkをスキップする分岐
- defense_level: 4 (gate内分岐でBLOCK回避)

### GP-184: 進行中月除外のAC標準文言
- AC文面「全期間の月次リターン差」→「完了月(最終月除外)の月次リターン差」
- cmd起票テンプレートに標準文言追加
- defense_level: 2 (テンプレート)

### cmd_1860再発防止(軍師プロセス改善)
- draftレビュー時、対象cmdが既にin_progress忍者に配備済みの場合、grep結果に忍者commitが混入する可能性をcaveat付記する
- 既存LG001「git show HEAD検証必須」の適用拡張: draftレビューでもgit show HEAD~Nで変更前状態を確認
- **ただし**: draftレビューは通常配備前に実行。cmd_1860はタイミング例外。頻度低ければ各論パッチ不要(LG023原則)

---

## §4 CS観点チェック
- CS1: karo_workarounds全15件+quality_monitor全6件読了 ✓
- CS2: workaround率33.3%は自システム計測値 ✓
- CS3: cmd_1860のgrep→commit順序を時刻で実コード確認(23:50 vs 23:53) ✓
- CS4: GP-183/184として行動変換 ✓
- CS5: 影丸の3回FAIL根因(テンプレート無視 vs 道具バグ)は未検証。LG014(道具を疑え)適用要 ✓
- CS6: 各因果鎖記載済み ✓
