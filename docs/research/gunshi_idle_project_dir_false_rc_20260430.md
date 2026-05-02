# Project Directory False RC事故分析+GP-238実装

日付: 2026-04-30
軍師idle自走 — 事故分析→gate化

## 事故概要

cmd_2426-2428(知識辞書シリーズ): project=dm-signalのcmdで
ac_physical_verify.shがshogunリポ(`/mnt/c/tools/multi-agent-shogun/`)内のみ検索。
DM-Signalリポ(`/mnt/c/Python_app/DM-Signal/`)のファイルを「不在」と誤判定。
偽REQUEST_CHANGES 3件発行→将軍反論→撤回→APPROVE。

## 根因

ac_physical_verify.sh L108-112:
```python
if p.startswith('/'):
    full_path = p
else:
    full_path = os.path.join(repo_root, p)  # repo_root=shogunリポ固定
```

相対パス(`docs/research/knowledge-base/methods/x-trend-few-shot.md`)は
常にshogunリポ基準で結合。project=dm-signalでもDM-Signalリポは検索されない。

## 対策: GP-238

1. cmdのprojectフィールドからPJディレクトリを取得(project_dirs dict)
2. 相対パスがshogunリポで見つからない場合、PJリポでfallback検索
3. defense_level: 5(事前コンテキスト提供)

commit: b079eb73。家老APPROVE済み。

## 影響

- 偽RC 3件(cmd_2426/2427/2428)
- 将軍の時間消費(反論作成)
- 忍者への混乱(RC→APPROVE撤回)
- accuracy指標には反映されない(Goodhart問題)

## 教訓

「想像するな確認せよ」の適用漏れ。確認先(リポジトリ)を間違えた。
ac_physical_verify.shは「確認」を自動化する道具だったが、道具自体が
確認先を間違えていた(LG014: 道具が壊れている)。
