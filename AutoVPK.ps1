[CmdletBinding()]
param (
    # Pass path directly: .\AutoVPK.ps1 -DestDir "C:\path\to\mod"
    [Parameter(Position = 0)]
    [string]$DestDir,

    # Force the modern folder prompt to appear: .\AutoVPK.ps1 -SelectFolder
    [switch]$SelectFolder
)

$ErrorActionPreference = "Stop"

# Configuration
$vpkEdit    = "C:\Program Files\VPKEdit\vpkeditcli.exe"
$sourceDir  = Join-Path $PSScriptRoot "pak01"
$configFile = Join-Path $PSScriptRoot ".destdir"

# --- Modern Windows Explorer Folder Picker ---
function Get-ModernFolderPicker {
    param(
        [string]$Title = "Select Destination Folder",
        [string]$InitialDirectory = ""
    )

    if (-not ([System.Management.Automation.PSTypeName]'ModernFolderDialog').Type) {
        $csharpCode = @"
using System;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;

public class ModernFolderDialog {
    [DllImport("kernel32.dll", ExactSpelling = true)]
    private static extern IntPtr GetConsoleWindow();

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int SHCreateItemFromParsingName(
        [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
        IntPtr pbc,
        ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItem ppv);

    // Fixed CLSID: E88A instead of E882
    [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    private class FileOpenDialogRCW { }

    [ComImport, Guid("D57C7288-D4AD-4768-BE02-9D969532D960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOpenDialog {
        [PreserveSig] int Show([In] IntPtr parent);
        void SetFileTypes();
        void SetFileTypeIndex();
        void GetFileTypeIndex();
        void Advise();
        void Unadvise();
        void SetOptions([In] uint fos);
        void GetOptions();
        void SetDefaultFolder();
        void SetFolder([In] IShellItem psi);
        void GetFolder();
        void GetCurrentSelection();
        void SetFileName();
        void GetFileName();
        void SetTitle([In, MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel();
        void SetFileNameLabel();
        void GetResult([Out] out IShellItem ppsi);
        void AddPlace();
        void SetDefaultExtension();
        void Close();
        void SetClientGuid();
        void ClearClientData();
        void SetFilter();
        void GetResults();
        void GetSelectedItems();
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem {
        void BindToHandler();
        void GetParent();
        void GetDisplayName([In] uint sigdnName, [Out] out IntPtr ppszName);
        void GetAttributes();
        void Compare();
    }

    public static string ShowDialog(string title, string initialPath) {
        if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA) {
            return ShowInternal(title, initialPath);
        }

        string result = null;
        var thread = new Thread(() => {
            result = ShowInternal(title, initialPath);
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        return result;
    }

    private static string ShowInternal(string title, string initialPath) {
        var dialog = (IFileOpenDialog)new FileOpenDialogRCW();
        try {
            // FOS_PICKFOLDERS (0x20) | FOS_FORCEFILESYSTEM (0x40)
            dialog.SetOptions(0x20 | 0x40);

            if (!string.IsNullOrEmpty(title)) {
                dialog.SetTitle(title);
            }

            if (!string.IsNullOrEmpty(initialPath) && Directory.Exists(initialPath)) {
                Guid shellItemGuid = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");
                IShellItem initialItem;
                if (SHCreateItemFromParsingName(initialPath, IntPtr.Zero, ref shellItemGuid, out initialItem) == 0) {
                    dialog.SetFolder(initialItem);
                }
            }

            IntPtr owner = GetConsoleWindow();
            int hr = dialog.Show(owner);
            if (hr == 0) {
                IShellItem resultItem;
                dialog.GetResult(out resultItem);
                IntPtr pPath;
                // SIGDN_FILESYSPATH = 0x80058000
                resultItem.GetDisplayName(0x80058000, out pPath);
                string path = Marshal.PtrToStringUni(pPath);
                Marshal.FreeCoTaskMem(pPath);
                return path;
            }
            return null;
        } finally {
            Marshal.ReleaseComObject(dialog);
        }
    }
}
"@
        Add-Type -TypeDefinition $csharpCode
    }

    return [ModernFolderDialog]::ShowDialog($Title, $InitialDirectory)
}

# 1. Resolve Destination Directory
if (-not $DestDir -and -not $SelectFolder -and (Test-Path $configFile)) {
    $DestDir = (Get-Content $configFile -Raw).Trim()
}

# If not set or -SelectFolder was passed, open modern dialog
if (-not $DestDir -or $SelectFolder) {
    Write-Host "Opening folder selection dialog..." -ForegroundColor Cyan
    $pickedDir = Get-ModernFolderPicker -Title "Select Target Mod Folder (Destination for pak01_dir.vpk)" -InitialDirectory $DestDir

    if (-not $pickedDir) {
        Write-Host "`n[CANCELLED] No folder selected. Aborting build." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit..."
        exit 0
    }

    $DestDir = $pickedDir
    Set-Content -Path $configFile -Value $DestDir -Force
}

$destFile = Join-Path $DestDir "pak01_dir.vpk"

# 2. Validation Checks
if (-not (Test-Path $vpkEdit)) {
    Write-Host "[ERROR] VPKEdit CLI not found at: $vpkEdit" -ForegroundColor Red
    Read-Host "`nPress Enter to exit..."
    exit 1
}

if (-not (Test-Path $sourceDir -PathType Container)) {
    Write-Host "[ERROR] Source folder not found: $sourceDir" -ForegroundColor Red
    Read-Host "`nPress Enter to exit..."
    exit 1
}

if (-not (Test-Path $DestDir)) {
    Write-Host "Destination folder does not exist. Creating: $DestDir" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
}

# 3. Clean up existing VPK files
$existingVpks = Get-ChildItem -Path $DestDir -Filter "pak01*.vpk" -ErrorAction SilentlyContinue

if ($existingVpks) {
    Write-Host "Deleting existing pak01 VPK files..." -ForegroundColor Yellow
    foreach ($file in $existingVpks) {
        try {
            Remove-Item $file.FullName -Force
        } catch {
            Write-Host "`n[ERROR] Failed to delete: $($file.Name)" -ForegroundColor Red
            Write-Host "Make sure Portal 2 is closed and you have write permissions." -ForegroundColor Red
            Read-Host "`nPress Enter to exit..."
            exit 1
        }
    }
}

# 4. Pack the new VPK
Write-Host "Target: $destFile" -ForegroundColor DarkGray
Write-Host "Packing mod into pak01_dir.vpk..." -ForegroundColor Cyan
& $vpkEdit -s -v 1 -o $destFile $sourceDir

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[SUCCESS] pak01_dir.vpk created successfully!" -ForegroundColor Green
} else {
    Write-Host "`n[ERROR] Failed to build VPK (Exit code: $LASTEXITCODE)." -ForegroundColor Red
    Read-Host "`nPress Enter to exit..."
    exit $LASTEXITCODE
}
