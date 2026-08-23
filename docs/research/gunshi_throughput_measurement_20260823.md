# スループット阻害実測データ (2026-08-23 本セッション)

## 1. review_bundle.py WSL timeout

集計コマンド: 手動計数(本セッションのbash実行結果)。自動ログなし
生出力:
```
kotaro: timeout 30 python3 review_bundle.py single ... → rc=124 (bg task b6v6nns4r exit 0)
saizo:  timeout 30 python3 review_bundle.py single ... → rc=124 (sg7生成済み、notify未達)
tobisaru: timeout 30 python3 review_bundle.py single ... → rc=124 (approval recorded、notify未達)
hayate: timeout 30 python3 review_bundle.py single ... → rc=124 (notify未達)
```
1件の定義: review_bundle.py singleコマンド1回のrc=124(30秒timeout超過)
結果: 発生 4/4件(100%)、通知未達 3/4件(75%)、損失 30s(timeout)+60s(手動補完)=90s/件

## 2. 重複inbox report_review

集計コマンド: `grep 'report_fingerprint:' queue/inbox/gunshi.yaml | sort | uniq -c | sort -rn`
生出力:
```
      3   report_fingerprint: 'd08fc25c...'  (saizo reflux_dirty)
      3   report_fingerprint: '77ecb282...'  (kotaro report_write)
      2   report_fingerprint: 'a5130256...'  (hayate gate_publication)
      2   report_fingerprint: '9713ddd8...'  (kagemaru cmd_4376)
      1   (他4種 各1件)
```
1件の定義: 同一report_fingerprintのtype=report_review inbox entry
結果: 全14 entries中8種、重複6件(43%)、損失10s/件×6=60s
