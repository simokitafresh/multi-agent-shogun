<!-- gist-master: ec8c65c562183147b41876530b1eb2ee wsl-vhdx-compact-runbook-20260825.md -->
# WSL VHDX圧縮 実施手順（disk物理回収 約370GB）

- 作成: 2026-08-25 21:41 JST（将軍）
- 目的: WSL ext4.vhdx（実測517GB、WSL内実使用148GB）の空洞約370GBをC:へ物理返却する
- 前提（完了済み）:
  - `fstrim -av` 実行済み — **659.2 GiB trimmed**（殿実行 21:33）
  - VHDX内重要データ退避済み — `backup/wsl_evacuation_20260825/`（~/.claude 406MB・pinned claude bin 69MB・ssh・crontab・bashrc、tar検証PASS）
  - 復帰点焼込み済み — 記憶DB `session_save_20260825_2140`
  - 走行中エージェント作業なし（忍者全idle確認済み）

## Step 1: Windows側で管理者ターミナルを開く

`Win+X` → 「ターミナル（管理者）」（PowerShell管理者でも可）

## Step 2: WSLを完全停止

```powershell
wsl --shutdown
```

この瞬間に全エージェント（将軍含む）が停止する。退避済みのため安全。

## Step 3: 停止確認

```powershell
wsl -l -v
```

STATEが `Stopped` になっていること。

## Step 4: VHDXを圧縮（本命）

```powershell
Optimize-VHD -Path "C:\Users\simok\AppData\Local\wsl\{c23d870a-02b3-4bea-980a-dc0eda6dc640}\ext4.vhdx" -Mode Full
```

進捗バーが出て数分〜十数分。

**「Optimize-VHD が認識されない」場合**（Hyper-Vモジュール無し）は代替:

```powershell
diskpart
```

diskpart内で1行ずつ:

```
select vdisk file="C:\Users\simok\AppData\Local\wsl\{c23d870a-02b3-4bea-980a-dc0eda6dc640}\ext4.vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
exit
```

## Step 5: 回収確認

```powershell
Get-Item "C:\Users\simok\AppData\Local\wsl\{c23d870a-02b3-4bea-980a-dc0eda6dc640}\ext4.vhdx" | Select-Object @{n='GB';e={[math]::Round($_.Length/1GB,1)}}
```

**517GB → 150GB前後**になっていれば成功（約370GB回収）。

## Step 6: WSL再起動と陣形復元

いつも通りWSLターミナルを開き、将軍セッションを起動。将軍に「y」で復帰指示。
復帰点 `session_save_20260825_2140` から立ち上がり、回収量の実測報告と陣形復元まで将軍が自走する。

**陣形復元の実手順（2026-08-25実施で確定。`/reset-layout`スキルは削除済み(efc8e016e)で使えない）:**

```bash
bash shutsujin_departure.sh -s     # tmuxセッションshogun再建のみ(将軍CLIは起動しない=二重起動回避)
bash scripts/reset_layout.sh       # 家老・軍師・忍者8ペインのCLI起動+watcher 9本再起動
tmux capture-pane -t shogun:agents.1 -p | tail -5   # 一次確認(家老が起動しているか)
```

将軍自身がtmux外の端末で動いている場合、`shutsujin_departure.sh`を引数なしで実行すると将軍CLIが二重起動するため必ず`-s`を付ける。

## 注意点（唯一のリスク）

**Step 4の実行中にPCを落とさないこと。** 圧縮中断がVHDX破損の唯一の現実的リスク。
万一破損した場合: WSL再インストール → `backup/wsl_evacuation_20260825/` から復元（repo・記憶DBは/mnt/cにあり無傷）。

## 参考: C: 908GB使用の全内訳（2026-08-25実測）

| 項目 | 実測 |
|---|---|
| Users（うちVHDX 517G + swap 8.1G） | 628.4 GB |
| Python_app | 87.1 GB |
| Program Files 計 | 45.7 GB |
| Windows | 41.1 GB |
| tools | 23.4 GB |
| tmp + temp | 25.6 GB |

正本ログ: `logs/disk_scan_c_drive_20260825.log`

## 実施結果（2026-08-25 21:57〜22:55 実測）

| 時刻 | 処置 | C: 空き(df -Pk /mnt/c) | 備考 |
|---|---|---|---|
| 21:40 | 実施前 | 20 GB | VHDX 517 GB |
| 21:57 | `wsl --shutdown` → `Optimize-VHD -Mode Full` → WSL再起動 | 362 GB | **VHDX 517 → 182.2 GB（−335 GB）**。期待150Gより32G大きい=WSL内実使用86Gに対し約95Gの空洞が残存。次回Optimize-VHDで更に縮む余地あり |
| 22:07 | 陣形復元（`shutsujin_departure.sh -s` → `reset_layout.sh`） | — | CLI 8/8・watcher 9/9・ninja_monitor/ntfy_listener稼働。home無傷（pinned claude 2.1.87・crontab 3行・ssh）。退避データは未使用 |
| 22:25 | `C:\tmp`/`C:\temp` のCDP Chromeプロファイル残骸88件削除 | 381.6 GB | 19.63 GB回収。温存=`cdp-chrome-9234`/`cdp-shogun-9222`/`note_figure_render`/`chrome_note_cdp`/`chrome-note-profile`+名前に`note`を含む全プロファイル+録音wav等の個別ファイル。Chrome起動中は「C:\tmp\|tempのプロファイルを使うプロセスのみ」を中断条件にする（殿の通常Chromeは対象外） |
| 22:45 | DM-signal git worktree 16本 remove + prune 22件 | 397.6 GB | 15.9 GB回収。`status --porcelain`=0のみ対象。ブランチ未所属のdetached 2 commitは `safety/wt-hayate-l5-upstream-v2-20260825`(dedab685)・`safety/wt-saizo-l5-join-await-20260825`(e254a3d7) へタグ退避。据置=main(dirty13)/rb8-clean(dirty2)/canonical-main(dirty7) |

**本日累計: C: 空き 20 GB → 397.6 GB（+377.6 GB）**

### 残件（Python_app 87.1 GBの内訳）

| 領域 | 容量 | 状態 |
|---|---|---|
| `DM-signal/outputs/grid_search` | 42.5 GB | 研究資産（GS結果DB群、正本`20260429/L1/shin`等）。台帳`DM-signal/docs/research/cmd_3868_gs_db_generation_inventory.md`と突合する偵察cmd_4404で削除候補を確定 |
| worktree群 | ≈22 GB → 据置3本のみ | 回収済み |
| `outputs/analysis` 3.2G / `analysis_runs` 2.3G / `.venv`系 1.5G | ≈7 GB | 稼働中・再生成可。据置 |
| 他PJ 30本 | ≈9 GB | 各0.1〜0.8G。据置 |

### 根因と再発防止（構造型）

- CDPプロファイル: `scripts/cdp/cdp_session.py`の`mkdtemp`プロファイルがcleanup失敗時に孤児化し、cmd単位の隔離プロファイルも無回収。→ insight `INS-20260825-222550368-eac2`（未使用かつ7日超のCDPプロファイルを日次回収、温存名簿付き）
- `/reset-layout`幻ポインタ: CLAUDE.md §Skillsが削除済みスキルを指していた。→ insight `INS-20260825-221101766-df42`（スキル参照の実在をstartup gateで検証）
- worktree: 完了cmdのworktreeが`git worktree remove`されず残る。→ cmd完了gate（archive_completed.sh）で当該cmdのworktreeをdirty=0確認のうえ自動removeする候補
