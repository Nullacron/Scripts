#include <windows.h>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <utility>
#include <cstdint>
#include <cstring>
#include <cstdlib>

#pragma comment(lib, "user32.lib")

extern "C" __declspec(dllexport) void Run() {}

// ============================================================================
// ConVar / ConCommand Memory Layout (Standard Source Engine 32-bit)
// ============================================================================

#pragma pack(push, 4)
struct ConCommandBase_Raw {
    void *vtable;                       // +0x00
    ConCommandBase_Raw *m_pNext;        // +0x04
    bool m_bRegistered;                 // +0x08
    char pad[3];                        // +0x09 alignment
    const char *m_pszName;              // +0x0C
    const char *m_pszHelpString;        // +0x10
    int m_nFlags;                       // +0x14
};

struct ConVar_Raw : public ConCommandBase_Raw {
    void *vtable_iconvar;               // +0x18
    ConVar_Raw *m_pParent;              // +0x1C
    const char *m_pszDefaultValue;      // +0x20
    char *m_pszString;                  // +0x24
    int m_StringLength;                 // +0x28
    float m_fValue;                     // +0x2C
    int m_nValue;                       // +0x30
    bool m_bHasMin;                     // +0x34
    char pad_min[3];
    float m_fMinVal;                    // +0x38
    bool m_bHasMax;                     // +0x3C
    char pad_max[3];
    float m_fMaxVal;                    // +0x40
};
#pragma pack(pop)

// ============================================================================
// Helpers
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

static bool IsValidAsciiString(const char *str, size_t maxLen) {
    if (!str || IsBadStringPtrA(str, 2)) return false;
    for (size_t i = 0; i < maxLen; ++i) {
        char c = str[i];
        if (c == '\0') return i > 0;
        // Basic printable ASCII + tabs/newlines
        if ((c < 32 || c > 126) && c != '\t' && c != '\n' && c != '\r') return false;
    }
    return false;
}

static bool FormatEntry(ConCommandBase_Raw *cmd, std::string &outJson) {
    if (!cmd || IsBadReadPtr(cmd, sizeof(ConCommandBase_Raw))) return false;
    if (!IsValidAsciiString(cmd->m_pszName, 128)) return false;

    const char *name = cmd->m_pszName;
    const char *help = IsValidAsciiString(cmd->m_pszHelpString, 4096) ? cmd->m_pszHelpString : "";
    int flags = cmd->m_nFlags;

    // Check if this is a command or a variable
    // In ConCommandBase, IsCommand() is at vtable index 1
    bool isCommand = false;
    if (cmd->vtable && !IsBadReadPtr(cmd->vtable, sizeof(void*) * 2)) {
        void **vt = reinterpret_cast<void**>(cmd->vtable);
        if (vt[1] && !IsBadCodePtr(reinterpret_cast<FARPROC>(vt[1]))) {
            typedef bool (__thiscall *IsCommandFn)(void*);
            auto fn = reinterpret_cast<IsCommandFn>(vt[1]);
            isCommand = fn(cmd);
        }
    }

    std::ostringstream ss;
    ss << "  {\n";
    ss << "    \"name\": \"" << EscapeJson(name) << "\",\n";
    ss << "    \"isCommand\": " << (isCommand ? "true" : "false") << ",\n";
    ss << "    \"helpStr\": \"" << EscapeJson(help) << "\",\n";
    ss << "    \"flags\": " << flags << ",\n";
    ss << "    \"flagsStr\": \"" << GetFlagsString(flags) << "\"";

    if (!isCommand) {
        auto cvar = reinterpret_cast<ConVar_Raw *>(cmd);
        if (!IsBadReadPtr(cvar, sizeof(ConVar_Raw))) {
            ConVar_Raw *parent = (cvar->m_pParent && !IsBadReadPtr(cvar->m_pParent, sizeof(ConVar_Raw))) ? cvar->m_pParent : cvar;

            const char *defVal = IsValidAsciiString(parent->m_pszDefaultValue, 1024) ? parent->m_pszDefaultValue : "";
            const char *curVal = IsValidAsciiString(parent->m_pszString, 4096) ? parent->m_pszString : "";

            ss << ",\n    \"default\": \"" << EscapeJson(defVal) << "\",\n";
            ss << "    \"value\": \"" << EscapeJson(curVal) << "\"";

            if (parent->m_bHasMin) {
                ss << ",\n    \"min\": " << parent->m_fMinVal;
            }
            if (parent->m_bHasMax) {
                ss << ",\n    \"max\": " << parent->m_fMaxVal;
            }
        }
    }

    ss << "\n  }";
    outJson = ss.str();
    return true;
}

// ============================================================================
// Safe Scan for the Real Linked List Head
// ============================================================================

static ConCommandBase_Raw* FindRealCvarHead() {
    const char *moduleNames[] = { "engine.dll", "vstdlib.dll", "tier1.dll", "server.dll" };

    for (const char *modName : moduleNames) {
        HMODULE hMod = GetModuleHandleA(modName);
        if (!hMod) continue;

        auto dos = reinterpret_cast<IMAGE_DOS_HEADER*>(hMod);
        if (dos->e_magic != IMAGE_DOS_SIGNATURE) continue;
        auto nt = reinterpret_cast<IMAGE_NT_HEADERS*>(reinterpret_cast<uintptr_t>(hMod) + dos->e_lfanew);
        if (nt->Signature != IMAGE_NT_SIGNATURE) continue;

        uintptr_t base = reinterpret_cast<uintptr_t>(hMod);
        uintptr_t size = nt->OptionalHeader.SizeOfImage;

        // Scan memory for an object where m_pszName points directly to "sv_cheats" or "version"
        for (uintptr_t p = base; p < base + size - sizeof(ConVar_Raw); p += 4) {
            auto candidate = reinterpret_cast<ConCommandBase_Raw*>(p);

            if (!IsBadReadPtr(candidate, sizeof(ConCommandBase_Raw))) {
                if (candidate->m_pszName && !IsBadStringPtrA(candidate->m_pszName, 16)) {
                    if (strcmp(candidate->m_pszName, "sv_cheats") == 0 || strcmp(candidate->m_pszName, "version") == 0) {
                        // Found a verified ConCommandBase! Now check its m_pNext pointer validity
                        if (candidate->m_pNext && !IsBadReadPtr(candidate->m_pNext, sizeof(ConCommandBase_Raw))) {
                            if (candidate->m_pNext->m_pszName && !IsBadStringPtrA(candidate->m_pNext->m_pszName, 64)) {
                                return candidate;
                            }
                        }
                    }
                }
            }
        }
    }
    return nullptr;
}

// ============================================================================
// Worker Thread
// ============================================================================

static DWORD WINAPI DumperThread(LPVOID) {
    Sleep(200);

    ConCommandBase_Raw *startCmd = FindRealCvarHead();

    if (!startCmd) {
        MessageBoxA(NULL, "Could not locate verified ConVar chain in memory!", "Error", MB_ICONERROR);
        return 0;
    }

    // Determine desktop path
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

    int count = 0;
    std::vector<std::string> entries;

    // Follow the global singly-linked list
    for (ConCommandBase_Raw *cmd = startCmd; cmd != nullptr; cmd = cmd->m_pNext) {
        if (IsBadReadPtr(cmd, sizeof(ConCommandBase_Raw))) break;

        std::string jsonChunk;
        if (FormatEntry(cmd, jsonChunk)) {
            entries.push_back(jsonChunk);
            ++count;
        }

        // Safety break in case of an invalid loop
        if (count > 8000) break;
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
