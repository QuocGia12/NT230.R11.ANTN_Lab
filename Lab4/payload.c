/* payload de chung minh Process Doppelganging da chay.
 * 3 bang chung doc lap, hong 1 cai van con 2 cai:
 *   1. ghi file C:\pd\proof.txt  -> khong can console, khong can desktop
 *   2. song 120 giay            -> kip mo Process Explorer xem ten tien trinh gia
 *   3. MessageBox               -> chi hien neu process co desktop
 * Build 64-bit: x86_64-w64-mingw32-gcc payload.c -o payload.exe -mwindows -static -O2 -s -luser32
 * Build 32-bit: i686-w64-mingw32-gcc   payload.c -o payload.exe -mwindows -static -O2 -s -luser32
 */
#include <windows.h>

#define PROOF_DIR  "C:\\pd"
#define PROOF_PATH "C:\\pd\\proof.txt"

int WINAPI WinMain(HINSTANCE hi, HINSTANCE hp, LPSTR cmd, int show)
{
    char line[512];
    char exe[MAX_PATH];
    DWORD written = 0;
    HANDLE h;

    (void)hi; (void)hp; (void)cmd; (void)show;

    exe[0] = 0;
    GetModuleFileNameA(NULL, exe, MAX_PATH);

    /* GetModuleFileName doc tu PEB->ImagePathName, chinh la cai PoC da doi thanh target.
       Day la cho de thay ro process dang mang ten file khac. */
    wsprintfA(line,
              "payload running\r\n"
              "pid                = %lu\r\n"
              "GetModuleFileNameA = %s\r\n"
              "GetCommandLineA    = %s\r\n",
              GetCurrentProcessId(), exe, GetCommandLineA());

    CreateDirectoryA(PROOF_DIR, NULL);
    h = CreateFileA(PROOF_PATH, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE)   /* du phong: ghi vao CurrentDirectory */
        h = CreateFileA("proof.txt", GENERIC_WRITE, FILE_SHARE_READ, NULL,
                        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h != INVALID_HANDLE_VALUE) {
        WriteFile(h, line, (DWORD)lstrlenA(line), &written, NULL);
        FlushFileBuffers(h);
        CloseHandle(h);
    }

    MessageBoxA(NULL, line, "PAYLOAD", MB_OK | MB_SETFOREGROUND);
    Sleep(120000);
    return 0;
}
