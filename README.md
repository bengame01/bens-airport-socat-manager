# Ben's Airport — Socat SSH Manager

**純 SSH 終端版 Socat TCP/IPv4 中轉管理工具**。無網站、Nginx、Docker、資料庫、Web API 或 XBoard 依賴。

> 此儲存庫保存 2026-11-19 在日本 `relay2` 使用的 SSH 安裝腳本及由該安裝腳本生成的管理程式版本。它是一份**程式碼備份**，不是伺服器即時設定同步，亦不會自動修改任何 VPS。

## 功能

- 新增 TCP/IPv4 中轉：本地 `0.0.0.0:PORT` → 目標 `HOST:PORT`。
- 列出由本工具管理的中轉和 systemd 狀態。
- 修改目的地（修改前備份，失敗時嘗試回復）。
- 啟動／停止／重新啟動個別中轉。
- 刪除指定中轉（刪除前備份）。
- 檢查本地監聽端口、查看 systemd 日誌、手動備份。
- 互動確認及 Dry Run 預覽。

**現時限制：只有 TCP/IPv4，未支援 UDP、IPv6、流量計數或自動健康切換。**

## 原始碼

| 檔案 | 用途 |
|---|---|
| `relay2-socat-ssh-installer.sh` | Debian 13 安裝及嵌入式 manager 安裝來源 |
| `socat-manager` | 從安裝腳本逐字抽出嘅 manager 原始碼；方便 GitHub 閱讀與審查 |
| `tests/check-source.sh` | 語法檢查及 manager／installer 內容一致性檢查 |
| `.github/workflows/check.yml` | GitHub Actions 自動語法及同步檢查 |
| `.gitignore` | 防止部分敏感檔案被加入 Git |

> **單一安裝來源提醒：** 原版安裝器會將內嵌 `MANAGER` 區塊寫成 `/usr/local/sbin/socat-manager`。如果修改獨立的 `socat-manager`，要同步更新安裝器內嵌區塊，否則再次安裝會用返舊版本。`tests/check-source.sh` 會檢查兩者一致。

## 安裝（Debian 13）

**操作前核對 VPS 身份，先備份及 Dry Run。** Repo 已包含原本安裝器；請先讀清楚程式碼。

```bash
# 只檢查，不修改
sudo bash relay2-socat-ssh-installer.sh --dry-run

# 核實結果後由操作者自行批准
sudo bash relay2-socat-ssh-installer.sh --install

# 開啟純 SSH 管理選單
sudo socat-manager

# 唯讀查看中轉列表
sudo socat-manager --list
```

正式安裝會執行 `apt-get update`、`apt-get install -y socat iproute2`，如舊 manager 存在會先備份，然後寫入 `/usr/local/sbin/socat-manager`。**安裝程序本身不會新增或啟動任何中轉端口**，不會修改防火牆、DNS、Nginx、XBoard。

## 中轉規則與儲存位置

| 位置 | 說明 |
|---|---|
| `/usr/local/sbin/socat-manager` | 已安裝管理程式 |
| `/etc/bens-socat-manager/` | 逐端口的中轉設定（**切勿上傳 GitHub**） |
| `/etc/systemd/system/bens-socat-*.service` | 管理器建立的 systemd units（實際端口及目的地可能敏感） |
| `/root/bens-socat-backups/` | 本機備份（**切勿上傳 GitHub**） |

建立個別轉發時，程式會預覽端口/目的地，並要求輸入 `YES`，才會寫入設定並啟用 `bens-socat-PORT.service`。

## 測試

```bash
bash tests/check-source.sh
```

## 安全與私隱

- 建議 **GitHub Private repository**。原版安裝器文字中包含日本 VPS 的網域及公網 IP；公開之前應自己檢查。
- **請勿上傳** token、密碼、私人金鑰、`.env`、Komari 資料、正在用的系統設定、機密 IP 名單或 `/root` 備份。
- 此工具會於本機開啟 `0.0.0.0:PORT` TCP 監聽，新增前必須考慮防火牆和暴露面。
- GitHub 程式碼與 VPS 正在執行的配置互不自動同步；`git push` 或 GitHub 編輯**不會**自動部署。
- 個別 systemd service 的開始、停止、修改及刪除，可能影響連線；請於維護時段執行。

## 版本狀態

- `v1.0.0-source-snapshot` — 2026-11-19 程式碼快照，未經 GitHub 發佈；Debian 13 安裝已由使用者終端截圖確認，尚未在 GitHub CI 執行。
- 尚未選擇開源授權；請保留為私人儲存庫，除非已決定公開授權及敏感資訊處理。
