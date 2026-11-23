# App Store 上架清單 — TokenVault（macOS + iOS）

更新於 2026-10-20。每一項標「已具備 ✅」或「待做」。

## 一、程式與 bundle

| 項目 | iOS | macOS |
|---|---|---|
| Bundle ID | `dev.wahsun.tokenvault` | `org.wahsun.tokenvault` ⚠️ 見決策 |
| 版本 / build | 1.0 (1) | 1.0 (1) |
| 最低系統 | iOS 18.0 | macOS 14.0 (arm64) |
| 分類 | developer-tools | developer-tools |
| Face ID 用途說明 | ✅ | ✅ |
| 加密出口合規 | ✅ `ITSAppUsesNonExemptEncryption=false`（僅標準 AES，屬豁免） | ✅ |
| App Sandbox | 不適用 | ✅ sandbox + user-selected files + network.client |
| Hardened Runtime | 不適用 | ✅ `--options runtime` |
| 第三方依賴 | 0 | 0 |
| 隱私清單 `PrivacyInfo.xcprivacy` | ✅ 已進 bundle | ✅ 已進 `Contents/Resources` |
| 追蹤 / 收集資料 | ✅ 無 | ✅ 無 |
| 網路 | 僅在使用者按下時連健康檢查 API | 同 + GitHub 備份 |
| 帳號系統 | 無 | 無 |

驗證指令：

```bash
codesign -dvvv --entitlements - .build/TokenVault.app   # macOS
codesign -dv --verbose=2 <iOS device build>/TokenVault.app
ls TokenVault.app/PrivacyInfo.xcprivacy                 # 必須存在
```

## 二、本次審計修掉的問題

| # | 問題 | 嚴重度 | 處理 |
|---|---|---|---|
| 1 | 兩端都缺 `PrivacyInfo.xcprivacy` → 上傳會被拒（ITMS-91053） | 🔴 阻擋上架 | 已補並確認進 bundle |
| 2 | macOS「iCloud 同步」是假功能：沙盒下不是真的 iCloud Drive，`useICloud` 只改標籤文字 | 🔴 功能誤導 | 移除開關，改本機儲存 + 匯出/匯入，README 更正 |
| 3 | 到期提醒預設開，但只有手動撥動才請求通知權限 → 提醒永遠不出現 | 🟠 功能失效 | 解鎖後主動請求一次 |
| 4 | `EncryptionService.reEncrypt` 死碼含 3 個強制解包（舊明文資料會 crash） | 🟠 崩潰風險 | 刪除（無呼叫點） |
| 5 | macOS「儲存位置」跟著假開關顯示 iCloud Drive | 🟡 文案 | 改「本機」 |
| 6 | 兩端都沒有隱私政策入口 | 🟡 審查觀感 | 兩端都加 `privacy.wahsun.org` |

## 三、上架前還要做的

### 0. iCloud 容器（已完成 ✅）

已用 Xcode 自動簽名建立，不需要你進後台點：

| 項目 | 值 |
|---|---|
| 容器 | `iCloud.dev.wahsun.tokenvault`（Production + Development 兩種環境） |
| App ID | `dev.wahsun.tokenvault`（`MAA6W8AG5P`），iCloud / CloudDocuments 已開啟 |
| Provisioning profile | `iOS Team Provisioning Profile: dev.wahsun.tokenvault`，含 `icloud-container-identifiers`、`ubiquity-container-identifiers`、`ubiquity-kvstore-identifier = MAA6W8AG5P.*` |
| 觸發方式 | `xcodebuild -allowProvisioningUpdates DEVELOPMENT_TEAM=MAA6W8AG5P` |

驗證指令（任何人可重跑，看 profile 裡是否真的有容器）：

```bash
xcodebuild -project iOS/TokenVault.xcodeproj -scheme TokenVault \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/tv-prov \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=MAA6W8AG5P build

security cms -D -i "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/<uuid>.mobileprovision" \
  | plutil -extract Entitlements json -o - - | grep -i icloud
```

兩端的 entitlements 都指向同一個容器：

```
com.apple.developer.icloud-container-identifiers = iCloud.dev.wahsun.tokenvault
com.apple.developer.icloud-services             = CloudDocuments
com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)$(CFBundleIdentifier)
```

> 本機 `build.sh` 會自動剝掉 `com.apple.developer.*` 再 ad-hoc 簽名，因為 ad-hoc 簽章帶這些 entitlement 會被 AMFI 直接 `Killed: 9`。真正上架的簽名請用 `publish.sh` / Xcode Archive（保留完整 entitlements）。

### 1. 決定 Bundle ID（已定案）

兩端統一 `dev.wahsun.tokenvault`（通用購買）。macOS 已改完並驗證。

### 2. macOS 截圖（已完成）

3 張 `2880×1800` 在 `~/Desktop/TokenVault-AppStore/macos/`：

| 檔案 | 內容 |
|---|---|
| `01-main.png` | 主視窗（側欄 + 8 個 Token 卡片） |
| `03-lock.png` | 鎖定畫面（Touch ID） |
| `04-about.png` | 關於面板 |

產法（可重跑）：

```bash
scripts/build-macos.sh
.build/TokenVault.app/Contents/MacOS/TokenVault --capture-shots /tmp/tv-macshots
swift scripts/make-macos-store-shots.swift /tmp/tv-macshots ~/Desktop/TokenVault-AppStore/macos
```

擷取走 App 自己的 `--capture-shots` 模式（`cacheDisplay` 真實像素，含材質與陰影，不需要螢幕錄製權限），輸出目錄會被沙盒限制在容器內；再合成紫黑底＋標題的 2880×1800。

限制：macOS 26 的 `TabView` 分頁標籤在離屏擷取時會渲染成白色膠囊，所以設定／說明這兩個 TabView 視窗目前不列入商店圖。iOS 的 6 張 `1320×2868` 已完成，在 `~/Desktop/TokenVault-AppStore/`。


### 3. App Store Connect 建檔

- 名稱：TokenVault（被佔用時 `TokenVault — API 密鑰保險庫`）
- 副標題：`開發者的 API 密鑰保險庫`
- 分類：Developer Tools（主）、Utilities（次）
- 價格：免費、無內購
- 年齡分級：4+
- 隱私政策：<https://privacy.wahsun.org/>
- 支援：<https://wahsun.org>
- 版權：WAHSUN
- 關鍵字：api key manager, developer tools, secrets, token, aes, face id, jwt, 密鑰
- 審查備註：不需帳號；資料只存本機並以 AES-256-GCM 加密；健康檢查僅在使用者按下時連線，只帶使用者自己的 token。

### 4. 功能宣稱要與程式一致

iCloud Drive 雙向同步已實作並在真機驗證（`vault.tvsync` 以 AES-256-GCM 加密、金鑰存於 iCloud 鑰匙圈、逐 token 合併、刪除以 tombstone 傳播）。App Store 版本以正確 entitlements 簽名，可以宣稱同步；但**不可**宣稱任何自有雲端伺服器。注意：adhoc 簽名的本地／Release 版無法帶 iCloud entitlements，該版本會顯示「iCloud 不可用」，描述要區分這兩者。

建議描述：

> 每個值以 AES-256-GCM 加密後才寫入磁碟，金鑰存放於裝置鑰匙圈；可選用你的 iCloud Drive 在 Mac 與 iPhone 之間同步（內容加密、金鑰在你的 iCloud 鑰匙圈）。支援 20 種服務商自動辨識、環境標籤、JWT 解碼、金鑰產生器、Token 健康檢查、重複密鑰掃描，以及本機稽核日誌。

### 5. 每次發版自檢

```bash
scripts/build-macos.sh                   # macOS
cd iOS && ./verify.sh                    # 10 個 XCUITest 全綠
cd iOS && ./build.sh                     # 模擬器
cd iOS && ./scripts/install-device.sh    # 真機（usbmuxd 備援）
```

首次上架維持 1.0；之後每次提交 `CFBundleVersion` 必須遞增。

## 四、簽名的坑（已解決，留紀錄）

1. **憑證不可帶自訂信任設定**，否則 xcodebuild 直接拒絕：
   `Invalid trust settings. Restore system default trust settings …`
   檢查 `security dump-trust-settings | grep -E '^Cert'`；
   清除 `security find-certificate -c "<憑證名>" -p login.keychain-db > /tmp/leaf.pem && security remove-trusted-cert /tmp/leaf.pem`
2. **團隊必須是 Xcode 已登入的那個**（本機 `MAA6W8AG5P`），腳本自動讀取。
3. **CoreDevice tunnel 可能壞掉**（`RemotePairingError 4`）而 usbmuxd 正常 → 用 `iOS/scripts/install-device.sh` 的 `ideviceinstaller` 備援。

## 五、隱私權政策

App 不對外傳送任何資料。Token 值以 AES-256-GCM 加密後存放在 App 自己的 Application Support 目錄，金鑰在裝置鑰匙圈。開發者無法存取使用者資料。完整條文：<https://privacy.wahsun.org/>
