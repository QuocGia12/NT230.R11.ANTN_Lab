# Lab 3 

## Thông tin nhóm 
| Họ và Tên | MSSV | 
| -------- | -------- | 
| Nguyễn Văn Quốc Gia    | 24520415    |
| Trịnh Quang Minh    | 24521089    |

## Câu 4: Tìm hiểu tổng quan về hệ thống C2 Mythic

### Ý tưởng
Đề cho chọn một trong sáu nền tảng C2, em chọn Mythic vì nó chạy hoàn toàn bằng Docker nên từng thành phần nằm trong một container riêng, nhìn thấy và đếm được. Câu này em không chép tài liệu mà cài thật lên Kali rồi đọc danh sách dịch vụ đang chạy, vì chính danh sách đó trả lời được cả ba ý đề hỏi.

### Đọc toàn bộ dịch vụ Mythic đang chạy

**[Kali]**
```bash
cd ~/Mythic && sudo ./mythic-cli status
```
![Bảng dịch vụ Mythic, gồm nhóm Mythic Main Services và nhóm Installed Services]()
*Hình 1. Danh sách dịch vụ Mythic đang chạy trên máy chủ C2.*
-> `Mythic Main Services` có 8 container, `Installed Services` có thêm `apollo` và `http`

[DELETE HERE]
Thao tác: [KALI] mở terminal, chạy lại lệnh ở trên
Chụp: từ dòng tiêu đề `MYTHIC SERVICE` tới hết bảng `Installed Services`
Mong đợi: cột `STATE` của mọi dòng đều là `running`. Dòng nào `exited` thì đọc `sudo ./mythic-cli logs <tên>`; nhiều container cùng chết thường là do thiếu RAM
[END OF DELETE]

### Kiến trúc tổng thể: lõi không biết agent là gì
Tám container lõi có sẵn từ lúc `mythic-cli start`, còn `apollo` và `http` chỉ xuất hiện sau khi em cài thêm. Em đọc tên image để kiểm chúng có cùng một nguồn hay không:

**[Kali]**
```bash
sudo docker ps --format '{{.Names}}\t{{.Image}}'
```
![Danh sách container kèm tên image đầy đủ của từng cái]()
*Hình 2. Tên image của mười container đang chạy.*
-> tám container lõi mang `ghcr.io/its-a-feature/mythic_*`, còn `apollo` mang `ghcr.io/mythicagents/apollo` và `http` mang `ghcr.io/mythicc2profiles/http`

[DELETE HERE]
Thao tác: [KALI] chạy lại lệnh ở trên trong cùng terminal
Chụp: đủ 10 dòng, thấy rõ phần namespace đứng trước tên image
Mong đợi: đúng 10 dòng. Thiếu `apollo` hoặc `http` thì lệnh cài chưa xong, chạy `mythic-cli status` xem lại
[END OF DELETE]

Ba namespace khác nhau cho thấy agent và C2 profile là dự án rời, không nằm trong mã nguồn Mythic. Thêm một agent mới chỉ là tải thêm một container, lõi không phải sửa gì.

=> đây là client-server có phần mở rộng cắm thêm: lõi giữ dữ liệu và hàng đợi, agent và giao thức là mô-đun

### Các thành phần chính nằm ở container nào
Bảng `mythic-cli status` in kèm địa chỉ của từng dịch vụ nên em gắn thẳng tên mà đề hỏi vào container thật:

- **UI console**: `mythic_nginx` phục vụ giao diện ở `https://127.0.0.1:7443`, nội dung trang do `mythic_react` sinh ra
- **Communication handler**: container `http`, chính là C2 profile quyết định bot nói chuyện bằng giao thức nào
- **Listener**: Mythic không có mục menu riêng tên listener, C2 profile lúc được bật chính là listener
- **Payload và implant**: container `apollo`, nơi giữ trình biên dịch và sinh ra file sẽ chạy trên máy victim
- **Hàng đợi nội bộ**: `mythic_rabbitmq` ở `amqp://127.0.0.1:5672`, đường nói chuyện giữa lõi và các container cắm thêm
- **Lớp API**: `mythic_graphql` ở `127.0.0.1:8080`, giao diện web lấy dữ liệu qua đây

Cột `BOUND LOCALLY` của `Nginx (Mythic Web UI)` là `false`, còn mọi dịch vụ khác đều là `true`.

=> chỉ cổng 7443 ra được khỏi máy Kali, phần lõi và cơ sở dữ liệu đóng lại ở localhost

### Yêu cầu hệ điều hành, ngôn ngữ và cơ sở dữ liệu
Máy chủ C2 của em là Kali chạy trên VMware, và thứ duy nhất phải cài tay là Docker cùng `make`. Không phải cài Go, Node hay PostgreSQL lên máy vì cả ba đã nằm sẵn trong image.

- **Hệ điều hành**: Linux có Docker
- **Cơ sở dữ liệu**: PostgreSQL, container `mythic_postgres`, chuỗi kết nối `postgresql://mythic_user:password@127.0.0.1:5433/mythic_db`
- **Giao diện**: React, container `mythic_react`
- **Lớp API**: Hasura GraphQL, container `mythic_graphql`
- **Hàng đợi**: RabbitMQ, container `mythic_rabbitmq`

Một chỗ lệch so với mặc định: Mythic vốn mở PostgreSQL ở cổng 5432, nhưng máy Kali của em đã có sẵn một PostgreSQL khác giữ cổng đó nên `mythic-cli start` sẽ chết vì cổng bị chiếm. Em đổi sang 5433 bằng `sudo ./mythic-cli config set POSTGRES_PORT 5433`, nên trong ảnh cổng là 5433 chứ không phải 5432.

Lúc cả mười container cùng chạy, `free -m` báo máy dùng 3020 MB trên 7905 MB.

=> yêu cầu thật gọn hơn tài liệu mô tả: một máy Linux có Docker là đủ, mọi ngôn ngữ và cơ sở dữ liệu đi kèm sẵn trong image

## Câu 5 
## Câu 6 
## Câu 7 
## Câu 8 