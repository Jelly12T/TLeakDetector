# ADR 003: `kind` của leak mô tả điều quan sát được, và không bao giờ đổi tên

- Trạng thái: Đã chấp nhận
- Ngày: 2026-11-10

## Bối cảnh

`kind` là một nửa của signature (tên type + `kind`). Signature được dùng để dedup trong một phiên chạy, và được
ghi thẳng vào `LeakSuppressions.json` của từng app. Nếu đổi tên một `kind` sau khi app đã có file suppression,
mọi entry cũ sẽ bị coi là sai format và bị bỏ qua. Khi đó các leak đã biết lại làm app dừng hoặc crash, tức là
đúng điều mà file suppression sinh ra để tránh.

LeakZoo phân loại leak theo nguyên nhân (`leak_cycle`, `leak_rooted`). Nhưng tool chỉ biết được nguyên nhân khi
đã có graph, dự kiến ở S3–4.

## Quyết định

`kind` mô tả điều tool **quan sát được**, không mô tả nguyên nhân. Từ M1 có đúng ba giá trị:

| `kind` | Tool quan sát được gì |
|---|---|
| `screen` | Màn hình vừa đóng vẫn còn sống ở T2 |
| `outlived` | Màn hình đã chết, nhưng một object nó giữ vẫn còn sống ở T2 |
| `budget` | Số instance cùng sống của một type vượt budget đã khai báo |

- Không đổi tên và không xoá giá trị nào. Chỉ thêm giá trị mới khi tool có thêm một cách quan sát mới.
- Nguyên nhân (cycle hay rooted) và hình dạng cycle ở S3–4 sẽ là các trường riêng của report, không thay cho `kind`.
  Khi các trường này được đưa vào signature, một entry suppression không ghi chúng sẽ khớp với mọi nguyên nhân,
  nên các file suppression đã viết vẫn dùng được.

## Các phương án đã loại

- **Dùng `cycle` / `rooted` làm `kind` ngay từ bây giờ:** tool chưa biết nguyên nhân, nên mọi leak sẽ phải mang
  một nhãn đoán. Tới khi có graph, đoán sai thì vẫn phải đổi nhãn.
- **Đặt tên dài hơn** (`screen-alive`, `over-budget`): rõ hơn một chút, nhưng ngay sau `kind` report đã có một câu
  giải thích, và tên ngắn dễ gõ đúng hơn khi viết file JSON bằng tay.

## Hệ quả

- Comment trên `LeakKind` nhắc rằng raw value không được đổi.
- Việc Z01–Z06 (cycle) và Z07–Z10 (rooted) cùng được báo là `screen` là đúng thiết kế. Đây không phải chỗ lệch
  cần sửa ở S3–4; S3–4 chỉ cần bổ sung nguyên nhân.
