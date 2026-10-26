# Lab 3 

## Thông tin nhóm 
| Họ và Tên | MSSV | 
| -------- | -------- | 
| Nguyễn Văn Quốc Gia    | 24520415    |
| Trịnh Quang Minh    | 24521089    |


## Câu 4

## Câu 5 
## Câu 6: Khám phá các tính năng nâng cao của nền tảng C2 
### a. Tạo và tiêm shellcode 
Mythic có option cho phép tạo payload dạng file `.bin` shell code thay vì file `exe` hoàn chỉnh
![alt text](image.png)

Từ đó em tạo thành công file `apollo.bin` chứa shell code kết nối đến C2 
![alt text](image-1.png)

Sau đó để test shell code này thì em sử dụng một repo shell code loader(https://github.com/knownsec/shellcodeloader)

Repo này cho phép chọn file shellcode và tạo file loader tương ứng 
![alt text](image-2.png)

Từ đó em có được file `loader.exe` và khi run file đó thì nhận thấy có kết nối thành công từ target đến c2 
### b. Sử dụng kỹ thuật obfuscation và mã hóa payload để tránh bị phát hiện.
Đây là tính năng mặc định của Mythic C2 

→ endpoint của C2 sẽ không ở dạng plaintext trong file binary 

Rõ hơn, ta thử tìm string `192.168.245.100`(IP của c2) trong payload 
![alt text](image-3.png)

Kết quả ta không thấy string endpoint của C2 trong payload, thể hiện rằng nó đã được mã hóa trong payload 

Đồng thời em cũng thử bắt traffic giao tiếp giữa victim và c2: 
![alt text](image-4.png)

Kết quả: ta thấy được là nội dung không được gửi đi dưới dạng plaintext mà là mã hóa

### c. Kỹ thuật domain fronting để vượt qua kiểm duyệt mạng và ngụy trang traffic.
#### Domain fronting 
Vì không có CDN thật nên em dựng mô phỏng một CDN giả bằng nginx lắng nghe ở port 8888, route traffic đến c2 server thật như sau: 
- Tạo config nginx route traffic từ port 8888(CDN) đến port 80(c2 server thật)
![alt text](image-8.png)
- Tạo payload kết nối đến CDN 
![alt text](image-9.png)

Kết quả: victim kết nối thành công đến c2 server như bình thường dù detector nhận thấy nó kết nối đến CDN hợp lệ 
![alt text](image-10.png)
#### Ngụy trang traffic
Em dùng wireshark để bắt traffic giao tiếp giữa victim và c2 thì thấy được giao thức sử dụng là http 
![alt text](image-5.png) 
- C2 server gửi nội dung lệnh muốn thực hiện dưới dạng một http response 
- Victim trả kết quả của lệnh dưới dạng một http request `POST /data`

![alt text](image-6.png)

Từ đó thì admin hay detector có thể xem đây là một traffic http bình thường mà không nghi ngờ 

Đồng thời khi tạo payload thì Mythic cũng hỗ trợ thay đổi giá trị `post_uri`(mặc định là `data`), đây là route mà victim sẽ gửi nội dung đến, từ đó ta có thể chọn `post_uri` mong muốn để có thể ngụy trang traffic 

Ví dụ em thay đổi `post_uri` thành `api/v1/analytics/collect` thì victim sẽ gửi nội dung đến `api/v1/analytics/collect` thay vì `data`, giống một route api bình thường hơn 
![alt text](image-7.png)

### d. Theo dõi cách mã hóa giao tiếp, cơ chế xác thực giữa client – server.
#### Mã hóa giao tiếp 


#### Cơ chế xác thực 
Quan sát traffic giao tiếp giữa victim và C2 
![alt text](image-11.png)

Ta thấy được các ký tự đầu payload của victim và c2 giống nhau, đây là UUID định danh callback session, Mythic dùng nó để biết callback nào đang gọi về và đồng thời là cơ chế xác thực của Mythic(server chỉ trả lời nếu UUID hợp lệ trong database)
![alt text](image-12.png) 


## Câu 7 
## Câu 8 
## Note 
GeBofFXPrKLePXLRmbBXUG2wWL59js