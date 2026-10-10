# Github Actions提供的免費虛擬機器(體驗/臨時)

你幾乎可以在這裏領取免費的MacOS, Windows 10以及Ubuntu的虛擬機\
:warning: 溫馨提示: 若果你發現某個系統啟動的時候操作發生問題, 敬請在[這裏](https://github.com/cybershadowvps/FreeVPS/issues)建立問題, 並且請保持更新你的複製專案,
按[此處](#%E6%9B%B4%E6%96%B0%E4%BB%A3%E7%A2%BC)進行操作. 

## 屏幕截圖
<details>
    <summary>Windows 10</summary>
<br>
    
- Windows 10 系統版本
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/268600af-c8b9-47cf-b5dd-d1c1ed6d9ce9.png">

- Windows 10 任務管理器
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/0cf98258-a6fe-46bb-ac9a-ee4bb3037e3a.png" >

- Windows 10 裝置管理器
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/d32cf285-5ecf-4cce-a52a-5cb54fb130c7.png">

- Windows 10 裝置規格
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/e1852b80-d550-44f3-b619-86ea82902bb4.png">
    
</details>

<details>
    <summary>Ubuntu (SSH 遠程指令版本)</summary>
<br>

1. 點擊 **Run Workflox**
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/96644176-D760-47D4-BED2-C47E62A6763F.png" >

2. 複製 SSH 連結
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/0F804C5F-FE8F-45FA-9720-F91F212597DF.png" >

3. 從你的電腦終端機或者SSH客戶端中輸入你的SSH連結及登入方式
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/78FE6C5A-7270-4986-AB8F-57EC4C9B4F44.png" >

請緊記輸入你所設定的Linux系統密碼

4. 輸入 **sudo -i** 以獲取超級用戶, 並且輸入你的密碼
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/E5527744-1ED1-4550-8867-EF4EC76D6895.png" >

5. 享受你的免費6小時Linux虛擬機
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/E6E9EA63-AC24-4FDB-AAF9-8B509658440A.png" >

</details>

<details>
    <summary>Ubuntu (桌面版版本)</summary>
<br>

- 桌面截圖
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/4EB9C2FF-9D03-4998-A440-D7716A0F7CD0.png" >

- Linux Chrome瀏覽器
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/09F0A4CF-9B30-44CD-8DC4-139D03DFC2CC.png" >

- 任意下載你喜歡的Linux軟件
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/A0886141-DF1E-4379-88E7-F00EDAD87D0E.png">

</details>

<details>
    <summary>MacOS 蘋果系統</summary>
<br>

- 桌面屏幕截圖
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.32.41%20AM.png" >

- 設定
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.32.21%20AM.png" >

- 內存
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.32.58%20AM.png" >

- 硬盤儲存空間
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.33.18%20AM.png" >

- 預先下載的軟件
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.34.10%20AM.png" >

</details>

## 機器規格:
以下規格為**公開**儲存庫中的標準 GitHub 托管運行器（在公開儲存庫中免費且不限時數）:

### Windows 及 Linux:
- 4-核心 vCPU
- 16 GB 內存
- 14 GB SSD硬盤儲存空間
### macOS (`macos-latest`, Apple 晶片)
- 3-核心 vCPU (Apple M1)
- 7 GB 內存
- 14 GB SSD硬盤儲存空間

> :warning: 以上規格適用於**公開** Fork。若你的 Fork 是**私有**的，Linux/Windows 運行器只有 2-核心 vCPU / 8 GB 內存，並會消耗每月 2,000 分鐘的免費 Actions 額度（Windows 計 2 倍、macOS 計 10 倍分鐘數）。

## 配置:

1.Fork此項目

2.轉到您的項目頁面，單擊“Settings”並轉到“Secrets”，然後單擊“New Secrets”以在下面添加這些Secrets：

Secrets 名稱 | 用途 | 備註
----- | ----- | -----
`MAC_REALNAME` | 對於MacOS用戶顯示名稱 | 輸入您想要的任何名稱
`MAC_USER_PASSWORD` | 對於MacOS系統管理員密碼 | 輸入您想要的任何密碼
`NGROK_AUTH_TOKEN` | 用於**ngrok**隧道 | 轉到ngrok網站，然後從 https://dashboard.ngrok.com/get-started/your-authtoken 復制API密鑰。：warning：ngrok 免費方案的 TCP 隧道（SSH/RDP/VNC）需要先完成信用卡驗證。
`VNC_PASSWORD` | 輸入VNC遠程認證的登錄密碼 | 輸入您想要的任何密碼
`WINDOWS_USER_PASSWORD` | 對於Windows 10 RDP登錄密碼 | 輸入您想要的任何密碼
`LINUX_USERNAME` | 對於linux系統用戶名 | 輸入您想要的任何名稱
`LINUX_USER_PASSWORD` | 對於Linux Shell和root密碼 | 輸入您想要的任何密碼
`LINUX_MACHINE_NAME` | 對於Linux系統計算機名稱 | 輸入您想要的任何名稱
`CHROME_HEADLESS_CODE`(自選) | 使用Google Remote遠程處理Linux桌面 | 從[這裡](https://remotedesktop.google.com/headless)復制代碼並使用您的Google帳戶登錄，然後將代碼複製到“Debian Linux”空白下方。：warning：每個代碼只能使用一次，當您使用一個代碼時，會生成另一個代碼。
`GOOGLE_REMOTE_PIN` | Google Remote Desktop 的連接 PIN | 輸入任何不少於6位的 PIN，連接 Linux 桌面時需要輸入它

## 部署並運行

<details>
    <summary>MacOS</summary>
<br>
    
1. 轉到`Actions`標籤，然後選擇系統工作流程之一。

2. 點擊`Run Workflow`左側的按鈕`This workflow has a workflow_dispatch event trigger`行列.

3. 等幾分鐘.

4. 前往 https://dashboard.ngrok.com/status/tunnels 並檢查是否有一個在線隧道在運行.

5. 複製鏈接 (**不帶tcp://**) 並轉到VNC Viewer（下載並安裝），輸入鏈接以連接從網站複製的區域。

6. 在用戶名`koolisw`和您輸入的`VNC_PASSWORD`的密碼中填寫這些登錄信息。

7. 享受！

</details>

<details>
    <summary>Windows 10</summary>
<br>

1.首先，啟動Windows 10系統的操作。\
2.其次，轉到 https://dashboard.ngrok.com/status/tunnels ，檢查是否有一個在線隧道在運行。\
3.轉到Windows遠程桌面連接應用程序或Microsoft遠程桌面軟件以連接到Windows 10 VPS。\
4.享受！

</details>

<details>
    <summary>Linux</summary>
<br>

1.首先，開始Linux System的操作。\
2.其次，從控制台複製鏈接\
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/0F804C5F-FE8F-45FA-9720-F91F212597DF.png" >
3. 轉到MacOS Terminal或Windows CMD Terminal或ssh客戶端，然後輸入提供的命令。 然後輸入您的ssh密碼。
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/78FE6C5A-7270-4986-AB8F-57EC4C9B4F44.png" >
4. ENJOY!

</details>


- Reminders:
:warning: 連接期間請不要停止 workflow。虛擬機（及您的遠程會話）只會存活至 GitHub Actions 的 **6 小時**限制，之後所有內容都會被刪除。

:warning: 連接期間請不要在虛擬機上安裝系統更新（macOS、Windows 等），它們可能會重新啟動並中斷您的遠程進程。

## 更新代碼:
<details>
    <summary>單擊此處展開</summary>
<br>

要把本專案的最新版本同步到你的 Fork:

**方式 A（在 GitHub 上）:** 打開你的 Fork，點擊分支名稱旁的 **Sync fork** 按鈕，然後按 **Update branch**。

**方式 B（在終端機中）:**

```bash
git remote add upstream https://github.com/cybershadowvps/FreeVPS.git   # 僅第一次需要
git fetch upstream
git merge upstream/main      # 或: git rebase upstream/main
git push
```

你的 Fork 現在已經是最新版本了。

</details>

## 限制：
1.每個虛擬機的運行時間最多只能有 `6` 小時（這是 GitHub 托管運行器的硬性執行限制）。如果虛擬機達到此限制，它將終止並清除所有內容。\
2.不建議您將一些重要且敏感的文件保存到每台計算機上，否則所有文件都將被刪除並且無法撤消。\
3.由於我們使用的是 `ngrok`，免費方案同時最多允許 **3** 個在線隧道，因此您最多可以同時運行這三個系統中的三個。：warning：免費方案的 **TCP 隧道（SSH/RDP/VNC）需要信用卡驗證**，並限制為每分鐘 100 個 TCP 連接、每月 5,000 個 TCP 連接及 1 GB 流量（詳見 https://ngrok.com/pricing）。\
4.不建議從任何網站（就像`Google`或`Microsoft`）一樣登錄任何帳戶，因為VNC連接未加密並且很容易被其他人訪問。\
5.**公開**儲存庫的 Actions 免費且不限時數；**私有** Fork 每月只有 2,000 分鐘免費額度（Linux 計 1 倍、Windows 計 2 倍、macOS 計 10 倍分鐘數）。\
6.GitHub Free 方案最多同時運行 **20** 個作業（其中最多 **5** 個可以是 macOS 作業）。

##  建議和最佳技巧：
- 如果您面對來自`MacOS`或`Windows`的緩慢而緩慢的遠程控制體驗，則可以使用`Google Remote Desktop`或`Microsoft Remote Control`來獲得更快，更流暢的遠程控制。\
- 我們強烈建議您**fork**該項目，以更改系統的用戶名和其他顯示名稱。
