# WSL2 NTFS シンボリックリンク制限 (2026-04-27)

## 結論
WSL2上の/mnt/c/(NTFS)でディレクトリを指すsymlinkは**作成可能だがtraversal不可**。
ファイルを指すsymlinkは正常動作する。

## 実測結果

| 操作 | ファイルsymlink | ディレクトリsymlink |
|------|---------------|-------------------|
| os.symlink() | OK | OK |
| is_symlink() | True | True |
| is_dir() | N/A | **False** |
| os.listdir(link) | N/A | **ENOENT** |
| Path(link)/file.read_text() | N/A | **ENOENT** |
| os.replace(tmp, link) | OK | **ENOENT** |
| unlink + recreate | OK | 作成はOKだがtraverseはFAIL |
| target_is_directory=True | N/A | 作成OK, traverseはFAIL |

## 影響範囲

- **DM-Signal**: symlink使用なし(cmd_2332が初導入予定)。cmd_2332でREQUEST_CHANGES済み
- **infra(archive_completed.sh)**: ファイルsymlink(ln -sf)使用。正常動作確認(GP-230)
- **設計書§3.1**: latest symlink仕様→テキストポインタ方式(latest.txt)に変更要

## 代替手段

| 方式 | WSL2互換 | atomic | 実装 |
|------|---------|--------|------|
| latest.txt(テキストポインタ) | OK | write_text=atomic | Path(read_text().strip()) |
| ファイルsymlink | OK | os.replace OK | ファイル参照のみ |
| ディレクトリsymlink | **NG** | os.replace NG | 使用禁止 |

## 一般原則
**WSL2 NTFS(/mnt/c/)ではディレクトリsymlinkを使うな。** テキストポインタまたはファイルsymlinkを使え。
ext4パーティション上(/home/, /tmp/)では問題なし。
