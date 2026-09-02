<!-- gist-master: 8e1336f8b297ccd9bd5f407444844434 x_account_ops_automation_asis_tobe_5w1h_20260903.md -->
# X アカウント運用(バム @TokyoJibika)の Grok 包装→API 自動化 — AsIs / ToBe / 5W1H 設計書 v0.3(2026-09-03 04:00、cmd_4463 実測 §1c を追加。v0.2=03:35、殿回答 B-1〜B-10 を §1b/§2/§5 へ反映。v0.1=03:20、殿発案 03:13『grok によるアカウント運用は今後 API などで自動化まで持って行きたい。新しい設計書にしないか』)

## §0 一文定義
Grok 作成の「届け方マニュアル」(中身固定・包装のみ変更)を、**ストック記事→スロット→LLM 包装→品質 gate→X API 投稿→KPI 還流**の 1 本の pipeline として段階的に自動化する。戦略・検証・有料層の中身は一切変えない(マニュアル §1 Non-negotiables を pipeline の不変条件として機械化する)。

## §1 AsIs(2026-09-03 一次確認)
| 項目 | 現状 | 出典 |
|---|---|---|
| マニュアル | Grok 作成 `docs/research/bam_delivery_manual_grok_20260902.md`(433 行、§0-§14)。実測で精度を上げる質問集 `bam_delivery_manual_questions_20260902.md`(A 公開 6 問/B 本人 10 問/C 法務 5 問/D 反映先) | 殿デスクトップ 09-02 21:05/21:06、将軍複写 9198f53a0 |
| 投稿 | 殿の手動。不規則(マニュアル §2『接触回数が医師スケジュール』) | マニュアル §2 |
| Grok API | `config/xai_api.env` に XAI_API_KEY。x_search を `skills/x-research`・`skills/x-thread-fetch`・`skills/weekly-report-writer` が使用(読み専用) | skills/*/SKILL.md |
| X 投稿 API | **未整備**。repo に投稿 script 0 | rg twitter/tweepy/api.x.com → 0 |
| note | `skills/note-writer`(CDP 経由の下書き作成、ProseMirror 制約)、`/prose-polish` | skills/note-writer/SKILL.md、CLAUDE.md |
| 素材 | 完全ガイド(note n171daa7f92a1)、How to マガジン(mb4377418b422)、dm-signal.com(LP EN/JA、月次頁 /signals/YYYY-MM/、Basic 無料)、堅牢性レポート、showcase API(hero/series/plans) | マニュアル §1、dm-signal-lp-seo-plan_20260830.md v5 |
| KPI | 未計測。Search Console/Bing は SEO lane で登録済(T201)。X analytics 未接続 | seo-plan v5 |
| 制約 | 医師の可用時間(週 90 分未満想定、B-1 未回答)、助言規制(マニュアル §10)、有料中身の非公開 | マニュアル §5 §10 |

## §1b 殿回答(2026-09-03 03:31、原文要旨。質問集 §B の 10 問)
| # | 回答 | 設計への反映 |
|---|---|---|
| B-1 可用時間 | 『自動化するから関係ない』 | §5 週次枠の上限を人手ではなく API cap で決める(P2 の週 3 投稿 cap は維持、上限は殿裁定で可変) |
| B-2 読者構成 | 不明。医師 40% 程度と推定、DM 経験者は少ない | 第一文は『忙しい専門職』寄りだが、初心者比率が高い前提で S3 の第一文に『相対+絶対の 2 部品』を必ず入れる(マニュアル §4) |
| B-3 有料化前の記事 | note の記事(特定 3 本は不明) | cmd_4463 A-4(再掲比)と S6 KPI(note ビュー→dm-signal 到達)で実測 |
| B-4 初回質問 | 不明 | cmd_4463 では公開リプから推定、以後 S6 で収集(質問集『いちばん効く 3 問』の 3) |
| B-5 Basic 到達 | 『今後調べたい』 | S6 の必須指標に昇格: dm-signal showcase_events(step/ua_class/lang)を月次集計する cmd を P1 で出す |
| **B-6 数字ホワイトリスト** | **保有シグナル・構成 ticker など模倣可能な情報は排除。metrics は全 PF 公開可。無料公開の Basic DualMomentum だけはポジションまで公開可** | **S4 gate の核心規則(§2 不変条件 (3) を改定)**: 出してよい=全 PF の CAGR/MaxDD/Sharpe/期間/ベンチ+Basic の保有。出してはいけない=Basic 以外の保有シグナル・構成 ticker・FoF の重み。blocklist は dm-signal 有料 PF 名ではなく『holding/ticker/weight』の値そのもの |
| B-7 倍率・劇薬・戦国 | どちらでもよい | マニュアル既定(A 面第一文には出さない、B 面可)を採用 |
| B-8 メンバーシップ | note のメンバーシップ | 公開文面は note の規約に従う。§10 法務は note メンバーシップ前提で書く |
| B-9 二次利用 | 保有シグナル・構成 ticker 以外は可 | 要約スレッド・図の転載・引用 RT・切り抜きは可。S4 の同じ blocklist で二次利用素材も検査 |
| B-10 成功指標 | エンゲージメント | §11 KPI の主指標=エンゲージメント(表示・いいね・リポスト・リンククリック)。マニュアルの『フォロワーを捨てる』は維持しつつ、理解到達 KPI は副指標 |

## §1c 公開情報の実測(cmd_4463 飛猿、観測日 2026-09-02、正本 `docs/research/x_account_asis_measurement_20260903.md` 795dbd37a。不明 19 項目は API/表示の構造的制約で、推測は 0)
| 項目 | 実測 | 設計への反映 |
|---|---|---|
| X @TokyoJibika | フォロワー 4,434。直近 30 日の投稿数・表示・いいね中央値は x_search では取れない(本人 Analytics のみ) | S6 KPI は X API(Basic 以上)か本人 Analytics の CSV 取込が必要→D2 の判断材料 |
| note | How to マガジン 49 本、完全ガイド スキ 53(公開 2025-09-25)。フォロワー数・コメント数は表示なし | S1 ストック台帳の初期母集団=49 本+完全ガイド |
| メンバーシップ | note: ベーシック ¥1,000/月・スタンダード ¥8,000/月。dm-signal 側は Basic/Standard/Premium(招待)/Secret の 4 段。人数は非公開 | 公開文面は note の 2 プラン名で統一(§10) |
| dm-signal.com 無料範囲 | Basic-DualMomentum は sign-in 不要で CAGR/Sharpe/MDD と 2003-09〜の長期チャートまで見える | 殿 B-6 と一致=Basic は保有まで公開可 |
| 入口(A-2) | note 2 種+旧ブログ 2 種(livedoor/hatena)+dm-signal の 5 種が並存し初見が迷う | §3 の『入口 3 つ固定』は実測で裏付け。旧ブログ 2 種は目次上位を完全ガイドへ揃える(マニュアル §9) |
| 検索(A-3) | 『デュアルモメンタム』上位は書籍販売・解説ブログ・動画が占め、完全ガイドは定義系の意図で勝ち、ツール/実績系で負ける(詳細は正本 §A3) | SEO lane(T201)の狙い語=定義系。実績系は LP 月次頁で取る |
| 再掲比(A-4) | 06-30〜09-02 でユニーク記事 18 本中、2 回以上貼られたのは 3 本(How to マガジン/『1 年続けられない人は向いてない』/アパート記事)、1 回のみ 15 本=約 1:5 | マニュアル §2『反復がない』を数値で確認。S2 の枠 A(教材再掲)の初期対象=完全ガイド+How to+堅牢性記事 |
| 類似アカウント(A-5) | 医師×投資 5 例中 4 例は間口の広いテーマ(インデックス/日本株)で医師以外も取込 | DM 特化は市場が狭い=フォロワーでなくエンゲージメント KPI(殿 B-10)が妥当 |
| 海外ツール(A-6) | Allocate Smartly/Optimal Momentum/PV の無料説明は『定義→ルール→バックテスト条件→限界→免責』の順 | S3 の包装順(マニュアル §4)と同型。見出し順をそのまま S3 のテンプレに使う |

## §2 ToBe(pipeline 6 段。各段の入出力を固定し、段ごとに手動→半自動→自動へ)
```
[S1 ストック台帳] 無料記事・図・数字ホワイトリスト(YAML)
   ↓
[S2 スロット計画] 週 3 枠(A 教材再掲/B 検証/C 運用の形)+月次 D+四半期 E → 予約 calendar(YAML)
   ↓
[S3 LLM 包装] マニュアル §12 のシステム文で Grok(または Claude)に生成。入力=記事 URL+スロット+切り口+使ってよい数字
   ↓
[S4 品質 gate] マニュアル §12 チェック 5 項+§4 禁止語(倍率単独/無敵/今これを買え/内部用語第一文/URL 3 つ以外)を機械判定。FAIL=投稿しない(fail-close)
   ↓
[S5 投稿] X API v2 POST /2/tweets(スレッドは reply chain)。予約は cron。P1 までは『下書き→殿承認→投稿』、P2 で自動
   ↓
[S6 KPI 還流] X API の tweet metrics+note ビュー+LP(Search Console)を週次で台帳へ。赤信号(§11)を検知したら S2 の切り口を変える
```
不変条件(機械化する Non-negotiables): (1) 戦略・パラメータ・新シグナルを生成しない(S3 のシステム文+S4 の diff 検査=素材にない数字を出さない) (2) 公開 URL は 3 つ固定 (3) Basic DualMomentum 以外の保有シグナル・構成 ticker・FoF 重みを出さない(殿 B-6。S4 は showcase API の holding/ticker/weight 値を blocklist に使う。metrics は全 PF 可) (4) 免責 1 行必須 (5) 数字は期間/CAGR/MaxDD/ベンチのセットのみ(単独倍率 regex で FAIL)。

## §3 段階(Phase)と可逆性
| Phase | 内容 | 自動化度 | 可逆 | 完了条件(二値) |
|---|---|---|---|---|
| P0 | ストック台帳+数字ホワイトリスト+スロット calendar を YAML 化。S3 を Claude/Grok で手動実行し下書き 12 本(4 週分) | 手動 | file 削除 | 台帳 1 file、下書き 12 本が S4 gate PASS |
| P1 | S4 gate を script 化(regex+blocklist+URL 検査)。S5 は『X API で下書き投稿(未公開)or 殿承認後に script が投稿』 | 半自動 | 投稿は取消可、API key 失効で停止 | gate 偽陽性 0/12、承認→投稿 1 本が API で成功 |
| P2 | cron で S2→S3→S4→S5 を無人実行。殿は週 15 分の KPI 確認のみ | 自動 | flag file で即停止(単一 publisher と同型) | 4 週連続で週 3 投稿・gate FAIL 0・殿介入 0 |
| P3 | S6 KPI 還流で切り口を自動選択(A の 4 切り口の rotation を metrics で重み付け) | 自動 | rotation を固定に戻す | 赤信号 0、理解到達 KPI が 4 週連続上昇 |

## §4 5W1H
- **WHY**: 良い記事が 1 回で終わり反復がない(マニュアル §2)。医師の時間では週 3 枠を手で回せない。中身は完成しているので届け方だけを機械に任せる。
- **WHAT**: §2 の 6 段 pipeline。P0-P3。
- **WHEN**: P0 は殿の B 質問回答後すぐ(数字ホワイトリスト B-6 が前提)。P1 は X API 発行後。P2 は P1 の 4 週実績後。
- **WHERE**: `multi-agent-shogun/skills/x-post-pipeline/`(新 skill)+`docs/research/x_stock_ledger.yaml`(台帳)+cron。投稿 API key は `config/x_api.env`(git-ignore)。
- **WHO**: 殿=B 質問回答・承認(P1)・KPI 確認。将軍=設計・cmd 起票。忍者=S1/S4/S5 の実装。Grok=S3 包装(x_search で反応も収集)。
- **HOW**: 単一 publisher と同じ型=flag file で ON/OFF、fail-close、1 batch 1 commit、canary は積まない(殿 09-03 01:30)。

## §5 未決事項(殿裁定が必要。返答なければ既定案)
| # | 論点 | 既定案 |
|---|---|---|
| D1 | S3 の LLM は Grok か Claude か | 既定=Claude(repo 内 skill で回せる)。Grok は x_search 収集+A 面の別案生成に使う |
| D2 | X API のプラン(Free は書込み 1,500/月・読取り不可、Basic は $100/月で metrics 可) | 既定=P1 は Free で投稿のみ、P3 で Basic |
| D3 | 殿承認の UI(P1) | 既定=ntfy に下書きを送り「y」で投稿(将軍と同じ y 復帰の型) |
| D4 | B 質問 10 問の回答 | **回答済 03:31(§1b)**。残り実測=B-3/B-4/B-5 は cmd_4463 と S6 で埋める |
| D5 | A 質問 6 問の偵察 cmd を先に出すか | 既定=出す(cmd_4463、忍者 1 名、Grok x_search+web) |
| D6 | 法務 C 5 問 | 既定=偵察 cmd に含めず、P1 前に別 cmd で一般論を集める |

## §6 リスクと検知
| リスク | 検知 | 処置 |
|---|---|---|
| LLM が新ルール・倍率を生成 | S4 の『素材にない数字』diff、regex | fail-close、下書きを捨てる |
| 有料の中身漏れ | dm-signal 有料名 blocklist | 同上 |
| 助言に見える表現 | 命令形+銘柄名の共起 regex | 同上+免責付与 |
| API 上限・失効 | HTTP 4xx | 停止 flag+ntfy |
| 殿不在時の暴走 | P2 の週 3 上限をハード cap | cap 超過は投稿しない |

## §7 最初の cmd(P0 の前)
- cmd_4463(偵察): マニュアル質問集 A-1〜A-6 を Grok x_search+web で埋め、`docs/research/x_account_asis_measurement_20260903.md` に表で残す(出典 URL+観測日、不明は不明)。
- 殿へ: B-1〜B-10(本人にしか答えられない)。特に B-6 数字ホワイトリストが S3 の入力になる。

## §8 レビュー履歴
- v0.3(09-03 04:00) cmd_4463 実測を §1c に統合。入口 5 種並存・再掲比 1:5・X 指標は API/Analytics 経由でしか取れない、を設計根拠に追加
- v0.2(09-03 03:35) 殿回答 B-1〜B-10 を §1b に記録、§2 不変条件 (3) と §5 D4 を改定。KPI 主指標=エンゲージメント
- v0.1(09-03 03:20) 将軍起草。殿発案 03:13。gist 初回。
