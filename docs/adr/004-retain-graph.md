# ADR 004: Retain graph ở T1: đọc strong reference an toàn, độ tin cậy, và ngân sách trên main thread

- Trạng thái: Đã chấp nhận
- Ngày: 2026-11-10

## Bối cảnh

Tới M1, tool biết object nào còn sống nhưng không biết vì sao. S3–4 thêm retain graph: từ object bị nghi,
tìm cycle strong reference ngắn nhất đi qua nó. Có ba ràng buộc:

1. **Không được crash.** Graph đọc bộ nhớ của app đang chạy. Đọc nhầm một word rác thành con trỏ là crash.
2. **Không được khẳng định sai.** Nếu tool báo "cycle chắc chắn" mà thật ra là weak reference, dev sẽ đi sửa sai chỗ.
3. **Không được gây hitch.** Search chạy trên main thread (UIKit chỉ an toàn ở đó), ngay lúc người dùng đang
   dùng màn hình tiếp theo.

## Quyết định

### 1. Chỉ coi là strong khi có nguồn biết ownership

| Loại ref | Nguồn | Độ tin cậy |
|---|---|---|
| Stored property Swift | Field metadata, bỏ `weak`/`unowned`/`unowned(unsafe)` theo đuôi `Xw`/`Xo`/`Xu` (ADR 002). Giá trị đọc qua `Mirror` theo **index**, không bao giờ đọc field unowned | certain |
| Struct, property wrapper, collection, enum, tuple | Đệ quy qua `Mirror`, field metadata của struct cho biết field weak bên trong wrapper | certain |
| Capture của closure Swift | Capture descriptor trong metadata của context (`0x400`), type phân giải bằng `_getTypeByMangledNameInContext`. Context chính là object khi closure chỉ bắt một object | certain |
| Ivar ObjC | ARC ivar layout (`class_getIvarLayout`): ivar weak và `__unsafe_unretained` không có trong layout nên không bao giờ bị đọc | certain |
| Capture của block clang | Block extended layout | certain |
| `NSArray`/`NSSet`/`NSDictionary`, `NSHashTable`/`NSMapTable` | Phần tử; bảng nào không có `acquireFunction` (weak) thì bỏ | certain |
| Associated object | Hook `objc_setAssociatedObject` bằng cách ghi lại symbol pointer (giống fishhook), chỉ ở image của app. Hook chỉ ghi **key và policy** lên chính owner, giá trị luôn đọc lại bằng `objc_getAssociatedObject` | certain |
| Subview của `UIView` | API `subviews`: UIKit giữ subview qua cây layer của Core Animation, không ivar nào cho thấy | certain |
| Bộ nhớ không rõ layout (block do Swift tạo, generic capture, module tắt reflection) | Chỉ **so địa chỉ** với object đã có trong graph, cộng nhận diện closure context (xem 2) | uncertain |

### 2. Không bao giờ dereference bộ nhớ không rõ layout

Một word lạ chỉ được dùng theo hai cách:

- So bằng địa chỉ với object đã có trong graph. Cách này không đọc gì cả.
- Nhận làm closure context nếu thỏa hết các điều kiện: là đầu một vùng malloc còn sống (`malloc_size`),
  metadata của nó nằm trong một image đã load, và kind bằng `0x400`.

Object mới **không bao giờ** được nhận từ một word lạ, vì một word rác có thể trông giống object.
Object nào có phần chỉ đọc được bằng cách so địa chỉ thì được đếm là "partly read". Khi đó tool không được kết luận
"không có cycle", chỉ được nói "không tìm thấy, nhưng chưa loại trừ được".

### 3. Độ tin cậy quyết định thời điểm báo

| Kết quả search ở T1 | Báo khi nào | Report ghi |
|---|---|---|
| Cycle mà mọi cạnh đều certain | Ngay khi search xong (khoảng 2s), sau khi kiểm tra lại object còn sống và vẫn tách khỏi màn hình | `retain cycle (certain)` |
| Cycle có cạnh uncertain | T2 (khoảng 8s), như cũ | `possible retain cycle`, cạnh không chắc gắn `?` |
| Không có cycle, đọc đủ | T2 | `no retain cycle through it`: bị giữ từ bên ngoài |
| Không có cycle, có object partly read | T2 | `no retain cycle found … only partly read` |
| Chạm giới hạn | T2 | `search stopped at the <depth/nodes/time> limit` |

Hình dạng cycle (`RetainCycle.description`, không có địa chỉ) được đưa vào signature. Entry suppression có thể ghi
thêm `"cycle"`; nếu không ghi thì entry khớp mọi cycle. Đây chính là phần mà ADR 003 dành sẵn: `kind` giữ nguyên,
nguyên nhân là một trường riêng.

### 4. Ngân sách trên main thread

- BFS **chia lát**: mỗi lượt runloop tối đa khoảng 4 ms, rồi nhường cho UI vẽ frame tiếp.
  Tổng ngân sách 100 ms, 1000 object, độ sâu 16.
- Trong cùng một độ sâu, object cùng module với màn hình bị nghi và closure được duyệt trước.
  Cycle tìm ra vẫn ngắn nhất, chỉ là tìm ra sớm hơn.
- **Warm-up ở background lúc `install()`**: dựng sẵn bảng image, tên và ivar layout của các class UIKit hay gặp,
  và chạy thử một search nhỏ.
- Cache theo class. Tên class ObjC lấy bằng `class_getName`, tên class Swift đọc từ type descriptor.
  Lý do: nhờ runtime Swift đặt tên tốn khoảng 0,6 ms cho mỗi class ở lần đầu, và đó là chi phí lớn nhất của
  một search khi cache còn lạnh.

Số đo trên LeakZoo (iPhone 17 Pro simulator, iOS 26.3, Xcode 26.2, đo từ log verbose của `scripts/zoo-autorun.sh`):

| Case | Object | Tổng | Số lát | Lát dài nhất | Kết quả |
|---|---|---|---|---|---|
| Z01 closure | 11 | 2,1 ms | 1 | 2,1 ms | cycle certain, báo ở T1 |
| Z02 delegate | 9 | 1,8 ms | 1 | 1,8 ms | cycle certain, T1 |
| Z03 UIAction | 233 | 29 ms | 5 | 4–12 ms | possible cycle qua block Swift, T2 |
| Z04 child closure | 8 | 0,3 ms | 1 | 0,3 ms | cycle certain, T1 |
| Z06 Combine | 239 | 19 ms | 4 | 7 ms | không tìm thấy, 7 object partly read |
| Z07 Timer | 143 | 1,9 ms | 1 | 1,9 ms | không có cycle |
| Z08 observer | 236 | 6,1 ms | 2 | 4,0 ms | không tìm thấy, 5 partly read |
| Z10 static | 235 | 6,0 ms | 2 | 4,0 ms | không tìm thấy, 5 partly read |
| Z21 associated | 11 | 3,4 ms | 1 | 3,4 ms | cycle certain, T1 |

Trước khi có warm-up, cache theo class và cách đặt tên mới, lần search đầu tiên có một lát dài 29 ms.

## Các phương án đã loại

- **Search không chia lát với ngân sách 8 ms:** search đầu tiên trong process không bao giờ kịp xong, và các
  leak bị giữ từ root cần vài trăm object mới kết luận được.
- **Prune UIKit để graph nhỏ đi:** mất luôn Z03, vì cycle của nó đi qua `UIButton` → `UIAction`.
  `prunedModules` vẫn có, nhưng mặc định để trống.
- **Nhận object mới từ word lạ (quét bảo thủ như GC):** có thể retain một object đã deinit (do được
  `unowned` giữ bộ nhớ lại) hoặc một vùng rác, tức là crash. Không đáng đánh đổi.
- **Mẹo dispose-helper của FBRetainCycleDetector cho block:** chỉ đúng với block clang. Với block do Swift tạo,
  dispose helper gọi `swift_release` lên object giả, làm hỏng bộ nhớ.

## Hệ quả và giới hạn

> Cập nhật S5–7 ([ADR 005](005-closures-concurrency-patterns.md)): closure generic (Z06) và block do Swift tạo
> (Z03) giờ đã đọc được và là certain. Leak bị giữ từ bên ngoài giờ cũng chỉ ra được ai giữ (Task, timer,
> observer, display link, session).

- Spike ADR 002 nhận diện class Swift bằng bit 0/1 ở offset 32. Cách này **sai** với runtime hiện tại, vì `AnyClass`
  của class ObjC thật ra là metadata `ObjCClassWrapper` (kind `0x305`) và đọc offset 32 của nó là đọc rác.
  Cách đúng: word đầu lớn hơn `0x7FF` thì là metadata class Swift. Fixture ObjC trong `LeakHeapTests` bắt được lỗi này.
- **Closure generic** (capture descriptor có metadata source), như bên trong Combine (Z06): chỉ so được địa chỉ,
  nên cycle qua đó không thấy. Report nói rõ là partly read, không nói sai thành "không có cycle".
- **Object không phải ObjC hay Swift class** (struct C, C++ trong framework): không đọc được, trừ những gì đã được
  khai báo riêng như subview của `UIView`.
- **Associated object** được set trước `install()` hoặc do framework hệ thống set thì không thấy.
- Một bước mở object không chia nhỏ được. Lát dài nhất đo được là khoảng 12 ms (Z03, một control UIKit có
  struct cấu hình Swift lớn). Mục tiêu là 4 ms; cần đo thêm khi dogfood.
- Mới đo trên simulator, chưa đo trên app thật (bước dogfood được hoãn).
