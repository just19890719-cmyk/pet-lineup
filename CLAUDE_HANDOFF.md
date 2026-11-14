# 萌寵排排站 — 交接檔

## 專案目標
Godot 4.7.2 製作的可愛動物「盲盒排序」益智遊戲（原創同類型玩法，不沿用參考影片的名稱與美術）。
非目標：排行榜、各動物叫聲。廣告與免廣告販售已進入規劃（目前只有假廣告流程）。（音效與背景音樂已於 2026-11-14 加入。）

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
  - 遊戲圖示 `icon.png`（512，ChatGPT 生成：貓咪、熊貓、兔子疊在一起，粉橘漸層底），`project.godot` 的 `config/icon` 指向它；網頁版的分頁圖示與加到手機主畫面的圖示由匯出自動產生。啟動與網頁載入畫面也改用這張圖（`boot_splash/image`，粉色底）。貼連結到通訊軟體時的預覽圖、標題、說明寫在 `export_presets.cfg` 的 `html/head_include`（og:image 指向線上的 `index.icon.png`）；通訊軟體會快取舊預覽，改了不會馬上換。
  - 「開發」按鈕只在除錯版顯示（`OS.is_debug_build()`），匯出的正式版看不到。

- 2026-11-14 音效與音樂（全部由 `tools/gen_audio.py` 用程式合成，輸出 `assets/audio/*.wav`，無外部素材）：
  - 14 個音效：pick 拿起、drop 放下、deny 不能放、flip 翻牌、clear 整欄消除（連續消除音調逐次升高，變數 `combo`）、win 過關、button 按鈕、undo 撤回、slot 暫存格、unlock 解鎖、stuck 卡住、pop 對話框、tick 開局掉落、step 教學說明步驟。
  - bgm：8 小節循環曲（約 18 秒），音量 -12dB。
  - 程式入口：`_init_audio()`、`_play(名稱, 音調, 音量)`、`_tap_sound()`；改音色只要改 `gen_audio.py` 重跑再匯入。
  - 「設定」按鈕（遊戲左上、開始畫面右上）可分別開關音效與音樂，存檔鍵 `sfx_off`、`music_off`。
  - **未驗證：我無法實際聽聲音**，只確認 14 個音效與音樂都有載入、音樂在播放、循環點正確、網頁版無錯誤。音色好不好聽、音量平衡要人耳確認。
  - 結束時終端機會出現「resources still in use at exit」，是強制結束時的殘留提示，不影響遊戲。

- 2026-11-14 關卡延伸到 100 關，並改成保證有解：
  - 關卡資料在 `scripts/level_data.gd`（由 `tools/gen_levels.py` 產生，勿手改）。做法：隨機發牌 → 解題程式（深度優先搜尋）在「只用開局開放的暫存格、不解鎖」的條件下確認解得開才收錄。舊的 `LEVELS` 表與純隨機發牌已移除。
  - 難度曲線是**純直線**（使用者 2026-11-14 指定，不要魔王關與喘息關）：`gen_levels.py` 的 `target(L)` 從第 1 關 25 分直線升到第 100 關 200 分；難度分數 `score()` = 解法步數 ×（1 + 0.5 × log10(搜尋量 ÷ 步數)）。每關在預定盤面大小 `nominal(L)` 附近發約 60 個盤面，全部解過後挑最貼近目標的。結果：平均偏差 2.3 分，最大 14.2 分（第 86 關）；偏差超過 6 分的有第 46、61、76、84、86、92、96 關。逐關數據在 `tools/level_report.json`。
  - 盤面大小範圍：動物種類 4→7、欄數 5→8、每欄格數 6→12、開局翻開比例 40%→8%；開放暫存格第 1–60 關 3 格、61–85 關 2 格、86–100 關 1 格（另有 1 格可免費解鎖）。
  - 遊戲端：`slot_open`（開局開放格數）、`slot_n`（顯示格數 = 開放 + 1）；暫存格列會依格數置中。
  - 第 100 關過關顯示「恭喜全破！」；第 101 關起循環使用第 51–100 關的盤面，換一批動物、每輪左右對調。
  - 開發面板新增「跳 10 關」「跳到第 100 關」；「換一個隨機盤面」是同一批方塊重新洗牌，**不保證有解**。
  - 測試參數：`--level=N`、`--check-levels`（逐關載入 150 關檢查數量，結果 bad=0）。
  - 已驗證：100 關都由解題程式解過；150 關載入檢查通過；第 10、40、61、86、100 關截圖版面正常。未驗證：真人實際玩的難度感受（解題程式看得到所有方塊，玩家看不到問號，體感會比數字難）；第 86 關以後只有 1 格暫存格可能偏難。

- 2026-11-14 求救道具與廣告流程（**廣告是假的**，3 秒倒數畫面 `_fake_ad()`，還沒接任何廣告服務或付款）：
  - 規則常數集中在 `main.gd`「求救道具與廣告」區塊開頭：`HONEYMOON_LEVELS=10`（前 10 關撤回無限、解鎖免費、不跳插頁）、`UNDO_FREE_MID=3`（第 11–60 關每關免費撤回）、`UNDO_FREE_LATE=5`（第 61 關起）、`UNDO_PER_AD=5`、`REVEAL_PER_USE=3`、`AD_EVERY_WINS=3`、`AD_MIN_GAP_MS=120000`。
  - 撤回：用完後按鈕變「補撤回」，跳對話框選看廣告補 5 次、免費重新開始或不用。重新開始永遠免費且會補滿次數。
  - 解鎖暫存格：第 11 關起要看廣告（`_request_unlock()`）。
  - 新道具「翻問號」：隨機翻開 3 個問號；前 10 關每關免費 1 次，之後看廣告。底部按鈕改成三顆（撤回、翻問號、重新開始）。
  - 插頁廣告 `_next_level()`：第 11 關起，過關後每 3 關最多一次、間隔至少 2 分鐘、這一關主動看過廣告就不跳。
  - 免廣告 `no_ads`（存檔鍵 `no_ads`）：不跳插頁、求救直接領。目前只有開發面板的「切換免廣告」能開，**沒有購買流程**。
  - 開發面板新增：重置求救次數、切換免廣告、模擬插頁廣告。測試參數：`--ask-undo`、`--ask-unlock`、`--fake-ad`。
  - 已驗證：各對話框與假廣告畫面截圖、啟動測試無錯誤。未驗證：實際點擊完整流程（看完廣告後獎勵是否入帳只看過程式邏輯）、次數是否合理要真人試玩。
  - 還沒做：「提示一步」道具、真的廣告與付款（需做成安卓或蘋果應用程式）、第 101–300 關的新盤面（規劃：維持第 70–100 關難度區間起伏）。

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
- 第 1–100 關保證有解（見上方）；玩家仍可能因為看不到問號而走進死路，靠無限撤回與重新開始救回。
- 尚未在實機手機觸控測試；只處理滑鼠事件（觸控會由 Godot 模擬成滑鼠）。
- 2026-11-14 已修：盤面改為在盤面區域內垂直置中（`board_bottom`）；撤回停用改深灰底白字深灰框；「解鎖」格改深色底、字放大到 18。只截圖驗證過第 1 關，第 2–7 關（欄位較高）尚未逐關看圖。
- 質感改版已截圖驗證：開始畫面、第 1 關、教學七步自動跑完到「學會了！」、過關對話框與彩帶、開發面板。未驗證：實際用手點的手感、動畫流暢度（截圖看不出）、第 2–7 關版面。
- 「完成！」粉紅字在粉色天空上對比偏低；按鈕白字配橘框在小字級（開發面板）不太清楚。
- 右上角「開發」按鈕上架前要隱藏；提示文字只有 16 級，手機上可能偏小。

## 下一個最安全任務
用開發面板逐關跳到第 2–7 關截圖，確認置中後沒有蓋到提示文字或暫存格；再做實機觸控測試。
