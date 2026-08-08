# OpenCode macOS Finder 최상위 컨텍스트 메뉴 구현 지침

## 목표

현재 `install-opencode-server.command`가 생성하는 Automator Service를 Finder 컨텍스트 메뉴의 주 구현에서 제거하고 Finder Sync Extension으로 교체한다.

최종 UX:

```text
폴더 우클릭

새로운 폴더
정보 가져오기
...
OpenCode에서 열기       ← Finder 최상위 context menu
...
빠른 동작 >
서비스 >
```

`OpenCode에서 열기`가 `빠른 동작 >` 또는 `서비스 >` 아래에 들어가면 실패로 간주한다.

Finder가 메뉴 그룹의 정확한 위치/순서를 결정하므로 “첫 번째 행”을 요구하지 않는다. 요구사항은 submenu가 아닌 top-level context item이다.


# 1. 기존 코드는 최대한 유지한다

기존 다음 파일은 그대로 활용한다.

```text
~/.local/bin/opencode-attach
~/.local/bin/opencode-attach-launcher
```

특히 `opencode-attach-launcher`의 역할을 Finder extension에 다시 구현하지 않는다.

현재 launcher는:

```shell
for target_dir in "$@"; do
    [[ -d "$target_dir" ]] || continue

    /usr/bin/osascript ...
        tell application "Terminal"
            activate
            do script commandText
        end tell
done
```

형태이므로 Finder에서 얻은 directory path만 launcher에 전달하면 된다.


# 2. FinderSync Extension 추가

파일:

```text
macos/finder-extension/OpenCodeFinderSync.swift
```

구현 요구사항:

```swift
import AppKit
import FinderSync

@objc(OpenCodeFinderSync)
final class OpenCodeFinderSync: FIFinderSync {

    private let callbackScheme = "opencode-attach"

    override init() {
        super.init()

        // Finder 전체 파일시스템을 대상으로 한다.
        //
        // /Volumes 아래 외장/네트워크 볼륨도 포함된다.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else {
            return nil
        }

        let directories = selectedDirectories()

        // 하나라도 file이거나 판별하지 못한 항목이면 메뉴를 노출하지 않는다.
        guard !directories.isEmpty else {
            return nil
        }

        let menu = NSMenu()

        let item = NSMenuItem(
            title: "OpenCode에서 열기",
            action: #selector(openInOpenCode(_:)),
            keyEquivalent: ""
        )

        item.target = self
        menu.addItem(item)

        return menu
    }

    @objc
    private func openInOpenCode(_ sender: Any?) {
        let directories = selectedDirectories()

        guard !directories.isEmpty else {
            return
        }

        var components = URLComponents()
        components.scheme = callbackScheme
        components.host = "open"

        components.queryItems = directories.map {
            URLQueryItem(name: "path", value: $0.path)
        }

        guard let url = components.url else {
            NSSound.beep()
            return
        }

        if !NSWorkspace.shared.open(url) {
            NSSound.beep()
        }
    }

    private func selectedDirectories() -> [URL] {
        let controller = FIFinderSyncController.default()

        let target = controller.targetedURL()
        var urls = controller.selectedItemURLs() ?? []

        // Finder가 선택 목록과 실제 control-click 대상에 다른 값을
        // 주는 경우 target을 우선한다.
        if let target {
            let normalizedTarget = target.standardizedFileURL

            let containsTarget = urls.contains {
                $0.standardizedFileURL == normalizedTarget
            }

            if !containsTarget {
                urls = [target]
            }
        }

        guard !urls.isEmpty else {
            return []
        }

        var result: [URL] = []

        for url in urls {
            guard url.isFileURL else {
                return []
            }

            guard
                let values = try? url.resourceValues(
                    forKeys: [.isDirectoryKey]
                ),
                values.isDirectory == true
            else {
                return []
            }

            result.append(url.standardizedFileURL)
        }

        return result
    }
}
```

중요:

`selectedItemURLs()`와 `targetedURL()`은 `menu(for:)`와 이 메뉴에서 생성한 action 안에서만 신뢰할 수 있다.

따라서 선택 path를 global variable에 장기간 저장하지 말고 action 안에서 다시 얻는 현재 구조를 유지한다.


# 3. extension에서 Process를 직접 실행하지 않는다

금지:

```swift
Process().executableURL =
    URL(fileURLWithPath:
        NSHomeDirectory() +
        "/.local/bin/opencode-attach-launcher")
```

FinderSync extension은 sandboxed process다.

그 extension이 실행한 child process에 sandbox 제약이 전달되기 때문에 `osascript`, Terminal automation, `~/.local/bin`, 기타 파일 접근에서 예측하기 어려운 오류가 발생할 수 있다.

대신:

```text
FinderSync
    ↓
custom URL
    ↓
unsandboxed host app
    ↓
Process
```

구조를 사용한다.


# 4. 아주 작은 host app 추가

파일:

```text
macos/finder-extension/OpenCodeFinderHost.swift
```

역할은 딱 하나다.

```text
opencode-attach://open?path=/foo&path=/bar
```

URL을 받아

```shell
~/.local/bin/opencode-attach-launcher /foo /bar
```

를 실행한다.

권장 구현:

```swift
import AppKit
import Foundation
import FinderSync

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var handledRequest = false

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        // Finder extension의 URL 없이 사용자가 app을 직접 실행한 경우
        // extension 관리 UI를 보여준다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if !self.handledRequest {
                FIFinderSyncController
                    .showExtensionManagementInterface()
            }
        }
    }

    func application(
        _ application: NSApplication,
        open urls: [URL]
    ) {
        handledRequest = true

        let paths = urls.flatMap(parsePaths)

        guard !paths.isEmpty else {
            terminateSoon()
            return
        }

        launchOpenCode(paths: paths)
    }

    private func parsePaths(_ url: URL) -> [String] {
        guard url.scheme == "opencode-attach",
              url.host == "open",
              let components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              )
        else {
            return []
        }

        var result: [String] = []

        // DoS 방지용 임의 상한
        for item in (components.queryItems ?? [])
            .filter({ $0.name == "path" })
            .prefix(32)
        {
            guard let value = item.value,
                  value.hasPrefix("/")
            else {
                continue
            }

            let url = URL(
                fileURLWithPath: value,
                isDirectory: true
            ).standardizedFileURL

            var isDirectory: ObjCBool = false

            guard FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
            else {
                continue
            }

            result.append(url.path)
        }

        return result
    }

    private func launchOpenCode(paths: [String]) {
        let launcher =
            FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin")
                .appendingPathComponent(
                    "opencode-attach-launcher"
                )

        guard FileManager.default.isExecutableFile(
            atPath: launcher.path
        ) else {
            log(
                "launcher not found: \(launcher.path)"
            )
            terminateSoon()
            return
        }

        let process = Process()
        process.executableURL = launcher
        process.arguments = paths

        process.terminationHandler = { [weak self] task in
            self?.log(
                "launcher exit: \(task.terminationStatus)"
            )

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }

        do {
            try process.run()
        } catch {
            log(
                "launcher failed: \(error.localizedDescription)"
            )

            terminateSoon()
        }
    }

    private func terminateSoon() {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.1
        ) {
            NSApp.terminate(nil)
        }
    }

    private func log(_ text: String) {
        let directory =
            FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/OpenCode")

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let file =
            directory.appendingPathComponent(
                "finder-extension.log"
            )

        let line =
            "\(Date()) \(text)\n"

        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(
            atPath: file.path
        ) {
            guard let handle =
                    try? FileHandle(
                        forWritingTo: file
                    )
            else {
                return
            }

            defer {
                try? handle.close()
            }

            try? handle.seekToEnd()
            try? handle.write(
                contentsOf: data
            )
        } else {
            try? data.write(to: file)
        }
    }
}

@main
struct OpenCodeFinderHost {
    static func main() {
        let app = NSApplication.shared

        let delegate = AppDelegate()

        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()

        // retain delegate while event loop runs
        withExtendedLifetime(delegate) {}
    }
}
```

검증 과정에서 `application(_:open:)`의 Swift SDK signature가 설치된 macOS SDK와 다를 경우 Xcode/`swiftc` compiler가 제시하는 현재 `NSApplicationDelegate` signature에 맞춰 수정한다.


# 5. Host Info.plist

생성할 bundle:

```text
OpenCode Finder.app
```

bundle id:

```text
com.pawprint0706.opencode.finder
```

필수 값:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC
 "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">
<dict>

    <key>CFBundleIdentifier</key>
    <string>com.pawprint0706.opencode.finder</string>

    <key>CFBundleName</key>
    <string>OpenCode Finder</string>

    <key>CFBundleExecutable</key>
    <string>OpenCodeFinderHost</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleVersion</key>
    <string>1</string>

    <key>CFBundleShortVersionString</key>
    <string>1.0</string>

    <key>LSUIElement</key>
    <true/>

    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>OpenCode Finder</string>

            <key>CFBundleURLSchemes</key>
            <array>
                <string>opencode-attach</string>
            </array>
        </dict>
    </array>

</dict>
</plist>
```

`LSUIElement=true`를 사용하여 이 broker app 때문에 Dock 아이콘이 뜨지 않도록 한다.


# 6. FinderSync bundle

최종 구조:

```text
OpenCode Finder.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── OpenCodeFinderHost
    └── PlugIns/
        └── OpenCodeFinderExtension.appex/
            └── Contents/
                ├── Info.plist
                └── MacOS/
                    └── OpenCodeFinderExtension
```

extension bundle id:

```text
com.pawprint0706.opencode.finder.extension
```

extension Info.plist:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC
 "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">
<dict>

    <key>CFBundleIdentifier</key>
    <string>
        com.pawprint0706.opencode.finder.extension
    </string>

    <key>CFBundleName</key>
    <string>OpenCode Finder Extension</string>

    <key>CFBundleExecutable</key>
    <string>OpenCodeFinderExtension</string>

    <key>CFBundlePackageType</key>
    <string>XPC!</string>

    <key>CFBundleVersion</key>
    <string>1</string>

    <key>CFBundleShortVersionString</key>
    <string>1.0</string>

    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>

    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict/>

        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.FinderSync</string>

        <key>NSExtensionPrincipalClass</key>
        <string>OpenCodeFinderSync</string>
    </dict>

</dict>
</plist>
```


# 7. Finder extension sandbox entitlement

파일:

```text
FinderSync.entitlements
```

내용:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC
 "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
```

Host app에는 이 entitlement를 적용하지 않는다.

의도적으로:

```text
Finder extension = sandboxed
host app         = unsandboxed
```

구조로 한다.


# 8. 빌드

설치 시 다음을 먼저 검사한다.

```shell
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Finder context menu requires Apple Command Line Tools."
    echo "Install with: xcode-select --install"
    return 1
fi
```

FinderSync executable은 대략:

```shell
xcrun swiftc \
    -O \
    -parse-as-library \
    -framework AppKit \
    -framework FinderSync \
    -Xlinker -e \
    -Xlinker _NSExtensionMain \
    OpenCodeFinderSync.swift \
    -o "$EXTENSION_EXECUTABLE"
```

host:

```shell
xcrun swiftc \
    -O \
    -framework AppKit \
    -framework FinderSync \
    OpenCodeFinderHost.swift \
    -o "$HOST_EXECUTABLE"
```

빌드 머신의 CPU architecture 그대로 빌드하면 된다.

installer가 해당 Mac 자체에서 build하기 때문이다.


# 9. code signing

순서 중요.

먼저 extension:

```shell
codesign \
    --force \
    --sign - \
    --entitlements FinderSync.entitlements \
    "$EXTENSION_PATH"
```

그 다음 containing app:

```shell
codesign \
    --force \
    --sign - \
    "$APP_PATH"
```

검증:

```shell
codesign --verify --deep --strict "$APP_PATH"

codesign -d \
    --entitlements - \
    "$EXTENSION_PATH"
```

두 번째 명령 결과에:

```text
com.apple.security.app-sandbox = true
```

가 있어야 한다.


# 10. 설치 위치

1차 구현에서는:

```text
/Applications/OpenCode Finder.app
```

을 사용한다.

스크립트가 root로 전체 실행되면 안 된다.

앱을 `/Applications`로 복사하는 부분에서만:

```shell
sudo ditto ...
```

또는 AppleScript administrator privileges 등을 사용한다.

OpenCode server / password / launcher는 지금처럼 user 권한으로 유지한다.


# 11. LaunchServices / PlugInKit 등록

상수:

```shell
FINDER_APP="/Applications/OpenCode Finder.app"

FINDER_EXT_ID="com.pawprint0706.opencode.finder.extension"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
```

설치 후:

```shell
"$LSREGISTER" -f "$FINDER_APP"

pluginkit \
    -a \
    "$FINDER_APP/Contents/PlugIns/OpenCodeFinderExtension.appex"

pluginkit \
    -e use \
    -i "$FINDER_EXT_ID"

killall Finder 2>/dev/null || true
```

확인:

```shell
pluginkit -m -i "$FINDER_EXT_ID"
```

결과에 extension이 나타나는지 확인한다.


# 12. 기존 Automator workflow 처리

현재:

```text
~/Library/Services/OpenCode에서 열기.workflow
```

는 FinderSync 설치 성공 후 제거하는 것을 기본으로 한다.

이유:

동일한 기능이

```text
OpenCode에서 열기
서비스 > OpenCode에서 열기
```

두 군데 동시에 나오는 것을 방지한다.

단, FinderSync 설치/build 실패 시에는 현재 Automator Service를 fallback으로 설치해도 된다.

권장 installer logic:

```text
try FinderSync
    성공:
        기존 .workflow 삭제
    실패:
        기존 install_quick_action 실행
        FinderSync 실패 경고 출력
```

즉 FinderSync 실패 때문에 전체 OpenCode server 설치가 실패하면 안 된다.


# 13. install-opencode-server.command 수정

기존:

```shell
install_quick_action
```

호출을:

```shell
if install_finder_context_menu; then
    rm -rf "$QUICK_ACTION_PATH"
else
    print "Finder 최상위 메뉴 설치에 실패했습니다."
    print "기존 Finder Service 방식으로 fallback합니다."
    install_quick_action
fi
```

형태로 변경한다.

출력도 현재:

```text
Finder 빠른 동작: OpenCode에서 열기
```

에서:

```text
Finder 우클릭 메뉴: OpenCode에서 열기
```

로 변경한다.


# 14. uninstall

현재 uninstall에서:

```shell
rm -rf "$QUICK_ACTION_PATH"
```

외에 다음을 추가한다.

먼저 extension disable:

```shell
pluginkit \
    -e ignore \
    -i "$FINDER_EXT_ID" \
    2>/dev/null || true
```

그 다음 앱 삭제:

```shell
sudo rm -rf "/Applications/OpenCode Finder.app"
```

가능하면 LaunchServices unregister:

```shell
"$LSREGISTER" \
    -u \
    "/Applications/OpenCode Finder.app" \
    2>/dev/null || true
```

마지막:

```shell
killall Finder 2>/dev/null || true
```

그리고 기존 `.workflow`도 계속 삭제한다.


# 15. 절대 하지 말 것

다음 방식으로 돌아가지 않는다.

```text
pbs.plist 직접 수정
presentationMode 조작
Automator quick action metadata 조작
Finder plist private key 조작
AppleScript로 Finder 메뉴 UI를 강제로 변경
FinderSync extension에서 직접 opencode 실행
FinderSync extension에서 직접 osascript 실행
```

목표가 top-level Finder menu인 이상 FinderSync를 primary implementation으로 사용한다.


# 16. 필수 테스트

Intel Mac과 Apple Silicon Mac 모두 가능한 경우 테스트한다.

테스트 A:

```text
Finder → 로컬 일반 폴더 우클릭
```

기대:

```text
OpenCode에서 열기
```

가 submenu가 아니라 바로 표시.

테스트 B:

메뉴 클릭.

기대:

```text
Terminal.app 활성화
→ opencode attach
→ 선택한 folder가 --dir로 전달
```

테스트 C:

공백:

```text
~/Development/My Project
```

테스트.

테스트 D:

한글:

```text
~/개발/테스트 프로젝트
```

테스트.

테스트 E:

```text
a
b
c
```

세 폴더 다중 선택 후 context menu.

기대:

현재 launcher 특성상 Terminal session 3개 실행.

테스트 F:

일반 파일 우클릭.

기대:

```text
OpenCode에서 열기
```

가 표시되지 않음.

테스트 G:

Finder background 우클릭.

현재 요구사항에서는 표시되지 않는 것이 정상.

향후 원한다면 `.contextualMenuForContainer`를 추가할 수 있음.

테스트 H:

재부팅/로그아웃 후에도 extension 등록 유지.

테스트 I:

uninstall 후:

```shell
pluginkit -m |
grep com.pawprint0706.opencode.finder
```

확인.

Finder 우클릭 메뉴에서도 제거됐는지 확인.


# 17. 디버그 절차

메뉴 자체가 안 뜬다면 먼저:

```shell
pluginkit -m \
    -i com.pawprint0706.opencode.finder.extension
```

다음:

```shell
codesign --verify \
    --deep \
    --strict \
    "/Applications/OpenCode Finder.app"
```

다음:

```shell
codesign -d \
    --entitlements - \
    "/Applications/OpenCode Finder.app/Contents/PlugIns/OpenCodeFinderExtension.appex"
```

다음:

```shell
killall Finder
```

host 실행 문제:

```text
~/Library/Logs/OpenCode/finder-extension.log
```

확인.

custom URL 확인:

```shell
open \
'opencode-attach://open?path=%2Ftmp'
```

이것으로 Terminal에서 `/tmp`에 attach된다면:

```text
host → launcher
```

구간은 정상이다.

Finder 메뉴 클릭으로만 안 된다면:

```text
FinderSync → host
```

구간을 조사한다.


# 18. 문서 수정

`MACOS-FINDER-QUICK-ACTION.md`에서 다음 주장을 반드시 삭제/수정한다.

기존 주장:

```text
FinderSync는 toolbar/badge/sidebar 용이고
우클릭 메뉴와 무관하다.
```

수정:

```text
FinderSync는 Finder contextual menu를 공식 지원한다.

FIMenuKind:
- contextualMenuForItems
- contextualMenuForContainer
- contextualMenuForSidebar
- toolbarItemMenu
```

기존 Automator 조사는 “Service / Quick Action submenu의 차이”를 설명하는 historical/fallback 섹션으로 남겨도 된다.


# 19. PR 제목

```text
feat(macOS): add top-level Finder "Open in OpenCode" context menu
```


# 20. PR 설명

```text
## Summary

Replace the primary macOS Finder integration with a Finder Sync
extension so "OpenCode에서 열기" appears directly in Finder's
context menu instead of under Services/Quick Actions.

## Architecture

FinderSync extension
  -> opencode-attach:// callback
  -> lightweight unsandboxed broker app
  -> existing opencode-attach-launcher
  -> Terminal
  -> opencode attach

## Compatibility

The existing Automator Service remains available as an installation
fallback when the Finder extension cannot be built or registered.

## Security

The Finder extension remains sandboxed and never executes shell
commands directly. The host app validates incoming callback URLs and
passes directory paths to the existing launcher using Process arguments,
without shell interpolation.

## Testing

- single folder
- paths containing spaces
- Korean paths
- multiple selected folders
- regular files
- reinstall
- uninstall
- reboot
- Apple Silicon / Intel where available
```