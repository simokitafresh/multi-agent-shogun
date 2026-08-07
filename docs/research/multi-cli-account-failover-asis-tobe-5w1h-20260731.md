<!-- gist-master: 59217417ce219afcd4fde024b8d932bb multi-cli-account-failover-asis-tobe-5w1h-20260731.md -->
# Multi-CLI・複数アカウント切替の簡素化 — As-Is / To-Be 5W1H

- 作成日: 2026-07-31
- 版: v2.0（将軍・家老レビュー反映）
- 対象: Claude CLI 2アカウント + Codex CLI 1アカウントを使う multi-agent-shogun
- 調査範囲: 既存OSS、現行ローカル運用、段階導入案
- 結論: **`claude-swap + CodexBar CLI cards`はisolated paneで試す価値がある候補。ただし現版はPoC設計であり、account identityを起動SSOTへ組み込む契約・独立identity probe・切替transaction・供給網監査・故障注入がPASSするまで本運用へ入れない。**

## 0. Executive Summary

同じ痛みは既に広く存在し、複数のOSSが解いている。

| 痛み | 既存解 |
|---|---|
| Claude複数accountを再loginなしで切替 | [claude-swap](https://github.com/realiti4/claude-swap) |
| Claude全accountの5h/7d使用率・reset時刻 | [claude-swap](https://github.com/realiti4/claude-swap) |
| Claude / Codex / Gemini等の設定切替 | [CC Switch](https://github.com/farion1231/cc-switch) |
| 複数OAuthアカウントのプール・round-robin | [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) |
| アカウント別quota表示・smart scheduling | [Quotio Desktop](https://github.com/xiaocoss/quotio-desktop) |
| 複数CLIを一つのローカルgatewayへ接続 | [Claude Code Router](https://github.com/musistudio/claude-code-router) |
| Claude公式CLIでの複数アカウント分離 | `CLAUDE_CONFIG_DIR`（Anthropic公式repo issueで案内） |

推奨する形は次の通り。

1. **Claude account切替をisolated paneで借りる**: `claude-swap`でA/Bを保持し、初期PoCはpane別`cswap run`だけを使う。global `cswap switch`はactive request全体へ波及するため対象外とする。
2. **両CLIの使用状況をcardsで借りる**: `CodexBar CLI`の`cards`表示はClaude/Codexのsession・weekly残量とresetを一画面化し、claude-swap複数accountも表示できる。**この複数account優先順位はcards限定であり、`usage`/`serve`へ一般化しない。**
3. **Codexは監視から始める**: 現在1アカウントなので切替機構は増やさない。2アカウント目が来た時だけ`codex-multi-auth`を検討する。
4. **既存資産を残す**: `config/cli_profiles.yaml`と`scripts/switch_cli_mode.sh`はClaude↔Codex切替と実態確認に使う。
5. **最初はisolated paneの手動切替だけ**: 自動rotation、global switch、proxyは、identity・fencing・rollback・fault injectionの契約が成立してから別Phaseで判断する。

われらのtask YAML・snapshot・recoveryは作業状態を保持するが、**どのaccountで次のCLI processが起動するかは保証していない**。`agent_respawn.sh`、`ninja_monitor.sh`、`switch_cli_mode.sh`はいずれも`cli_launch_cmd`/`launch_cmd`から起動commandを再構築するため、`cswap run`をその場で実行するだけでは次回respawn時にaccount affinityが失われる。したがって主眼はquota可視化だけでなく、account identityを起動SSOTへ接続して復帰後も維持することに置く。

### 0.1 三軸の結論

| 軸 | 今のpain | まず使うOSS | 便利になる点 | 初期採否 |
|---|---|---|---|---|
| **Claude** | 2 accountのlogin切替と残量確認が面倒 | [claude-swap](https://github.com/realiti4/claude-swap) | pane固定wrapper、2 accountの5h/7d/reset一覧 | 安全性PoC候補 |
| **Codex** | 1 accountの残量/resetを容易に見たい | [CodexBar CLI](https://github.com/steipete/CodexBar) | session/weekly残量、reset、paceを即表示 | cards PoC候補 |
| **両者** | Claude/Codexを別々に確認する | [CodexBar CLI](https://github.com/steipete/CodexBar) | `codexbar cards --brief`で3 accountを一画面化 | cards PoC候補 |

将来Codexも複数accountになった場合だけ、[codex-multi-auth](https://github.com/ndycode/codex-multi-auth)をCodex軸へ追加する。今は不要な複雑性を入れない。

### 0.2 成功の定義

初期PoCの成功は便利さではなく、次の安全契約を二値で証明できた状態とする。

- 表示: `codexbar cards --brief`でClaude A/BとCodex Cのcapacityを**1画面**に表示できる。
- 固定: paneごとのdesired accountが全起動経路で`cswap run`へ合成され、auto-respawn後も失われない。
- 実測: controllerの`cswap status`ではなく、実CLIの独立観測面でpane/account一致を証明できる。
- 安全: global credential切替を使わず、fencing・rollback・fault injectionが全件PASSする。
- 保全: OSSのversion/SHA、source、権限、egress、update停止、backup/restoreを監査できる。

proxyによる無停止round-robin、全pane自動再配置、最適化schedulerは初期スコープ外とする。

## 1. As-Is 5W1H

| 5W1H | 現状 |
|---|---|
| Who | 殿または家老が、9ペインのClaude/Codex割当と3アカウントの残量を別々に見ながら切替判断する |
| What | アカウント認証、CLI種別、モデル、tmux環境変数、実プロセスを別々に切り替える |
| When | rate limit到達時、モデル変更時、Claude/Codex障害時、編成変更時 |
| Where | OAuth資格情報、`config/settings.yaml`、`config/cli_profiles.yaml`、tmux pane環境、起動中CLI |
| Why | 2つのClaude枠と1つのCodex枠を止めずに使い切るため |
| How | ログイン切替または資格情報分離 → 設定変更 → pane respawn → CLI/model実態確認 → 失敗pane復旧 |

### 1.1 現行フロー

```text
rate limit/障害を人が認知
  ↓
どのアカウント・CLIへ逃がすか判断
  ↓
認証または設定を切替
  ↓
settings / tmux変数を同期
  ↓
idle paneをrespawn、active paneは退避判断
  ↓
CLIバナー・モデル・task状態を実測
  ↓
失敗時は再配備または再切替
```

### 1.2 既に解けている部分

- `config/cli_profiles.yaml`: CLI起動条件のSSOT。
- `scripts/switch_cli_mode.sh`: Claude/Codex切替、tmux同期、idle pane respawn、事後検証。
- `skills/shogun-cli-switch/`: 操作手順の標準化。
- Claude複数アカウントは`CLAUDE_CONFIG_DIR=~/.claude-{name}`で資格情報を分離できる。
- 過去の双方向切替検証は6/6成功。端末状態のリセットが必要なことも判明済み。

### 1.3 残る問題

| 問題 | 影響 |
|---|---|
| quota確認・アカウント選択・CLI切替が別操作 | 判断箇所が多く、手順漏れが起きる |
| 設定上の値と起動中プロセスが乖離しうる | 「切り替えたつもり」が発生する |
| global logout/loginは全Claude CLIへ波及 | 30–60秒程度の一斉停止と再認証が起きる |
| 使用率とreset残時間がaccount横断で並ばない | 「どれへ切り替えるか」を即断できない |
| rate limit後の対応が事後的 | 枯渇してから人が割当を組み直す |
| accountとCLI/modelが一つの概念に混在 | 「Claude AのSonnet」「Claude BのOpus」「Codex」の状態が追いにくい |

根本原因は、**account profile・現在使用率・reset残時間・切替操作が一つのview/commandに束ねられていないこと**である。会話・task状態は既存の外部化機構で復元できる。

## 2. OSS比較

調査日は2026-07-31。GitHubの主リポジトリ・公式マニュアルを一次資料とした。

### 2.1 比較表

| 候補 | 解く範囲 | Claude/Codex横断 | 複数OAuth | quota | 自動failover | Shogun適合 | 判定 |
|---|---|---:|---:|---:|---:|---:|---|
| **claude-swap** | Claude account切替、5h/7d dashboard、自動rotation | Claudeのみ | yes | yes | yes | 非常に高 | **第一候補** |
| **CodexBar CLI** | Claude/Codex quota、reset、paceの統合表示 | yes | claude-swap/Codex accountを列挙 | yes | guardのみ | 非常に高 | **統合表示の第一候補** |
| **codex-multi-auth** | Codex account管理、quota forecast、switch | Codexのみ | yes | yes | yes | 高 | Codex 2 account目で採用 |
| **CC Switch** | provider/profile GUI、local proxy、quota、circuit breaker | yes | Codex OAuthはyes。Claude公式2アカウントは要PoC | yes | yes | 高 | provider管理候補 |
| **CLIProxyAPI** | OAuthを互換API化、複数account pool | yes | yes | 別ツール併用 | round-robin | 中 | 基盤候補・高リスク |
| **Quotio Desktop** | CLIProxyAPIのGUI、quota、smart scheduling | yes | yes | yes | yes | 中 | 第二PoC候補 |
| **Claude Code Router** | 複数CLI/Providerのgateway、credential pool、fallback | yes | 主にprovider/API資格情報 | yes | yes | 中 | API移行時候補 |
| Claude公式`CLAUDE_CONFIG_DIR` | Claude profile分離 | Claudeのみ | yes | no | no | 高 | 今すぐ使う土台 |

### 2.2 claude-swap — 今回のClaude側要件にほぼ完全一致

[claude-swap](https://github.com/realiti4/claude-swap)はMITライセンスのClaude Code専用multi-account switcher。Linux/WSL対応であり、今回の「Claude 2アカウントを滑らかに切り替え、残量とresetを容易に見る」に最も小さく適合する。

確認できた機能:

- 複数Claude OAuth accountを保持し、logoutなしでaccount指定切替。
- `cswap list`で全accountの5時間・7日使用率とreset時刻を一覧。
- `cswap switch --strategy best`で残量最大accountを選択。
- `cswap switch --strategy next-available`でrate-limited accountをskip。
- `cswap auto`は既定60秒poll、既定90%到達前に残量の多いaccountへ自動切替。
- cooldown・hysteresisで閾値付近の往復を防止。
- `cswap run <account>`でterminal/pane単位にaccountを固定し、複数accountを並行利用。
- `cswap list/status --json`でShogun dashboardへ機械連携可能。
- usage値には取得時刻・ageがあり、一時的なusage API障害時はlast-known値を表示。
- Linux/Windowsでは通常restart不要で、次messageから新accountを読む。即時反映が必要な場合だけCLIをrestart。
- account固有loginだけを交換し、MCP等のaccount非依存OAuth状態は維持。
- credential write時にClaude Code側のlockを取り、token refreshとの競合を防止。

GitHub snapshot（2026-07-31取得）:

- Stars: 1,444
- Forks: 153
- License: MIT
- 最終push: 2026-07-30

Shogunへの適用:

```text
paneごとにaccount固定:
  cswap run <alias> -- <claude起動引数>

表示:
  cswap list --json
    ├─ account alias
    ├─ active/disabled
    ├─ 5h pct + resetsAt
    ├─ 7d pct + resetsAt
    └─ usageAgeSeconds
```

初期PoCでは`cswap switch`による共通account一斉切替を使わない。稼働中paneのaccount affinityとtoken refreshへ波及するためである。匿名aliasをPhase 0から起動SSOTへ接続し、全respawn経路が同じpane固定wrapperを再構成できることを先に証明する。

### 2.3 CodexBar CLI — 両CLIの残量を一画面にする

[CodexBar](https://github.com/steipete/CodexBar)はMITライセンスのusage monitor。menu bar appが主だが、Linux/WSL向けstandalone CLI releaseがあり、今回必要なのはCLI部分だけである。

確認できた機能:

- ClaudeとCodexのsession/primary、weekly/secondary使用率とreset時刻を同時取得。
- `codexbar cards --brief`で`Provider / Usage / Reset`のcompact tableを表示。
- Claude側はclaude-swap integrationを持ち、2 account以上なら各accountを別cardで表示。
- Codex側はvisible accountを列挙し、account別にquotaを取得。
- remaining quota、reset、使用pace、枯渇予測を表示。
- `codexbar --format json --provider both`で機械取得。
- 一時取得失敗時はlast-good responseを保持し、画面のちらつきを防止。
- `codexbar guard`でsession/weekly残量閾値を二値判定できる。

制約: claude-swap複数accountのcardinality拡張は`cards`表示に限定される。`usage`や`serve`をClaude A/Bの統合dashboardとみなしてはならない。初期採用契約は`codexbar cards --brief`だけとし、`serve`は別PoCで同じcardinalityを独立検証できるまで不採用とする。

GitHub snapshot（2026-07-31取得）:

- Stars: 19,365
- Forks: 1,614
- License: MIT
- 最終push: 2026-07-30

初期利用はこれだけでよい。

```text
codexbar cards --brief
```

期待表示:

```text
ACCOUNT/PROVIDER   SESSION LEFT   WEEKLY LEFT   RESET
Claude A           58%            71%           2h 18m / 4d
Claude B           89%            92%           4h 52m / 6d
Codex C            33%            61%           1h 07m / 3d
```

これは「両者を容易にnear-real-time確認」に最短で届く。ただし表示と切替は責務を分離し、CodexBarからcredential mutationを実行しない。

### 2.4 codex-multi-auth — Codexが複数accountになった時の対称解

[codex-multi-auth](https://github.com/ndycode/codex-multi-auth)はMITライセンスのCodex CLI multi-account manager。

確認できた機能:

- account login/list/switch、health check、diagnostics。
- `forecast --live`で次に使うaccountを選定。
- `monitor --json`でusage、quota、policy、runtimeを機械出力。
- `codex-multi-auth-codex --account`で1 sessionだけaccount固定。
- credentialはlocal保存、official `codex` binaryの所有権を奪わない。

GitHub snapshot（2026-07-31取得）:

- Stars: 412
- Forks: 38
- License: MIT
- 最終push: 2026-07-29

ただし現在Codexは1 accountなので、導入しても切替painは減らない。**今はCodexBarでquotaを見るだけ**とし、Codex 2 account目が追加された時の既製解として記録する。

### 2.5 CC Switch — multi-CLI provider管理の完成品

[CC Switch](https://github.com/farion1231/cc-switch)はMITライセンスのcross-platform desktop appで、Claude Code、Codex、Gemini CLI等を一元管理する。

確認できた機能:

- provider設定をSQLiteのSSOTで管理し、live configへatomic write。
- Claude/Codex/Geminiごとのtray切替。
- local proxy takeoverとhot switching。
- failover queue、retry、circuit breaker、health status、failover log。
- Claude/Codex公式subscriptionのquota表示。
- Codex OAuth Auth Centerで複数ChatGPTアカウントを保持し、providerへ紐付け。
- Linux対応。Codexのprovider切替はterminal restartが必要と公式manualに明記。

GitHub snapshot（2026-07-31取得）:

- Stars: 122,580
- Forks: 8,282
- License: MIT
- 最終push: 2026-07-31

適合点:

- われらが欲しい「今どのproviderか」「残量はどうか」「次へ逃がす」を一画面にまとめられる。
- circuit breakerとfailover logを自作せず借りられる。
- configのatomic write/rollback思想が現行Shogunの安全要件と合う。

不足点:

- CC Switchのswitch完了は主にconfig/provider状態であり、Shogunのtask YAML、active/idle判定、tmux pane復旧までは扱わない。
- 公式Claude subscriptionを2アカウント同時保持・自動切替できることは一次資料で確認できなかった。ここはPoC項目。
- Codex OAuth reverse proxyは同プロジェクト自身が「reverse-engineered OAuth flow」「規約違反・アカウント制限・将来停止の可能性」を明記している。

### 2.6 CLIProxyAPI — 複数OAuth poolの中核

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)はMITライセンスのlocal proxyで、Claude Code OAuthとOpenAI Codex OAuthを互換APIとして公開する。

確認できた機能:

- Claude Code / OpenAI CodexのOAuth login。
- Claude、OpenAI、Gemini等の複数アカウントround-robin。
- Claude Code multi-account load balancing。
- OpenAI Codex multi-account load balancing。
- OpenAI Responses / Anthropic Messages等の互換endpoint。

GitHub snapshot（2026-07-31取得）:

- Stars: 45,675
- Forks: 7,091
- License: MIT
- 最終push: 2026-07-31

重要な注意:

- Codex Responses APIを複数アカウントへrequest単位round-robinすると、`previous_response_id`を作ったアカウントと次requestのアカウントが異なり、会話継続が壊れるというissueがある。
- われらはCodex 1アカウントであり、task状態も外部化済みなので、これは今回の主要論点ではない。将来Codex accountを増やしてproxy pool化する時の注意に留める。
- OAuth tokenをproxyへ集約するため、侵害時のblast radiusが現在より大きくなる。

### 2.7 Quotio Desktop — Claude/Codex統合dashboardが直球

[Quotio Desktop](https://github.com/xiaocoss/quotio-desktop)はCLIProxyAPIを内包するMITライセンスのcross-platform GUI。

確認できた機能:

- Claude Code / Codex等の複数OAuthアカウントpool。
- アカウント別5時間・週次quota表示。
- Codexで「最も早く回復するアカウントだけをpoolへ入れ、時刻到来で自動交代」するsmart scheduling。
- Claude Code / Codex / Gemini CLIをlocal proxyへ一括接続。
- multi-instance Codexのaccount固定。

GitHub snapshot（2026-07-31取得）:

- Stars: 48
- Forks: 7
- License: MIT
- 最終push: 2026-07-22

Claude/Codexを一画面で見る要件には最も直球だが、CLIProxyAPI proxyの導入を伴い、採用実績も小さい。**claude-swapで不足する「統合GUI」が本当に必要と確認できた場合の第二PoC**とする。

### 2.8 Claude Code Router — provider gatewayとして有力

[Claude Code Router](https://github.com/musistudio/claude-code-router)はMITライセンスで、Claude CodeとCodexを同じlocal endpointへ接続し、provider、credential pool、retry、fallback、観測をまとめる。

GitHub snapshot（2026-07-31取得）:

- Stars: 36,294
- Forks: 3,038
- License: MIT
- 最終push: 2026-07-31

API key/providerを横断する将来像には合う。一方、今回の主問題は「3つの公式subscription OAuth枠をどう安全に使うか」であり、第一候補ではない。

### 2.9 ccusage — 消費実績分析には強いが残量確認の主役ではない

[ccusage](https://github.com/ccusage/ccusage)はClaude/Codexを含む多数CLIのlocal session logを統合し、daily/weekly/monthly/token/costを表示する。

これは「何をどれだけ使ったか」の事後分析には有用だが、今回重視するsubscriptionの**残り何%・いつresetか**はCodexBar/claude-swapの方が直接的である。補助候補に留める。

### 2.10 公式CLI側の未解決pain

Anthropicの公式Claude Code repoには「複数account/profileを切り替えたい」というissueが複数あり、同じpainが継続している。公式issueでは当面の回避策として`CLAUDE_CONFIG_DIR`によるprofile directory分離が案内されている。

これは次を意味する。

- 痛みはわれら固有ではない。
- 公式native profile switchを待つ選択肢はあるが、現時点では一操作化されていない。
- 資格情報分離そのものはOSS proxyを入れず、公式CLIの環境変数で安全に実現できる。

## 3. To-Be 5W1H

| 5W1H | 目標 |
|---|---|
| Who | 殿または家老がcardsを見て、idle paneのfenced transactionを1操作で開始。自動選択は故障契約PASS後のみ |
| What | Claude A/BとCodex Cの使用率、残量、reset残時間、現在割当を一覧化 |
| When | 任意の手動切替時、Claude 5h/7d閾値到達前、rate limit時 |
| Where | `claude-swap` + Codex quota表示 + `cli_profiles.yaml` |
| Why | login/logoutと複数画面確認をなくし、使える枠を即座に選べるようにする |
| How | quota自動更新 → 一覧表示 → alias指定またはbest戦略で切替 → 次messageから反映 |

### 3.1 目標アーキテクチャ

```text
Desired state                         Launch path
settings.yaml account_profile ─┐
cli_profiles.yaml profile args ─┼─> cli_launch_cmd resolver
pane assignment generation ─────┘        │
                                         └─> cswap run <alias> -- <claude args>
                                              │
                                              ├─ manual launch
                                              ├─ agent_respawn.sh
                                              ├─ ninja_monitor auto-respawn
                                              └─ switch_cli_mode.sh

Observed identity (独立観測)            Capacity view (意思決定補助)
live Claude CLI/profile identity ──┐    claude-swap usage ─┐
pane PID/env/config-dir evidence ──┴─照合  Codex native quota ─┴─> CodexBar cards
```

`desired account`、`observed account identity`、`capacity`は別の状態である。`cswap status`はcontrollerのdesired/current slot確認には使えるが、実CLIがそのaccountで動いている証拠にはしない。

現行`agent_respawn.sh`と`ninja_monitor.sh`は`cli_launch_cmd`を再構成し、`switch_cli_mode.sh`はCLI種別変更時にper-agent `launch_cmd` overrideを消す。このため手入力した`cswap run`はrespawn後に消える。`account_profile`はPhase 1の後付け属性ではなく、Phase 0から`cli_launch_cmd`の必須入力にする。

責務境界:

| 層 | 責務 | 採用 |
|---|---|---|
| Credential | Claude OAuthの複数slot保持・更新 | claude-swap |
| Capacity | Claude 5h/7d pct、reset、data age | claude-swap |
| Codex Capacity | Codex使用率、reset、data age | CodexBar CLI |
| Unified View | Claude A/B + Codex Cの残量一覧 | CodexBar `cards`限定 |
| Policy | 初期は人がalias選択。自動選択はfault injection後 | Shogun側transaction |
| Execution | pane別account固定のみ | `cli_launch_cmd` → `cswap run` |
| Verification | 実CLI/profile identityの独立一次実測 | 新identity probe + 既存switch gate |
| Audit | 誰がいつ何から何へ切替したか | OSS log + Shogun event log |

初期PoCから除外するもの:

- `cswap switch`によるglobal credential mutation。
- `cswap auto`による自動rotation。
- `CodexBar serve`を複数Claude account統合viewとすること。
- reverse proxy、round-robin、active request途中のaccount移動。

### 3.2 目標dashboard

```text
ACCOUNT        CLI      NOW     REMAIN   RESET IN   DATA AGE   ASSIGNED
claude-a       Claude   42%     58%      2h 18m     34s        karo,ninja-1
claude-b       Claude   11%     89%      4h 52m     51s        ninja-2,3
codex-c        Codex    67%     33%      1h 07m     22s        ninja-4,5
```

初期`cards` viewの最低要件:

- 5h/sessionと7d/weeklyを混同せず別表示。
- 使用率だけでなく**残量・resetまでの残時間・データの古さ**を同時表示。
- emailやtokenは表示せずaliasだけ。
- accountごとのpane割当が見える。
- 表示はread-onlyであり、credential mutationと同一操作面へ結合しない。
- `cards`以外のsubcommandへ同じaccount数を一般化しない。

「リアルタイム」は上流usage APIの更新頻度に依存するため、秒単位の厳密値とはしない。**自動更新され、最終取得からのageが常に見えるnear-real-time**を正しい要件とする。

### 3.3 切替transactionと不変量

```text
PRECHECK
  対象paneがidle / alias存在 / usage age許容 / old identity取得 / restore可能
  ↓
RESERVE + FENCE
  pane assignment generationをCAS更新し、同一paneの並行切替を拒否
  ↓
LAUNCH CANDIDATE
  global stateを変えず、cswap run <new-alias> wrapperで対象paneだけ起動
  ↓
INDEPENDENT VERIFY
  controller statusではなくlive CLI/profile identityとdesired generationを照合
  ↓ PASS                         ↓ FAIL/timeout/crash
COMMIT assignment               ROLLBACK old wrapper/config
  ↓                              ↓
release old generation          old identityを独立再検証してfence解放
```

不変量:

- 1 paneにcommitted assignmentは常に1つ。各変更に単調増加`generation`を持たせる。
- active request/sessionの途中では切り替えない。Phase 0はidle paneだけを対象にする。
- current CLI identityとdesired accountが一致するまで切替完了にしない。
- auto-respawn、watcher restart、CLI種別往復後も同じ`account_profile`を再合成する。
- usageがstale、全account exhausted、identity probe不能のいずれかなら自動選択しない。
- 任意のmutation点で停止しても、再実行は同じgenerationへ収束するかold assignmentへrollbackする。

禁止:

- config更新だけを切替完了としない。
- 全paneを同時に実験対象へしない。
- global `cswap switch`をPoCへ混ぜない。
- `cswap status`を実CLI identityの証明に使わない。
- OAuth reverse proxyを規約・security reviewなしで本番導入しない。

## 4. Build vs Buy判断

| 選択 | 長所 | 短所 | 判断 |
|---|---|---|---|
| 現行を全面自作拡張 | task/tmuxへ完全適合 | quota UI、OAuth管理、circuit breakerを再発明 | 不採用 |
| **claude-swap + 起動SSOT連携** | proxy不要、JSON有、pane固定候補 | identity/fencing/respawn契約はわれらが実装・検証必要 | **安全性PoC候補** |
| CC Switchへ全面置換 | UIとfailoverが完成 | task YAML・active pane・復旧を知らない | 不採用 |
| CLIProxyAPIへ全面集約 | account poolが直球 | OAuth/規約、会話affinity、単一障害点 | 現時点不採用 |
| Quotio Desktop統合GUI | Claude/Codexを一画面化 | proxy導入、成熟度が低い | 第二PoC |
| 公式native機能を待つ | 最も低リスク | 時期不明、現在のpainが残る | fallback |

## 5. 推奨ロードマップ

### Phase 0 — isolated pane安全性PoC（時間断定なし）

- claude-swapとCodexBarの採用versionおよびcommit SHAを固定し、source・release artifact・更新経路を監査する。
- test専用`CLAUDE_CONFIG_DIR`とClaude A/Bの匿名slotを用意し、保存ファイル権限、外向き通信先、log redactionを確認する。
- 変更前backupを作り、アンインストール・設定restore・旧profile起動を実演する。
- `account_profile`をPhase 0からlaunch SSOTへ追加し、`cli_launch_cmd`が`cswap run <alias> -- <claude args>`を決定論的に生成する。
- isolated idle pane 1つだけでmanual launch、`agent_respawn.sh`、`ninja_monitor` auto-respawn、`switch_cli_mode.sh`往復後のaccount affinityを検証する。
- `cswap list --json`で5h/7d pct、reset、data ageを取得する。
- `codexbar cards --brief`でClaude A/B + Codex Cを表示する。`usage`/`serve`へ一般化しない。
- live CLI/profile API、pane PID環境、実config directory等の独立identity probeを定義し、`cswap status`とは別に照合する。
- global `cswap switch`、`cswap auto`、active paneは一切使わない。

Exit criteria:

- Claude 2/2アカウントを匿名aliasで識別できる。
- session/weekly使用率・reset時刻を3/3で一画面表示できる。
- manual/agent_respawn/ninja_monitor/switch往復の4/4経路でdesired=observed identity。
- auto-respawn 20/20で誤account 0件、wrapper喪失0件。
- token/email/組織名のlog露出0件、credential fileの過剰権限0件、未許可egress 0件。
- pinned version/SHA一致、source audit済み、auto-update停止、backup→破損模擬→restore 3/3成功。

### Phase 1 — fenced pane切替transaction

- PRECHECK→RESERVE/FENCE→LAUNCH→独立identity VERIFY→COMMIT/ROLLBACKを実装する。
- pane別並行運用だけを`cswap run <alias>`で試す。
- assignment `generation`とCASで同一paneの並行切替を直列化する。
- logout/loginを通常切替から除く。
- transaction各mutation点へのcrash injectionを行う。

Exit criteria:

- alias指定から独立current identity実測まで1操作。
- global logout/login回数が通常切替で0。
- isolated idle paneでA→B→A切替が20/20。
- pane別A/B並行実行で誤account 0/40。
- transaction全mutation点のcrash注入N/Nで二重commit 0、fence残留0、旧identity rollback成功N/N。
- active requestを切り替えた件数0。

### Phase 2 — cards限定capacity表示

- `codexbar cards --brief`を常時見られる入口へ置く。
- 表示データとShogunのpane assignmentをread-onlyで並置する。
- `usage`/`serve`は複数Claude accountを同じcardinalityで表示できる独立証拠が得られた場合だけ別PoCにする。
- ここで十分便利なら終了する。

Exit criteria:

- 3/3アカウントを一画面表示。
- current/remaining/reset-in/data-ageを全accountで表示。
- 手動refreshと自動refreshの双方が成功。
- stale値を最新値に見せる件数0。
- `cards`以外の表示を統合dashboardと誤認した件数0。

### Phase 3 — fault injection完了後のみ自動選択

- auto-respawn、watcher restart、token refresh競合、usage stale、全account exhausted、transaction途中crashを全て注入する。
- 全failure contractがPASSした後だけ、Claudeの手動選択がまだ面倒ならisolated pane単位の自動候補選択を設計する。
- global `cswap auto`はaccount affinityを保てる独立証拠がない限り採用しない。
- Codex 2 account目が追加されたらcodex-multi-authを試す。
- GUIが必要ならQuotio DesktopまたはCC Switchを試す。
- proxy routingはこの段階まで入れない。

### Phase 4 — 採否

| PoC結果 | 採るもの |
|---|---|
| P1〜P18が全PASS | controlled isolated-pane切替とcards viewを採用 |
| 統合viewだけで十分 | auto switch/proxyを増やさず終了 |
| GUI価値が運用増を上回る | Quotio Desktopのquota/viewだけ採用検討 |
| proxyが不安定または規約要件を満たさない | reverse proxy不採用 |
| 将来API key中心へ移行 | Claude Code RouterまたはLiteLLM系gatewayを再評価 |

## 6. PoCで答えるべき二値質問

| ID | 質問 | PASS |
|---|---|---|
| P1 | Claude A/Bを同時に保持できるか | 再loginなしでA→B→Aが10/10 |
| P2 | launch SSOTがaccount affinityを保持するか | 4/4起動経路、auto-respawn 20/20でdesired=observed |
| P3 | pane別にA/Bを並行利用できるか | 誤account実行0/40 |
| P4 | 5h/7d使用率を容易に見られるか | 2/2 accountを1画面表示 |
| P5 | reset残時間を容易に見られるか | 2/2 accountでreset-in表示 |
| P6 | データ鮮度が分かるか | 全値にageまたは取得時刻あり |
| P7 | Codexをcards viewへ載せられるか | `cards`で3/3 accountのcapacity表示 |
| P8 | 独立identityを証明できるか | `cswap status`以外の観測でpane一致40/40 |
| P9 | rollbackできるか | 全mutation点N/Nで旧identity復元 |
| P10 | auto-respawnでwrapperを失わないか | 20/20でalias保持、誤account 0件 |
| P11 | watcher restartへ耐えるか | restart注入10/10でassignment generation不変 |
| P12 | token refresh競合へ耐えるか | 同時refresh注入10/10でcredential破損0、誤identity 0 |
| P13 | stale usageを安全に扱うか | stale注入10/10で自動切替0、明示BLOCK 10/10 |
| P14 | 全account exhausted時に安全停止するか | 10/10で切替0、現assignment維持10/10 |
| P15 | transaction途中crashへ耐えるか | 全mutation点N/Nで二重commit 0、fence残留0 |
| P16 | CodexBarのcardinality境界を守るか | `cards`のみ採用、`usage`/`serve`一般化0件 |
| P17 | supply chainとsecretを保全できるか | version/SHA一致、監査項目全PASS、token/email露出0 |
| P18 | 完全restoreできるか | backup→破損模擬→旧profile復元3/3 |

P1〜P18の全件PASS前に「採用」と判定しない。正常系だけの10/10や表示成功だけではfailover設計の証明にならない。

## 7. リスクと対策

| リスク | 対策 |
|---|---|
| OAuth refresh tokenを第三者OSSへ集約 | test専用profileから開始。version+commit SHA pin、source/release差分、保存権限、egress、更新停止、logを監査 |
| 非公式OAuth経路によるアカウント制限 | reverse proxyは初期PoC対象外。採用前に規約確認 |
| usage API値が遅延する | data ageを必ず併記し、stale値を意思決定に使わない |
| local proxy停止で全CLI停止 | 公式endpointへ戻すbreak-glass profileを常備 |
| OSS updateで挙動変化 | version/SHA pin、auto-update停止、設定backup、upgrade前後contract test |
| GUIとShogun SSOTが競合 | ownershipを分離。OSS=capacity、Shogun=execution |
| config上は成功、実CLIは旧状態 | controllerと独立したlive CLI/profile identity probeを完了条件にする |
| 手入力wrapperがrespawnで消える | `account_profile`をPhase 0から`cli_launch_cmd`入力とし4/4起動経路を試験 |
| global switchが他paneへ波及 | PoCからglobal mutationを除外しisolated pane wrapperのみ使う |
| 同時切替・refresh race | generation CAS、pane fence、credential lock、race injectionを必須化 |
| transaction途中crash | 全mutation点でcrash injectionし、再実行収束またはold assignment rollbackを検証 |
| 全account exhausted | 自動切替せず現assignmentを維持し明示BLOCK |
| CodexBar表示範囲の誤一般化 | 複数claude-swap account統合は`cards`限定契約とする |
| uninstall後に復旧不能 | backup/restore手順をPoC前に作り、破損模擬から3/3復元 |

## 8. 最終提案

**`claude-swap + CodexBar CLI`はisolated pane安全性PoCの候補とする。現時点では実装採用不可である。**

Claude credential/capacity候補はclaude-swap、read-only capacity view候補はCodexBar `cards`である。CodexBarの`usage`/`serve`へ複数Claude account表示を一般化しない。local proxyもglobal credential mutationもPhase 0へ入れない。

Codexは1アカウントなので切替機構を増やさない。Codex 2 account目が来た時だけcodex-multi-authを追加すればClaude側と対称になる。

最初に解くのは便利さではなく、`account_profile → cli_launch_cmd → cswap run`が全respawn経路で保たれ、独立identity probe・fencing・rollback・fault injection・供給網監査を通ることである。P1〜P18が全てPASSした時だけcontrolled pane切替を採用判定する。

期待する運用変化:

```text
As-Is:
別々に残量を見る → 人がaccount判断 → logout/loginまたはconfig変更
→ 必要ならpane再起動 → 実態確認

To-Be:
codexbar cardsで3 accountのremaining/reset/data-ageをread-only表示
→ idle paneのdesired aliasをtransaction開始
→ fence下でisolated wrapperを起動
→ 独立identity probeでdesired=observedを確認
→ PASSならcommit、FAILならold assignmentへrollback
```

### 8.1 Review disposition

| 指摘 | 反映 |
|---|---|
| A failover transaction未定義 | §3.3にPRECHECK→FENCE→LAUNCH→VERIFY→COMMIT/ROLLBACKを定義 |
| B respawnで`cswap run`喪失 | §3.1とPhase 0で`account_profile`を`cli_launch_cmd`の入口契約へ昇格 |
| C global switchの波及/race | global mutationをPoC外化し、isolated pane + generation CASに限定 |
| D `cswap status`自己観測 | live CLI/profileの独立identity probeをP8へ追加 |
| E fault injection欠落 | P10〜P15にauto-respawn、watcher、refresh、stale、exhaustion、crashを追加 |
| F CodexBar cardinality誤認 | `cards`限定契約へ修正し`usage`/`serve`を除外 |
| G supply chain監査不足 | version/SHA/source/権限/egress/update/restoreをPhase 0とP17/P18へ追加 |
| H 30分断定 | 時間断定を撤去し、securityとrestoreを含む安全性PoCへ改称 |

## 9. 一次資料

- [claude-swap repository](https://github.com/realiti4/claude-swap)
- [CodexBar repository](https://github.com/steipete/CodexBar)
- [CodexBar CLI documentation](https://github.com/steipete/CodexBar/blob/main/docs/cli.md)
- [codex-multi-auth repository](https://github.com/ndycode/codex-multi-auth)
- [OpenAI Codex app-server rate limit API](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [ccusage repository](https://github.com/ccusage/ccusage)
- [CC Switch repository](https://github.com/farion1231/cc-switch)
- [CC Switch User Manual](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/en/README.md)
- [CC Switch provider switching](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/en/2-providers/2.2-switch.md)
- [CC Switch failover / circuit breaker](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/en/4-proxy/4.3-failover.md)
- [CC Switch Codex OAuth multi-account and risk notice](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/en/2-providers/2.1-add.md)
- [CLIProxyAPI repository](https://github.com/router-for-me/CLIProxyAPI)
- [CLIProxyAPI Codex multi-account continuity issue](https://github.com/router-for-me/CLIProxyAPI/issues/1382)
- [Quotio Desktop repository](https://github.com/xiaocoss/quotio-desktop)
- [Claude Code Router repository](https://github.com/musistudio/claude-code-router)
- [Anthropic Claude Code multi-account issue and `CLAUDE_CONFIG_DIR` workaround](https://github.com/anthropics/claude-code/issues/261)

## 10. ローカル根拠

- `config/cli_profiles.yaml`
- `config/settings.yaml`
- `scripts/lib/cli_lookup.sh`（`cli_launch_cmd` resolver）
- `scripts/agent_respawn.sh`（manual/recovery respawn経路）
- `scripts/ninja_monitor.sh`（auto-respawn経路）
- `scripts/switch_cli_mode.sh`
- `skills/shogun-cli-switch/SKILL.md`
- `docs/research/cmd_314_account_switching_procedures.md`
- `docs/research/cmd_314_usage_api_verification.md`
- `docs/research/model-comparison-5w1h-20260701.md`
- `docs/research/gunshi_idle_auto_clear_ratelimit_design_20260720.md`
- `context/infrastructure.md`

---

Memory trace:

- `[MEM: memory_db ts=2026-07-31T10:41:52+09:00 "multi CLI・複数アカウント・rate limit切替の簡素化"]`
- `[MEM: semantic concept=multi_cli_event_commonization]`
- `[MEM: obsidian link=[[multi_cli_hook_gap]]]`
