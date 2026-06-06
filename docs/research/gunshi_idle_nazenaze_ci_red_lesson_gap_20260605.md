# なぜなぜ7回: CI RED見逃し+D0バグ4件の根因分析
<!-- generated: 2026-06-05T19:10:00+09:00 by gunshi idle analysis -->

## 対象事象

軍師のレビュー/検証が「1パスで十分」と判断し、別パスのバグ/副作用を見逃す。
- cmd_3184: gate script挙動変更→既存bats前提崩壊→CI RED（adversarial未適用）
- D0 ac_physical_verify: stdinモードのみテスト→cmd_idモードでバグ4件（S0-5不十分）

## なぜなぜ7回

| # | なぜ | 答え |
|---|------|------|
| 1 | なぜcmd_3184でCI REDを見逃したか | adversarial観点未適用。挙動変更が既存batsの前提を崩すことを事前検死で検出しなかった |
| 2 | なぜadversarialを適用しなかったか | 冷え観点(3/10件)。しかしpremortemは適用済み。premortemで「テスト前提崩壊」を列挙しなかったのが真因 |
| 3 | なぜpremortemで「テスト前提崩壊」を列挙しなかったか | FM(失敗モード)を「実行時の挙動」で考えた。テスト前提は「開発時の副作用」で視野外 |
| 4 | なぜ事前検死の視野が「本番挙動」に限定されていたか | gunshi.md Step 4の5パターン(return 1波及/set+e/フィルタ偽陰性/上限値除外/非atomic)は全て実行時バグ。開発プロセスバグ未カバー |
| 5 | なぜ開発プロセスバグがパターンに含まれていなかったか | パターンは過去workaround/BLOCK事例から帰納追加。テスト前提崩壊→CI REDは今回が初の顕在化…ではなく、CI RED修正cmd 3件が既に存在した |
| 6 | なぜ過去CI REDの根因が還流していなかったか | CI RED修正はkaro_direct(緊急定型)で処理。workaroundではなくclean扱い。detail/root_causeが空 |
| 7 | なぜCI RED修正の根因が還流しないか | **karo_directフローにlesson_candidate抽出ステップがない**。通常cmdは報告YAMLにlesson_candidateが含まれるが、karo_directは簡略フローで省略 |

## 根因

CI RED修正のkaro_directフローにlesson_candidate抽出がなく、根因がlessons/事前検死パターンに還流しない。
同種のCI REDが繰り返されても事前検死パターンが拡張されず、挙動変更→テスト前提崩壊を検出できない。

## 自動化ターゲット（2件）

### Target 1: 事前検死パターンに「テスト前提崩壊」追加
- gunshi.md Step 4に6番目のパターン追加
- 「gate/hook/scripts変更cmdで、target_pathの関連batsテストの前提(fixture)が崩れないか」
- D0で追加したac_physical_verify関連テスト表示(Level 5)が事前コンテキスト提供

### Target 2: karo_directフローにlesson_candidate強制
- CI RED修正のkaro_directでも報告YAMLにlesson_candidate記入を強制
- または karo_workaround_log.sh でCI RED修正時にdetail/root_causeの記入を必須化
- 家老側の仕組み変更のため、家老にlesson_candidateとして送信

## D0バグ4件との関係

D0のS0-5不十分(stdinのみテスト)もなぜ3と同根: 「1パスで動いた=十分」という判断構造。
- stdinで動いた→十分（実行時挙動OK）
- cmd_idモードは「既存バグ」→自分の範囲外（開発プロセスの境界判断ミス）

両方とも「自分が見たパスの外に穴がある」という同一パターン。対策: S0-5に「全入力モードテスト」を追加済み。
