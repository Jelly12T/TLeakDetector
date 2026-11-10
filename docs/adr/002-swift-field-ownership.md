# ADR 002: Đọc ownership (strong/weak/unowned) của field Swift từ reflection metadata

- Trạng thái: **Đã chấp nhận. GO**
- Cập nhật 2026-11-10: cách nhận diện class Swift bằng bit 0/1 ở offset 32 là sai với runtime hiện tại, xem
  [ADR 004](004-retain-graph.md). Phần đọc field ownership vẫn đúng và đang được dùng trong `LeakHeap`.
- Ngày: 2026-11-05
- Spike: [`Spikes/FieldOwnership/`](../../Spikes/FieldOwnership/). Code tham khảo, **không dùng làm code production**.

## Câu hỏi

Graph v1 cần biết một stored property là strong hay weak/unowned, để không vẽ cạnh "giữ" cho tham chiếu weak.
Mirror không cho biết điều này, vì label của Mirror giống nhau với mọi loại ownership.
Câu hỏi của spike: có đọc được ownership từ metadata Swift **một cách ổn định** không.

## Cách đo

Đường đi: `metadata → type context descriptor → field descriptor → field record → mangled type name`.

| Bước | Vị trí (64-bit, có ObjC interop) | Nguồn |
|---|---|---|
| Class metadata → descriptor | offset 64 (`Description`). Superclass ở offset 8. Bit 0/1 của rodata (offset 32) cho biết đó là class Swift | `include/swift/ABI/Metadata.h` |
| Struct/enum metadata → descriptor | offset 8 | `Metadata.h` |
| Descriptor → `FieldDescriptor` | relative pointer ở offset 16 (`Flags, Parent, Name, AccessFunction, Fields`) | `Metadata.h` |
| `FieldDescriptor` | `MangledTypeName, Superclass, Kind(2), FieldRecordSize(2), NumFields(4)`, rồi đến các record | `include/swift/RemoteInspection/Records.h` |
| `FieldRecord` (12 byte) | `Flags(4), MangledTypeName(rel 4), FieldName(rel 4)` | `Records.h` |
| Ownership | đuôi mangled name: `Xw` weak, `Xo` unowned, `Xu` unowned(unsafe) | `docs/ABI/Mangling.rst` |

Spike dùng hai cách đọc rồi so chéo kết quả:

- **A.** Tự đọc theo layout trên ([FieldOwnershipReader.swift](../../Spikes/FieldOwnership/Sources/FieldOwnershipReader/FieldOwnershipReader.swift)).
- **B.** Hỏi runtime qua `swift_reflectionMirror_recursiveChildMetadata` ([RuntimeFieldReader.swift](../../Spikes/FieldOwnership/Sources/FieldOwnershipReader/RuntimeFieldReader.swift)). Đây là entry point mà `_forEachField` của stdlib dùng. Nó trả về `isStrong` và kiểu của field.

Có 9 type mẫu và 43 field ([Samples.swift](../../Spikes/FieldOwnership/Sources/SpikeSamples/Samples.swift)). Test in ra một dòng `SPIKE|…` cho mỗi phát hiện. [`scripts/run.sh`](../../Spikes/FieldOwnership/scripts/run.sh) gom các dòng đó vào [`results/`](../../Spikes/FieldOwnership/results/). Build Debug.

## Kết quả

| # | Câu hỏi | Trả lời | Bằng chứng |
|---|---|---|---|
| Q1 | Từ một instance có tới được `FieldDescriptor` không: class Swift thuần, subclass NSObject/UIViewController, struct, generic class, generic struct? | **Có, 9/9 type.** Với class phải tự đi lên chuỗi superclass, vì mỗi descriptor chỉ chứa field của chính class đó. Dừng khi gặp class ObjC (`NSObject`, `UIViewController`, `_SwiftObject`). Generic không có gì đặc biệt: descriptor dùng chung, mangled name chứa tham số generic (`x`, `q_`). Generic subclass của generic base cũng đọc được. | `results/sim-all.txt`, các dòng `TYPE` |
| Q2 | Mangled name của field weak/unowned có kết thúc bằng `Xw`/`Xo`/`Xu` không, kể cả khi có symbolic reference? | **Có, 43/43**, và khớp `isStrong` của runtime (cách B) ở mọi field. Đã gặp: `{direct}SgXw`, `{indirect}SgXw` (class ở module khác), `So8NSObjectCSgXw` (ObjC), `{direct}_pSgXw` (protocol Swift), `12SpikeSamples12ObjCDelegate_pSgXw` (protocol `@objc`), `yXlSgXw` (AnyObject), `xSgXw`/`xXo` (generic), `{direct}Xu`. **Bắt buộc** phải parse symbolic reference: byte 0x01–0x17 kéo theo 4 byte offset, 0x18–0x1F kéo theo 8 byte. Đọc như C string thường sẽ sai, vì 4 byte offset có thể chứa byte 0. | `results/sim-all.txt`, các dòng `FIELD` |
| Q3 | Tên field trong descriptor có khớp label của Mirror không, kể cả lazy var và property wrapper? | **Có, 43/43.** Lazy var có tên `$__lazy_storage_$_x`, wrapper có tên `_x`, cả hai đều trùng Mirror. **Cạm bẫy:** property wrapper che ownership. `@WeakRef var x` có field ngoài là `_x: WeakRef<T>` (strong), còn `weak` nằm ở field `value` bên trong wrapper. Muốn thấy thì phải đệ quy vào field kiểu value type, và cần metadata của kiểu field (cách B trả về sẵn). | `results/sim-all.txt`, các dòng `FIELD` và `NESTED` |
| Q4 | Kết quả có giống nhau trên simulator và device thật không? | **Có, giống hệt nhau.** iPhone 12 Pro (iOS 26.6, arm64) cho 60/60 dòng `TYPE`/`FIELD`/`NESTED`/`OBJC` giống simulator iOS 26.3 (diff rỗng), ở cả mức `all` lẫn `none`. Simulator cũng giống nhau giữa Xcode 26.2 + iOS 26.3 và Xcode 27.1 + iOS 27.1. Trên device, package test không chạy trực tiếp được (Xcode báo "Tool-hosted testing is unavailable"), nên report được chạy qua app [`SpikeHost`](../../Spikes/FieldOwnership/HostApp/) bằng `scripts/run-device.sh`. | `results/device-all.txt`, `results/device-none.txt`, `results/sim-all.txt`, `results/sim27-all.txt` |
| Q5 | Tool mù tới mức nào khi project đổi build setting reflection metadata? | Xem bảng dưới. | `results/sim-*.txt` |

### Q5: theo từng mức reflection metadata

| Mức (build setting) | Field descriptor | Ownership (A, B) | Tên field | Mirror | ObjC `class_copyIvarList` |
|---|---|---|---|---|---|
| All (mặc định) | có | ✅ 43/43 | ✅ | ✅ đủ label | tên và offset, **không có ownership** |
| `SWIFT_REFLECTION_METADATA_LEVEL=without-names` | có | ✅ 43/43 | ❌ rỗng | ❌ label `nil` | tên và offset (vẫn còn) |
| `-Xfrontend -reflection-metadata-for-debugger-only` | **null** | ❌ | ❌ | ❌ 0 children | tên và offset (vẫn còn) |
| `SWIFT_REFLECTION_METADATA_LEVEL=none` | **null** | ❌ | ❌ | ❌ 0 children | tên và offset (vẫn còn) |

`class_getWeakIvarLayout` luôn trả về `nil` với class Swift ở mọi mức. Vì vậy ObjC runtime **không bao giờ** cho biết field Swift nào là weak. Nó chỉ cho tên và offset, và chỉ áp dụng cho class, không áp dụng cho struct.

Build setting này tính **theo từng module**. App có thể tắt reflection cho module của mình trong khi pod hay package khác vẫn bật. Khi gặp `Fields` null, tool biết chắc module đó đã tắt reflection.

## Quyết định M0

**GO.** Cả 5 câu đều có câu trả lời dựa trên lần chạy thật, và Q1–Q4 đều đạt. Graph v1 đi tiếp theo plan và dùng reflection metadata làm nguồn ownership chính cho field Swift.

1. **Nguồn chính là cách A** (tự đọc theo layout). Layout metadata, descriptor và field record thuộc phạm vi ABI stability của Swift 5 trên nền tảng Apple, vì runtime của OS phải đọc được binary build từ compiler cũ. Cách B gọi hàm nội bộ của runtime, không được hứa ổn định, nên chỉ dùng để so chéo trong test và để lấy metadata kiểu field khi cần đệ quy. Nếu muốn bỏ hẳn B thì thay bằng `swift_getTypeByMangledNameInContext`.
2. Đệ quy vào field kiểu struct (tối đa vài tầng) để bắt weak nằm trong property wrapper hoặc trong struct lồng nhau.
3. Phát hiện module tắt reflection (`Fields` null), đưa vào report: "module X tắt reflection metadata, field Swift của X được gắn nhãn uncertain".

### Fallback theo từng mức

| Tình huống | Graph v1 làm gì |
|---|---|
| `without-names` | Vẫn biết ownership theo thứ tự field. Lấy tên từ `class_copyIvarList` (với class), hoặc ghi `field#n` (với struct). |
| `debugger-only` / `none` | Dùng ObjC runtime (tên + offset) và Mirror (lúc này cũng mù). Mọi field Swift có kiểu class đều gắn nhãn **uncertain**, không coi là strong. Đúng như hướng fallback của plan. |
| Một bản iOS/Swift sau này đổi layout (test so chéo A và B fail) | Toàn bộ graph v1 chuyển sang fallback ở trên (ObjC runtime + Mirror + uncertain), cho tới khi cập nhật reader. |

## Rủi ro còn mở

- **Mới thử 1 device** (iPhone 12 Pro, iOS 26.6) và 2 toolchain. Nên đưa test so chéo A/B vào CI để phát hiện sớm khi layout thay đổi.
- **arm64e / pointer authentication.** App bên thứ ba build arm64 nên con trỏ `Description` của type trong app không bị ký. Nhưng type Swift của framework hệ thống (SwiftUI…) là arm64e, con trỏ có thể bị ký, và phải strip trước khi đọc. Spike chưa thử type hệ thống.
- **Enum có associated value** và **class được ObjC tạo động** (KVO, `NSKVONotifying_…`) chưa nằm trong phạm vi spike.
- Spike chỉ build Debug. Optimization không ảnh hưởng tới reflection metadata, nhưng chưa đo trên Release.
