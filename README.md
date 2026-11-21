# 眼動鼠之賽車 https://achir1015.github.io/eyemouse-racer/online/
https://achir1015.github.io/eyemouse-racer/
<img width="1920" height="1001" alt="image" src="https://github.com/user-attachments/assets/02dc61c4-c160-4b54-b2d7-0363a4aee3ff" />
<img width="1920" height="1001" alt="image" src="https://github.com/user-attachments/assets/dd2fb6b7-6eea-4429-82f6-2f64cc680130" />

用眼睛開賽車的 **3D 駕駛遊戲**（Godot 4.7.2，由寶島卡車專案延伸）：只要一台網路攝影機，眼睛和轉頭就能控制鏡頭，看著按鈕就能開車。

- **內建攝影機眼動追蹤（EyeCam）**：參考 [UnitEye](https://github.com/wgnrto/uniteye)（MuC '24）的流程自行實作——MediaPipe 臉部特徵點＋虹膜＋eyeLook 係數＋頭部姿勢 → 每人校正（嶺迴歸，含二次項、轉頭階段）→ One Euro 濾波 → 眨眼時維持視線。影像只在本機處理。
- **頭眼合併控制鏡頭**：頭轉一點、鏡頭轉多一點；眼睛看畫面邊緣再多轉；紫色視線圈顯示你看的位置。
- **大鵬灣國際賽車場**（原創賽道配置）：5 位 AI 對手、起跑燈、圈速、名次、路緣石、碎石區、看台、維修區；可選圈數、對手強度、夜間賽、雨戰。
- **GT 賽車駕駛艙**：數位儀表（換檔燈、檔位、圈速）、防滾籠、導航平板、後照鏡；可調視野廣角。
- **台灣地圖**：台北、國道一號、日月潭、高雄、太魯閣、墾丁、駕訓場；交通標誌識別、駕訓班、考驗挑戰。
- **小柯 AI 自駕**：一般道路照號誌行駛；賽車場跑賽車線、會超車。
- 語音動態教學、程式內更新；也可連線眼動鼠（Tobii，127.0.0.1:47961）。

## 結構
- `eyecam/eyecam.py`：攝影機追蹤小程式（PyInstaller 打包成 EyeCam.exe；遊戲自動啟動、關閉即結束；127.0.0.1:47971）。
- `scripts/eyecam.gd`（連線、特徵、嶺迴歸、One Euro）、`scripts/calib.gd`（校正畫面）、`scripts/race.gd`（比賽）、`scripts/circuit.gd`（賽道佈置）。

## 建置與測試
- `bash tools/build_win.sh` → `../build/release/EyeMouseRacer-Setup.exe`
- `-- --test --screen=drive --map=dapeng --vehicle=race --ap --laps=1 --drive-secs=150`
- `-- --test --screen=calib --fake-eyecam`

系統開發：吳玉柱 先生 與 Claude AI Opus 5.5
