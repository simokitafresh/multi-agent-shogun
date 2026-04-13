# Codex CLI commit_missing パターン分析

軍師idle自走 Step 1→5。2026-04-13。

## 発見

karo_workarounds直近5件中4件が `commit_missing`。全てCodex CLI(hayate/saizo)。

| cmd | ninja | type | root_cause |
|-----|-------|------|------------|
| cmd_1890 | hayate | codex | 影丸auto-commitに巻き込まれた |
| cmd_1891 | hayate | codex | Codex commit未了→家老代行 |
| cmd_1892 | saizo | codex | Codex commit未了→共有WT dirty |
| cmd_karo_gp110 | hayate | codex | Codex commit未了+auto-commit巻込み |

Claude型忍者(kagemaru/hanzo/kotaro/tobisaru): commit_missing = 0件。

## 因果鎖

```
Codex CLIのgit commit実行能力に制限あり(根因候補)
→ 共有WTでdirty state(他エージェントの未commit変更)が存在
→ Codex CLIがcommitを完了できない or 部分的commitになる
→ 忍者がcommit=no報告(正直)
→ 家老が代行commit(workaround)
→ 家老CTX消費+commit帰属問題
```

## LG014適用

「忍者/家老ミスに見える問題はインフラ真因を疑え。道具を疑え」
commit_missingが同一categoryで4件 → 道具(Codex CLI)のcommit実行能力を疑う。

## 進展 (2026-04-13T23:40)

cmd_1893でhayateがcommit成功(ad04f319)。報告にcommit=yes。
家老inbox: 「Codex rules修正有効!」と記載。
→ Codex CLIのcommit制限は設定(rules)で改善可能だった可能性。
→ 次のWA統計でcommit_missing減少を計測すべき。

## 要検証

1. ~~Codex CLIはgit commitコマンドを実行できるか？~~ → cmd_1893でcommit成功。rules修正で改善
2. 共有WTのdirty stateがCodex commit失敗のトリガーか？(dirty state時の再現テスト未実施)
3. Codex型忍者のcommit成功率を今後のWA統計で追跡(commit_missing率の推移)
