#include <windows.h>
#include <fstream>
#include <string>
#include <vector>
#include <utility>
#include <cstdint>
#include <cstring>
#include <cstdlib>

#pragma comment(lib, "user32.lib")

// Export so Cheat Engine will never jump to address 0 if OK is pressed
extern "C" __declspec(dllexport) void Run() {}

typedef void* (*CreateInterfaceFn)(const char *pName, int *pReturnCode);

// ============================================================================
// Source Engine Structures
// ============================================================================

class ConCommandBase {
public:
    virtual ~ConCommandBase() {}
    virtual bool IsCommand() const = 0;
    virtual bool IsFlagSet(int flag) const = 0;
    virtual void AddFlags(int flags) = 0;
    virtual const char *GetName() const = 0;
    virtual const char *GetHelpText() const = 0;
    virtual bool IsRegistered() const = 0;
    virtual int GetDLLIdentifier() const = 0;
    virtual void CreateBase(const char *pName, const char *pHelpString = 0, int flags = 0) = 0;

    ConCommandBase *m_pNext;
    bool m_bRegistered;
    const char *m_pszName;
    const char *m_pszHelpString;
    int m_nFlags;
};

class IConVar {
public:
    virtual void SetValue(const char *pValue) = 0;
    virtual void SetValue(float flValue) = 0;
    virtual void SetValue(int nValue) = 0;
    virtual const char *GetName() const = 0;
    virtual bool IsFlagSet(int nFlag) const = 0;
};

class ConVar : public ConCommandBase, public IConVar {
public:
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

class IAppSystem {
public:
    virtual bool Connect(CreateInterfaceFn factory) = 0;
    virtual void Disconnect() = 0;
    virtual void *QueryInterface(const char *pInterfaceName) = 0;
    virtual int Init() = 0;
    virtual void Shutdown() = 0;
    virtual const void* GetDependencies() = 0;
    virtual int GetTier() = 0;
    virtual void Reconnect(CreateInterfaceFn factory, const char *pInterfaceName) = 0;
    virtual bool IsSingleton() = 0;
};

class ICvar004 : public IAppSystem {
public:
    virtual void RegisterConCommandBase(ConCommandBase *variable) = 0;
    virtual const char *GetCommandLineValue(const char *pVariableName) = 0;
    virtual ConVar *FindVar(const char *var_name) = 0;
    virtual const ConVar *FindVar(const char *var_name) const = 0;
    virtual ConCommandBase *GetCommands() = 0;
};

class ICvarIteratorInternal {
public:
    virtual void SetFirst() = 0;
    virtual void Next() = 0;
    virtual bool IsValid() = 0;
    virtual ConCommandBase *Get() = 0;
};

class ICvar007 : public IAppSystem {
public:
    virtual int AllocateDLLIdentifier() = 0;
    virtual void RegisterConCommand(ConCommandBase *pCommandBase) = 0;
    virtual void UnregisterConCommand(ConCommandBase *pCommandBase) = 0;
    virtual void UnregisterConCommands(int id) = 0;
    virtual const char *GetCommandLineValue(const char *pVariableName) = 0;
    virtual ConCommandBase *FindCommandBase(const char *name) = 0;
    virtual const ConCommandBase *FindCommandBase(const char *name) const = 0;
    virtual ConVar *FindVar(const char *var_name) = 0;
    virtual const ConVar *FindVar(const char *var_name) const = 0;
    virtual void *FindCommand(const char *name) = 0;
    virtual const void *FindCommand(const char *name) const = 0;
    virtual void InstallGlobalChangeCallback(void *callback) = 0;
    virtual void RemoveGlobalChangeCallback(void *callback) = 0;
    virtual void CallGlobalChangeCallbacks(ConVar *var, const char *pOldString, float flOldValue) = 0;
    virtual void InstallConsoleDisplayFunc(void *pDisplayFunc) = 0;
    virtual void RemoveConsoleDisplayFunc(void *pDisplayFunc) = 0;
    virtual void ConsoleColorPrintf(const void *clr, const char *pFormat, ...) const = 0;
    virtual void ConsolePrintf(const char *pFormat, ...) const = 0;
    virtual void ConsoleDPrintf(const char *pFormat, ...) const = 0;
    virtual void RevertFlaggedConVars(int nFlag) = 0;
    virtual void InstallCVarQuery(void *pQuery) = 0;
    virtual bool IsMaterialThreadSetAllowed() const = 0;
    virtual void QueueMaterialThreadSetValue(ConVar *pConVar, const char *pValue) = 0;
    virtual void QueueMaterialThreadSetValue(ConVar *pConVar, int nValue) = 0;
    virtual void QueueMaterialThreadSetValue(ConVar *pConVar, float flValue) = 0;
    virtual bool HasQueuedMaterialThreadConVarSets() const = 0;
    virtual int ProcessQueuedMaterialThreadConVarSets() = 0;
    virtual ICvarIteratorInternal *FactoryInternalIterator() = 0;
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

static void FormatAndWriteCvar(std::ofstream &file, ConCommandBase *cmd) {
    const char *rawName = cmd->m_pszName ? cmd->m_pszName : "";
    const char *rawHelp = cmd->m_pszHelpString ? cmd->m_pszHelpString : "";
    bool isCommand = cmd->IsCommand();
    int flags = cmd->m_nFlags;

    file << "  {\n";
    file << "    \"name\": \"" << EscapeJson(rawName) << "\",\n";
    file << "    \"isCommand\": " << (isCommand ? "true" : "false") << ",\n";
    file << "    \"helpStr\": \"" << EscapeJson(rawHelp) << "\",\n";
    file << "    \"flags\": " << flags << ",\n";
    file << "    \"flagsStr\": \"" << GetFlagsString(flags) << "\"";

    if (!isCommand) {
        auto cvar = reinterpret_cast<ConVar *>(cmd);
        ConVar *parent = (cvar && cvar->m_pParent) ? cvar->m_pParent : cvar;

        const char *defVal = parent->m_pszDefaultValue ? parent->m_pszDefaultValue : "";
        const char *curVal = parent->m_pszString ? parent->m_pszString : "";

        file << ",\n";
        file << "    \"default\": \"" << EscapeJson(defVal) << "\",\n";
        file << "    \"value\": \"" << EscapeJson(curVal) << "\"";

        if (parent->m_bHasMin) {
            file << ",\n    \"min\": " << parent->m_fMinVal;
        }
        if (parent->m_bHasMax) {
            file << ",\n    \"max\": " << parent->m_fMaxVal;
        }
    }

    file << "\n  }";
}

// ============================================================================
// Worker Thread
// ============================================================================

static DWORD WINAPI DumperThread(LPVOID) {
    HMODULE hVstdlib = GetModuleHandleA("vstdlib.dll");
    if (!hVstdlib) hVstdlib = LoadLibraryA("vstdlib.dll");
    if (!hVstdlib) return 0;

    auto vstdlibFactory = reinterpret_cast<CreateInterfaceFn>(GetProcAddress(hVstdlib, "CreateInterface"));
    if (!vstdlibFactory) return 0;

    void *cvarInterface = vstdlibFactory("VEngineCvar007", nullptr);
    bool is007 = (cvarInterface != nullptr);

    if (!cvarInterface) {
        cvarInterface = vstdlibFactory("VEngineCvar004", nullptr);
    }
    if (!cvarInterface) {
        cvarInterface = vstdlibFactory("VEngineCvar003", nullptr);
    }
    if (!cvarInterface) return 0;

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
    outFile.flush();
    int count = 0;

    if (is007) {
        auto cvar007 = reinterpret_cast<ICvar007 *>(cvarInterface);
        ICvarIteratorInternal *iter = cvar007->FactoryInternalIterator();
        if (iter) {
            for (iter->SetFirst(); iter->IsValid(); iter->Next()) {
                ConCommandBase *cmd = iter->Get();
                if (!cmd || !cmd->m_pszName) continue;
                if (count > 0) outFile << ",\n";
                FormatAndWriteCvar(outFile, cmd);
                outFile.flush();
                ++count;
            }
        }
    } else {
        auto cvar004 = reinterpret_cast<ICvar004 *>(cvarInterface);
        ConCommandBase *head = cvar004->GetCommands();
        for (ConCommandBase *cmd = head; cmd != nullptr; cmd = cmd->m_pNext) {
            if (!cmd || !cmd->m_pszName) continue;
            if (count > 0) outFile << ",\n";
            FormatAndWriteCvar(outFile, cmd);
            outFile.flush();
            ++count;
        }
    }

    outFile << "\n]\n";
    outFile.close();

    std::string msg = "SUCCESS!\nDumped " + std::to_string(count) + " cvars to your Desktop:\n\n" + dumpPath;
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
