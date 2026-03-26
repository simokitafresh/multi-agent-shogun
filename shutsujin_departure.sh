#!/bin/bash
# 🏯 multi-agent-shogun 出陣スクリプト（毎日の起動用）
# Daily Deployment Script for Multi-Agent Orchestration System
#
# 使用方法:
#   ./shutsujin_departure.sh           # 全エージェント起動（前回の状態を維持）
#   ./shutsujin_departure.sh -c        # キューをリセットして起動（クリーンスタート）
#   ./shutsujin_departure.sh -s        # セットアップのみ（Claude起動なし）
#   ./shutsujin_departure.sh -h        # ヘルプ表示

set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# エージェント構成の一元管理ライブラリ読み込み
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"

# venvプリフライトチェック（Python依存のある処理の前に確認）
VENV_DIR="$SCRIPT_DIR/.venv"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"
if [ ! -f "$VENV_DIR/bin/python3" ] || ! "$VENV_DIR/bin/python3" -c "import yaml" 2>/dev/null; then
    echo "venv missing or broken. Recreating..."
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        echo "ERROR: requirements.txt not found at $REQUIREMENTS_FILE"
        exit 1
    fi
    python3 -m venv "$VENV_DIR" || { echo "ERROR: venv creation failed"; exit 1; }
    "$VENV_DIR/bin/pip" install -r "$REQUIREMENTS_FILE" -q || { echo "ERROR: pip install -r requirements.txt failed"; exit 1; }
    "$VENV_DIR/bin/python3" -c "import yaml" 2>/dev/null || { echo "ERROR: PyYAML import failed after venv recreation"; exit 1; }
fi

# 言語設定を読み取り（デフォルト: ja）
LANG_SETTING="ja"
if [ -f "./config/settings.yaml" ]; then
    LANG_SETTING=$(grep "^language:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "ja")
fi

# シェル設定を読み取り（デフォルト: bash）
SHELL_SETTING="bash"
if [ -f "./config/settings.yaml" ]; then
    SHELL_SETTING=$(grep "^shell:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "bash")
fi

# CLI Adapter読み込み（Multi-CLI Support）
if [ -f "$SCRIPT_DIR/lib/cli_adapter.sh" ]; then
    source "$SCRIPT_DIR/lib/cli_adapter.sh"
    CLI_ADAPTER_LOADED=true
else
    CLI_ADAPTER_LOADED=false
fi

# モデル別色定義ライブラリ読み込み
if [ -f "$SCRIPT_DIR/scripts/lib/model_colors.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/model_colors.sh"
fi

# 色付きログ関数（戦国風）
log_info() {
    echo -e "\033[1;33m【報】\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m【成】\033[0m $1"
}

log_war() {
    echo -e "\033[1;31m【戦】\033[0m $1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# プロンプト生成関数（bash/zsh対応）
# ───────────────────────────────────────────────────────────────────────────────
# 使用法: generate_prompt "ラベル" "色" "シェル"
# 色: red, green, blue, magenta, cyan, yellow
# ═══════════════════════════════════════════════════════════════════════════════
generate_prompt() {
    local label="$1"
    local color="$2"
    local shell_type="$3"

    if [ "$shell_type" == "zsh" ]; then
        # zsh用: %F{color}%B...%b%f 形式
        echo "(%F{${color}}%B${label}%b%f) %F{green}%B%~%b%f%# "
    else
        # bash用: \[\033[...m\] 形式
        local color_code
        case "$color" in
            red)     color_code="1;31" ;;
            green)   color_code="1;32" ;;
            yellow)  color_code="1;33" ;;
            blue)    color_code="1;34" ;;
            magenta) color_code="1;35" ;;
            cyan)    color_code="1;36" ;;
            *)       color_code="1;37" ;;  # white (default)
        esac
        echo "(\[\033[${color_code}m\]${label}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ "
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# オプション解析
# ═══════════════════════════════════════════════════════════════════════════════
SETUP_ONLY=false
OPEN_TERMINAL=false
CLEAN_MODE=false
KESSEN_MODE=false
SHOGUN_NO_THINKING=false
SILENT_MODE=false
SHELL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--setup-only)
            SETUP_ONLY=true
            shift
            ;;
        -c|--clean)
            CLEAN_MODE=true
            shift
            ;;
        -k|--kessen)
            KESSEN_MODE=true
            shift
            ;;
        -t|--terminal)
            OPEN_TERMINAL=true
            shift
            ;;
        --shogun-no-thinking)
            SHOGUN_NO_THINKING=true
            shift
            ;;
        -S|--silent)
            SILENT_MODE=true
            shift
            ;;
        -shell|--shell)
            if [[ -n "$2" && "$2" != -* ]]; then
                SHELL_OVERRIDE="$2"
                shift 2
            else
                echo "エラー: -shell オプションには bash または zsh を指定してください"
                exit 1
            fi
            ;;
        -h|--help)
            echo ""
            echo "🏯 multi-agent-shogun 出陣スクリプト"
            echo ""
            echo "使用方法: ./shutsujin_departure.sh [オプション]"
            echo ""
            echo "オプション:"
            echo "  -c, --clean         キューとダッシュボードをリセットして起動（クリーンスタート）"
            echo "                      未指定時は前回の状態を維持して起動"
            echo "  -k, --kessen        決戦の陣（全忍者をOpusで起動）"
            echo "                      未指定時はCLI Adapter設定に従う"
            echo "  -s, --setup-only    tmuxセッションのセットアップのみ（Claude起動なし）"
            echo "  -t, --terminal      Windows Terminal で新しいタブを開く"
            echo "  -shell, --shell SH  シェルを指定（bash または zsh）"
            echo "                      未指定時は config/settings.yaml の設定を使用"
            echo "  -S, --silent        サイレントモード（忍者の戦国echo表示を無効化・API節約）"
            echo "                      未指定時はshoutモード（タスク完了時に戦国風echo表示）"
            echo "  -h, --help          このヘルプを表示"
            echo ""
            echo "例:"
            echo "  ./shutsujin_departure.sh              # 前回の状態を維持して出陣"
            echo "  ./shutsujin_departure.sh -c           # クリーンスタート（キューリセット）"
            echo "  ./shutsujin_departure.sh -s           # セットアップのみ（手動でClaude起動）"
            echo "  ./shutsujin_departure.sh -t           # 全エージェント起動 + ターミナルタブ展開"
            echo "  ./shutsujin_departure.sh -shell bash  # bash用プロンプトで起動"
            echo "  ./shutsujin_departure.sh -k           # 決戦の陣（全忍者Opus）"
            echo "  ./shutsujin_departure.sh -c -k         # クリーンスタート＋決戦の陣"
            echo "  ./shutsujin_departure.sh -shell zsh   # zsh用プロンプトで起動"
            echo "  ./shutsujin_departure.sh --shogun-no-thinking  # 将軍のthinkingを無効化（中継特化）"
            echo "  ./shutsujin_departure.sh -S           # サイレントモード（echo表示なし）"
            echo ""
            echo "モデル構成:"
            echo "  将軍:      Opus 4.6"
            echo "  家老:      Opus 4.6"
            echo "  軍師:      Opus 4.6"
            echo "  忍者(全員): Opus 4.6"
            echo ""
            echo "陣形:"
            echo "  平時の陣（デフォルト）: CLI Adapter設定に従う（全Opus 4.6）"
            echo "  決戦の陣（--kessen）:   全忍者=Opus"
            echo ""
            echo "表示モード:"
            echo "  shout（デフォルト）:  タスク完了時に戦国風echo表示"
            echo "  silent（--silent）:   echo表示なし（API節約）"
            echo ""
            echo "エイリアス:"
            echo "  csst  → cd /mnt/c/tools/multi-agent-shogun && ./shutsujin_departure.sh"
            echo "  csm   → tmux attach-session -t shogun"
            echo ""
            exit 0
            ;;
        *)
            echo "不明なオプション: $1"
            echo "./shutsujin_departure.sh -h でヘルプを表示"
            exit 1
            ;;
    esac
done

# シェル設定のオーバーライド（コマンドラインオプション優先）
if [ -n "$SHELL_OVERRIDE" ]; then
    if [[ "$SHELL_OVERRIDE" == "bash" || "$SHELL_OVERRIDE" == "zsh" ]]; then
        SHELL_SETTING="$SHELL_OVERRIDE"
    else
        echo "エラー: -shell オプションには bash または zsh を指定してください（指定値: $SHELL_OVERRIDE）"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 出陣バナー表示（CC0ライセンスASCIIアート使用）
# ───────────────────────────────────────────────────────────────────────────────
# 【著作権・ライセンス表示】
# 忍者ASCIIアート: syntax-samurai/ryu - CC0 1.0 Universal (Public Domain)
# 出典: https://github.com/syntax-samurai/ryu
# "all files and scripts in this repo are released CC0 / kopimi!"
# ═══════════════════════════════════════════════════════════════════════════════
show_battle_cry() {
    clear

    # タイトルバナー（色付き）
    echo ""
    echo -e "\033[1;31m╔══════════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m███████╗██╗  ██╗██╗   ██╗████████╗███████╗██╗   ██╗     ██╗██╗███╗   ██╗\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m██╔════╝██║  ██║██║   ██║╚══██╔══╝██╔════╝██║   ██║     ██║██║████╗  ██║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m███████╗███████║██║   ██║   ██║   ███████╗██║   ██║     ██║██║██╔██╗ ██║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m╚════██║██╔══██║██║   ██║   ██║   ╚════██║██║   ██║██   ██║██║██║╚██╗██║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m███████║██║  ██║╚██████╔╝   ██║   ███████║╚██████╔╝╚█████╔╝██║██║ ╚████║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m╚══════╝╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝ ╚═════╝  ╚════╝ ╚═╝╚═╝  ╚═══╝\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m╠══════════════════════════════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;31m║\033[0m       \033[1;37m出陣じゃーーー！！！\033[0m    \033[1;36m⚔\033[0m    \033[1;35m天下布武！\033[0m                          \033[1;31m║\033[0m"
    echo -e "\033[1;31m╚══════════════════════════════════════════════════════════════════════════════════╝\033[0m"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # 忍者隊列（オリジナル）
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;34m  ╔═════════════════════════════════════════════════════════════════════════════╗\033[0m"
    _ninja_count=$(get_ninja_names | wc -w)
    _squad_label="軍師1名+忍者${_ninja_count}名"
    echo -e "\033[1;34m  ║\033[0m                    \033[1;37m【 忍 者 隊 列 ・ ${_squad_label} 配 備 】\033[0m                      \033[1;34m║\033[0m"
    echo -e "\033[1;34m  ╚═════════════════════════════════════════════════════════════════════════════╝\033[0m"

    cat << 'NINJA_EOF'

       /\      /\      /\      /\      /\      /\      /\
      /||\    /||\    /||\    /||\    /||\    /||\    /||\
     /_||\   /_||\   /_||\   /_||\   /_||\   /_||\   /_||\
       ||      ||      ||      ||      ||      ||      ||
      /||\    /||\    /||\    /||\    /||\    /||\    /||\
      /  \    /  \    /  \    /  \    /  \    /  \    /  \
     [軍師]  [疾風]  [影丸]  [半蔵]  [才蔵] [小太郎] [飛猿]

NINJA_EOF

    echo -e "                    \033[1;36m「「「 はっ！！ 出陣いたす！！ 」」」\033[0m"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # システム情報
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;33m  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\033[0m"
    echo -e "\033[1;33m  ┃\033[0m  \033[1;37m🏯 multi-agent-shogun\033[0m  〜 \033[1;36m戦国マルチエージェント統率システム\033[0m 〜           \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┃\033[0m                                                                           \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┃\033[0m  \033[1;35m将軍\033[0m: 統括  \033[1;31m家老\033[0m: 管理  \033[1;36m軍師\033[0m: 参謀×1  \033[1;34m忍者\033[0m: 実働×${_ninja_count}      \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m"
    echo ""
}

# バナー表示実行
show_battle_cry

echo -e "  \033[1;33m天下布武！陣立てを開始いたす\033[0m (Setting up the battlefield)"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: 既存セッションクリーンアップ
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🧹 既存の陣を撤収中..."
tmux kill-session -t shogun 2>/dev/null && log_info "  └─ shogun陣、撤収完了" || log_info "  └─ shogun陣は存在せず"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1.5: 前回記録のバックアップ（--clean時のみ、内容がある場合）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$CLEAN_MODE" = true ]; then
    BACKUP_DIR="./logs/backup_$(date '+%Y%m%d_%H%M%S')"
    NEED_BACKUP=false

    if [ -f "./dashboard.md" ]; then
        if grep -q "cmd_" "./dashboard.md" 2>/dev/null; then
            NEED_BACKUP=true
        fi
    fi

    # 既存の dashboard.md 判定の後に追加
    if [ -f "./queue/shogun_to_karo.yaml" ]; then
        if grep -q "id: cmd_" "./queue/shogun_to_karo.yaml" 2>/dev/null; then
            NEED_BACKUP=true
        fi
    fi

    if [ "$NEED_BACKUP" = true ]; then
        mkdir -p "$BACKUP_DIR" || true
        cp "./dashboard.md" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/reports" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/tasks" "$BACKUP_DIR/" 2>/dev/null || true
        cp "./queue/shogun_to_karo.yaml" "$BACKUP_DIR/" 2>/dev/null || true
        log_info "📦 前回の記録をバックアップ: $BACKUP_DIR"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: キューディレクトリ確保 + リセット（--clean時のみリセット）
# ═══════════════════════════════════════════════════════════════════════════════

# queue ディレクトリが存在しない場合は作成（初回起動時に必要）
[ -d ./queue/reports ] || mkdir -p ./queue/reports
[ -d ./queue/tasks ] || mkdir -p ./queue/tasks
# inbox はLinux FSにシンボリックリンク（WSL2の/mnt/c/ではinotifywaitが動かないため）
INBOX_LINUX_DIR="$HOME/.local/share/multi-agent-shogun/inbox"
if [ ! -L ./queue/inbox ]; then
    mkdir -p "$INBOX_LINUX_DIR"
    [ -d ./queue/inbox ] && cp ./queue/inbox/*.yaml "$INBOX_LINUX_DIR/" 2>/dev/null && rm -rf ./queue/inbox
    ln -sf "$INBOX_LINUX_DIR" ./queue/inbox
    log_info "  └─ inbox → Linux FS ($INBOX_LINUX_DIR) にシンボリックリンク作成"
fi

if [ "$CLEAN_MODE" = true ]; then
    log_info "📜 前回の軍議記録を破棄中..."

    # 忍者名配列（agent_config.shから動的取得）
    read -ra NINJA_NAMES <<< "$(get_ninja_names)"

    # 忍者タスクファイルリセット
    for name in "${NINJA_NAMES[@]}"; do
        cat > ./queue/tasks/${name}.yaml << EOF
# ${name}専用タスクファイル
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF
    done

    # 忍者レポートファイルリセット
    # 現行命名は {ninja}_report_{cmd}.yaml のため、clean startでは過去レポートを一括削除する
    find ./queue/reports -maxdepth 1 -type f -name '*_report*.yaml' -delete

    # ntfy inbox リセット
    echo "inbox:" > ./queue/ntfy_inbox.yaml

    # agent inbox リセット
    for agent in shogun $(get_all_agents); do
        echo "messages:" > "./queue/inbox/${agent}.yaml"
    done

    log_success "✅ 陣払い完了"
else
    log_info "📜 前回の陣容を維持して出陣..."
    log_success "✅ キュー・報告ファイルはそのまま継続"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: ダッシュボード初期化（--clean時のみ）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$CLEAN_MODE" = true ]; then
    log_info "📊 戦況報告板を初期化中..."
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

    if [ "$LANG_SETTING" = "ja" ]; then
        # 日本語のみ
        cat > ./dashboard.md << EOF
# 📊 戦況報告
最終更新: ${TIMESTAMP}

## 🚨 要対応 - 殿のご判断をお待ちしております
なし

## 🔄 進行中 - 只今、戦闘中でござる
なし

## ✅ 本日の戦果
| 時刻 | 戦場 | 任務 | 結果 |
|------|------|------|------|

## 🎯 スキル化候補 - 承認待ち
なし

## 🛠️ 生成されたスキル
なし

## ⏸️ 待機中
なし

## ❓ 伺い事項
なし
EOF
    else
        # 日本語 + 翻訳併記
        cat > ./dashboard.md << EOF
# 📊 戦況報告 (Battle Status Report)
最終更新 (Last Updated): ${TIMESTAMP}

## 🚨 要対応 - 殿のご判断をお待ちしております (Action Required - Awaiting Lord's Decision)
なし (None)

## 🔄 進行中 - 只今、戦闘中でござる (In Progress - Currently in Battle)
なし (None)

## ✅ 本日の戦果 (Today's Achievements)
| 時刻 (Time) | 戦場 (Battlefield) | 任務 (Mission) | 結果 (Result) |
|------|------|------|------|

## 🎯 スキル化候補 - 承認待ち (Skill Candidates - Pending Approval)
なし (None)

## 🛠️ 生成されたスキル (Generated Skills)
なし (None)

## ⏸️ 待機中 (On Standby)
なし (None)

## ❓ 伺い事項 (Questions for Lord)
なし (None)
EOF
    fi

    log_success "  └─ ダッシュボード初期化完了 (言語: $LANG_SETTING, シェル: $SHELL_SETTING)"
else
    log_info "📊 前回のダッシュボードを維持"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: tmux の存在確認
# ═══════════════════════════════════════════════════════════════════════════════
if ! command -v tmux &> /dev/null; then
    echo ""
    echo "  ╔════════════════════════════════════════════════════════╗"
    echo "  ║  [ERROR] tmux not found!                              ║"
    echo "  ║  tmux が見つかりません                                 ║"
    echo "  ╠════════════════════════════════════════════════════════╣"
    echo "  ║  Run first_setup.sh first:                            ║"
    echo "  ║  まず first_setup.sh を実行してください:               ║"
    echo "  ║     ./first_setup.sh                                  ║"
    echo "  ╚════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: shogun セッション作成 — mainウィンドウ（将軍の本陣）
# ═══════════════════════════════════════════════════════════════════════════════
log_war "👑 将軍の本陣を構築中..."

# shogun セッションがなければ作る — window 0 = main（将軍）
if ! tmux has-session -t shogun 2>/dev/null; then
    tmux new-session -d -s shogun -n main
fi

# グローバル設定: 接続元端末サイズ差分を吸収
tmux set-option -g window-size latest
tmux set-option -g aggressive-resize on

# 将軍ペインはウィンドウ名 "main" で指定（base-index 1 環境でも動く）
SHOGUN_PROMPT=$(generate_prompt "将軍" "magenta" "$SHELL_SETTING")
tmux send-keys -t shogun:main "cd \"$(pwd)\" && export PS1='${SHOGUN_PROMPT}' && clear" Enter
tmux select-pane -t shogun:main -P 'bg=#002b36'  # 将軍の Solarized Dark
tmux set-option -p -t shogun:main @agent_id "shogun"
tmux set-option -p -t shogun:main @context_pct "--"

log_success "  └─ 将軍の本陣、構築完了"
echo ""

# pane-base-index を取得（1 の環境ではペインは 1,2,... になる）
PANE_BASE=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5.1: agents ウィンドウ追加（家老+軍師+忍者6名 = 8ペイン）
# ═══════════════════════════════════════════════════════════════════════════════
_deploy_count=$(get_all_agents | wc -w)
log_war "⚔️ 家老・忍者の陣を構築中（${_deploy_count}名配備）..."

# shogun セッションに agents ウィンドウを追加
if ! tmux new-window -t shogun -n "agents" 2>/dev/null; then
    echo ""
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║  [ERROR] Failed to create window 'agents'                ║"
    echo "  ║  agents ウィンドウの作成に失敗しました                   ║"
    echo "  ╠════════════════════════════════════════════════════════════╣"
    echo "  ║  shogun session may not exist.                       ║"
    echo "  ║  セッションが存在しない可能性があります                  ║"
    echo "  ║                                                          ║"
    echo "  ║  Check: tmux ls                                          ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
fi

# DISPLAY_MODE: shout (default) or silent (--silent flag)
if [ "$SILENT_MODE" = true ]; then
    tmux set-environment -t shogun DISPLAY_MODE "silent"
    echo "  📢 表示モード: サイレント（echo表示なし）"
else
    tmux set-environment -t shogun DISPLAY_MODE "shout"
fi

# 3列 2-3-3 レイアウト作成（ペイン番号=エージェント順の連続番号）
# ペインを先に全数作成し、select-layoutで3列配置を適用する。
# これによりペイン番号がget_all_agents順と一致(karo=PB, gunshi=PB+1, hayate=PB+2, ...)
# → pane_lookup静的フォールバック・reset_layoutのswapが不要

# 列割当（表示位置の決定。split順序には影響しない）
read -ra _ALL_AG <<< "$(get_all_agents)"
_ninja_ci=0; _COL1=(); _COL2=(); _COL3=()
for _ag in "${_ALL_AG[@]}"; do
    _r=$(get_agent_role "$_ag")
    if [[ "$_r" == "ninja" ]]; then
        if (( _ninja_ci < 3 )); then _COL2+=("$_ag")
        elif (( _ninja_ci < 6 )); then _COL3+=("$_ag")
        else _COL1+=("$_ag")
        fi
        _ninja_ci=$((_ninja_ci + 1))
    else
        _COL1+=("$_ag")
    fi
done

# 8ペイン作成（連続番号: PB〜PB+7）
# Step 1: 上下2行に分割
tmux split-window -v -t "shogun:agents.${PANE_BASE}"

# Step 2: 上段を水平分割3回（PB, PB+2, PB+3, PB+4）
_target=${PANE_BASE}
for ((s=0; s<3; s++)); do
    tmux split-window -h -t "shogun:agents.${_target}"
    _target=$((PANE_BASE + 2 + s))
done

# Step 3: 下段を水平分割3回（PB+1, PB+5, PB+6, PB+7）
_target=$((PANE_BASE + 1))
for ((s=0; s<3; s++)); do
    tmux split-window -h -t "shogun:agents.${_target}"
    _target=$((PANE_BASE + 5 + s))
done

# select-layout で3列 2-3-3 に配置（動的LAYOUT_STRING）
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/layout_string.sh"
_layout=$(generate_layout_string "shogun:agents" "$PANE_BASE")
tmux select-layout -t "shogun:agents" "$_layout"

# PANE_IDS: 連続番号（ペイン番号=エージェント順）
PANE_IDS=()
AGENT_IDS=("${_COL1[@]}" "${_COL2[@]}" "${_COL3[@]}")
for ((i=0; i<${#AGENT_IDS[@]}; i++)); do
    PANE_IDS+=("$((PANE_BASE + i))")
done

# ペインラベル・色を動的構築
PANE_LABELS=("${AGENT_IDS[@]}")
# 色設定: role判定で動的生成（karo=red, gunshi=cyan, ninja=yellow）
PANE_COLORS=()
for _aid in "${AGENT_IDS[@]}"; do
    _role=$(get_agent_role "$_aid")
    case "$_role" in
        karo)   PANE_COLORS+=("red") ;;
        gunshi) PANE_COLORS+=("cyan") ;;
        *)      PANE_COLORS+=("yellow") ;;
    esac
done

# モデル名設定（CLI Adapterから動的に取得 — ハードコード禁止）
MODEL_NAMES=()
PANE_TITLES=()
AGENT_COUNT=${#AGENT_IDS[@]}
for i in $(seq 0 $((AGENT_COUNT-1))); do
    _agent="${AGENT_IDS[$i]}"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _cli=$(get_cli_type "$_agent")
        case "$_cli" in
            codex)
                _codex_model=$(grep '^model ' ~/.codex/config.toml 2>/dev/null | head -1 | sed 's/.*= *"\(.*\)"/\1/')
                _codex_effort=$(grep '^model_reasoning_effort' ~/.codex/config.toml 2>/dev/null | head -1 | sed 's/.*= *"\(.*\)"/\1/')
                _codex_model=${_codex_model:-gpt-5.4}
                _codex_effort=${_codex_effort:-high}
                MODEL_NAMES[$i]="${_codex_model}/${_codex_effort}"
                ;;
            copilot)
                MODEL_NAMES[$i]="Copilot"
                ;;
            kimi)
                MODEL_NAMES[$i]="Kimi"
                ;;
            claude|*)
                _model=$(get_agent_model "$_agent")
                # 決戦モード: claudeは全員Opus強制
                if [ "$KESSEN_MODE" = true ] && [ "$_cli" = "claude" ]; then
                    _model="opus"
                fi
                # 先頭大文字化（opus→Opus, haiku→Haiku）
                MODEL_NAMES[$i]="$(echo "${_model:0:1}" | tr '[:lower:]' '[:upper:]')${_model:1}"
                ;;
        esac
    else
        # CLI Adapter未読み込み時のフォールバック
        if [ "$KESSEN_MODE" = true ]; then
            MODEL_NAMES[$i]="Opus"
        else
            # CLI Adapter未読み込み時: settings.yamlから直接model_nameを読む
            _model_raw=$(python3 -c "
import yaml
try:
    with open('${SETTINGS_YAML:-./config/settings.yaml}') as f:
        cfg = yaml.safe_load(f) or {}
    agents = cfg.get('cli', {}).get('agents', {})
    agent = agents.get('${_agent}', {})
    if isinstance(agent, dict):
        mn = agent.get('model_name', '')
        if mn:
            for name in ['Opus', 'Haiku']:
                if name.lower() in mn.lower():
                    print(name)
                    raise SystemExit
            if 'gpt' in mn.lower() or 'codex' in mn.lower():
                print('Codex')
                raise SystemExit
        print('Opus')
    else:
        print('Opus')
except SystemExit:
    pass
except Exception:
    print('Opus')
" 2>/dev/null)
            MODEL_NAMES[$i]="${_model_raw:-Opus}"
        fi
    fi
    PANE_TITLES[$i]="${MODEL_NAMES[$i]}"
done

for i in $(seq 0 $((AGENT_COUNT-1))); do
    p=${PANE_IDS[$i]}
    tmux select-pane -t "shogun:agents.${p}" -T "${PANE_TITLES[$i]}"
    tmux set-option -p -t "shogun:agents.${p}" @agent_id "${AGENT_IDS[$i]}"
    tmux set-option -p -t "shogun:agents.${p}" @model_name "${MODEL_NAMES[$i]}"
    tmux set-option -p -t "shogun:agents.${p}" @current_task ""
    tmux set-option -p -t "shogun:agents.${p}" @context_pct "--"
    _bg_color=$(resolve_bg_color "${AGENT_IDS[$i]}" "${MODEL_NAMES[$i]}")
    tmux select-pane -t "shogun:agents.${p}" -P "bg=${_bg_color}"
    PROMPT_STR=$(generate_prompt "${PANE_LABELS[$i]}" "${PANE_COLORS[$i]}" "$SHELL_SETTING")
    tmux send-keys -t "shogun:agents.${p}" "cd \"$(pwd)\" && export PS1='${PROMPT_STR}' && clear" Enter
done

# ─── remain-on-exit (cmd_183) ───
# CLIプロセスが死んでもペインを残す（OOM Kill等の原因調査用）
tmux set-option -w -t "shogun:agents" remain-on-exit on 2>/dev/null

# ─── pane-border-format: ペイン枠にagent_id・モデル名・タスクを常時表示 ───
# Color scheme: karo=#f9e2af(黄) gunshi=#94e2d5(水色) Opus=#cba6f7(紫) gpt-*=#a6e3a1(緑) else=#89b4fa(青)
tmux set-option -t shogun:agents -w pane-border-status top
tmux set-option -w -t "shogun:agents" pane-border-format \
  '#{?#{==:#{@agent_id},karo},#[fg=#f9e2af],#{?#{==:#{@agent_id},gunshi},#[fg=#94e2d5],#{?#{m:Opus*,#{@model_name}},#[fg=#cba6f7],#{?#{m:gpt-*,#{@model_name}},#[fg=#a6e3a1],#[fg=#89b4fa]}}}}#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]#{?#{!=:#{@inbox_count},},#[fg=#fab387]#{@inbox_count}#[default],} #{@current_task}' \
  2>/dev/null

# ─── shogun window pane-border ───
tmux set-option -w -t "shogun:main" pane-border-status top 2>/dev/null
tmux set-option -w -t "shogun:main" pane-border-format \
  '#[fg=#cba6f7]#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]' \
  2>/dev/null

# ─── 将軍ペイン変数 ───
_shogun_pane_idx=$(tmux list-panes -t "shogun:main" -F '#{pane_index}' 2>/dev/null | head -1)
tmux set-option -p -t "shogun:main.${_shogun_pane_idx:-0}" @agent_id shogun 2>/dev/null
tmux set-option -p -t "shogun:main.${_shogun_pane_idx:-0}" @model_name "Opus" 2>/dev/null

# ─── status bar style: Catppuccin Mocha base ───
tmux set-option -g status-style "bg=#1e1e2e,fg=#cdd6f4" 2>/dev/null
tmux set-option -t shogun status-right-length 200
tmux set-option -t shogun status-right "#[fg=#cdd6f4]%Y-%m-%d %H:%M"

# ─── Prefix+v: clipboard screenshot capture (cmd_551) ───
tmux bind-key v run-shell "bash ${SCRIPT_DIR}/scripts/capture_clipboard_image.sh"

# ─── idle flag initialization (cmd_455) ───
_STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"
mkdir -p "$_STATE_DIR"
for _agent in $(get_all_agents); do
    touch "${_STATE_DIR}/shogun_idle_${_agent}"
done

# ─── ペイン変数検証 ───
_verify_fail=0
for i in $(seq 0 $((AGENT_COUNT-1))); do
    p=${PANE_IDS[$i]}
    _actual_id=$(tmux show-options -p -t "shogun:agents.${p}" -v @agent_id 2>/dev/null)
    if [ "$_actual_id" != "${AGENT_IDS[$i]}" ]; then
        echo "  ⚠️ VERIFY FAIL: pane ${p} expected @agent_id='${AGENT_IDS[$i]}' got '${_actual_id}'"
        _verify_fail=1
    fi
done
if [ "$_verify_fail" -eq 0 ]; then
    log_success "  └─ ペイン変数検証: 全${AGENT_COUNT}名 OK"
else
    echo "  ⚠️ ペイン変数に不整合あり。手動確認してください。"
fi

log_success "  └─ 家老・忍者の陣、構築完了"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: Claude Code 起動（-s / --setup-only のときはスキップ）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$SETUP_ONLY" = false ]; then
    # CLI の存在チェック（Multi-CLI対応）
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        # 全agentで実際に使うCLI種別を重複排除して検証する。
        # get_cli_type "" は後方互換で claude を返すため、ここでは使わない。
        declare -A _required_cli_map=()
        for _agent in shogun $(get_all_agents); do
            _agent_cli=$(get_cli_type "$_agent")
            case "$_agent_cli" in
                claude|codex|copilot|kimi)
                    _required_cli_map["$_agent_cli"]=1
                    ;;
            esac
        done
        for _required_cli in "${!_required_cli_map[@]}"; do
            if ! validate_cli_availability "$_required_cli"; then
                exit 1
            fi
        done
    else
        if ! command -v claude &> /dev/null; then
            log_info "⚠️  claude コマンドが見つかりません"
            echo "  first_setup.sh を再実行してください:"
            echo "    ./first_setup.sh"
            exit 1
        fi
    fi

    log_war "👑 全軍に Claude Code を召喚中..."

    # 将軍: CLI Adapter経由でコマンド構築
    _shogun_cli_type="claude"
    _shogun_cmd="claude --model opus --dangerously-skip-permissions"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _shogun_cli_type=$(get_cli_type "shogun")
        _shogun_cmd=$(build_cli_command "shogun")
    fi
    tmux set-option -p -t "shogun:main" @agent_cli "$_shogun_cli_type"
    if [ "$SHOGUN_NO_THINKING" = true ] && [ "$_shogun_cli_type" = "claude" ]; then
        tmux send-keys -t shogun:main "MAX_THINKING_TOKENS=0 $_shogun_cmd"
        tmux send-keys -t shogun:main Enter
        log_info "  └─ 将軍（${_shogun_cli_type} / thinking無効）、召喚完了"
    else
        tmux send-keys -t shogun:main "$_shogun_cmd"
        tmux send-keys -t shogun:main Enter
        log_info "  └─ 将軍（${_shogun_cli_type}）、召喚完了"
    fi

    # 少し待機（安定のため）
    sleep 1

    # 家老（pane 0）: CLI Adapter経由でコマンド構築
    p=${PANE_IDS[0]}
    _karo_cli_type="claude"
    _karo_cmd="claude --model opus --dangerously-skip-permissions"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _karo_cli_type=$(get_cli_type "karo")
        _karo_cmd=$(build_cli_command "karo")
    fi
    tmux set-option -p -t "shogun:agents.${p}" @agent_cli "$_karo_cli_type"
    tmux send-keys -t "shogun:agents.${p}" "$_karo_cmd"
    tmux send-keys -t "shogun:agents.${p}" Enter
    log_info "  └─ 家老（${_karo_cli_type}）、召喚完了"

    NINJA_PANE_COUNT=$((AGENT_COUNT - 1))
    if [ "$KESSEN_MODE" = true ]; then
        # 決戦の陣: CLI Adapter経由（claudeはOpus強制）
        for i in $(seq 1 $NINJA_PANE_COUNT); do
            p=${PANE_IDS[$i]}
            ninja_name="${AGENT_IDS[$i]}"
            _ashi_cli_type="claude"
            _ashi_cmd="claude --model opus --dangerously-skip-permissions"
            if [ "$CLI_ADAPTER_LOADED" = true ]; then
                _ashi_cli_type=$(get_cli_type "${ninja_name}")
                if [ "$_ashi_cli_type" = "claude" ]; then
                    # 決戦モード: claudeは全員Opus強制
                    _ashi_cmd="claude --model opus --dangerously-skip-permissions"
                else
                    _ashi_cmd=$(build_cli_command "${ninja_name}")
                fi
            fi
            tmux set-option -p -t "shogun:agents.${p}" @agent_cli "$_ashi_cli_type"
            tmux send-keys -t "shogun:agents.${p}" "$_ashi_cmd"
            tmux send-keys -t "shogun:agents.${p}" Enter
        done
        log_info "  └─ 忍者・軍師1-${NINJA_PANE_COUNT}（決戦の陣）、召喚完了"
    else
        # 平時の陣: CLI Adapter経由で各忍者のCLI/モデルを決定
        for i in $(seq 1 $NINJA_PANE_COUNT); do
            p=${PANE_IDS[$i]}
            ninja_name="${AGENT_IDS[$i]}"
            _ashi_cli_type="claude"
            _ashi_cmd="claude --model opus --dangerously-skip-permissions"
            if [ "$CLI_ADAPTER_LOADED" = true ]; then
                _ashi_cli_type=$(get_cli_type "${ninja_name}")
                _ashi_cmd=$(build_cli_command "${ninja_name}")
            fi
            tmux set-option -p -t "shogun:agents.${p}" @agent_cli "$_ashi_cli_type"
            tmux send-keys -t "shogun:agents.${p}" "$_ashi_cmd"
            tmux send-keys -t "shogun:agents.${p}" Enter
        done
        log_info "  └─ 忍者・軍師1-${NINJA_PANE_COUNT}（平時の陣）、召喚完了"
    fi

    if [ "$KESSEN_MODE" = true ]; then
        log_success "✅ 決戦の陣で出陣！全軍Opus！"
    else
        log_success "✅ 平時の陣で出陣"
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6.5: 各エージェントに指示書を読み込ませる
    # ═══════════════════════════════════════════════════════════════════════════
    log_war "📜 各エージェントに指示書を読み込ませ中..."
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # 忍者戦士（syntax-samurai/ryu - CC0 1.0 Public Domain）
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;35m  ┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;35m  │\033[0m                              \033[1;37m【 忍 者 戦 士 】\033[0m  Ryu Hayabusa (CC0 Public Domain)                        \033[1;35m│\033[0m"
    echo -e "\033[1;35m  └────────────────────────────────────────────────────────────────────────────────────────────────────────────┘\033[0m"

    cat << 'NINJA_EOF'
...................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░▒▒▒▒▒▒                         ...................................
..................................░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░▒▒▒▒▒▒▒                         ...................................
..................................░░░░░░░░░░░░░░░░▒▒▒▒          ▒▒▒▒▒▒▒▒░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░▒▒▒▒▒▒▒▒▒                             ...................................
..................................░░░░░░░░░░░░░░▒▒▒▒               ▒▒▒▒▒░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                ...................................
..................................░░░░░░░░░░░░░▒▒▒                    ▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                    ...................................
..................................░░░░░░░░░░░░▒                            ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                        ...................................
..................................░░░░░░░░░░░      ░░░░░░░░░░░░░                                      ░░░░░░░░░░░░       ▒          ...................................
..................................░░░░░░░░░░ ▒    ░░░▓▓▓▓▓▓▓▓▓▓▓▓░░                                 ░░░░░░░░░░░░░░░ ░               ...................................
..................................░░░░░░░░░░     ░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░                          ░░░░░░░░░░░░░░░░░░░                ...................................
..................................░░░░░░░░░ ▒  ░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░             ░░▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░  ░   ▒         ...................................
..................................░░░░░░░░ ░  ░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░ ░  ▒         ...................................
..................................░░░░░░░░ ░  ░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░  ░    ▒        ...................................
..................................░░░░░░░░░▒  ░ ░               ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓░                 ░            ...................................
.................................░░░░░░░░░░   ░░░  ░                 ▓▓▓▓▓▓▓▓░▓▓▓▓░░░▓░░░░░░▓▓▓▓▓                    ░ ░   ▒         ..................................
.................................░░░░░░░░▒▒   ░░░░░ ░                  ▓▓▓▓▓▓░▓▓▓▓░░▓▓▓░░░░░░▓▓                    ░  ░ ░  ▒         ..................................
.................................░░░░░░░░▒    ░░░░░░░░░ ░                 ░▓░░▓▓▓▓▓░▓▓▓░░░░░                   ░ ░░ ░░ ░   ▒         ..................................
.................................░░░░░░░▒▒    ░░░░░░░   ░░                    ▓▓▓▓▓▓▓▓▓░░                   ░░    ░ ░░ ░    ▒        ..................................
.................................░░░░░░░▒▒    ░░░░░░░░░░                      ░▓▓▓▓▓▓▓░░░                     ░░░  ░  ░ ░   ▒        ..................................
.................................░░░░░░░ ▒    ░░░░░░                         ░░░▓▓▓░▓░░░░      ░                  ░ ░░ ░    ▒        ..................................
.................................░░░░░░░ ▒    ░░░░░░░     ▓▓        ▓  ░░ ░░░░░░░░░░░░░  ░   ░░  ▓        █▓       ░  ░ ░   ▒▒       ..................................
..................................░░░░░▒ ▒    ░░░░░░░░  ▓▓██  ▓  ██ ██▓  ▓ ░░░▓░  ░ ░ ░░░░  ▓   ██ ▓█  ▓  ██▓▓  ░░░░  ░ ░    ▒      ...................................
..................................░░░░░▒ ▒▒   ░░░░░░░░░  ▓██  ▓▓  ▓ ██▓  ▓░░░░▓▓░  ░░░░░░░░ ▓  ▓██ ▓   ▓  ██▓▓ ░░░░░░░ ░     ▒      ...................................
..................................░░░░░  ▒░   ░░░░░░░▓░░ ▓███  ▓▓▓▓ ███░  ░░░░▓▓░░░░░░░░░░    ░▓██  ▓▓▓  ███▓ ░░▓▓░░  ░    ▒ ▒      ...................................
...................................░░░░  ▒░    ░░░░▓▓▓▓▓▓░  ███    ██      ░░░░░▓▓▓▓▓░░░░░░░     ███   ████ ░░▓▓▓▓░░  ░    ▒ ▒      ...................................
...................................░░░░ ▒ ░▒    ░░▓▓▓▓▓▓▓▓▓▓ ██████  ▓▓▓░░ ░░░░▓▓▓▓▓▓░░░░░░░░░▓▓▓   █████  ▓▓▓▓▓▓▓░░░░    ▒▒ ▒      ...................................
...................................░░░░ ░ ░░     ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█░░░░░░░▓▓▓▓▓▓▓░░░░ ░░   ░░▓░▓▓░░░░░░░▓▓▓▓▓▓░░      ▒▒ ▒      ...................................
...................................░░░░ ░ ░░      ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██  ░░░░░░░▓▓▓▓▓▓▓░░░░  ░░░░░   ░░░░░░░░░▓▓▓▓▓░░ ░    ▒▒  ▒      ...................................
...................................░░░░▒░░▒░░      ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░▓▓▓▓▓▓▓▓░░░  ░░░░░░░░░░░░░░░░░░▓▓░░░░      ▒▒  ▒     ....................................
...................................░░░░▒░░ ░░       ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░▓▓▓▓▓▓▓▓▓░░░░  ░░░░░░░░░░░░░░░░░░░░░        ▒▒  ▒     ....................................
...................................░░░░░░░ ▒░▒       ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░▓▓▓░░   ░░░░░  ░░░░░░░░░░░░░░░░░░░░         ▒   ▒     ....................................
...................................░░░░░░░░░░░           ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓              ░    ░░░░░░░░░░░░░░░            ▒   ▒     ....................................
....................................░░░░░░░░░░░▒  ▒▒        ▓▓▓▓▓▓▓▓▓▓▓▓▓  ░░░░░░░░░░▒▒                         ▒▒▒▒▒   ▒    ▒    .....................................
....................................░░░░░░░░░░ ░▒ ▒▒▒░░░        ▓▓▓▓▓▓   ░░░░░░░░░░░░░▒▒▒      ▒▒▒▒▒░░░░▒▒    ▒▒▒▒▒▒▒  ▒▒    ▒    .....................................
....................................░░░░░░░░░░ ░░░ ▒▒▒░░░░░░          ░░░░░ ░░░░░░░░░░▒░▒     ▒▒▒▒▒▒░░░░░░▒▒▒▒▒░▒▒▒▒   ▒▒         .....................................
.....................................░░░░░░░░░░ ░░░░░  ▒▒░░░░░░░░░░░░░    ░░░░░░░░░  ▒░▒▒    ▒▒▒▒▒░░░░▒▒▒▒▒▒░░▒▒▒   ▒▒▒         ......................................
.....................................░░░░░░░░░░░░░░░░░░  ▒░░░░░░░░░░░   ░░░░░░░░░░░░░░   ▒   ▒▒▒▒▒▒▒░▒▒▒▒▒▒░░░░▒▒▒   ▒▒          ......................................
.....................................░░░░░░░░░░░ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░      ▒▒▒▒▒▒▒    ▒  ░░░▒▒▒▒  ▒▒▒          ......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ▒░▒▒▒ ▒▒▒    ▒░░░░░░░░░░▒   ▒▒▒▒      ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒  ░░▒▒▒▒▒▒░░░░░░░░░░░░░▒  ░▒▒▒▒       ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒ ▒▒░▒▒▒▒▒▒▒░░░░░░░░░░  ░░▒▒▒▒▒       ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒ ░▒▒▒▒▒▒▒▒▒░░▒░░░░░░ ░░▒▒▒▒▒▒      ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒░░▒░▒▒▒ ▒▒▒▒▒░░░░░░░░░▒▒▒▒▒        ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒░▒▒▒▒▒     ░░░░░░░░▒▒▒▒▒▒        ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒░░▒░▒▒▒▒▒▒  ▒░░░░░░░▒▒▒▒▒▒        ▒     .......................................
NINJA_EOF

    echo ""
    echo -e "                                    \033[1;35m「 天下布武！勝利を掴め！ 」\033[0m"
    echo ""
    echo -e "                               \033[0;36m[ASCII Art: syntax-samurai/ryu - CC0 1.0 Public Domain]\033[0m"
    echo ""

    echo "  CLI起動を待機中（最大30秒）..."

    # 将軍の起動を確認（最大30秒待機）
    for i in {1..30}; do
        if tmux capture-pane -t shogun:main -p | grep -Eq "bypass permissions|bypass approvals and sandbox"; then
            echo "  └─ 将軍CLIの起動確認完了（${i}秒）"
            break
        fi
        sleep 1
    done

    # 実行中モデル名をtmuxペイン変数へ同期（将軍含む）
    if bash "$SCRIPT_DIR/scripts/sync_pane_vars.sh" > /dev/null 2>&1; then
        log_info "  └─ tmux @model_name 同期完了（将軍含む）"
    else
        log_info "  └─ ⚠️ tmux @model_name 同期失敗（起動直後のため次周期で再同期）"
    fi

    # ═══════════════════════════════════════════════════════════════════
    # STEP 6.6: inbox_watcher起動（全エージェント）
    # ═══════════════════════════════════════════════════════════════════
    log_info "📬 メールボックス監視を起動中..."

    # ntfy_inbox 7日アーカイブ（watcher起動前に古メッセージを退避）
    bash "$SCRIPT_DIR/scripts/ntfy_inbox_archive.sh" || log_warn "ntfy_inbox_archive failed (non-fatal)"

    # inbox ディレクトリ初期化（シンボリックリンク先のLinux FSに作成）
    mkdir -p "$SCRIPT_DIR/logs"
    for agent in shogun $(get_all_agents); do
        [ -f "$SCRIPT_DIR/queue/inbox/${agent}.yaml" ] || echo "messages:" > "$SCRIPT_DIR/queue/inbox/${agent}.yaml"
    done

    # 既存のwatcherと孤児inotifywaitをkill
    pkill -f "inbox_watcher.sh" 2>/dev/null || true
    pkill -f "inotifywait.*queue/inbox" 2>/dev/null || true
    sleep 1

    # 将軍のwatcher（エスカレーション抑制 + タイムアウト無効化）
    _shogun_watcher_cli=$(tmux show-options -p -t "shogun:main" -v @agent_cli 2>/dev/null || echo "claude")
    nohup env ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 \
        bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" shogun "shogun:main" "$_shogun_watcher_cli" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_shogun.log" &
    disown

    # 家老のwatcher
    _karo_watcher_cli=$(tmux show-options -p -t "shogun:agents.${PANE_IDS[0]}" -v @agent_cli 2>/dev/null || echo "claude")
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" karo "shogun:agents.${PANE_IDS[0]}" "$_karo_watcher_cli" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_karo.log" &
    disown

    # 忍者・軍師のwatcher
    for i in $(seq 1 $NINJA_PANE_COUNT); do
        p=${PANE_IDS[$i]}
        ninja_name="${AGENT_IDS[$i]}"
        _ashi_watcher_cli=$(tmux show-options -p -t "shogun:agents.${p}" -v @agent_cli 2>/dev/null || echo "claude")
        nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "${ninja_name}" "shogun:agents.${p}" "$_ashi_watcher_cli" \
            &>> "$SCRIPT_DIR/logs/inbox_watcher_${ninja_name}.log" &
        disown
    done

    log_success "  └─ $((AGENT_COUNT + 1))エージェント分のinbox_watcher起動完了"

    # STEP 6.7 は廃止 — CLAUDE.md Session Start (step 1: tmux agent_id) で各自が自律的に
    # 自分のinstructions/*.mdを読み込む。検証済み (2026-02-08)。
    log_info "📜 指示書読み込みは各エージェントが自律実行（CLAUDE.md Session Start）"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6.8: ntfy入力リスナー起動
# ═══════════════════════════════════════════════════════════════════════════════
NTFY_TOPIC=$(grep 'ntfy_topic:' ./config/settings.yaml 2>/dev/null | awk '{print $2}' | tr -d '"')
if [ -n "$NTFY_TOPIC" ]; then
    pkill -f "ntfy_listener.sh" 2>/dev/null || true
    [ ! -f ./queue/ntfy_inbox.yaml ] && echo "inbox:" > ./queue/ntfy_inbox.yaml
    nohup bash "$SCRIPT_DIR/scripts/ntfy_listener.sh" &>/dev/null &
    disown
    log_info "📱 ntfy入力リスナー起動 (topic: $NTFY_TOPIC)"

    # ntfyスモークテスト: 出陣時に通知が実際に送信できることを確認
    # curlの終了コードで判定（ネットワーク到達性 + ntfy.shの引数処理）
    if bash "$SCRIPT_DIR/scripts/ntfy.sh" "🏯 出陣！将軍システム起動完了。" 2>/dev/null; then
        log_info "📱 ntfyスモークテスト: ✅ 送信成功"
    else
        log_warn "📱 ntfyスモークテスト: ❌ 送信失敗 — ntfy.shまたはネットワークを確認"
    fi
else
    log_info "📱 ntfy未設定のためリスナーはスキップ"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6.9: Gist同期ウォッチャー起動
# ═══════════════════════════════════════════════════════════════════════════════
GIST_ID=$(grep 'gist_id:' ./config/settings.yaml 2>/dev/null | awk '{print $2}' | tr -d '"')
if [ -z "$GIST_ID" ]; then
    # settings.yamlになければデフォルト値
    GIST_ID="6eb495d917fb00ba4d4333c237a4ee0c"
fi
pkill -f "gist_sync.sh" 2>/dev/null || true
nohup bash "$SCRIPT_DIR/scripts/gist_sync.sh" "$GIST_ID" \
    &>> "$SCRIPT_DIR/logs/gist_sync.log" &
disown
log_info "📊 Gist同期ウォッチャー起動 (gist: $GIST_ID)"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6.10: Usage statusbarデーモン起動（5h/7d利用率表示）
# ═══════════════════════════════════════════════════════════════════════════════
if [ -f "$SCRIPT_DIR/scripts/usage_statusbar_loop.sh" ]; then
    pkill -f "usage_statusbar_loop.sh" 2>/dev/null || true
    nohup bash "$SCRIPT_DIR/scripts/usage_statusbar_loop.sh" >> "$SCRIPT_DIR/logs/usage_statusbar_loop.log" 2>&1 &
    disown
    log_info "📊 Usage statusbarデーモン起動 (5h/7d)"
else
    log_info "⚠️ scripts/usage_statusbar_loop.sh が見つかりません（スキップ）"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6.11: 忍者監視デーモン起動（コンテキスト%更新）
# ═══════════════════════════════════════════════════════════════════════════════
if [ -f "$SCRIPT_DIR/scripts/ninja_monitor.sh" ]; then
    pkill -f "ninja_monitor.sh" 2>/dev/null || true
    nohup bash "$SCRIPT_DIR/scripts/ninja_monitor.sh" >> "$SCRIPT_DIR/logs/ninja_monitor.log" 2>&1 &
    disown
    log_info "👁️ 忍者監視デーモン起動 (context%更新)"
else
    log_info "⚠️ scripts/ninja_monitor.sh が見つかりません（スキップ）"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: 環境確認・完了メッセージ
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🔍 陣容を確認中..."
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📺 Tmux陣容 (Sessions)                                  │"
echo "  └──────────────────────────────────────────────────────────┘"
tmux list-sessions | sed 's/^/     /'
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📋 布陣図 (Formation)                                   │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "     【shogunセッション】単一セッション構成"
echo ""
echo "     Window 0: main（将軍の本陣）"
echo "     ┌─────────────────────────────┐"
echo "     │  将軍 (SHOGUN)              │  ← 総大将・プロジェクト統括"
echo "     └─────────────────────────────┘"
echo ""
echo "     Window 1: agents（3列レイアウト）"
# 列情報を動的に取得して3列布陣図を表示
_max_rows=$_COL1_N
(( _COL2_N > _max_rows )) && _max_rows=$_COL2_N
(( _COL3_N > _max_rows )) && _max_rows=$_COL3_N
echo "     ┌──────────┬──────────┬──────────┐"
for ((_fr=0; _fr<_max_rows; _fr++)); do
    _c1=""; _c2=""; _c3=""
    (( _fr < _COL1_N )) && _c1="${_COL1[$_fr]}"
    (( _fr < _COL2_N )) && _c2="${_COL2[$_fr]}"
    (( _fr < _COL3_N )) && _c3="${_COL3[$_fr]}"
    printf "     │ %-8s │ %-8s │ %-8s │\n" "$_c1" "$_c2" "$_c3"
    if (( _fr < _max_rows - 1 )); then
        echo "     ├──────────┼──────────┼──────────┤"
    fi
done
echo "     └──────────┴──────────┴──────────┘"
echo ""

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║  🏯 出陣準備完了！天下布武！                              ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

if [ "$SETUP_ONLY" = true ]; then
    echo "  ⚠️  セットアップのみモード: Claude Codeは未起動です"
    echo ""
    echo "  手動でClaude Codeを起動するには:"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  # 将軍を召喚                                            │"
    echo "  │  tmux send-keys -t shogun:main \\                     │"
    echo "  │    'claude --dangerously-skip-permissions' Enter         │"
    echo "  │                                                          │"
    echo "  │  # 家老・忍者を一斉召喚                                  │"
    echo "  │  for p in ${PANE_IDS[*]}; do                              │"
    echo "  │      tmux send-keys -t shogun:agents.\$p \\            │"
    echo "  │      'claude --dangerously-skip-permissions' Enter       │"
    echo "  │  done                                                    │"
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""
fi

echo "  次のステップ:"
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  本陣にアタッチして命令を開始:                            │"
echo "  │     tmux attach-session -t shogun                    │"
echo "  │                                                          │"
echo "  │  ウィンドウ切替: Ctrl+A → 0 (将軍) / 1 (忍者)           │"
echo "  │                                                          │"
echo "  │  ※ 各エージェントは指示書を読み込み済み。                 │"
echo "  │    すぐに命令を開始できます。                             │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "  ════════════════════════════════════════════════════════════"
echo "   天下布武！勝利を掴め！ (Tenka Fubu! Seize victory!)"
echo "  ════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: Windows Terminal でタブを開く（-t オプション時のみ）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$OPEN_TERMINAL" = true ]; then
    log_info "📺 Windows Terminal でタブを展開中..."

    # Windows Terminal が利用可能か確認
    if command -v wt.exe &> /dev/null; then
        wt.exe -w 0 new-tab wsl.exe -e bash -c "tmux attach-session -t shogun"
        log_success "  └─ ターミナルタブ展開完了"
    else
        log_info "  └─ wt.exe が見つかりません。手動でアタッチしてください。"
    fi
    echo ""
fi
