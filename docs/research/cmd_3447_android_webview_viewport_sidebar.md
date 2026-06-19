# Android WebView viewport幅決定ロジック + サイドバー2行問題根因分析

- **cmd**: cmd_3447_saizo_normal
- **date**: 2026-06-19
- **author**: saizo
- **target**: `/mnt/c/Python_app/google_classroom/android/app/src/main/java/com/classroom/app/MainActivity.kt`
- **HTML/CSS**: `/mnt/c/Python_app/google_classroom/public/index.html`

---

## AC1: Android WebView viewport幅決定ロジック (file:// URL)

### useWideViewPort=false時のviewport幅決定 (v1.7現在)

**Android公式ドキュメント**: `WebSettings.setUseWideViewPort(boolean)`
> "Sets whether the WebView should enable support for the 'viewport' HTML meta tag or should use a wide viewport. When the value of the setting is **false**, the layout width is always set to the **width of the WebView control in device-independent (CSS) pixels**."

**参照**: https://developer.android.com/reference/android/webkit/WebSettings#setUseWideViewPort(boolean)

#### `useWideViewPort=false` (v1.7現在 - MainActivity.kt L113)

| 項目 | 値 |
|------|-----|
| viewport幅の決定元 | WebViewコントロールのレイアウト幅(dp) |
| 典型的な値 | 360〜430 CSS px (機種依存) |
| viewport meta tagの扱い | 無視 (layoutWidthを強制) |
| `@media (max-width: 768px)` | **発動する** (360-430 < 768) |
| ハンバーガー表示 | **`display: block`** |
| サイドバー初期状態 | 非表示 (`transform: translateX(-100%)`, `height: 0`) |

#### `useWideViewPort=true` (旧APK / Android WebView default)

| 項目 | 値 |
|------|-----|
| viewport幅の決定元 | viewport meta tagのwidth値、またはfallback |
| file://URL時の挙動 | **viewport meta tagが無視され980pxになる** |
| fallback値 | **980px** (Chromiumのレガシーデスクトップ幅) |
| `@media (max-width: 768px)` | **発動しない** (980 > 768) |
| ハンバーガー表示 | `display: none` (非表示) |
| サイドバー初期状態 | 常時表示 (デスクトップレイアウト) |

**file:// URL での特殊挙動 (Chromium既知動作)**:
- `useWideViewPort=true` かつ `file://` URL の場合、HTMLの `<meta name="viewport">` が処理されない
- 結果: viewport = 980px (デスクトップ幅) が強制される
- これは `file://` プロトコルのセキュリティコンテキストとChromiumのviewport処理パイプラインの問題

### CSS media query発動の結論

```
useWideViewPort=false → viewport=360-430px → @media(max-width:768px) 発動
useWideViewPort=true  → viewport=980px     → @media(max-width:768px) 不発動
```

---

## AC2: サイドバー2行問題の根因 (CSS計算値レベル)

### 問題の観察

- **症状**: ハンバーガーボタンタップでサイドバーがスライドインするが、「Classroom」(h2) と「📌 最新情報」(a)の2行のみ表示
- **スライド動作**: 正常 (`transform: translateX(-100%) → translateX(0)`)
- **残りコンテンツ**: 非表示 (宿題/試験/提出/PDFリンク等が見えない)

### 関連CSS (index.html L402-428)

```css
/* ベースルール (L32-43) */
.sidebar {
    position: fixed;
    top: 0; bottom: 0; left: 0;
    width: var(--sidebar-w);   /* 200px */
    height: auto;
    max-height: 100dvh;
    overflow-y: auto;
    padding: 16px 0 72px;      /* ← top: 16px, bottom: 72px */
    /* box-sizing: border-box  ← * { box-sizing: border-box } L9 */
}

/* メディアクエリ (L402-428) */
@media (max-width: 768px) {
    .sidebar {
        transform: translateX(-100%);   /* 非表示位置 */
        transition: transform 0.2s ease;
        width: 260px;
        height: 0;             /* ← 問題の起点: 明示的に0 */
        overflow: hidden;      /* ← overflow-x AND overflow-y を hidden */
    }
    .sidebar.open {
        transform: translateX(0);   /* スライドイン */
        height: 100dvh;        /* ← dvh依存: 根本問題 */
        overflow-y: auto;      /* ← overflow-y のみ上書き */
    }
}
```

### CSS計算値分析

#### `height: 100dvh` の問題

**`dvh` (dynamic viewport height) のサポート状況**:
- Chromium 108以降でサポート (Android 12+のシステムWebViewが対応)
- Android 9-11 の旧デバイスではWebViewが未対応の可能性あり

**`dvh` 非サポート時のCSS Cascade動作**:
```
宣言順 (同一メディアブロック内、同ファイル):
1. .sidebar    (specificity 0,1,0): height: 0
2. .sidebar.open (specificity 0,2,0): height: 100dvh  ← INVALID (非サポート時)

CSSルール: 無効な宣言値はなかったものとして扱われる。
→ .sidebar.openのheightが無効化 → cascade fallback先を探す
→ .sidebar (0,1,0): height: 0  ← これが適用される
```

**結果として**:
- `height: 0` (border-box) + `overflow-y: auto` + `position: fixed; top: 0; bottom: 0`
- border-boxでheight: 0かつpadding: 16px 0 72px → 理論上コンテンツ非表示

#### `overflow: hidden` と `overflow-y: auto` の分離問題

`.sidebar.open` が設定するのは `overflow-y: auto` のみ。

```
.sidebar (media): overflow: hidden → overflow-x: hidden, overflow-y: hidden
.sidebar.open:    overflow-y: auto  → overflow-y のみ上書き

結果:
  overflow-x = hidden  (from .sidebar media)
  overflow-y = auto    (from .sidebar.open)
```

`overflow-x: hidden` と `overflow-y: auto/scroll` の組み合わせは仕様上有効だが、
Chromiumの一部バージョンでは `overflow-x: hidden` がBlock Formatting Context(BFC)を生成し、
`overflow-y` の計算値に干渉する既知の動作がある。

#### 2行のみ表示される高さ推定

表示されている2項目の推定高さ:
```
h2 "Classroom":      padding(4+8) + font-size(14) × line-height(1.7) = 12 + 23.8 = 35.8px
a "📌 最新情報":      padding(5+5) + font-size(14) × line-height(1.7) = 10 + 23.8 = 33.8px
合計:                ~70px
```

この70pxが表示される理由の仮説:
- `box-sizing: border-box` + `height: 0` + `padding: 16px 0 72px` → ブラウザ実装によっては padding area が border-boxのheight: 0を「無視」して描画
- padding-top(16px) 領域 + α でコンテンツが滲み出る
- あるいは `position: fixed; top: 0; bottom: 0` が `height: 0` を上書きして自然高(~70px相当) を算出するケース

### 修正コード案

**修正対象**: `index.html` L410-414 (`.sidebar.open` CSS)

**案1: `dvh` → `vh` に変更 (推奨・互換性優先)**
```css
.sidebar.open {
    transform: translateX(0);
    height: 100vh;    /* dvh → vh: Chrome 4+対応, Android全バージョン対応 */
    overflow-y: auto;
}
```

**案2: `height` 指定をやめて `top/bottom` ピン留めに統一 (CSS設計的に正しい)**
```css
@media (max-width: 768px) {
    .sidebar {
        transform: translateX(-100%);
        transition: transform 0.2s ease;
        width: 260px;
        top: 0;
        bottom: 0;          /* ← 明示的に追加 */
        height: auto;       /* ← height: 0 を廃止 */
        overflow-y: hidden; /* ← transform で隠すのでheightではなく overflow制御 */
        visibility: hidden; /* ← 追加: コンテンツを完全に非表示 */
    }
    .sidebar.open {
        transform: translateX(0);
        height: auto;       /* ← 継承 */
        overflow-y: auto;
        visibility: visible;
    }
}
```

**推奨**: 案1 (`dvh` → `vh`) がリスク最小。案2はCSS設計が正しいが、`visibility` 追加による副作用確認が必要。

---

## 診断補足

現在のコードにはLogcat診断が組み込まれている (MainActivity.kt L116-133):
```
diagnostic:viewport=<W>x<H>; sidebarScrollHeight=<N>; sidebarClientHeight=<M>; ...
```

**確認すべき値**:
- `sidebarClientHeight` が70px程度 → height: 0のpadding leak仮説
- `sidebarClientHeight` が0 → overflow:hiddenで完全非表示(ただしopen後の再実行が必要)
- `sidebarClientHeight` が全高さ → overflow-xのBFC干渉仮説

実機でのLogcat確認または設定画面の「デバッグ viewport」表示でwebページロード直後の値を確認すること。

---

## 結論

| AC | 結果 |
|----|------|
| AC1 | `useWideViewPort=false` → viewport=360-430px → @media(max-width:768px) **発動**。`useWideViewPort=true` → file:// URL特殊挙動により980px → media query **不発動** |
| AC2 | 根本原因: `.sidebar.open { height: 100dvh }` の `dvh` 非サポート時のCSS cascade collapse。修正案: `height: 100vh` (案1) または `top/bottom/visibility` 方式 (案2) |
