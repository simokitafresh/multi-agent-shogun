# CMD年代記
<!-- last_updated: 2026-05-04 -->

> 完了cmdの1行索引。詳細は queue/archive/cmds/{cmd_id}.yaml 参照。

## 2026-03

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| — | → 3月前半(03-09, cmd_662-707)は `context/archive/cmd-chronicle-2026-03-early.md` 参照 | — | 03-09 | 43件 |
| cmd_940 | 偵察+整備 — Drive確定申告フォルダの整合性検証+チェックリスト恒久化 | | auto-ops | 03-14 | Drive「2026確定申告 個人事業」フォルダの完全性・整合性チェック完了。 3AC全て調査完了。ローカルCSVとDrive版の間に体系的な差異を検出。 |
| cmd_942 | 偵察 — 確定申告証票PDFの重複・有効性調査 | | auto-ops | 03-14 | — |
| cmd_944 | 修正 — マスターCSV更新（MFクレカ追加反映） | | auto-ops | 03-14 | — |
| cmd_945 | 修正 — PayPal公式レシートPDFでDrive既存PDFを差し替え | | auto-ops | 03-14 | — |
| cmd_946 | 実装 — マスターCSV列16「使用カード」追加 | | auto-ops | 03-14 | — |
| cmd_943 | 修正+整備 — 確定申告証票PDF浄化 | | auto-ops | 03-14 | — |
| cmd_949 | 修正 — CDP修復+note領収書DL試行 | | auto-ops | 03-15 | — |
| cmd_948 | 修正 — Anthropic領収書アップロード+[OK]格上げ | | auto-ops | 03-15 | — |
| cmd_947 | 修正 — note.com領収書DL（売上手数料2件+振込手数料11件） | | auto-ops | 03-15 | — |
| cmd_950 | 偵察 — 欠損領収書6商号Gmail調査+取得可能性判定 | | auto-ops | 03-15 | — |
| cmd_951 | 修正 — 全Driveフォルダ Invoice/Receipt混在是正 | | auto-ops | 03-15 | — |
| cmd_955 | 最適化 — monthly-returns fallback window query化（-88%改善） | | dm-signal | 03-15 | — |
| cmd_956 | 最適化 — monthly_trade N+1クエリ修正（170→3 queries） | | dm-signal | 03-15 | — |
| cmd_957 | 偵察 — MCP obs正本突合（Vercel原則適用） | | infra | 03-15 | — |
| cmd_959 | 偵察 — MCP判定割れobs万全偵察（8名独立判定） | | infra | 03-15 | — |
| cmd_960 | 強化 — 逆瀬川記事知見4点取込 | | infra | 03-15 | — |
| cmd_961 | 強化 — tdd-guard型Hook＋Gate（テストSKIP/FAIL機械強制） | | infra | 03-15 | — |
| cmd_962 | 万全偵察 — DM-signal UX快適性の現況再調査 | | dm-signal | 03-15 | — |
| cmd_964 | 修正 — FEキャッシュ整合性修復（ETag孤児/SWR不統一） | | dm-signal | 03-15 | — |
| cmd_963 | 修正 — BE N+1クエリ修正High3件 | | dm-signal | 03-15 | — |
| cmd_967 | 修正 — trade-rule.md §7.3aに§2.1 SSOT 3層への逆参照追加 | | dm-signal | 03-15 | trade-rule.md §7.3aの逆参照注記を強化。既 |
| cmd_968 | 強化 — 金融ML知識辞書 ID予約済み5エントリの辞書化 | | dm-signal | 03-15 | 金融ML知識辞書 ID予約済み5エントリの辞書化完了。 全フ |
| cmd_965 | 最適化 — Recharts/KaTeX dynamic import強化（バンドル27%削減） | | dm-signal | 03-15 | Recharts/KaTeX dynamic import強 |
| cmd_966 | 修正 — FEテスト5件FAIL修復（現行コードへの追随） | | dm-signal | 03-16 | — |
| cmd_958 | 修正 — MCP Vercel原則適用（構造改革） | | infra | 03-16 | — |
| cmd_969 | 強化 — DM-Signal Ruff導入 + PostToolUse Hook品質ループ構築 | | dm-signal | 03-16 | — |
| cmd_971 | 強化 — DM-Signal FE Biome PostToolUse Hook + Hurl API E2Eテスト | | dm-signal | 03-16 | DM-Signal FE Biome導入+PostToolU |
| cmd_974 | 偵察 — Codex忍者のアイデンティティ認識状況調査 | | infra | 03-16 | — |
| cmd_975 | 偵察 — DM-Signal PF健全性・現在ポジション・実績の定量調査 | | dm-signal | 03-16 | — |
| cmd_970 | 強化 — infra shellcheck PostToolUse Hook + リンター設定保全 | | infra | 03-16 | — |
| cmd_972 | 強化 — Stop Hook完了ゲート + エラーメッセージ修正 | | infra | 03-16 | — |
| cmd_973 | 強化 — AIアンチパターン検出 + ast-grepアーキテクチャ | | infra | 03-16 | — |
| cmd_976 | 偵察 — 殿の哲学から導くDM-Signal診断指標の再設計 | | dm-signal | 03-16 | — |
| cmd_978 | 衛生 — 全プロジェクト .gitignore整備 + 未プッシュ一覧 | | infra | 03-16 | — |
| cmd_980 | 偵察 — 教訓注入率低下の原因精査と改善提案 | | infra | 03-16 | — |
| cmd_979 | 強化 — lint違反放置禁止ルール + Stop Hook lint残留チェック | | infra | 03-16 | — |
| cmd_1010 | 四神12体+忍法15体 — 極値プロファイル・相関構造・忍法コンビネーション分析 | | dm-signal | 03-16 | AC7横断サマリー完了。4サブタスク(Sub-A〜D)の結果 |
| cmd_1301 | startup gate bash算術エラー修正 — grep -c || echo anti-pattern根絶 | infra | 03-23 | gate_shogun_startup.sh L101/L282の grep -c || echo anti-pattern を修正。syntax error  |

## 2026-04

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_1696 | 影丸(Sonnet 4.6)の@model_nameが「Opus」と誤表示。根因: model_detect.shのバナー検出パターンが (Opus|Haiku)のみでSonnetが欠落。Sonnetバナーがマッチせずキャッシュの古い値が返される。 加えて、陣形図(karo_snapshot.txt)にモデル情報列がなく、編成状態が不可視。 | infra | 04-03 | model_detect.shにSonnet検出パターン追加 |
| cmd_1697 | cmd_save.sh L152-153のgrep "scope_mode:"/"scout_exempt:"がcmdブロック内にマッチしない場合、 set -eで即exit 1。|| trueがないのが原因。cmd_1696でscout_exemptなし初回BLOCK発生の根因。 | infra | 04-03 | cmd_save.sh L152-153のgrep scop |
| cmd_1703 | cmd_1702がHigh=「rolling CAGR > 全期間CAGR」の二値分類で実装した。 本番定義はHigh=rolling CAGR系列のMax値(generators/rolling_returns.py L89: best=portfolio_rolling.max())。 間違った前提で得た成果物は混乱の元。削除して正しい定義で再分析する。 | dm-signal | 04-04 | cmd_1702成果物3件を削除後、production定義 |
| cmd_1704 | cmd_1700で65PF一律EMA5→59 FoF 83%悪化。原因: Highが落ちるPFにも一律適用し尖りを削った。 cmd_1703のrolling return High特徴量で、EMA5でHighが落ちないPFを特定済み。 Highが落ちないPFだけにEMA5を選択適用し、FoF伝播を再測定する。 | dm-signal | 04-04 | 12M delta_high >= 0 で52/65 PFを |
| cmd_1705 | EMA span=5でStandard PF改善→FoF 83%悪化。棄却済み仮説2件: (1) シグナル同期化(Jaccard r=-0.199) (2) High(Max)落下(選択適用でも悪化)。 原因特定に至っていない。広く5指標を同時に算出してデータを揃え、原因を多角的に分析する。 | dm-signal | 04-04 | — |
| cmd_1706 | EMA5一律→FoF 83%悪化。原因分析より先に「より良いFoFが作れるか」を探る。 良いものが見つかれば、現行との差分をなぜなぜしてヒントが見つかる(殿指示)。 5パターンの前処理を59 FoFで試し、baselineに勝つパターンを探索する。 | dm-signal | 04-04 | 5条件×59FoF比較を完了。best patternはE( |
| cmd_1707 | 前処理研究完了。Standard PF品質改善はFoFに伝播しない。 次の研究: FoFがStandard PFを選ぶ「判断ロジック」自体の改善。 まず現行FoFのmomentum判定の実装を正確に把握し、改善余地を特定する。 | dm-signal | 04-04 | 59 active FoF auditを完了。現DB基準の相 |
| cmd_1708 | 前処理研究は区切り。FoFの天井突破には材料品質(前処理)ではなく判断ロジック(selection)の改善が必要。 既存のr29f_shin_clsel_2d_grid.py(LB×Metric 48セル WF-OOS)を再実行し、 現行シン忍法v2のselection blockパラメータが最適か検証する。 既存スクリプトをそのまま使う。新規開発なし。 | dm-signal | 04-04 | — |
| cmd_1709 | GS速度最適化を修行で回す前提条件。パリティ基盤なしに修行を回すな(軍師なぜなぜ結論)。 パリティ条件(殿定義): 全期間の本番DBでの保有ポジション(holding_signal)の完全一致。 ゴールデンデータ(殿提案): 本番DBから1回取得→固定ファイル。以降はこれと比較。 | dm-signal | 04-04 | 65 standard PF golden dump作成、g |
| cmd_1710 | 今日のセッションで4回、殿の言葉を定義確認せず即cmd起票した: (1) rolling return High→本番定義(Max)未確認 (2) シン忍法のスクリプト→run_077_*未特定 (3) 2Dグリッド→既存結果未確認 (4) パリティ条件→定義を軍師に丸投げ 真因: cmd起票前の「確認フェーズ」を強制する仕組みがない。 cmd_save.shにq7(殿用語定義確認)を追加し、環境に埋め込む。 | infra | 04-04 | cmd_save.sh に q7_definition_ve |
| cmd_karo_reflux_1707 | context還流 — cmd_1702-1707研究結果のdm-signal-research.md更新 | dm-signal | 04-04 | L544-L540の5件をcontext/dm-signal |
| cmd_karo_gs_profile | GS速度最適化Phase 1b。軍師設計書(gunshi-gs-speed-optimization-design.md §2)に基づく。 パリティ基盤(cmd_1709)完了。次はプロファイリングでhot pathを特定する。 | dm-signal | 04-04 | oikaze cProfileをPATTERN_LIMIT= |
| cmd_karo_gs_benchmark_v2 | GS速度最適化Phase 1c。軍師設計書+軍師助言(PATTERN_LIMIT=100, timeout 5分/本, 段階的実行)反映版。 | dm-signal | 04-04 | 8スクリプトをPATTERN_LIMIT=100で計測し、g |
| cmd_karo_gs_tool_growth | 軍師SG10なぜなぜ結果: cmdのACに'research_engine.pyに追加せよ'が明示されていない。 cmd_1698で半蔵が自発的に追加したが再現性なし(忍者の意志依存)。 cmd_save.shにresearch cmdで新規関数定義時にengine統合ACを要求するチェックを追加。 | infra | 04-04 | cmd_save.shに研究cmd向け道具成長WARNING |
| cmd_karo_gs_kawarimi_profile | kawarimi(81分)が全体の75%。高速化最優先。ランブック§7: kawaramiは未プロファイル。 oikazeの知見がそのまま適用できる保証はない。まずcProfile取得。 | dm-signal | 04-04 | 指定の cProfile コマンドを実行し、早期終了を含む |
| cmd_karo_gs_oikaze_optimize | oikazeプロファイルで特定済みの3最適化対象を実装。ランブック§7。 パリティ検証(gs_parity_check.py)必須。 | dm-signal | 04-04 | oikazeの月次momentum計算とcache再利用を最 |
| cmd_karo_gs_kawarimi_opt | kawarimi(81分)が最大ボトルネック。前回プロファイルは既存出力ガードで即終了。 既存出力をリネーム→cProfile取得→hot path特定→最適化実装→パリティ検証。 | dm-signal | 04-04 | kawarimiのGS hot-pathで補助データ生成を遅 |
| cmd_karo_gs_nukimi_opt | nukimi(3.5分)もMomentumFilter系。oikazeと同構造の可能性。oikaze知見を横展開。 | dm-signal | 04-04 | nukimi の single-view momentum |
| cmd_karo_gs_kasoku_diff_opt | GS高速化 — kasoku_diff最適化(oikaze知見横展開) | dm-signal | 04-04 | kasoku_diff の GS context build |
| cmd_karo_gs_kasoku_ratio_opt | GS高速化 — kasoku_ratio最適化(oikaze知見横展開) | dm-signal | 04-04 | kasoku_ratio の GS serial hot p |
| cmd_karo_gs_yotsume_opt | GS高速化 — yotsume最適化(oikaze知見横展開) | dm-signal | 04-04 | yotsume の multi-view hot path |
| cmd_karo_gs_bunshin_opt | GS高速化 — bunshin最適化 | dm-signal | 04-04 | bunshin の hot path を最適化し、gs_pa |
| cmd_karo_gs_shijin_opt | GS高速化 — shin_shijin最適化 | dm-signal | 04-04 | shin_shijin_l1_gs.py の monthly |
| cmd_karo_gs_kawarimi_opt2 | kawarimi 81分の99.9%はserial pathのTrendReversalFilterBlock.execute未最適化。 yotsume(21.6倍)で実証済みの3最適化を適用。ランブック§7に具体指示あり。 | dm-signal | 04-04 | TrendReversalFilterBlock に yot |
| cmd_karo_gs_shared_cache | 軍師cmd案A。oikaze/nukimi/yotsumeにあるshared_momentum_cache(rebalance間再利用)を kawarimi/kasoku_diff/kasoku_ratioに横展開。3スクリプトは異なるファイル。 | dm-signal | 04-04 | shared_momentum_cacheをkawarimi |
| cmd_karo_gs_dict_lookup | 軍師cmd案B。momentum_filter.pyとsingle_view_momentum_filter.pyの get_momentum_value_at_date(bisect)をdict lookupに置換。2ファイルは独立。 | dm-signal | 04-04 | MomentumFilterBlock と SingleVi |
| cmd_karo_gs_shijin_cache | 軍師提案。shin_shijin(14.6分)のsimulate_strategy_vectorized Phase 1結果を lookback configキーでキャッシュ。同一キーはキャッシュ→Phase 2のみ実行。 | dm-signal | 04-04 | shin_shijin_l1_gs.pyにlookback |
| cmd_karo_gs_shijin_batch | 軍師分析: shin_shijin Phase 2が384s(50%)。NumPy行列演算バッチ化で40x→合計4.1x。 | dm-signal | 04-04 | Phase 2の月次リターン計算をunique signal |
| cmd_karo_gs_skip_verify | 軍師提案。3スクリプトに--skip-verifyフラグ追加。 期待: kawarimi 3.3分→数十秒、kasoku_diff 46s→~10s、kasoku_ratio 50s→~20s。 | dm-signal | 04-04 | 3本の忍法GSランナーに --skip-verify を追加 |
| cmd_karo_gs_shijin_skip_parity | GS高速化 — shin_shijin --skip-parityフラグ追加(7.7分→4.3分見込み) | dm-signal | 04-04 | --skip-parity 実行時にAC1スキップを明示表示 |
| cmd_karo_gs_shijin_parallel | GS高速化 — shin_shijin ProcessPool並列化(206s→58s見込み) | dm-signal | 04-04 | shin_shijin_l1_gs.py を family |
| cmd_karo_gs_shijin_full_batch | GS高速化 — shin_shijin Phase 2完全バッチ化(3.2分→1.1分見込み) | dm-signal | 04-04 | shin_shijin_l1_gs.py の family |
| cmd_1711 | 忍法GS結果(run_077_* 35万パターン)が全忍法分揃っている。 この既存データを深掘りし、パラメータ空間の構造を可視化する。 画像(ヒートマップ)で殿に報告する。 | dm-signal | 04-04 | 7忍法GS CSVを集約し、champion 7x6メトリク |
| cmd_1712 | CI赤が1日以上放置。E2E test#11「inbox delivery: nudge reaches mock_cli」が32秒タイムアウト。 フレーキーで片付けているがCI赤放置はgate信頼性低下。根本修正する。 | infra | 04-04 | — |
| cmd_1713 | 殿指示で発見したFLAIR手法を知識辞書に登録する。 4パラメータで710MパラメータのChronos-T5-Largeを上回る時系列予測手法。 GPU不要、numpy+scipy 654行。ハイパーパラメータ0個。 我々のdual momentum/FoF研究に応用可能性あり。 | dm-signal | 04-04 | FLAIR知識辞書を2層構造で追加し、methods/m17 |
| cmd_karo_fix_1711 | 軍師FAIL指摘3点: (1)CSV選択誤り(1186_*→246_*に修正) (2)AC1パラメータ空間ヒートマップ42枚未生成 (3)kawarimi legacy名使用。正しいCSVで全AC再実行。 | dm-signal | 04-04 | cmd_1711を再修正し、正しいGS入力でtop10/ch |
| cmd_1714 | 前処理研究9手法の結論がdm-signal/解釈層に未還流。次cmdで忍者が同じ轍を踏むリスク。 軍師設計案P1(gunshi-interpretation-layer-design.md §4)に基づき作成。 | dm-signal | 04-04 | preprocessing-research-conclus |
| cmd_1715 | 殿の裁定(PI-021/PI-009/パリティ条件等)がdm-signal/解釈層に未明文化。 忍者がPI違反実装→本番破壊のリスク。軍師設計案P2に基づき作成。 | dm-signal | 04-04 | production-invariants.mdを作成し、P |
| cmd_1716 | FLAIRの周期検出能力をDM-Signal研究ツールとして使う(殿発案)。 65 PFの月次リターンに周期構造があるか→どのlookback帯に効くかの検証基盤。 | dm-signal | 04-04 | FLAIR 65PF分析を実装し、Pテーブル・12ヶ月Sha |
| cmd_karo_codex_deploy_fix | 本セッションでhayate(Codex)に8回STALL。根因: deploy後の到達確認なし+respawn起動待ちなし。 LK028(Codex STALL根因)の自動化ターゲット3点を実装。 | infra | 04-04 | Codex ninja deployment reliabi |
| cmd_1717 | 軍師ランドスケープ分析でnukimi/kasoku_diffがoverfit HIGH判定(CAGR drop 33-34%)。 忍法GSのchampionパラメータがOOSで崩壊するか定量検証する。 道具(33倍速GS+パリティ基盤)が揃っている。 | dm-signal | 04-04 | cmd_1717 OOS検証を実装・実行し、5忍法のIS/O |
| cmd_1718 | FLAIR部品のDM-Signal応用を5方向で同時検証。絞らず全部やる(殿指示)。 cmd_1716のLevel/Shape結果を入力に、各部品の有効性を定量評価する。 | dm-signal | 04-04 | FLAIR 5部品検証を65PFで実行し、cmd_1718 |
| cmd_1719 | 殿発案: PFの今月の信頼度を予測する。ゼロベースの新アプローチ。 FLAIRのforecast(horizon=1, n_samples=200)で来月リターンの確率予測→ 期待リターン/不確実性=信頼度スコア。momentum(後ろ向き)とは根本的に異なる前向き判定。 | dm-signal | 04-04 | cmd_1719 FLAIR信頼度研究を実装・実行し、65P |
| cmd_1720 | FLAIR部品のDM-Signal応用第2サイクル。4方向を同時検証。 cmd_1716/1718/1719と合わせてFLAIR全応用を網羅する。 | dm-signal | 04-04 | FLAIR第2サイクル4検証を65PFで実行。cmd_172 |
| cmd_1721 | FLAIR検証で有効判定された3部品(Shapeゲート/LOO残差/Box-Cox)+信頼度top3が 特定PFに依存した結果ではなく一般的な特性かを検証する(殿指示)。 | dm-signal | 04-04 | cmd_1721 FLAIR有効部品の汎用性検証を実装・実行 |
| cmd_1722 | 全研究の共通構造「lookback帯域がSNRを支配」の検証。 FLAIRのLevel(ノイズ除去トレンド)でmomentumを計算し、Raw momentumとの精度差を測定。 Level系列は12ヶ月周期解像度(15-19点/PF)のため、月次比較は不可。 年次解像度での比較+動的lookback切替の原理検証を行う。 | dm-signal | 04-04 | cmd_1722完了。cmd_1716 Level CSVを |
| cmd_1723 | 殿発案: 新しいビルディングブロック=新しい忍法。 Levy & Lopes (2021) Dynamic Momentum Learningをselection blockとして実装・検証。 固定lookbackの構造的上限を超える。全研究の到達点(lookback帯域=SNR支配)の解。 | dm-signal | 04-04 | Levy DMA/DMS研究を65PFへ適用し、5条件比較・ |
| cmd_1724 | FLAIR研究(cmd_1716-1721)の結果が解釈層に未反映。38行のまま。 9検証+信頼度スコア+汎用性検証の結論を還流する。 | dm-signal | 04-04 | flair-interpretation.mdに§5-§8を |
| cmd_1725 | cmd_1722で年次Level momentum > Raw momentum(delta+0.020, N=14, 統計的確証なし)。 月次解像度で検証する。SSA(Singular Spectrum Analysis)で月次トレンドを抽出し、 そのトレンド系列でmomentumを計算→翌月実リターンとの精度比較。 | dm-signal | 04-04 | SSA(window=12)月次Level momentum |
| cmd_1726 | 軍師発案: PFレベルではなく基礎資産レベル(最上流)でノイズ除去。 前処理研究Phase 8「ノイズの源泉に近いほど効果大」の究極形。 10銘柄の日次/月次価格にSSA+FLAIRを適用→トレンド抽出→ そのトレンド価格でstandard PFのmomentumを再計算→精度比較。 | dm-signal | 04-04 | SSA(252)で13資産のトレンド成分を抽出し、65標準P |
| cmd_1727 | Levy論文の孫引き+引用先調査で発見した6論文が知識辞書に未登録。 adaptive lookback momentum研究の知識基盤を厚くする。 | dm-signal | 04-04 | methods/ に 6 件のモメンタム知識辞書を追加し、i |
| cmd_karo_fix_kb | 将軍検証指摘: (1)production-invariants.mdがmulti-agent-shogunに誤配置→DM-Signal移動 (2)cmd_1727追加指示3件が未登録 | dm-signal | 04-04 | production-invariants.md を DM- |
| cmd_1728 | 軍師なぜなぜ合成(gunshi-nazenaze-synthesis.md)の設計検証。 信号改善の天井確定→選択改善に全振り。Ward(多様性)×confidence(品質)×momentum(方向)+動的K。 | dm-signal | 04-04 | cmd_1728 の4段検証を実装・実行し、random v |
| cmd_1729 | 殿指示: 最強のALMを見つける。 Levy DMAの根本問題=目的関数がBinary(方向予測正解率)。IPヒートマップで1Mが支配的だが、 忍法GS/momentum top5では18Mが圧勝。「当てやすい」≠「儲かる」。 目的関数をBinary→CAGRランキング精度に変え、「儲かるlookback」を動的選択するALMを設計・検証。 | dm-signal | 04-04 | — |
| cmd_1730 | ALM研究で本番メトリクスを特徴量に使う。独自計算は本番と乖離するため禁止(殿指示)。 本番metrics_calculator.pyのロジックを研究スクリプトからimportできる道具を構築する。 research_engine(前処理研究)と同じパターン。道具が先。 | dm-signal | 04-04 | metrics_research_engine.py作成完了 |
| cmd_1732 | gate — gate_fire_logからテスト実行FAILを除外しメトリクス汚染解消 | infra | 04-04 | gate_report_format が /tmp テストレ |
| cmd_1733 | gate — autofix拡張: verdict自動導出+status自動更新(GP-107消火4問PASS) | infra | 04-04 | gate_report_autofix_main.py に |
| cmd_1734 | gate — 報告テンプレートにninja_weak_points gate_warningをフィールド直上に注入し学習ループを回す | infra | 04-04 | deploy_task.sh の報告テンプレート生成に ga |
| cmd_1735 | 研究 — ALM: 34メトリクス目的関数×24 lookback(1M~24M全部)動的選択 | dm-signal | 04-04 | 24 lookback版ALM研究を完了。1M-24M全固定 |
| cmd_1736 | 研究 — ALM top_n=1-10 × 24 lookback × 5 rolling窓 × 34メトリクス目的関数 | dm-signal | 04-04 | cmd_1736完了。ALM full sweep 1940 |
| cmd_1737 | 研究 — ALM OOS検証 3段構え(Stage0:3軸同時 + Stage1:50組合せ + Stage2:PBO) | dm-signal | 04-04 | cmd_1737実装・実行完了。cache欠損を自己修復し、 |
| cmd_1738 | gate — cmd_save.shに前段cmdパラメータ空間突合チェック追加(BLOCK) | infra | 04-04 | cmd_save.sh に前段 results.yaml の |
| cmd_1739 | 研究 — ALM OOS検証 全50組合せPBO + Stage0/1 (パラメータ縮小なし) | dm-signal | 04-04 | cmd_1739を実装し、ALM OOS Stage0-2を |
| cmd_karo_1739_cscv | 研究 — ALM OOS Stage0/1をCSCV 70組合せに拡張 | dm-signal | 04-04 | cmd_1739 Stage0/1をCSCV 70分割へ拡張 |
| cmd_1743 | 研究 — 既存124PF有限時間4指標一括計測 + L0/L1層別分布 | dm-signal | 04-05 | research_engine.pyに有限時間4指標(cal |
| cmd_karo_fix_1743 | 修正 — cmd_1743層別分類の修正(L0=standard全65体/L1=FoF全59体) | dm-signal | 04-05 | classify_layer関数をportfolio_typ |
| cmd_1744 | 研究 — ALM L0材料×既存L1パターンでFoF構築+既存ベースライン比較 | dm-signal | 04-05 | cmd_1744完了。ALM L0 4系列CSV・L1パター |
| cmd_1746 | 強化 — shutsujin_departure.shに--dry-runオプション追加 | infra | 04-05 | shutsujin_departure.sh に --dry |
| cmd_1747 | 研究 — 6目的関数ALM L0材料×忍法7本。Max Run-up以外の尖りでも効くか検証 | dm-signal | 04-05 | cmd_1747完了。6目的関数×4ファミリーのALM be |
| cmd_karo_score_wide | 研究 — ALMスクリプトscore_wide高速化(score_fn→numpy一括) | dm-signal | 04-06 | cmd_1735/1736 を score_fn から sc |
| cmd_1748 | 研究 — ALM L1 OOS検証。6目的関数×忍法7種=42パターンWF-OOS | dm-signal | 04-06 | 41/42 ROBUST。tail_contribution×加速RのみOVERFIT |
| cmd_1749 | 偵察 — ALM本番組込み。BEパイプライン+Admin CDP+ALMフック候補 | dm-signal | 04-06 | L0フロー全容把握。Hook A(fof)+FE UI分析+CDPスクショ |
| cmd_1750 | 偵察 — ALM Phase 3.7/4/4.5改修設計。recalculate_fast.py精読 | dm-signal | 04-06 | 2パス方式推奨。事前計算+月次選出+fullrecalc設計確定 |
| cmd_1751 | 偵察 — ALM盲点6件。保存バリデーション+cron+FoF連携+CDP実地 | dm-signal | 04-06 | FoF透過的OK。daily cron=mode=PORTFOLIO。fullrecalc自動cronなし |
| cmd_1752 | ALM impl cmd発令前に残る4つの未検証事項を埋める。 cmd_1750設計書の実現可能性を実コードで最終確認する。 | dm-signal | 04-06 | cmd_1752書込み競合偵察を完了。Pass2→Phase |
| cmd_1753 | なぜなぜ7回転で発見した4盲点を現物確認。全て5-10分のコード精読で済む。 | dm-signal | 04-06 | MTDはMonthlyReturnテーブルに混入する（意図的 |
| cmd_1754 | ALM設計知識が10ファイルに散在。/clear後に全エージェントが即使えるよう 1統合設計書にまとめ、projects/dm-signal.yaml+context §35にポインタを置く。殿直接指示。 | dm-signal | 04-06 | cmd_1754を完了。ALM統合設計書を新規作成し、§1- |
| cmd_1755 | 大元リポ(yohey-w/multi-agent-shogun)の最新アップデートから 我が軍にない3点の有用性を現物比較で判定する。 なぜなぜ7回転で絞り込んだ3点。 | infra | 04-06 | PR#113 guard.sh(6 hooks)と我が軍pr |
| cmd_1756 | 大元リポ(yohey-w) commit c87ca64のratelimit表示改善+SSH key改善を 我が軍のAndroidアプリ(v5.7)+ratelimit_check.shと比較し、取り込み価値を判定する。 | infra | 04-06 | cmd_1756偵察を完了。upstream c87ca64 |
| cmd_1757 | cmd_1754で作成された統合設計書(docs/research/alm-integration-design.md)に なぜなぜ追加回転で発見した6件の修正事項を反映する。 誤った数字(30分)と誤った前提(2パス=manual限定)を正す。 | dm-signal | 04-06 | alm-integration-design.md に指定6 |
| cmd_1758 | 大元リポ(yohey-w)のPR#113+skill-creator v2.0から 我が軍に不足する7件を取り込む。cmd_1755偵察で特定済み。 | infra | 04-06 | guard強化3件完了。G1:test_hooks.sh(7 |
| cmd_1760 | ALM目的関数の鉄壁方向が手薄（LTJ_invのみ）。 calmar/sortino/UWP/MDDの4つを新規ALM目的として検証し、 L0性能+L1忍法7種性能+既存シン忍法比較まで一気に出す。 殿直接指示。 | dm-signal | 04-06 | cmd_1760 sortino_ratio ALM L0+ |
| cmd_1761 | ALM忍法19体とシン忍法20体の全メトリクスを38指標で統一計算し、 忍法別比較表の空欄を全て埋める。 cmd_1760のcalmar/sortino目的でMaxDD/MRU/TC/NHF等が欠落していた問題を解消。 | dm-signal | 04-06 | 分身+追い風の旧/シン/ALM3世代・11体38メトリクス算 |
| cmd_1762 | ALM(Adaptive Lookback Momentum)本番組込みの第一弾。 スキーマにAlmConfig追加 + recalculate_fast.pyのPhase 3.7で ALM PFの全候補lookbackのmomentum cache + vectorized signalsを事前計算する。 設計書: docs/research/cmd_1750_alm_design.md (AC1+AC3前半) | dm-signal | 04-06 | ALM本番組込み第一弾(cmd_1762)を完了。AC1/A |
| cmd_1737_v2 | ALM OOS検証v2: 全50組合せPBO | dm-signal | 04-06 | — |
| cmd_1740 | ファミリー別Max Run-up ALM+ローリング相関 | dm-signal | 04-06 | — |
| cmd_1763 | ALM忍法の3目的関数（現行: MRU/calmar/UWP）が最適か検証する。 L2（Ward FoF等）はシン忍法20体+ALM忍法を材料に使う。 L2材料プール全体の多様性を最大化する3目的関数の組合せを、 6目的関数の既存データからデータドリブンで選定する。 | dm-signal | 04-06 | AC1: cmd_1761_full_metrics.yam |
| cmd_1764 | cmd_1763(6目的C(6,3)=20通り)の不完全分析を完全版に拡張。 cmd_1760データ(calmar/MaxDD/sortino/UWP)を追加し10目的関数でC(10,3)=120通り。 L2材料プール(シン20体+ALM)の多様性を最大化する3目的関数をデータドリブンで確定。 | dm-signal | 04-06 | AC1-4完了。90体×11メトリクス行列/120通りランキ |
| cmd_1765 | L1 ALM WFエンジン骨格。CSV読込+WF fold生成+ベクトル化メトリクス計算。DM2(119,493パターン)先行 | dm-signal | 04-07 | AC1-3完了。L1 ALM WFエンジン骨格実装。CSV読 |
| cmd_1773 | URGENT — ALM四神12体を本番で非表示にする | dm-signal | 04-07 | global_visibility_settings(id= |
| cmd_1777 | 道具磨き — 月次リターン計算pure function化 + ALMパリティ完全達成 | dm-signal | 04-07 | 月次リターン pure function を新設し、既存 c |
| cmd_1780 | 起動ゲートstale GP検知修正 + 孤立context統合 + 未commit push | infra | 04-07 | Gate11 dashboard完了GP除外+GP-137 |
| cmd_1781 | ALM 67窓速度最適化 — compute_metrics_np全量呼出し廃止 | dm-signal | 04-07 | cmd_1781_impl は将軍指示で中止。作業到達点とし |
| cmd_1783 | ハーネス — cmd起票時WHY→WHAT因果強制 + 範囲縮小検知 | infra | 04-07 | cmd_save.shにq8_why_what BLOCK+ |
| cmd_1774 | ALM四神L0パリティ検証 — 研究スクリプト vs 本番DB(12体) + momentum_data修正 | dm-signal | 04-07 | ALM L0パリティ検証PASS。momentum_data |
| cmd_1784 | ALM 67窓速度 — Pool並列+batch最適化で7忍法31秒以内 | dm-signal | 04-07 | — |
| cmd_1787 | URGENT修正 — FoF 23体Cash化バグ修正 + fullrecalculate + 本番復旧 | dm-signal | 04-07 | 3ブロックの月次FoF momentum cache loo |
| cmd_1788 | ALM四神リネーム — DM番号→四神名に統一 | dm-signal | 04-07 | ALM四神12体の portfolios.name を DM |
| cmd_1790 | ALM L1 38メトリクス — Phase A commit + Phase B vectorized系7メトリクス | dm-signal | 04-07 | Phase A を commit 1ff11495 で固定し |
| cmd_1786 | URGENT偵察 — FoF Cash化バグ根因特定。4/7 fullrecalculateで23FoFがCash化 | dm-signal | 04-07 | Level3 FoF(23体)が常時Cashを出す根本原因を |
| cmd_1791 | ALM L1 38メトリクス Phase C — MINIMIZE更新+select_champions整合+7忍法67窓全量実行 | dm-signal | 04-07 | select_champions_multi_is は 6 |
| cmd_1789 | ALM L1 38メトリクス拡張Phase A — PrefixMomentCache+prefix系14メトリクス | dm-signal | 04-07 | PrefixMomentCacheに4配列を追加し、down |
| cmd_1792 | ALM四神フォルダ作成 — 12体をALM四神フォルダに移動 | dm-signal | 04-07 | 本番Admin APIで ALM四神 フォルダを新規作成し、 |
| cmd_1776 | ALM L0パリティ修正 — 研究スクリプトのmonthly_return計算を本番と完全一致させる | dm-signal | 04-07 | 研究側の monthly_return 期待値計算を本番Op |
| cmd_1782 | ALM 67窓 — 34メトリクス全量prefix/vectorized化 + 7忍法5分以内 | dm-signal | 04-07 | 34メトリクス window fast path 化により |
| cmd_1785 | 軍師設計依頼 — compute_metrics_npを38メトリクス対応に拡張する設計 | dm-signal | 04-07 | — |
| cmd_1793 | ALM L1 WF分析 — 7忍法selection_timelineから忍法別ALM適性+モードラベル付与 | dm-signal | 04-07 | cmd_1791で生成した7忍法selection_time |
| cmd_1794 | 知識鮮度回復 — ALMチェックリスト+context+dashboard+CLAUDE.md実物同期 | dm-signal | 04-08 | checklist-alm-registration.md( |
| cmd_karo_fix_precommit_comment | pre-commit hookコメント行偽陽性修正 | infra | 04-08 | git-pre-commit.sh L49にコメント行除外g |
| cmd_1795 | ALM忍法Step 3準備 — 12体universe+結合CSV+全7本ALM対応+bunshin動作検証 | dm-signal | 04-08 | AC1: alm_l0_12.yaml+alm_l0_12_ |
| cmd_1796 | ALM忍法Step 3実行 — 残り6忍法を6忍者並列実行 | dm-signal | 04-08 | 6忍法(oikaze/nukimi/kawarimi/kas |
| cmd_karo_fix_neverstop_hang | never_stop_forにプロセスhang独立検証を追加 | infra | 04-08 | NEVER_STOP_DEFAULTS に 4 項目目として |
| cmd_karo_fix_gate_split_loop | GATE構造バグ2件修正 — 分割配備ACスコープ+auto_draft循環防止 | infra | 04-08 | cmd_complete_gate.shのassigned_ |
| cmd_1797 | チェックリスト改訂 — Step 3をIS窓動的選出フローに書き換え+GS完了記録 | dm-signal | 04-08 | checklist-alm-registration.md |
| cmd_1798 | ALM忍法Step 3b — WFエンジンをALM GSデータで実行し21体候補のselection_timeline生成 | dm-signal | 04-08 | WFエンジンALM 7忍法実行は完了。CSV_FILESを6 |
| cmd_1799 | ALM忍法Step 3b再実行 — WFエンジン67窓(--multi-is)で7忍法全量実行 | dm-signal | 04-08 | 7忍法全量--multi-is(IS=6-72M, 67窓) |
| cmd_karo_ci_fix | CI赤修正 — テスト失敗3グループ修正(setup_file/q8_why_what/proposal出力) | infra | 04-08 | CI失敗テスト4件修正。全811件PASS達成 |
| cmd_1800 | infra — lord_conversation loggerに殿のinput(inbound)を記録する | infra | 04-08 | AC1: log_terminal_input.shのdir |
| cmd_1801 | infra — cmd_save.sh消火判定gate(q9)追加 — 消火cmdの入口で真因記入を強制 | infra | 04-08 | cmd_save.shに消火cmd向けq9_firefigh |
| cmd_1804 | fix — cmd_save.sh q9磨き上げ — キーワード追加+意志依存prevention WARN | infra | 04-09 | cmd_save.shのq9判定語彙にバグ/bug/不具合/ |
| cmd_1805 | fix — q9意志依存パターンを語幹マッチに強化（活用形抜け修正） | infra | 04-09 | q9意志依存パターンを語幹マッチに変更。活用形(気をつけて/ |
| cmd_1807 | fix — deploy_task.shに消火判定gate追加（家老自発cmd経路のq9カバー） | infra | 04-09 | deploy_task.shにcheck_firefight |
| cmd_karo_fix_wa_yaml_dump | fix — gate_wa_data_quality.sh --fixモードのyaml.dump除去 | infra | 04-09 | gate_wa_data_quality.sh --fixモ |
| cmd_karo_gp177_keyword_lib | enhance — 消火キーワードリストをscripts/lib/に共通化（GP-177） | infra | 04-09 | scripts/lib/firefighting_keywo |
| cmd_1808 | fix — /clear前チェックhookをSessionEndに移設+ntfy通知化 | infra | 04-09 | SessionEnd clear check hookを追加 |
| cmd_1809 | fix — Androidアプリ エージェントpane全画面表示の初期スクロール位置を最下部にする | infra | 04-09 | PaneFullScreen初回表示時のスクロール位置を最下 |
| cmd_1810 | enhance — Androidアプリ エージェントpane入力UI改善（展開ボタン+特殊コマンド常時表示） | infra | 04-09 | PaneFullScreen入力バー改善3点を実装。AC1: |
| cmd_1811 | enhance — Androidアプリ メモ画面にGistファイル一覧表示を追加 | infra | 04-09 | GistファイルAPI連携+メモ画面UI追加をassembl |
| cmd_1812 | enhance — GATE CLEAR時に将軍idle検知→inbox通知で将軍が自動で完了に気づく | infra | 04-09 | cmd_complete_gate.sh の通常・emerg |
| cmd_1814 | fix — 将軍画面のSpecialKeysRowも常時表示にする | infra | 04-09 | ShogunScreen.ktのSpecialKeysRow |
| cmd_1815 | recon — Androidアプリ入力欄キーボード問題の根本原因特定（おしお殿コード全比較+Android公式調査） | infra | 04-09 | Android EdgeToEdge+keyboard ha |
| cmd_1816 | fix — Android keyboard問題根本修正 — NavigationBar.imePadding削除+Column.imePadding追加 | infra | 04-09 | NavigationBarのimePadding()をSho |
| cmd_1817 | ゴールデンデータ全量アップデート — 全136PFのmonthly_returns+holding_signal取得(タイムスタンプ付き) | dm-signal | 04-09 | AC2完了: 全active PF 136体(standar |
| cmd_1819 | ALM忍法 殿定義6目的 67窓L1 WF全量実行 — METRIC_NAMES変更+7忍法再実行 | dm-signal | 04-09 | METRIC_NAMESをcagr/nhf/maximum_ |
| cmd_1821 | 奥義-シン忍法 — シン忍法20体を材料にL2忍法GS+67窓WF実行 | dm-signal | 04-09 | AC1-AC4の技術作業は完了。シン忍法20体の本番DB月次 |
| cmd_1823 | 研究道具カタログ永続化 + cmd_save.sh道具明示チェック追加 | infra | 04-09 | AC1: dm-signal-ops.md §18に研究道具 |
| cmd_1826 | 偵察 — l1_alm_wf_engine.py メモリプロファイリング（468MB CSV→13GB膨張の根因特定） | dm-signal | 04-10 | l1_alm_wf_engine.py メモリ消費分析完了。 |
| cmd_karo_premise_check | fix — inbox_write.sh pre-send captureに★前提問い追加 | infra | 04-10 | inbox_write.sh L785の★10回問いecho |
| cmd_1827 | fix — l1_alm_wf_engine.py メモリ削減（PrefixMomentCache fold毎構築+float32化） | dm-signal | 04-10 | cmd_1827_impl再完了。deepdive第3弾の5 |
| cmd_1829 | fix — nukimi simulate_batch L3キャッシュ最適化（BATCH_CHUNK分割） | dm-signal | 04-10 | run_077_nukimi.py に BATCH_CHUN |
| cmd_1831 | new — GS並列ランナー(gs_runner.py)構築 | dm-signal | 04-10 | gs_runner.py新規実装完了(147行)。--uni |
| cmd_1835 | recon — kawarimi batch vs sequential md5不一致の根因調査 | dm-signal | 04-10 | TrendReversalFilterBlock.execu |
| cmd_1834 | recon — CSV I/Oボトルネック調査(GS書出し91%占有) | dm-signal | 04-10 | CSV書出し実装箇所特定・計測完了。kasoku_ratio |
| cmd_1832 | perf — pipeline関連heavy import lazy化(全7忍法) | dm-signal | 04-10 | 7忍法 run_077_*.py のpipeline関連mo |
| cmd_1838 | fix — deploy_task.sh commit check gitignore自動除外 | infra | 04-10 | deploy_task.shにgit check-ignor |
| cmd_1836 | perf — GS CSV書出しnumpy savetxt置換(pandas 270s→4.6s) | dm-signal | 04-10 | 7忍法のrun_077_*.pyの月次CSV書出しをnump |
| cmd_1837 | fix — kawarimi PYTHONHASHSEED非決定性修正(L78 sorted()) | dm-signal | 04-10 | TrendReversalFilterBlock L78をs |
| cmd_1842 | fix — GS run_077_*.py CSV出力時に.npyキャッシュ同時生成（キャッシュ不在ゼロ化） | dm-signal | 04-10 | 7忍法run_077_*.pyのwrite_monthly_ |
| cmd_1841 | fix — l1_alm_wf_engine.py load_data() numpy直読み化（pd.read_csv OOM根絶） | dm-signal | 04-10 | l1_alm_wf_engine.pyのcache-miss |
| cmd_1840 | fix — 奥義-シン忍法 大CSVキャッシュ生成+WF完走+チャンピオン選出 | dm-signal | 04-10 | AC1 PASS: nukimi/kasoku_ratio |
| cmd_1844 | 奥義-シン忍法 GS事後チャンピオン選出 — 3目的(CAGR/NHF/MaxDD)×7忍法 | dm-signal | 04-10 | GS CSV 7本全量確認完了。全パターン(合計195805 |
| cmd_1845 | 奥義-シン忍法 6メトリクス比較表 — GS事後 vs ALM方式 vs シン忍法(材料) | dm-signal | 04-10 | AC1 PASS: シン忍法20体全UUID存在確認(20/ |
| cmd_1846 | 奥義-シン忍法 忍法×忍法 組み合わせ有効性分析 — selection_timeline全21チャンピオン | dm-signal | 04-11 | 21体パラメータ一覧(AC1)、21本selection_t |
| cmd_1848 | 奥義-シン忍法 過適合検証2 — 期間分割OOS | dm-signal | 04-11 | cmd_1848完了。IS/OOS分割(前半75M/後半75 |
| cmd_1847 | 奥義-シン忍法 過適合検証1 — 近傍パラメータ安定性 | dm-signal | 04-11 | AC1 PASS: 21チャンピオンpattern_idから |
| cmd_1850 | 奥義-シン忍法 CPCV全方位分析 — L0/L1/L2の3層PBO+IS-OOS相関+分散+MinBTL | dm-signal | 04-11 | AC1: L0(四神12体)/L2(奥義シン忍法20体×7忍 |
| cmd_1851 | fix — ninja_monitor.sh CLI死活判定+自動再起動（OOM死亡2h放置防止） | infra | 04-11 | ninja_monitor.shにCLI死活判定+自動再起動 |
| cmd_1852 | 奥義-シン忍法 β調整α分析 — L0/L1/L2の3層でSPY/TQQQ/TECLベンチマーク比較 | dm-signal | 04-11 | AC1: SPY 195ヶ月/TQQQ 194ヶ月/TECL |
| cmd_1854 | ゴールデンデータ更新 — 本番DB全PF monthly_returns再取得 | dm-signal | 04-11 | 本番DB全PF monthly_returnsを取得しゴール |
| cmd_1856 | 奥義-シン忍法 残り20体 本番DB一括登録（登録のみ） | dm-signal | 04-11 | 20体の奥義FoFレコードを本番DBに正常登録(hide=t |
| cmd_1857 | fix — insight§14自走トリガー廃止+report templateデフォルト値追加 | infra | 04-11 | cmd_1857: §14自走トリガー廃止(AC1)+dep |
| cmd_1858 | fix — gate_shogun_startup.sh ALERT精度改良3件（false ALERT削減+actionable化） | infra | 04-11 | AC2(Gate17 oneshot除外)+AC3(Gate |
| cmd_1859 | perf — Gate15 orphan検知 git logバッチ化（GP-170） | infra | 04-12 | Gate15 orphanループ内のgit log個別呼出し |
| cmd_1862 | fix — archive_completed.sh TOCTOU競合修正 shogun_to_karo.yaml読込flock内移動（GP-182） | infra | 04-12 | archive_cmds()のQUEUE_FILE読込(ma |
| cmd_1861 | fix — deploy_task.sh STALE_RESET全パス実行+実行済みフラグ確認（GP-180+GP-181） | infra | 04-12 | reset_stale_fields()をresolve_c |
| cmd_1863 | ALM WF再実行 — MaxDD方向バグ修正後の全量再計算(バグデータ削除+再生成) | dm-signal | 04-12 | AC1完了(127件削除/87件指定範囲+40件スコープ外を |
| cmd_1864 | FE Compare SummaryにCalmar RatioとUWP(Underwater Period)を追加 | dm-signal | 04-12 | Compare SummaryページにCalmar列(高→低 |
| cmd_1865 | ALM忍法CPCV検証 — 7忍法×4ファミリー選択バイアス定量評価 | dm-signal | 04-12 | 既存の --alm-dm 24セルに加え、constrain |
| cmd_1866 | ALM忍法 全方位検証(7手法) — WF-OOS劣化率+β調整+超越条件+IS感度+指標感度+構成体数+SPA | dm-signal | 04-12 | cmd_1866 ALM忍法全方位検証7手法完了。8手法中5 |
| cmd_1868 | ALM×シン — ALM四神BBのGS CSVからchampion_selector固定選出(2×2因子分析) | dm-signal | 04-12 | ALM四神BB 7忍法×3目的=21チャンピオン選出完了。c |
| cmd_1867 | シン×ALM — シン四神BBのGS CSVをWFエンジンで動的選出(2×2因子分析) | dm-signal | 04-12 | l1_alm_wf_engine.py --batch-cs |
| cmd_1869 | 2×2因子分析 同一期間統一再計算(2015-03~2026-01, 130ヶ月) | dm-signal | 04-12 | cmd_1869 2×2因子分析完了。7忍法×6メトリクス× |
| cmd_1870 | 2×2因子分析 β調整版 — 同一期間4セルのα/β分離+β調整後CAGR比較 | dm-signal | 04-12 | 4セル×7忍法=28データポイントのβ/α/β調整後CAGR |
| cmd_1871 | L2奥義8パターン生成 Step1 — universe CSV作成+GS実行+②WF | dm-signal | 04-12 | — |
| cmd_1872 | L2奥義8パターン生成 Step2 — ③〜⑧選出+L2 2×2因子分析(β調整) | dm-signal | 04-12 | — |
| cmd_1873 | fix — SessionEnd hookのALERT判定を修正（cmd_pending/ninja_activeはINFO化） | infra | 04-12 | clear_prep_check.shのcmd_pendin |
| cmd_1874 | gate — MCP書込み時の殿帰属キーワード照合hook追加（研究出力→殿定義混同防止） | infra | 04-12 | cmd_1874: pre-mcp-lord-attribu |
| cmd_1875 | gate — MCP書込み時の設計情報/好み仕分けhook（設計パラメータはprojects/*.yamlへ誘導） | infra | 04-12 | pre-mcp-lord-attribution-guard |
| cmd_1877 | L2奥義 49ブロック完全直列 — 1忍者1忍法OOM防止 | dm-signal | 04-13 | ③3-5 kawarimi GS完了。270900パターン処 |
| cmd_1879 | WF出力上書きバグ修正後の3忍法WF再実行 — 並列配備 | dm-signal | 04-13 | ④4-1 bunshin WF再実行を完了。5成果物生成と忍 |
| cmd_1878 | L2奥義 8パターン全比較 — チャンピオン21体確認+2×2因子分析+傾向分析 | dm-signal | 04-13 | AC1+AC2を完了。8パターン全てで21体を確認し、168 |
| cmd_1880 | L2奥義168体 β調整検証 — 市場リスク分離+α算出 | dm-signal | 04-13 | AC1-AC4完了。168体をSPY共通期間(88-161ヶ |
| cmd_1881 | DM-Signal push修復 — git履歴から大ファイル除去+push | dm-signal | 04-13 | AC1完了(8ファイル履歴除去済み)。AC2でG2ゲートブロ |
| cmd_1882 | UWP定義修正 — 比較表+β調整表再生成+スプレッドシート更新 | dm-signal | 04-13 | AC1-AC4完了。UWPを本番定義(最大DDのpeak→r |
| cmd_1883 | GS再実行 — filter-repo消失3忍法×2パターン復旧 | dm-signal | 04-13 | cmd_1883の欠損GS成果物6本を確認し、未存在だったk |
| cmd_1884 | GS出力CSV命名統一 — _grid_results_fast/_grid_monthly_fast形式に統一 | dm-signal | 04-13 | cmd_1884対象4dirのGS出力CSVを_grid_* |
| cmd_karo_gp183_184 | GP-183/184実装 — commit check研究cmd免除+進行中月除外AC文言 | infra | 04-13 | deploy_task.sh の binary_checks |
| cmd_1885 | 偵察+修正 — 三層学習ループFAIL率分析+gate強化 | infra | 04-13 | gate_fire_log.yaml の22件中9件FAIL |
| cmd_1887 | 修正 — gate_shogun_startup.sh 2件の誤検知修正（inboundアーカイブ+AC段階配備） | infra | 04-13 | gate_shogun_startup.sh 誤検知2件修正 |
| cmd_1889 | 整備 — context鮮度WARN解消（dm-signal 3件+infrastructure 1件） | infra | 04-13 | AC1/AC2達成。context/infrastructu |
| cmd_karo_shouka2_wid | 消火撤去第2弾 — worker_id/parent_cmdファイル名推定を撤去 | infra | 04-13 | gate_report_autofix_main.pyからw |
| cmd_1888 | 消火撤去 — lessons_useful MISSING autofixをBLOCK化（消火→免疫転換） | infra | 04-13 | gate_report_autofix_main.pyのle |
| cmd_1890 | 消火撤去 — binary_checks result文字列正規化(PASS/ok→yes)を撤去しBLOCKに転換 | infra | 04-13 | autofix から PASS/ok/FAIL/ng の r |
| cmd_1891 | GP-186 — infra系shallow cmdのscout_exempt自動判定（cmd_save.sh改修） | infra | 04-13 | cmd_save.sh の q5 判定に infra+q4_ |
| cmd_1892 | GP-189 — lesson_write.shにtitle Jaccard類似度WARN追加（教訓重複検出） | infra | 04-13 | lesson_write.sh に title Jaccar |
| cmd_karo_gp110_deploy_warn | GP-110 — deploy_task.shに配備前重複チェック(自走commit検知WARN) | infra | 04-13 | deploy_task.sh に target_path の |
| cmd_1893 | L2奥義168体 パターン間相関分析 — ①(登録済み)vs②〜⑧の月次リターン相関構造 | dm-signal | 04-13 | AC1-AC3完了。168体を共通87ヶ月で揃えた相関分析を |
| cmd_1894 | L3奥義EW全量β調整 — 79万組み合わせでL2αを超えるL3があるか | dm-signal | 04-14 | — |
| cmd_karo_gs_vectorized | GS高速化 — gs_vectorized_subset.py本実装(3最適化+チャンク+verify) | dm-signal | 04-14 | gs_vectorized_subset.py に3最適化+ |
| cmd_1896 | L3 EW β調整 — 84体C(84,2)=3486通りのβ/α分離+L2α比較 | dm-signal | 04-14 | 3486ペアのL3 2体EW β調整を完了。L3最良α=13 |
| cmd_1897 | 奥義ALMシン 21体 本番DB登録 — ⑤(ALM-BB×シン忍法×GS固定)をhide=trueで登録 | dm-signal | 04-14 | okugi_alm_shin champions.json |
| cmd_karo_gp192 | GP-192 — パリティcmdテンプレートにtarget_date標準文言追加 | infra | 04-14 | inject_task_modifiers.pyにinjec |
| cmd_karo_gp191 | GP-191 — dict.get(target_date)禁止 pre-commit hook | dm-signal | 04-14 | scripts/run_precommit_checks.s |
| cmd_1899 | fix — FoF選択ブロック日付ミスマッチ修正(TRF dict.get→bisect)+潜在バグ2箇所+fullrecalculate+パリティ | dm-signal | 04-14 | dict.get(target_date)→get_mome |
| cmd_karo_ci_fix_1900 | CI赤修正 — test_cmd_save_ac_paths.bats T-002/T-004/T-005 unbound WARN_COUNT + stderr capture | infra | 04-14 | test_cmd_save_ac_paths.bats修正。 |
| cmd_1900 | fix — パリティスクリプト target_date修正 + 奥義ALMシン21体全量パリティ再検証 | dm-signal | 04-14 | cmd_1898 parity script の targe |
| cmd_1902 | L3 β調整 6指標拡張 — cmd_1896既存3486ペアにα版NHF/MaxDD/MRU/Calmar/UWP追加 | dm-signal | 04-14 | cmd_1902完了。cmd_1896互換の3486ペアCS |
| cmd_karo_gp190 | GP-190 commit check waive — scout_exempt/研究cmdのbinary_checksからcommit check除外 | infra | 04-15 | GP-190: scout_exempt=trueのcomm |
| cmd_1898 | 奥義ALMシン 21体 パリティチェック — holding_signal+monthly_return突合 | dm-signal | 04-15 | cmd_1898 parity実測完了。21体のうち hol |
| cmd_1903 | 将軍のcmd起票品質を構造的に引き上げる。Phase 31-32で11過ちが全てgateを通過した根因=「無知の知」がcmd起票に強制されていない。q10で検証済み空間の明示を強制し、q7を昇格し、研究cmd手順を追加する | infra | 04-15 | AC1(q10 WARNING), AC2(q7 dm-si |
| cmd_1906 | WARNINGは意志依存で壊れる。trust:unverifiedが残存するcmdをBLOCKし、sourceのファイルパス実在を検査することで、将軍の前提自己申告の嘘を構造的に防ぐ | infra | 04-15 | AC1: Check 20のtrust:unverified |
| cmd_1907 | cmd_1902の6指標α版3486ペアCSVからα-Calmar Top30を抽出し、モード混成(激攻×鉄壁)・忍法組合せ・奥義レベル構成の出現頻度を定量化する。Phase 32の発見(激攻+鉄壁混成がα安定性の構造的源泉)を数字で裏付ける | dm-signal | 04-15 | cmd_1902のalpha-Calmar Top30を抽出 |
| cmd_1908 | L3 α-Calmar Top30 Pareto最適ペア特定(6指標)。→殿指摘「なぜペアなの？3体の研究したよな」で車輪再発明に気づく | dm-signal | 04-15 | Pareto最適9/30件特定。しかし2体分析の重複。次は3体C(84,3) |
| cmd_1904 | 将軍cmd品質フィードバックループ — 軍師RC傾向の起動時可視化+verdict自動記録 | infra | 04-15 | gate_shogun_startup.shにRC傾向表示+cmd_design_quality verdict自動更新 |
| cmd_1905 | cmd前提明示 — assumptionsフィールド新設+trust検査+軍師review連携(なぜなぜ7回到達点) | infra | 04-15 | assumptions+trust WARNING。AC≧3のcmdで前提明示を促す |
| cmd_1909 | GP-194実装 — 分割配備時binary_checksをac_assigned範囲に制限 | infra | 04-15 | 配備中(小太郎) |
| cmd_1910 | テスト統合整理Phase1 — deploy_task.sh 16→7ファイル統合(軍師設計書準拠) | infra | 04-15 | 配備中(半蔵) |
| cmd_1912 | 強化 — assumptions未記入BLOCK化: AC≧3のcmdにassumptions必須化 | infra | 04-15 | Check 20でAC>=3のassumptions欠落をB |
| cmd_1913 | 強化 — 未コミット変更WARNに陣形図照合追加(cmd_1912誤キャンセル事故防止) | infra | 04-15 | cmd_save.shの未コミット変更警告に直近完了忍者一覧 |
| cmd_1911 | fix — CI RED修正: テスト並列化(--jobs 4)で露出した14テストの分離不足修正 | infra | 04-15 | 4テストファイルのsetup/teardownでBATS_T |
| cmd_1914 | 整備 — CoDDリファクタリング台帳作成+既存実績登録+軍師連携 | infra | 04-15 | CoDDリファクタリング台帳を新設し、既存3実績登録・inf |
| cmd_1915 | 強化 — q11_not_already_done: cmdの必要性検証BLOCK(車輪の再発明の原理的防止) | infra | 04-15 | cmd_save.sh に q11_not_already_ |
| cmd_1917 | 偵察 — cmd_save.sh CoDDプロファイリング(Phase 1): 関数レベルボトルネック特定 | infra | 04-15 | cmd_save.sh を隔離cloneで実測し、全体中央値 |
| cmd_1919 | 強化 — inbox_writeにaction_required引数追加(全エージェントデッドロック防止) | infra | 04-15 | scripts/inbox_write.sh に任意5引数 |
| cmd_1920 | 強化 — 掲示板システム導入: 全エージェント共有ボード+チェックボックス確認追跡 | infra | 04-15 | 共有掲示板を導入し、書込み/確認スクリプトと shogun・ |
| cmd_1916 | 強化 — q11自動検索: cmdの対象スクリプトとdocs/research/を自動照合(意志依存ゼロ層) | infra | 04-15 | cmd_save.shにcommandフィールドのスクリプト名自動抽出+docs/research grep+INFO表示 |
| cmd_1918 | fix — q11自動検索バグ修正(cmd_1916実装の動作不良修正) | infra | 04-15 | cmd_save.sh L298-336のq11自動検索ロジック修正 |
| cmd_1921 | fix — 掲示板requires_confirmationバグ修正+Q4形骸化防止(前セッション出来事注入) | infra | 04-15 | 作業中(影丸) |
| cmd_1922 | 強化 — 因果探索原則を将軍必読ファイルに追加(CLAUDE.md+startup gate) | infra | 04-15 | CLAUDE.md Step 2.55+gate存在チェック追加。テスト済み |
| cmd_1923 | cmd_save.sh Check 21: ACの数値絶対値WARN検出 | infra | 04-15 | cmd_save.shにCheck 21を追加し、AC de |
| cmd_1924 | Androidアプリ知識のcontext登録 — 存在するものを探せない問題の根因修正 | infra | 04-15 | context/infrastructure.md に An |
| cmd_karo_feedback_gap | fix — lesson feedback記録欠損の根因調査+修正 | infra | 04-15 | AC1: cmd_complete_gate.sh L403 |
| cmd_1926 | cmd_1924取消 — 各論パッチrevert | infra | 04-15 | cmd_1924で追加されたAndroid知識をcontex |
| cmd_1925 | 殿の全入力に確認リマインド注入 — 確認せずに回答する真因修正 | infra | 04-15 | 通常モードの additionalContext に `re |
| cmd_1927 | cmd_1925取消 — 確認なし起票のrevert | infra | 04-15 | cmd_1925で加えられた確認リマインド注入を撤去し、追加 |
| cmd_1930 | deepdive_causal_tracing Phase 6追記 — 人殺しの思想 | infra | 04-15 | deepdive_causal_tracing に Phas |
| cmd_karo_revert_1928_1930 | fix — cmd_1928/1930のgate_shogun_startup.sh変更をrevert | infra | 04-15 | gate_shogun_startup.shからcmd_19 |
| cmd_karo_revert_1928_1930_v2 | fix — revert不完全修正(deepdive Phase 6 + gate L750-753) | infra | 04-15 | Gate 18(lord_conversation inbo |
| cmd_karo_ci_fix_ga056 | fix — CI RED修正(gate_karo_startup.bats + cmd_save.bats テスト失敗4件) | infra | 04-15 | CI失敗テスト(test_cmd_save.bats×5件 |
| cmd_1933 | cmd_save.sh Check 10の作成cmd偽陽性修正。ファイル不在時に親ディレクトリが存在すれば作成対象としてINFO表示に降格し、親ディレクトリも不在ならBLOCK維持。cmd_1931/1932で2回連続BLOCKされた実害あり | infra | 04-15 | Check 10で親ディレクトリが存在する未作成パスをINF |
| cmd_1931 | 将軍の追体験品質が構造的に低い根因修正。家老(lessons_karo.yaml 55件)と軍師(lessons_gunshi.yaml 26件)にはdeepdive前に通読する具体的失敗データがあるが、将軍にはない。教訓の格納形式が出力の深さを決める(軍師分析)。lessons_shogun.yamlを作成し起動手順に組み込む | infra | 04-16 | lessons_shogun.yaml 20件を新設し、将軍 |
| cmd_1932 | 掲示板システムの引数順バグ修正+ライフサイクル管理追加。4エントリ中3件でcontent/posted_byが逆転。根因=引数順<posted_by> <content>がinbox_write.sh(<target> <content> ... <from>)と不一致でエージェントが間違える | infra | 04-16 | 掲示板の引数順バグを修正し、明示クローズ機能追加と既存3件の |
| cmd_karo_ci_fix_acpaths | CI RED修正 — test_cmd_save_ac_paths.bats更新コミット | infra | 04-16 | AC path test期待値を更新し、追加で露出したbul |
| cmd_1934 | 研究 — 3体EW全量探索: C(21,3)=1330通り×4手法β調整α6指標 | dm-signal | 04-16 | cmd_1934 実装完了。⑤_* 21列の3体1330通り |
| cmd_1935 | 整備 — context/codd.md新設: CoDD v1.8.0知識一元化 | infra | 04-16 | context/codd.mdを新設し、CLAUDE.md/ |
| cmd_karo_gp195_197 | GP-195+197統合 — gate_diagnose_check.shをgate_report_format.shに統合 | infra | 04-16 | gate_report_format.sh の FAIL 経 |
| cmd_karo_gp196 | GP-196 — 教訓注入絞込み 10→3件+IF-THEN構造化 | infra | 04-16 | deploy_task.sh の related_lesso |
| cmd_1936 | 強化 — gist作成時にインデックスgistを自動更新するスクリプト | infra | 04-16 | gist一覧の自動更新スクリプトと52+件実データの分類テス |
| cmd_karo_gp198 | GP-198 — Session State: タスクレベル失敗履歴引継ぎ | infra | 04-16 | GP-198実装完了。gate_report_format. |
| cmd_1937 | 整備 — context/ui-design-guide.md新設: 全エージェント共通UIデザインガイド | infra | 04-16 | Created context/ui-design-guid |
| cmd_1938 | 整備 — context/ui-design-guide.md補強: ボタンデザイン9tips+16tips統合 | infra | 04-16 | context/ui-design-guide.md に 1 |
| cmd_1939 | 強化 — scripts/cmd_save.sh L3診断推論: BLOCK時Diagnose MANDATORY+Session State | infra | 04-16 | cmd_save.shにDiagnose MANDATORY |
| cmd_1942 | 強化 — 忍者ACテストをaffected_tests.sh(関連テストのみ)に変更 | infra | 04-16 | deploy_task.shのテストAC生成で、全量unit |
| cmd_1941 | 強化 — GP/改善にbefore/after退化計測を義務化 | infra | 04-16 | GP/改善cmd向けreport templateにbefo |
| cmd_1940 | 強化 — gate_lesson_health.sh閾値をuseful率に変更+低効果教訓自動除外 | infra | 04-16 | gate_lesson_health.shにuseful率計 |
| cmd_1943 | 改修 — Androidアプリ ボトムナビ「メモ」→「Gist Index」差替え | infra | 04-16 | ボトムナビの「メモ」を「Gist Index」に差し替え、旧 |
| cmd_1945 | 修正 — Androidアプリ ライトテーマ文字コントラスト強化（殿フィードバック: ルール違反） | infra | 04-16 | DarkSengokuPalette の textMuted |
| cmd_1946 | verdict_override構造対策 — waive_ac正式機構 + 研究cmd commit check自動waive | infra | 04-16 | deploy_task.shに研究cmd/waive_ac用 |
| cmd_1947 | 研究 — N体EW比較: 1体/2体/3体 × 4手法 × 6指標 横並び分析 | dm-signal | 04-16 | cmd_1947完了。⑤_* 21列の1体21通り・2体21 |
| cmd_1948 | 研究 — N体EW比較(①×①): 1体/2体/3体 × 4手法 × 6指標 | dm-signal | 04-16 | cmd_1947を実行し、⑤_*21列の1体21通り・2体2 |
| cmd_1949 | 研究 — N体EW比較(①2⑤1): クロス 2体+3体(①多め) × 4手法 × 6指標 | dm-signal | 04-16 | ①×⑤クロス2体441通りと①①⑤の3体4410通りをcmd |
| cmd_karo_1948_retry | 研究 — N体EW比較(①×①) 再配備: load_monthly_returns引数化済み | dm-signal | 04-16 | ①_* 21列の1/2/3体EWを4手法×6指標で再計算し、 |
| cmd_1950 | 研究 — N体EW比較(①1⑤2): クロス 3体(⑤多め) × 4手法 × 6指標 | dm-signal | 04-16 | ①1⑤2の3体4410通りをcmd_1934同手法で算出し、 |
| cmd_1951 | 偵察 — インフラスクリプト全量プロファイリング+CoDD改善リスト作成 | infra | 04-16 | 全220本を計測・分類しCoDD改善リスト作成 |
| cmd_karo_ci_fix_cmd_save | CI修正 — cmd_save.shテスト期待値修正(BLOCKメッセージ形式変更対応) | infra | 04-16 | cmd_save の現行出力に合わせて 5 件の失敗テスト期 |
| cmd_1957 | CoDD改善#5 — gate_artifact_map.sh高速化(2.2s→目標400ms) | infra | 04-16 | gate_artifact_map.sh高速化完了。967m |
| cmd_1954 | CoDD改善#2 — dashboard_auto_section.sh高速化(2.8s→目標500ms) | infra | 04-16 | dashboard_auto_section.sh を高速化 |
| cmd_1953 | CoDD改善#1 — shutsujin_departure.sh高速化(2.4s→目標500ms) | infra | 04-16 | scripts/shutsujin_departure.sh |
| cmd_1956 | CoDD改善#4 — report_merge.sh高速化(1.9s→目標300ms) | infra | 04-16 | report_merge.sh: 1ファイルあたり4-5回の |
| cmd_1955 | CoDD改善#3 — gate_cycle_health.sh高速化(2.6s→目標500ms) | infra | 04-16 | gate_cycle_health.sh を 793ms→2 |
| cmd_1958 | CoDD改善#6 — gate_karo_startup.sh高速化(1.1s→目標300ms) | infra | 04-16 | gate_karo_startup.sh高速化完了。befo |
| cmd_1960 | CoDD改善#8 — inbox_write.sh高速化(89ms→目標40ms) | infra | 04-16 | inbox_write.shを高速化。agent_confi |
| cmd_1961 | CoDD改善#9 — ntfy.sh高速化(130ms→目標50ms) | infra | 04-16 | ntfy.sh高速化: before 33ms→after |
| cmd_1959 | CoDD改善#7 — gate_recalculate_completeness.sh高速化(4.0s→目標500ms) | infra | 04-16 | gate_recalculate_completeness. |
| cmd_1963 | CoDD改善#11 — gate_loop_health.sh高速化(493ms→目標100ms) | infra | 04-16 | gate_loop_health.sh 287ms→93ms |
| cmd_1964 | CoDD改善#12 — gate_lesson_health.sh高速化(228ms→目標50ms) | infra | 04-16 | gate_lesson_health.sh を 666ms |
| cmd_1962 | CoDD改善#10 — lesson_effectiveness.sh高速化(5.5s→目標500ms) | infra | 04-16 | lesson_effectiveness.sh高速化: ba |
| cmd_1966 | CoDD改善#14 — report_field_set.sh高速化(40ms×73回→目標15ms) | infra | 04-16 | report_field_set.shを高速化し、scala |
| cmd_1965 | CoDD改善#13 — ninja_done.sh高速化(68ms×104回→目標30ms) | infra | 04-16 | ninja_done.sh を軽量化し、usage/help |
| cmd_1970 | CoDD改善#18 — gate_workaround_rate.sh高速化(135ms×14回→目標40ms) | infra | 04-16 | gate_workaround_rate.sh高速化: py |
| cmd_1972 | CoDD改善#20 — parity_check.sh高速化(5.5s timeout→目標500ms) | infra | 04-16 | parity_check.sh に --help fast- |
| cmd_1974 | CoDD改善#22 — post_recalculate_checks.sh高速化(5.5s timeout→目標500ms) | infra | 04-16 | post_recalculate_checks.shをCRL |
| cmd_1975 | CoDD改善#23 — test_hooks.sh高速化(4.0s timeout→目標500ms) | infra | 04-16 | test_hooks.shを共通evaluator直呼びへ変 |
| cmd_1976 | CoDD改善#24 — gate_vercel_phase.sh高速化(481ms×7回→目標100ms) | infra | 04-16 | gate_vercel_phase.sh高速化完了。norm |
| cmd_1969 | CoDD改善#17 — pre_compact_save.sh高速化(141ms×毎compaction→目標40ms) | infra | 04-16 | pre_compact_save.sh高速化完了。jq×2→ |
| cmd_1977 | CoDD改善#25 — cmd_save.sh高速化(4.0s→目標500ms) | infra | 04-16 | cmd_save.sh高速化結果を記録。warm media |
| cmd_1978 | CoDD改善#26 — stop-lint-gate.sh高速化(3.0s→目標500ms) | infra | 04-16 | Stop hookの changed-file 取得を Gi |
| cmd_1980 | CoDD改善#28 — gate_recalculate_completeness.sh再トライ(2.74s→目標500ms) | infra | 04-16 | gate_recalculate_completeness. |
| cmd_1984 | CoDD改善#32 — gate_karo_startup.sh再トライ(225ms→目標80ms, 起動ごと) | infra | 04-16 | gate_karo_startup.sh 3改善: pyth |
| cmd_1983 | CoDD改善#31 — deploy_task.sh再トライ(88ms→目標30ms, 配備ごと) | infra | 04-16 | deploy_task.sh generate_report |
| cmd_1981 | CoDD改善#29 — dashboard_auto_section.sh再トライ(340ms→目標100ms, ×21回) | infra | 04-16 | dashboard_auto_section.shの第2次高 |
| cmd_karo_ci_fix_1987 | CI RED修正 — test_stop_lint_gate.bats test 941 HASH_FILE未生成 | infra | 04-17 | bats --jobs 8並列実行でHASH_FILEが/t |
| cmd_karo_context_freshness_1993 | context鮮度更新 — dm-signal-research.md+infrastructure.md | infra | 04-17 | context鮮度更新2件を反映し、対象2ファイルのみをコミ |
| cmd_karo_1995_fix | cmd_1995補足 — compare_snapshots.py holding_signal空振り修正+列名統一 | dm-signal | 04-17 | compare_snapshots.pyのholding_s |
| cmd_1994 | Phase 4準備① — fullrecalculate cProfile計測(read-only) | dm-signal | 04-17 | recalculate_fast.py fullrecalc |
| cmd_karo_ci_fix_f821 | CI RED修正 — run_077_yotsume.py F821(未定義変数)解消 | dm-signal | 04-17 | run_077_yotsume.py F821/F841/B |
| cmd_karo_gp190_fix | GP-190バグ修正 — scout_exemptがcommit checkを消す問題解消 | infra | 04-17 | deploy_task.sh修正: scout_exempt |
| cmd_1998 | Phase 4偵察 — fullrecalculate cache miss/fallback/N+1実測 | dm-signal | 04-17 | Phase4 cache/miss偵察を完了。signal_ |
| cmd_1999 | インフラ改善 — cmd_delegate.sh gate先行送信化(レースコンディション防止) | infra | 04-17 | cmd_delegate の gate FAIL分岐を実装・ |
| cmd_karo_ci_fix_blt72 | CI RED修正 — test_bulletin_board.bats test 72修正 | infra | 04-17 | bulletin_confirm.sh の if rc: ガ |
| cmd_karo_gp210_fix | GP-210修正 — inbox_watcher STATE_DIRパス不一致解消 | infra | 04-17 | restart_watchers.shの3箇所からSHOGU |
| cmd_2000 | Phase 4偵察② — fullrecalculate SQLクエリログ分類+top10重クエリ特定 | dm-signal | 04-17 | SQLAlchemy queryロギングをcmd_1994ハ |
| cmd_2003 | Phase 4偵察④ — fullrecalculate DB呼出のループ構造現物確認 | dm-signal | 04-17 | expand_portfolio_to_tickersの直呼 |
| cmd_2002 | Gist Index分類改善 — gist_index_update.sh classify_gist()を10カテゴリに再設計 | infra | 04-17 | gist_index_update.shのCATEGORY_ |
| cmd_2005 | Phase 4偵察⑤ — B1 preload変更のFE/UI影響範囲確認+設計書追記 | dm-signal | 04-17 | preload条件は monthly_return 値を変え |
| cmd_karo_ci_fix_ga091 | CI RED修正(GA-091) — gist_index_updateテスト期待値を新カテゴリ体系に更新+CATEGORY_ORDER修正 | infra | 04-17 | gist_index_update.sh のカテゴリ体系を新 |
| cmd_karo_ci_fix_ga092 | CI RED修正(GA-092) — cmd_delegate inbox_write失敗時のexit code修正 | infra | 04-17 | cmd_delegate の inbox_write失敗仕様 |
| cmd_2007 | Phase 4事前確認 — preload動作3パターン記録(standardPF/FoF/nestedFoF) | dm-signal | 04-17 | 代表3体(standard/FoF/nestedFoF)を |
| cmd_2008 | Phase 4 golden data化 — cmd_2007スナップショットを全改善cmdのパリティ基準に固定 | dm-signal | 04-17 | golden baseline固定・設計書作成・compar |
| cmd_2009 | Phase 4設計書更新 — §3全改善項目にgolden dataパリティ基準を明記 | dm-signal | 04-17 | §3の5改善項目と§6.4 golden data節を設計書 |
| cmd_2010 | インフラ修正 — cmd初期statusをdraftに変更(gate未通過配備防止) | infra | 04-17 | — |
| cmd_2006 | Phase 4 B1 impl — monthly_returns preload条件変更(N+1解消) | dm-signal | 04-17 | monthly_returns の FoF partial- |
| cmd_1997 | Phase 4準備②補足 — compare_snapshots.py列名不一致修正 | dm-signal | 04-17 | compare tool修正はbranch履歴に存在しpus |
| cmd_2011 | Phase 4設計書更新 — B1実測反映+本番baseline計測位置づけ明記 | dm-signal | 04-17 | Phase4設計書更新完了 |
| cmd_2001 | Phase 4偵察③ — Render上cProfile計測(純Python時間取得) | dm-signal | 04-17 | Render cProfile結果を docs/resear |
| cmd_2012 | Phase 4偵察⑥ — DELETE FROM signals 2505s(77%)の真因特定 | dm-signal | 04-17 | signals cleanup経路を特定し、DELETE条件 |
| cmd_2013 | Phase 4偵察⑦ — fullrecalculate PF×date網羅性検証(UPSERT化可否判定) | dm-signal | 04-17 | full recalcのPF取得・date範囲・inacti |
| cmd_2016 | Phase 4偵察⑨ — スキーマドリフト修正方法確認(CASCADE本番未反映) | dm-signal | 04-17 | 本番DB FK制約 vs models.py宣言の差分を全件 |
| cmd_2014 | Phase 4 C1 spec作成 — cleanup UPSERT化の影響範囲設計+他テーブルDELETE時間確認 | dm-signal | 04-17 | C1 UPSERT specを新規作成し、signals D |
| cmd_2018 | Phase 4 A2 CoDD spec — _generate_trade_performance ベクトル化設計 | dm-signal | 04-17 | A2 vectorize specを新規作成し、5候補の変更 |
| cmd_2019 | Karpathy Simplicity導入 — 軍師review_log+忍者報告テンプレートに自問追加 | infra | 04-17 | gunshi_review_log headerとdeplo |
| cmd_2017 | Phase 4 C1 impl — signals cleanup DELETE→UPSERT化(fullrecalc 77%削減) | dm-signal | 04-17 | signals cleanup DELETEをskipしてP |
| cmd_2020 | Phase 4設計書v3.0更新 — C面追加+B1/C1実測反映+Render cProfile統合+次ステップ計画 | dm-signal | 04-17 | Phase 4設計書をv3.0三面作戦の完了状態へ同期し、C |
| cmd_2021 | Phase 4 C1後Render本番計測 — 新ベースライン確定+self time分析 | dm-signal | 04-17 | C1をmainへmerge(PR #12)してRender本 |
| cmd_2022 | Phase 4締め括り — 設計書v3.1最終更新+研究日誌Phase 34追記+成果サマリ | dm-signal | 04-17 | Phase 4設計書にcmd_2021の実測値(842.90 |
| cmd_2024 | L3選出(正確版) — 2体EWプール861通り+3体EWプール10150通りから3目的×Top1=6体 | dm-signal | 04-17 | 2体/3体EWプールからWF α 3目的のTop1候補6体を |
| cmd_2025 | L3秘奥義6体 本番登録 — フォルダー作成+FoF登録+hide+fullrecalculate+パリティ | dm-signal | 04-17 | 秘奥義6体の本番登録・folder hide・fullrec |
| cmd_2026 | ⑤奥義-ASS忍法 リネーム+フォルダー整理 — 21体のPF名変更+新フォルダー作成+移動 | dm-signal | 04-18 | 奥義ALMシン21体を奥義-ASS-{}形式へ改名し、新規フ |
| cmd_2027 | ①奥義-SSS忍法 リネーム+フォルダー整理 — 21体のPF名変更+新フォルダー作成+移動 | dm-signal | 04-18 | 奥義-シン忍法フォルダーとplain奥義21体を奥義-SSS |
| cmd_2028 | p̄バッチ実行 — 全active PFの劣化指標+p̄一括再計算 | dm-signal | 04-18 | 本番 deterioration-batch を実行し、秘奥 |
| cmd_2029 | 偵察 — 全184PFのp̄/Z統計量分布調査+q̄(好調指標)設計材料 | dm-signal | 04-18 | 184 active PFのp_bar+Z(6/12/24) |
| cmd_2030 | 研究 — ルックバック期間別IC分析(1M-12M) — 特徴量としてのモメンタム効果量 | dm-signal | 04-18 | 本番 monthly_return_open を用いて ac |
| cmd_2031 | 研究 — L3モメンタムローテーション全量バックテスト(LB 1-12M × Top 1-42 = 504通り) | dm-signal | 04-18 | L2奥義42体(ASS21+SSS21)の月次リターンを本番 |
| cmd_2032 | 偵察 — L3秘奥義6体パフォーマンス取得+cmd_2031モメンタムBestとの比較 | dm-signal | 04-18 | 秘奥義6体EWとcmd_2031主要4パターンの同条件比較を |
| cmd_2033 | CoDD改善バッチ6-A — insight_write.sh + gate_shogun_memory.sh + gate_skill_quality.sh | infra | 04-18 | 3本のCoDD改善を完了。insight_write 117 |
| cmd_2036 | CoDD改善バッチ7-B — lesson_write.sh + sync_lessons.sh + inbox_write.sh(再) | infra | 04-18 | lesson_write/sync_lessons/inbo |
| cmd_2035 | CoDD改善バッチ7-A — cmd_save.sh(再) + ninja_done.sh(再) + shutsujin_departure.sh(再) | infra | 04-18 | cmd_save.sh 1.06s→0.98s、ninja_ |
| cmd_2038 | CoDD改善バッチ8-B — gate_report_format.sh + yaml_field_set.sh + gate_pd_sync.sh | infra | 04-18 | gate_report_format/yaml_field_ |
| cmd_2037 | CoDD改善バッチ8-A — gate_karo_startup.sh(再) + gate_gunshi_cs_checklist.sh + gate_field_get.sh | infra | 04-18 | gate_karo_startup.sh・gate_guns |
| cmd_2039 | CoDD改善バッチ9-A — stop-lint-gate.sh(再) + gate_recalculate_completeness.sh(再) + git-pre-commit.sh | infra | 04-18 | stop-lint-gate を status v2+awk |
| cmd_2048 | CoDD改善バッチ13-B — mark_no_learning.sh + log_terminal_input.sh + statusline.sh | infra | 04-18 | infra小物3本を高速化し、mark_no_learnin |
| cmd_2046 | CoDD改善バッチ12-B — cmd_quality_log.sh + task_deploy.sh + log_terminal_response.sh | infra | 04-18 | cmd_quality_log.sh(26ms→~11ms, |
| cmd_2043 | CoDD改善バッチ11-A — lesson_harvest.sh(再) + post_recalculate_checks.sh(再) + model_switch_preflight.sh(再) | infra | 04-18 | lesson_harvest/post_recalculat |
| cmd_2045 | CoDD改善バッチ12-A — gate_report_autofix.sh + gate_dc_duplicate.sh + gate_cmd_state.sh | infra | 04-18 | gate_report_autofix/gate_dc_du |
| cmd_2049 | CoDD改善バッチ14-A — session_start_inject.sh + prompt_state_inject.sh + session_end_clear_check.sh | infra | 04-18 | session系hook 3本を高速化し、session_s |
| cmd_2047 | CoDD改善バッチ13-A — gate_diagnose_check.sh + gate_silent_fallback.sh + gate_mcp_access.sh | infra | 04-18 | gate_diagnose_check/silent_fal |
| cmd_2050 | CoDD改善バッチ14-B — bash_state_hook.sh + test_result_guard.sh + pre-write-report-deny.sh | infra | 04-18 | bash_state_hook.sh(36ms→~16ms, |
| cmd_2052 | CoDD改善バッチ15-B — gate_recalculate_completeness.sh(再々) + lesson_write.sh(再) + shutsujin_departure.sh(再々) | infra | 04-18 | 3本のスクリプトをCoDD再々/再改善完了。gate_rec |
| cmd_2044 | CoDD改善バッチ11-B — archive_completed.sh(再) + report_merge.sh(再) + parity_check.sh(再) | infra | 04-18 | archive_completed.sh(783ms→550 |
| cmd_2057 | CoDD spec補完(5/8) — gate_cmd_state.sh + bash_state_hook.sh + test_result_guard.sh | infra | 04-18 | CoDD spec 3本作成(gate_cmd_state/ |
| cmd_2056 | CoDD spec補完(4/8) — gate_mcp_access.sh + gate_report_autofix.sh + gate_dc_duplicate.sh | infra | 04-18 | gate_mcp_access/gate_report_au |
| cmd_2058 | CoDD spec補完(6/8) — pre-write-report-deny.sh + cmd_quality_log.sh + task_deploy.sh | infra | 04-18 | CoDD spec補完(6/8)完了。3本全specをdoc |
| cmd_2053 | CoDD spec補完+悪化revert — stop-lint-gate revert + spec省略21件の正規CoDDやり直し(1/8) | infra | 04-18 | cmd_2053 の CoDD 正規化を実施し、3本の sp |
| cmd_2054 | CoDD spec補完(2/8) — parity_check.sh + gate_recalculate_completeness.sh + lesson_write.sh | infra | 04-18 | cmd_2054 の対象3本について CoDD spec を |
| cmd_2055 | CoDD spec補完(3/8) — shutsujin_departure.sh + gate_diagnose_check.sh + gate_silent_fallback.sh | infra | 04-18 | CoDD spec補完3本完了。shutsujin_depa |
| cmd_2060 | CoDD spec補完(8/8) — inbox_mark_read.sh + 悪化防止gate追加 | infra | 04-18 | AC1: inbox_mark_read.sh CoDD s |
| cmd_2059 | CoDD spec補完(7/8) — log_terminal_response.sh + agent_config.sh + field_get.sh | infra | 04-18 | cmd_2059対象3本のCoDD spec補完は既に co |
| cmd_2062 | CoDD正規改善(忍者hook B) — pre-write-edit-combined.sh + post-write-edit-combined.sh + pre-write-read-tracker.sh | infra | 04-18 | write/edit/read系 hook 3本を正規CoD |
| cmd_2064 | CoDD正規改善(忍者通知) — report_field_set.sh(再) + inbox_write.sh(再) | infra | 04-18 | report_field_set.sh+inbox_writ |
| cmd_2063 | CoDD正規改善(忍者完了処理) — ninja_done.sh(再) + gate_report_format.sh(再) + post-search-completeness-guard.sh | infra | 04-18 | 3スクリプトCoDD正規改善完了。gate_report_f |
| cmd_2061 | CoDD正規改善(忍者hook A) — stop-lint-gate.sh + pre-bash-combined.sh + post-bash-combined.sh | infra | 04-18 | hook A 3本を正規 CoDD で再評価し、Before |
| cmd_2065 | stop-lint-gate.sh L3診断推論改善 — Session State付き正規CoDD(失敗履歴注入) | infra | 04-18 | stop-lint-gate.sh を L3診断推論 + S |
| cmd_2051 | CoDD改善バッチ15-A — cmd_save.sh(再々) + stop-lint-gate.sh(再々) + gate_karo_startup.sh(再々) | infra | 04-18 | cmd_2051 は部分完了。cmd_save.sh の w |
| cmd_2067 | 研究 — CoDD #5深堀り+本家リポジトリ分析 — 我が軍への応用拡張 | infra | 04-18 | CoDD #5記事と codd-dev 公開実装を深掘りし、 |
| cmd_2069 | CoDD拡張 P5 — context/codd.md索引同期(GP-198/200/201現状反映) | infra | 04-18 | context/codd.md の索引を 2026-04-1 |
| cmd_2070 | CoDD拡張 P2 — DIVERGENT v2: 仮説一致検知 | infra | 04-18 | DIVERGENT判定を prior_attempts[] |
| cmd_2072 | CoDD拡張 P4 — partial failure surfacing: verdict第三状態(PASS_NO_IMPROVEMENT)導入 | infra | 04-18 | gate_report_format_main.pyにPAS |
| cmd_karo_ci_fix_571 | CI RED修正 — test_gate_ninja_workaround_rate #571(再修正) | infra | 04-18 | テスト571（gate_ninja_workaround_r |
| cmd_karo_ci_fix_2066 | CI RED修正 — test_assumption_invalidation(3件) + test_cmd_save(1件) + test_pending_decision(1件) | infra | 04-18 | 6件のCIテスト失敗を修正。gate_report_form |
| cmd_karo_ci_fix_568 | CI RED修正 — test_gate_ninja_workaround_rate #568 | infra | 04-18 | gate_ninja_workaround_rate.shの |
| cmd_2075 | CoDD正規再改善 R1-C — revert retry Bash hooks 3本(combined+search-guard) | infra | 04-18 | pre-bash-combined(jq→awk, guar |
| cmd_karo_ci_fix_ssh_sl | CI RED修正: SSH/SLテスト(999-1006)CI環境FAIL | infra | 04-18 | unit-tests workflow の再実行でも SSH |
| cmd_2077 | CoDD正規再改善 R1-E — cmd_save.sh(spec省略→正規CoDD再改善) | infra | 04-18 | scripts/cmd_save.sh正規CoDD再改善。b |
| cmd_2090 | CoDD正規再改善 R2-C — gate_vercel_phase.sh(spec省略→正規CoDD再改善) | infra | 04-18 | gate_vercel_phase.sh を正規CoDDで再 |
| cmd_2078 | CoDD正規再改善 R1-F — deploy_task.sh(spec省略→正規CoDD再改善) | infra | 04-18 | deploy_task.sh CoDD正規再改善完了。hot |
| cmd_2081 | CoDD正規再改善 R1-I — dashboard_auto_section.sh(spec省略→正規CoDD再改善) | infra | 04-18 | dashboard_auto_section.sh 3fix |
| cmd_karo_sleep_fix | ninja_monitor.sh sleep -5エラー修正 — codex confirm_waitデフォルト値追加 | infra | 04-18 | ninja_monitor.sh L3060付近: code |
| cmd_2088 | CoDD正規再改善 R2-A — gate_cycle_health.sh(spec省略→正規CoDD再改善) | infra | 04-18 | gate_cycle_health.sh CoDD正規再改善 |
| cmd_karo_ci_fix_cli_lookup | CI赤修正 — cli_lookup.sh _cli_lookup_profile_getが空行でbreak | infra | 04-18 | cli_lookup が profile間の空行で code |
| cmd_2084 | CoDD正規再改善 R1-L — report_merge.sh(spec省略→正規CoDD再改善) | infra | 04-18 | report_merge.sh を mawk優先化し、rea |
| cmd_2085 | CoDD正規再改善 R1-M — archive_completed.sh(spec省略→正規CoDD再改善) | infra | 04-18 | archive_completed.sh CoDD正規再改善 |
| cmd_2086 | CoDD正規再改善 R1-N — lesson_harvest.sh(spec省略→正規CoDD再改善) | infra | 04-18 | lesson_harvest.sh CoDD正規再改善: T |
| cmd_karo_precommit_yaml_dump_fp | pre-commit yaml.dumpチェックのfalse positive修正 | infra | 04-18 | pre-commitのyaml.dump誤検知をpre_ba |
| cmd_2080 | CoDD正規再改善 R1-H — inbox_write.sh(spec省略→正規CoDD再改善) | infra | 04-18 | inbox_write.sh write path を再改善 |
| cmd_2092 | CoDD正規再改善 R2-E — gate_workaround_rate.sh(spec省略→正規CoDD再改善) | infra | 04-18 | gate_workaround_rate.sh CoDD正規 |
| cmd_2091 | CoDD正規再改善 R2-D — gate_loop_health.sh(spec省略→正規CoDD再改善) | infra | 04-18 | gate_loop_health.sh CoDD正規再改善: |
| cmd_2093 | insightノイズ除去 — 生成時自動done化 + cleanカテゴリALERT除外 | infra | 04-18 | insightノイズの上流生成を停止。auto-done/S |
| cmd_2094 | 偵察+実装 — 他システム知識辞書 一次知識層作成 (6システム並列調査) | infra | 04-19 | AC4完了。知識辞書一次層作成 |
| cmd_karo_ci_fix_ga116 | CI修正 — test_cmd_save.bats 8テスト失敗修正 | infra | 04-19 | CI修正完了。abort_if_block_immediat |
| cmd_2098 | 実装 — AI開発知識辞書 鮮度チェックgate (CoDDドキュメント適用Phase1) | infra | 04-19 | 知識辞書verified_at鮮度gateを追加し、将軍st |
| cmd_2100 | 実装 — AI開発知識辞書 落とし穴+相互参照の補完 (全エントリ) | infra | 04-19 | ace/vercel/gsd に Pitfalls/Cros |
| cmd_karo_ci_fix_ga117 | CI修正 — test_cmd_save.bats 5テスト失敗(BLOCK集約副作用) | infra | 04-19 | cmd_save.shの2箇所を修正: (1)q5 elif |
| cmd_2102 | 改善 — gate_shogun_startup.sh CoDD再改善 (サブプロセス削減で1.3秒→目標0.5秒) | infra | 04-19 | gate_shogun_startup.sh を 1.28s |
| cmd_2104 | 偵察 — Android SSH入力消失の原因調査 (両面調査) | infra | 04-19 | Android/SSH入力消失を5観点で切り分け、P1=Cl |
| cmd_2105 | 実装 — 変更連動テスト実行 (git diff→対応テストのみ実行) | infra | 04-19 | scripts/test_select.sh を新規作成。g |
| cmd_2103 | 改善 — テストCoDD高速化第一弾 TOP5ファイル (32秒→目標10秒) | infra | 04-19 | — |
| cmd_2109 | 改善 — テストCoDD高速化 test_gate_shogun_startup.bats (6.8秒→目標3秒) | infra | 04-19 | Gate 4.5 python3 fast-path追加 + |
| cmd_2107 | 改善 — テストCoDD高速化 test_deploy_task_ac_version.bats (32秒→目標10秒) | infra | 04-19 | AC4完了: test_deploy_task_ac_ver |
| cmd_2111 | 改善 — テストCoDD高速化 test_stop_check_inbox.bats (6.2秒→目標3秒) | infra | 04-19 | test_stop_check_inbox.bats 46. |
| cmd_2113 | 改善 — テストCoDD高速化 test_cli_adapter.bats (4.6秒→目標2秒) | infra | 04-19 | test_cli_adapter.bats の fixtur |
| cmd_2108 | 改善 — テストCoDD高速化 test_deploy_task_template_generation.bats (9.8秒→目標4秒) | infra | 04-19 | deploy_task template generatio |
| cmd_2116 | 改善 — テストCoDD高速化 test_build_system.bats (3.6秒→目標1.5秒) | infra | 04-19 | test_build_system.bats を37.6%高 |
| cmd_karo_pane_lookup_fix | pane_lookup.sh lazy init修正 — deploy_task.sh pane解決障害の真因修正 | infra | 04-19 | cmd_karo_pane_lookup_fix は com |
| cmd_2115 | 改善 — テストCoDD高速化 test_cmd_save.bats (4.2秒→目標2秒) | infra | 04-19 | test_cmd_save.bats の CMD_BLOCK |
| cmd_2112 | 改善 — テストCoDD高速化 test_deploy_task_lifecycle.bats (4.7秒→目標2秒) | infra | 04-19 | before 7.104s → after 4.134s ( |
| cmd_2122 | 強化(家老) — deploy_task.sh タスク明瞭性チェック追加 (配備前検証) | infra | 04-19 | HEAD上でcmd_2122要件が既に実装済みと確認。dep |
| cmd_2127 | 強化 — 軍師LGTM収束判定 (ambiguity_points 0件をLGTM条件に) | infra | 04-19 | instructions/gunshi.md のdraftレ |
| cmd_2128 | 強化 — 修行サイクルhold-outテスト設計 (gate過適合検出) | infra | 04-19 | context/training-cycle.md §27 |
| cmd_2124 | 強化(忍者) — gate_report_format binary_checks客観裏付け (git diff突合) | infra | 04-19 | gate_report_format_main.pyにbin |
| cmd_2123 | 強化(軍師) — karo_workaround_log.sh SG紐付けフィールド追加 (偽陰性計測) | infra | 04-19 | karo_workaround_log.shへ任意の第6引数 |
| cmd_2023 | L3選出 — 6パターン×3目的関数 WF-α Top1 候補リスト生成 | dm-signal | 04-19 | — |
| cmd_2130 | 強化 — 指示文書TDD (忍者task_clarity_scoreで指示品質を計測) | infra | 04-19 | deploy_task.shテンプレートにtask_clar |
| cmd_karo_ci_fix_lk084 | CI修正 — test_cmd_complete_gate_locking.bats bash -lc→bash -c (LK084) | infra | 04-19 | tests/unit/test_cmd_complete_g |
| cmd_2131 | 偵察(緊急) — FoF monthly_returns 0件の根因特定 | dm-signal | 04-19 | FoF monthly_returns 0件の主因は sig |
| cmd_2132 | 修正(緊急) — sync-standard FoF分離 + monthly_returns crash-safe化 | dm-signal | 04-19 | sync_standardの親FoF波及を止め、Monthl |
| cmd_2134 | 設計 — 3レジーム市場分析ページ CoDD設計書 | dm-signal | 04-19 | 3レジーム分析の spec と CoDD 設計文書 3 本を |
| cmd_2135 | 修正(緊急) — DM-Signal PR #15 コンフリクト解決+マージ+Renderデプロイ | dm-signal | 04-19 | PR #15 の2競合を解消し、FoF flush help |
| cmd_2137 | 設計 — 3レジーム市場分析 Frontend CoDD設計書 | dm-signal | 04-19 | Regime analysis frontend向けのspe |
| cmd_2138 | 実装 — 3レジーム市場分析 Frontend (チャート+テーブル+API連携) | dm-signal | 04-19 | MetricsページをRegime Analysis表示へ切 |
| cmd_2140 | 修正 — cmd_2138 frontend変更revert + 本番スクリーンショット撮影 | dm-signal | 04-19 | frontend 3ファイルを origin/main 一致 |
| cmd_2142 | CoDD最適化 — run_077_bunshin.py (GS分身忍法) | dm-signal | 04-20 | run_077_bunshin.py の serial ho |
| cmd_2143 | CoDD最適化 — run_077_kasoku_diff.py (GS加速diff忍法) | dm-signal | 04-20 | run_077_kasoku_diff.py に month |
| cmd_2146 | CoDD最適化 — run_077_nukimi.py (GS抜き身忍法) | dm-signal | 04-20 | run_077_nukimi.py CoDD再最適化完了。s |
| cmd_2144 | CoDD最適化 — run_077_kasoku_ratio.py (GS加速ratio忍法) | dm-signal | 04-20 | run_077_kasoku_ratio.py の simu |
| cmd_2149 | CoDD最適化 — champion_selector.py (チャンピオン選出) | dm-signal | 04-20 | champion_selector.py のCSV fall |
| cmd_2151 | CoDD最適化 — cmd_1947_l3_ew_combo_stability.py (2体EW安定性) | dm-signal | 04-20 | cmd_1947をcache-first fallback+ |
| cmd_2152 | CoDD最適化 — cmd_1934_l3_threebody_stability.py (3体EW安定性) | dm-signal | 04-20 | cmd_1934_l3_threebody_stabilit |
| cmd_karo_ci_fix_ga135 | CI修正 — TG-T002テスト失敗(SG10 AC_SECTIONインデント検出) | infra | 04-20 | check_research_tool_growth_ac |
| cmd_2157 | 強化 — cmd_save.sh assumptions全cmd必須化(CMD品質原理的解決) | infra | 04-20 | cmd_save.shのassumptions必須チェック閾 |
| cmd_2158 | 強化 — cmd_save.sh 1cmd毎ゲート強制(前回cmd未昇格ならBLOCK) | infra | 04-20 | cmd_save.sh に Check 1.6 を追加: P |
| cmd_2159 | 強化 — cmd_save.sh BLOCK/WARN学習ループ強制(diagnosis質検査+WARN累計昇格) | infra | 04-20 | diagnosis質検査(Check 3.5)とWARN累計 |
| cmd_2160 | 強化 — cmd_save.sh environment_change強制(BLOCK→環境埋込の免疫系完成) | infra | 04-20 | BLOCK後の再PASS時にenvironment_chan |
| cmd_2161 | 強化 — gate_report_format 忍者BLOCK学習ループ(同一パターンN回→テンプレート自動改善) | infra | 04-20 | gate_report_formatの反復BLOCK学習ルー |
| cmd_2162 | 修正 — deploy_task.sh target_path転写漏れ恒久修正 | infra | 04-20 | deploy_task.shのcmd解決経路へtarget_ |
| cmd_2163 | 強化 — LK007環境埋込: workaroundパターン3件累積で構造的解決cmd自動起票催促 | infra | 04-20 | gate_karo_startup.sh に同カテゴリwor |
| cmd_karo_ci_fix_ga137 | CI修正 — cmd_save系bats 16件FAIL(cmd_2157-2160新フィールド未対応) | infra | 04-20 | cmd_save系batsフィクスチャをassumption |
| cmd_2166 | 修正 — cmd_save.sh バンドル定義修正: 変更対象(target_path+command)のみスキャン | infra | 04-20 | collect_primary_cmd_targetsをta |
| cmd_2164 | 強化 — 忍者BLOCK学習ループ汎用化: 全BLOCKパターン自動学習→テンプレートprefill | infra | 04-20 | gate_report_format学習ループを汎化し、pr |
| cmd_2167 | 研究 — WF L0四神24体作成: shin_shijin_l1 GS 4CSV × WFエンジン → シン12体+ALM12体チャンピオン選出 | dm-signal | 04-20 | AC1-AC4完了。shin_shijin_l1 の 4 C |
| cmd_2169 | 修正 — cmd_save.sh ���ンドル除外リストにoutputs/とcontext/を追加(非変更パス誤検出) | infra | 04-20 | scripts/cmd_save.shのL213-220 a |
| cmd_2168 | 修正 — cmd_save.sh Check 18 GS誤検出修正: outputs/grid_searchパスをGS実行と判定しない | infra | 04-20 | cmd_save.shのGS検出を出力CSVパスでは反応しな |
| cmd_2170 | 研究 — WF L1準備: WF四神BB月次リターンCSV抽出 + universe YAML 2本作成 | dm-signal | 04-20 | WFシン12体/月次CSV、WF ALM12体/月次CSV、 |
| cmd_2171 | 修正 — cmd_save.sh バンドル検出: target_pathとcommandの重複パスを除外(dedup) | infra | 04-20 | collect_primary_cmd_targetsでta |
| cmd_2172 | 修正 — cmd_save.sh Check 18 WF誤検出修正: WFエンジンを使わないcmdでWF WARN発火しない | infra | 04-20 | WF検出前にWF四神とWF選別を説明ラベルとして無害化し、w |
| cmd_2175 | 研究 — WF L1 WF-AS忍法21体: WF ALM四神BBで忍法GS 7本実行 + WFα選出 | dm-signal | 04-20 | WF ALM四神BBで忍法GS 7本実行(全rc=0)・WF |
| cmd_2173 | 強化 — cmd_save.sh environment_change構造化+自動検証: 約束の履行をBLOCKで強制 | infra | 04-20 | environment_change が type=...; |
| cmd_2176 | L1でWFα選出が逆効果(2勝19敗)だった。WF四神BB(L0改善済み)はそのまま活かし、忍法チャンピオン選出だけ事後選出に戻す。WFα選出(cmd_2174)との比較で、どの選出方式が有効かを判定する材料を得る | dm-signal | 04-20 | cmd_2174 GS成果物へ champion_selec |
| cmd_2178 | L2奥義のBBを準備する。cmd_2176(SS事後21体)+cmd_2177(AS事後21体)のチャンピオンpattern_idをL1 GS月次CSVから抽出し、L2用BB月次リターンCSV+universe YAMLを作成する。cmd_2170(L0→L1準備)と同構造 | dm-signal | 04-20 | L2 WF universe準備完了。SS/AS月次CSV各 |
| cmd_2129 | 強化 — CTX消費率による忍者タスク負荷検出 (tool_uses質的解釈の代替) | infra | 04-20 | GATE CLEAR時にCTX%をgate_metrics. |
| cmd_2179 | L2奥義SS系統。cmd_2178で作成したSS 21体BBで忍法GS 7本→事後選出で21体(7忍法×3目的)を確定する。L0 WF四神+L1事後選出+L2事後選出の3層積み上げ | dm-signal | 04-20 | — |
| cmd_2180 | L2奥義AS系統。cmd_2178で作成したAS 21体BBで忍法GS 7本→事後選出で21体(7忍法×3目的)を確定する。cmd_2179のAS版 | dm-signal | 04-20 | — |
| cmd_2181 | 道具磨き — run_077_kasoku_diff.py CoDDメモリ削減(8.5GB→3-4GB) | dm-signal | 04-20 | AC4: 全batsテスト(unit 1158件+top-l |
| cmd_2182 | 道具磨き — run_077_kasoku_ratio.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_kasoku_ratio.py は既に ka |
| cmd_2184 | 道具磨き — run_077_oikaze.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_oikaze.py に kasoku_dif |
| cmd_2183 | 道具磨き — run_077_nukimi.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_nukimi.py に PatternSpe |
| cmd_2187 | 道具磨き — run_077_bunshin.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_bunshin.py に PatternSp |
| cmd_2185 | 道具磨き — run_077_kawarimi.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_kawarimi.py に kasoku_d |
| cmd_2186 | 道具磨き — run_077_yotsume.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_yotsume.py に kasoku_di |
| cmd_karo_ctx_reflux_2188 | context還流 — gs-speedup-knowledge.md にcmd_2181-2187成果反映 | dm-signal | 04-20 | context/gs-speedup-knowledge.m |
| cmd_karo_env_change_gate | karo_workaround_log.shにenvironment_change強制+grep検証を追加 | infra | 04-21 | karo_workaround_log.sh に --wa |
| cmd_karo_ci_fix_env_change | CI RED修正 — test_cmd_save_environment_change.bats 3件FAIL修正 | infra | 04-21 | environment_change系テスト4件の期待値を現 |
| cmd_karo_ci_fix_aggregation | CI RED修正 — test_cmd_save_block_aggregation.bats AC2期待値更新 | infra | 04-21 | cmd_save BLOCK集約テストの期待値を現行挙動へ更 |
| cmd_2189 | 研究 — WF L2 GS bunshin(SS系統): wf_l2_ss_21体でbunshin忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでbunshin GSをex |
| cmd_2190 | 研究 — WF L2 GS kasoku_diff(SS系統): wf_l2_ss_21体でkasoku_diff忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでkasoku_diff G |
| cmd_2191 | 研究 — WF L2 GS kasoku_ratio(SS系統): wf_l2_ss_21体でkasoku_ratio忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでkasoku_ratio |
| cmd_2192 | 研究 — WF L2 GS nukimi(SS系統): wf_l2_ss_21体でnukimi忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでnukimi GSをexi |
| cmd_2194 | 研究 — WF L2 GS oikaze(SS系統): wf_l2_ss_21体でoikaze忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでoikaze GSをexi |
| cmd_karo_auto_draft_review | deploy_task.shにdraftレビュー自動送信を追加 | infra | 04-21 | deploy_task.sh に draft review |
| cmd_2197 | 修正 — run_077_kawarimi.py verify部分のsequential/batch整合バグ修正 | dm-signal | 04-21 | AC1/AC2はPASS。AC3はcmd_2196基準CSV |
| cmd_2198 | 研究 — WF L2 SS系統 champion_selector統合: 7忍法GSからchampion事後選出 | dm-signal | 04-21 | wf_l2_ss の 7忍法 monthly/cache を |
| cmd_karo_ci_fix_draft_review | CI RED修正 — test deploy draft_review送信テスト修正 | infra | 04-21 | draft review CI失敗の根因を特定し、並列テスト |
| cmd_2199 | 研究 — WF L2 GS bunshin(AS系統): wf_l2_as_21体でbunshin忍法GS実行 | dm-signal | 04-21 | WF L2 AS bunshin GSを完了。exit 0 |
| cmd_2200 | 研究 — WF L2 GS kasoku_diff(AS系統): wf_l2_as_21体でkasoku_diff忍法GS実行 | dm-signal | 04-21 | WF L2 AS 21体universeでkasoku_di |
| cmd_2201 | 研究 — WF L2 GS kasoku_ratio(AS系統): wf_l2_as_21体でkasoku_ratio忍法GS実行 | dm-signal | 04-21 | WF L2 AS 21体universeでkasoku_ra |
| cmd_2203 | 研究 — WF L2 GS kawarimi(AS系統): wf_l2_as_21体でkawarimi忍法GS実行 | dm-signal | 04-21 | WF L2 AS 21体universeでkawarimi |
| cmd_2205 | 研究 — WF L2 GS yotsume(AS系統): wf_l2_as_21体でyotsume忍法GS実行 | dm-signal | 04-21 | WF L2 AS 21体universeでyotsume G |
| cmd_2207 | 研究 — WF L2 AS系統 champion_selector統合: 7忍法GSからchampion事後選出 | dm-signal | 04-21 | wf_l2_as 配下の7忍法 monthly CSV/ca |
| cmd_karo_auto_review_gate | inbox_write.shにreport_review自動送信+GATE自動実行を追加 | infra | 04-21 | report_received→report_review自 |
| cmd_karo_self_gate_template | deploy_task.shのreportテンプレートにself_gate_check 4項目を自動注入 | infra | 04-21 | deploy_task.shの報告テンプレートへself_g |
| cmd_karo_lk086_update | LK086+karo.md更新 — report_review自動化に伴う3アクション→2アクションへ | infra | 04-21 | LK086を2アクション運用へ更新し、AC2はinstruc |
| cmd_2209 | 修正 — cmd_save.shブロック抽出awkが非数字cmd_idで境界検出失敗 | infra | 04-21 | cmd_save.sh の cmd 境界判定を非数字 cmd |
| cmd_karo_gate_wait | cmd_complete_gate.sh GATE CLEARパスにwait追加 — background子プロセス完走保証 | infra | 04-21 | cmd_complete_gate の GATE CLEAR |
| cmd_2208 | 修正 — cmd_save.sh WARN記録にnotes欠落(FP率計測不能) | infra | 04-21 | cmd_2209で先行反映済みのWARN経路統一を現物確認し |
| cmd_karo_pipeline_verify | 検証 — 自動パイプライン全段動作確認(draftレビュー→report_review→GATE→bulletin) | infra | 04-21 | context/senkyoku-log.md に cmd_ |
| cmd_2211 | 偵察 — WF四神の本番fullrecalculate計算可能性調査 | dm-signal | 04-21 | 既存四神の保存実体を特定。シン四神pipeline_conf |
| cmd_2212 | 修正 — scripts/cmd_save.sh Check 22 AC数検出バグ | infra | 04-21 | Check 22のAC件数カウントを acceptance_ |
| cmd_2213 | 整備 — WF四神命名ルール+L2命名修正をドキュメント反映 | infra | 04-21 | WF命名ルールとL2命名乖離を文書へ反映し、wfシン/wfA |
| cmd_2214 | 研究 — WFシン四神championの各foldパーセンタイル安定性検証 | dm-signal | 04-21 | WFシン四神12体のglobal fold percenti |
| cmd_2215 | 研究 — WF ALM四神 α6指標top安定性検証(計算期間3M短縮) | dm-signal | 04-21 | WF ALM四神4ファミリーの6objectiveについて、 |
| cmd_2216 | 整備 — 長期ロバストネス検証方法カタログ作成 | dm-signal | 04-21 | 7手法の長期ロバストネス検証カタログを新規作成し、cmd_2 |
| cmd_2221 | 修正 — scripts/cmd_save.sh バンドル検出のcommandスキャンバグ | infra | 04-21 | cmd_save.sh のバンドル検出で command フ |
| cmd_2217 | 研究 — L1シン忍法21体 ロバストネス検証(foldパーセンタイル+top安定性) | dm-signal | 04-21 | シン忍法21体ロバストネス検証完了。AC1(foldパーセン |
| cmd_2218 | 研究 — L1 ALM忍法21体 ロバストネス検証(foldパーセンタイル+top安定性) | dm-signal | 04-21 | AC1/AC2/AC3: ALM忍法21体(7忍法×3目的) |
| cmd_karo_gunshi_notify_flag | 修正 — gunshi_notify重複防止フラグが再修正報告の自動レビュー送信を阻害 | infra | 04-21 | deploy_task.shの再配備時にstale guns |
| cmd_karo_2220_ac3 | 研究 — cmd_2220 AC3追記(4パターン比較コメント) | dm-signal | 04-21 | cmd_2220 Markdownに4パターン比較コメント追 |
| cmd_karo_ci_fix_2221_r2 | CI RED修正 — test_cmd_save_command_steps_vs_ac.bats 1件FAIL残存 | infra | 04-21 | scripts/cmd_save.sh の command |
| cmd_karo_inbox_watcher_selfwatch | fix — inbox_watcher self-watch誤検知で将軍nudge不送信 | infra | 04-21 | agent_has_self_watchがwatcher自身 |
| cmd_2223 | 整備 — CLAUDE.md英語化(Language Policy Phase 2) | infra | 04-21 | Translated CLAUDE.md into Engl |
| cmd_1825 | 奥義-シン忍法 WF直列実行 — AC1完了済み7 CSVに対し1本ずつWF実行 | dm-signal | 04-22 | — |
| cmd_1824 | 研究道具レジストリ構築 — cmd起票時に道具の最新CLI引数を自動表示 | infra | 04-22 | — |
| cmd_karo_gs_benchmark | GS Phase1c — 8スクリプト現行ベンチマーク | dm-signal | 04-22 | — |
| cmd_1775 | ALM四神 pipeline_config再生成 — 本番制約内champion再選別 | dm-signal | 04-22 | — |
| cmd_1806 | fix — CI赤根治 — gunshi_role.md commit + bats期待値動的化 + 未追跡.md検出 | infra | 04-22 | — |
| cmd_1818 | ALM青龍-激攻 1体パリティ — 研究L0リターンと本番monthly_returnsの完全一致 | dm-signal | 04-22 | — |
| cmd_1820 | ALM四神 本番パリティ — 研究vs本番の月次リターン不一致原因特定+修正 | dm-signal | 04-22 | — |
| cmd_1822 | 奥義-シン忍法(再) — シン忍法20体を材料にGS新規実行+67窓WF | dm-signal | 04-22 | — |
| cmd_1839 | 奥義-シン忍法 WF実行+チャンピオン選出 — 3目的(CAGR/NHF/MaxDD)×7忍法 | dm-signal | 04-22 | — |
| cmd_1843 | perf — wf_runner.py WF並列ランナー新規作成（7忍法メモリグループ並列） | dm-signal | 04-22 | — |
| cmd_1828 | fix — l1_alm_wf_engine.py メモリ削減第2弾（中間配列float32化+drawdown追従） | dm-signal | 04-22 | — |
| cmd_1876 | L2奥義 正しい設計で再実行 — 各方式3目的(最大21体)universe+GS+8パターン選出+因子分析 | dm-signal | 04-22 | — |
| cmd_karo_ci_fix_1885 | CI修正 — cmd_1885 autofix pre-step導入によるテスト期待値不整合4件 | infra | 04-22 | — |
| cmd_1895 | L3忍法GS — L2奥義84体(GS固定①③⑤⑦)を材料にした既存忍法パイプライン実行+β調整 | dm-signal | 04-22 | — |
| cmd_karo_ci_fix_ga122 | CI修正 — cmd_2109副作用のテスト10件失敗修正 | infra | 04-22 | — |
| cmd_2121 | 強化(将軍) — cmd_save.sh q_ambiguity追加 (不明瞭自覚の自己申告) | infra | 04-22 | scripts/cmd_save.shにq_ambiguit |
| cmd_karo_ci_fix_2221 | CI RED修正 — cmd_save.sh関連テスト16件FAIL | infra | 04-22 | — |
| cmd_2224 | 検証 — CLAUDE.md英語化の突合+4ロールテスト(cmd_2223後追い) | infra | 04-22 | CLAUDE.md日本語原本との40行突合を完了し、4ロール |
| cmd_2225 | 整備 — Language Policy Phase 3b deploy_task.sh出力英語化 | infra | 04-22 | — |
| cmd_2226 | 整備 — Language Policy Phase 3a/3d/3e 小規模スクリプト出力英語化 | infra | 04-22 | — |
| cmd_karo_ci_fix_2225 | CI RED修正 — deploy_task.sh英語化によるテスト期待値不一致4件 | infra | 04-22 | Updated the two failing deploy |
| cmd_karo_ci_fix_gp199 | CI RED修正 — GP-199テスト期待値が日本語のまま | infra | 04-22 | Updated the GP-199 warning exp |
| cmd_2227 | research-tool — Vintage分析パイプライン雛形作成(道具磨き) | dm-signal | 04-22 | Implemented vintage_pipeline.p |
| cmd_2228 | research — Vintage 2020分析(コロナショック L0→L1→L2再選出+OOS検証) | dm-signal | 04-22 | python3 scripts/analysis/alm_r |
| cmd_2229 | research-tool — Vintage L0→L1→L2全レイヤーGSにend_date引数追加(道具磨き) | dm-signal | 04-22 | Added end-date cutoff propagat |
| cmd_2230 | 殿裁定: 英語化により全エージェントの日本語理解が著しく低下。 CLAUDE.md/AGENTS.md/スクリプト出力/テストを全て日本語に戻す。 設計書: docs/research/rollback_english_design_20260422.md 軍師レビュー: APPROVE (confidence: HIGH, 指摘0件) | infra | 04-22 | Phase 3の10本をgit historyから日本語期待 |
| cmd_karo_context_freshness_2224 | 整備 — dm-signal context鮮度回復(9日未更新) | dm-signal | 04-22 | dm-signal context indexes refr |
| cmd_2231 | fix — ETL cron OOM解消: curl→python直接実行 + メモリ計測 | dm-signal | 04-22 | AC4: log_memory_usage()を全Phase |
| cmd_2232 | 強化 — CDP CLI標準化: cdp_cli.shをワンストップCDP入口に拡張 | auto-ops | 04-22 | cdp_cli.sh に launch/navigate/e |
| cmd_karo_auto_ops_context_freshness | 調査 — auto-ops context freshness ALERTの原因分析 | auto-ops | 04-22 | cmd_2232 の context未反映箇所を特定し、co |
| cmd_2233 | CoDD偵察 — daily_etl.pyの存在理由調査: 本番fullrecalculateとの乖離分析 | dm-signal | 04-22 | FILL_THIS |
| cmd_karo_ci_fix_ga158 | CI RED修正 — cmd_save environment_change テスト317-320復旧 | infra | 04-22 | cmd_save.shのPythonパーサーがassumpt |
| cmd_2234 | fix — sync-prices(L0)を全期間取得+UPSERTに変更: 730日固定→FULL_HISTORY_START | dm-signal | 04-22 | sync_layers.py DEFAULT_LOOKBAC |
| cmd_2236 | 廃止 — daily_etl.py + ETL cron削除: L0-L3 sync cronに統一 | dm-signal | 04-22 | ETL cron廃止完了。Render ETL cron(c |
| cmd_2235 | 検証 — sync cron L0→L3手動実行: 全期間再取得+再計算の完走確認 | dm-signal | 04-22 | L0/L1/L2はRender logs+timinig h |
| cmd_karo_deploy_notice_fix | 修正 — deploy_task.sh task YAML破損(_deploy_notice継続行残留)を根治 | infra | 04-22 | yaml_field_set.sh が scalar sib |
| cmd_2237 | fix — 壊れた一回限りパリティテスト2本削除: pytest collection error解消 | dm-signal | 04-22 | 壊れたパリティテスト2本を削除して commit e7c69 |
| cmd_2238 | 偵察 — pytest残存失敗8件の切り分け(修正候補 vs 削除候補) | dm-signal | 04-22 | FILL_THIS |
| cmd_karo_max_inject_fix | 修正 — deploy_task lesson注入でMAX_INJECT未定義になる経路を根治 | infra | 04-22 | MAX_INJECT を tag fallback 前へ前倒 |
| cmd_2141 | 実装 — Up vs Down MarketにSideways行追加 + レスポンシブ対応 | dm-signal | 04-23 | — |
| cmd_2210 | 研究 — L2 GS固定選出 vs WF動的選出 比較分析記事+gist共有 | dm-signal | 04-23 | — |
| cmd_2239 | CoDD最適化 — ticker_returns.py(L1: リターン計算) | dm-signal | 04-23 | — |
| cmd_2240 | CoDD最適化 — recalculate_fast.py(L2/L3計算本体) | dm-signal | 04-23 | — |
| cmd_2241 | CoDD最適化 — recalculate_fof.py(L3: FoF再計算, 最大ボトルネック) | dm-signal | 04-23 | — |
| cmd_2242 | CoDD最適化 — sync_layers.py(オーケストレーター) | dm-signal | 04-23 | — |
| cmd_2243 | CoDD準備 — data_fetcher.py(L0) extract+spec作成 | dm-signal | 04-23 | 既存sandbox抽出物とspecの再確認でAC1/AC2は |
| cmd_2244 | CoDD準備 — ticker_returns.py(L1) extract+spec作成 | dm-signal | 04-23 | AC1: CoDD extract完了(codd/extra |
| cmd_2245 | CoDD準備 — recalculate_fast.py(L2/L3計算本体) extract+spec作成 | dm-signal | 04-23 | recalculate_fast.py(3048行)のcod |
| cmd_2246 | CoDD準備 — recalculate_fof.py(L3: FoF再計算, 最大ボトルネック) extract+spec作成 | dm-signal | 04-23 | CoDD extractとspec作成は完了したが、AC3の |
| cmd_2247 | CoDD準備 — sync_layers.py(オーケストレーター) extract+spec作成 | dm-signal | 04-23 | FILL_THIS |
| cmd_karo_2231_ac7_retry | 検証 — cmd_2231 AC7やり直し: 既存成功job基準のsignal比較のみ | dm-signal | 04-23 | 既存成功job d7k7k1cm0tmc73acvga0 を |
| cmd_karo_ci_fix_ga159 | CI RED修正 — deploy_task if_then/legacy detailテスト2件 | infra | 04-24 | cmd_save diagnose 系は HEAD 時点で既 |
| cmd_2248 | fix — cmd_save.sh gate偽陽性率改善: FP率60%超のWARN type修正 | infra | 04-24 | cmd_save.sh のWARN noteを型付き化し、r |
| cmd_karo_ci_fix_2248 | CI RED修正 — test_cmd_save_warn_logging AC2テスト失敗 | infra | 04-24 | test_cmd_save_warn_logging.bat |
| cmd_2249 | fix — cmd_save.sh check_self_reread_red_flag FP修正: YAMLキー名をgrep対象から除外 | infra | 04-24 | check_self_reread_red_flag の P |
| cmd_2250 | fix — cmd_save.sh Session State拡張: 同一WARN 2回目以降で検出ロジック自動表示 | infra | 04-24 | cmd_save.sh の WARN記録に check me |
| cmd_2251 | 偵察 — recalculate_fof.py L3速度改善設計書: 依存分析+cProfile+FE整合性 | dm-signal | 04-24 | recalculate_fof/fullrecalculat |
| cmd_2252 | fix — cmd_save.sh LS009/LS029 gate化: 各論パッチ検出+assumptions時系列強制 | infra | 04-24 | cmd_save の LS009/LS029 挙動を回帰テス |
| cmd_karo_gate_clear_idle | fix — GATE CLEAR後のtask YAML自動idle化 | infra | 04-24 | cmd_complete_gate.sh に GATE CL |
| cmd_2253 | 最適化 — trade_performance生成 速度改善（設計書Rank 1） | dm-signal | 04-24 | FILL_THIS |
| cmd_karo_conflict_marker_gate | fix — lessons SSOT conflict markers検出gate | infra | 04-24 | gate_lesson_health.sh に SSOT l |
| cmd_karo_pd_summary_fix | fix — pending_decisions.yaml summary自動再計算 | infra | 04-24 | pending_decision_write.shにreca |
| cmd_2254 | fix — FoF MonthlyReturn DB永続化バグ修正（precompute rollback巻き添え防止） | dm-signal | 04-24 | precomputeをPF単位savepoint化し、例外時 |
| cmd_2255 | 実装 — DM-Signal本番ヘルスチェックスクリプト（DB→API→FE 3レイヤー貫通確認） | dm-signal | 04-24 | scripts/health_check.py を追加し、D |
| cmd_karo_ci_fix_2252 | fix — CI RED修正: cmd_save.bats 12テスト失敗 | infra | 04-24 | 6件テストフィクスチャのassumptions claimに |
| cmd_2257 | 偵察+設計 — FoF増分計算化のCoDD設計書生成(recalculate_fof.py + recalculate_fast.py L2528-2638) | dm-signal | 04-24 | _recalculate_fof_history全文読解完了 |
| cmd_2258 | impl — FoF sync-fof増分計算化(Signal差分+MR増分。462.8s→60s目標) | dm-signal | 04-24 | FoF増分計算実装完了。sync-fof(PORTFOLIO |
| cmd_2259 | impl — FoF MR生成高速化: signal_cacheバッチ事前ロード+共有化(PI-024準拠・全期間再計算維持) | dm-signal | 04-24 | cmd_2259を完了した。初回修正(af469454)でs |
| cmd_2260 | impl — FoF MR生成 DB fallback穴塞ぎ(356→0件目標。26.53s→1.5s) | dm-signal | 04-24 | price_ratio_calculatorのcomplet |
| cmd_2261 | 偵察 — L3_fof daily_loop 224sの内訳計測+高速化ターゲット特定 | dm-signal | 04-24 | cmd_2261_scout完了。live timing(r |
| cmd_2262 | 本番FEのユーザー体験速度を定量計測する。全ページの初回表示時間、PF切替時の再描画速度(10回連続)、ページ間遷移時間を計測し、ボトルネック特定の基礎データを取得する。コード変更なし。 | dm-signal | 04-25 | FILL_THIS |
| cmd_2263 | cmd_save.sh BLOCK時に将軍が止まる問題を自動化×強制で解消する。BLOCK出力の冒頭に「止まるな、修正して再実行」ナッジを1行追加。 | infra | 04-25 | cmd_save.shのBLOCK初回出力にだけ「止まるな、 |
| cmd_2264 | cmd_2262の計測データとFEコードの現状分析を基に、FE表示速度を改善するための設計書を作成する。全ページで「PF切替が一瞬」を達成するための改善施策を優先度付きで網羅する。コード変更なし。 | dm-signal | 04-25 | cmd_2262原票とFE/BEコードを基に、FE速度改善設 |
| cmd_2265 | cmd_save.shのgate偽陽性率が高すぎる(16件がFP率66%超)。偽陽性は将軍のBLOCK対応時間を浪費し殿の時間を奪う。共通根を修正し全cmdに複利で効くgate精度改善を行う。 | infra | 04-25 | FILL_THIS |
| cmd_2266 | cmd_2264設計書の穴6件を埋める補完偵察。BE profiling + FEフィールド使用マッピング + Render構成制約 + デプロイ順序 + Static Export制約 + 依存関係の正確な整理を行い、設計書を補完更新する。 | dm-signal | 04-25 | cmd_2266補完偵察完了。`docs/research/ |
| cmd_2267 | /api/signalsの最大ボトルネック(FoF display展開 220-360ms/500-700ms)を事前計算化して初回表示・ページ遷移を250-400ms短縮する。設計書§4.2 Measure A + §6.1の分析に基づく。 | dm-signal | 04-25 | FoF displayをrequest時再展開から事前計算l |
| cmd_2268 | cmd_2267(FoF display事前計算化)をpush→Render deploy→CDP再計測し、速度改善効果とバグ有無を確認する。cmd_2262のベースラインと比較。 | dm-signal | 04-25 | push・Render deploy・healthz確認まで |
| cmd_2269 | gate BLOCKパターン分析→instructions修正提案を自動生成する仕組みを構築。GEPA(ICLR 2026 Oral)の自然言語反射アプローチを将軍システムに適用。deepdive Phase 5「なぜの目的=自動化ターゲット特定」の機械化。 | infra | 04-25 | FILL_THIS |
| cmd_2270 | deploy_task.shの教訓注入で、タスク内容に基づく関連度スコアリングを導入。engram(autoresearch-engram)の頻度重み付きクロスセッション知識検索を参考に、教訓有用率を7.7%から大幅改善する。 | infra | 04-25 | deploy_task.shの教訓注入にキーワード関連度スコ |
| cmd_2271 | cmd_2268のCDP計測失敗を条件調整して再実行。Phase 1-A(signals slim化)の速度改善効果とバグ有無を確認する。 | dm-signal | 04-25 | FILL_THIS |
| cmd_karo_ci_fix_2270 | cmd_2270でMAX_INJECT=3→10に変更したがテスト2件(test 444/445)が旧値3を期待してFAIL。テストを新値10に更新しCI GREEN復帰する。 | infra | 04-25 | MAX_INJECT=10変更に追随して deploy_ta |
| cmd_2272 | GStack/GBrain深掘りカタログ(docs/research/gstack-gbrain-takeaway-catalog.md §8)のRound 1全15項目をinstructions/context/templateに追記。全cmdのレビュー品質・偵察品質・報告品質に複利で効く。 | infra | 04-25 | AC2(ashigaru.md: bisect commit |
| cmd_2273 | cmd_complete_gate.shに4つの新検証を追加し、忍者のscope逸脱・レビュー陳腐化・部分完了・修正暴走を構造的に検出する。cmd_2271事故(scope外174行改変)の再発防止。 | infra | 04-25 | cmd_complete_gate.shに4新検証(scop |
| cmd_2274 | CDP計測結果にbaseline比較・回帰閾値判定・health score算出を追加。deploy後の性能変化を自動検出し、Phase毎の改善効果を数値で追跡可能にする。 | infra | 04-25 | scripts/cdp/cdp_benchmark.py(. |
| cmd_2275 | 教訓管理の陳腐化検出(Prune)、プロジェクト横断教訓検索、deploy再実行の冪等性、差分テストの4機能を追加。教訓品質と配備効率に複利で効く。 | infra | 04-25 | AC1: ~/.claude/skills/dream/SK |
| cmd_2276 | deploy_task.shの教訓注入がtarget_pathベースのタグマッチのみでCDP教訓が0件注入された事故(cmd_2271)の根因修正。purpose/command/context_filesのキーワードも加味し、タスク内容に関連する教訓を正しくルーティングする。 | infra | 04-25 | FILL_THIS |
| cmd_2277 | 強化 — GStack知見Round 2-G2: レビュー系4項目(Adaptive gating/Adversarial review/Scope lock/前提3段階) | infra | 04-25 | FILL_THIS |
| cmd_2278 | 強化 — GStack知見Round 3: L工数4項目(Deploy後監視/check-resolvable/routing-eval/ハイブリッド検索) | infra | 04-25 | AC1 cdp_canary.sh と AC4 hybrid |
| cmd_2279 | 修正 — cmd_save.sh check_gunshi_design_num_relax カタログ参照FP除外 | infra | 04-25 | FILL_THIS |
| cmd_2280 | 強化 — GStack知見Round 2-G2再実施: レビュー系4項目(Adaptive gating/Adversarial review/Scope lock/前提3段階) | infra | 04-25 | FILL_THIS |
| cmd_2281 | Phase 1-A(FoF display事前計算化, cmd_2267)のdeploy済み本番FEをCDP計測し、cmd_2262ベースラインと速度改善効果を比較。cmd_2268/2271で2回失敗(認証不成立+artifact上書き)の教訓を反映。 | dm-signal | 04-25 | FILL_THIS |
| cmd_2282 | BLOCK率50%の最大原因draft_lessons(13件/100件)の根因=教訓登録が意志依存を自動化×強制で解消 | infra | 04-25 | cmd_save.sh 4箇所精査完了。CLEARリマインド |
| cmd_2283 | 実装 — FE signals handoff cache（Phase 1-B: hard navigation遷移時のblank/loading除去） | dm-signal | 04-26 | SignalsProviderにsessionStorage |
| cmd_2285 | 強化 — cmd起票前の事前確認gate（PreToolUse:Edit hook for shogun_to_karo.yaml） | infra | 04-26 | shogun_to_karo.yaml Edit時の起票前確 |
| cmd_2286 | 強化 — 忍者版事前ワクチン（DM-Signal本番ファイル編集時にPI注入） | infra | 04-26 | FILL_THIS |
| cmd_2287 | 修正 — cmd_complete_gate.shにtest_triage判定追加（pre_existing FAIL誤判定バグ修正） | infra | 04-26 | cmd_complete_gateのbinary_check |
| cmd_2284 | 強化 — cmd_save.sh BLOCK後の将軍自走強制hook | infra | 04-26 | cmd_save.sh BLOCK(exit 1)時だけPo |
| cmd_2288 | 検証 — Phase 1-B CDP再計測（handoff cache効果確認+ベースライン比較） | dm-signal | 04-26 | FILL_THIS |
| cmd_2289 | 強化 — 第三層指標転換（忙しさ→賢さ: 同クラス再発率+ワクチン有効率をstartup gateに追加） | infra | 04-26 | Gate 12.5拡張完了。再発率(前50cmd vs直近5 |
| cmd_2291 | 検証 — CDP再計測（道具磨き後・全ページ+PF切替） | dm-signal | 04-26 | — |
| cmd_2292 | 偵察 — シン四神→シン忍法→シン奥義 L0→L2経路の現物検証 | dm-signal | 04-26 | シン四神12体(type=standard, compone |
| cmd_2293 | 強化 — 殿の質問に対する確認強制hook(事前ワクチン系譜) | infra | 04-26 | FILL_THIS |
| cmd_2294 | 修正 — dm-signal context §0陳腐化修正+L0/L1/L2定義統一 | dm-signal | 04-26 | FILL_THIS |
| cmd_2295 | 強化 — projects/dm-signal.yaml Vercel圧縮(491→80行) | dm-signal | 04-26 | — |
| cmd_2296 | 強化 — dm-signal context 4ファイルVercel圧縮+500行制限適用 | dm-signal | 04-26 | FILL_THIS |
| cmd_2297 | 偵察 — FE/BE速度改善設計書の現状照合+次Phase特定 | dm-signal | 04-26 | FE設計書(fe-speed-improvement-des |
| cmd_2298 | 偵察 — FE/BE速度改善設計書の現状照合+次Phase特定(Codex独立視点) | dm-signal | 04-26 | FILL_THIS |
| cmd_2299 | 強化 — 将軍弱点2計測hook(因果展開ステップ数+新規vs既存判断) | infra | 04-26 | prompt_state_inject.shへ殿入力回数の自 |
| cmd_2300 | 実装 — Measure C: next-portfolio predictive prefetch(PF切替高速化) | dm-signal | 04-26 | FILL_THIS |
| cmd_karo_ci_fix_375 | CI修正 — batsテスト#375失敗修正 | infra | 04-26 | FILL_THIS |
| cmd_2301 | — | — | 04-26 | — |
| cmd_2304 | 計測 — Measure C効果検証(CDP PF切替時間、1009msベースライン比較) | dm-signal | 04-26 | FILL_THIS |
| cmd_2303 | 配備 — cmd_2300(Measure C prefetch)のpush+Render deploy確認 | dm-signal | 04-26 | cmd_2303_normal: GitHub main と |
| cmd_2306 | 偵察 — Measure A残り(pending_map/folders/portfolio全件/momentum payload)削減箇所特定 | dm-signal | 04-26 | FILL_THIS |
| cmd_2305 | 偵察 — Measure D(full fetch defer)実装箇所特定+波及分析 | dm-signal | 04-26 | dashboard/monthly-returns/annu |
| cmd_2308 | 実装 — Measure D: full fetch idle後ろ倒し(dashboard/monthly/annual 3ページ) | dm-signal | 04-26 | FILL_THIS |
| cmd_2309 | 実装 — Measure A: signals.py pending_map月中スキップ+portfolio lazy load | dm-signal | 04-26 | FILL_THIS |
| cmd_2307 | 偵察 — PF切替1009msフェーズ分解(API fetch vs FE処理の実測内訳) | dm-signal | 04-26 | PF切替1008-1009msをperf_measure定義 |
| cmd_2310 | 改善 — perf_measure.py PF切替計測手法修正(dropdown固定待機520ms排除) | dm-signal | 04-26 | FILL_THIS |
| cmd_2313 | 修正 — Codex config.toml approval_mode=full-auto追加(STALL根絶) | infra | 04-26 | FILL_THIS |
| cmd_2312 | 計測 — Measure D/A効果検証(修正済み計測手法でCDP PF切替再計測) | dm-signal | 04-26 | FILL_THIS |
| cmd_2311 | 配備 — Measure D/A/計測手法修正のpush+Render deploy確認 | dm-signal | 04-26 | cmd_2308/2309はDM-Signal GitHub |
| cmd_karo_ci_fix_357 | CI修正 — batsテスト#357失敗修正 | infra | 04-26 | FILL_THIS |
| cmd_karo_reprofile_freq | インフラスクリプト頻度再計測 — 直近24h | infra | 04-26 | 直近24hのインフラスクリプト頻度を5ソースで再計測し、do |
| cmd_2314 | 偵察 — GS CSV パラメータ→月次リターン列マッピング調査 | dm-signal | 04-26 | summary CSV行i == monthly CSV列i |
| cmd_karo_reprofile_bench | インフラスクリプト実行時間再計測 — Top 20 × 5回 | infra | 04-26 | 前回プロファイリングTop20を5回中央値で再計測し、doc |
| cmd_2315 | 偵察 — GS CSV正規化Phase 0.5: スクリプト130本全量分類+サブディレクトリ最終確定 | dm-signal | 04-27 | cmd_2315 Phase 0.5偵察として、GS関連スク |
| cmd_2316 | 実装 — GS正規化Phase 1: マニフェスト記録 | dm-signal | 04-27 | outputs/gs_backup/20260427_pre |
| cmd_2317 | 実装 — GS正規化Phase 1.5a: gs_db_utils.py(SQLite write/read共通層) | dm-signal | 04-27 | FILL_THIS |
| cmd_2318 | 実装 — GS正規化Phase 1.5b: verify_gs_db.py(CSV-SQLite照合検証) | dm-signal | 04-27 | scripts/analysis/verify_gs_db. |
| cmd_2319 | 実装 — GS正規化Phase 1.5c: gs_db_summary.py(SQLiteサマリ表示) | dm-signal | 04-27 | gs_db_summary.py を新規作成。--db-pa |
| cmd_2320 | 実装 — GS正規化Phase 1.5d: test_gs_db_utils.py(ユニットテスト) | dm-signal | 04-27 | — |
| cmd_2321 | 実装 — GS正規化Phase 1.5d: test_gs_db_utils.py(ユニットテスト) | dm-signal | 04-27 | gs_db_utilsの8関数に対するround-trip単 |
| cmd_2322 | 実装 — GS正規化Phase 2: L0シン bunshin CSV→SQLite変換(4family) | dm-signal | 04-27 | L0/shin bunshin 4familyのCSV→SQ |
| cmd_2323 | 実装 — GS正規化Phase 2: L0シン oikaze CSV→SQLite変換(4family) | dm-signal | 04-27 | cmd_2323 oikaze L0シン4familyをCS |
| cmd_2324 | 実装 — GS正規化Phase 2: L0シン yotsume CSV→SQLite変換(4family) | dm-signal | 04-27 | FILL_THIS |
| cmd_2325 | 実装 — GS正規化Phase 2: L0シン kawarimi CSV→SQLite変換(4family) | dm-signal | 04-27 | FILL_THIS |
| cmd_2326 | 実装 — GS正規化Phase 2: L0シン nukimi CSV→SQLite変換(4family) | dm-signal | 04-27 | FILL_THIS |
| cmd_2327 | 実装 — GS正規化Phase 2: L0シン kasoku_diff CSV→SQLite変換(4family・大規模) | dm-signal | 04-27 | FILL_THIS |
| cmd_2328 | 実装 — GS正規化Phase 2: L0シン kasoku_ratio CSV→SQLite変換(4family・大規模) | dm-signal | 04-27 | — |
| cmd_2329 | 修正 — gs_db_utils.py write_monthly NaN→NULL許容改修 | dm-signal | 04-27 | FILL_THIS |
| cmd_2330 | shin_shijin_l1_gs.pyのシミュレーション精度を現在株価で検証。GS正規化Phase 1.9の前提条件。読取+計算+比較のみ | dm-signal | 04-27 | AC1: shin_shijin_l1_gs.py --pa |
| cmd_2331 | shin_shijin_l1_gs.pyの出力にSQLite直接出力を追加する(道具磨き)。 合わせてPhase 2で生成した汚染.dbとbypass独自スクリプトを清掃する。 Phase 1.9b(フルGS再実行)の前提。道具が正しく動かなければGS再実行は無意味。 | dm-signal | 04-27 | 旧SQLite成果物と変換用一時スクリプト2本を削除し、sh |
| cmd_2332 | shin_shijin_l1_gs.pyの出力パスを設計書§3.1の命名規則に合わせる。 日付バージョニング+layer/method構造+latest symlinkを追加し、GS結果の管理基盤を整備する。 フルGS再実行(cmd_2334)の前提となる道具磨き。 | dm-signal | 04-27 | — |
| cmd_2333 | cmd_1125_v2_champion_select.pyの入力をCSV→SQLite(gs_db_utils.read_*)に変更する。 チャンピオン突合(cmd_2335)の前提となる道具磨き。cmd_2332と並列実行可能。 | dm-signal | 04-27 | cmd_1125_v2_champion_select.py |
| cmd_2334 | shin_shijin_l1_gs.pyで4family(DM2/DM3/DM6/DM7+)のフルGSを最新株価で再実行する。 cmd_2332でOUTPUT_DIRを設計書§3.1準拠に変更済み。設計書準拠パスにSQLite+CSV同時出力。 チャンピオン12体選出(cmd_2335)の前提。 | dm-signal | 04-28 | shin_shijin_l1_gs.pyを--familie |
| cmd_2335 | cmd_2334で生成したフルGS結果(SQLite)からシン四神チャンピオン12体を選出する。 cmd_1125_v2_champion_select.pyで--db-pathを指定しSQLite直読。 DNA制約フィルタ→3モード選出(激攻CAGR/常勝NHF/鉄壁MaxDD)→吸収判定→旧チャンピオンとの差分確認。 | dm-signal | 04-28 | cmd_1125_v2_champion_select.py |
| cmd_2336 | cmd_delegate.sh L180のkaro inbox重複検出がgrep -F "$CMD_ID"で全文検索するため、 軍師のlesson_candidateやbulletin_notify等に含まれるcmd_id文字列にも誤マッチする。 type:cmd_newのエントリのみを検査対象に限定する。 | infra | 04-28 | cmd_delegate.shの家老inbox重複検出をcm |
| cmd_2337 | 本番DBのシン四神12体のconfig(lookback/rebalance/top_n)を取得し、 cmd_2335で選出したGS選出シン四神12体と正確に12体vs12体で突合する。 cmd_2335のスクリプトは旧JSON(吸収後10体)と比較しており、本番DB12体との正しい差分が未確認。 | dm-signal | 04-28 | 本番PostgreSQLのシン四神12体pipeline_c |
| cmd_2338 | gunshi_notifyの重複防止フラグがdraft_reviewとreport_reviewで共有されており、 draft送信済みフラグが存在するとreport_received時のreport_reviewが不発になるバグを修正する。 cmd_2334で実証(家老報告 2026-04-28)。 | infra | 04-28 | draft_reviewの重複防止マーカーをcmd_id.s |
| cmd_2339 | gs_data_loader.pyからCSV読込経路を完全に廃止し、DB直読を唯一のデータ取得経路にする。 殿裁定「CSVをまた作るな。DB直読せよ」の構造的実装。§33 Phase 3の前半。 | dm-signal | 04-28 | gs_data_loader.pyからCSV読込関数を削除し |
| cmd_2340 | gs_data_loader.pyのL1_PORTFOLIO_MAP(L531-547、UUIDハードコード)を廃止し、 universe config(YAML)のcomponentsセクションをUUIDの唯一の供給源にする。 §33 Phase 3の後半。cmd_2339(CSV経路廃止)の完了が前提。 | dm-signal | 04-28 | — |
| cmd_2341 | ninja_monitorでtask正常完了→idle遷移時にSTALL_FIRST_SEEN/STALL_COUNTがクリアされず、 新task配備直後に前taskの停滞時間+回数が持ち越されてESCALATE誤検知が発生する。 cmd_2340/hayateで29秒後に41140秒idle+2回STALLと誤検知された実証あり(家老掲示板報告)。 | infra | 04-28 | ninja_monitorの完了/idle遷移でSTALL_ |
| cmd_2342 | ACに「全テストPASS」「0 failures, 0 skips」等のパターンがあった場合にWARNし、 「変更対象の関連テストPASS(pre-existing failure除外)」へのスコープ限定を促す。 将軍のcmd設計段階で達成不可能なACを防ぎ、忍者FAIL→家老waiveの消火循環を根絶する。 | infra | 04-28 | — |
| cmd_2343 | outputs/analysis/配下のCSVファイルを調査し、GS入力用CSV(削除対象)と研究成果物(保護対象)を選別する。 Phase 3でCSV経路を廃止したが、旧CSV入力ファイルがoutputs/analysis/に残存(軍師確認済み)。 削除対象を特定してPhase 4実行cmdの前提とする。 | dm-signal | 04-28 | outputs/analysis配下CSVは807件・923 |
| cmd_2344 | run_077_*.py 7本のデフォルトuniverse configをalm_l0_12.yaml(source_type:csv)から okugi_shin_ninpo_20.yaml(source_type:db, 20体UUID付き)に変更する。 Phase 3でCSV経路廃止済み→現状のデフォルトで実行するとValueError。DB直読を唯一の経路にする。 | dm-signal | 04-28 | run_077系7本のデフォルト--universeをoku |
| cmd_2345 | cmd_2343偵察で特定した旧GS入力CSV 9件(371KB)を削除する。 Phase 3でCSV経路廃止済み(source_type=csv→ValueError)のため、これらを参照するコードパスは存在しない。 GS再実行(後続A)前にクリーンな状態にする。 | dm-signal | 04-28 | 旧GS入力CSV 9件を /mnt/c/Python_app |
| cmd_2346 | run_077全7本で共通のGS結果SQLite出力モジュールを作成する。 現在のCSV出力関数(write_meta_yaml/append_data_catalog/write_monthly_csv_streaming)を SQLite出力版に置換する共通モジュール。殿裁定「CSVをまた作るな」に従いCSV出力は廃止。 shin_shijin_l1_gs.py L1041-1043のSQLite出力実装が参考。 | dm-signal | 04-28 | — |
| cmd_2347 | cmd_2346で作成したSQLite出力共通モジュールを使い、run_077全7本のCSV出力をSQLite出力に切替える。 CSV出力関数(to_csv/write_monthly_csv_streaming)の呼出しを共通モジュールのSQLite出力に置換。 殿裁定「CSVをまた作るな」に従いCSV出力コードは削除。 | dm-signal | 04-28 | — |
| cmd_2348 | shin_shijin_l1_gs.py L1042-1043のCSV出力2行を削除する。 殿裁定「CSVをまた作るな」に違反する残存コード。 gs_db_utilsはDataFrameを直接受付可能(_as_frame L47-50)のためCSV経由は不要。 cmd_2346がこのファイルを参考実装として使うため、CSV出力を除去してから参考にさせる。 | dm-signal | 04-28 | shin_shijin_l1_gs.pyのGS出力をCSV中 |
| cmd_2349 | gs_sqlite_output.py L56とgs_db_utils.py L50のpd.read_csv(CSV入力フォールバック)をValueErrorに変更する。 殿裁定「CSVをまた作るな」の徹底。DataFrame直接渡しが正規パス。CSV経由の裏口を完全封鎖。 cmd_2346の成果物(gs_sqlite_output.py)は機能するがCSV fallbackが残存→この補足cmdで修正。 | dm-signal | 04-28 | GS SQLite書込み系のCSVパス入力を拒否し、Data |
| cmd_2350 | gs-data-normalization-spec.md Phase 7(近傍分析道具)の設計書を書くために必要な4つの未調査事項を確認する。 道具を作る前に入力データの構造と既存道具の改修範囲を把握する。 | dm-signal | 04-28 | cmd_1012の月次return入力、指定L0 SQLit |
| cmd_2351 | 設計書(docs/design/gs-data-normalization-spec.md §5.2 Phase 7)のgs_grid_robustness.pyのコア機能を実装する。 SQLite .dbからparams+metricsを読み、指定されたgrid_axes軸で全パターンの指標値を抽出し、JSON出力する。 可視化(PNG)とpeak_ratio計算は後続cmdで追加する。本cmdはデータ抽出+JSON出力のみ。 | dm-signal | 04-28 | scripts/analysis/gs_grid_robus |
| cmd_2352 | L0シン四神12体のchampion_pattern_idをSQLite .dbのparamsテーブルから特定し、 タイムスタンプ付きYAML(champion_list.yaml)に記録する。 gs_grid_robustness.pyの入力データとなるchampionリスト。 | dm-signal | 04-28 | outputs/robustness/champion_li |
| cmd_2353 | cmd_2351で実装したgs_grid_robustness.pyのJSON出力を入力として、 PNGヒートマップ(α6指標ごとにchampionマーカー付き)と断面プロット(champion固定LBスイープ1Dライン)を生成する機能を追加する。 | dm-signal | 04-28 | gs_grid_robustness.pyに--visual |
| cmd_2354 | cmd_2351で実装したgs_grid_robustness.pyのJSON出力に、 peak_ratio(champion / ±1隣接平均、方向正規化)と統合スコア(peak_ratio幾何平均)を追加する。 | dm-signal | 04-28 | — |
| cmd_2355 | 軍師が殿の直接命令を3回連続で拒否した(2026-04-28 13:21頃)。 根因: instructions/gunshi.md F-G01が「殿に直接報告する」を禁止し、 Identityに「殿にも直接報告しない」と明記。環境が殿拒否を教えている。 殿の裁定「俺が絶対。それ以外に鎖の原理はないぞ」を環境に埋め込む。 | infra | 04-28 | cmd_2355完了。軍師指示に殿最上位原則を追加し、F-G |
| cmd_2356 | Phase 7(gs_grid_robustness.py設計+実装)はcmd_2350-2354全てGATE CLEARだが、 設計書の進捗表(§5.3)がPhase 7を「未着手」のまま。実態と乖離している。 設計書を実態に合わせて更新し、Phase 7.1起票の前提を整える。 | dm-signal | 04-28 | — |
| cmd_2357 | Phase 7で作ったgs_grid_robustness.pyをL0シン四神GS結果(SQLite)で実行し、 12体(4family×3mode)のグリッドロバストネスを検証する。 L0は1軸(lookback_index)のため2Dグリッドのみ。 結果を殿に提示し、閾値判断の材料とする。 | dm-signal | 04-28 | cmd_2357 L0 robustness generat |
| cmd_2358 | Phase 1.95(L1 GS再実行)の前提。run_077がgs_data_loaderで構成PF月次リターンを読むが、 現在source_type:dbのみ(本番PostgreSQL直読=§5.5.4違反)。 L0 SQLite .dbにopen-to-open月次リターンが存在する(設計書§5.1.5確認済み)。 source_type:local_sqliteを追加し、ローカルSQLiteからchampion月次リターンを読む経路を作る。 | dm-signal | 04-28 | cmd_2358完了。gs_data_loader.pyにs |
| cmd_2359 | Phase 1.95の第1弾。run_077_bunshin.pyをsource_type:local_sqlite(L0 SQLite直読)で実行し、 L1分身忍法のGS結果をSQLite .dbに出力する。 bunshinは0軸(LBなし、top_nのみ)で最軽量。OOMリスク最小。 | dm-signal | 04-28 | cmd_2359完了。run_077_bunshin.pyを |
| cmd_2360 | Phase 1.95の第2弾。run_077_oikaze.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 追い風(MomentumFilter)は1軸LB忍法。bunshin(1/7)GATE CLEAR確認済み。 | dm-signal | 04-28 | cmd_2360完了。run_077_oikaze.pyをs |
| cmd_2361 | Phase 1.95の第3弾。run_077_kawarimi.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 変わり身(TrendReversalFilter)は1軸LB忍法。oikaze(2/7)GATE CLEAR確認済み。 | dm-signal | 04-28 | cmd_2361完了。run_077_kawarimi.py |
| cmd_2362 | Phase 1.95の第4弾。run_077_yotsume.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 四つ目(MultiViewMomentumFilter)は1軸LB忍法。kawarimi(3/7)GATE CLEAR確認済み。 | dm-signal | 04-28 | cmd_2362完了。run_077_yotsume.pyを |
| cmd_2363 | Phase 1.95の第5弾。run_077_nukimi.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 抜き身(SingleViewMomentumFilter)は2軸LB忍法(base+skip)。yotsume(4/7)GATE CLEAR確認済み。 2軸忍法の最初。メモリ負荷増大に注意。 | dm-signal | 04-28 | cmd_2363_normal完了。run_077_nuki |
| cmd_2364 | Phase 1.95の第6弾。run_077_kasoku_diff.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 加速D(MomentumAccelerationFilter method=diff)は2軸LB忍法。最大パターン数(119,493pat実績)。 nukimi(5/7)GATE CLEAR確認済み。Peak RSS 1,696MB実績あり。OOM注意。 | dm-signal | 04-28 | cmd_2364_normal完了。run_077_kaso |
| cmd_2365 | Phase 1.95の最終弾。run_077_kasoku_ratio.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 加速R(MomentumAccelerationFilter method=ratio)は2軸LB忍法。kasoku_diff(6/7)GATE CLEAR確認済み。 これでL1全7忍法GS再実行が完了する。 | dm-signal | 04-28 | cmd_2365_normal完了。run_077_kaso |
| cmd_2366 | Phase 1.95で再実行したL1全7忍法GS結果(ローカルSQLite 7本)からチャンピオンを選出し、 本番DBのシン忍法configと突合する。cmd_2335(L0四神)と同パターン。 L1は7忍法×3モード(激攻CAGR/常勝NHF/鉄壁MaxDD)。吸収判定後の体数がL1の確定体数になる。 | dm-signal | 04-28 | L1 7忍法×3モード=21チャンピオンをrun_077 S |
| cmd_2367 | cmd_2366でL1チャンピオン21体中MATCH 8/MISMATCH 12/未登録1と判明。 殿の問い「L0が同じで構成PFが違うならどう違うのか」に答える分析。 MISMATCH 12体それぞれのGS選出パラメータ vs 本番パラメータを並べ、 乖離のパターン(component_set/lookback/top_n等)を分類する。 | dm-signal | 04-28 | MISMATCH 12体+未登録1体の詳細比較をMarkdo |
| cmd_2368 | run_077のGSはPydanticバリデーションなしでパラメータグリッドを生成している。 GS選出チャンピオン21体のconfigを本番ビルディングブロック(MomentumFilter等)に通し、 バリデーションエラーで弾かれるパターンがないか検証する。 本番バリデーション下でGS結果と現行本番configが同一になるか確認する。 | dm-signal | 04-28 | cmd_2366選出21体を本番Pydantic入口(Pip |
| cmd_2369 | 殿の仮説: 本番シン忍法はWF-α(Walk-Forward OOS alpha)で選出された可能性。 今回のGS結果(cmd_2359-2365 SQLite)からWF-α方式でチャンピオンを選出し、 (1)事後選出(cmd_2366)との差異、(2)本番configとの一致率を比較する。 WF-α-CAGR=激攻、WF-α-NHF=常勝、WF-α-MaxDD=鉄壁。 | dm-signal | 04-28 | cmd_2369: 7忍法run_077 SQLite DB |
| cmd_2370 | cmd_1902のα6指標手法(alpha_t = return_t - beta * spy_return_t)を使い、 本番シン忍法20体と事後GS選出21体のβ調整α6指標を算出・比較する。 本番L1の月次リターンは本番DB(FoFパイプライン計算済み)から読取。 事後GS L1の月次リターンはrun_077 GS SQLiteから読取。 | dm-signal | 04-28 | 本番シン忍法20体とcmd_2366 L1事後GS21体につ |
| cmd_2372 | 本番シン忍法20体と事後GS選出21体のWF β調整α6指標を算出・比較する。 第4の試練: IS=24M、OOS=6M、step=3M、20ステップ。各ステップでβを再推定し、 OOS窓でα6指標(alpha-CAGR/NHF/MaxDD/MRU/Calmar/UWP)を計算。 20個の独立OOS結果を連結して最終α6を算出。 | dm-signal | 04-28 | cmd_2372: 本番シン忍法20体と事後GS21体のSP |
| cmd_2373 | cmd_2366のチャンピオン選出スクリプトが忍法×モードごとに正しい目的関数で選出しているか検証する。 疑い: (1)鉄壁のMaxDD最小化で符号が逆転していないか (2)異なる忍法で同一パターンが選ばれる原因 (3)常勝3忍法のMaxDD完全一致(-0.3371)の原因特定。 | dm-signal | 04-29 | cmd_2366 L1チャンピオン選出ロジックを監査し、選出 |
| cmd_2374 | 本番シン忍法20体のconfigパラメータ(component_set+lookback+top_n)でGS SQLiteを検索し、 該当パターンの月次リターンと本番DBのmonthly_returnsが一致するか検証する。 本番configがGS空間内に存在すること自体の確認+リターンパリティ。 | dm-signal | 04-29 | 本番シン忍法20体の同一パラメータpattern_idをGS |
| cmd_2375 | cmd_2374で発見した「L1パリティ0/20 FAIL」の原因がmonthly_return(close) vs monthly_return_open(open)の列取り違えかを確認する。 本番DB側をmonthly_return_openに揃えて再突合し、GS L1にバグがあるか白黒つける。 | dm-signal | 04-29 | cmd_2375としてcmd_2374ベースのmonthly |
| cmd_2376 | cmd_2375で判明した「選択ブロック忍法17体のL1パリティ不一致」の原因を特定する。 追い風-激攻(oikaze)の不一致月を1つ取り、本番PipelineEngine(MomentumFilterBlock)と GS simulate_pattern()がその月にどのL0四神を選択したかを比較し、差分の根因を特定する。 | dm-signal | 04-29 | 追い風-激攻 oikaze_N4_0569_18M_N1_R |
| cmd_2377 | cmd_2375で17/20不一致だった原因を特定する。cmd_2376は1ヶ月1体しか確認せず大差月を見逃した。 全20体×共通期間のみでmonthly_return_open突合し、共通期間内にvalue_diffがある月について 本番holding_signal(保有PF) vs GS simulate_patternの選択結果を比較する。 | dm-signal | 04-29 | cmd_2377: シン忍法20体のmonthly_retu |
| cmd_2378 | 追い風(oikaze)のsimulate_pattern()を本番MomentumFilterBlockと完全一致するよう修正する。 ラルフループ: コード読み比べ→差分特定→修正→パリティ検証→不一致あれば再修正→100%達成まで。 追い風3体(激攻/常勝/鉄壁)の本番monthly_return_openと完全一致(1e-6以内)が完了条件。 | dm-signal | 04-29 | run_077_oikaze.pyのNumPy快速版を検証し |
| cmd_2382 | cmd_2378の3修正を四つ目に適用。修正版で全パターン計算→新SQLite生成→本番一致100%検証→旧SQLite削除。 | dm-signal | 04-29 | cmd_2382: run_077_yotsume.pyへc |
| cmd_2381 | cmd_2378の3修正(close累積momentum/全履歴shift/初回signal等ウェイト)を変わり身に適用。 修正版で全パターン計算→新SQLite生成→本番monthly_return_openと100%一致検証→旧SQLite削除。 | dm-signal | 04-29 | 変わり身run_077にcmd_2378の3修正（produ |
| cmd_2383 | cmd_2378の3修正を抜き身に適用。修正版で全パターン計算→新SQLite生成→本番一致100%検証→旧SQLite削除。 | dm-signal | 04-29 | run_077_nukimi.pyにcmd_2378の3修正 |
| cmd_2384 | cmd_2378の3修正を加速Dに適用。修正版で全パターン計算→新SQLite生成→本番一致100%検証→旧SQLite削除。 | dm-signal | 04-29 | run_077_kasoku_diff.pyにcmd_237 |
| cmd_2386 | Phase 1.96でrun_077全7忍法のsimulate_pattern修正完了(cmd_2378-2385)。修正版SQLiteでL1チャンピオン再選出し本番シン忍法configと突合する。cmd_2366の再実行。修正前SQLiteで選出したチャンピオンは無効。 | dm-signal | 04-29 | cmd_2366_l1_champion_select.py |
| cmd_2387 | cmd_save.sh L2861のcheck_parity_ac_requirementsがtitle/purposeの文脈を見ず語句マッチのみで判定するため、分析cmdでFP発火する(cmd_2386で実証。startup gateでもFP率ALERT)。過去形コンテキスト(修正後/修正版/修正済み/完了)を除外し本番DB変更cmdのみトリガーさせる。 | infra | 04-29 | Check 19 _CHECK19_TRIGGERに過去形除 |
| cmd_2388 | lessons_shogun.yaml 35件(上限35件)到達で新教訓記録不可。成長ループが断絶。LS023-LS035の13件を既存クラスタに吸収し空きを確保する。v1→v3統合(97→22件)と同パターン。 | infra | 04-29 | lessons_shogun.yaml: LS023-LS0 |
| cmd_2389 | check_ac_phase_mixing(L3033)のFP率66%(3件中2件FP、startup gate ALERT)。impl_hitsのキーワード(修正/変更/追加等)が殆どのcmdにマッチし、ACに計測/commit語が偶然含まれると誤発火。AC単位の文脈判定を追加しFPを削減する。 | infra | 04-29 | check_ac_phase_mixingにAC単位文脈判定 |
| cmd_2391 | cmd_2386で再選出したGS事後最適チャンピオン21体のうちbunshin(0軸)を除く6忍法×3モード=18体について、gs_grid_robustness.pyでLB×α6グリッドを生成し、championの面的頑健性を検証する。過適合リスクの定量評価。cmd_2357(L0 12体)と同パターン。 | dm-signal | 04-29 | 6忍法×3モード=18体のL1 GS robustnessを |
| cmd_2392 | cmd_2386で再選出したGS事後最適21体を本番DBにhide状態で登録する。既存シン忍法20体は維持。フォルダ「GSシン忍法」を新規作成し、名前は「GSシン{忍法名}-{モード}」(例: GSシン抜き身-鉄壁)。登録後fullrecalculate→パリティ検証。 | dm-signal | 04-29 | GSシン忍法フォルダーを作成し、cmd_2386 GSチャン |
| cmd_2393 | GSL1 SQLite 7本が設計書§3.1の命名ルール(outputs/grid_search/{YYYYMMDD}/{layer}/{method}/gs_{ninjutsu}.db)に従っていない。cmd番号付き命名やファイル名揺れ(_results_fast/_grid_results_fast)を正規化する。GSL2実行前に入力元パスを確定させる。 | dm-signal | 04-29 | GSL1 SQLite 7本を outputs/grid_s |
| cmd_2394 | GSL2 GS実行の前提。GSシン忍法21体のUUID+source_type:local_sqlite+GSL1 SQLite正規パスを含むuniverse YAMLを作成する。okugi_shin_ninpo_20.yamlをベースに差し替え。 | dm-signal | 04-29 | GSL2用のGSシン忍法21体 universe YAMLを |
| cmd_2396 | 軍師がkasoku_diffに適用したOOMkill対策(commit 40d40e55: monthly_wide_frame除去+numpy直接SQLite書込み)を残6忍法に横展開。各run_077の_run_mp()内のmonthly_wide_frame()呼出し除去+main関数のwrite_grid_search_sqlite呼出しをnumpy配列パスに変更。1忍法あたり変更2箇所。 | dm-signal | 04-29 | run_077残6本(bunshin/oikaze/kawa |
| cmd_2397 | 殿指摘: GS SQLite方式の実行速度が遅すぎる。CSV時代より遅い。高速化必須。 現状: L2 kasoku_diff(~1.15Mpat)が56分以上かかりまだ完了しない。DB 18GB。 根因: gs_sqlite_output.py/gs_db_utils.pyにPRAGMA設定がゼロ。SQLiteデフォルト(journal_mode=DELETE, synchronous=FULL, cache_size=2MB)のまま~190M行のmonthly書込み。加えてWSL2 /mnt/c cross-filesystem書込みペナルティ。 対策: (1)PRAGMA最適化(journal_mode=OFF, synchronous=OFF, cache_size拡大) (2)Linux-native一時ファイル書込み+完了後/mnt/cへmove (3)CREATE INDEX AFTER INSERT (4)before/after計測で効果確認。 | dm-signal | 04-29 | GS SQLite書込み高速化完了: PRAGMA+blob |
| cmd_2400 | 本セッションで発見した2件のインフラバグを修正。 (1)ninja_monitor再起動時にsingletonロックが残存し新インスタンス起動不能(4回連続SINGLETON-EXIT)。 根因: AUTO-RESTART時にold processのflock解放前にnew processが起動するrace condition。 (2)バックグラウンドタスク実行中のCLIをidle判定。hayateが1h08mバックグラウンド実行中なのにsnapshotがidle表示。 根因: プロンプト検出=idle判定だが、codex/claudeのbackgroundモード時はプロンプト表示+裏で実行中。 | infra | 04-29 | ninja_monitorのbackground/Worki |
| cmd_2401 | 殿裁定(2026-04-29): kagemaru=low, hayate/saizo=medium。 settings.yamlのmodel_nameが実態と乖離(hayate/saizo=gpt-5.5-highのまま)。 kagemaruにmodel: sonnet残骸あり。実態に合わせて更新し、 全Codex忍者のeffort実態をcapture-paneで確認する。 | infra | 04-29 | config/settings.yamlを指定どおり更新し、 |
| cmd_2402 | cmd_2399(MP_WORKERS=6)がOOM Killで失敗。軍師自己分析: fork×6のRSS累積が16GB超。 MP_WORKERS=1で安全に再実行する。前回L2実績(cmd_1844: 944Kpat直列OOMなし)が安全実績。 高速化commit(PRAGMA+blob+Linux-native)は有効なままなのでSQLite書込みは高速。 | dm-signal | 04-29 | cmd_2402再実行完了。GS_MP_WORKERS=1 |
| cmd_2403 | 将軍のinbox_watcherがASW_DISABLE_ESCALATION=1で起動されており、nudgeが届かない。 殿が2.5時間不在の間にinbox7件蓄積→気づかず。殿裁定: バグとして修正。 ninja_monitor.sh L2285-2288とdaemon_watchdog.sh L175-178のshogun分岐を削除し、 全エージェント共通の起動パスに統一する。修正後にwatcher再起動で即反映。 | infra | 04-29 | ninja_monitor.sh と daemon_watc |
| cmd_2399 | 高速化版(c563ec23+b5a009ef)でGSL2 kasoku_diffを再実行。 旧版: 60min超+21GB DB+OOMkill。新版: 見込み26-59sec+1.4GB DB。 旧DBは削除済み。L2/shin/ディレクトリ空。ゼロからの再実行。 | dm-signal | 04-29 | — |
| cmd_2405 | GSL2残6忍法の第1弾。bunshinは0軸(LBなし、top_nのみ)で最軽量。 kasoku_diff実績(1.15Mpat, 543sec, RSS 10.1GB)よりパターン数が少なく安全。 SHMリーク修正(commit 48356b69)適用済み。 | dm-signal | 04-29 | GSL2 shin 21体universeでrun_077_ |
| cmd_2406 | 「1本ずつ昇格→委任→次」が意志依存のまま。cmd_save.shにdraft複数BLOCKはあるが、 Edit toolでのpending昇格時に既存pending cmdの存在チェックがない。 pre-write-edit-combined.shにshogun_to_karo.yaml status:pending書き込み時の 既存pending検出BLOCKを追加し、自動化×強制で1CMD1ゲートを保証する。 | infra | 04-29 | — |
| cmd_2410 | GSL2残2忍法の第5弾。nukimi(抜き身)は2軸LB忍法(SingleViewMomentumFilter、base+skip)。 2軸忍法はパターン数が多い。kasoku_diff(2軸、1.15Mpat)実績で安全確認済み。 | dm-signal | 04-29 | run_077_nukimi.py (抜き身L2 GS) を |
| cmd_2411 | GSL2最終弾。kasoku_ratio(加速R)は2軸LB忍法(MomentumAccelerationFilter method=ratio)。 kasoku_diff(同フィルタ method=diff)と同パターン数。全7忍法完了でL2チャンピオン選出に進める。 | dm-signal | 04-29 | run_077_kasoku_ratio.py GSL2実行 |
| cmd_2412 | GSL2全7忍法GS完走(cmd_2402-2411)。L2 SQLite 7本からチャンピオンを選出する。 cmd_2366(L1チャンピオン選出)と同パターン。cmd_2366_l1_champion_select.pyをL2用に実行。 7忍法×3モード(激攻CAGR/常勝NHF/鉄壁MaxDD)。吸収判定後の体数がL2の確定体数になる。 | dm-signal | 04-29 | L2 SQLite 7本から7忍法×3モード=21チャンピオ |
| cmd_2413 | cmd_2412で選出したL2チャンピオン21体のうちbunshin(0軸)を除く6忍法×3モード=18体について、 gs_grid_robustness.pyでLB×α6グリッドを生成し、championの面的頑健性を検証する。 cmd_2391(L1 robustness)と同パターン。過適合リスクの定量評価。 | dm-signal | 04-29 | L2 SQLite 6本(bunshin除く)で18体のLB |
| cmd_2414 | robustness-verification-catalog §0アルファ空間原則: ロバストネスの第一指標=パラメータ空間全体のCAGR正率。 cmd_2413はpeak_ratio(隣接±1比)のみ。全パターンのα-CAGR正率を未計算。 L2 SQLite 7本の全パターンについてβ調整α-CAGRを計算し、正率を忍法×モード別に報告する。 殿指摘: 「いつもは全探索でやっていなかったか？」 | dm-signal | 04-29 | L2 SQLite 7本の全パターンについてβ調整alpha |
| cmd_2415 | 設計書§5.3の進捗表がPhase 10=★次★のまま。実態: Phase 10-12全完了+SHM修正。 進捗表を実態に合わせて更新し、次Phase(13: 本番DB登録+パリティ確認)を追記する。 | dm-signal | 04-29 | docs/design/gs-data-normalizat |
| cmd_2417 | inbox_watcherがWSL2 NTFSのinotify検知後の処理でhangし、nudgeが送信されなくなる。 kagemaru watcher=16:03停止、hayate watcher=17:04停止(家老訂正報告 22:43)。 STALL 3連続の真因。hang検知+自動再起動を追加する。 | infra | 04-29 | inbox_watcher hang検知heartbeat+ |
| cmd_2418 | 軍師LG014(道具を疑え)がLevel 2(ドキュメント=意志依存)のまま。 gate_ninja_workaround_rate.shにcategory集計を追加し、同一category 3件以上→WARN。 軍師レビュー前に自動表示されるため意志依存がゼロになる。 本セッションのrfs binary_checks保護バグ(cmd_2397)はこのgateがあれば事前検出できた。 | infra | 04-29 | gate_ninja_workaround_rate.sh |
| cmd_2421 | cmd_publish.shを実装したが、instructions/shogun.md §cmd起票手順に未反映。 将軍の起票ワークフローを「Edit(draft)→cmd_publish.sh」の2ステップに更新する。 | infra | 04-29 | instructions/shogun.mdのcmd起票手順 |
| cmd_2420 | config.toml共有でhayateがlow(殿裁定medium)。Codex CLIは-c model_reasoning_effort=XXXで 起動時override可能(codex --help確認済み)。cli_profiles.yamlにper-agent launch_argsを追加し、 settings.yamlのmodel_nameからeffort部分を抽出→起動コマンドに-cフラグを付与する。 | infra | 04-29 | cli_launch_cmd()にmodel_nameからe |
| cmd_2416 | cmd_2412で選出したL2チャンピオン21体を本番DBにhide状態で登録する。 cmd_2392(L1 GSシン忍法21体登録)と同パターン。 フォルダー「GSシン奥義」を新規作成。名前は「奥義-GS-{忍法名}-{モード}」(例: 奥義-GS-加速R-常勝)。 登録後fullrecalculate→L2 GS SQLiteとのパリティ検証。 | dm-signal | 04-30 | — |
| cmd_2419 | commit 48356b69のSHM修正(workers<=1でUSE_SHM=False + Phase 0.5 psm_*自動清掃)が kasoku_diffのrun_077にのみ適用。残6忍法(bunshin/oikaze/kawarimi/yotsume/nukimi/kasoku_ratio)に横展開する。 cmd_2396(OOMkill対策横展開)と同パターン。 | dm-signal | 04-30 | commit 48356b69のSHMリーク対策をrun_0 |
| cmd_2422 | cmd_2412で選出したL2チャンピオン21体のうち分身3体でtop_n>2(subset_size=4等)が 本番Pydanticスキーマ(top_n: le=2)に違反しPortfolioRepository.load()全PFロード失敗を引き起こした。 L2 GS SQLite 7本からsubset_size<=2のパターンのみでチャンピオンを再選出する。 cmd_2368(L1 Pydanticバリデーション検証)と同パターン。 | dm-signal | 04-30 | cmd_2422: L2 SQLite 7本をsubset_ |
| cmd_2423 | PortfolioRepository.load()で1体のPydanticバリデーション失敗が全PFロード失敗を引き起こす構造的欠陥を修正。 cmd_2416事故(top_n=4→全168体API消失)の再発防止。 L1: API応答にskipped情報を含める(サイレント禁止)。L2: logger.errorでBEログ記録。Render内完結。 | dm-signal | 04-30 | PFロード時に個別PFのバリデーション失敗をskippedと |
| cmd_2425 | workers=1固定運用(LG025 OOM防止)+gs-runbook.md結論(fork CoWで十分)により run_077の6忍法スクリプトのSHMコードは全てデッドコード。削除してコードを簡潔にする。 cmd_1037(PPE実験スクリプト)は実験記録として保存(軍師推奨)。 | dm-signal | 04-30 | run_077の6忍法からSHM専用経路を削除し、legac |
| cmd_2424 | cmd_2422で再選出した制約内(top_n<=2)L2チャンピオンを本番DBに登録する。 cmd_2416(Phase 13)の再実行。cmd_2423(耐障害化)が本番に入った状態で安全に実行。 | dm-signal | 04-30 | cmd_2422 constrained L2 champi |
| cmd_2426 | Wood, Roberts, Zohren (2023) "X-Trend: Few-Shot Learning for Trend Following"(arXiv:2310.10500)を 原論文精読し、金融ML知識辞書methods/エントリを作成する。 DMS-TVP(M31)の競合手法。Few-Shot+CPDでレジーム転換対応。2018-2023激動期でTSMOM比10倍リターン。 | dm-signal | 04-30 | arXiv:2310.10500v2をTeX sourceま |
| cmd_2429 | Ong & Herremans (2024) "DeepUnifiedMom: Unified Deep Learning for Multi-Task Momentum"(arXiv:2406.08742)を 原論文精読し、金融ML知識辞書methods/エントリを作成する。 Multi-Gate Mixture of ExpertsでFast/Mid/Slowモメンタムを統合。DMS-TVPの「1モデル選択」より柔軟な混合。 | dm-signal | 04-30 | arXiv:2406.08742 DeepUnifiedMo |
| cmd_2431 | Keller & Keuning "Vigilant Asset Allocation(VAA)" (SSRN 2017) + "Bold Asset Allocation(BAA)" (SSRN 2022)を 原論文精読し知識辞書エントリ作成。複合Momentum Score(1/3/6/12M加重)で毎月ベスト1資産に全額投資。 DM-Signalのレイヤー別Top-1選出に直接適用可能な手法。 | dm-signal | 04-30 | VAA(SSRN:3002624)+BAA(SSRN:416 |
| cmd_2432 | Ehsani & Linnainmaa (2022) "Factor Momentum and the Momentum Factor" (J. Finance, Vol.77(3), pp.1877-1919)を原論文精読し知識辞書エントリ作成。 51ファクターのリターンに時系列autocorrelationを発見。先月リターン基準のファクターローテーション。α=32bps/月。 | dm-signal | 04-30 | NBER WP25551 / Journal of Fina |
| cmd_2433 | "Improving Portfolio Optimization Results with Bandit Networks" (arXiv:2410.04217, 2024)を 原論文精読し知識辞書エントリ作成。Adaptive Discounted Thompson Sampling(ADTS)+Combinatorial ADTS(CADTS)。 非定常報酬分布に対応するsliding window+割引機構。regret bound証明付き。 | dm-signal | 04-30 | ADTS/CADTS原論文(arXiv:2410.04217 |
| cmd_2434 | "Weak Aggregating Specialist Algorithm" (Computational Economics, 2023)を 原論文精読し知識辞書エントリ作成。各戦略を「エキスパート」としてweight更新。 理論的regret bound証明付き。Online Portfolio Selection分野の手法。 | dm-signal | 04-30 | WASA(Weak Aggregating Speciali |
| cmd_2435 | DMS-TVPビルディングブロック設計の前提。本番で選択可能な14種lookback(10D-24M)から 5帯域(超短期/短期/中期/長期/超長期)の最適lookbackを計算で決定する。 L0/L1/L2 GS SQLiteの全パターンでlookback別CAGR/Sharpe分布を集計し、 5帯域に自然な境界を発見→各帯域の最適値を特定。 | dm-signal | 04-30 | GS SQLite全レイヤーから単一lookback 18種 |
| cmd_2436 | DMS-TVP設計書(dm-signal/dms-tvp-layer-selection-design.md)のPhase 1-2。 Levy & Lopes (2021)のDMS-TVP分類器を忠実実装し、L0四神12体の月次リターンデータで 5lookback[10D,21D,84D,210D,315D]の動的選択を実行。固定lookbackとのCAGR/MaxDD比較。 | dm-signal | 04-30 | DMS-TVP L0四神12体バックテストを実装・実行し、指 |
| cmd_2437 | cmd_2436は各PF個別にlookback選択するバックテストだったが、殿の目的は 「L0の12体の中から毎月1体を選び毎月リバランス」。設計書§2.1修正済み。 12体を「モデル」と見なし、各PFの月次リターン符号をベイズ更新で逐次学習し、 argmax πで来月保有する1体を毎月選出。固定EW(等配分12体)との比較。 | dm-signal | 04-30 | DMSでL0四神12体を12モデルとして扱い、monthly |
| cmd_2438 | cmd_2437でα=0.99の切替が110ヶ月中3回と少なすぎ、EW等配分に劣後した。 根因: α=0.99の忘却が遅すぎて実質固定保有。αを下げて反応速度を上げる。 α={0.90,0.95,0.99}×λ={0.95,0.99}の6組合せでグリッド検証し最適αを特定。 | dm-signal | 04-30 | DMS L0 α/λ感度分析を実装・実行し、6組合せのCAG |
| cmd_2439 | Aveシリーズ(激攻/常勝/鉄壁)3体からDMS argmaxで毎月1体選出。 K=3(7モデル)でcmd_2437/2438の12体選出(K=12)より収束が速い。 lookback候補2セットで比較: (A)設計書[10D,21D,84D,210D,315D] (B)原論文[21D,42D,84D,126D,168D,252D]。 3レイヤー(L0/L1/L2)×2セット=6条件。α=0.90,λ=0.95(cmd_2438最善)固定。 | dm-signal | 04-30 | 本番PostgreSQL monthly_return_op |
| cmd_2440 | 設計書v1.0に基づき、任意PF群からN体EW全組み合わせを網羅探索する汎用スクリプトを実装する。 初回実行として奥義-GS-21体(2体210通り+3体1,330通り=1,540通り)を4検証手法×7指標+レジーム分析で評価。 単体より強い組み合わせを発見する。再利用可能な道具として設計(入力PF差替えで繰り返し実行可能)。 | dm-signal | 04-30 | combo_exhaustive_search.pyを新規実 |
| cmd_2441 | cmd_2440で実装したcombo_exhaustive_search.pyを四神12体に適用。 12C2=66通り+12C3=220通り=286通りを4検証手法×7指標+レジーム分析で評価。 奥義-GS-21体の結果(α-Calmar 7.58)と比較し、レイヤー間の効果を定量化する。 | dm-signal | 04-30 | シン四神12体をDBからCSVソース化し、combo_exh |

## 2026-05

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_2442 | combo_exhaustive_search.py L95のdropna(how="any")が全PFデータを最短PFの期間に切り詰めている。 単体パフォーマンスが本番DBと乖離(抜き身-激攻: 本番CAGR 100.6% vs 出力120.8%、20pp乖離)。 修正: 単体は各PFの全期間で計算、EW組み合わせは構成PF共通期間で計算。 修正後に奥義-GS-21体+四神12体を再実行し、gist記事2本を更新する。 | dm-signal | 05-01 | combo_exhaustive_search.pyの単体評 |
| cmd_2443 | 各忍法(7本)のpipeline_configで本番バリデーションが受け入れるtop_nの有効範囲を特定する。 FoF登録時にtop_n=1,2,3,4のどこまでvalidateが通るかを忍法毎に確認する。 | dm-signal | 05-02 | 7忍法×top_n(1,2,3,4)のpipeline_co |
| cmd_2444 | cmd_2416事故で奥義-GS-登録時にPydantic top_n le=2違反が発生した。 SSS奥義は4コンポーネントで問題なく稼働(top_n=1)。 登録スクリプトがGSのsubset_sizeをPortfolio直下top_nに誤入力した可能性を確認する。 | dm-signal | 05-02 | subset_size/top_nがPortfolio直下t |
| cmd_2447 | cmd_2412で選出した制約なしGSL2チャンピオン21体を本番DBに登録する。 旧奥義-GS-(一律subset_size=2)は将軍が削除済み。 cmd_2424の修正版スクリプト(top_n=1固定)で登録。hide=true。 フォルダー「GSシン奥義」を新規作成。命名: 奥義-GS-{忍法名}-{モード}。 | dm-signal | 05-02 | cmd_2412制約なしL2チャンピオン21体を本番DBへ奥 |
| cmd_2448 | cmd_2447でAC4 P1 FAIL: holding_signal vs GS SQLite 54行不一致(変わり身51+他3)。 パリティ不一致は論外。原因特定+修正+P1再検証で不一致0行を達成する。 | dm-signal | 05-02 | cmd_2447 P1 holding_signal vs |
| cmd_2449 | cmd_2447+2448で制約なし奥義-GS-21体の本番登録+パリティ完全一致を達成。 この新21体でEW3全1,330通りを網羅探索し、WF-β調整後の4指標Top1を秘奥義-GS-候補として選出する。 gist記事(note_gs_okugi_exhaustive)の手法を制約なし21体で再実行。 | dm-signal | 05-02 | cmd_2449: 奥義-GS 21体のEW3網羅探索を完了 |
| cmd_2450 | cmd_2449で選出した秘奥義-GS-候補4体(WFα4指標Top1)を秘奥義フォルダーに本番登録する。 旧秘奥義6体は2026-04-25浄化で削除済み。新4体で再構築。 | dm-signal | 05-02 | 秘奥義4体(激攻/常勝/鉄壁/堅守)を本番DBへhide登録 |
| cmd_2451 | FEのMonthly Trade画面で最新のPosition Start行がUUID生表示になっている(殿スクショ確認)。 Dashboard画面では同じPFがticker表示されており、Monthly Trade固有の名前解決ロジックに問題がある。 過去月(04/01以前)はticker表示で正常のため、最新月のみの問題。 | dm-signal | 05-02 | Monthly TradeのFoF pending行でUUI |
| cmd_2452 | Standard PFの5月holding_signalは4月から変化(11/56体)しているが、 FoFの15体(GSシン系)が5月も4月と同一のholding_signal。 Phase 4.1はstandard PFのみ対象(L2442)。FoFのsignal再計算パス(sync-fof/recalculate_fof)が 5月に対して正しく動作していない根因を特定する。 | dm-signal | 05-02 | FoF L3生成パスは正常稼働。2026-05-01 01: |
| cmd_2453 | cmd_2452偵察で判明: FoFのholding_signal(構成PF UUID列)は正常だが、 Monthly Trade画面とDashboard画面のFoF保有ポジション表示が5月分の下層ticker展開を参照していない。 両画面で5月のprecomputed display_ticker_weightsを正しく参照するよう修正する。 | dm-signal | 05-02 | FoF表示のprecomputed ticker weigh |
| cmd_2454 | GSL1(21体)とGSL2(21体)の全42体が理論最長期間より1-26ヶ月短い。 120ヶ月=10年のハードリミットが入っている疑い。 recalculate_fof.pyまたはFoF signal生成ロジックで120ヶ月制限をかけている箇所を特定する。 | dm-signal | 05-02 | FoF期間短縮の主因候補を特定。120ヶ月は再計算ではなくM |
| cmd_2455 | signalsテーブルのUPSERTでupdated_atが記録されず、holding_signalの変更履歴が追えない。 コード修正で過去の保有シグナルが変わったかを事後検証できない問題を解決する。 殿指示: 「いつ何から何に変わったかは追えた方がいい」(2026-05-02)。 | dm-signal | 05-02 | signals/fof_component_weights |
| cmd_2456 | 将軍がBLOCKされた後に教訓を記録せずに次のcmdを起票するパターンが直近50cmdで6回発生。 現行はWARN→累計昇格BLOCKだが、累計までの間に教訓なしcmdが量産される。 初回からBLOCKにして教訓サイクルの断絶を構造的に防止する。殿指示「将軍のCMD起票能力を成長させよう」(2026-05-02)。 | infra | 05-02 | 前cmd BLOCK後の教訓未記録チェックをWARNから即B |
| cmd_2460 | 30スキル中15件が「覚えていれば使う」=意志依存で/clearで消える。 既存の自動トリガー(hook/gate/inbox_watcher)にスキル発動催促を接続し、 使うべきタイミングで自動的にスキル名が提示される仕組みを構築する。 殿指示「スキルはいつ使うかを設定するのが大事」+「自動発動の仕組みに接続せよ」(2026-05-02)。 | infra | 05-02 | スキル自動発動トリガーをcmd_complete_gate/ |
| cmd_2459 | Gate/Hookで集めたデータがスキルに自動還流する基盤を構築する。 現状30スキルは静的手順書で成長しない。Gate=データ収集、スキル=環境整備のサイクルを接続し、 全スキルに共通の学習ループを1つの基盤で実現する。 殿指示「スキル自体が成長する仕組みがないと消火作業になる。Gateはデータ集め、環境を整えることが真の目的」(2026-05-02)。 | infra | 05-02 | スキル実行ログ、Gate FAIL→スキル注意ポイント還流、 |
| cmd_2461 | CLAUDE.mdを正本としAGENTS.mdをsed自動変換で生成。fork元のbuild_instructions.shパターン適用。 手動同期の意志依存を排除しCLI切替時の不整合をゼロにする。 | infra | 05-02 | cmd_2461は既存実装でAC充足。build_instr |
| cmd_2462 | instructions/*.mdの共通部分をcommon/に、CLI固有部分をcli_specific/に分離。 build_instructions.shで自動合成。1箇所修正で全ロール×全CLI反映。fork元パターン適用。 | infra | 05-02 | instructions 3層分離とbuild生成経路を現物 |
| cmd_2466 | lib/cli_adapter.shにget_model_display_name関数を追加し、各エージェントのモデル表示名を profile SSOT(cli_profiles.yaml)から取得できるようにする。 fork元偵察(cmd_2465)で発見したP1学習ポイント。現在tmuxペインのモデル表示(M:GPT等)は ninja_monitor.shが独自ロジックで生成しておりcli_adapterと分離している。 | infra | 05-02 | cli_adapterにget_model_display_ |
| cmd_2469 | skills/skill-creator/SKILL.mdをAnthropic公式ガイド準拠版にアップグレードする。 7項目チェック(目的/TRIGGER/DO NOT TRIGGER/入出力/エラー/テスト可能性/重複)を構造強制し、 frontmatterのargument-hint/user-invocable記入を検証する。 modelフィールドはmulti-CLI原則に反するため非推奨警告(殿裁定2026-05-02)。 | infra | 05-02 | skill-creatorに7項目チェックリストとfront |
| cmd_2470 | 既存37スキルのSKILL.md frontmatterにargument-hintとuser-invocableフィールドを追加する。 fork元偵察(cmd_2465)で発見したP2学習ポイント。現在は引数ヒントがなく、 内部スキル(gate-sync等)もユーザーリストに表示される。 modelフィールドはmulti-CLI原則に反するため追加しない(殿裁定2026-05-02)。 | infra | 05-02 | AC1/AC2範囲でskills/*/SKILL.mdのfr |
| cmd_2471 | Codex CLIにClaude Codeと同じmemory MCPサーバーを接続し、全CLIでMCPが使えるようにする。 現在Codex側は「No MCP servers configured yet」。codex mcp addで接続するだけで解決する。 殿指摘「codexもMCPを利用可能では？」(2026-05-02)。将軍のOpus固定前提を解消する。 | infra | 05-02 | Codex global MCPにmemoryサーバーを追加 |
| cmd_2472 | deploy_task.shが生成する報告テンプレートにassumption_invalidationとbinary_checksの デフォルト値(プレースホルダ構造)を追加する。 gate_fire_logでFAIL TOP2がassumption_invalidation MISSING(389回)+binary_checks MISSING(290回)= 全FAIL765件中679件(89%)。テンプレートに構造が存在しないため忍者が/clear後に記入できない。 | infra | 05-02 | deploy_task生成テンプレートのassumption |
| cmd_2473 | skill_execution_log.shがdashboard-updateスキル実行時にgate_report_formatで判定しているが、 dashboard-updateは報告YAMLを扱わないスキル。判定ゲートの誤接続でFAIL率100%(30/30)。 正しいゲートに接続するか、dashboard-update固有の成功判定に修正する。 | infra | 05-02 | dashboard-updateスキル実行結果をdashbo |
| cmd_2474 | bulletin_notify型メッセージのinbox_mark_read時に、bulletin_board.yamlの該当エントリが 実際にRead toolで読まれたかをPostToolUse hookで検証する。 未読の掲示板エントリがある状態でinbox_mark_readすると警告を出す。 殿指摘「掲示板は確認しているか」(2026-05-02)。将軍がinbox_mark_readを機械的に実行し 掲示板の実質内容を読まない問題を自動化×強制で解消する。 | infra | 05-02 | — |
| cmd_2475 | cmd_publish.shの実行前にBLOCK条件を事前排除するpre-flightチェックを追加する。 現在はcmd_save.shがBLOCK→将軍が手動修正→再試行の事後対処ループ。 事前に(1)教訓空き件数(2)前cmdの教訓記録済みかを検証し、不足なら具体的な解消手順を提示する。 なぜなぜ7回の結論: 事後の教訓自動記録は品質を下げる。事前防止が正しい方向(殿裁定2026-05-02)。 | infra | 05-02 | cmd_publish.sh pre-flightの存在と制 |
| cmd_2476 | lesson_write_shogun.shのenforcementが「既存自動強制」のみの場合BLOCKする。 本セッション教訓6件中5件が消火(既知パターン再発記録)。品質向上ゼロ。 殿指示「品質向上にフォーカス。消火での誤魔化しはないか」(2026-05-02)。 | infra | 05-02 | lesson_write_shogun.shのenforce |
| cmd_2477 | スキル学習ループの消火構造を根本解消する。 軍師なぜなぜ7回の結論: 品質未定義のまま計測装置を作った→計測がゴミを生む→改善にならない。 殿「計測が結果につながらなければならない。因果とは過去と未来につながる」。 テストデータ除外で計測を実態に一致させ、quality_metricで品質を定義し、計測→結果の因果チェーンを接続する。 | infra | 05-02 | AC1完了: skill_execution_log.shで |
| cmd_2478 | 起票前確認hookを意志依存の手動追加から自動成長に変える。 cmd_save.shがWARN累計昇格BLOCKした時にcheck名をファイルに自動記録し、 次回cmd起票時にpre-write-edit-combined.shが動的に表示する。 殿「成長とは次に同じ事をしないこと」を環境に埋め込む。 | infra | 05-02 | preflight_autolearnの動的起票前確認表示を |
| cmd_2479 | CI実行332秒(5.5分)のテストスイートから不要テストを特定する。 殿「テストは負債。3問検証(リグレッション必要性/変更頻度/維持コスト)」。 前回調査(2026-04-15)からは40日経過。スクリプト削除・変更で状況が変わっている。 | infra | 05-02 | tests/unit/*.bats 154件を対象に、対象ス |
| cmd_2480 | CI実行332秒のうちTop 5テスト(120秒超=36%)をCoDD高速化する。 cmd_2479偵察でtimeout 2件(cmd_save_environment_change 32.9s, sync_lessons 32.2s)と 高コスト3件(cmd_save_diagnosis_quality 22.2s, deploy_task_ac_handling 18.0s, deploy_task_ac_version 15.2s)を特定。 CoDD台帳に30件の実績あり(cmd_save.sh -32%、deploy_task.sh -25%等)。同手法を適用。 | infra | 05-02 | AC1/AC3完了。timeoutしていた2本を15s以下へ |
| cmd_2483 | 軍師分析で特定されたインフラバグ3件を修正する。 karo_workarounds 102件中9件(8.8%)がこの3パターンに起因。 放置中もWAが蓄積し家老のトークンを浪費する。idle忍者に即配備。 | infra | 05-02 | AC1: yaml_field_set.shがbinary_ |
| cmd_2486 | skill_gate_feedback.shのスキル特定を名前推測(haystack keyword照合)から skill_execution_log.yamlの実行記録ベースに変更する。誤帰属によるゴミデータを根絶。 | infra | 05-03 | skill_gate_feedback.shのスキル帰属をh |
| cmd_2487 | つまずきパターンからSKILL.mdの手順自体を構造的に更新する変換器を実装する。 caution_points=付箋貼りではなく、手順に具体的防止ステップを自動追加する。 | infra | 05-03 | skill_execution_logのFAIL集計からスキ |
| cmd_2489 | SKILL.mdが参照するスクリプト・パスが変更された時、壊れる前に検知する監査仕組み。 段階0: つまずき記録(段階2)は事後検出。壊れる前の予防的検知が必要。 | infra | 05-03 | SKILL.md内script参照の存在・鮮度を監査するga |
| cmd_2490 | on_holdのcmdをcmd_publish.shに直接入力できるようにする。 現状: on_hold→Edit toolで手動draft変更→cmd_publish.sh。手動変更時にgate未通過で修正機会を逃す。 改善: cmd_publish.shがon_hold入力を受け付け、内部でon_hold→draft昇格→gate検証→pending→delegateの4ステップを実行。 | infra | 05-03 | cmd_publish.shでstatus=on_holdの |
| cmd_2491 | cmd_2490のrollback失敗リスクを根本解消する。 現状: on_hold→draft(YAML書込み)→cmd_save→失敗→rollback(壊れうる)。 改善: YAML書込みをcmd_save成功後に遅延。失敗時はYAML未変更(on_holdのまま)。rollback不要。 | infra | 05-03 | cmd_publish.shのon_hold公開経路を、cm |
| cmd_2492 | 報告YAMLテンプレートの必須フィールド欠落を配備経路に依存せず防止する。 現状: deploy_task.sh経由時のみgenerate_report_template()が走る。karo_direct/task YAML直接編集では未実行→必須4フィールド欠落(cmd_2481 hanzo r3で実証)。 改善: 忍者/clear Recovery Step 4.5でreport_pathのテンプレート検証+欠落フィールド自動補完。 | infra | 05-03 | 既存の不完全な報告テンプレートでも必須4フィールドを自動補完 |
| cmd_2493 | 215本のスクリプト(scripts/144+gates/37+hooks/34)を計測し、最適化ボトルネックを特定する。 台帳(codd_refactor_registry.md)の約100件と突合し、未計測スクリプトと再最適化候補を洗い出す。 | infra | 05-03 | scripts/*.sh 144本を安全なbash -n解析 |
| cmd_2495 | gate_silent_fallback.shがリグレッション(25ms→769ms、31x悪化)。 CoDD正規手順(spec→設計書→実装→計測→台帳記入)で台帳値25ms以下に復帰させる。 | infra | 05-03 | gate_silent_fallback.shの--help |
| cmd_2498 | gate_shogun_memory.shがリグレッション(9ms→82ms、9.1x悪化)。 601行。load_memory_cache()でMEMORY.mdをawk解析+6項目チェック(行数/陳腐化/重複/MCP obs数/curation日/sync鮮度)。 CoDD正規手順で台帳値9ms以下に復帰させる。 | infra | 05-03 | gate_shogun_memory.shをline-cou |
| cmd_2500 | gate_karo_startup.shがリグレッション(110ms→251ms、2.3x悪化)。 592行。前回3回最適化(464→225→190→110ms)。前回revert時に真因特定済み: _META_PIDS awk(deepdiveファイルon /mnt/c NTFS)が~100ms支配。WA rateキャッシュは効果なし(revert)。 CoDD正規手順で110ms以下に復帰。ボトルネックが/mnt/c I/O支配なら代替アプローチ(キャッシュ/遅延読込)をspec段階で設計。 | infra | 05-03 | gate_karo_startup.sh R4 CoDD再改 |
| cmd_2501 | gate_skill_script_refs.shが未最適化で408ms(偵察計測)。台帳未登録。 143行。全体がpython3ヒアドキュメントでSKILL.mdからスクリプト参照を抽出し存在確認+更新日比較。 python3起動コスト+pathlib走査がボトルネック候補。CoDD正規手順で初回最適化。 | infra | 05-03 | gate_skill_script_refs.shに短TTL |
| cmd_2502 | gate_autofix_proposal.shが未最適化で272ms(偵察計測)。台帳未登録。 178行。直近50件のgate_metrics.logからBLOCKパターンを集計し、instructions修正提案をinsights.yamlに還流する。 mktemp+tail+awk+insight_write.sh呼出しがボトルネック候補。CoDD正規手順で初回最適化。 | infra | 05-03 | gate_autofix_proposal.shに短TTL出 |
| cmd_2503 | gate_wa_data_quality.shがリグレッション(52.9ms→111ms、2.1x悪化)。213行。 前回(2026-04-18 hayate): 106.6→52.9ms(-50.4%)。CoDD正規手順で台帳値復帰。 | infra | 05-03 | gate_wa_data_quality.shの通常chec |
| cmd_2506 | gate_skill_health.shが未最適化で139ms(偵察計測)。台帳未登録。241行。 SKILL.mdのTRIGGER/MECE/DRY検証を行うgate。CoDD正規手順で初回最適化。 | infra | 05-03 | gate_skill_health.shの既定skills走 |
| cmd_2505 | gate_field_get.shがリグレッション(40ms→71ms、1.8x悪化)。213行。 前回(2026-04-18 saizo): 404→40ms(-90.1%)。CoDD正規手順で台帳値復帰。 | infra | 05-03 | gate_field_get.sh R2 CoDD再改善を完 |
| cmd_2508 | gateの最適化(cmd_2495-2507)は偵察計測値ベースで進行中。次はhooks+通常スクリプトを対象に、 頻度x実行時間=インパクトの観点で最適化ROI順位を付ける。 cmd_2493のTSVは呼出頻度あるが実行時間がbash -n(構文チェック)で正確でない。実測が必要。 | infra | 05-03 | hooks全34本をmedian 3runで実測し、Clau |
| cmd_2509 | 軍師利他提案: cmd_complete_gate.sh内でlesson_candidate(found:true)をlesson_write.sh自動呼出しで登録。 現状: 軍師LGTM→gate即時発火→家老lesson未登録→BLOCK→手動登録→再GATE(38%=5/13件)。 gate内でlesson_write.shを自動呼出しし、BLOCK→CLEAR往復を構造的に解消する。 | infra | 05-03 | cmd_complete_gateのlesson_candi |
| cmd_2511 | cmd_2508偵察結果: stop_check_inbox.shがインパクト1位(187,739 ms/day)。 未読0件時にinotifywait(5sタイムアウト)で毎回ブロック。inbox_watcher.shが同機能を提供しており冗長。 inotifywait待機ブロックを除去し、全エージェントのStop操作を高速化する。 | infra | 05-03 | stop_check_inbox.shの未読0件inotif |
| cmd_2514 | 家老バグ報告: ninja_monitorが/clear→CLI再起動した直後のCodex CLIは初期画面表示中。 inbox_watcherのpaste-buffer nudgeが空振りし、忍者がプロンプト待ち状態に陥る(5連発実績)。 deploy_task.shにpost-deploy re-nudge(5秒後に再送)を追加し、初期画面通過後にnudgeを確実に届ける。 | infra | 05-03 | — |
| cmd_2515 | cmd_2508偵察結果2位(31,915 ms/day)。Pre/PostToolUse両方で発火(1958回/day)×16.3ms。 tmux set-option 2回(state+timestamp)を1回に統合し、プロセス起動コストを削減する。 | infra | 05-03 | bash_state_hookのtmux state更新がP |
| cmd_2516 | スキル自動成長(段階3)の出力品質が不十分。report-write/verdict-check FAIL率100%が継続。 根因: (1)stumbling_pointsではなくgate名で帰属→防止ステップが的外れ(2)汎用テンプレートで具体性なし。 skill_auto_improve.shの出力テンプレートを改善し、実際のFAILパターンに対する具体的防止手順を生成させる。 | infra | 05-03 | skill FAIL原因から具体的な確認/修正手順をSKIL |
| cmd_2517 | CI全体287s→240s削減の第一段階。cmd_save系slowテスト8ファイル(32.2s)の fixture共有+統合で50%以上短縮する。偵察cmd_2494で特定済みの統合候補: test_cmd_save_ac_test_scope(2.7s), test_cmd_save_block_aggregation(2.1s), test_cmd_save_check19_fp(4.1s), test_cmd_save_command_steps_vs_ac(2.0s), test_cmd_save_diagnose(4.7s), test_cmd_save_diagnosis_quality(6.9s), test_cmd_save_environment_change(4.3s), test_cmd_save_warn_logging(5.5s)。 既存cmd_2480/2481でfixture閉鎖+helper共有の前例あり(70-83%短縮実績)。 | infra | 05-03 | cmd_save系slowテスト8本を32.236sから11 |
| cmd_2519 | CI時間削減の第三段階。偵察cmd_2494で特定済みの残りslow 7ファイル(20.7s)の fixture共有+統合で50%以上短縮する。対象: test_cmd_complete_gate_locking(2tests/2.4s), test_cmd_complete_gate_subsystems(17tests/3.5s), test_gate_report_format_learning(3tests/2.7s), test_gate_skill_script_refs(3tests/2.5s), test_lesson_harvest(3tests/3.0s), test_session_state(8tests/2.5s), test_skill_feedback_loop(11tests/4.2s)。 cmd_2517/2518と並列実施。 | infra | 05-03 | 対象7本のBats合計時間を16.287sから7.567sへ |
| cmd_2518 | CI時間削減の第二段階。deploy_task系slowテスト4ファイル(32.8s)の fixture共有+統合で50%以上短縮する。偵察cmd_2494で特定済みの統合候補: test_deploy_task_ac_handling(26tests/15.4s), test_deploy_task_codd_failure_history(9tests/2.5s), test_deploy_task_lifecycle(41tests/12.0s), test_deploy_task_template_generation(24tests/3.0s)。 cmd_2517(cmd_save系)と並列実施。 | infra | 05-03 | deploy_task系4本の軽量化を試行したが、AC1の5 |
| cmd_2521 | dashboard_update.shはcmd完了ごとに実行(呼出頻度18)で未最適化。 CoDDリファクタリングパイプラインで計測→設計→実装→検証を実施し高速化する。 プロファイリング結果に基づきbash -n 16msから実行時パスのボトルネックを特定する。 | infra | 05-03 | dashboard_update.sh --dry-runを |
| cmd_2522 | context_freshness_check.shはgate内部で頻繁呼出し(呼出頻度44)で未最適化。 gate_context_freshness.shは台帳済み(156ms→62ms)だが、その内部で呼ぶ context_freshness_check.sh自体は未最適化。CoDDで計測→高速化。 | infra | 05-03 | context_freshness_check.shを短TT |
| cmd_2523 | ninja_monitor.shは常駐デーモンで呼出頻度最大(118)、未最適化。 全忍者の状態監視・idle検知・/clear判定・snapshot生成を担う。 CoDDで計測→ボトルネック特定→高速化。 | infra | 05-03 | ninja_monitor.shのループ相当処理を23.84 |
| cmd_2527 | report_field_set.sh L400のyaml.dumpが文字列'yes'/'no'を裸のYAML boolean(true/false) として出力する。autofix_main.py L250-252が毎回bool→str変換で消火中。 根本修正: yaml.dump出力で引用符付き文字列化+消火コード除去。 report-write/verdict-check FAIL率100%の根因(軍師現物確認済み)。 | infra | 05-03 | report_field_setのyes文字列保持とauto |
| cmd_2530 | cmd_complete_gate.sh L1975-1990のfallback globがstale reportを無差別に拾い偽BLOCK。加えてreview_gate.done作成後のgate_metrics CLEAR書込みが保証されていない。再配備時の偽BLOCK根絶+統計精度向上 | infra | 05-03 | cmd_complete_gate lesson track |
| cmd_2529 | archive_completed.shが3パターン(archive.done不在/placeholder/review_gate.done不在)で報告YAMLをSKIPし永久残存させている。169件蓄積=交差汚染(バグ2)の増幅源。負の複利を解消する | infra | 05-03 | archive_completed.shの報告sweepを修 |
| cmd_2533 | サブシェル内のreturn 1は親に伝播しない→flock timeout後もecho synced が無条件実行→chronicle更新失敗が成功として記録される。3箇所(L137,L219,L1437)を修正 | infra | 05-03 | archive_completed.shのchronicle |
| cmd_2532 | auto_unwrap_report_yamlでflock timeout→exit 1→サブシェル内のためunwrap_resultが空文字→case文のどのパターンにもマッチせず完全沈黙。デフォルトパターン追加で空文字をキャッチする | infra | 05-03 | auto_unwrap_report_yamlの空文字/未知 |
| cmd_2537 | L2848のglob展開でMATCHING_TASK_FILESを構築→後続ループ中にdeploy_task.shがタスクYAML追加/archive_completed.shが移動→処理漏れ/不整合。glob結果をスナップショットとして固定し、ループ中の変更に耐性を持たせる | infra | 05-03 | MATCHING_TASK_FILES参照ループへ消失ファイ |
| cmd_2538 | deploy_task.sh L5008-5009でparent_cmd+statusは設定するがtask_idが漏れている。旧cmdのtask_idが残存→cmd_complete_gate.shが旧cmdのreportを参照→交差汚染。1行追加で解消 | infra | 05-03 | direct_mode配備でtask_idが新cmdへ更新さ |
| cmd_2543 | report_field_set.shのverdict書込みとstatus=completed更新を1回のflock内でatomicに実行するようbatch化 | infra | 05-04 | report_field_set.shのverdict確定時 |
| cmd_2545 | archive_overflow_reports_to_capでGATE CLEAR待ち(status=pending)reportがcap超え時に強制archiveされないよう除外チェックを追加 | infra | 05-04 | archive_overflow_reports_to_ca |
| cmd_2547 | L221のinbox_write成功後にwatcher存在チェックがない→watcher未起動時にnudgeが喪失しても沈黙。pgrep確認+WARN出力を追加する | infra | 05-04 | bulletin_write.sh L221(inbox_w |
| cmd_2544 | auto_draft_lesson.sh L215のSOURCE_CMD二重渡し引数修正 + cmd_absorb.sh L243のgrep空変数ガード追加 | infra | 05-04 | auto_draft_lessonの6番目引数空文字仕様とc |
| cmd_2548 | deploy_task.shの2バグ修正。(1)purposeに二重パイプ演算子を含むcmd配備時にyaml_field_set_batch内で値がシェル展開され切り詰まる。(2)count_task_acceptance_criteria失敗時にac_count=0となりdraft_reviewが常にSKIPされ軍師レビューが届かない | infra | 05-04 | cmd_2548のdeploy_task回帰検証を追加。pu |
