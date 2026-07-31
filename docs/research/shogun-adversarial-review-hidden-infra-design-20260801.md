# 将軍敵対レビュー — hidden-infrastructure-gate-hook-remediation-design v3.4 (固定commit 50575c8ae)

| 項目 | 値 |
|---|---|
| reviewer | shogun (Claude Fable 5, 殿直接下知 2026-08-01 00:07) |
| 対象SHA256 | 323ef710a612c4af4fd79c73d9aeab479254ed577f185a7365357bec732130e6 (git show一致を実測) |
| verdict | **REQUEST_CHANGES** (穴2件+軽微1件。1穴でもREQUEST_CHANGESの契約に従う) |

## 一次確認済みの事実 (全て本レビューで実測)

- 引用commit 7件(9e5f8a382/ce54074be/f37a4365a/2e1090bb7/4c89d38ca/6f4e4b77b/55b3df6d4)は全て実在。集計コマンド=`git log --oneline -1 <sha>`、MISSING 0件。
- foundation成果物(durable_state.py/.sh/test_durable_state.bats/canonical manifest/wave0 receipts)は実在。To-Be成果物(runtime_support_matrix.yaml/runtime_matrix_generate.py/runtime_compatibility_restore.sh)は未存在=設計書の記載通り未実装。
- `.claude/settings.json` blob=be93a9ff…・SHA256=4b1945c8…は現物一致。event 6種/top-level handler 12(Stop5+UserPromptSubmit3含む)も現物一致(python jsonで計数)。
- 実pane編成: karo〜tobisaru全8paneが`@agent_cli=codex`、将軍のみClaude(Fable 5)。active比率はCodex優勢だが設計書はD07/AC21でClaude primaryを固定しており、殿裁定2026-07-31 23:55と整合 [MEM: memory_db ts=2026-08-01 "主編成はClaude…Codexはactive比率でClaude primaryを上書きしない" knowledge:e2dd10df]。

## 殿の5問いへの判定

1. **active Codex比率によるClaude primary上書き**: なし。support_matrix Claude row必須+schema BLOCK(§0.1)、D07、AC21で三重に封じている。PASS。
2. **Claude native hookのdaemon/gate化悪化**: 契約上は不置換(§0.0/§0.4/latency budget)だが、**穴F2**(下記)でWave 4Aの文言がClaude hook合成を許容し得る。
3. **tuple差無視のCodex局所最適**: matrix 3層分離+valid constraint+fault tuple展開で概ね封じている。ただし**軽微F3**。
4. **旧系成立因果の固定証跡**: §0.0の証跡ポインタ・commit・blob hashは実在確認済み。ただし**穴F1**でAs-Is実測値が不正確。
5. **NO-CHANGE条項**: §0.0規則4、D08、AC24に実在。PASS。

## Findings

### F1 (穴・REQUEST_CHANGES根拠): type/binary mismatch「2件」は過少計数 — resolver適用で3件目(gunshi)が現存
- 設計書§0.2は「As-Isでは`cli_profiles.yaml`にtype: codexとClaude起動binaryが混在するrowが**2件**」とし、fixtureを`type_binary_mismatch=2`へ固定している。
- 実測: cli_profiles.yaml内の直接混在はsaizo/tobisaruの2件で数字自体は正しい。**しかし設計書自身のresolver precedence(§0.2手順1-2)を適用すると3件目が出る**: `config/settings.yaml` gunshi=`type: codex`+`launch_cmd:`空 → 欠落fieldを`cli_profiles.yaml defaults.agents.gunshi`から補うと`type: claude`+claude binary(`~/bin/claude`)が充当され、resolved tupleはtype=codex×binary=claudeの矛盾になる。集計コマンド=`grep -n -A4 gunshi: config/cli_profiles.yaml`(L22-25)+`sed -n settings.yaml gunshi節`。
- 影響: fixtureが「2件検出でPASS→正本修正後0」を要求するため、**cross-file fallback由来のmismatchを検出しないgeneratorが2/2で緑になり、gunshi矛盾が恒久すり抜ける**。是正=mismatch定義を「resolved tuple単位」(単一file内混在に限定しない)と明記し、期待値をfixture固定でなくresolved全agent走査のN/N検証にせよ。
- origin: `[[§0.2 resolver precedence]] -> [[cross-file fallback未計数]] -> [[type_binary_mismatch過少fixture]]`

### F2 (穴): Wave 4A「同一event内の順序依存処理はCLIごとに単一adapterへ合成」がClaude現行Stop 5-handler鎖と衝突し得る
- §5.8の合成規則はCLI限定修飾がなくClaudeにも適用され得る。Claude現行はStop 5 handler+UserPromptSubmit 3 handlerの**順序付き多段構成が本番稼働中**であり、単一adapter化は`.claude/settings.json`の構造変更=Claude主系の変更。§0.4非退行契約・AC21で事後検出は可能だが、**そもそも変更を発生させない側(§0.0規則4のNO-CHANGE)との優先関係が未記載**。
- 是正: Wave 4Aへ1行追加 —「Claude現行multi-handler構成は合成対象外(既にreachable owner 1/actionを満たす)。合成はhook欠落CLIの代替owner割当てに限定する」。これで質問(2)の懸念経路が構造的に閉じる。
- origin: `[[§5.8 adapter合成]] -> [[Claude Stop5鎖=変更対象化リスク]] -> [[NO-CHANGE優先の明文欠落]]`

### F3 (軽微): model例示が現配置と乖離
- §0.1のmodel行は「Claude Opus/Sonnet系、GPT系」を例示するが、現settings.yamlのshogunは`claude-fable-5-low`(本日切替)。契約文言は「configured model_name全量」なので実害はないが、support_matrix初期投入時にFable 5 rowの取り漏れを誘う。例示を「configured実値(claude-fable-5-low等)」へ更新推奨。

## 総評
設計の骨格(4根因収束・durable primitive・Claude primary非退行・NO-CHANGE条項・因果保存)は殿裁定と整合し、引用証跡は全て実在した。忖度なしの結論としてF1は**実装前に直さねばgeneratorのfixtureが誤った正解を焼き込む**類の穴であり、REQUEST_CHANGESとする。

---

# RC2 (v3.5, 固定commit 6da5386792) 再敵対レビュー — 2026-08-01 00:16

| 項目 | 値 |
|---|---|
| 対象SHA256 | 06478b2bc30bebb9431ab3586008f4ef1b07dd06769afc2efdc84cfdeafb8e2a (git show一致を実測) |
| verdict | **LGTM** (非ブロッキング訂正1件付き) |

## RC1 3 finding再検証 (各1/1)
1. **F1 mismatch**: 修正確認。§0.2が固定`2`を廃し「resolved tuple不整合3 agent(saizo/tobisaru/gunshi)」を明記、generatorはresolved全agent N/N走査・終端`0/N`。1/1 PASS。
2. **F2 Wave 4A合成**: 修正確認。§5.8へ「Claude現行multi-handler構成(Stop 5/UserPromptSubmit 3/leaf N)は合成対象外。NO-CHANGE優先。Claude適用は別裁定まで禁止」を明記。1/1 PASS。
3. **F3 Fable row**: 修正確認。§0.1 model行へ`claude-fable-5-low`明記。1/1 PASS。

## 軍師RC3対応の反証 (全て一次実測)
- **mode二重性**: 実測`git_mode=100644`(git ls-files -s)、`fs_mode_observed=777`(stat -c %a)、`fstype=v9fs`(stat -f %T)。設計書の分離契約と実測一致。※mount option `aname=drvfs`はD007(mount禁止)により将軍環境で直接検証不能。stat -f=v9fsは9p familyとして整合。
- **before/after mutation突合**: §0.5がsnapshot(`runtime_state_before/after.json`)×journal exactly-one対応+`UNKNOWN_MUTATION=0`+AC22強化。散文でなく計数契約になっており妥当。
- **因果5 row immutable evidence**: 7 blob全数照合(git rev-parse `<commit>:<path>` vs claimed blob)=**7/7 OK、MISMATCH 0**。行内容も照合: infrastructure.md:177=「全9名。全員Opus 4.6(2026-03-17)」一致、training-cycle.md:733/750のR7→R8数値(Opus 2/2→2/2, GPT 0/2→2/2, Sonnet 1/2→0/2)一致、commonization doc L7-15趣旨一致。

## Codex前提すり替わりの探索
Claude primary row必須・Wave 4A合成除外・NO-CHANGE優先・rollback実在契約を通読と差分で確認。**Codex前提へのすり替わり穴=0件**。

## 非ブロッキング訂正1件
- 因果row 5の行範囲`cc1d6a80…:.codex/hooks.json:1-82`は実blobが**73行**(git show | wc -l)であり範囲がEOFを9行超過。blob hash束縛は正確なため証跡能力は毀損しないが、immutable evidence契約(commit/path/line束縛)の自己基準に照らし`1-73`へ訂正されたし。
