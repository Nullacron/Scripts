#include <windows.h>
#include <fstream>
#include <string>
#include <vector>
#include <utility>
#include <cstdint>
#include <cstring>
#include <cstdlib>

#pragma comment(lib, "user32.lib")

extern "C" __declspec(dllexport) void Run() {}

typedef void* (*CreateInterfaceFn)(const char *pName, int *pReturnCode);

// ============================================================================
// Source Engine Struct Layouts
// ============================================================================

class ConCommandBase {
public:
    void *vtable;
    ConCommandBase *m_pNext;
    bool m_bRegistered;
    const char *m_pszName;
    const char *m_pszHelpString;
    int m_nFlags;
};

class ConVar : public ConCommandBase {
public:
    void *vtable_iconvar;
    ConVar *m_pParent;
    const char *m_pszDefaultValue;
    char *m_pszString;
    int m_StringLength;
    float m_fValue;
    int m_nValue;
    bool m_bHasMin;
    float m_fMinVal;
    bool m_bHasMax;
    float m_fMaxVal;
};

// ============================================================================
// Formatting
// ============================================================================

static std::string EscapeJson(const char *str) {
    if (!str) return "";
    std::string out;
    for (; *str; ++str) {
        switch (*str) {
            case '\"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(*str) < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned char>(*str));
                    out += buf;
                } else {
                    out += *str;
                }
                break;
        }
    }
    return out;
}

static std::string GetFlagsString(int flags) {
    if (flags == 0) return "none";
    static const std::pair<int, const char *> flagDefs[] = {
        { (1 << 0),  "unregistered" },
        { (1 << 1),  "developmentonly" },
        { (1 << 2),  "game" },
        { (1 << 3),  "client" },
        { (1 << 4),  "hidden" },
        { (1 << 5),  "protected" },
        { (1 << 6),  "sponly" },
        { (1 << 7),  "archive" },
        { (1 << 8),  "notify" },
        { (1 << 9),  "userinfo" },
        { (1 << 10), "printableonly" },
        { (1 << 11), "unlogged" },
        { (1 << 12), "never_as_string" },
        { (1 << 13), "replicated" },
        { (1 << 14), "cheat" },
        { (1 << 15), "ss" },
        { (1 << 16), "demo" },
        { (1 << 17), "dontrecord" },
        { (1 << 18), "ss_added" },
        { (1 << 19), "release" },
        { (1 << 20), "reload_materials" },
        { (1 << 21), "reload_textures" },
        { (1 << 22), "not_connected" },
        { (1 << 23), "material_system_thread" },
        { (1 << 24), "archive_gameconsole" },
        { (1 << 25), "accessible_from_threads" },
        { (1 << 28), "server_can_execute" },
        { (1 << 29), "server_cannot_query" },
        { (1 << 30), "clientcmd_can_execute" }
    };

    std::string result;
    for (const auto &entry : flagDefs) {
        if (flags & entry.first) {
            if (!result.empty()) result += " ";
            result += entry.second;
        }
    }
    return result.empty() ? "unknown" : result;
}

// Call IsCommand via its standard vtable offset (virtual index 1)
static bool CallIsCommand(ConCommandBase *cmd) {
    __try {
        void **vtable = *(void***)cmd;
        typedef bool (__thiscall *IsCommandFn)(void*);
        IsCommandFn fn = (IsCommandFn)vtable[1];
        return fn(cmd);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

static bool TryExtractData(ConCommandBase *cmd, std::string &outJson) {
    __try {
        if (!cmd || !cmd->m_pszName || IsBadStringPtrA(cmd->m_pszName, 256)) return false;

        const char *name = cmd->m_pszName;
        const char *help = (cmd->m_pszHelpString && !IsBadStringPtrA(cmd->m_pszHelpString, 4096)) ? cmd->m_pszHelpString : "";
        int flags = cmd->m_nFlags;
        bool isCommand = CallIsCommand(cmd);

        std::string entry = "  {\n";
        entry += "    \"name\": \"" + EscapeJson(name) + "\",\n";
        entry += "    \"isCommand\": " + std::string(isCommand ? "true" : "false") + ",\n";
        entry += "    \"helpStr\": \"" + EscapeJson(help) + "\",\n";
        entry += "    \"flags\": " + std::to_string(flags) + ",\n";
        entry += "    \"flagsStr\": \"" + GetFlagsString(flags) + "\"";

        if (!isCommand) {
            auto cvar = reinterpret_cast<ConVar *>(cmd);
            ConVar *parent = (cvar->m_pParent) ? cvar->m_pParent : cvar;

            const char *defVal = (parent->m_pszDefaultValue && !IsBadStringPtrA(parent->m_pszDefaultValue, 1024)) ? parent->m_pszDefaultValue : "";
            const char *curVal = (parent->m_pszString && !IsBadStringPtrA(parent->m_pszString, 4096)) ? parent->m_pszString : "";

            entry += ",\n    \"default\": \"" + EscapeJson(defVal) + "\",\n";
            entry += "    \"value\": \"" + EscapeJson(curVal) + "\"";

            if (parent->m_bHasMin) {
                entry += ",\n    \"min\": " + std::to_string(parent->m_fMinVal);
            }
            if (parent->m_bHasMax) {
                entry += ",\n    \"max\": " + std::to_string(parent->m_fMaxVal);
            }
        }

        entry += "\n  }";
        outJson = entry;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

// ============================================================================
// Worker Thread
// ============================================================================

static DWORD WINAPI DumperThread(LPVOID) {
    HMODULE hVstdlib = GetModuleHandleA("vstdlib.dll");
    if (!hVstdlib) hVstdlib = LoadLibraryA("vstdlib.dll");
    if (!hVstdlib) return 0;

    auto vFactory = reinterpret_cast<CreateInterfaceFn>(GetProcAddress(hVstdlib, "CreateInterface"));
    if (!vFactory) return 0;

    void *pCVar = vFactory("VEngineCvar007", nullptr);
    if (!pCVar) pCVar = vFactory("VEngineCvar004", nullptr);
    if (!pCVar) pCVar = vFactory("VEngineCvar003", nullptr);
    if (!pCVar) return 0;

    // In CCvar, m_pConCommandList is stored as a pointer field.
    // Instead of guessing vtables, let's grab a known cvar: "sv_cheats"
    // FindVar is located in the first few virtual functions across all engines.
    ConCommandBase *startCmd = nullptr;

    // Scan the ICvar object memory for pointers that lead into a linked list
    uintptr_t *cvarFields = reinterpret_cast<uintptr_t *>(pCVar);
    for (int i = 0; i < 64; ++i) {
        ConCommandBase *candidate = reinterpret_cast<ConCommandBase *>(cvarFields[i]);
        if (candidate && !IsBadReadPtr(candidate, sizeof(ConCommandBase))) {
            if (candidate->m_pszName && !IsBadStringPtrA(candidate->m_pszName, 64)) {
                if (candidate->m_pNext && !IsBadReadPtr(candidate->m_pNext, sizeof(ConCommandBase))) {
                    startCmd = candidate;
                    break;
                }
            }
        }
    }

    // Fallback: If not found in members, search vstdlib's data segment for the head pointer
    if (!startCmd) {
        MODULEINFO modInfo = {0};
        HMODULE hTier1 = GetModuleHandleA("tier1.dll");
        HMODULE searchMod = hTier1 ? hTier1 : hVstdlib;

        IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER*)searchMod;
        IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS*)((uintptr_t)searchMod + dos->e_lfanew);
        uintptr_t base = (uintptr_t)searchMod;
        uintptr_t size = nt->OptionalHeader.SizeOfImage;

        for (uintptr_t p = base; p < base + size - sizeof(uintptr_t); p += 4) {
            ConCommandBase *candidate = *(ConCommandBase**)p;
            if (candidate && !IsBadReadPtr(candidate, sizeof(ConCommandBase))) {
                if (candidate->m_pszName && !IsBadStringPtrA(candidate->m_pszName, 64)) {
                    if (candidate->m_pNext && !IsBadReadPtr(candidate->m_pNext, sizeof(ConCommandBase))) {
                        // Found a valid node in the list
                        startCmd = candidate;
                        break;
                    }
                }
            }
        }
    }

    if (!startCmd) {
        MessageBoxA(NULL, "Failed to resolve CVar linked list in memory!", "Error", MB_ICONERROR);
        return 0;
    }

    // Determine path on Desktop
    std::string dumpPath;
    const char *userProfile = getenv("USERPROFILE");
    if (userProfile && strlen(userProfile) > 0) {
        dumpPath = std::string(userProfile) + "\\Desktop\\cvars_dump.json";
    } else {
        dumpPath = "cvars_dump.json";
    }

    std::ofstream outFile(dumpPath, std::ios::out | std::ios::trunc);
    if (!outFile.is_open()) return 0;

    outFile << "[\n";

    // Follow the global singly-linked list
    int count = 0;
    std::vector<std::string> entries;

    for (ConCommandBase *cmd = startCmd; cmd != nullptr; cmd = cmd->m_pNext) {
        if (IsBadReadPtr(cmd, sizeof(ConCommandBase))) break;

        std::string jsonChunk;
        if (TryExtractData(cmd, jsonChunk)) {
            entries.push_back(jsonChunk);
            ++count;
        }
    }

    for (size_t i = 0; i < entries.size(); ++i) {
        if (i > 0) outFile << ",\n";
        outFile << entries[i];
    }

    outFile << "\n]\n";
    outFile.flush();
    outFile.close();

    std::string msg = "SUCCESS!\nDumped " + std::to_string(count) + " cvars (with full values, defaults & min/max) to:\n\n" + dumpPath;
    MessageBoxA(NULL, msg.c_str(), "CVar Dumper", MB_ICONINFORMATION);

    return 0;
}

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID) {
    if (fdwReason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hinstDLL);
        CreateThread(NULL, 0, DumperThread, NULL, 0, NULL);
    }
    return TRUE;
}
