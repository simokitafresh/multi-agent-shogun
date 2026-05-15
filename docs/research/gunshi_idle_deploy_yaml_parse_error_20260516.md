# deploy_task.sh YAML parse error — なぜなぜ7回

## 現象
deploy_task.logで3回のYAML parse error。全てkagemaru.yamlでverify_ac_consistency+NINJA_WP+[INJECT]が失敗。
デプロイは継続するが、教訓注入・AC検証・ninja_weak_pointsが無効化される。

```
[INJECT] ERROR: while parsing a block mapping
  in ".../queue/tasks/kagemaru.yaml", line 2, column 3
expected <block end>, but found '<scalar>'
  in ".../queue/tasks/kagemaru.yaml", line 31/24/45, column 25/13/19
```

発生タイムスタンプ:
1. 2026-05-15 23:01:49 (cmd_2785配備)
2. 2026-05-15 23:39:01 (cmd_2788配備)
3. 2026-05-15 23:46:22 (cmd_2792配備) — `while scanning a quoted scalar`

## なぜなぜ
1. なぜparse error？ → yaml.safe_loadがblock mapping不整合を検出
2. なぜデプロイ続行？ → except(L4006)でキャッチし`[INJECT] ERROR`ログのみ。verify_ac_consistencyも同様
3. なぜkagemaru.yamlが壊れる？ → エラー行が毎回異なる(31→24→45)。デプロイごとに書換わるため
4. なぜ書換えで壊れる？ → _safe_section_replace(L3915)がテキストベースでYAMLセクションを置換
5. なぜテキスト置換でYAMLが壊れる？ → マルチライン値のインデント処理(_sv L3861)が2スペース固定。ネスト深度によっては不足
6. なぜ固定インデント？ → _yaml_lines(L3870)はind引数でネスト対応だが、_sv(L3867)のマルチラインは`'  ' + ln`固定
7. 根因: **_sv()のマルチライン値インデントがネスト深度を無視する構造バグ**。深いネスト(related_lessons内のdetailなど)で挿入されたマルチライン値がインデント不足→YAML構文崩壊

## 影響
- 3回のデプロイで教訓注入・AC検証・ninja_weak_pointsが無効化
- デプロイ自体は続行するため**忍者は気づかない**(silent failure)
- 教訓注入がスキップされた忍者の作業品質低下（教訓なしで作業）
- verify_ac_consistency失敗でAC不整合が未検出のまま配備

## silent failure構造(PI-018関連)
[INJECT] ERROR後にexcept→続行。忍者への影響通知なし。家老/軍師への通知もなし。
deploy_task.logを手動で読まない限り発見不可能。

## 修正案
### 短期
_sv()のマルチライン値インデントをネスト深度(ind引数)に連動させる

### 中期
1. [INJECT] ERROR発生時にstderrへWARNINGだけでなくntfy/inbox通知を追加
2. verify_ac_consistency失敗時もntfy/inbox通知を追加

## 因果鎖
_sv()マルチラインインデント固定2sp→ネスト3+でYAML構文崩壊→yaml.safe_load FAIL→except catch+続行→教訓注入/AC検証/NINJA_WP全スキップ→忍者に教訓なし+AC不整合未検出→品質低下(silent)。

修正: _sv()インデント連動+失敗通知→silent failure根絶=正の複利
