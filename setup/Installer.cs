using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace DR2AutosaveSetup
{
    public enum GameState { Missing, WrongVersion, Supported }

    public class ModSettings
    {
        public int IntervalMinutes = 5;
        public bool ShowNotification = true;
        public bool KeepBackups = true;
    }

    public class InstallerException : Exception
    {
        public InstallerException(string message) : base(message) { }
    }

    public static class Installer
    {
        public const string GameExe = "DR2_us.exe";
        public static readonly int[] Intervals = { 2, 5, 10, 15, 30 };
        const string ModDll = "d3dx9_43.dll", Original = "d3dx9_43.dll.original", Ini = "dr2_autosave.ini", Log = "dr2_autosave.log";
        const string Mark = "DR2 Autosave";

        public static string SaveFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "My Games", "Danganronpa2");
        public static string BackupFolder => Path.Combine(SaveFolder, "AutosaveBackups");
        public static string LogPath(string folder) => Path.Combine(folder, Log);

        public static string FindGameFolder()
        {
            var steamRoots = new List<string>();
            foreach (var (hive, key, value) in new[] {
                (Registry.CurrentUser, @"Software\Valve\Steam", "SteamPath"),
                (Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath") })
                using (var k = hive.OpenSubKey(key))
                    if (k?.GetValue(value) is string path) steamRoots.Add(path.Replace('/', '\\'));

            var libraries = new List<string>(steamRoots);
            foreach (var root in steamRoots)
            {
                var vdf = Path.Combine(root, "steamapps", "libraryfolders.vdf");
                if (!File.Exists(vdf)) continue;
                try
                {
                    foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"(.+?)\""))
                        libraries.Add(m.Groups[1].Value.Replace(@"\\", @"\"));
                }
                catch (IOException) { } // an unreadable list only means the player browses manually
            }

            return libraries.Distinct(StringComparer.OrdinalIgnoreCase)
                .Select(l => Path.Combine(l, "steamapps", "common", "Danganronpa 2 Goodbye Despair"))
                .FirstOrDefault(f => CheckGame(f) != GameState.Missing);
        }

        public static GameState CheckGame(string folder)
        {
            var exe = string.IsNullOrEmpty(folder) ? null : Path.Combine(folder, GameExe);
            if (exe == null || !File.Exists(exe)) return GameState.Missing;
            try
            {
                using (var r = new BinaryReader(File.OpenRead(exe)))
                {
                    if (r.BaseStream.Length < 0x40) return GameState.WrongVersion;
                    r.BaseStream.Position = 0x3C;
                    var pe = r.ReadInt32();
                    if (pe < 0 || pe > r.BaseStream.Length - 84) return GameState.WrongVersion;
                    r.BaseStream.Position = pe + 8;
                    var stamp = r.ReadUInt32();
                    r.BaseStream.Position = pe + 80;
                    return stamp == 0x57C6D776 && r.ReadUInt32() == 0x489000 ? GameState.Supported : GameState.WrongVersion;
                }
            }
            catch (Exception e) when (e is IOException || e is UnauthorizedAccessException)
            {
                return GameState.WrongVersion;
            }
        }

        public static bool DirectXPresent() =>
            File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.SystemX86), ModDll));

        public static bool IsGameRunning()
        {
            var running = Process.GetProcessesByName("DR2_us");
            foreach (var p in running) p.Dispose();
            return running.Length > 0;
        }

        public static bool IsModInstalled(string folder) => IsOurDll(Path.Combine(folder ?? "", ModDll));

        static bool IsOurDll(string path)
        {
            if (!File.Exists(path)) return false;
            try { return Encoding.ASCII.GetString(File.ReadAllBytes(path)).Contains(Mark); }
            catch (Exception e) when (e is IOException || e is UnauthorizedAccessException) { return false; }
        }

        public static ModSettings ReadSettings(string folder)
        {
            var s = new ModSettings();
            var path = Path.Combine(folder ?? "", Ini);
            if (!File.Exists(path)) return s;
            try
            {
                foreach (var line in File.ReadAllLines(path))
                {
                    var kv = line.Split('=');
                    if (kv.Length != 2 || !int.TryParse(kv[1].Trim(), out var v)) continue;
                    switch (kv[0].Trim())
                    {
                        case "IntervalMinutes": if (Intervals.Contains(v)) s.IntervalMinutes = v; break;
                        case "ShowNotification": s.ShowNotification = v != 0; break;
                        case "KeepBackups": s.KeepBackups = v != 0; break;
                    }
                }
            }
            catch (Exception e) when (e is IOException || e is UnauthorizedAccessException) { }
            return s;
        }

        // Autosave slots (28-30) already holding the player's own saves.
        public static int PlayerSavesInAutosaveSlots(string saveFolder)
        {
            var taken = new HashSet<string>();
            foreach (var name in new[] { "savedata.vfs", "savedata_jp.vfs", "savedata_ch.vfs" })
            {
                var path = Path.Combine(saveFolder, name);
                if (!File.Exists(path)) continue;
                byte[] d;
                try { d = File.ReadAllBytes(path); }
                catch (Exception e) when (e is IOException || e is UnauthorizedAccessException) { continue; }

                long o = 0;
                while (d.Length - o >= 4)
                {
                    var nameLen = BitConverter.ToUInt32(d, (int)o);
                    if (nameLen == 0xDEADBEEF || nameLen == 0 || nameLen > 64 || d.Length - o - 8 < nameLen) break;
                    var entry = Encoding.ASCII.GetString(d, (int)o + 4, (int)nameLen);
                    var size = BitConverter.ToUInt32(d, (int)(o + 4 + nameLen));
                    o += 8 + nameLen;
                    if (size > d.Length - o) break;
                    if (Regex.IsMatch(entry, @"^data00(27|28|29)\.bin$") &&
                        (size < Mark.Length || Encoding.ASCII.GetString(d, (int)o, Mark.Length) != Mark))
                        taken.Add(entry);
                    o += size;
                }
            }
            return taken.Count;
        }

        public static void Install(string folder, ModSettings settings)
        {
            Guarded(folder, () =>
            {
                if (CheckGame(folder) != GameState.Supported)
                    throw new InstallerException("This copy of the game is not supported. The mod needs the current Steam version.");
                if (!DirectXPresent())
                    throw new InstallerException("DirectX 9 files are missing. Start the game once from Steam, then run this setup again.");

                var dll = Path.Combine(folder, ModDll);
                var original = Path.Combine(folder, Original);
                var incoming = dll + ".new";
                var foreign = File.Exists(dll) && !IsOurDll(dll);
                if (foreign && File.Exists(original))
                    throw new InstallerException("Another mod is using d3dx9_43.dll in the game folder. Remove it first.");

                byte[] payload;
                using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream(ModDll))
                using (var m = new MemoryStream())
                {
                    s.CopyTo(m);
                    payload = m.ToArray();
                }

                var movedForeign = false;
                try
                {
                    File.WriteAllBytes(incoming, payload);
                    if (!Sha256(File.ReadAllBytes(incoming)).SequenceEqual(Sha256(payload)))
                        throw new InstallerException("The mod file was not written correctly. Check the drive and try again.");
                    if (foreign) { File.Move(dll, original); movedForeign = true; }
                    if (File.Exists(dll)) File.Replace(incoming, dll, null);
                    else File.Move(incoming, dll);
                    WriteSettings(folder, settings);
                }
                catch
                {
                    if (File.Exists(incoming)) File.Delete(incoming);
                    if (movedForeign)
                    {
                        if (File.Exists(dll)) File.Delete(dll);
                        File.Move(original, dll);
                    }
                    throw;
                }
            });
        }

        public static void Uninstall(string folder)
        {
            Guarded(folder, () =>
            {
                var dll = Path.Combine(folder, ModDll);
                var original = Path.Combine(folder, Original);
                if (IsOurDll(dll)) File.Delete(dll);
                if (File.Exists(original) && !File.Exists(dll)) File.Move(original, dll);
                File.Delete(Path.Combine(folder, Ini));
                File.Delete(Path.Combine(folder, Log));
            });
        }

        static void WriteSettings(string folder, ModSettings s)
        {
            var path = Path.Combine(folder, Ini);
            var incoming = path + ".new";
            File.WriteAllText(incoming, "[Autosave]\r\n" +
                $"IntervalMinutes={s.IntervalMinutes}\r\n" +
                $"ShowNotification={(s.ShowNotification ? 1 : 0)}\r\n" +
                $"KeepBackups={(s.KeepBackups ? 1 : 0)}\r\n", new ASCIIEncoding());
            if (File.Exists(path)) File.Replace(incoming, path, null);
            else File.Move(incoming, path);
        }

        static byte[] Sha256(byte[] data)
        {
            using (var h = SHA256.Create()) return h.ComputeHash(data);
        }

        static void Guarded(string folder, Action action)
        {
            if (IsGameRunning()) throw new InstallerException("Close the game first, then try again.");
            if (!Directory.Exists(folder)) throw new InstallerException("The game folder no longer exists.");
            try { action(); }
            catch (UnauthorizedAccessException)
            {
                throw new InstallerException("Windows denied access to the game folder. Right-click the setup and choose Run as administrator.");
            }
            catch (IOException e)
            {
                throw new InstallerException("A game file could not be changed: " + e.Message);
            }
        }
    }
}
