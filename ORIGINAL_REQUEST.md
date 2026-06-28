# Original User Request

## Initial Request — 2026-06-28T06:03:27Z

Tối ưu hóa hiệu năng, cải thiện độ sạch của mã nguồn (Swift Concurrency/warnings/memory) và bổ sung bộ test tự động toàn diện bao phủ toàn bộ các module cốt lõi trong ứng dụng SoundsSource.

Working directory: /Users/mac/Documents/GitHub/soundssource
Integrity mode: development

## Requirements

### R1. Tối ưu hóa bộ nhớ và hiệu năng
Rà soát mã nguồn để phát hiện và giải phóng các rò rỉ bộ nhớ (memory leaks), đặc biệt chú trọng các tham chiếu vòng (retain cycles) trong closures và các observer của NotificationCenter.
Tối ưu hóa luồng Audio Engine để giảm thiểu độ trễ và tải CPU khi xử lý định dạng âm thanh.
Cải thiện độ an toàn đồng thời bằng cách tuân thủ nghiêm ngặt Swift Concurrency (Swift 6 strict concurrency checks).

### R2. Dọn dẹp mã nguồn & Refactoring
Khắc phục triệt để các cảnh báo từ trình biên dịch (compiler warnings) trong dự án.
Loại bỏ mã nguồn thừa, không sử dụng hoặc các đoạn ghi nhật ký (log) dư thừa gây chậm hệ thống.

### R3. Phát triển bộ test tự động toàn diện
Bổ sung các lớp kiểm thử tự động (Unit Tests) sử dụng framework phù hợp (ưu tiên `Testing` hoặc `XCTest` tương thích) cho các module:
- Logic Audio Engine (`AppAudioNode`, `AudioEngineManager`).
- Logic nghỉ ngơi (`BreakTimerManager`).
- Logic quản lý công việc (`TodoStore`, `TodoScheduler`).

## Acceptance Criteria

### Chất lượng mã nguồn & Biên dịch
- [ ] Ứng dụng biên dịch thành công thông qua lệnh `./scripts/build_app.sh`.
- [ ] Không còn bất kỳ cảnh báo biên dịch (warnings) hoặc lỗi (errors) nào liên quan đến Swift Concurrency hoặc rò rỉ tham chiếu trong các file được thay đổi.

### Mức độ bao phủ kiểm thử
- [ ] Tất cả các ca kiểm thử trong thư mục `Tests/` biên dịch thành công.
- [ ] Bộ test bao phủ đầy đủ các trường hợp biên của logic lập lịch công việc (invariants, auto-blocking, midnight roll-over).

## Follow-up — 2026-06-28T06:44:55Z

Cải thiện trải nghiệm người dùng (UX) cho danh sách công việc To-Do của SoundsSource bằng cách tích hợp trực tiếp bảng cấu hình thời gian dưới ô nhập tên và đơn giản hóa thao tác nhập giờ.

Working directory: /Users/mac/Documents/GitHub/soundssource
Integrity mode: demo

## Requirements

### R1. Chọn giờ trực tiếp khi tạo việc mới
Tích hợp vùng chọn thời gian bắt đầu (Start) và kết thúc (End) ngay phía dưới ô nhập tên công việc. Bảng chọn giờ này sẽ mở rộng mượt mà khi người dùng tương tác với trường nhập liệu, loại bỏ quy trình phức tạp khi phải rê chuột tìm biểu tượng đồng hồ sau khi tạo việc.

### R2. Tối giản hóa thao tác chọn giờ (Quick presets)
Bổ sung các nút bấm chọn nhanh thời lượng (ví dụ: +15 phút, +30 phút, +1 giờ, +2 giờ) bên cạnh bộ DatePicker truyền thống để người dùng có thể thiết lập nhanh thời gian kết thúc dựa trên thời gian bắt đầu chỉ với một lần click.

### R3. Thống nhất phong cách thiết kế
Đảm bảo giao diện mới kế thừa phong cách thiết kế hoạt hình (cartoon/neo-brutalism) của ứng dụng với viền đậm, bóng đổ cứng và hiệu ứng chuyển cảnh mượt mà (SwiftUI animations).

## Acceptance Criteria

### Tính năng
- [ ] Khi nhập việc mới, bảng chọn giờ hiển thị trực tiếp ngay dưới ô nhập liệu và cho phép cấu hình thời gian.
- [ ] Có ít nhất 3 nút chọn nhanh thời lượng (+30 phút, +1 giờ, +2 giờ) để tự động điền thời gian kết thúc tương ứng.
- [ ] Thao tác lưu việc mới áp dụng đúng thời gian biểu đã chọn (nếu có cấu hình).

### Kỹ thuật & Biên dịch
- [ ] Dự án biên dịch thành công không có lỗi thông qua lệnh `./scripts/build_app.sh`.
- [ ] Không phát sinh lỗi liên quan đến quản lý trạng thái UI hoặc vòng lặp cập nhật.
