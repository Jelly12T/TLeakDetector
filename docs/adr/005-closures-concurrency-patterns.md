# ADR 005: Closure, block, Task và các bẫy kinh điển

- Trạng thái: Đã chấp nhận
- Ngày: 2026-11-10

## Bối cảnh

Hết S3–4, retain graph còn ba chỗ mù (ADR 004):

1. **Closure generic** (bên trong Combine, Z06) và **block do Swift tạo** (handler của `UIAction`, Z03): chỉ so được địa chỉ, nên cycle hoặc không thấy, hoặc chỉ là "possible".
2. **Leak bị giữ từ bên ngoài** (Z07–Z10): report chỉ nói "không có cycle", không nói ai đang giữ.
3. **Concurrency**: tool không biết Task nào đang chạy. Một Task bắt `[weak self]` mà chờ mãi trên một stream không bao giờ finish thì màn hình chết bình thường, nhưng Task sống mãi. Trường hợp này không ai báo.

S5–7 mở đầu bằng một spike có timebox, để trả lời: đọc được capture của closure context tới đâu, và theo dõi Task mà không giữ nó lại được không.

## Kết quả spike

Thí nghiệm chạy trên macOS (arm64e) và iPhone 17 Pro simulator (iOS 26.3).

| Câu hỏi | Trả lời |
|---|---|
| Context của closure generic có đọc được không? | **Được.** `OffsetToFirstCapture` trỏ vào `NumBindings` word (metadata và witness table của generic argument), capture nằm ngay sau đó. Metadata source dạng `B<n>` cho biết tham số generic nào lấy từ binding nào. Capture có type là tham số generic trần (`x`, `q_`) thì lấy layout từ binding. Capture là hàm thick (mangled kết thúc bằng `I…g…_`) thì luôn là 2 word (hàm, context), dù type của nó generic |
| Block do Swift tạo có cấu trúc thế nào? | Luôn dài 48 byte, có copy/dispose helper, không có extended layout. Tại +32 là con trỏ hàm, tại +40 là context mà copy helper đã retain. Khi app chuyển closure thành block, invoke là reabstraction thunk `…IeyB_TR` nằm trong image của app. **Handler của `UIAction` thì do code Swift trong UIKitCore tạo**, nên không có symbol nào của app để dựa vào |
| `Subscribers.Sink` của Combine là `CustomReflectable`, nên `Mirror` không cho thấy field nào. Có cách khác không? | Có. Dùng chính các hàm mà `Mirror` dựa vào: `swift_reflectionMirror_recursiveCount`, `…ChildMetadata` và `…ChildOffset`. Chúng cho offset và type đã thay generic argument, tính cả các class cha. **Bẫy:** `…ChildMetadata` nhận 3 tham số, tham số thứ ba là con trỏ tới struct `_FieldReflectionMetadata` (name, freeFunc, isStrong, isVar). Khai báo nhầm thành 4 tham số thì runtime ghi đè lên stack và crash |
| `[weak self]` được lưu ra sao? | Là một box (`…SgXwz_Xx`) chứa weak reference. Đọc được bằng `swift_unknownObjectWeakLoadStrong`, cho cả object Swift lẫn ObjC |
| Có biết được Task nào được tạo không? | Được. `Task.init` là `@_alwaysEmitIntoClient`, nên lời gọi `swift_task_create` nằm trong image của app và rebind được, giống cách hook associated object. Giá trị trả về là 2 word (`AsyncTaskAndContext`), nằm trong x0/x1, nên khai báo hook bằng `ldiv_t` |
| Context `swift_task_create` nhận được có giữ được lâu không? | **Không.** Đó là wrapper generic mà `Task.init` dựng quanh operation, và nó bị giải phóng ngay khi Task bắt đầu chạy. Operation (hàm và context) chuyển vào frame của Task, nên phải đọc nó ngay lúc tạo Task, rồi giữ context của operation |
| Có theo dõi được mà không giữ Task lại không? | Task thì được: `swift_weakInit` dùng được với `AsyncTask`. Closure context thì không: `swift_weakInit` crash. Với context, giữ unowned count (`swift_unownedRetain`), rồi trước mỗi lần đọc thì `swift_tryRetain`. **Bẫy:** `swift_tryRetain` trả về con trỏ, không phải `bool`. Đọc nó như `Bool` là đọc bit 0, mà địa chỉ căn 16 byte thì bit 0 luôn bằng 0 |
| Task đã xong mà ai đó vẫn giữ handle thì sao? | Context của operation được giải phóng khi operation return, kể cả khi handle vẫn còn. Nên "Task còn chạy" nghĩa là Task còn sống **và** context của operation còn sống |
| "Image hệ thống" bằng `_dyld_shared_cache_contains_path` có đúng mọi nơi không? | Không. Trên simulator, khi chạy test, ngay cả libobjc cũng không nằm trong shared cache. Image hệ thống giờ là: nằm trong shared cache, hoặc có đường dẫn thuộc `/RuntimeRoot/`, `/System/` hay `/usr/lib/`. Bảng image được đọc lại khi gặp một địa chỉ lạ mà có thêm image mới được load |

Kết luận: **GO** cho cả ba hướng.

## Quyết định

### 1. Closure và block provider (LeakHeap)

- Context generic: đọc binding, rồi capture theo bảng trên. Nguồn generic nào không phải closure binding thì vẫn quay về chỉ so địa chỉ.
- Field của class Swift đọc bằng các hàm reflection của runtime, theo offset, kèm ownership lấy từ field metadata của từng class (ADR 002). Nhờ vậy không còn phụ thuộc `Mirror`: custom mirror không che được field, và không phải tạo một `Mirror` cho mỗi object.
- Block do Swift tạo là **certain**. Nhận biết bằng một trong hai cách:
  - symbol thunk, nếu block được tạo trong app;
  - hình dạng: 48 byte, có copy/dispose, không có layout của clang, +32 là code. Thêm vào đó, +40 phải là nil, hoặc object đã có trong graph, hoặc closure context hợp lệ.

  Một block clang có đúng hình dạng đó mà biên dịch không bật ARC thì cũng retain word ở +40, nên kết luận "strong" vẫn đúng.
- Biến `__block` (byref) được đọc theo layout của byref (`BLOCK_BYREF_LAYOUT_STRONG`).

### 2. LeakConcurrency: Task

- `TaskRegistry` rebind `swift_task_create` trong image của app. Không ghi lại child task (cờ `Task_IsChildTask`: `async let`, task group), vì chúng không thể sống lâu hơn task cha.
- Mỗi bản ghi gồm:
  - weak native tới Task;
  - tên operation, ví dụ `closure #1 in ProfileVC.viewDidLoad()`;
  - con trỏ hàm của operation;
  - `UnretainedHeapReference` tới context của operation: weak nếu context là object, unowned nếu là closure context.
- Trong graph, Task là một node `.task` có một cạnh `operation`, đi tiếp vào những gì operation bắt.
- **Lúc mark**, những Task còn chạy mà trỏ tới (strong hay weak) một object của app trong subtree sẽ được thêm vào làm member, dưới dạng `TaskProbe`. Probe sống chừng nào Task còn chạy. Đến T2 màn hình đã chết mà probe còn sống thì báo `kind: outlived`, type `Task`, nguyên nhân "still running" (Z22).

### 3. LeakPatterns: những gì hệ thống giữ

Hook bằng `method_setImplementation`. Mọi thứ được giữ weak, và chỉ ghi lại khi target, delegate, handler hoặc block là của app.

| Hook | Ghi lại | Hết giữ khi |
|---|---|---|
| `+[NSTimer scheduledTimerWith…/timerWith…]` (target và block) | timer → target/block | `isValid == false` |
| `+[CADisplayLink displayLinkWithTarget:selector:]` | link → target | `-invalidate` |
| `-[NSNotificationCenter addObserverForName:object:queue:usingBlock:]` | token → block (bản copy trên heap) | `removeObserver:`, `removeObserver:name:object:` |
| `+[NSURLSession sessionWithConfiguration:delegate:delegateQueue:]` | session → delegate | `delegate == nil` (đã invalidate) |
| `-[WKUserContentController addScriptMessageHandler…]` (3 biến thể) | controller → handler | các hàm `removeScriptMessageHandler…` |

Ngoài ra, `WKWebView` → `configuration.userContentController` được thêm làm cạnh, vì WebKit giữ nó trong storage riêng.

Những gì ghi lại được dùng vào ba việc:

1. **Cạnh trong retain graph.** Nhờ vậy Z08, Z24, Z25 thành cycle certain và được báo ở T1.
2. **Root cho bước tìm "ai đang giữ":** timer còn valid, link chưa invalidate, observer chưa remove, session chưa invalidate.
3. **Cảnh báo lúc màn hình đóng** (mục 5).

### 4. Hai bước tìm ở T1

1. Tìm cycle qua object (như ADR 004). Cycle certain thì báo ngay.
2. Không có cycle certain thì BFS từ mọi root đã biết (Task đang chạy và các thứ hệ thống giữ) tới object. Tìm thấy thì nguyên nhân là `held by <root>`, kèm chuỗi tham chiếu từ root tới object. Root chính là object (token của Z27) thì chuỗi rỗng.

Thứ tự ưu tiên: cycle certain, rồi `held by`, rồi possible cycle / no cycle / limit. Hai bước dùng chung ngân sách theo lát. Số object và thời gian trong RESULTS là tổng của cả hai bước.

### 5. Cảnh báo kinh điển, lúc màn hình đóng

`PatternChecker` chạy trên các member vừa được mark. Nó ghi log ở category `warning`, mỗi cặp pattern và vị trí một lần, và không bao giờ dừng app. Mục đích là báo cả những chỗ **chưa leak**.

| Pattern | Khi nào |
|---|---|
| `strongDelegate` | Field `delegate` hoặc `dataSource` strong (certain) trong object của app |
| `timerTarget` | Timer còn valid có target là member, hoặc block của nó giữ member qua một chuỗi ngắn |
| `displayLinkTarget` | Display link chưa invalidate có target là member |
| `urlSessionDelegate` | Session chưa invalidate có delegate là member |
| `scriptMessageHandler` | Controller còn giữ member làm handler |
| `observerBlock` | Observer chưa remove có block giữ member strongly. `[weak self]` thì không cảnh báo |

Raw value của `LeakPattern` không bao giờ đổi tên (cùng lý do với ADR 003). `LeakChecks.ignoredPatterns` tắt từng pattern.

### 6. Gợi ý sửa theo hình dạng nguyên nhân

`LeakFixes` thêm dòng `fix:` vào report:

| Thấy trong nguyên nhân | Gợi ý |
|---|---|
| Closure của app (bước `{closure…}` hoặc node closure) | `[weak self]` trong đúng closure đó |
| Field có tên kiểu delegate | `weak var` |
| `associated <key>` | `.OBJC_ASSOCIATION_ASSIGN` hoặc weak box |
| Timer, CADisplayLink, URLSession, `__NSObserver`, WKUserContentController | invalidate, remove, hoặc dùng weak proxy, tùy loại |
| `Subscribers.Sink` / `Subscribers.Assign` | `[weak self]` trong `sink`, `assign(to: &$property)` |
| Held by Task / Task still running | Giữ handle, `cancel()` ở `viewDidDisappear`, `continuation.finish()` cho AsyncStream |
| Không có cycle, không biết ai giữ | Tìm static, singleton, cache (Memory Graph) |

### 7. `kind` vẫn giữ nguyên (ADR 003)

Task hay subscription còn sống sau khi màn hình chết đều là `outlived`. Đó đúng là điều tool quan sát được. Phần "chạy tiếp" hay "bị ai giữ" nằm ở nguyên nhân. Hình dạng chuỗi `held by` được đưa vào signature giống như hình dạng cycle.

## Số đo trên LeakZoo

27/27 scenario khớp. Đo trên iPhone 17 Pro simulator, iOS 26.3, cộng cả hai bước tìm.

| Case | Trước (S3–4) | Bây giờ | Object | Tổng | Lát dài nhất |
|---|---|---|---|---|---|
| Z03 UIAction | possible cycle, báo ở T2 | cycle certain, T1 | 233 | 27 ms | 13 ms |
| Z06 Combine | không tìm thấy, partly read | cycle certain, T1, qua `Sink.receiveValue` | 199 | 16 ms | 6,5 ms |
| Z07 Timer | không có cycle | held by Timer | 158 | 4,8 ms | 2,5 ms |
| Z08 observer | không có cycle, partly read | cycle certain qua token, T1 | 146 | 2,7 ms | 2,7 ms |
| Z09 Task | không có cycle | held by Task | 156 | 3,8 ms | 2,2 ms |
| Z22 Task sống tiếp | (không báo) | `Task` outlived, still running | — | — | — |
| Z23 CADisplayLink | (mới) | held by CADisplayLink | 246 | 27 ms | 15 ms |
| Z24 URLSession | (mới) | cycle certain, T1 | 27 | 2,8 ms | 2,8 ms |
| Z25 WKScriptMessageHandler | (mới) | cycle certain, T1 | 142 | 1,8 ms | 1,8 ms |
| Z26 delegate strong, không leak | (mới) | không báo leak, có cảnh báo `strongDelegate` | — | — | — |
| Z27 observer sống tiếp | (mới) | `__NSObserver` outlived, held by observer | 11 | 0,2 ms | 0,2 ms |

## Các phương án đã loại

- **Theo dõi Task qua hook của executor** (`swift_task_enqueueGlobal_hook`): chỉ thấy job khi nó được đưa vào hàng đợi, không thấy operation. Task đang chờ trên stream thì không bao giờ được đưa vào lại.
- **Giữ Task strongly rồi đọc status:** status nằm trong layout private, và giữ Task là giữ luôn những gì nó bắt.
- **Giữ context bằng `weak`:** crash với closure context (spike).
- **Quét `__DATA` của app để tìm biến static (Z10):** cũng là kiểu quét bảo thủ như GC mà ADR 004 đã loại.
- **Swizzle các init của `NSTimer`:** NSTimer là class cluster, init chạy ở subclass. Chỉ hook các class method.

## Hệ quả và giới hạn

- Chỉ thấy Task, timer, observer… được tạo **sau** `install()`. Task do image hệ thống tạo, và child task, cũng không thấy.
- Timer tạo bằng `-initWithFireDate:…` rồi tự add vào run loop sẽ không thấy.
- Biến static, singleton (Z10) vẫn chỉ ra "no cycle". Gợi ý sửa chỉ chỉ hướng tìm.
- Một Task chạy hợp lệ quá 8 giây sau khi màn hình đóng, ví dụ một lần tải dài mà bắt `[weak self]`, sẽ bị báo là sống tiếp. Muốn tắt thì đặt `LeakChecks.tracksTasks = false`.
- Lát dài nhất có lúc tới khoảng 15 ms (Z23) và 13 ms (Z03): một object UIKit lớn, mở ra một lần là không chia nhỏ được. Cần đo thêm khi dogfood.
- Với context của operation, tool giữ unowned count tới khi Task xong. Bộ nhớ của context (không phải những gì nó bắt) được giải phóng muộn hơn một chút, và chỉ ở Debug.
