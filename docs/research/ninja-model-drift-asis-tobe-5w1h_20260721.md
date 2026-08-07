# 忍者モデルドリフト（settings.yaml=sol-lowなのにライブがバラバラ）— As-Is/To-Be 5W1H

- date: 2026-07-21T13:24+09:00
- author: shogun（殿指示 13:21「忍者modelが相変わらずバラバラ。放置バグを軍師と協議しasis/tobe 5W1H設計書を作成せよ」）
- status: 軍師協議用ドラフト（設計書。実装は協議合意後）

## 現象（一次証拠：pane最下行バナー＝唯一の現在値）

| 忍者 | settings.yaml(二次SSOT) | paneバナー(一次・実モデル) | 乖離 |
|---|---|---|---|
| hayate | sol-low | sol low | ✓ |
| kagemaru | sol-low | sol low | ✓ |
| **hanzo** | sol-low | **sol medium** | ✗ |
| **saizo** | sol-low | **sol high** | ✗ |
| **kotaro** | sol-low | **sol high** | ✗ |
| tobisaru | sol-low | sol low | ✓ |

settings.yaml(SSOT)は全員sol-lowだが、ライブ3名がmedium/highに固着。家老の復元A-C(settings.yaml/tmux変数/config.toml)報告後もライブに未反映＝ドリフト定着。

## 真因（コード＋git確定）

1. **codex_config_restore廃止裁定が実装に貫通していない**:
   - commit `a125c2aa5`(殿裁定2026-07-21 00:38「config.toml restore廃止」)のメッセージ: 「真因=codex_config_restoreがrespawn後に汚染値へ戻していた。applyで正本→respawn→restoreで汚染復帰→次respawnで誤model。修正=restore廃止」。
   - しかし現コードに **codex_config_restore 呼び出しが4箇所現存**: `ninja_monitor.sh:1421 / 6850 / 8192 / 8196`＋定義 `cli_lookup.sh:622`。a125c2aa5は2箇所しか削除しておらず、rollback `b3f2f56d0`(脱感染sweep全撤回)が `ninja_monitor.sh` を13行touch＝廃止を復活。**廃止裁定が実装に残存＝バグ放置**。
2. **発生機序**（ninja_monitor.sh:1400-1421）: `1404 codex_config_apply_agent`(settings.yaml=sol-low を config.toml へ) → `1409 respawn-pane -k` → **`1421 codex_config_restore`(config.tomlを前回=汚染値へ戻す)**。restoreがrespawn後に走るため、config.tomlが汚染状態で残り、hanzo/saizo/kotaroが実験(model_effort 01:xx)でmedium/high respawnされた値がSSOT復元後もクリーンrespawnされず固着。
3. **二次情報で完了判断**: 家老の復元は settings.yaml/tmux変数/config.toml(二次)を直し「復元完了」と報告したが、一次情報(banner)未確認。想像するな確認せよ原則違反（[MEM: 殿厳命 想像せずに確認 二次情報で判断を止めるな]）。
4. **反映がrespawn依存**: 作業中paneは/model不可・idle時のみrespawn([MEM: knowledge:2f8c46ec])。busy中のhanzo/saizo/kotaroにSSOTが伝播しない。

## 5W1H

### As-Is
- **What**: settings.yaml(SSOT)=全員sol-lowだが、ライブ忍者3名がsol medium/highに固着。SSOTがライブへ伝播しない。
- **Why(害)**: (1)殿指示「6人sol-low」が実現していない (2)コスト/性能が意図と乖離(high=低速高コスト) (3)復元完了報告が虚偽になり信頼が崩れる。
- **Who**: ninja_monitor.sh のcodex respawn経路(codex_config_apply_agent→respawn→codex_config_restore)。cli_lookup.sh codex_config_restore定義。
- **When**: respawn毎。実験(model_effort 01:xx)以降、SSOT復元(13:xx)後も未クリーンrespawnの3名で固着。
- **Where**: `scripts/ninja_monitor.sh:1421,6850,8192,8196` / `scripts/lib/cli_lookup.sh:622` / config.toml(正本)。
- **How**: apply(正本)→respawn→restore(汚染復帰)の順序欠陥＋廃止裁定のrollback復活。

### To-Be（軍師協議で確定。軍師はmodel切替6/6実験の知見保有）
- **What**: codex_config_restore廃止裁定(a125c2aa5)を実装へ完全貫通。config.tomlは apply後そのまま正本維持しrestoreしない。
- **How(候補・協議対象)**:
  - (1) **codex_config_restore 4呼び出し(1421/6850/8192/8196)を全撤去**し、定義もdead codeなら削除。config.tomlはcodex_config_apply_agentが常にSSOTから再生成する正本のまま維持。
  - (2) **一次情報ドリフト検知**: pane最下行バナー vs settings.yaml(SSOT) の乖離を ninja_monitor が定期照合し、乖離をALERT＋idle時に自動クリーンrespawnで是正（二次情報依存を排除）。
  - (3) **既存3名の即時是正**: hanzo/saizo/kotaro が idle になり次第 codex_config_apply_agent + clean respawn で sol-low へ。busy中は待つ（/model不可制約）。
  - (4) **回帰防止**: 「廃止したはずのrestoreがrollbackで復活」を防ぐため、restore呼び出し0件を境界fixture/契約testで固定（正本突合＋境界fixture両方義務[MEM: 殿15:14]）。
- **Why**: restoreは設計上不要（applyがSSOTから正本生成）。restoreは汚染復帰しか生まない。表示型gate追加でなく欠陥ロジック撤去＝殿「表示型を削る」原則に合致。
- **When/Who**: 協議合意後にcmd化→忍者実装→軍師レビュー。SSOT=settings.yaml、一次確認=banner。

## 軍師協議の確定回答（三者合意成立 2026-07-21T13:37 blt_133716）
- **(1) YES**: codex_config_apply_agent(cli_lookup.sh:593-618)はSSOTからsed置換＝冪等。restore不要。restoreは汚染復帰しか生まない。
- **(2) 4箇所全撤去可**: L1421/L6850/L8192(BYPASS失敗ロールバック意図・次applyが上書きで実害なし)/L8196＝全て次applyが再生成のため撤去OK。定義cli_lookup.sh:622-630もdead code削除。
- **(3) ドリフト検知は保険・優先度低**: restore撤去(1)だけで根治十分。検知は任意。
- **★実装順序(緊急)**: restore撤去を先に実装せよ。撤去前respawnは再汚染する。既存3名はrestore撤去後のidle自動respawnで sol-low へ自然是正。

## 確定To-Be（三者合意＝根治）
1. codex_config_restore 4呼び出し(ninja_monitor.sh:1421/6850/8192/8196)＋定義(cli_lookup.sh:622)を全撤去。config.tomlはapplyがSSOTから再生成する正本のまま維持。
2. 回帰防止: restore呼び出し0件を境界fixture/契約testで固定（rollback復活の再発防止）。
3. (保険・任意) banner vs SSOTドリフト検知をidle時ALERT＋自動respawnで是正。
4. 撤去後、hanzo/saizo/kotaroがidle化次第の自動respawnでsol-lowへ是正をbanner一次確認。
