using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using unlockfps_nc.Model;
using unlockfps_nc.Utility;

namespace unlockfps_nc.Service
{
    public class ProcessService
    {
        private readonly CancellationTokenSource _cts = new();
        private IntPtr _gameHandle = IntPtr.Zero;
        private int _gamePid = 0;

        private readonly Config _config;

        private readonly IpcService _ipcService;

        public ProcessService(ConfigService configService, IpcService ipcService)
        {
            _config = configService.Config;
            _ipcService = ipcService;

            _ = Task.Run(UnlockerPoll, _cts.Token);
        }

        public bool StartGame()
        {
            if (!File.Exists(_config.GamePath)) {
                MessageBox.Show(@"Game path is invalid.", @"Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }

            if (IsGameRunning()) {
                MessageBox.Show(@"An instance of the game is already running.", @"Error", MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return false;
            }

            if (_gameHandle != IntPtr.Zero) {
                Native.CloseHandle(_gameHandle);
                _gameHandle = IntPtr.Zero;
            }

            if (_config.UseHDR) {
                var subKeyName = Path.GetFileName(_config.GamePath) == "YuanShen.exe" ? "原神" : "Genshin Impact";
                try {
                    using var key = Registry.CurrentUser.CreateSubKey($@"Software\miHoYo\{subKeyName}");
                    key.SetValue("WINDOWS_HDR_ON_h3132281285", 1);
                }
                catch(Exception e) {
                    MessageBox.Show($@"Failed to enable HDR: {e.Message}", @"Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }

            STARTUPINFO si = new();
            var gimiCompatibilityMode = !string.IsNullOrWhiteSpace(_config.GimiLoaderPath);
            var preloadDlls = GetExistingDlls(_config.PreloadDlls)
                .Where(path => !gimiCompatibilityMode || !IsGimiOwnedOrConflictingGraphicsDll(path))
                .ToList();
            var dllList = GetExistingDlls(_config.DllList)
                .Where(path => !gimiCompatibilityMode || !IsGimiOwnedOrConflictingGraphicsDll(path))
                .ToList();
            // A preload DLL must be present before the game's primary thread
            // can load Direct3D.  Force CREATE_SUSPENDED for this case even
            // when the legacy SuspendLoad option was left disabled.
            bool suspendLoad = _config.SuspendLoad || preloadDlls.Count > 0;
            uint creationFlag = suspendLoad ? 4u : 0u; // CREATE_SUSPENDED
            var gameFolder = Path.GetDirectoryName(_config.GamePath);

            if (!Native.CreateProcess(_config.GamePath, BuildCommandLine(), IntPtr.Zero, IntPtr.Zero, false, creationFlag, IntPtr.Zero, gameFolder, ref si, out var pi)) {
                MessageBox.Show(
                    $@"CreateProcess failed ({Marshal.GetLastWin32Error()}){Environment.NewLine} {Marshal.GetLastPInvokeErrorMessage()}",
                    @"Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }

            var injected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var dllsToInject = new List<string>();
            foreach (var dllPath in preloadDlls.Concat(dllList)) {
                var fullPath = Path.GetFullPath(dllPath);
                if (injected.Add(fullPath))
                    dllsToInject.Add(fullPath);
            }

            if (!ProcessUtils.InjectDlls(pi.hProcess, dllsToInject)) {
                MessageBox.Show(
                    $@"Dll Injection failed ({Marshal.GetLastWin32Error()}){Environment.NewLine} {Marshal.GetLastPInvokeErrorMessage()}",
                    @"Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }

            if (suspendLoad)
                Native.ResumeThread(pi.hThread);

            _gamePid = pi.dwProcessId;
            _gameHandle = pi.hProcess;

            Native.CloseHandle(pi.hThread);
            return true;
        }

        public void OnFormClosing()
        {
            _cts.Cancel();
            Native.CloseHandle(_gameHandle);
        }

        private bool IsGameRunning()
        {
            if (_gameHandle == IntPtr.Zero)
                return false;

            if (!Native.GetExitCodeProcess(_gameHandle, out var exitCode))
                return false;

            return exitCode == 259; // STILL_ACTIVE
        }

        private async Task UnlockerPoll()
        {
            while (!_cts.IsCancellationRequested) {

                await Task.Delay(1000, _cts.Token);
                using var process = Process.GetProcesses()
                    .FirstOrDefault(x => x is { ProcessName: "GenshinImpact" } or { ProcessName: "YuanShen" });
                if (process == null)
                    continue;

                while (!ProcessUtils.IsWindowDrawing(process.MainWindowHandle) && !_cts.IsCancellationRequested)
                    await Task.Delay(1000, _cts.Token);

                if (!_ipcService.Start(process.Id))
                    return;

                while (!process.HasExited && !_cts.IsCancellationRequested) {
                    _ipcService.Update();
                    await Task.Delay(62, _cts.Token);
                }

                if (_gameHandle != IntPtr.Zero && _config.AutoClose) {
                    Application.Exit();
                }

                _ipcService.OnGameExit();
                await Task.Delay(5000, _cts.Token);
            }
        }

        private string BuildCommandLine()
        {
            string commandLine = $"{_config.GamePath} ";
            if (_config.PopupWindow)
                commandLine += "-popupwindow ";

            if (_config.UseCustomRes)
                commandLine += $"-screen-width {_config.CustomResX} -screen-height {_config.CustomResY} ";

            commandLine += $"-screen-fullscreen {(_config.Fullscreen ? 1 : 0)} ";
            if (_config.Fullscreen)
                commandLine += $"-window-mode {(_config.IsExclusiveFullscreen ? "exclusive" : "borderless")} ";

            commandLine += $"-monitor {_config.MonitorNum} ";
            commandLine += $"{_config.AdditionalCommandLine} ";
            return commandLine;
        }

        private static bool IsGimiOwnedOrConflictingGraphicsDll(string path)
        {
            var fileName = Path.GetFileName(path);
            return fileName.Equals("d3d11.dll", StringComparison.OrdinalIgnoreCase) ||
                   fileName.Equals("Dx11FsrBridge.dll", StringComparison.OrdinalIgnoreCase) ||
                   fileName.Equals("OptiScaler.dll", StringComparison.OrdinalIgnoreCase) ||
                   fileName.Equals("ReShade64.dll", StringComparison.OrdinalIgnoreCase);
        }

        private static List<string> GetExistingDlls(IEnumerable<string>? paths)
        {
            var result = new List<string>();
            if (paths == null)
                return result;

            foreach (var path in paths) {
                if (string.IsNullOrWhiteSpace(path))
                    continue;

                try {
                    var fullPath = Path.GetFullPath(path.Trim());
                    if (File.Exists(fullPath))
                        result.Add(fullPath);
                }
                catch {
                    // Ignore malformed optional entries.  The normal unlocker
                    // behavior is preserved for valid entries.
                }
            }

            return result;
        }

    }
}
