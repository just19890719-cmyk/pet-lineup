# 萌寵排排站 — 交接檔

## 專案目標
Godot 4.7.2 製作的可愛動物「盲盒排序」益智遊戲（原創同類型玩法，不沿用參考影片的名稱與美術）。
非目標：排行榜、廣告、音效。

## 目前階段
原型（一個完整循環可玩：選欄 → 移動 → 翻牌 → 整欄消除 → 過關／卡住）。

## 最新完成工作
- `scripts/main.gd`：完整玩法、7 個關卡、無限撤回、第 4 格暫存格免費解鎖、存檔、過關／卡住對話框、開發面板。
- `scripts/animal_art.gd`：12 種動物（有圖片就讀圖，沒圖就用程式畫的暫代圖）。
- 已產生整套美術並自動套用（2026-11-14 改為 ChatGPT 網頁版生圖：動物總表與星光用洋紅底、方塊用綠底，去背後切圖縮放；舊的程式繪製版備份在 `assets/_backup_20261114_1630/`）：
  - 12 張動物圖 `assets/animals/<key>.png`（cat dog panda rabbit bear pig frog chick fox koala lion cow，透明背景，單張優先於 sheet）
  - `assets/ui/tile_front.png`、`tile_hidden.png`、`background.png`、`assets/fx/sparkle.png`

- GPT 自動生圖工具：`AI生成美術.bat` → `tools/gen_ai_art.py`（gpt-image-1，透明背景，完整獨立提示詞，舊圖自動備份到 `assets/_backup_<時間>/`，可只生成指定項目如 `cat dog`）。金鑰放 `tools/openai_key.txt` 或環境變數 `OPENAI_API_KEY`（已列入 .gitignore）。此工具保留備用、從未實際呼叫（沒有金鑰）；目前的美術是直接操作使用者 Chrome 裡的 ChatGPT 網頁生成，完整提示詞與此檔內的相同（僅把「透明背景」改成純色底）。

- 2026-11-14 質感改版（`scripts/main.gd` 局部加入，玩法規則未動）：
  - 開始畫面 `_show_title()`：標題字、動物主視覺、綠色「開始遊戲」、進度說明；玩過教學後多一顆「玩法教學」。
  - 新手教學 `_start_tutorial()`：固定 4 欄小盤面、7 步手指引導（步驟表在常數 `TUT`），暗幕只亮出該點的欄，可按「跳過」。完成或跳過後存 `tutorial_done`。
  - 動畫：開局方塊掉落、落地壓扁、翻牌翻轉、選取上下浮動、消除光環與更多星光、過關彩帶、對話框彈出、按鈕按壓縮放。
  - 介面圖（ChatGPT 網頁版生成，洋紅底去背）：`assets/ui/` 的 logo、hero、btn_orange、btn_green、btn_grey（已裁成 80x60 精簡版，左右各 36 不變形）、hand、slot、slot_lock、ribbon、panel（320 寬，九宮格邊距左右 60 上 44 下 30）、background（草地場景）。缺圖會自動退回程式繪製。
  - 開發面板新增：回開始畫面、重看新手教學、灑彩帶。
  - 測試用啟動參數（接在 `--` 後）：`--skip-title`、`--tutorial`、`--tut-step`、`--tut-auto`（自動點完教學）、`--win`、`--dev`。注意 `--win` 與 `--tut-auto` 會寫入真的存檔，測完要把 `%APPDATA%\Godot\app_userdata\萌寵排排站\save.cfg` 改回去。

- 2026-11-14 網頁版與 GitHub：
  - 版本庫 `just19890719-cmyk/pet-lineup`（公開），GitHub Pages 用 `main` 分支的 `docs/`，遊玩網址 https://just19890719-cmyk.github.io/pet-lineup/
  - 重新匯出：`Godot --headless --path <專案> --import`，再 `--export-release "Web" docs/index.html`，然後提交並推送。網頁匯出範本裝在 `%APPDATA%\Godot\export_templates\4.7.2.stable\`（只裝了 web_nothreads 兩個檔）。
  - 字型 `assets/fonts/NotoSansTC-SemiBold-subset.ttf` 只含程式裡出現過的字；**新增或修改遊戲文字後要重跑 `tools/subset_font.py`**（需要 fonttools 與完整的 NotoSansTC 可變字型），否則網頁版新字會缺字（電腦版會退回系統字型）。
  - 網頁版畫面比例用 `window/stretch/aspect.web="keep"`（寬螢幕左右留邊，不裁切）。
  - 「開發」按鈕只在除錯版顯示（`OS.is_debug_build()`），匯出的正式版看不到。

## 重要檔案
- `main.tscn`、`project.godot`
- `scripts/main.gd`、`scripts/animal_art.gd`
- `執行遊戲.bat`、`開啟編輯器.bat`
- 美術放置位置（已有檔案；直接用同檔名覆蓋即可替換）：
  - `assets/animals/<key>.png`（單張透明 PNG，優先使用）
  - `assets/animals/animals_sheet.png`（選用）（4x3，洋紅 #FF00FF 底，順序：貓 狗 熊貓 兔 / 熊 豬 青蛙 小雞 / 狐狸 無尾熊 獅子 乳牛）
  - `assets/ui/tile_hidden.png`、`assets/ui/tile_front.png`、`assets/ui/background.png`
  - `assets/fx/sparkle.png`

## 驗證方式與結果
- `Godot_v4.7.2-stable_win64_console.exe --headless --path <專案> --quit-after 180`：無 ERROR / SCRIPT ERROR。
- `--write-movie` 擷取第 1 關畫面：新美術正確載入，動物無裁切、無灰底，文字無溢出。

## 已知風險與未測部分
- 隨機發牌不保證有解（靠暫存格、無限撤回、重新開始緩解）。
- 尚未在實機手機觸控測試；只處理滑鼠事件（觸控會由 Godot 模擬成滑鼠）。
- 2026-11-14 已修：盤面改為在盤面區域內垂直置中（`board_bottom`）；撤回停用改深灰底白字深灰框；「解鎖」格改深色底、字放大到 18。只截圖驗證過第 1 關，第 2–7 關（欄位較高）尚未逐關看圖。
- 質感改版已截圖驗證：開始畫面、第 1 關、教學七步自動跑完到「學會了！」、過關對話框與彩帶、開發面板。未驗證：實際用手點的手感、動畫流暢度（截圖看不出）、第 2–7 關版面。
- 「完成！」粉紅字在粉色天空上對比偏低；按鈕白字配橘框在小字級（開發面板）不太清楚。
- 右上角「開發」按鈕上架前要隱藏；提示文字只有 16 級，手機上可能偏小。

## 下一個最安全任務
用開發面板逐關跳到第 2–7 關截圖，確認置中後沒有蓋到提示文字或暫存格；再做實機觸控測試。
