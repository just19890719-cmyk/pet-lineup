@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist "tools\openai_key.txt" if "%OPENAI_API_KEY%"=="" (
  echo 第一次使用：請在記事本貼上你的 OpenAI API 金鑰（只放一行），存檔後關閉記事本。
  type nul > "tools\openai_key.txt"
  notepad "tools\openai_key.txt"
)
"%LOCALAPPDATA%\Programs\Python\Python313\python.exe" tools\gen_ai_art.py %*
echo.
echo 完成後雙擊「執行遊戲.bat」就能看到新美術。
pause
