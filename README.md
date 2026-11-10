# TLeakDetector

Tool phát hiện memory leak của UIViewController trên iOS, **chỉ chạy ở Debug**.
Bản Release vẫn build module nhưng module rỗng, không có symbol nào của tool.

> **Trạng thái: M1 (MVP).** `TLeakDetector.install()` tự mark VC khi rời màn hình (pop, dismiss, remove child, đổi
> `rootViewController`), mark cả subtree, check T1 (2 giây) / T2 (8 giây) rồi báo leak (xem [Khi có leak](#khi-có-leak)).
> Instance budget bắt thêm những leak không đi qua sự kiện rời màn hình nào.
> LeakZoo: 20/20 scenario khớp đáp án, xem [LeakZoo/RESULTS.md](LeakZoo/RESULTS.md).
> Chạy với env `TLEAK_VERBOSE=1` để log mỗi lần mark.
>
> Giới hạn hiện tại:
> - Chỉ VC compile trong app target mới được mark. VC nằm trong dynamic framework bị bỏ qua.
> - Container tự viết phải gọi `willMove(toParent: nil)` trước `removeFromParent()`, đúng contract của UIKit.
>   Nếu không, child không bị mark; chỉ [instance budget](#instance-budget) bắt được leak của nó.
> - Chưa có graph: report chưa cho biết ai đang giữ object, và chưa phân biệt leak do cycle với leak do bị giữ từ root.
> - VC được cache lại sau khi đóng (giữ để mở lại) phải khai báo `allowedTypes` hoặc conform `LeakOptOut`, nếu không sẽ bị báo leak. Xem [Cấu hình](#cấu-hình).

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

## Khi có leak

Mỗi lần rời màn hình cho tối đa một report. Mỗi leak (tên type + `kind`) chỉ báo một lần trong một phiên chạy.

| Tình huống | Mặc định |
|---|---|
| Có debugger (chạy từ Xcode) | App dừng ở debugger (`SIGTRAP`). Mở Memory Graph để soi object, bấm Continue để chạy tiếp |
| Không có debugger | App crash (`assertionFailure`) kèm report |

Đổi mode bằng env `TLEAK_MODE`: `debugger`, `crash` hoặc `log` (chỉ log, không dừng).
`--autorun` của LeakZoo cần `TLEAK_MODE=log`, nếu không app sẽ dừng hoặc crash ở leak đầu tiên.

Report đi qua `os_log`, subsystem `TLeakDetector`. Trong Console.app lọc bằng `subsystem:TLeakDetector`.

```
[TLeakDetector] LEAK Z01ClosurePropertyViewController (0x103808200) still alive 8.2s after pop of Z01ClosurePropertyViewController
  kind: screen, the closed screen itself is still alive
  path: Z01ClosurePropertyViewController
  also alive (3):
    UIView  Z01ClosurePropertyViewController.view
    UIStackView  Z01ClosurePropertyViewController.view.subviews[0]
    UILabel  Z01ClosurePropertyViewController.view.subviews[0].subviews[0]
```

### Đọc report

| Dòng | Nghĩa |
|---|---|
| `LEAK <Type> (0x…)` | Object bị nghi leak, gần màn hình gốc nhất. Địa chỉ dùng để tìm trong Memory Graph hoặc `po` trong lldb |
| `still alive 8.2s after pop of <Root>` | Sống thêm bao lâu, sau sự kiện rời màn hình nào (`pop`, `dismiss`, `removeFromParent`, `replaceRoot`), của màn hình nào |
| `kind:` | Loại leak, xem bảng dưới |
| `path:` | Đường đi từ màn hình gốc tới object, ví dụ `ProfileVC.children[0].view.subviews[2]` hoặc `ProfileVC.viewModel` |
| `also alive (N):` | Các object khác trong cùng subtree vẫn còn sống (tối đa 10 dòng). Màn hình còn sống thì view của nó còn sống là bình thường |
| `suppressed until …` | Leak có trong suppression file: chỉ log, không dừng app |
| `suppression expired on …` | Entry suppression đã hết hạn, leak bị báo lại như mới |

| `kind` | Nghĩa | Thường sửa ở đâu |
|---|---|---|
| `screen` | Chính màn hình vừa đóng vẫn còn sống | Closure bắt `self`, delegate strong, Timer, observer, Task… trong VC đó |
| `outlived` | Màn hình đã chết nhưng một object nó giữ vẫn sống, tức có thứ bên ngoài đang giữ object đó | Ai đang giữ object (singleton, cache…). Nếu object dùng chung có chủ đích thì thêm vào `allowedTypes` |
| `budget` | Số instance của một type cùng sống vượt budget đã khai báo | Instance cũ không được giải phóng khi mở instance mới |

`kind` mô tả điều tool quan sát được, không mô tả nguyên nhân, và không bao giờ đổi tên ([ADR 003](docs/adr/003-leak-kind.md)).
Cycle hay rooted sẽ là một trường riêng khi có graph.

Report vượt budget có dạng:

```
[TLeakDetector] LEAK Z20CarelessChildViewController: 2 instances alive, budget is 1
  kind: budget, more instances alive at once than its budget
  alive (oldest first): 0x104812a00, 0x10481e600
```

## Cấu hình

`install()` nhận một `LeakConfiguration`. Mọi tham số đều có giá trị mặc định:

```swift
#if DEBUG
TLeakDetector.install(LeakConfiguration(allowedTypes: [ProductCacheViewController.self]))
#endif
```

| Tham số | Mặc định | Ý nghĩa |
|---|---|---|
| `t1`, `t2` | `2`, `8` | Số giây sau khi rời màn hình: lần check đầu và lúc báo |
| `mode` | `nil` | `.crash`, `.debugger` hoặc `.log`. `nil` nghĩa là có debugger thì dừng, không có thì crash. Env `TLEAK_MODE` ghi đè giá trị này |
| `maxSubtreeDepth` | `nil` | Số bước bên dưới màn hình được mark (child, view, subview, property). `nil` là không giới hạn |
| `allowedTypes` | `[]` | Các type được phép sống sau khi rời màn hình, tính cả subclass. Ví dụ: VC được cache |
| `suppressionFile` | `LeakSuppressions.json` trong bundle chính | File liệt kê các leak đã biết |
| `instanceBudgets` | `[]` | Số instance tối đa của một type được sống cùng lúc. Xem [Instance budget](#instance-budget) |

Type nằm trong `allowedTypes` hoặc conform `LeakOptOut` sẽ không bao giờ bị mark. View của nó, child của nó và
những gì nó giữ cũng không bị mark. Protocol này không tồn tại ở Release, nên conformance phải bọc `#if DEBUG`:

```swift
#if DEBUG
extension MiniPlayerViewController: LeakOptOut {}
#endif
```

### Instance budget

Bắt leak tích luỹ qua nhiều lần mở rồi đóng, kể cả khi không biết sự kiện nào gây ra: khai báo type X chỉ được
có tối đa N instance cùng sống. Mỗi lần có instance mới, tool bỏ các instance đã chết rồi đếm lại; vượt N thì báo
với `kind: budget`. Subclass được tính chung vào budget của class cha.

```swift
#if DEBUG
TLeakDetector.install(LeakConfiguration(instanceBudgets: [
    LeakInstanceBudget(ProfileViewController.self, max: 1),
    LeakInstanceBudget(ProfileViewModel.self, max: 1),
]))
#endif
```

- View controller được đếm tự động ở `viewDidLoad`.
- Object khác phải tự đăng ký ở cuối `init`. Gọi được từ thread nào cũng được:

  ```swift
  init() {
      …
      #if DEBUG
      TLeakDetector.track(self)
      #endif
  }
  ```

### Suppression file

Dùng khi áp dụng tool vào codebase cũ: leak đã biết chỉ được log, không dừng hay crash app cho tới ngày hết hạn.
Hết hạn thì leak bị báo lại như một leak mới. Xem file mẫu ở [LeakZoo/LeakZoo/LeakSuppressions.json](LeakZoo/LeakZoo/LeakSuppressions.json).

```json
{
  "version": 1,
  "suppressions": [
    {
      "signature": { "type": "ProfileViewController", "kind": "screen" },
      "reason": "Closure trong ProfileViewModel bắt self, sửa ở ticket APP-123",
      "owner": "thachlh",
      "expires": "2026-12-31"
    }
  ]
}
```

- `signature.type` là tên type ở dòng `LEAK` của report, `signature.kind` là giá trị ở dòng `kind:`.
- `expires` có dạng `yyyy-MM-dd` và còn hiệu lực hết ngày đó, theo giờ của máy. `reason` và `owner` là bắt buộc.
- Entry sai format bị bỏ qua, các entry còn lại vẫn có hiệu lực. File sai cú pháp JSON thì bị bỏ qua toàn bộ.
  Mọi lỗi đều được log ở category `config` (`subsystem:TLeakDetector category:config`) và không làm crash app.
- Chỉ nên đưa file vào bundle Debug: đặt `EXCLUDED_SOURCE_FILE_NAMES = LeakSuppressions.json` cho configuration
  Release của target, như LeakZoo đang làm.

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
├── Tests/                        LeakCoreTests (macOS + simulator), LeakUIKitTests (simulator)
├── scripts/
│   ├── check-release-symbols.sh  kiểm tra tool không lọt vào Release
│   └── zoo-autorun.sh            chạy LeakZoo trên simulator, chấm theo expected.json
├── Examples/HostApp/             app tối giản để script trên archive
├── LeakZoo/                      app 20 scenario leak / không leak, kèm expected.json và RESULTS.md
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

[LeakZoo/](LeakZoo/) là app UIKit cố ý chứa 20 scenario **đã biết đáp án**. Mỗi sprint dùng nó để chấm tool:
10 case leak phải được báo, 8 case không leak hoặc được phép sống không được báo, 1 case đã suppress chỉ được log,
và 1 case chỉ instance budget mới bắt được.

| Nhóm | Case | Ví dụ |
|---|---|---|
| Leak, cycle | Z01–Z06 | closure bắt `self`, delegate strong, `UIAction`, child VC, popToRoot, Combine `sink` |
| Leak, rooted | Z07–Z10 | Timer không invalidate, observer không remove, Task trên AsyncStream không finish, biến static |
| Không leak | Z11–Z16 | `[weak self]`, Task bị cancel, Timer được invalidate, `asyncAfter` (deinit trễ khoảng 1 giây), child và popToRoot đúng cách |
| Được phép, suppress | Z17–Z19 | VC được cache (`allowedTypes`), VC conform `LeakOptOut`, leak có trong `LeakSuppressions.json` (chỉ log) |
| Chỉ budget bắt được | Z20 | Container quên `willMove(toParent: nil)` nên không có sự kiện rời màn hình; budget 1, autorun mở 2 lần |

Có đủ 4 cách vào/ra màn hình: push/pop, present/dismiss, popToRoot, add/remove child.

- **[expected.json](LeakZoo/expected.json)** là nơi duy nhất ghi đáp án. App đọc file này để hiện danh sách, và UI test ở S8 sẽ đọc lại.
  Mỗi case có `expectation`, `navigation`, `retainPath` (ai đang giữ object) và danh sách object kèm cờ `leaks`.
  Nếu id trong JSON không có VC tương ứng thì app crash ngay lúc mở.
- Mỗi VC in `[LeakZoo] t=<uptime> deinit <id>` khi bị giải phóng.
- Mở app với launch argument `--autorun` thì app tự mở rồi đóng lần lượt mọi case (`opens` lần, mặc định 1)
  và ghi log `open` / `close` / `deinit`.

```sh
open LeakZoo/LeakZoo.xcodeproj        # scheme LeakZoo, chạy trên simulator
scripts/zoo-autorun.sh                # chạy mọi case, chấm theo expected.json, ghi LeakZoo/RESULTS.md
```

`zoo-autorun.sh` build LeakZoo, chạy `--autorun` với `TLEAK_MODE=log`, đọc report của tool từ unified log và log
`deinit` của LeakZoo, rồi so với `expected.json`: case leak phải được báo đúng loại, case không leak không được báo,
object có `leaks: false` phải deinit và object có `leaks: true` thì không. Exit 1 nếu có case lệch.
Kết quả mới nhất: [LeakZoo/RESULTS.md](LeakZoo/RESULTS.md).

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
scripts/zoo-autorun.sh                         # chấm tool trên LeakZoo (simulator)
```

## Tài liệu

| ADR | Nội dung |
|---|---|
| [001](docs/adr/001-exclude-from-release.md) | Loại tool khỏi bản Release: flag trong package, `#if DEBUG` trong app, script kiểm tra binary |
| [002](docs/adr/002-swift-field-ownership.md) | Đọc ownership của field Swift từ reflection metadata, và cách fallback khi app tắt reflection |
| [003](docs/adr/003-leak-kind.md) | `kind` của leak (`screen`, `outlived`, `budget`) mô tả điều quan sát được và không bao giờ đổi tên |
