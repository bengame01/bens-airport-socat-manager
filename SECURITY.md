# Security / 安全注意

本專案建議先用 **Private** GitHub Repository。

不要加入 VPS 真實設定（`/etc/bens-socat-manager`）、systemd runtime 規則（`bens-socat-*.service`）、root 的備份目錄、任何 API token、密碼或 SSH key。這些檔案可能透露私有目標地址與拓撲。

原版安裝腳本包含 `151.242.165.19` 與 `relay2.boosa285280.xyz` 作身份提示，係公網資訊，但仍應在公開儲存庫前評估。

程式可建立 TCP listener 並修改個別 systemd 單元；只可喺自己控制且已授權的主機部署。
