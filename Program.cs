using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Principal;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace UserAccountAudit
{
    class UserInfo
    {
        public string Username { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public bool IsAdmin { get; set; }
        public string AccountActive { get; set; } = string.Empty;
        public string PasswordRequired { get; set; } = string.Empty;
        public string PasswordExpires { get; set; } = string.Empty;
        public string PasswordLastSet { get; set; } = string.Empty;
        public string LastLogon { get; set; } = string.Empty;
        public string Comment { get; set; } = string.Empty;
        public List<string> Groups { get; set; } = new();
        public List<string> Flags { get; set; } = new();
    }

    class Program
    {
        static int Main(string[] args)
        {
            try
            {
                if (!IsElevated())
                {
                    Console.Error.WriteLine("Warning: not running elevated. Some information (local groups, admin list) may be incomplete. Run as Administrator for full results.");
                }

                var users = GetLocalUsers();
                var admins = GetLocalAdministrators();

                foreach (var u in users)
                {
                    u.IsAdmin = admins.Contains(u.Username, StringComparer.OrdinalIgnoreCase);
                    if (string.Equals(u.AccountActive, "No", StringComparison.OrdinalIgnoreCase) || string.Equals(u.AccountActive, "Disabled", StringComparison.OrdinalIgnoreCase))
                        u.Flags.Add("AccountDisabled");
                    if (string.Equals(u.PasswordRequired, "No", StringComparison.OrdinalIgnoreCase))
                        u.Flags.Add("NoPasswordRequired");
                    if (string.IsNullOrWhiteSpace(u.PasswordLastSet) || string.Equals(u.PasswordLastSet, "Never", StringComparison.OrdinalIgnoreCase))
                        u.Flags.Add("PasswordNeverSet");
                    if (u.IsAdmin) u.Flags.Add("IsAdministrator");
                }

                var json = JsonSerializer.Serialize(users, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText("user_audit.json", json);

                using var sw = new StreamWriter("user_audit.csv");
                sw.WriteLine("Username,FullName,IsAdmin,AccountActive,PasswordRequired,PasswordExpires,PasswordLastSet,LastLogon,Comment,Flags");
                foreach (var u in users)
                {
                    sw.WriteLine($"{EscapeCsv(u.Username)},{EscapeCsv(u.FullName)},{u.IsAdmin},{EscapeCsv(u.AccountActive)},{EscapeCsv(u.PasswordRequired)},{EscapeCsv(u.PasswordExpires)},{EscapeCsv(u.PasswordLastSet)},{EscapeCsv(u.LastLogon)},{EscapeCsv(u.Comment)},{EscapeCsv(string.Join(";", u.Flags))}");
                }

                Console.WriteLine($"Audit complete. Users: {users.Count}. Outputs: user_audit.json, user_audit.csv");
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("Error: " + ex.Message);
                return 2;
            }
        }

        static bool IsElevated()
        {
            if (!OperatingSystem.IsWindows()) return false;

            try
            {
                using var identity = WindowsIdentity.GetCurrent();
                var principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch
            {
                return false;
            }
        }

        static List<UserInfo> GetLocalUsers()
        {
            var users = new List<UserInfo>();
            var output = RunNet("user");
            if (string.IsNullOrWhiteSpace(output)) return users;

            var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).ToList();
            int startIdx = lines.FindIndex(l => l.TrimStart().StartsWith("---"));
            if (startIdx >= 0)
            {
                for (int i = startIdx + 1; i < lines.Count; i++)
                {
                    if (lines[i].Contains("The command completed", StringComparison.OrdinalIgnoreCase)) break;
                    var parts = Regex.Split(lines[i].Trim(), @"\s{2,}");
                    foreach (var p in parts)
                    {
                        var name = p.Trim();
                        if (!string.IsNullOrEmpty(name))
                        {
                            var info = GetUserDetails(name);
                            info.Username = name;
                            users.Add(info);
                        }
                    }
                }
            }
            return users;
        }

        static UserInfo GetUserDetails(string username)
        {
            var info = new UserInfo { Username = username };
            var output = RunNet($"user \"{username}\"");
            if (string.IsNullOrWhiteSpace(output)) return info;
            var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                if (string.IsNullOrWhiteSpace(trimmed)) continue;
                var kv = Regex.Split(trimmed, @"\s{2,}");
                if (kv.Length >= 2)
                {
                    var key = kv[0].Trim();
                    var val = string.Join(" ", kv.Skip(1)).Trim();
                    switch (key)
                    {
                        case "Full Name": info.FullName = val; break;
                        case "Account active": info.AccountActive = val; break;
                        case "Password required": info.PasswordRequired = val; break;
                        case "Password last set": info.PasswordLastSet = val; break;
                        case "Password expires": info.PasswordExpires = val; break;
                        case "Last logon": info.LastLogon = val; break;
                        case "Comment": info.Comment = val; break;
                        default:
                            if (key.StartsWith("Local Group", StringComparison.OrdinalIgnoreCase) || key.StartsWith("Local Group Memberships", StringComparison.OrdinalIgnoreCase) || key.StartsWith("Local Group memberships", StringComparison.OrdinalIgnoreCase))
                            {
                                var groups = Regex.Split(val, @"[,\s\\]+").Where(s => !string.IsNullOrWhiteSpace(s)).ToArray();
                                info.Groups.AddRange(groups);
                            }
                            break;
                    }
                }
            }
            return info;
        }

        static List<string> GetLocalAdministrators()
        {
            var admins = new List<string>();
            var output = RunNet("localgroup Administrators");
            if (string.IsNullOrWhiteSpace(output)) return admins;
            var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).ToList();
            int membersIdx = lines.FindIndex(l => l.Trim().StartsWith("Members", StringComparison.OrdinalIgnoreCase));
            int start = membersIdx >= 0 ? membersIdx + 1 : 0;

            for (int i = start; i < lines.Count; i++)
            {
                var line = lines[i].Trim();
                if (string.IsNullOrEmpty(line)) continue;
                if (line.Contains("The command completed", StringComparison.OrdinalIgnoreCase)) break;
                if (line.StartsWith("Alias name", StringComparison.OrdinalIgnoreCase) || line.StartsWith("Comment", StringComparison.OrdinalIgnoreCase)) continue;
                if (line.StartsWith("---")) continue;

                var parts = Regex.Split(line, @"\s{2,}");
                foreach (var p in parts)
                {
                    var name = p.Trim();
                    if (!string.IsNullOrEmpty(name))
                    {
                        var idx = name.LastIndexOf('\\');
                        if (idx >= 0 && idx < name.Length - 1) name = name.Substring(idx + 1);
                        admins.Add(name);
                    }
                }
            }
            return admins.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        }

        static string RunNet(string arguments)
        {
            try
            {
                var psi = new ProcessStartInfo("net", arguments)
                {
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using var p = Process.Start(psi);
                if (p == null) return string.Empty;

                var outTask = p.StandardOutput.ReadToEndAsync();
                var errTask = p.StandardError.ReadToEndAsync();
                p.WaitForExit();
                Task.WaitAll(outTask, errTask);

                var outp = outTask.Result ?? string.Empty;
                var err = errTask.Result ?? string.Empty;
                return string.IsNullOrEmpty(err) ? outp : outp + "\nERR:\n" + err;
            }
            catch
            {
                return string.Empty;
            }
        }

        static string EscapeCsv(string s)
        {
            if (s == null) return "";
            s = s.Replace('\n', ' ').Replace('\r', ' ');
            if (s.Contains(",") || s.Contains("\""))
            {
                return "\"" + s.Replace("\"", "\"\"") + "\"";
            }
            return s;
        }
    }
}