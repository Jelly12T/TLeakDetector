# TLeakDetector

Tool phát hiện memory leak của UIViewController trên iOS, **chỉ chạy ở Debug**.
Bản Release vẫn build module nhưng module rỗng, không có symbol nào của tool.

> **Trạng thái: S5–7 (closure, concurrency, bẫy kinh điển).** `TLeakDetector.install()` tự mark VC khi rời màn hình
> (pop, dismiss, remove child, đổi `rootViewController`), mark cả subtree, check T1 (2 giây) / T2 (8 giây) rồi báo leak
> (xem [Khi có leak](#khi-có-leak)). Ở T1, tool tìm retain cycle qua object còn sống, cycle chắc chắn thì báo ngay.
> Không có cycle thì tool tìm **ai đang giữ** object: Task đang chạy, Timer, observer, CADisplayLink, URLSession.
> Mỗi report kèm dòng `fix:` gợi ý cách sửa (xem [Retain graph](#retain-graph)). Task còn chạy sau khi màn hình đã chết
> cũng bị báo. Lúc màn hình đóng, tool cảnh báo sớm các bẫy kinh điển, kể cả khi chưa leak (xem [Cảnh báo](#cảnh-báo)).
> Instance budget bắt thêm những leak không đi qua sự kiện rời màn hình nào.
> LeakZoo: 27/27 scenario khớp đáp án, xem [LeakZoo/RESULTS.md](LeakZoo/RESULTS.md).
> Chạy với env `TLEAK_VERBOSE=1` để log mỗi lần mark.
>
> Giới hạn hiện tại:
> - Chỉ VC compile trong app target mới được mark. VC nằm trong dynamic framework bị bỏ qua.
> - Container tự viết phải gọi `willMove(toParent: nil)` trước `removeFromParent()`, đúng contract của UIKit.
>   Nếu không, child không bị mark; chỉ [instance budget](#instance-budget) bắt được leak của nó.
> - Retain graph chưa thấy struct C/C++ của framework, associated object do framework hệ thống set, và biến static
>   hay singleton giữ object (khi đó report ghi "no cycle"). Xem [ADR 004](docs/adr/004-retain-graph.md).
> - Task, Timer, observer… chỉ được thấy nếu tạo **sau** `install()`, và từ code của app. Xem [ADR 005](docs/adr/005-closures-concurrency-patterns.md).
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
| `retain cycle (certain):` | Cycle strong reference, mỗi dòng một bước: `A.field → B`. Mọi bước đều chắc chắn là strong, nên report ra ngay ở T1 |
| `possible retain cycle …` | Cycle có bước đánh dấu `?`: tool không chứng minh được bước đó là strong (thường là block do Swift tạo) |
| `no retain cycle through it` | Không có cycle: object bị giữ từ bên ngoài màn hình (timer, observer, task, singleton) |
| `no retain cycle found … partly read` | Không tìm thấy, nhưng có object chỉ đọc được một phần, nên chưa loại trừ được cycle |
| `retain cycle search stopped at the … limit` | Search chạm giới hạn độ sâu, số object hoặc thời gian trước khi kết luận |
| `held by a running Task (…):` | Không có cycle: một root bên ngoài màn hình giữ object, kèm chuỗi tham chiếu từ root. Root có thể là Task đang chạy, Timer còn valid, CADisplayLink chưa invalidate, observer chưa remove, hoặc URLSession chưa invalidate |
| `Task (…) is still running` | Leak là một Task mà màn hình đã khởi chạy: màn hình đã chết, Task vẫn chạy (thường do `for await` trên stream không bao giờ finish) |
| `fix: …` | Gợi ý cách sửa theo hình dạng nguyên nhân: `[weak self]` trong đúng closure, `weak var delegate`, invalidate timer, cancel task… |
| `graph: …dot` / `…json` | Graph đã duyệt, cycle tô đỏ. Xem bằng `dot -Tsvg file.dot -o graph.svg` (`brew install graphviz`) |

| `kind` | Nghĩa | Thường sửa ở đâu |
|---|---|---|
| `screen` | Chính màn hình vừa đóng vẫn còn sống | Closure bắt `self`, delegate strong, Timer, observer, Task… trong VC đó |
| `outlived` | Màn hình đã chết nhưng một object nó giữ (hoặc một Task nó khởi chạy) vẫn sống | Ai đang giữ object (singleton, cache, NotificationCenter…), hoặc Task chưa được cancel. Nếu object dùng chung có chủ đích thì thêm vào `allowedTypes` |
| `budget` | Số instance của một type cùng sống vượt budget đã khai báo | Instance cũ không được giải phóng khi mở instance mới |

`kind` mô tả điều tool quan sát được, không mô tả nguyên nhân, và không bao giờ đổi tên ([ADR 003](docs/adr/003-leak-kind.md)).
Nguyên nhân (cycle, held by, still running) là các dòng riêng ngay sau `path:`.

### Cảnh báo

Lúc màn hình đóng, trước khi biết có leak hay không, tool cảnh báo các bẫy kinh điển trong những gì màn hình phải giải
phóng. Cảnh báo chỉ được log (category `warning`), mỗi chỗ một lần, và không bao giờ dừng app.

```
[TLeakDetector] WARNING strongDelegate: Z26Parser.delegate holds Z26Logger strongly
  seen when Z26StrongDelegateNoLeakViewController closed (pop): it leaks unless something releases it later
  fix: declare `Z26Parser.delegate` as `weak var` (and its protocol as `AnyObject`)
```

| Pattern | Khi nào |
|---|---|
| `strongDelegate` | Property `delegate` hoặc `dataSource` strong trong class của app |
| `timerTarget` | Timer còn valid có target là màn hình, hoặc block của nó giữ màn hình |
| `displayLinkTarget` | CADisplayLink chưa invalidate có target là màn hình |
| `urlSessionDelegate` | URLSession chưa invalidate có delegate là màn hình (session giữ delegate tới khi invalidate) |
| `scriptMessageHandler` | `WKUserContentController` còn giữ màn hình làm script message handler |
| `observerBlock` | Observer của NotificationCenter chưa remove có block giữ màn hình (`[weak self]` thì không cảnh báo) |

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

### Retain graph

Ở T1, tool duyệt graph strong reference từ object còn sống, tìm cycle ngắn nhất đi qua nó. Cách tool biết một ref
là strong:

- **Swift:** field metadata (bỏ `weak`, `unowned`), capture của closure, giá trị trong struct, collection,
  property wrapper.
- **Objective-C:** ARC ivar layout, extended layout của block, `NSArray`/`NSDictionary`/`NSSet`, và chỉ những
  `NSHashTable`/`NSMapTable` giữ strong.
- **Associated object:** tool hook `objc_setAssociatedObject` trong các image của app ngay khi `install()`.
- **UIKit:** subview của view.
- **Closure generic và block do Swift tạo** (ví dụ bên trong Combine, handler của `UIAction`): đọc được capture.
- **Hệ thống:** Timer → target/block, CADisplayLink → target, observer → block, URLSession → delegate,
  `WKUserContentController` → handler. Tool hook các hàm tạo ra chúng ngay khi `install()`.
- **Task:** tool hook `swift_task_create` trong image của app, nên biết Task nào đang chạy và operation của nó bắt gì.

Không có cycle chắc chắn thì tool tìm tiếp từ các Task đang chạy và những thứ hệ thống đang giữ (timer, observer…)
tới object, để chỉ ra **ai đang giữ** nó.

Chỗ nào không rõ layout thì tool chỉ so địa chỉ với object đã biết và đánh dấu `?`. Chi tiết và số đo nằm ở
[ADR 004](docs/adr/004-retain-graph.md) và [ADR 005](docs/adr/005-closures-concurrency-patterns.md).

```swift
TLeakDetector.install(LeakConfiguration(graph: LeakGraphOptions(prunedModules: ["Combine"])))
```

| `LeakGraphOptions` | Mặc định | Ý nghĩa |
|---|---|---|
| `isEnabled` | `true` | `false`: không tìm cycle, report chỉ có từ T2 và không ghi nguyên nhân |
| `maxDepth` | `16` | Cycle dài nhất được tìm |
| `maxNodes` | `1000` | Số object tối đa mỗi lần search |
| `maxDuration` | `0.1` | Tổng số giây mỗi lần search, cộng mọi lát |
| `sliceDuration` | `0.004` | Search chạy trên main thread từng lát, mỗi lát chừng này giây, để không gây hitch |
| `prunedModules` | `[]` | Module có object được ghé qua nhưng không duyệt tiếp, ví dụ `["UIKitCore"]` |
| `exportDirectory` | thư mục tạm của app + `TLeakDetector/` | Nơi ghi DOT và JSON của mỗi report. `nil`: không ghi |

Trên simulator, thư mục tạm của app nằm ngay trên ổ của máy Mac: dòng `graph:` trong report là đường dẫn mở được luôn.
Chạy với `TLEAK_VERBOSE=1` để log số object và thời gian của mỗi lần search. Trong Instruments, mỗi lần search hiện
thành một interval "retain graph" (os_signpost, category `graph`).

`LeakConfiguration.checks` (`LeakChecks`) điều khiển phần Task, hệ thống và cảnh báo:

| `LeakChecks` | Mặc định | Ý nghĩa |
|---|---|---|
| `isEnabled` | `true` | Hook Timer, CADisplayLink, NotificationCenter, URLSession, WKUserContentController lúc `install()`, và cảnh báo lúc màn hình đóng |
| `ignoredPatterns` | `[]` | Các pattern không cảnh báo, ví dụ `[.strongDelegate]` |
| `tracksTasks` | `true` | Hook việc tạo Task. Task còn chạy 8 giây sau khi màn hình đóng sẽ bị báo `outlived`, nên tắt đi nếu app có Task chạy dài hợp lệ |

Entry suppression có thể ghi thêm hình dạng cycle để chỉ bỏ qua đúng cycle đó:
`"signature": { "type": "ProfileVC", "kind": "screen", "cycle": "ProfileVC.viewModel → ProfileViewModel.onChange → ProfileVC" }`.

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
│   ├── LeakGraph/                object và strong reference thành graph, tìm cycle ngắn nhất, export DOT/JSON
│   ├── LeakHeap/                 đọc strong reference của object thật: Swift, ObjC, block, associated object
│   ├── LeakConcurrency/          Task đang chạy: hook swift_task_create, Task giữ ai, Task sống tiếp
│   ├── LeakPatterns/             Timer, CADisplayLink, observer, URLSession, WKUserContentController; cảnh báo
│   ├── LeakCore/                 quyết định có leak hay không, nguyên nhân, gợi ý sửa; không import UIKit
│   └── LeakUIKit/                hook vào UIViewController, API public TLeakDetector
├── Tests/                        test cho từng target; LeakHeapFixtures là class ObjC thật cho LeakHeapTests
├── scripts/
│   ├── check-release-symbols.sh  kiểm tra tool không lọt vào Release
│   └── zoo-autorun.sh            chạy LeakZoo trên simulator, chấm theo expected.json
├── Examples/HostApp/             app tối giản để script trên archive
├── LeakZoo/                      app 27 scenario leak / không leak, kèm expected.json và RESULTS.md
├── Workspace/                    JellyLeakDetector.xcworkspace để mở mọi thứ trong Xcode
├── Spikes/                       thí nghiệm có timebox, không phải code production
└── docs/adr/                     các quyết định kiến trúc
```

| Target | Vai trò |
|---|---|
| `LeakGraph` | Biểu diễn object và strong reference thành graph. BFS tìm cycle ngắn nhất đi qua object bị nghi, có giới hạn độ sâu và số object, bỏ qua (prune) các module được chỉ định. Không biết gì về leak hay UIKit. |
| `LeakHeap` | Đọc strong reference của object đang sống: field Swift (ADR 002), closure, ivar ObjC, block, collection, associated object. Nguồn cho `LeakGraph`. Không import UIKit. |
| `LeakConcurrency` | Task đang chạy: hook `swift_task_create` ở image của app, giữ Task và context của operation mà không giữ chúng sống. Cho biết Task nào giữ object, Task nào sống lâu hơn màn hình. |
| `LeakPatterns` | Những gì hệ thống giữ mà không ivar nào cho thấy (Timer, CADisplayLink, observer, URLSession, WKUserContentController), biết được nhờ hook. Cảnh báo bẫy kinh điển lúc màn hình đóng. |
| `LeakCore` | Quyết định có leak hay không, nguyên nhân và gợi ý sửa. Không import UIKit. |
| `LeakUIKit` | Hook vào UIViewController, báo tin cho `LeakCore`. Chứa API public `TLeakDetector`. |
| `LeakGraphTests` | Test cho `LeakGraph`, chạy trên macOS và simulator. |
| `LeakHeapTests` | Test cho `LeakHeap` trên object thật, kể cả class ObjC trong `LeakHeapFixtures`. |
| `LeakCoreTests` | Test cho `LeakCore`. |
| `LeakConcurrencyTests` | Test cho `LeakConcurrency`, với Task thật. |
| `LeakPatternsTests` | Test cho `LeakPatterns`, với Timer, observer, URLSession thật. |
| `LeakUIKitTests` | Test cho `LeakUIKit`, chạy trên iOS Simulator. |

Chiều phụ thuộc chỉ có một hướng: `LeakUIKit → LeakConcurrency, LeakPatterns → LeakCore, LeakHeap → LeakGraph`.
`LeakCore` và `LeakHeap` không biết nhau. Các target khác được thêm khi tới sprint cần.

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

[LeakZoo/](LeakZoo/) là app UIKit cố ý chứa 27 scenario **đã biết đáp án**. Mỗi sprint dùng nó để chấm tool:
14 case leak phải được báo, 2 case Task/observer sống tiếp sau màn hình phải được báo, 9 case không leak hoặc được phép
sống không được báo, 1 case đã suppress chỉ được log, và 1 case chỉ instance budget mới bắt được. Mỗi case còn ghi
các cảnh báo phải có (và chỉ những cảnh báo đó). RESULTS.md cho thấy nguyên nhân, gợi ý sửa và cảnh báo của từng case.

| Nhóm | Case | Ví dụ |
|---|---|---|
| Leak, cycle | Z01–Z06, Z21, Z24, Z25 | closure bắt `self`, delegate strong, `UIAction`, child VC, popToRoot, Combine `sink`, associated object, URLSession delegate, WKScriptMessageHandler |
| Leak, rooted | Z07–Z10, Z23 | Timer không invalidate, observer không remove, Task trên AsyncStream không finish, biến static, CADisplayLink |
| Sống tiếp sau màn hình | Z22, Z27 | Task `[weak self]` chờ mãi trên stream, observer `[weak self]` không remove |
| Không leak | Z11–Z16, Z26 | `[weak self]`, Task bị cancel, Timer được invalidate, `asyncAfter` (deinit trễ khoảng 1 giây), child và popToRoot đúng cách, delegate strong chưa tạo cycle (chỉ cảnh báo) |
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
| [004](docs/adr/004-retain-graph.md) | Retain graph ở T1: đọc strong reference an toàn, certain/uncertain, báo sớm, ngân sách trên main thread và số đo |
| [005](docs/adr/005-closures-concurrency-patterns.md) | Spike closure context; closure generic và block Swift; Task (hook `swift_task_create`); hook Timer, observer…; tìm ai đang giữ; cảnh báo và gợi ý sửa |
