MENU GỌI MÓN TẠI BÀN — NHÀ TIGER

THƯ MỤC NÀY LÀ GỐC ĐỂ ĐƯA LÊN GITHUB PAGES
Giữ index.html, config.js, food-hero.png, food/, drinks/ và supabase/ ở cùng cấu trúc.

1. TẠO BACKEND SUPABASE
- Tạo project mới trong Supabase Dashboard.
- Nếu đây là project mới: mở supabase/schema.sql; email quản lý kutrungls@gmail.com đã được điền sẵn. Dán vào SQL Editor và chạy.
- Nếu đã chạy schema cũ: mở supabase/customer_tracking_migration.sql, dán toàn bộ vào SQL Editor và bấm Run để bật trạng thái realtime cho khách. Không chạy lại schema cũ để thay migration này.
- Trong Authentication, tắt đăng ký công khai; thêm email quản lý làm user với mật khẩu riêng.
- Bật xác nhận email cho user quản lý nếu Dashboard yêu cầu.
- Project URL và Publishable key đã được điền sẵn trong config.js của gói này.
- Nếu đổi/thu hồi key, cập nhật hai giá trị trong config.js rồi tải file đó lên lại GitHub.
- Không dùng Secret key hoặc service_role key trong trang web.

2. ĐƯA LÊN GITHUB PAGES
- Đưa toàn bộ nội dung thư mục này (bao gồm index.html, config.js, food/, drinks/, food-hero.png và supabase/) vào gốc repository kutrungls.github.io.
- Trong GitHub: Settings > Pages > Build and deployment, chọn Deploy from a branch, nhánh main và thư mục /(root).
- Sau khi GitHub Pages hoàn tất, trang sẽ ở https://kutrungls.github.io/.
- Mã QR từng bàn dùng địa chỉ https://kutrungls.github.io/?table=01, ?table=02, ...

3. NHẬN ĐƠN TẠI QUÁN
- Mở trang, chọn Quản lý đơn, đăng nhập bằng tài khoản quản lý.
- Bấm “Bật chuông lớn” một lần trên thiết bị nhận đơn và cho phép thông báo của trình duyệt.
- Để nghe chuông, giữ trang quản lý đang mở và kết nối mạng. Đơn mới sẽ đồng bộ realtime, hiện trong danh sách và phát chuông.
- Khi bấm “Nhận đơn”, trạng thái trong Supabase chuyển thành processing; điện thoại khách đang theo dõi đơn sẽ hiện “Quán đang làm món cho bạn”.
- Khách có thể mở lại “Đơn của tôi” trên chính điện thoại đã gửi đơn. Giữ trang menu mở và có mạng để nhận cập nhật tức thì.
- Trang quản lý chỉ cho phép tài khoản có email đã ghi trong schema.sql đọc/sửa đơn; khách chỉ gửi đơn mới và tra trạng thái bằng mã riêng của đơn.

4. THANH TOÁN
- Bản này hỗ trợ gửi đơn và thanh toán tại quầy. Chưa kết nối cổng thanh toán online; cần chọn phương thức như VietQR/ngân hàng, MoMo hoặc cổng khác trước khi tích hợp.

Ảnh banner nằm trong food-hero.png; 9 ảnh đồ ăn trong food/; 11 ảnh đồ uống trong drinks/.
Nếu chưa điền Supabase, trang vẫn chạy ở chế độ xem trước và chỉ lưu đơn trên trình duyệt hiện tại.
