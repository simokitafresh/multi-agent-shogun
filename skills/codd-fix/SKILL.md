---
name: codd-fix
argument-hint: "[phenomenon]"
description: |
  CoDD fix PHENOMENONで、観測した事象から設計書・実装・テストを一貫更新するスキル。
  忍者が自然言語で「何が起きているか」を渡し、CoDDが関連設計書を特定して修正案を進める。
  TRIGGER: /codd-fix、codd fix、事象修正、現象修正、PHENOMENON修正
  DO NOT TRIGGER: 設計書の新規生成のみ（→/codd）、性能リファクタ（→/codd-refactor）、テスト実行のみ、運用YAMLの自動修復
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにcodd-fix手順起因のworkaroundが記録されない割合）"
---

# codd-fix

自然言語の事象を`codd fix [PHENOMENON]`に渡し、設計書、実装、テスト、DAG検証まで一貫して進める。

## 前提

- CoDD v2.18.0: `/home/simokitafresh/.codd-venv/bin/codd`
- PATH設定: `export PATH="/home/simokitafresh/.codd-venv/bin:$PATH"`
- 対象リポに`codd/codd.yaml`または`codd.yaml`が存在すること
- `codd dag build`済み、またはこの手順内でbuildできること
- 必要lexiconは対象リポにinstall済みであること。未確認なら`codd lexicon list --path .`で確認する

## 手順

1. 対象リポで依存確認する。

```bash
export PATH="/home/simokitafresh/.codd-venv/bin:$PATH"
codd --version
codd fix --help
codd dag verify --help
```

2. 事象を1文に絞る。

良い入力は「観測した問題」と「望む状態」を含む。コード変更指示に寄せすぎない。

```bash
PHENOMENON="ログインエラー時の表示が利用者に原因を伝えていない"
```

3. 非対話で計画を確認する。

```bash
codd fix "$PHENOMENON" --path . --non-interactive --on-ambiguity abort --dry-run
```

4. 曖昧性がなければ適用する。

```bash
codd fix "$PHENOMENON" --path . --non-interactive --on-ambiguity abort --no-push
```

5. DAGを再構築し検証する。

```bash
codd dag build --path . --format json --output codd/dag_fix_verify.json
codd dag verify --all --path . --format json
```

CoDD v2.18.0で`--all`が未対応の環境では、同等の全体検証として次を実行する。

```bash
codd dag verify --path . --format json
```

6. 変更内容を確認し、対象テストを実行する。

```bash
git diff --stat
bash scripts/test_select.sh <changed-file>
```

共通基盤やCI gateを触った場合は関連batsを実行する。SKIPはFAILとして扱う。

## 報告

- `codd fix --dry-run`の結果
- 実行した`codd fix "$PHENOMENON"`コマンド
- `codd dag build`と`codd dag verify`の結果
- 実行したテストとSKIP数
- 変更された設計書、実装、テストのパス

## 禁止

- 運用YAMLに`dag verify --auto-repair --apply`を使うな
- `codd fix`の曖昧性を無視して`--on-ambiguity top1`で進めるな
- `--no-push`なしで実行するな。忍者はpush禁止
- 事象ではなく広すぎる実装指示を渡すな
