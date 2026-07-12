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

# check_pf_config.py は実在するDM-Signalスクリプト(PF構成一括確認, cmd_3378)。
# これを実行するsegmentのみ構造的に免除する。"db-check"のような自由文字列免除はしない。
EXEMPT_SCRIPT_BASENAMES = {"check_pf_config.py"}

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


def _canonical_exempt_script_path() -> str | None:
    # config/projects.yaml (SSOT) の dm-signal.path から正規check_pf_config.pyパスを導出する。
    # ハードコードしない(Guard18: 操作的オントロジー — PJパス直書き禁止)。
    # hookは python3 -S (site初期化skip、実測-6ms/呼び出し)で起動するため、通常経路では
    # site-packages がsys.pathに無くyamlをimportできない。ここ(免除判定の稀な経路)でのみ
    # site.main()でsite-packagesを復元してからimportする。
    try:
        import yaml
    except ImportError:
        try:
            import site
            site.main()
            import yaml
        except ImportError:  # pragma: no cover - PyYAML欠如環境ではfail-closed
            return None
    # Unit tests supply a private projects fixture so this structural samefile
    # check never depends on a developer's external DM-Signal checkout.  The
    # override is deliberately unavailable outside Bats: production must use
    # this repository's config/projects.yaml SSOT, not a caller-controlled
    # environment variable.
    if os.environ.get("BATS_TEST_FILENAME"):
        projects_yaml = os.environ.get(
            "GUARD14_PROJECTS_YAML", os.path.join(_REPO_ROOT, "config", "projects.yaml")
        )
    else:
        projects_yaml = os.path.join(_REPO_ROOT, "config", "projects.yaml")
    try:
        with open(projects_yaml, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except OSError:
        return None
    for proj in data.get("projects") or []:
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
HTTP_CLIENT_CALL_RE = re.compile(
    r"\b(?:requests|httpx)\.(?:get|post|put|patch|delete|request)\s*\("
    r"|\burllib\.request\.urlopen\s*\("
)
CURL_CMD_RE = re.compile(r"^(?:curl|curl\.exe)$")
HTTP_MODULES = {"requests", "httpx", "urllib", "urllib.request"}
SAFE_STDLIB_MODULES = {
    "json", "os", "pathlib", "re", "time", "datetime", "base64", "hashlib",
    "typing", "collections", "urllib.parse",
}
SAFE_CREDENTIAL_MODULES = {"dotenv"}
ESCAPE_MODULES = {"socket", "subprocess", "ctypes", "importlib"}
ESCAPE_CALLS = {"eval", "exec", "compile", "__import__"}


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
    return ENV_CREDENTIAL_FILE_RE.search(" ".join(tokens)) is not None


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


def _python_http_only_capability(tokens: list[str]) -> bool:
    """Prove Python -c has only ordinary data processing plus explicit HTTP capability."""
    code = _python_inline_code(tokens)
    if code is None:
        return False
    try:
        tree = ast.parse(code)
    except (SyntaxError, ValueError):
        return False
    saw_http = False
    # REPL-style snippets often reference already-available standard/HTTP modules without
    # an import in the same -c string; these roots still have known bounded capability.
    trusted_roots = {"Path", "os", "json", "requests", "httpx", "urllib"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                name = alias.name
                if name in ESCAPE_MODULES or name.split(".", 1)[0] in ESCAPE_MODULES:
                    return False
                if name not in HTTP_MODULES and name not in SAFE_STDLIB_MODULES and name not in SAFE_CREDENTIAL_MODULES:
                    return False
                trusted_roots.add(alias.asname or name.split(".", 1)[0])
                saw_http |= name in HTTP_MODULES
        elif isinstance(node, ast.ImportFrom):
            name = node.module or ""
            if name in ESCAPE_MODULES or name.split(".", 1)[0] in ESCAPE_MODULES:
                return False
            if name not in HTTP_MODULES and name not in SAFE_STDLIB_MODULES and name not in SAFE_CREDENTIAL_MODULES:
                return False
            trusted_roots.update(alias.asname or alias.name for alias in node.names)
            saw_http |= name in HTTP_MODULES
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
                        saw_http = True
                    elif cur.id not in trusted_roots:
                        return False
            elif isinstance(node.func, ast.Name) and node.func.id not in trusted_roots:
                # Builtins are ordinary data processing; imported/assigned opaque executors are not.
                if node.func.id not in {"open", "print", "len", "str", "bytes", "dict", "list", "set", "tuple", "int", "float", "bool"}:
                    return False
    return saw_http


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
    if "-c" in rest:
        return False
    for tok in rest:
        if tok.startswith("-"):
            continue
        clean = tok.strip("'\"")
        if os.path.basename(clean) not in EXEMPT_SCRIPT_BASENAMES:
            return False
        # review_correction(2026-07-12 09:24, karo): basename一致だけでは同名の別ファイル
        # (例: /tmp/check_pf_config.py)でも免除されてしまう。実行operandのrealpathを
        # 正規パスとsamefile同一性確認(両方の実在確認込み)した場合のみ免除する。
        canonical = _canonical_exempt_script_path()
        if not canonical or not os.path.exists(canonical):
            return False
        resolved = os.path.realpath(clean)
        if not os.path.exists(resolved):
            return False
        try:
            return os.path.samefile(resolved, canonical)
        except OSError:
            return False
    return False


def _url_host_candidate(url: str) -> str:
    # postgresql://が実際に現れた時だけurllib.parseをimportする(実測-4ms/呼び出しの節約)
    from urllib.parse import parse_qs, urlsplit

    parts = urlsplit(url)
    if parts.hostname:
        return parts.hostname
    query_host = parse_qs(parts.query).get("host", [""])[0]
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
    for m in HOST_KV_RE.finditer(text):
        found.append(m.group(1))
    for m in DSN_URL_RE.finditer(text):
        found.append(_url_host_candidate(m.group(0)))
    found.extend(_flag_host_candidates(tokens))
    return found


def _is_local_candidate(value: str) -> bool:
    if value == "":
        return False  # review_correction(09:17): 未解決/空値はfail-closedでuntrusted
    if value == ":memory:" or value in LOCAL_HOST_VALUES:
        return True
    if value.startswith("/"):
        return True  # Unix socketパス (host=/var/run/postgresql 等)
    return False


def classify(command: str) -> str:
    try:
        all_tokens = _tokenize(command)
    except ValueError:
        # コマンド全体のquote解析に失敗 = fail-closed BLOCK
        return "connection:untrusted"

    segments = _split_into_segments(all_tokens)
    connection_segments = [seg for seg in segments if _is_connection_segment(seg)]

    credential_segments = [seg for seg in segments if _segment_has_env_credential_source(seg)]
    if credential_segments and not connection_segments:
        # rg/grep/sed/cat等はファイル名を読むだけで接続能力を持たない。
        if all(_python_inline_code(seg) is None for seg in segments):
            return "not_connection"
        # Render等の固有語では免除しない。HTTP clientの構造がcommand内に明示された場合のみ
        # ASTからimport/call能力を検査し、未知module/escape capabilityはfail-closedにする。
        python_segments = [seg for seg in segments if _python_inline_code(seg) is not None]
        if python_segments and all(_python_http_only_capability(seg) for seg in python_segments):
            return "not_connection"
        return "connection:untrusted"

    if not connection_segments:
        return "not_connection"

    for seg in connection_segments:
        if _segment_is_exempt(seg):
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
