#!/usr/bin/env python3
# semantic-links: [[ゲート迂回防止]]
"""Guard14 DB direct connection trust classifier.

cmd_karo_hotfix_guard14_db_trust_boundary_202607120854: 語彙一律BLOCK(旧Guard14)を
DB操作意図(not_connection/connection)と接続先信頼境界(local_ephemeral/untrusted)の
構造判定へ置換する単一の共通ヘルパー。.claude/hooks/pre-bash-combined.sh から呼ばれ、
テストからも同じ関数を直接呼び出せる(実行コマンドをCOMMAND環境変数または引数で渡す)。

判定は3値: "not_connection" / "connection:local_ephemeral" / "connection:untrusted"。
fail-closed: DSN未抽出・変数展開・parse失敗・空authority(query override無し)は全て
untrusted (呼び出し側でBLOCK)。

review_correction 2026-07-12 09:05/09:12/09:17/09:22 (karo) 対応:
- command全文への裸文字列一致("localhost"等)はしない。接続runtimeを含むsegment自身の
  トークンから host=X / postgres(ql)://[user@]HOST[?query] / :memory: というDSN構造で
  のみ値を抽出し、その値自体を判定する。他segment(echo等)の文字列は一切参照しない。
- セグメント分割は shlex.shlex(posix=True, punctuation_chars=";&|") でquote-aware かつ
  空白なし演算子("cmd1"&&echo 等)にも対応したlexerでtoken化してから演算子トークン
  (&&/||/;/|/単独&のバックグラウンド演算子も含む)で区切る。quote内の演算子は1トークン
  へ吸収されるため誤分割しない。
- host候補の空文字列は「未解決」として untrusted 扱いする(host=空値、URLのauthority欠落
  かつqueryにhost override無し、のいずれも空文字列を許可しない)。URLはurllib.parseで
  hostname/queryを構造的に解析し、authority空+query内host=/pathのUnix socket指定のみを
  localと判定する。
- db-check/check_pf_config の免除は command 全文への部分文字列一致(bash側)ではなく、
  python系segmentの「実行スクリプトoperand」(先頭のcmd0/flag群の直後にある最初の非flag
  引数。-c指定時はinline codeなので対象外)がcheck_pf_config.pyという実在スクリプトパス
  である場合のみ、そのsegmentを構造的に免除する。segment内の任意位置のtoken一致では免除
  しない(remote接続コマンドの末尾に単なる引数としてcheck_pf_config.pyを足すだけの
  なりすまし免除、および `; echo db-check` のような自由文字列免除の両方を防ぐ)。
- basename一致だけでは同名の別ファイル(例: /tmp/check_pf_config.py)でも免除されてしまう
  (review_correction 09:24, karo)。実行operandのrealpathを、config/projects.yaml(SSOT)の
  dm-signal.path から導出した正規check_pf_config.pyのrealpathと同一性確認(os.path.samefile,
  両方の実在確認込み)した場合のみ免除する。文字列一致→位置限定→同一性確認まで閉じる。
- pre-bash-combined.sh冒頭のawk抽出はJSON文字列の\"エスケープを"正しく処理"するが、
  それは早期break回避のためであって実際のunescapeはしない。結果、$commandには
  Python -c 引数のバックスラッシュ+quoteがそのまま残り、classify()内のshlex token化が
  quote境界を誤認識してhost候補を別segmentへ分断する(review_correction 09:30, karo)。
  classifier側でこの成果物にregexパッチを当てるのではなく、フック呼び出し元がHOOK
  payload全体(生JSON)をHOOK_PAYLOAD_JSON環境変数で渡し、本entrypointが
  json.loads(payload)["tool_input"]["command"]から正規のcommand文字列を復元してから
  classify()へ渡す。classify(command)自体は常に生のcommand文字列を受け取る契約を保つ
  (単体テストはclassify(raw command)を直接叩ける)。
- 入口の語彙gate(psycopg2/DATABASE_URL/create_db_engine等)を廃止し、Guard14は全Bash
  commandを無条件でclassify()へ渡す(review_correction 09:33/09:36, karo)。これにより
  「python/pytestというruntimeを起動した」だけで即connection扱いにすると、DBと無関係な
  benign pythonまでfail-closedでBLOCKされてしまう新たな回帰が発生した。runtimeが
  python/pytest系の場合は、そのsegment自身にDBマーカーが実在する場合のみconnection
  intentとみなす。psqlは常にDB接続クライアントそのものなので無条件でconnection intent
  とし、-h/--host ネイティブフラグもDSN候補として構造抽出する。
- DBマーカーは特定client名の列挙(psycopg2/create_db_engine等)ではなく、psycopg v3/
  asyncpg/pg8000等の異種clientを横断して成立する構造的signalカテゴリで判定する
  (review_correction 09:45, karo): DSN URLスキーム(postgres(ql)://)、DB系env/DSN変数名
  (大文字+_URL/_DSNパターン)、接続API呼出の形(`.connect(` / `create_*engine(`)、host指定
  (host=)、in-memoryマーカー(:memory:)。個別client名を追加して育てる設計にしない。

cmd_karo_hotfix_guard14_env_db_intent_rc5_202607122241 (karo反例) 対応:
- .envクレデンシャル併存判定(_shell_segments_are_bounded)がREAD_ONLY_SHELL_CMDSを
  「command名一致だけ」でALLOWしていたため、find -exec/-execdir/-ok/-okdir、
  rg --pre/--pre-glob、sedのe(shell実行)/w(ファイル書込)/-i(in-place書込)/-f(内容不明の
  外部script)という「read-onlyに見えて実行・書込能力を持つoption」がそのまま素通り
  していた。command0だけでなくoption/script内容の実行・書込能力を検証する
  _segment_is_readonly_safe() へ置換し、未知の能力(-f等)はfail-closedでBLOCKする。
- 同時に、pipe(|)を一律拒否していたため cat .env | grep SECRET のような安全な
  read-onlyパイプラインまで誤BLOCKしていた。pipeはsegment境界(既存の_split_into_segments
  が処理済み)として扱い、全segmentがsafeならALLOWする。command substitution($()/
  backtick)とprocess substitution(<(...)/>(...))は引き続き生コマンド文字列で無条件BLOCK。
"""
from __future__ import annotations

import json
import os
import re
import shlex
import ast

# review_correction(2026-07-12 09:36, karo): yamlはcheck_pf_config.py免除判定時にしか
# 不要なのに、module冒頭でimportすると全Bash呼び出し(not_connection経路含む)がyaml
# import分のコスト(実測+15ms)を常に払う。実際に免除判定へ入る時だけ遅延importする。

CONNECTION_CMDS = {
    "python", "python3", "python.exe", "pytest", "py.test",
    "psql", "uvicorn", "gunicorn", "node", "ipython",
}
OPERATORS = {"&&", "||", ";", "|", "&"}

# These scripts are trusted capability boundaries, not free-text exceptions.
# The executed operand must still resolve to the canonical file below.
EXEMPT_SCRIPT_BASENAMES = {
    "check_pf_config.py",
    "db_capability_launcher.py",
    "dm_signal_adapters.py",
}

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


def _projects_config() -> dict:
    """Load configured project roots from the production SSOT (test override is Bats-only)."""
    try:
        import yaml
    except ImportError:
        try:
            import site
            site.main()
            import yaml
        except ImportError:  # pragma: no cover - PyYAML欠如環境ではfail-closed
            return {}
    if os.environ.get("BATS_TEST_FILENAME"):
        projects_yaml = os.environ.get(
            "GUARD14_PROJECTS_YAML", os.path.join(_REPO_ROOT, "config", "projects.yaml")
        )
    else:
        projects_yaml = os.path.join(_REPO_ROOT, "config", "projects.yaml")
    try:
        with open(projects_yaml, encoding="utf-8") as handle:
            data = yaml.safe_load(handle) or {}
    except (OSError, yaml.YAMLError):
        return {}
    return data if isinstance(data, dict) else {}


def _configured_project_roots() -> list[str]:
    roots: list[str] = []
    for project in _projects_config().get("projects") or []:
        if not isinstance(project, dict):
            continue
        path = project.get("path")
        if isinstance(path, str) and os.path.isabs(path):
            resolved = os.path.realpath(path)
            if os.path.isdir(resolved):
                roots.append(resolved)
    return roots


def _canonical_exempt_script_path(basename: str) -> str | None:
    if basename == "db_capability_launcher.py":
        return os.path.realpath(os.path.join(_REPO_ROOT, "scripts", basename))
    if basename == "dm_signal_adapters.py":
        return os.path.realpath(os.path.join(_REPO_ROOT, "scripts", "cdp", basename))
    if basename != "check_pf_config.py":
        return None
    # config/projects.yaml (SSOT) の dm-signal.path から正規check_pf_config.pyパスを導出する。
    # ハードコードしない(Guard18: 操作的オントロジー — PJパス直書き禁止)。
    # hookは python3 -S (site初期化skip、実測-6ms/呼び出し)で起動するため、通常経路では
    # site-packages がsys.pathに無くyamlをimportできない。ここ(免除判定の稀な経路)でのみ
    # site.main()でsite-packagesを復元してからimportする。
    for proj in _projects_config().get("projects") or []:
        if not isinstance(proj, dict):
            continue
        if proj.get("id") == "dm-signal":
            base = proj.get("path")
            if not base:
                return None
            return os.path.realpath(os.path.join(base, "scripts", "check_pf_config.py"))
    return None

HOST_KV_RE = re.compile(r"host\s*=\s*['\"]?([A-Za-z0-9_.:/-]*)")
DSN_URL_RE = re.compile(r"(?:postgres|postgresql)://[^\s'\"]*")

LOCAL_HOST_VALUES = {"localhost", "127.0.0.1", "::1"}

# review_correction(2026-07-12 09:39/09:45/09:51, karo): 実在するDBマーカーを1つも
# 含まないsegmentを"python/pytestを起動しただけ"でconnection扱いすると、DBと無関係な
# benign python/pytestが全てfail-closedでBLOCKされる。マーカーが実在する場合のみ
# connection intentとみなす。マーカーはpsycopg2/create_db_engineのような特定client名の
# 列挙ではなく、psycopg v3/asyncpg/pg8000等の異種clientを横断して成立する構造的signalで
# 判定する: (1) DB系env/DSN変数名(DB/DATABASE/POSTGRES/PGというDB意味トークンを含む
# 大文字識別子+_URL/_DSN。単なる_URL/_DSN suffixだけではAPI_URL/SENTRY_DSN等の無関係な
# env varまで拾ってしまうため、DB意味トークンを要求する) (2) 接続API呼出の形 `.connect(`
# (3) engine factory呼出の形 `create_*engine(` (4) host指定(host=) (5) in-memory(:memory:)
# (6) postgres(ql)://スキームは別途DSN_URL_REで判定済み。
# .env credential sourceは接続先を隠すため原則fail-closed。ただしcommand全体にDB固有
# markerが0件で、明示HTTP client callがある場合だけ非DB資格情報として除外する。
DB_ENV_VAR_RE = re.compile(r"\b[A-Z][A-Z0-9_]*(?:DB|DATABASE|POSTGRES|PG)[A-Z0-9_]*_(?:URL|DSN)\b")
CONNECT_CALL_RE = re.compile(r"\.connect\s*\(")
CREATE_ENGINE_RE = re.compile(r"create_[A-Za-z_]*engine\s*\(")
ENV_CREDENTIAL_FILE_RE = re.compile(r"(?:^|[^A-Za-z0-9_])\.env(?:\.[A-Za-z0-9_]+)?\b")
CREDENTIAL_FILE_FLAG_RE = re.compile(r"^--credential-file(?:=.*)?$")
HTTP_CLIENT_CALL_RE = re.compile(
    r"\b(?:requests|httpx)\.(?:get|post|put|patch|delete|request)\s*\("
    r"|\burllib\.request\.urlopen\s*\("
)
CURL_CMD_RE = re.compile(r"^(?:curl|curl\.exe)$")
HTTP_MODULES = {"requests", "httpx", "urllib", "urllib.request"}
WEBSOCKET_MODULES = {"websocket", "websockets"}
SAFE_STDLIB_MODULES = {
    "json", "os", "pathlib", "re", "time", "datetime", "base64", "hashlib",
    "typing", "collections", "urllib.parse",
}
SAFE_CREDENTIAL_MODULES = {"dotenv"}
ESCAPE_MODULES = {"socket", "subprocess", "ctypes", "importlib"}
ESCAPE_CALLS = {"eval", "exec", "compile", "__import__"}
READ_ONLY_SHELL_CMDS = {"rg", "grep", "sed", "cat", "head", "tail", "cut", "wc", "find"}
# gitはVCSツールでありDB接続能力なし。commit message内の.envテキストはファイルアクセスではない。
# 2026-07-15将軍実証: git commit -m "...text with .env..." がconnection:untrustedに誤判定。
SAFE_NON_DB_CMDS = {
    "git", "echo", "printf", "date", "mkdir", "cp", "mv", "ls", "rm", "touch", "chmod", "tmux", "ntfy",
    "tr", "sort", "uniq", "awk", "tee", "basename", "dirname", "realpath", "readlink", "stat",
    "diff", "comm", "paste", "column", "fold", "rev", "od", "xxd", "sha256sum", "md5sum",
    "true", "false", "test", "sleep", "kill", "pgrep", "pkill", "id", "whoami", "hostname",
}
ENV_SETUP_SHELL_CMDS = {"source", ".", "export"}
SAFE_OS_CALLS = {"getenv"}
# python3 -m <module> で起動される安全なstdlib module。DB接続能力なし。
SAFE_PYTHON_M_MODULES = {"json.tool", "json", "base64", "pprint", "http.server"}

# review_correction(2026-07-12 22:xx, karo RC5): READ_ONLY_SHELL_CMDS が cmd0 の一致だけで
# 全option/scriptをALLOWしていたため、find -exec系・rg --pre系・sedのe/w系という「read-only
# に見えて実際は外部コマンド実行・任意ファイル書込を行えるoption」がそのまま素通りしていた
# (karo反例)。command名一致だけのALLOWを禁止し、cmd0+引数(option/script内容)の実行・書込
# 能力を個別に検証してから安全と判定する。未知の能力を持ち得る場合(sedの-f外部scriptファイル
# 等、内容を検証できないもの)はfail-closedでBLOCKする。
FIND_EXEC_FLAGS = {"-exec", "-execdir", "-ok", "-okdir"}
RG_PRE_FLAG_RE = re.compile(r"^--pre(?:-glob)?(?:=.*)?$")
SED_FILE_FLAG_RE = re.compile(r"^(?:-f|--file)(?:=.*)?$")
SED_INPLACE_FLAG_RE = re.compile(r"^(?:-i|--in-place)(?:=.*|[^A-Za-z0-9_].*)?$")

# sedのe(shell実行)/w(ファイル書込)commandは、standalone command('[addr]e'/'[addr]w file')
# とs///置換の末尾flag('s/re/repl/e'や's/re/repl/w file')の2形態で現れる。delimiterは'/'に
# 限らず任意の非英数字1文字が使えるため、s(.)...\1...\1(flags) の後方参照でdelimiterを揃えて
# 抽出する。addressはlineno/$/ステップ(~)/正規表現(/pattern/)/範囲(addr1,addr2)を許容する。
_SED_ADDR_ATOM = r"(?:\$|[0-9]+|/(?:\\.|[^/\\])*/)"
_SED_ADDR = (
    r"!?\s*" + _SED_ADDR_ATOM + r"(?:\s*~\s*[0-9]+|\s*,\s*!?" + _SED_ADDR_ATOM + r")?" + r"\s*!?"
)
SED_STANDALONE_EXEC_RE = re.compile(r"(?:^|[;\n}])\s*(?:" + _SED_ADDR + r")?\s*[ew](?:\s|;|$)")
SED_SUBST_FLAG_RE = re.compile(r"s(.)(?:\\.|[^\\\n])*?\1(?:\\.|[^\\\n])*?\1([a-zA-Z0-9]*)")


def _sed_script_is_dangerous(script: str) -> bool:
    if SED_STANDALONE_EXEC_RE.search(script):
        return True
    for m in SED_SUBST_FLAG_RE.finditer(script):
        flags = m.group(2)
        if "e" in flags or "w" in flags:
            return True
    return False


def _find_segment_is_dangerous(tokens: list[str]) -> bool:
    return any(tok in FIND_EXEC_FLAGS for tok in tokens[1:])


def _rg_segment_is_dangerous(tokens: list[str]) -> bool:
    return any(RG_PRE_FLAG_RE.match(tok) for tok in tokens[1:])


def _sed_segment_is_dangerous(tokens: list[str]) -> bool:
    rest = tokens[1:]
    scripts: list[str] = []
    has_unknown_capability = False
    positional_script_claimed = False
    i = 0
    while i < len(rest):
        tok = rest[i]
        if tok in ("-e", "--expression"):
            if i + 1 < len(rest):
                scripts.append(rest[i + 1])
                i += 2
            else:
                i += 1
            continue
        if tok.startswith("--expression="):
            scripts.append(tok.split("=", 1)[1])
            i += 1
            continue
        if SED_FILE_FLAG_RE.match(tok):
            # -f/--file は外部scriptファイルの内容をこのcommand行から検証できないため
            # fail-closedでdangerous扱いする。
            has_unknown_capability = True
            i += 1
            continue
        if SED_INPLACE_FLAG_RE.match(tok):
            # -i/--in-place はそれ自体が「読み取り専用」の逆(直接書込)なので常にdangerous。
            has_unknown_capability = True
            i += 1
            continue
        if tok.startswith("-"):
            i += 1
            continue
        if not scripts and not positional_script_claimed:
            # 最初の非flag引数のみがscript本体。以降の非flag引数は入力ファイル名。
            scripts.append(tok)
            positional_script_claimed = True
        i += 1
    if has_unknown_capability:
        return True
    return any(_sed_script_is_dangerous(s) for s in scripts)


def _segment_is_readonly_safe(cmd0: str, tokens: list[str]) -> bool:
    if cmd0 == "find":
        return not _find_segment_is_dangerous(tokens)
    if cmd0 == "rg":
        return not _rg_segment_is_dangerous(tokens)
    if cmd0 == "sed":
        return not _sed_segment_is_dangerous(tokens)
    return True


def _tokenize(command: str) -> list[str]:
    # review_correction(2026-07-12 09:17, karo): shlex.split既定は空白のない演算子
    # ("cmd1"&&echo 等)を直前/直後のトークンへ融合し、演算子境界を見失う。
    # punctuation_chars指定のquote-aware lexerを使い、空白有無に関わらず
    # ;/&/| を独立トークンとして切り出す。
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|")
    lexer.whitespace_split = True
    return list(lexer)


def _strip_env_prefix(tokens: list[str]) -> list[str]:
    i = 0
    while i < len(tokens) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[i]):
        i += 1
    return tokens[i:]


def _segment_cmd0(tokens: list[str]) -> str:
    tokens = _strip_env_prefix(tokens)
    while tokens and os.path.basename(tokens[0]) == "timeout":
        tokens = tokens[1:]
        if tokens and re.match(r"^[0-9.]+[smhd]?$", tokens[0]):
            tokens = tokens[1:]
        tokens = _strip_env_prefix(tokens)
    if not tokens:
        return ""
    return os.path.basename(tokens[0])


def _segment_has_db_marker(tokens: list[str]) -> bool:
    text = " ".join(tokens)
    if ":memory:" in text:
        return True
    if HOST_KV_RE.search(text):
        return True
    if DSN_URL_RE.search(text):
        return True
    if DB_ENV_VAR_RE.search(text):
        return True
    if CONNECT_CALL_RE.search(text):
        # websockets.connect(...) shares the generic DB-driver spelling.  Exclude
        # it only after the Python AST capability proof binds that exact call to
        # a literal wss:// first argument; dynamic/aliased opaque calls remain DB
        # candidates and fail closed.
        if _python_inline_code(tokens) is not None and _python_http_only_capability(tokens):
            return False
        return True
    if CREATE_ENGINE_RE.search(text):
        return True
    return False


def _is_connection_segment(tokens: list[str]) -> bool:
    cmd0 = _segment_cmd0(tokens)
    if cmd0 == "psql":
        return True  # psqlはDB接続クライアントそのもの。マーカー不問で常にconnection intent
    if cmd0 in CONNECTION_CMDS or cmd0.endswith(".py"):
        # python/pytest等の汎用runtimeは、そのsegment自身にDBマーカーが実在する場合のみ
        # connection intentとみなす(review_correction 09:39, karo: benign python/pytest回帰)
        return _segment_has_db_marker(tokens)
    return False


def _segment_has_env_credential_source(tokens: list[str]) -> bool:
    if any(CREDENTIAL_FILE_FLAG_RE.match(token) for token in tokens):
        return True
    if ENV_CREDENTIAL_FILE_RE.search(" ".join(tokens)) is None:
        return False

    # A dot-env spelling is a credential source only when the command can use it
    # as one.  VCS/message commands carry arbitrary prose, and a non-inline shell
    # script receives tokens after its script operand as inert argv.  Treating
    # those argument strings as file reads made inbox notifications and commit
    # messages fail closed despite having no DB or credential capability.
    cmd0 = _segment_cmd0(tokens)
    if cmd0 in SAFE_NON_DB_CMDS:
        return False
    stripped = _strip_env_prefix(tokens)
    if cmd0 in {"bash", "sh"} and "-c" not in stripped:
        rest = stripped[1:]
        script_index = next((i for i, token in enumerate(rest) if not token.startswith("-")), None)
        if script_index is not None:
            script = rest[script_index]
            if ENV_CREDENTIAL_FILE_RE.search(script) is None:
                return False
    return True


def _segment_has_explicit_http_call(tokens: list[str]) -> bool:
    return (
        HTTP_CLIENT_CALL_RE.search(" ".join(tokens)) is not None
        or CURL_CMD_RE.match(_segment_cmd0(tokens)) is not None
    )


def _python_inline_code(tokens: list[str]) -> str | None:
    stripped = _strip_env_prefix(tokens)
    if not stripped or os.path.basename(stripped[0]) not in {"python", "python3", "python.exe"}:
        return None
    try:
        index = stripped.index("-c")
    except ValueError:
        return None
    return stripped[index + 1] if index + 1 < len(stripped) else ""


PYTHON_HEREDOC_NO_ARG_HEADER_RE = re.compile(
    r"^(?:(?:[A-Za-z_][A-Za-z0-9_]*)=\S+\s+)*"
    r"(?:python|python3|python\.exe)(?:\s+-)?\s+<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1$"
)
PYTHON_HEREDOC_ARG_HEADER_RE = re.compile(
    r"^(?:(?:[A-Za-z_][A-Za-z0-9_]*)=\S+\s+)*"
    r"(?:python|python3|python\.exe)\s+-\s+(\S+)\s+<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2$"
)


def _python_heredoc_parts(command: str) -> tuple[str, str | None] | None:
    """Extract code only from a standalone, unindented Python heredoc invocation."""
    lines = command.splitlines()
    if len(lines) < 3:
        return None
    header_line = lines[0].strip()
    arg_header = PYTHON_HEREDOC_ARG_HEADER_RE.fullmatch(header_line)
    no_arg_header = PYTHON_HEREDOC_NO_ARG_HEADER_RE.fullmatch(header_line)
    header = arg_header or no_arg_header
    if header is None:
        return None
    tag = header.group(3) if arg_header else header.group(2)
    if lines[-1].strip() != tag:
        return None
    argv = arg_header.group(1) if arg_header else None
    return "\n".join(lines[1:-1]), argv


def _python_heredoc_code(command: str) -> str | None:
    parts = _python_heredoc_parts(command)
    return parts[0] if parts is not None else None


def _readonly_sqlite_uri_is_confined(value: str) -> bool:
    """Prove a literal SQLite file URI is read-only and resolves inside a configured project."""
    from urllib.parse import parse_qs, unquote, urlsplit

    try:
        parts = urlsplit(value)
        query = parse_qs(parts.query, keep_blank_values=True, strict_parsing=True)
    except ValueError:
        return False
    if parts.scheme != "file" or parts.netloc or parts.fragment:
        return False
    if set(query) - {"mode", "immutable", "cache"}:
        return False
    if query.get("mode") != ["ro"]:
        return False
    if "immutable" in query and query["immutable"] != ["1"]:
        return False
    if "cache" in query and query["cache"] not in (["private"], ["shared"]):
        return False

    path = unquote(parts.path)
    if not path or "\x00" in path or not os.path.isabs(path):
        return False
    resolved = os.path.realpath(path)
    if not os.path.isfile(resolved):
        return False
    for root in _configured_project_roots():
        try:
            if os.path.commonpath((root, resolved)) == root:
                return True
        except ValueError:
            continue
    return False


def _python_readonly_sqlite_capability(tokens: list[str]) -> bool:
    """Prove every connect call in Python -c is an explicit confined SQLite read-only URI."""
    code = _python_inline_code(tokens)
    if code is None:
        return False
    # A segment that mixes the bounded SQLite call with any other DB-intent
    # category must fall back to the generic fail-closed classifier.  Otherwise
    # one valid SQLite call could camouflage a remote engine/DSN in the same -c.
    if (
        DSN_URL_RE.search(code)
        or DB_ENV_VAR_RE.search(code)
        or CREATE_ENGINE_RE.search(code)
        or HOST_KV_RE.search(code)
        or ":memory:" in code
    ):
        return False
    try:
        tree = ast.parse(code)
    except (SyntaxError, ValueError):
        return False

    module_aliases: set[str] = set()
    connect_aliases: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "sqlite3":
                    module_aliases.add(alias.asname or "sqlite3")
        elif isinstance(node, ast.ImportFrom) and node.module == "sqlite3":
            for alias in node.names:
                if alias.name == "connect":
                    connect_aliases.add(alias.asname or "connect")

    protected_names = module_aliases | connect_aliases
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign, ast.NamedExpr)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(isinstance(target, ast.Name) and target.id in protected_names for target in targets):
                return False

    saw_sqlite_connect = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        is_sqlite_connect = False
        if isinstance(node.func, ast.Attribute) and node.func.attr == "connect":
            if not isinstance(node.func.value, ast.Name) or node.func.value.id not in module_aliases:
                return False
            is_sqlite_connect = True
        elif isinstance(node.func, ast.Name) and node.func.id in connect_aliases:
            is_sqlite_connect = True
        if not is_sqlite_connect:
            continue

        if any(keyword.arg is None for keyword in node.keywords):
            return False
        database = node.args[0] if node.args else next(
            (keyword.value for keyword in node.keywords if keyword.arg == "database"), None
        )
        uri_flag = next((keyword.value for keyword in node.keywords if keyword.arg == "uri"), None)
        if not (
            isinstance(database, ast.Constant)
            and isinstance(database.value, str)
            and isinstance(uri_flag, ast.Constant)
            and uri_flag.value is True
            and _readonly_sqlite_uri_is_confined(database.value)
        ):
            return False
        saw_sqlite_connect = True
    return saw_sqlite_connect


def _python_readonly_sqlite_heredoc_capability(command: str) -> bool:
    """Apply the -c AST proof to a standalone Python heredoc body."""
    code = _python_heredoc_code(command)
    if code is None:
        return False
    return _python_readonly_sqlite_capability(["python3", "-c", code])


def _literal_project_file(value: str) -> bool:
    """Prove a shell-header argument is a literal existing file inside a project root."""
    if (
        not value
        or not os.path.isabs(value)
        or any(marker in value for marker in ("$", "`", "*", "?", ";", "|", "&", "<", ">"))
    ):
        return False
    resolved = os.path.realpath(value)
    if not os.path.isfile(resolved):
        return False
    for root in _configured_project_roots():
        try:
            if os.path.commonpath((root, resolved)) == root:
                return True
        except ValueError:
            continue
    return False


def _python_readonly_sqlite_argv_heredoc_capability(command: str) -> bool:
    """Rewrite one proven argv[1] URI and reuse the established Python AST proof."""
    parts = _python_heredoc_parts(command)
    if parts is None or parts[1] is None or not _literal_project_file(parts[1]):
        return False
    code = parts[0]
    try:
        tree = ast.parse(code)
    except (SyntaxError, ValueError):
        return False

    literal_uri = f"file:{parts[1]}?mode=ro"
    replaced = 0

    class _ArgvUriRewriter(ast.NodeTransformer):
        def visit_Call(self, node: ast.Call) -> ast.AST:
            nonlocal replaced
            if not (
                isinstance(node.func, ast.Attribute)
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id == "sqlite3"
                and node.func.attr == "connect"
                and node.args
            ):
                return self.generic_visit(node)
            database = node.args[0]
            if not isinstance(database, ast.JoinedStr) or len(database.values) != 3:
                return self.generic_visit(node)
            prefix, dynamic, suffix = database.values
            if not (
                isinstance(prefix, ast.Constant)
                and prefix.value == "file:"
                and isinstance(dynamic, ast.FormattedValue)
                and dynamic.conversion == -1
                and dynamic.format_spec is None
                and isinstance(dynamic.value, ast.Subscript)
                and isinstance(dynamic.value.value, ast.Attribute)
                and isinstance(dynamic.value.value.value, ast.Name)
                and dynamic.value.value.value.id == "sys"
                and dynamic.value.value.attr == "argv"
                and isinstance(dynamic.value.slice, ast.Constant)
                and dynamic.value.slice.value == 1
                and isinstance(suffix, ast.Constant)
                and suffix.value == "?mode=ro"
            ):
                return self.generic_visit(node)
            node.args[0] = ast.copy_location(ast.Constant(value=literal_uri), database)
            replaced += 1
            return self.generic_visit(node)

    tree = _ArgvUriRewriter().visit(tree)
    ast.fix_missing_locations(tree)
    if replaced != 1:
        return False
    try:
        rewritten = ast.unparse(tree)
    except (AttributeError, ValueError):
        return False
    return _python_readonly_sqlite_capability(["python3", "-c", rewritten])


def _python_http_only_capability(tokens: list[str]) -> bool:
    """Prove Python -c has only ordinary data processing plus explicit non-DB network capability."""
    code = _python_inline_code(tokens)
    if code is None:
        return False
    try:
        tree = ast.parse(code)
    except (SyntaxError, ValueError):
        return False
    saw_network = False
    websocket_module_aliases = {"websocket": "websocket", "websockets": "websockets"}
    websocket_call_aliases: dict[str, str] = {}
    for import_node in ast.walk(tree):
        if isinstance(import_node, ast.Import):
            for alias in import_node.names:
                if alias.name in WEBSOCKET_MODULES:
                    websocket_module_aliases[alias.asname or alias.name] = alias.name
        elif isinstance(import_node, ast.ImportFrom) and import_node.module in WEBSOCKET_MODULES:
            expected_call = "create_connection" if import_node.module == "websocket" else "connect"
            for alias in import_node.names:
                if alias.name == expected_call:
                    websocket_call_aliases[alias.asname or alias.name] = import_node.module

    def websocket_call_has_literal_wss(call: ast.Call, module: str) -> bool:
        endpoint: ast.expr | None = call.args[0] if call.args else None
        if endpoint is None:
            keyword_name = "url" if module == "websocket" else "uri"
            endpoint = next((kw.value for kw in call.keywords if kw.arg == keyword_name), None)
        return bool(
            isinstance(endpoint, ast.Constant)
            and isinstance(endpoint.value, str)
            and endpoint.value.startswith("wss://")
        )

    # REPL-style snippets often reference already-available standard/HTTP modules without
    # an import in the same -c string; these roots still have known bounded capability.
    trusted_roots = {
        "Path", "os", "json", "requests", "httpx", "urllib",
        *websocket_module_aliases, *websocket_call_aliases,
    }
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign, ast.NamedExpr)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name) and target.id in trusted_roots:
                    return False
        if isinstance(node, ast.Import):
            for alias in node.names:
                name = alias.name
                if name in ESCAPE_MODULES or name.split(".", 1)[0] in ESCAPE_MODULES:
                    return False
                if name not in HTTP_MODULES and name not in WEBSOCKET_MODULES and name not in SAFE_STDLIB_MODULES and name not in SAFE_CREDENTIAL_MODULES:
                    return False
                trusted_roots.add(alias.asname or name.split(".", 1)[0])
                saw_network |= name in HTTP_MODULES
        elif isinstance(node, ast.ImportFrom):
            name = node.module or ""
            if name in ESCAPE_MODULES or name.split(".", 1)[0] in ESCAPE_MODULES:
                return False
            if name not in HTTP_MODULES and name not in WEBSOCKET_MODULES and name not in SAFE_STDLIB_MODULES and name not in SAFE_CREDENTIAL_MODULES:
                return False
            trusted_roots.update(alias.asname or alias.name for alias in node.names)
            saw_network |= name in HTTP_MODULES
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id in ESCAPE_CALLS:
                return False
            if isinstance(node.func, ast.Attribute):
                chain: list[str] = []
                cur = node.func
                while isinstance(cur, ast.Attribute):
                    chain.append(cur.attr)
                    cur = cur.value
                if isinstance(cur, ast.Name):
                    chain.append(cur.id)
                    dotted = ".".join(reversed(chain))
                    if dotted.startswith(("requests.", "httpx.", "urllib.request.")):
                        saw_network = True
                    elif cur.id in websocket_module_aliases:
                        websocket_module = websocket_module_aliases[cur.id]
                        expected_call = "create_connection" if websocket_module == "websocket" else "connect"
                        if node.func.attr != expected_call:
                            return False
                        # Bind the proof to this call's first AST argument.  A dynamic
                        # endpoint plus an unrelated "wss://" string must stay blocked.
                        if not websocket_call_has_literal_wss(node, websocket_module):
                            return False
                        saw_network = True
                    elif dotted == "os.getenv" or dotted.startswith("os.environ.get"):
                        pass
                    elif cur.id == "os":
                        return False
                    elif cur.id not in trusted_roots:
                        return False
            elif isinstance(node.func, ast.Name):
                if node.func.id in websocket_call_aliases:
                    if not websocket_call_has_literal_wss(node, websocket_call_aliases[node.func.id]):
                        return False
                    saw_network = True
                elif node.func.id not in trusted_roots:
                    # Builtins are ordinary data processing; imported/assigned opaque executors are not.
                    if node.func.id not in {"open", "print", "len", "str", "bytes", "dict", "list", "set", "tuple", "int", "float", "bool"}:
                        return False
    return saw_network


def _python_m_is_safe(tokens: list[str]) -> bool:
    """python3 -m <module> が既知の安全なstdlibモジュールかを判定する。

    json.tool等のDB接続能力ゼロのstdlibモジュールがcurlパイプライン内で
    使われた場合にFPを防ぐ(2026-07-15将軍実証: source .env && curl ... | python3 -m json.tool)。
    """
    stripped = _strip_env_prefix(tokens)
    if not stripped or os.path.basename(stripped[0]) not in {"python", "python3", "python.exe"}:
        return False
    try:
        idx = stripped.index("-m")
    except ValueError:
        return False
    if idx + 1 >= len(stripped):
        return False
    module = stripped[idx + 1]
    return module in SAFE_PYTHON_M_MODULES


def _bash_has_inline_code(tokens: list[str]) -> bool:
    """bash/sh -c はインラインコード実行。-c なしはスクリプトファイル実行。

    スクリプトファイル実行時の引数テキストにcredential-likeワードが含まれても
    ファイルアクセスではないため安全(2026-07-15将軍実証: bash lesson_write_shogun.sh
    に credential-like テキストを渡すとGuard14 FP)。
    -c ありの場合はインラインコードを実行するため安全とは言えない。
    """
    stripped = _strip_env_prefix(tokens)
    return "-c" in stripped


def _shell_segments_are_bounded(command: str, segments: list[list[str]]) -> bool:
    """Allow only explicit env setup, capability-checked read-only inspection, curl, or verified Python.

    review_correction(2026-07-12 RC5, karo): pipe(|)はsegment境界(_split_into_segments済み)
    として扱い、一律拒否しない。各segmentがcmd0+option能力で個別にsafeと判定された場合のみ
    ALLOWする。xargs/sh/評価不能なopaque commandが1つでも混じれば最終的に return False へ
    落ちる。command substitution($()/backtick)とprocess substitution(<(...)/>(...))は
    segment分割を経由しても迂回できる実行経路のため、引き続き生コマンド文字列で無条件BLOCK。
    """
    if "$(" in command or "`" in command or "<(" in command or ">(" in command:
        return False
    for segment in segments:
        cmd0 = _segment_cmd0(segment)
        if cmd0 in ENV_SETUP_SHELL_CMDS:
            continue
        if cmd0 in SAFE_NON_DB_CMDS:
            continue
        # A shell script is executable capability, not bounded inspection.
        # When credentials are in scope, an opaque sh/bash operand must stay
        # fail-closed even without -c; its body is not proven by this command.
        if cmd0 in READ_ONLY_SHELL_CMDS:
            if _segment_is_readonly_safe(cmd0, segment):
                continue
            return False
        if CURL_CMD_RE.match(cmd0):
            continue
        if _python_inline_code(segment) is not None and _python_http_only_capability(segment):
            continue
        if _python_m_is_safe(segment):
            continue
        return False
    return bool(segments)


def _split_into_segments(all_tokens: list[str]) -> list[list[str]]:
    segments: list[list[str]] = []
    current: list[str] = []
    for tok in all_tokens:
        if tok in OPERATORS:
            if current:
                segments.append(current)
            current = []
            continue
        current.append(tok)
    if current:
        segments.append(current)
    return segments


def _segment_is_exempt(tokens: list[str]) -> bool:
    # review_correction(2026-07-12 09:22, karo): 全token走査だと、remote接続segmentの
    # 末尾に単なる引数としてcheck_pf_config.pyを足すだけでなりすまし免除できてしまう。
    # 免除対象はpython系cmd0の「実行スクリプトoperand」(flag群の直後の最初の非flag引数)
    # のみに限定する。-c指定(inline code実行)は対象外(スクリプトファイルを実行しない)。
    stripped = _strip_env_prefix(tokens)
    if not stripped:
        return False
    cmd0 = os.path.basename(stripped[0])
    if cmd0 not in {"python", "python3", "python.exe"}:
        return False
    rest = stripped[1:]
    # Python accepts several interpreter options whose values do not start with
    # a dash (for example ``-X utf8`` and ``-W ignore``).  Treating the value as
    # the first executable operand makes an otherwise canonical launcher look
    # like an arbitrary script and causes Guard14 to fail closed.  Consume only
    # Python's documented option/value pairs; unknown options remain rejected.
    value_options = {"-X", "-W", "--check-hash-based-pycs"}
    no_value_options = {
        "-B", "-b", "-d", "-E", "-h", "-I", "-i", "-O", "-OO", "-P",
        "-q", "-s", "-S", "-u", "-v", "-V", "-VV", "--help", "--version",
    }
    script_index: int | None = None
    i = 0
    while i < len(rest):
        tok = rest[i]
        if tok in value_options:
            if i + 1 >= len(rest) or rest[i + 1].startswith("-"):
                return False
            i += 2
            continue
        if tok in no_value_options:
            i += 1
            continue
        if tok.startswith("-"):
            return False
        script_index = i
        break
    if script_index is None:
        return False

    tok = rest[script_index]
    clean = tok.strip("'\"")
    if os.path.basename(clean) not in EXEMPT_SCRIPT_BASENAMES:
        return False
    # review_correction(2026-07-12 09:24, karo): basename一致だけでは同名の別ファイル
    # (例: /tmp/check_pf_config.py)でも免除されてしまう。実行operandのrealpathを
    # 正規パスとsamefile同一性確認(両方の実在確認込み)した場合のみ免除する。
    canonical = _canonical_exempt_script_path(os.path.basename(clean))
    if not canonical or not os.path.exists(canonical):
        return False
    # Hook callers do not have a stable cwd.  A repository-relative script
    # operand is defined relative to the classifier's repository SSOT, while
    # an absolute operand remains absolute.  Cwd-relative realpath made the
    # documented `python3 scripts/db_capability_launcher.py ...` form fail
    # whenever the hook process happened to start outside the repository.
    resolved = os.path.realpath(
        clean if os.path.isabs(clean) else os.path.join(_REPO_ROOT, clean)
    )
    if not os.path.exists(resolved):
        return False
    try:
        if not os.path.samefile(resolved, canonical):
            return False
    except OSError:
        return False
    if os.path.basename(clean) == "db_capability_launcher.py":
        return _db_launcher_invocation_valid(rest[script_index + 1 :])
    if os.path.basename(clean) == "dm_signal_adapters.py":
        return _cdp_auth_adapter_invocation_valid(rest[script_index + 1 :])
    return True


_REDIRECT_RE = re.compile(r"^[0-9]*[><]")


def _strip_shell_redirects(tokens: list[str]) -> list[str]:
    """Remove shell redirect tokens (2>, >, <, etc.) that shlex leaves in segments.

    Claude Code appends '2>&1' to bash commands. shlex with punctuation_chars=";&|"
    tokenizes this as '2>' + '&' + '1'. The '&' is a segment separator, so '2>' ends
    up as the last token of the preceding segment. This is a shell redirect, not a
    script argument (2026-07-15 shogun root cause: launcher exempt rejected because
    '2>' was treated as unknown child arg → not child = False).
    """
    return [t for t in tokens if not _REDIRECT_RE.match(t)]


def _db_launcher_invocation_valid(argv: list[str]) -> bool:
    """Prove the canonical launcher was invoked through its registered contract."""
    argv = _strip_shell_redirects(argv)
    value_flags = {
        "--capability", "--mode", "--confirm", "--nonce", "--credential-file",
        "--credential-source-file", "--expected-commit", "--execution-root",
    }
    parsed: dict[str, str | bool] = {}
    child: list[str] = []
    i = 0
    while i < len(argv):
        token = argv[i]
        if token == "--":
            child = argv[i + 1 :]
            break
        if token == "--prepare-only":
            if token in parsed:
                return False
            parsed[token] = True
            i += 1
            continue
        if token in value_flags:
            if token in parsed or i + 1 >= len(argv) or argv[i + 1].startswith("--"):
                return False
            parsed[token] = argv[i + 1]
            i += 2
            continue
        if not token.startswith("-"):
            child = argv[i:]
            break
        return False

    required = {"--capability", "--mode", "--confirm", "--credential-file"}
    if not required.issubset(parsed):
        return False
    try:
        with open(os.path.join(_REPO_ROOT, "config", "db_capabilities.json"), encoding="utf-8") as handle:
            registry = json.load(handle)
    except (OSError, ValueError):
        return False
    contract = registry.get("capabilities", {}).get(parsed["--capability"])
    if not isinstance(contract, dict):
        return False
    if parsed["--mode"] not in contract.get("modes", []) or parsed["--confirm"] != contract.get("confirm"):
        return False
    if parsed.get("--prepare-only"):
        return bool(parsed.get("--credential-source-file")) and not child and "--nonce" not in parsed
    if "--credential-source-file" in parsed or "--nonce" not in parsed:
        return False
    if contract.get("requires_expected_commit") and "--expected-commit" not in parsed:
        return False
    actions = contract.get("actions")
    if not actions:
        return not child
    if not child or child[0] not in actions:
        return False
    allowed_flags = set(contract.get("allowed_child_flags", []))
    return len(child[1:]) % 2 == 0 and all(
        child[j] in allowed_flags and not child[j + 1].startswith("--")
        for j in range(1, len(child), 2)
    )


def _cdp_auth_adapter_invocation_valid(argv: list[str]) -> bool:
    """Prove the canonical adapter is restricted to its auth-strategy contract.

    The adapter performs viewer/admin HTTP and CDP WebSocket authentication; it
    is not a database client.  Keep this boundary exact so an arbitrary Python
    script, a different adapter subcommand, or an appended child command cannot
    inherit the exemption.
    """
    argv = _strip_shell_redirects(argv)
    if len(argv) < 2 or argv[0] != "--receipt" or argv[1].startswith("--"):
        return False
    index = 2
    if index >= len(argv) or argv[index] != "auth-strategy":
        return False
    index += 1

    value_flags = {"--target-url", "--required-capability", "--env-file"}
    parsed: dict[str, str] = {}
    while index < len(argv):
        token = argv[index]
        if token not in value_flags or token in parsed or index + 1 >= len(argv):
            return False
        value = argv[index + 1]
        if not value or value.startswith("--"):
            return False
        parsed[token] = value
        index += 2

    if set(parsed) != value_flags:
        return False
    if parsed["--required-capability"] not in {"viewer", "admin"}:
        return False
    return parsed["--target-url"].startswith(("http://", "https://"))


def _url_host_candidate(url: str) -> str:
    # postgresql://が実際に現れた時だけurllib.parseをimportする(実測-4ms/呼び出しの節約)
    from urllib.parse import parse_qs, unquote, urlsplit

    parts = urlsplit(url)
    if parts.hostname:
        return parts.hostname
    # libpq accepts both a literal absolute socket directory and its
    # percent-encoded URL representation.  Decode exactly the structured
    # query value; never unquote/free-scan the surrounding command text.
    query_host = unquote(parse_qs(parts.query).get("host", [""])[0])
    if query_host.startswith("/"):
        return query_host  # Unix socket指定 (?host=/var/run/postgresql)
    return ""  # authority空かつquery override無し = 未解決(fail-closed)


def _flag_host_candidates(tokens: list[str]) -> list[str]:
    # psql等CLIのネイティブ -h HOST / --host HOST / --host=HOST 形式を構造抽出する
    found: list[str] = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok in ("-h", "--host") and i + 1 < len(tokens):
            found.append(tokens[i + 1].strip("'\""))
            i += 2
            continue
        if tok.startswith("--host="):
            found.append(tok.split("=", 1)[1].strip("'\""))
        i += 1
    return found


def _extract_candidates(tokens: list[str]) -> list[str]:
    text = " ".join(tokens)
    found: list[str] = []
    if ":memory:" in text:
        found.append(":memory:")
    # URL query parameters are parsed by urllib below.  Feeding their host=
    # fragment through HOST_KV_RE as well creates a second, truncated candidate
    # for percent-encoded socket paths ("%2F..." -> empty), incorrectly making
    # an otherwise valid structured URL fail closed.
    urls = list(DSN_URL_RE.finditer(text))
    non_url_text = DSN_URL_RE.sub(" ", text)
    for m in HOST_KV_RE.finditer(non_url_text):
        found.append(m.group(1))
    for m in urls:
        found.append(_url_host_candidate(m.group(0)))
    found.extend(_flag_host_candidates(tokens))
    return found


def _is_local_candidate(value: str) -> bool:
    if value == "":
        return False  # review_correction(09:17): 未解決/空値はfail-closedでuntrusted
    if value == ":memory:" or value in LOCAL_HOST_VALUES:
        return True
    if value.startswith("/"):
        # An arbitrary absolute-looking string is not a local capability.
        # libpq's host value is a socket *directory*, so require the directory
        # to exist at classification time and reject files/nonexistent paths.
        return os.path.isdir(value)
    return False


def classify(command: str) -> str:
    try:
        all_tokens = _tokenize(command)
    except ValueError:
        # コマンド全体のquote解析に失敗 = fail-closed BLOCK
        return "connection:untrusted"

    segments = _split_into_segments(all_tokens)
    # A canonical capability launcher owns validation of its credential file,
    # nonce, mode and child command.  Remove only that exact segment from both
    # generic DB-intent and credential-source classification.  Other segments
    # in a compound command remain fully fail-closed.
    exempt_connection_present = any(_segment_is_exempt(seg) and _is_connection_segment(seg) for seg in segments)
    untrusted_boundary_segments = [seg for seg in segments if not _segment_is_exempt(seg)]
    connection_segments = [seg for seg in untrusted_boundary_segments if _is_connection_segment(seg)]

    credential_segments = [seg for seg in untrusted_boundary_segments if _segment_has_env_credential_source(seg)]
    if credential_segments and not connection_segments:
        # 全segmentを能力分類し、未知shell/Python実行が1つでもあればfail-closed。
        if _shell_segments_are_bounded(command, segments):
            return "not_connection"
        return "connection:untrusted"

    if not connection_segments:
        return "connection:local_ephemeral" if exempt_connection_present else "not_connection"

    for seg in connection_segments:
        if _segment_is_exempt(seg):
            continue
        if (
            _python_readonly_sqlite_capability(seg)
            or _python_readonly_sqlite_heredoc_capability(command)
            or _python_readonly_sqlite_argv_heredoc_capability(command)
        ):
            continue
        candidates = _extract_candidates(seg)
        if not candidates:
            # 接続意図はあるがそのsegment自身からDSN未抽出(環境変数展開/未解決参照等) = fail-closed BLOCK
            return "connection:untrusted"
        if not all(_is_local_candidate(c) for c in candidates):
            return "connection:untrusted"

    return "connection:local_ephemeral"


def classify_from_payload(payload: str) -> str:
    # review_correction(2026-07-12 09:30, karo): JSON境界の復元はSSOTパーサー(json module)
    # に一任する。awk抽出済みの$commandをregexで修復しない。
    try:
        data = json.loads(payload)
    except (json.JSONDecodeError, TypeError):
        return "connection:untrusted"
    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        return "connection:untrusted"
    command = tool_input.get("command")
    if not isinstance(command, str):
        return "connection:untrusted"
    return classify(command)


if __name__ == "__main__":
    _payload = os.environ.get("HOOK_PAYLOAD_JSON", "")
    if _payload:
        print(classify_from_payload(_payload))
    else:
        # 単体テスト/直接呼び出し向け: 生のcommand文字列をそのまま分類する
        print(classify(os.environ.get("COMMAND", "")))
