# Installing Quick Chat: guide for AI assistants

This file is written for an AI assistant (Claude, ChatGPT, Codex, Cursor, …) helping someone
install Quick Chat. If you're a person, the [README](README.md#install) has the same steps.

To use it, tell your assistant:

> Read https://github.com/shuaibird/Quick-Chat/blob/main/INSTALL.md and help me install Quick Chat.

---

## For the assistant

Quick Chat is a macOS menu-bar app (no Dock icon) that shows chatgpt.com in a floating panel
on ⌥Space. Repository: `https://github.com/shuaibird/Quick-Chat`. Bundle id:
`dev.shuaibird.quickchat`. App name on disk: `Quick Chat.app`.

### Ground rules

- **Explain before you act.** Say what each command does before running it, or before asking
  the user to run it if you can't run commands yourself.
- **Never** disable Gatekeeper system-wide (`spctl --master-disable`, `--global-disable`) and
  never use `sudo`. Neither is needed.
- Removing the quarantine flag from Quick Chat is the user's decision. Explain what it means
  (step R4) and get a yes first.
- Don't edit `~/.codex/keybindings.json` by hand. Quick Chat manages its own entry there.
- If a step fails, show the user the exact error and use [Troubleshooting](#troubleshooting)
  before trying anything else.

### Step 0: check the Mac

```sh
sw_vers -productVersion   # must be 14.0 or later
uname -m                  # arm64 (Apple silicon) or x86_64 (Intel); both are supported
```

If macOS is older than 14, stop: Quick Chat won't run there.

### Step 1: pick a path

Ask the user which they want, and recommend the first unless they say otherwise:

1. **Download the release** (recommended for most people): a few minutes, no developer tools.
   macOS shows a one-time "could not verify" warning because the app isn't notarized.
2. **Build from source**: for people who'd rather not run a prebuilt binary or who want to
   change the code. Needs Xcode (or the Command Line Tools) and takes longer, but there's no
   Gatekeeper warning.

---

## Path A: download the release

**R1. Download the latest zip and its checksum** into a fresh folder:

```sh
mkdir -p ~/Downloads/quick-chat && cd ~/Downloads/quick-chat
api=https://api.github.com/repos/shuaibird/Quick-Chat/releases/latest
for url in $(curl -fsSL "$api" | grep -oE '"browser_download_url": *"[^"]+\.zip(\.sha256)?"' | grep -oE 'https://[^"]+'); do
  curl -fLO "$url"
done
ls
```

You should see `Quick-Chat-<version>.zip` and `Quick-Chat-<version>.zip.sha256`. If the API is
rate-limited or unreachable, have the user download both files by hand from
`https://github.com/shuaibird/Quick-Chat/releases/latest`.

**R2. Verify the checksum:**

```sh
shasum -a 256 -c Quick-Chat-*.zip.sha256
```

It must print `OK`. If it doesn't, delete the files and stop; don't install a mismatched zip.

**R3. Unzip and move to Applications.** If Quick Chat is already running (updating), quit it
first: menu-bar icon → **Quit Quick Chat**, or `pkill -x QuickChat`.

```sh
ditto -x -k Quick-Chat-*.zip .
rm -rf "/Applications/Quick Chat.app"
mv "Quick Chat.app" /Applications/
```

The app must run from Applications, not Downloads.

**R4. Get past Gatekeeper (one time per version).** Explain first: *the release is built by
GitHub Actions from the public source, but it isn't signed with an Apple Developer ID or
notarized, so macOS blocks the first launch.* Then offer two ways:

- **Terminal (quicker).** With the user's OK:

  ```sh
  xattr -dr com.apple.quarantine "/Applications/Quick Chat.app"
  open "/Applications/Quick Chat.app"
  ```

- **System Settings (no Terminal).** Walk the user through it:
  1. Open **Quick Chat** from Applications. macOS says *"Apple could not verify 'Quick Chat' is
     free of malware…"*. Click **Done**.
  2. Open **System Settings → Privacy & Security**, scroll to **Security**, click
     **Open Anyway** next to "Quick Chat was blocked…", then confirm with **Open Anyway** and
     the login password.
  3. The button only shows for about an hour after the blocked launch. If it's missing, open
     the app once more and check again.

  On macOS 15 and later, Control-click → Open no longer skips this.

Then continue with [First run](#first-run).

---

## Path B: build from source

**B1. Check the toolchain:**

```sh
xcode-select -p
swift --version   # needs Swift 6.0 or later
```

- If `xcode-select -p` fails, the user needs developer tools. Recommend installing **Xcode 16
  or later** from the App Store (most reliable). The Command Line Tools
  (`xcode-select --install`) are smaller and can work, but see the plist error under
  Troubleshooting.
- If Xcode is installed but `swift --version` reports an older compiler, the active developer
  directory may be wrong; have the user pick the newer Xcode in Xcode → Settings → Locations
  → Command Line Tools.
- The first time Xcode is installed, it may need its license accepted: open Xcode once.

**B2. Clone and build:**

```sh
git clone https://github.com/shuaibird/Quick-Chat.git
cd Quick-Chat
make
```

This writes `build/Quick Chat.app`. The first build takes a minute or two.

**B3. Install and open:**

```sh
make install                       # copies to /Applications and quits any running copy
open "/Applications/Quick Chat.app"
```

If the user can't write to /Applications, use `make install PREFIX=~/Applications` and open
`~/Applications/Quick Chat.app` instead. Self-built apps aren't quarantined, so there's no
Gatekeeper prompt.

**Optional: keep microphone and camera grants across rebuilds.** If the user signed in to
Xcode with an Apple ID (Xcode → Settings → Accounts), they have a free Apple Development
certificate and the build script uses it automatically. Without one the app is signed ad-hoc,
and macOS may ask for microphone access again after every rebuild.

**Updating later:** `git pull && make install` from the clone.

Then continue with [First run](#first-run).

---

## First run

Tell the user:

1. Quick Chat appears **only in the menu bar** (a speech bubble with sparkles). There's no
   Dock icon or window yet. If the menu bar is crowded, the icon may be hidden behind the
   notch; quitting another menu-bar app or using a menu-bar manager reveals it.
2. Click the icon and turn on **Quick Chat**. Both features start off.
3. Press **⌥Space**. A small panel opens with chatgpt.com. Sign in once inside it. Email,
   Apple or Microsoft sign-in are the most reliable; Google sign-in works today but Google may
   block embedded browsers at any time.
4. Press ⌘N for another window and ⌘W to close the current one. Press ⌥Space or Esc to hide all windows. **Change Shortcut…** in the menu picks another global key.
5. **If the new ChatGPT desktop app is installed**, it also uses ⌥Space (for Show Mini).
   Quick Chat frees that shortcut automatically while it uses it, and offers
   **Restart ChatGPT to Apply**: ChatGPT only reads shortcut changes at launch. Quick Chat
   never restarts ChatGPT on its own. Quitting Quick Chat restores the original shortcut.
6. The first time the user speaks to ChatGPT, macOS asks for microphone access. Allow it.

To launch it at login: **System Settings → General → Login Items → Open at Login → +**, then
choose Quick Chat.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "Quick Chat is damaged and can't be opened" | The zip was unpacked by a tool that broke the signature. Re-download, unzip with Finder or `ditto` (step R3), then do step R4. |
| "Open Anyway" button not in Privacy & Security | It only shows for about an hour after a blocked launch. Open the app again, then look again. |
| Nothing visible after opening | It's a menu-bar app; look for the icon, which can be hidden behind the notch. `pgrep -x QuickChat` confirms it's running. |
| ⌥Space does nothing | Turn on **Quick Chat** in the menu. If ChatGPT still grabs ⌥Space, choose **Restart ChatGPT to Apply**. Another app (Raycast, Alfred, input-source switching) may also own ⌥Space; pick a different shortcut with **Change Shortcut…**. |
| `swift build` fails with "Unknown error parsing property list" | Happens with the Command Line Tools alone. Install Xcode and select it (B1). |
| `UNIVERSAL=1 make` fails | Universal builds need full Xcode, and a normal `make` is fine for one Mac. |
| `swift: command not found` / `xcrun: error: invalid active developer path` | Developer tools are missing; see B1. |
| Microphone or camera keeps being asked for after an update | Expected for ad-hoc-signed builds. To clear stale entries: `tccutil reset Microphone dev.shuaibird.quickchat` and `tccutil reset Camera dev.shuaibird.quickchat`. |
| Want to remove it | Quit from the menu (this restores ChatGPT's shortcut), then delete `/Applications/Quick Chat.app` (or `make uninstall` in a clone). To also clear settings: `defaults delete dev.shuaibird.quickchat` and `rm -rf ~/Library/Application\ Support/ChatGPTCompanion`. |

For anything else, point the user to the
[issue tracker](https://github.com/shuaibird/Quick-Chat/issues) with the macOS version, the
install path they used, and the exact error.
