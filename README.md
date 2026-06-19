# SoundsSource

Mình làm cái app này để chỉnh âm thanh riêng cho từng ứng dụng trên Mac. Kiểu như bạn muốn để nhạc Spotify ra tai nghe, còn tiếng Discord thì ra loa ngoài, mỗi cái một âm lượng, thậm chí kéo EQ riêng — macOS mặc định không cho làm vậy, nên có SoundsSource.

App chạy gọn trên thanh menu bar, bấm vào là ra. Không cần cài driver hay khởi động lại máy gì hết.

> Cần **macOS 14.2 trở lên** nhé. App dùng API tap âm thanh tiến trình của Apple, mà cái này chỉ có từ 14.2.

## Nó làm được gì

- Bắt (capture) tiếng của từng app một — Spotify, Chrome, Cốc Cốc, Discord, game…
- Mỗi app một thanh **âm lượng** và nút **tắt tiếng** riêng.
- **EQ 10 dải** (32 Hz đến 16 kHz), kéo tay trực tiếp trên đồ thị.
- Đẩy mỗi app ra một **thiết bị phát khác nhau**. Nhạc ra tai nghe, họp hành ra loa, tuỳ.
- Lưu lại thành **preset** để lần sau khỏi chỉnh lại từ đầu.
- Danh sách chỉ hiện app đang thật sự phát tiếng, không hiện mấy tiến trình rác của hệ thống.

## Cài đặt

Tải file **SoundsSource.dmg** ở [mục Releases](https://github.com/songoku-03/voice-macos/releases/latest), mở ra rồi kéo app thả vào thư mục **Applications**. Xong, mở từ Launchpad là chạy.

Lần đầu mở có thể bị macOS chặn, báo kiểu "không mở được" hoặc "nhà phát triển chưa xác định". Bình thường thôi, tại app mình ký kiểu ad-hoc chứ chưa mua tài khoản Apple để notarize. Cách qua:

- Chuột phải vào app trong Applications → bấm **Open** → **Open** lần nữa. Làm một lần này thôi, sau mở thẳng được.
- Hoặc mở Terminal gõ lệnh này cho nhanh:
  ```bash
  xattr -dr com.apple.quarantine /Applications/SoundsSource.app
  ```

À, lần đầu chạy macOS sẽ hỏi quyền **ghi âm**. Phải đồng ý thì app mới bắt được tiếng, không cho là coi như đứng hình.

## Dùng thế nào

Bấm icon hình sóng âm trên menu bar, cái bảng điều khiển hiện ra.

1. Trong danh sách là mấy app đang phát tiếng. App nào đang kêu sẽ có chấm xanh.
2. Muốn chỉnh app nào thì bấm **nút nguồn** bên phải dòng đó để bắt đầu bắt tiếng nó.
3. Bấm mũi tên để mở rộng dòng ra, lúc này mới hiện đủ đồ chơi:
   - Thanh kéo **âm lượng** với nút **tắt tiếng**.
   - Ô **Route to** — chọn loa/tai nghe muốn đẩy tiếng app đó ra.
   - Phần **EQ** — bật lên rồi kéo mấy điểm trên đường cong cho hợp tai.
4. Chỉnh xong ưng rồi thì bấm **Save Preset** đặt tên lưu lại. Lần sau chọn lại preset đó ở góc trên bên trái là về y nguyên.

Lưu ý nhỏ: mấy trình duyệt như Chrome, Cốc Cốc hay Discord nó không phát tiếng bằng tiến trình chính, mà bằng tiến trình con (Helper). App mình tự dò ra app cha nên trong danh sách bạn vẫn thấy đúng tên "Google Chrome" kèm icon, cứ bấm vào đó là được.

## Tự build từ mã nguồn

Ai muốn vọc thì clone về rồi chạy script, không cần Xcode mở project gì cho mệt:

```bash
git clone https://github.com/songoku-03/voice-macos.git
cd voice-macos

# Build ra file app, nằm ở build/SoundsSource.app
./scripts/build_app.sh

# Hoặc đóng gói luôn thành file .dmg để chia sẻ
./scripts/build_dmg.sh
```

Build xong gõ `open build/SoundsSource.app` là chạy thử được liền.

Cần sẵn: macOS 14.2+, bộ Swift 6 (cài command line tools của Xcode 16 trở lên là có). App phải chạy ngoài sandbox để tap được tiếng, nên trong entitlements có bật quyền `system-audio-capture`. Ký local kiểu ad-hoc thì không cần tài khoản Apple, chỉ khi nào muốn phát hành cho người khác khỏi báo lỗi mới cần.

## Sơ qua về cấu trúc

Code chia làm mấy tầng cho dễ quản, tầng trên xài tầng dưới:

```
SoundsSource → UI → Engine → Core
```

- **Core** — phần chạm tay vào CoreAudio: liệt kê app đang phát tiếng, tạo tap để hứng âm thanh, với cái ring buffer chứa data.
- **Engine** — dựng đồ thị AVAudioEngine: mỗi thiết bị một engine, mỗi app một node có kèm EQ và âm lượng, lo luôn vụ lưu preset.
- **UI** — mấy màn hình SwiftUI: cái popover, danh sách app, thanh chỉnh, đồ thị EQ.
- **SoundsSource** — điểm khởi động, dựng icon menu bar.

## Giấy phép

Chưa kèm file license. Nếu định cho người khác xài lại code thì thêm vào nhé.
