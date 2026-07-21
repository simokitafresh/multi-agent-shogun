# cmd_4109 忍者モデルドリフト根治

- 固定基点: `scripts/lib/cli_lookup.sh` HEAD `3de92b6bc473194cd57ffedcdc463fa43c87d6a7`
- 根因: respawn前のSSOT適用後に`codex_config_restore`が汚染値を戻していた。
- 修正: `scripts/ninja_monitor.sh`の4呼出しと`scripts/lib/cli_lookup.sh`の定義を撤去し、restore参照を5件から0件へ変更。
- 契約: `tests/unit/test_codex_config_ssot.bats`がscripts内restore 0件と、同一agentへの2回連続applyが同一出力になることを固定。

## paneバナー一次情報

| 忍者 | 修正前 | 修正後 | SSOT | 乖離 |
|---|---|---|---|---|
| hanzo | sol medium | sol low | sol low | 0 |
| saizo | sol high | sol low | sol low | 0 |
| kotaro | sol high | sol low | sol low | 0 |

結論: restore撤去でsettings.yamlのSSOTがconfig.tomlと次回自動respawn後のライブへ貫通する。

補足: kotaroの初回再起動は家老の手動bare respawnがstale `pane_start_command`（high）を再利用したためhighが残った。正規`cli_launch_cmd`経路で再起動後、6/6 sol-low・乖離0を確認した。したがってrestoreは恒久ドリフトの真因だが、bare respawnも一時的なstale起動経路として併存していた。
