# TLeakDetector

Tool phát hiện memory leak của UIViewController trên iOS, **chỉ chạy ở Debug**.
Bản Release vẫn build module nhưng module rỗng, không có symbol nào của tool.

## Cài đặt

Thêm Swift Package này vào app, chọn product **TLeakDetector** (một dependency duy nhất).

```swift
#if DEBUG
import LeakUIKit
#endif

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    #if DEBUG
    TLeakDetector.install()
    #endif
    return true
}
```

Yêu cầu: iOS 15+, Xcode 16+ (Swift tools 6.0).

## Cấu trúc

| Target | Vai trò |
|---|---|
| `LeakCore` | Quyết định có leak hay không. Không import UIKit. |
| `LeakUIKit` | Hook vào UIViewController, báo tin cho `LeakCore`. Chứa API public `TLeakDetector`. |
| `LeakCoreTests` | Test cho `LeakCore`. |

Chiều phụ thuộc chỉ có một hướng: `LeakUIKit → LeakCore`. Các target khác được thêm khi tới sprint cần.

Mọi file source đều bọc trong `#if LEAK_DETECTOR_ENABLED`. Flag này chỉ bật ở configuration debug
(`.when(configuration: .debug)` trong `Package.swift`). File mới cũng phải bọc như vậy.

## Kiểm tra tool không lọt vào Release

```sh
scripts/check-release-symbols.sh                                   # archive host app ví dụ, Release
scripts/check-release-symbols.sh --project App.xcodeproj --scheme App --configuration Release
scripts/check-release-symbols.sh --configuration Debug --expect-present   # kiểm tra ngược: Debug phải có symbol
```

Script archive app, chạy `nm` và `strings` trên mọi Mach-O trong `.app`, fail nếu thấy tên module,
tên product, flag hoặc tên type khai báo trong `Sources/`. Chi tiết: [ADR 001](docs/adr/001-exclude-from-release.md).

## Configuration khác Debug/Release

Xcode chọn debug hay release cho package **theo tên configuration**, không theo build settings của app.
Đã kiểm tra trên Xcode 26.2:

| Configuration của app | Package build như | Flag |
|---|---|---|
| `Debug` | debug | bật |
| `StagingDebug` | debug | bật |
| `Staging` (dù app có `DEBUG`, `-Onone`) | **release** | **tắt** |
| `Release` | release | tắt |

Nếu project có configuration riêng, chạy script với `--configuration <tên>` cho từng cái
(thêm `--expect-present` cho những cái cần có tool).

## Phát triển

```sh
swift build && swift test                      # macOS, chỉ LeakCore có nội dung
open Examples/HostApp/HostApp.xcodeproj        # host app iOS để chạy thử
```

## Tài liệu

- [docs/adr/](docs/adr/): các quyết định kiến trúc
