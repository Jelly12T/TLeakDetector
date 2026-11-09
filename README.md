# TLeakDetector

Tool phát hiện memory leak của UIViewController trên iOS, **chỉ chạy ở Debug**.
Bản Release vẫn build module nhưng module rỗng, không có symbol nào của tool.

> **Trạng thái:** `TLeakDetector.install()` tự mark VC khi rời màn hình (pop, dismiss, remove child, đổi
> `rootViewController`), mark cả subtree, check T1 (2 giây) / T2 (8 giây) rồi in `[TLeakDetector] LEAK? ...` ra console.
> Chạy với env `TLEAK_VERBOSE=1` để log mỗi lần mark.
>
> Giới hạn hiện tại:
> - Chỉ VC compile trong app target mới được mark. VC nằm trong dynamic framework bị bỏ qua.
> - Container tự viết phải gọi `willMove(toParent: nil)` trước `removeFromParent()`, đúng contract của UIKit.
> - VC được cache lại sau khi đóng (giữ để mở lại) sẽ bị báo leak.

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

## Mở trong Xcode

```sh
open Workspace/JellyLeakDetector.xcworkspace
```

Workspace gồm package, LeakZoo và HostApp. Sửa code tool rồi chạy LeakZoo (⌘R) là thấy ngay, không cần build riêng.
Test: scheme `TLeakDetector` + iOS Simulator, ⌘U.

Workspace nằm trong thư mục con để `xcodebuild` ở thư mục gốc vẫn dùng `Package.swift` (CI dựa vào điều này).

## Cấu trúc repo

```
├── Package.swift                 package chính, product "TLeakDetector"
├── Sources/
│   ├── LeakCore/                 quyết định có leak hay không, không import UIKit
│   └── LeakUIKit/                hook vào UIViewController, API public TLeakDetector
├── Tests/LeakCoreTests/
├── scripts/check-release-symbols.sh   kiểm tra tool không lọt vào Release
├── Examples/HostApp/             app tối giản để script trên archive
├── LeakZoo/                      app 16 scenario leak / không leak, kèm expected.json
├── Workspace/                    JellyLeakDetector.xcworkspace để mở mọi thứ trong Xcode
├── Spikes/                       thí nghiệm có timebox, không phải code production
└── docs/adr/                     các quyết định kiến trúc
```

| Target | Vai trò |
|---|---|
| `LeakCore` | Quyết định có leak hay không. Không import UIKit. |
| `LeakUIKit` | Hook vào UIViewController, báo tin cho `LeakCore`. Chứa API public `TLeakDetector`. |
| `LeakCoreTests` | Test cho `LeakCore`. |
| `LeakUIKitTests` | Test cho `LeakUIKit`, chạy trên iOS Simulator. |

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

### Configuration khác Debug/Release

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

## LeakZoo: bài kiểm tra cho tool

[LeakZoo/](LeakZoo/) là app UIKit cố ý chứa 16 scenario **đã biết đáp án**. Mỗi sprint dùng nó để chấm tool:
10 case leak phải được báo, và 6 case không leak không được báo.

| Nhóm | Case | Ví dụ |
|---|---|---|
| Leak, cycle | Z01–Z06 | closure bắt `self`, delegate strong, `UIAction`, child VC, popToRoot, Combine `sink` |
| Leak, rooted | Z07–Z10 | Timer không invalidate, observer không remove, Task trên AsyncStream không finish, biến static |
| Không leak | Z11–Z16 | `[weak self]`, Task bị cancel, Timer được invalidate, `asyncAfter` (deinit trễ khoảng 1 giây), child và popToRoot đúng cách |

Có đủ 4 cách vào/ra màn hình: push/pop, present/dismiss, popToRoot, add/remove child.

- **[expected.json](LeakZoo/expected.json)** là nơi duy nhất ghi đáp án. App đọc file này để hiện danh sách, và UI test ở S8 sẽ đọc lại.
  Mỗi case có `expectation`, `navigation`, `retainPath` (ai đang giữ object) và danh sách object kèm cờ `leaks`.
  Nếu id trong JSON không có VC tương ứng thì app crash ngay lúc mở.
- Mỗi VC in `[LeakZoo] t=<uptime> deinit <id>` khi bị giải phóng.
- Mở app với launch argument `--autorun` thì app tự mở rồi đóng lần lượt 16 case và ghi log `open` / `close` / `deinit`.

```sh
open LeakZoo/LeakZoo.xcodeproj        # scheme LeakZoo, chạy trên simulator
```

### Soi bộ nhớ (Memory Graph, `leaks`, `heap`)

Kiểm tra trên máy dev ngày 2026-11-05:

- **Phải dùng Xcode 27.1** (`~/Desktop/xcode/Xcode.app`) với simulator **iOS 27.1**.
  Xcode 26.2 không đọc được bộ nhớ của simulator mới hơn nó (lỗi `Failed to get DYLD info`).
- Máy cần bật quyền debug một lần: `sudo DevToolsSecurity -enable`.
- Khi chạy `leaks`/`heap` từ terminal, app cần có entitlement `com.apple.security.get-task-allow`. Xcode tự thêm khi bấm Run.
- Các case cycle **không có dấu "!"** trong Memory Graph. UIKit tự đăng ký mọi VC vào NotificationCenter,
  nên công cụ của Apple coi là vẫn có đường từ root. Hãy dựa vào log deinit và danh sách object còn sống.

## Spikes

[Spikes/](Spikes/) chứa các thí nghiệm có timebox. Mỗi spike trả lời một câu hỏi kỹ thuật trước khi làm tính năng thật.
Mỗi spike là một package riêng, **không** được link vào TLeakDetector. Có thể xoá mà không ảnh hưởng tool.

| Spike | Câu hỏi | Kết quả |
|---|---|---|
| [FieldOwnership](Spikes/FieldOwnership/) | Đọc được property nào là weak/unowned từ metadata Swift không? | **GO.** Xem [ADR 002](docs/adr/002-swift-field-ownership.md) |

```sh
cd Spikes/FieldOwnership
swift test                                                          # macOS
scripts/run.sh sim-all 'platform=iOS Simulator,name=iPhone 17'      # simulator → results/sim-all.txt
scripts/run-device.sh device-all <udid> <team-id>                   # iPhone thật, qua app SpikeHost
```

## Phát triển

```sh
swift build && swift test                      # package chính trên macOS (chỉ LeakCore có nội dung)
scripts/check-release-symbols.sh               # Release sạch
open LeakZoo/LeakZoo.xcodeproj                 # app chấm tool
```

## Tài liệu

| ADR | Nội dung |
|---|---|
| [001](docs/adr/001-exclude-from-release.md) | Loại tool khỏi bản Release: flag trong package, `#if DEBUG` trong app, script kiểm tra binary |
| [002](docs/adr/002-swift-field-ownership.md) | Đọc ownership của field Swift từ reflection metadata, và cách fallback khi app tắt reflection |
