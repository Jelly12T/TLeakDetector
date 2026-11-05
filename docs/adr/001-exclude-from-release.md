# ADR 001: Loại TLeakDetector khỏi bản Release

- Trạng thái: Đã chấp nhận
- Ngày: 2026-11-05

## Bối cảnh

TLeakDetector hook vào UIViewController (swizzle) và giữ trạng thái runtime. Nó chỉ dùng khi phát triển.
Nếu lọt vào bản App Store thì sẽ tốn hiệu năng, có thể crash vì swizzle, và lộ tên nội bộ.
Yêu cầu: tool **không bao giờ** có mặt trong binary Release, và phải kiểm chứng được bằng máy.

## Quyết định

Dùng ba lớp, lớp sau kiểm chứng lớp trước:

1. **Flag biên dịch trong package.** Mọi target có
   `.define("LEAK_DETECTOR_ENABLED", .when(configuration: .debug))`, và toàn bộ source bọc trong
   `#if LEAK_DETECTOR_ENABLED`. Ở release, module vẫn build được (app vẫn link product bình thường)
   nhưng rỗng.
2. **Lời gọi trong app bọc `#if DEBUG`.** Cả `import LeakUIKit` lẫn `TLeakDetector.install()`.
   Ở release, type `TLeakDetector` không tồn tại, nên lời gọi không bọc sẽ là lỗi compile, không âm thầm lọt.
3. **Script `scripts/check-release-symbols.sh`.** Archive app, chạy `nm -a` và `strings -a` trên mọi
   Mach-O trong `.app`, fail nếu thấy tên module (`LeakCore`, `LeakUIKit`), tên product, flag hoặc
   tên type khai báo trong `Sources/`. Tên module bắt được mọi symbol Swift vì mangled name chứa tên module
   (ví dụ `$s8LeakCore…`). Danh sách lấy tự động từ `Sources/`, target hay type mới không cần sửa script.
   Có chế độ `--expect-present` để chạy trên Debug, chứng minh script thật sự bắt được symbol
   (tránh trường hợp pass vì quét nhầm chỗ). Script này chạy trong CI ở S8.

## Các phương án đã loại

- **Chỉ link package ở Debug** (link có điều kiện bằng `OTHER_LDFLAGS` hoặc build phase): mỗi app phải cấu hình
  tay, dễ sai, và SPM không hỗ trợ link product theo configuration một cách chính thức.
- **Chỉ dùng `#if DEBUG` trong package**: được, nhưng `DEBUG` là flag chung, có thể bị app hoặc package khác
  định nghĩa. Flag riêng `LEAK_DETECTOR_ENABLED` rõ nghĩa và tìm kiếm được.
- **Kiểm tra runtime** (`install()` tự tắt ở release): code vẫn nằm trong binary, không đạt yêu cầu.

## Hệ quả

- File source mới phải bọc `#if LEAK_DETECTOR_ENABLED`. Quên bọc thì script sẽ fail ở CI.
- Xcode chọn debug/release cho package **theo tên configuration**. Kiểm tra trên Xcode 26.2:
  `Debug` và `StagingDebug` build như debug. `Staging` build như **release**, dù app đặt `DEBUG` và `-Onone`.
  Hệ quả là configuration nội bộ có tên không chứa "Debug" sẽ không có tool (app báo lỗi compile
  `cannot find 'TLeakDetector'` nếu gọi trong `#if DEBUG`). Ngược lại, một configuration dùng để phát hành
  mà tên có "Debug" sẽ **có tool**. Vì vậy phải chạy script với đúng configuration dùng để phát hành.
- `LeakUIKit` cũng bọc `canImport(UIKit)`, nên `swift build`/`swift test` chạy được trên macOS.
