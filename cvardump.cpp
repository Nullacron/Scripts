#include <windows.h>
#include <fstream>
#include <string>
#include <vector>
#include <utility>
#include <cstdint>
#include <cstring>

// ============================================================================
// Source Engine Definitions
// ============================================================================

typedef void* (*CreateInterfaceFn)(const char *pName, int *pReturnCode);

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
    virtual ~ConVar() {}
    virtual bool IsFlagSet(int flag) const override = 0;
    virtual const char *GetHelpText() const override = 0;
    virtual bool IsRegistered() const override = 0;
    virtual const char *GetName() const override = 0;
    virtual void AddFlags(int flags) override = 0;
    virtual bool IsCommand() const override = 0;
    virtual void SetValue(const char *pValue) override = 0;
    virtual void SetValue(float flValue) override = 0;
    virtual void SetValue(int nValue) override = 0;
    virtual void InternalSetValue(const char *value) = 0;
    virtual void InternalSetFloatValue(float value) = 0;
    virtual void InternalSetIntValue(int value) = 0;
    virtual bool ClampValue(float& value) = 0;
    virtual void ChangeStringValue(const char *tempVal, float flOldValue) = 0;
    virtual void Init() = 0;

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

class ICvarIteratorInternal {
public:
    virtual void SetFirst() = 0;
    virtual void Next() = 0;
    virtual bool IsValid() = 0;
    virtual ConCommandBase *Get() = 0;
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

class ICvar : public IAppSystem {
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

static void DumpConCommandBase(std::ofstream &file, ConCommandBase *cmd) {
    const char *rawName = cmd->GetName();
    const char *rawHelp = cmd->GetHelpText();
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
        ConVar *parent = cvar->m_pParent ? cvar->m_pParent : cvar;

        file << ",\n";
        file << "    \"default\": \"" << EscapeJson(parent->m_pszDefaultValue) << "\",\n";
        file << "    \"value\": \"" << EscapeJson(parent->m_pszString) << "\"";

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
// Core Execution Logic
// ============================================================================

static DWORD WINAPI ExecuteDump(LPVOID) {
    Sleep(200); // Allow engine modules to settle

    ICvar *pCVar = nullptr;
    const char *cvarVersions[] = { "VEngineCvar007", "VEngineCvar004", "VEngineCvar003" };

    HMODULE hVstdlib = GetModuleHandleA("vstdlib.dll");
    if (!hVstdlib) hVstdlib = LoadLibraryA("vstdlib.dll");

    if (hVstdlib) {
        auto vstdlibFactory = reinterpret_cast<CreateInterfaceFn>(GetProcAddress(hVstdlib, "CreateInterface"));
        if (vstdlibFactory) {
            for (const char *ver : cvarVersions) {
                pCVar = reinterpret_cast<ICvar *>(vstdlibFactory(ver, nullptr));
                if (pCVar) break;
            }
        }
    }

    if (!pCVar) {
        MessageBoxA(NULL, "Could not find ICvar in vstdlib.dll!", "CVar Dumper", MB_ICONERROR | MB_OK);
        return 0;
    }

    // Determine path next to the game executable
    char dumpPath[MAX_PATH] = {0};
    GetModuleFileNameA(NULL, dumpPath, MAX_PATH);
    char *lastSlash = strrchr(dumpPath, '\\');
    if (lastSlash) {
        *(lastSlash + 1) = '\0';
        strcat_s(dumpPath, MAX_PATH, "cvars_dump.json");
    } else {
        strcpy_s(dumpPath, MAX_PATH, "cvars_dump.json");
    }

    std::ofstream outFile(dumpPath, std::ios::out | std::ios::trunc);
    if (!outFile.is_open()) {
        char err[512];
        snprintf(err, sizeof(err), "Failed to write file to:\n%s", dumpPath);
        MessageBoxA(NULL, err, "CVar Dumper", MB_ICONERROR | MB_OK);
        return 0;
    }

    outFile << "[\n";
    int count = 0;
    ICvarIteratorInternal *iter = pCVar->FactoryInternalIterator();
    if (iter) {
        for (iter->SetFirst(); iter->IsValid(); iter->Next()) {
            ConCommandBase *cmd = iter->Get();
            if (!cmd) continue;
            if (count > 0) outFile << ",\n";
            DumpConCommandBase(outFile, cmd);
            ++count;
        }
    }
    outFile << "\n]\n";
    outFile.close();

    char successMsg[1024];
    snprintf(successMsg, sizeof(successMsg), "SUCCESS! Dumped %d cvars to:\n\n%s", count, dumpPath);
    MessageBoxA(NULL, successMsg, "CVar Dumper", MB_ICONINFORMATION | MB_OK);

    return 0;
}

// ============================================================================
// DllMain (Runs the moment the DLL is loaded)
// ============================================================================

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID) {
    if (fdwReason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hinstDLL);
        CreateThread(NULL, 0, ExecuteDump, NULL, 0, NULL);
    }
    return TRUE;
}

// Export for plugin_load compatibility
extern "C" __declspec(dllexport) void *CreateInterface(const char *, int *pReturnCode) {
    if (pReturnCode) *pReturnCode = 0;
    return (void*)1;
}
