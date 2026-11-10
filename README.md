# TLeakDetector

Tool phát hiện memory leak của màn hình (UIViewController) trên iOS, **chỉ chạy ở Debug**.

Mỗi khi một màn hình đóng (pop, dismiss, remove child, đổi `rootViewController`), tool kiểm tra xem màn hình đó và mọi thứ
nó giữ có được giải phóng không. Nếu không, tool báo:

- **retain cycle nào** đang giữ màn hình, hoặc **ai đang giữ** nó (Task, Timer, CADisplayLink, observer, URLSession…);
- **cách sửa** gợi ý theo đúng chỗ (`[weak self]` trong closure nào, `weak var` ở field nào, invalidate timer nào…).

Bản Release không chứa một dòng code nào của tool.

- [Tích hợp](#tích-hợp)
- [Khi có leak](#khi-có-leak)
- [Cảnh báo sớm](#cảnh-báo-sớm)
- [Cấu hình](#cấu-hình)
- [Giới hạn](#giới-hạn)
- [Kiểm tra tool không lọt vào Release](#kiểm-tra-tool-không-lọt-vào-release)
- [App demo](#app-demo)
- [Phát triển tool](#phát-triển-tool)

## Tích hợp

Yêu cầu: iOS 15+, Xcode 16+ (Swift tools 6.0). App UIKit, Swift hoặc Objective-C.

### 1. Thêm package

Xcode → **File › Add Package Dependencies…** → nhập URL repo:

```
https://github.com/Jelly12T/TLeakDetector
```

Chọn product **TLeakDetector** và thêm vào **target app** (không thêm vào extension hay test target).

Nếu dùng `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Jelly12T/TLeakDetector", branch: "main"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "TLeakDetector", package: "TLeakDetector")]),
]
```

### 2. Gọi `install()` một lần lúc app khởi động

```swift
#if DEBUG
import LeakUIKit
#endif

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        TLeakDetector.install()
        #endif
        return true
    }
}
```

Chỉ vậy thôi. Không phải gọi gì ở từng màn hình: tool tự biết khi nào màn hình đóng.

> **Bắt buộc bọc `#if DEBUG`.** Ở Release, type `TLeakDetector` không tồn tại, nên quên bọc là lỗi compile chứ không
> thể âm thầm lọt vào bản phát hành.

### 3. Kiểm tra tên configuration

Xcode chọn build package ở chế độ debug hay release **theo tên configuration của app**, không theo build settings:

| Configuration của app | Package build như | Tool có chạy? |
|---|---|---|
| `Debug`, `StagingDebug`… (tên có chữ Debug) | debug | có |
| `Staging` (kể cả khi app đặt `DEBUG`, `-Onone`) | **release** | **không** |
| `Release` | release | không |

Nếu team dùng configuration riêng mà muốn có tool, đặt tên chứa `Debug`.

### Dùng hằng ngày

1. Chạy app từ Xcode như bình thường, đi qua các màn hình rồi đóng chúng.
2. Có leak thì app **dừng ở debugger**. Đọc report trong console của Xcode.
3. Mở **Debug Memory Graph** nếu muốn soi thêm, rồi bấm **Continue** để chạy tiếp.

Mỗi leak chỉ báo một lần trong một lần chạy app.

## Khi có leak

### Report

```
[TLeakDetector] LEAK ProfileViewController (screen)
  also alive: ProfileViewModel  ProfileViewController.viewModel
  retain cycle: ProfileViewController._worker → ProfileWorker._delegate → ProfileViewController
  fix: declare `ProfileWorker.delegate` as `@property (weak)`
```

Đọc từ trên xuống: **ai bị leak** (dòng `LEAK`), **cái gì của nó còn sống** (`also alive`), **vì sao** (chuỗi model nào
giữ model nào, qua field nào), **sửa ở đâu** (`fix:`). Tool không biết số dòng code; tìm field bằng ⇧⌘O trong Xcode,
ví dụ `ProfileWorker.delegate`. Không tìm được nguyên nhân (ví dụ bị biến static giữ) thì report chỉ có dòng `LEAK`.

Report đi qua `os_log`, subsystem `TLeakDetector`. Ngoài console của Xcode, có thể lọc trong Console.app bằng
`subsystem:TLeakDetector`.

| Dòng | Nghĩa |
|---|---|
| `LEAK <Type> (<kind>)` | Object bị leak, gần màn hình gốc nhất, và loại leak (xem bảng dưới) |
| `path:` | Chỉ có khi object không phải chính màn hình: đường từ màn hình tới nó, ví dụ `ProfileVC.viewModel` |
| `also alive:` | Model, child VC… của màn hình vẫn còn sống (tối đa 5). View không được liệt kê: màn hình còn sống thì view còn sống |
| `retain cycle:` | Cycle strong reference `A.field → B.field → A`. Mọi bước đều chắc chắn là strong, nên báo ngay sau 2 giây. Field bắt đầu bằng `_` là ivar Objective-C |
| `possible retain cycle (? may be weak):` | Cycle có bước đánh dấu `?`: tool không chứng minh được bước đó là strong |
| `held by …:` | Không có cycle: một thứ bên ngoài màn hình đang giữ object (Task đang chạy, Timer còn valid, CADisplayLink, observer chưa remove, URLSession chưa invalidate), kèm chuỗi tham chiếu |
| `… is still running` | Màn hình đã chết nhưng Task nó khởi chạy vẫn chạy (thường do `for await` trên stream không bao giờ finish) |
| `fix:` | Gợi ý cách sửa, đúng cú pháp Swift hoặc Objective-C |
| `suppressed until …` | Leak có trong [suppression file](#suppression-file): chỉ log, không dừng app |

Chạy với `TLEAK_VERBOSE=1` để report có thêm: sống thêm bao lâu sau sự kiện nào, địa chỉ object (để `po` trong lldb
hoặc tìm trong Memory Graph), mọi object còn sống kể cả view, tool đã tìm những gì khi không ra nguyên nhân, và graph
đầy đủ dạng `.dot`/`.json` (`dot -Tsvg file.dot -o graph.svg`, cần `brew install graphviz`).

| `kind` | Nghĩa | Thường sửa ở đâu |
|---|---|---|
| `screen` | Chính màn hình vừa đóng vẫn còn sống | Closure bắt `self`, delegate strong, Timer, observer, Task… trong màn hình đó |
| `outlived` | Màn hình đã chết nhưng một object nó giữ, hoặc một Task nó khởi chạy, vẫn sống | Ai đang giữ object (singleton, cache, NotificationCenter…), hoặc Task chưa được cancel |
| `budget` | Số instance của một type cùng sống vượt [budget](#instance-budget) | Instance cũ không được giải phóng khi mở instance mới |

### Sửa leak thường gặp

| Report cho thấy | Cách sửa |
|---|---|
| Closure của app trong cycle | `[weak self]` trong đúng closure được nêu |
| Field kiểu `delegate` / `dataSource` | Swift: `weak var delegate`, protocol kế thừa `AnyObject`. ObjC: `@property (weak)` |
| `held by Timer` | `invalidate()` ở `viewDidDisappear`, hoặc timer dùng block với `[weak self]` |
| `held by CADisplayLink` | `invalidate()` khi màn hình đóng, hoặc dùng weak proxy làm target |
| Observer của NotificationCenter | `removeObserver(token)` khi đóng, block dùng `[weak self]` |
| URLSession giữ delegate | `finishTasksAndInvalidate()` khi xong việc |
| `WKUserContentController` giữ handler | `removeScriptMessageHandler(forName:)`, hoặc weak proxy |
| `Subscribers.Sink` (Combine) | `[weak self]` trong `sink`, hoặc `assign(to: &$property)` |
| `held by a running Task` / `still running` | Giữ handle của Task và `cancel()` ở `viewDidDisappear`; với `AsyncStream` thì `continuation.finish()` |
| `associated <key>` | `.OBJC_ASSOCIATION_ASSIGN`, hoặc lưu weak box |
| `no retain cycle` | Tìm biến static, singleton, cache đang giữ màn hình (Memory Graph) |

### Đổi cách báo

Mặc định: có debugger thì app dừng (`SIGTRAP`, bấm Continue chạy tiếp), không có debugger thì app crash kèm report.
Đổi bằng biến môi trường trong scheme (**Edit Scheme › Run › Arguments › Environment Variables**):

| Biến | Giá trị | Ý nghĩa |
|---|---|---|
| `TLEAK_MODE` | `debugger`, `crash`, `log` | `log`: chỉ ghi log, không dừng app. Ghi đè `LeakConfiguration.mode` |
| `TLEAK_VERBOSE` | `1` | Report có thêm thời gian, địa chỉ, mọi object còn sống, graph `.dot`/`.json`; log mỗi lần mark màn hình và mỗi lần search |

## Cảnh báo sớm

Lúc màn hình đóng, trước khi biết có leak hay không, tool cảnh báo các bẫy kinh điển. Cảnh báo chỉ được log
(category `warning`), mỗi chỗ một lần, **không bao giờ dừng app**. Mục đích là bắt cả những chỗ chưa leak nhưng sẽ leak.

```
[TLeakDetector] WARNING strongDelegate: Parser.delegate holds Logger strongly
  seen when SettingsViewController closed (pop): it leaks unless something releases it later
  fix: declare `Parser.delegate` as `weak var` (and its protocol as `AnyObject`)
```

| Pattern | Khi nào |
|---|---|
| `strongDelegate` | Property `delegate` hoặc `dataSource` strong trong class của app |
| `timerTarget` | Timer còn valid có target là màn hình, hoặc block của nó giữ màn hình |
| `displayLinkTarget` | CADisplayLink chưa invalidate có target là màn hình |
| `urlSessionDelegate` | URLSession chưa invalidate có delegate là màn hình |
| `scriptMessageHandler` | `WKUserContentController` còn giữ màn hình làm script message handler |
| `observerBlock` | Observer của NotificationCenter chưa remove có block giữ màn hình (`[weak self]` thì không cảnh báo) |

Tắt từng pattern bằng `LeakChecks(ignoredPatterns: [.strongDelegate])`.

## Cấu hình

`install()` nhận một `LeakConfiguration`. Mọi tham số đều có giá trị mặc định, chỉ truyền cái cần đổi:

```swift
#if DEBUG
TLeakDetector.install(LeakConfiguration(
    allowedTypes: [MiniPlayerViewController.self],
    instanceBudgets: [LeakInstanceBudget(ProfileViewModel.self, max: 1)]
))
#endif
```

| Tham số | Mặc định | Ý nghĩa |
|---|---|---|
| `t1`, `t2` | `2`, `8` | Số giây sau khi đóng màn hình: lần kiểm tra đầu (báo ngay nếu cycle chắc chắn) và lúc báo các trường hợp còn lại |
| `mode` | `nil` | `.crash`, `.debugger`, `.log`. `nil`: có debugger thì dừng, không thì crash |
| `allowedTypes` | `[]` | Type được phép sống sau khi màn hình đóng, tính cả subclass |
| `maxSubtreeDepth` | `nil` | Số bước bên dưới màn hình được theo dõi. `nil` là không giới hạn |
| `suppressionFile` | `LeakSuppressions.json` trong bundle chính | File liệt kê leak đã biết |
| `instanceBudgets` | `[]` | Số instance tối đa của một type được sống cùng lúc |
| `graph` | `LeakGraphOptions()` | Tìm retain cycle, xem [dưới](#tìm-retain-cycle) |
| `checks` | `LeakChecks()` | Task, hook hệ thống và cảnh báo, xem [dưới](#task-hook-hệ-thống-và-cảnh-báo) |

### Màn hình được phép sống lại

Màn hình được cache để mở lại (mini player, tab giữ trạng thái…) sẽ bị báo leak nếu không khai báo. Có hai cách:

```swift
LeakConfiguration(allowedTypes: [MiniPlayerViewController.self])
```

```swift
#if DEBUG
extension MiniPlayerViewController: LeakOptOut {}
#endif
```

Type được phép thì view, child và những gì nó giữ cũng không bị theo dõi. `LeakOptOut` không tồn tại ở Release, nên
conformance phải bọc `#if DEBUG`.

### Instance budget

Bắt leak không đi qua sự kiện đóng màn hình nào, ví dụ container tự viết quên gọi `willMove(toParent: nil)`, hoặc
object tích luỹ qua nhiều lần mở: khai báo type X chỉ được có tối đa N instance cùng sống.

```swift
LeakConfiguration(instanceBudgets: [
    LeakInstanceBudget(ProfileViewController.self, max: 1),
    LeakInstanceBudget(ProfileViewModel.self, max: 1),
])
```

- View controller được đếm tự động ở `viewDidLoad`.
- Object khác tự đăng ký ở cuối `init` (gọi từ thread nào cũng được):

  ```swift
  init() {
      …
      #if DEBUG
      TLeakDetector.track(self)
      #endif
  }
  ```

Vượt budget thì báo `LEAK <Type> (budget)`. Subclass được tính chung vào budget của class cha.

### Suppression file

Dùng khi áp dụng tool vào codebase cũ: leak đã biết chỉ được log, không dừng app, cho tới ngày hết hạn. Hết hạn thì
leak bị báo lại như mới. Thêm file `LeakSuppressions.json` vào bundle của app:

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

- `signature.type` là tên type ở dòng `LEAK`, `signature.kind` là giá trị trong ngoặc ngay sau tên type (`screen`, `outlived`, `budget`).
- Thêm `"cycle": "ProfileVC.viewModel → ProfileViewModel.onChange → ProfileVC"` vào `signature` để chỉ bỏ qua đúng cycle đó.
- `expires` dạng `yyyy-MM-dd`, còn hiệu lực hết ngày đó. `reason` và `owner` là bắt buộc.
- Entry sai format bị bỏ qua, file sai cú pháp JSON bị bỏ qua toàn bộ. Lỗi được log ở category `config`, không crash app.
- Chỉ đưa file vào bundle Debug: đặt `EXCLUDED_SOURCE_FILE_NAMES = LeakSuppressions.json` cho configuration Release.

### Tìm retain cycle

Khi màn hình còn sống ở giây thứ 2, tool đọc strong reference thật trong bộ nhớ (field Swift, closure, ivar ObjC,
block, collection, associated object), tìm cycle ngắn nhất qua màn hình. Không có cycle thì tìm tiếp ai đang giữ nó.
Search chạy trên main thread từng lát khoảng 4 ms để không làm giật app.

```swift
LeakConfiguration(graph: LeakGraphOptions(prunedModules: ["Combine"]))
```

| `LeakGraphOptions` | Mặc định | Ý nghĩa |
|---|---|---|
| `isEnabled` | `true` | `false`: không tìm cycle, chỉ báo ở giây thứ 8 và không có nguyên nhân |
| `maxDepth` | `16` | Cycle dài nhất được tìm |
| `maxNodes` | `1000` | Số object tối đa mỗi lần search |
| `maxDuration` | `0.1` | Tổng số giây mỗi lần search, cộng mọi lát |
| `sliceDuration` | `0.004` | Độ dài mỗi lát trên main thread |
| `prunedModules` | `[]` | Module được ghé qua nhưng không duyệt tiếp, ví dụ `["UIKitCore"]` |
| `exportDirectory` | thư mục tạm của app + `TLeakDetector/` | Nơi ghi file DOT/JSON của mỗi report khi `TLEAK_VERBOSE=1`. `nil`: không ghi |

Trong Instruments, mỗi lần search hiện thành một interval "retain graph" (os_signpost, category `graph`).

### Task, hook hệ thống và cảnh báo

Lúc `install()`, tool hook việc tạo Task và các hàm tạo Timer, CADisplayLink, observer, URLSession,
WKScriptMessageHandler, để biết ai đang giữ màn hình.

| `LeakChecks` | Mặc định | Ý nghĩa |
|---|---|---|
| `isEnabled` | `true` | Hook Timer, CADisplayLink, NotificationCenter, URLSession, WKUserContentController và cảnh báo lúc màn hình đóng |
| `ignoredPatterns` | `[]` | Các pattern không cảnh báo |
| `tracksTasks` | `true` | Theo dõi Task. Task còn chạy 8 giây sau khi màn hình đóng bị báo `outlived`. Tắt nếu app có Task chạy dài hợp lệ |

## Giới hạn

- Chỉ màn hình compile trong target app mới được theo dõi. View controller nằm trong dynamic framework bị bỏ qua.
- Container tự viết phải gọi `willMove(toParent: nil)` trước `removeFromParent()`, đúng contract của UIKit. Nếu không,
  child không được theo dõi; chỉ [instance budget](#instance-budget) bắt được.
- Task, Timer, observer, associated object chỉ được thấy nếu tạo **sau** `install()`, từ code của app.
- Biến static, singleton giữ màn hình: report chỉ ghi "no retain cycle", không chỉ ra được ai giữ.
- Struct C/C++ bên trong framework hệ thống không đọc được.
- Một Task chạy hợp lệ quá 8 giây sau khi màn hình đóng (ví dụ tải file dài với `[weak self]`) sẽ bị báo. Tắt bằng
  `LeakChecks(tracksTasks: false)`.

## Kiểm tra tool không lọt vào Release

Có ba lớp: mọi file của tool bọc `#if LEAK_DETECTOR_ENABLED` (chỉ bật ở debug), app bọc `#if DEBUG`, và script quét binary:

```sh
scripts/check-release-symbols.sh                                    # archive AppDemo Release, fail nếu thấy symbol của tool
scripts/check-release-symbols.sh --project App.xcodeproj --scheme App --configuration Release   # app của bạn
scripts/check-release-symbols.sh --configuration Debug --expect-present                          # kiểm tra ngược: Debug phải có
```

Script archive app, chạy `nm` và `strings` trên mọi Mach-O trong `.app`, fail nếu thấy tên module, flag hoặc tên type
của tool. Nếu project có configuration riêng, chạy với `--configuration <tên>` cho từng cái. Chi tiết:
[ADR 001](docs/adr/001-exclude-from-release.md).

## App demo

[AppDemo/](AppDemo/) là app UIKit (Swift + Objective-C) chứa 72 màn hình leak và không leak **đã biết đáp án**: block và
closure bắt `self`, delegate strong, Timer, observer, KVO, Task, singleton, biến static, cycle giữa Swift và ObjC, và các
luồng giống app thật. App cũng là ví dụ tích hợp: xem [AppDelegate.swift](AppDemo/AppDemo/App/AppDelegate.swift) và
[LeakSuppressions.json](AppDemo/AppDemo/LeakSuppressions.json).

```sh
open AppDemo/AppDemo.xcodeproj          # chạy trên simulator, mở rồi đóng từng màn hình để xem report
AppDemo/scripts/demo-autorun.sh         # tự mở/đóng mọi màn hình, chấm theo expected.json, ghi AppDemo/RESULTS.md
```

- [expected.json](AppDemo/expected.json) ghi đáp án: một detector đúng phải báo gì cho từng màn hình.
- `demo-autorun.sh` build app, chạy với `--autorun` và `TLEAK_MODE=log`, đọc report của tool và log `deinit`, rồi so với
  đáp án. Exit 1 nếu có màn hình lệch.
- Kết quả mới nhất và phân tích từng case lệch: [AppDemo/RESULTS.md](AppDemo/RESULTS.md).

## Phát triển tool

```sh
open AppDemo/AppDemo.xcodeproj    # package được tham chiếu local: sửa code tool rồi ⌘R là thấy ngay
xed .                             # chỉ package: chọn iOS Simulator rồi ⌘U để chạy cả test UIKit
swift build && swift test         # test trên macOS (phần không cần UIKit)
```

```
├── Package.swift                 product "TLeakDetector"
├── Sources/
│   ├── LeakUIKit/                API public TLeakDetector, hook UIViewController, gom những gì màn hình phải giải phóng
│   ├── LeakCore/                 giữ weak, hẹn giờ, quyết định có leak, nguyên nhân, gợi ý sửa, report; không import UIKit
│   ├── LeakHeap/                 đọc strong reference của object thật: Swift, ObjC, block, associated object
│   ├── LeakGraph/                graph strong reference, BFS tìm cycle ngắn nhất, export DOT/JSON
│   ├── LeakConcurrency/          Task đang chạy: hook swift_task_create, Task giữ ai, Task sống tiếp
│   └── LeakPatterns/             Timer, CADisplayLink, observer, URLSession, WKUserContentController; cảnh báo
├── Tests/                        test cho từng target; LeakHeapFixtures là class ObjC thật cho LeakHeapTests
├── AppDemo/                      app demo, 72 màn hình có đáp án, script chấm điểm
├── scripts/check-release-symbols.sh
└── docs/adr/                     các quyết định kiến trúc
```

Chiều phụ thuộc chỉ có một hướng: `LeakUIKit → LeakConcurrency, LeakPatterns → LeakCore, LeakHeap → LeakGraph`.
Mọi file source phải bọc `#if LEAK_DETECTOR_ENABLED`; flag này chỉ bật ở configuration debug trong `Package.swift`.

| ADR | Nội dung |
|---|---|
| [001](docs/adr/001-exclude-from-release.md) | Loại tool khỏi Release: flag trong package, `#if DEBUG` trong app, script kiểm tra binary |
| [002](docs/adr/002-swift-field-ownership.md) | Đọc ownership của field Swift từ reflection metadata |
| [003](docs/adr/003-leak-kind.md) | `kind` của leak (`screen`, `outlived`, `budget`) mô tả điều quan sát được và không bao giờ đổi tên |
| [004](docs/adr/004-retain-graph.md) | Retain graph: đọc strong reference an toàn, certain/uncertain, báo sớm, ngân sách main thread |
| [005](docs/adr/005-closures-concurrency-patterns.md) | Closure generic và block Swift; theo dõi Task; hook Timer, observer…; tìm ai đang giữ; cảnh báo và gợi ý sửa |
