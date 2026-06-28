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

## Follow-up — 2026-06-28T07:51:01Z

Sửa lỗi mất âm thanh của các ứng dụng phát nhạc (như Spotify) khi thay đổi thiết bị đầu ra mặc định (Default Output Device) bằng cách xử lý sự kiện cấu hình thay đổi của AVAudioEngine.

Working directory: /Users/mac/Documents/GitHub/soundssource
Integrity mode: benchmark

## Requirements

### R1. Xử lý AVAudioEngineConfigurationChange để tự động khôi phục ngầm
Đăng ký lắng nghe thông báo `NSNotification.Name.AVAudioEngineConfigurationChange` cho từng thực thể `AVAudioEngine` được quản lý bởi `OutputDeviceEngine`.
Khi nhận được thông báo thay đổi cấu hình (do thay đổi thiết bị hệ thống, thay đổi xung nhịp sample rate, v.v.):
- Thực hiện dừng engine.
- Tự động dựng lại các kết nối đồ thị âm thanh (reconnect nodes) một cách êm ái cho toàn bộ các ứng dụng đang được định tuyến đến thiết bị đó (recreate AppAudioNode để cập nhật tỷ lệ chuyển đổi định dạng âm thanh phù hợp với thiết bị mới).
- Khởi động lại engine ngầm mà không gây tiếng ồn hay ngắt dòng âm thanh của người dùng.

### R2. Đảm bảo an toàn giải phóng bộ nhớ
Đảm bảo giải phóng observer đúng cách trong hàm hủy `deinit` của `OutputDeviceEngine` để tránh rò rỉ bộ nhớ hoặc gây crash khi ứng dụng đóng.

## Acceptance Criteria

### Tính năng
- [ ] Khi thay đổi thiết bị đầu ra mặc định của hệ thống, các ứng dụng đang được định tuyến riêng biệt (như Spotify được định tuyến đến một thiết bị cụ thể) vẫn tự động kết nối lại ngầm và tiếp tục phát nhạc bình thường mà không bị ngắt hoặc lỗi âm thanh.
- [ ] Các ứng dụng định tuyến theo mặc định (Default) được di trú (migrate) chính xác sang thiết bị mặc định mới và tiếp tục phát nhạc.

### Biên dịch & Kiểm thử
- [ ] Biên dịch dự án thành công không lỗi thông qua lệnh `./scripts/build_app.sh`.
