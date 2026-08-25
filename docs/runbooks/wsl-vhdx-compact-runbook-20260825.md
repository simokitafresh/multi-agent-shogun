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
復帰点 `session_save_20260825_2140` から立ち上がり、回収量の実測報告と陣形復元（/reset-layout）まで将軍が自走する。

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
