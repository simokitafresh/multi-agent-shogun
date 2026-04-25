<!-- GStack/GBrain takeaway #15 -->
# CDP Severity

CDP計測・canary・ブラウザ実測の異常は、以下の4段階で扱う。

## Severity定義

| severity | 意味 | 例 | 初動 |
|---|---|---|---|
| critical | 本番利用不能、または誤データを返す | 主要画面が開かない、認証不能、誤注文/誤登録 | 直ちに停止・修正優先 |
| high | 本番利用は可能だが主要フローが崩れる | 保存失敗、主要API 5xx、多数の console error | 当該cmd内で修正候補を最優先化 |
| medium | 劣化はあるが回避策あり | LCP悪化、部分UI崩れ、再試行で回復 | 原因と再現条件を記録し補修計画へ |
| low | 軽微、観測のみでよい | 単発warning、表示揺れ、非本質ログ | 記録のみ。即修正しない |

## 運用ルール

- `critical/high` は「何が壊れたか」だけでなく、影響範囲と再現手順を必ず添える
- `medium/low` は闇雲に直すな。再現条件と頻度を先に固める
- severity は主観でなく、ユーザー影響と blast radius で決める
- `critical` と `high` は canary / deploy 後監視の優先対象とする
