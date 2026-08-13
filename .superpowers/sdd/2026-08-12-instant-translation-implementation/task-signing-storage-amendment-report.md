# Signing and Keychain Storage Amendment Report

## Status

完成。实现基于 `414fae3`，仅在 `codex/instant-translation-signing-storage` worktree 内修改。未合并主分支，未执行 notarization，也未宣称 Developer ID/notarized 分发。

## 实现摘要

- 新增显式 `KeychainBackend`：
  - `.fileBased` 的所有 SecItem read/write/delete 查询均省略 `kSecUseDataProtectionKeychain` 与 `kSecAttrAccessGroup`。
  - `.dataProtection(accessGroup:)` 的所有查询均带 `kSecUseDataProtectionKeychain = true` 与构造时传入的精确 access group。
  - 两者保持 service `com.instanttranslation.macos.credentials`、既有 account 标识与写入属性 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`。
  - 没有 status/entitlement 错误后的跨 backend retry 或 runtime fallback。
- 新增显式迁移器，仅公开迁移 `.googleAPIKey` 与 `.llmAPIKey`：目标存在即目标优先；否则按“读源 → 写目标 → 回读精确验证 → 删源”执行。所有底层错误被压缩为不含原错误文本/值的 stage error。
- 新增应用签名元数据解析：
  - 精确 `adhoc` → file-based。
  - 精确 `signed` 且 group 符合 `DEVELOPMENT_TEAM.com.instanttranslation.macos` → Data Protection，并从 file-based 迁移。
  - packaged app 的未知/缺失 mode、signed 缺失/非法 group 均 fail closed。
  - SwiftPM 未打包开发可显式注入配置；未打包且无 metadata 时使用 file-based 开发配置。
- `ApplicationContainer.make` 传播配置/迁移错误；`AppDelegate` 只记录固定的 `credential initialization failed`，不记录底层错误或凭据。
- `package-app.sh` 在 ad-hoc Info.plist 写入 `adhoc` 且删除 access-group metadata；signed metadata 只在既有 profile TeamIdentifier、application identifier 与精确 keychain group gate 全部通过后写入。
- 新增 `package-release.sh`：只接受显式 `SIGNING_MODE=adhoc`，只归档 app bundle，生成并自验 `SHA256SUMS`；关闭 resource fork/extattr/quarantine/ACL 归档，避免 `._*`/`__MACOSX` 无关项。
- 新增 packaged-host ad-hoc Keychain probe：只允许专用 `com.instanttranslation.macos.credentials.probe.*` service 与 `probe.*` account，值在进程内随机生成，写入、回读、删除，输出不含值或底层错误。

## TDD 记录

### Cycle 1：backend / migration / signing metadata / release

先新增：

- `CredentialStorageAmendmentTests`
- `SigningModeConfigurationTests`
- `scripts/test-packaging-amendment.sh`

Focused RED：

```text
$ swift test --filter CredentialStorageAmendmentTests
error: cannot find 'ApplicationCredentialConfiguration' in scope
error: cannot find type 'ApplicationCredentialConfigurationError' in scope

$ bash scripts/test-packaging-amendment.sh
scripts/materialize-signing-info.sh: No such file or directory
```

说明：第一次 sandbox 内 Swift 命令先因 `~/.cache/clang/ModuleCache: Operation not permitted` 失败，这是环境 gate，不计为功能 RED；获准在 sandbox 外重跑后，得到上面的缺失 backend/build-mode 行为 RED。

最小 GREEN：实现 backend 查询构造、迁移器、bundle 配置解析、签名 metadata materializer 与 release 脚本。

```text
$ swift test --filter CredentialStorageAmendmentTests
Executed 8 tests, with 0 failures

$ swift test --filter SigningModeConfigurationTests
Executed 5 tests, with 0 failures

$ bash scripts/test-packaging-amendment.sh
InstantTranslation-macOS.zip: OK
packaging amendment regressions passed

$ bash scripts/test-signing-gates.sh
signing gate regressions passed
```

### Cycle 2：packaged-host live probe 与迁移失败阶段

Focused RED：

```text
$ swift test --filter AdHocKeychainProbeTests
error: cannot find 'AdHocKeychainRoundTripProbe' in scope
error: cannot find type 'AdHocKeychainRoundTripProbeError' in scope
```

最小 GREEN 后：

```text
$ swift test --filter AdHocKeychainProbeTests
Executed 2 tests, with 0 failures

$ swift test --filter CredentialStorageAmendmentTests
Executed 11 tests, with 0 failures
```

新增迁移覆盖包括：目标优先、两项迁移顺序、目标首读失败、源读取失败、写失败、验证读取失败、验证不相等、删除失败后目标仍有效及重复执行幂等。失败路径断言不包含 fixture secret。

### Cycle 3：release 无关 AppleDouble 项

真实 artifact 列表首次发现 `._CodeResources`、`._InstantTranslation` 等 AppleDouble 项。根因是 `ditto` 默认启用 `--rsrc --extattr`。

先给带扩展属性的 fixture 增加回归断言，观察 RED：

```text
$ bash scripts/test-packaging-amendment.sh
InstantTranslation-macOS.zip: OK
FAIL: release contains AppleDouble or resource-fork metadata
```

最小修复为 `ditto --norsrc --noextattr --noqtn --noacl`。GREEN：

```text
$ bash scripts/test-packaging-amendment.sh
InstantTranslation-macOS.zip: OK
packaging amendment regressions passed
```

### Cycle 4：release 必须显式指定 mode

先新增“缺失 `SIGNING_MODE` 不得调用 package-app”的断言，观察 RED：

```text
$ bash scripts/test-packaging-amendment.sh
FAIL: expected failure containing: release packaging accepts only SIGNING_MODE=adhoc
```

将 release 的缺省 mode 从 `adhoc` 改为空值后 GREEN；显式 `adhoc` 成功，`signed` 与缺失值均在调用 package-app 前拒绝。

## 最终验证

### Focused / regression

```text
$ swift test --filter CredentialStorageAmendmentTests
Executed 11 tests, with 0 failures

$ swift test --filter SigningModeConfigurationTests
Executed 5 tests, with 0 failures

$ swift test --filter AdHocKeychainProbeTests
Executed 2 tests, with 0 failures

$ bash scripts/test-packaging-amendment.sh
InstantTranslation-macOS.zip: OK
packaging amendment regressions passed

$ bash scripts/test-signing-gates.sh
signing gate regressions passed
```

### Fresh full suite

最终提交前实际执行：

```text
$ swift package clean && swift test
Build complete! (9.49s)
Executed 94 tests, with 0 failures (0 unexpected)
```

编译输出无 warning/error。随后同一验证命令继续运行两个脚本回归并通过。

### Ad-hoc app metadata 与签名

```text
$ SIGNING_MODE=adhoc bash scripts/package-app.sh
warning: ad-hoc mode; users may need to authorize the app with Open Anyway
.../build/InstantTranslation.app

$ /usr/libexec/PlistBuddy -c 'Print :InstantTranslationSigningMode' build/InstantTranslation.app/Contents/Info.plist
adhoc

$ /usr/libexec/PlistBuddy -c 'Print :InstantTranslationKeychainAccessGroup' build/InstantTranslation.app/Contents/Info.plist
Print: Entry, ":InstantTranslationKeychainAccessGroup", Does Not Exist

$ codesign --verify --deep --strict build/InstantTranslation.app
# exit 0, no output
```

### Release artifact 与 checksum

最终实际执行：

```text
$ SIGNING_MODE=adhoc bash scripts/package-release.sh
InstantTranslation-macOS.zip: OK
.../build/release/InstantTranslation-macOS.zip

$ cd build/release && shasum -a 256 -c SHA256SUMS
InstantTranslation-macOS.zip: OK
```

最终 checksum：

```text
0d871cb20a25c4fa40e91cc8cb61ae71aea8af545b0d5a7fae96f60b47f30325  InstantTranslation-macOS.zip
```

`unzip -t` 无错误。归档内容扫描通过：只有 `InstantTranslation.app` 的 executable、Info.plist、CodeResources 与已知 provider resource bundle；无 `._*`、`__MACOSX`、`.build`、仓库 `build`、`.git`、provisioning profile 或 entitlements 文件。

### Live file-based Keychain probe

最终 release 生成后，直接运行该 ad-hoc 签名 app 的 executable：

```text
$ build/InstantTranslation.app/Contents/MacOS/InstantTranslation \
    --adhoc-keychain-round-trip-probe \
    com.instanttranslation.macos.credentials.probe.final \
    probe.20260813-final
ad-hoc Keychain round trip passed
```

随后用 `security find-generic-password` 对同一专用 service/account 做独立存在性检查，结果为 not found，验证输出为 `probe item cleaned`。因此本环境的 packaged ad-hoc host 实际完成 file-based 写入、回读、删除；这不是 fixture 或未签名 SwiftPM 进程。probe 的随机值从未写入命令行、日志或报告。

### 静态安全扫描

- `AppPreferences` 不含 credential/API-key 字段；`UserDefaultsPreferencesStore` 仍只编码 `AppPreferences`。
- 非测试 Sources/scripts/Config 搜索 `UserDefaults|apiKey|credential|secret|Authorization|x-api-key` 后，凭据只在 Keychain/provider 内存与 HTTP header 构造路径出现；没有写入 preferences、URL 或日志。
- release binary 与 ZIP 内 executable 搜索测试 credential fixture 值（`secret-value`、`source-secret`、`destination-secret`、`google-secret`、`llm-secret`、`TESTTEAM`）均无命中。
- `git diff --check` 通过。

## 自审与真实边界

- 保留了 signed-mode 的 TeamIdentifier、application identifier、profile 精确 keychain group、entitlements 与最终 codesign verification gates；没有放宽或增加 runtime fallback。
- 没有 paid Apple Developer identity/profile，因此没有执行真实 signed-mode package 或 Data Protection entitlement live probe；signed-mode 仅由 deterministic configuration tests 与既有 signing-gate fixture tests 覆盖。
- 没有执行 notarization，release 脚本明确拒绝 `signed`，因此 artifact 仅为 ad-hoc GitHub/self-use 分发。
- live probe 只证明当前 macOS 环境下该 ad-hoc app 的 file-based Keychain round trip 与清理成功，不证明其他机器的 Gatekeeper 首次授权体验。
