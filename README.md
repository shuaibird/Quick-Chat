# Quick Chat

**The ⌥Space chat bar we all loved in ChatGPT Classic, brought to the new ChatGPT app.**

Press ⌥Space anywhere on your Mac, ask a quick question, and get a plain ChatGPT chat in a small floating panel: no agent task, and (for now) no Work or Codex usage.

Quick Chat is a small menu-bar app for macOS. It works alongside the new ChatGPT desktop app (and frees ⌥Space from its Mini shortcut), but it doesn't need it: without any ChatGPT app installed, it runs on its own as a standalone quick chat.

https://github.com/user-attachments/assets/794aeec5-806e-40d9-b5fb-b281d90393a4

*Reading an article, hitting an unfamiliar term, asking about it with ⌥Space, and getting back to reading.*

## Why this exists

ChatGPT Classic for Mac has a chat bar on ⌥Space: press it anywhere, ask a question, get a normal chat.

The new ChatGPT desktop app (Chat, Work and Codex) works differently:

- **⌥Space opens Mini**, which starts Work/Codex agent tasks, not plain chats.
- **The experimental Popout Window** (Settings → Experimental features) also starts Work/Codex agent tasks.
- **Plain chat is only reachable inside the app window.** There is no system-wide shortcut to it.

That matters because, today, the two kinds of usage are metered differently. Work and Codex share one usage allowance with a 5-hour window and a weekly limit, while Chat has its own model availability and message limits ([OpenAI: Managing usage in Work and Codex](https://help.openai.com/en/articles/20001516)). A quick question asked through Mini counts against the agent allowance you may want to keep for real tasks.

#### Announced, not yet live (November 2026)

OpenAI has told users (by email) that it plans to combine Chat and Work, and to replace the separate limits with one allowance shared by ChatGPT and Codex. Instant won't count against it. Neither change has a date yet. Once the shared allowance is live, only Instant answers in Quick Chat stay off it, and Quick Chat's main value becomes ⌥Space for a plain chat.

Why not just keep using ChatGPT Classic? Its chat bar is great, but Classic is going away:

- **It retires on January 30, 2027**, per OpenAI's notice in the app. After that, the ⌥Space chat bar has no official replacement.
- **New features skip it.** OpenAI still ships model updates and bug fixes, but says new features may come only to the new app ([OpenAI: Moving to the new ChatGPT desktop app](https://help.openai.com/en/articles/20001276)). Classic hasn't had a new build since July 2026, and in daily use its chat bar has become flaky.
- **It can't show Intelligent UI**, GPT-6's answers that mix text, visuals and interactive elements. In OpenAI's words: "The older ChatGPT desktop apps for macOS and Windows do not support these capabilities; use ChatGPT on the web instead." ([OpenAI: GPT-6 and other models in ChatGPT](https://help.openai.com/en/articles/20001354-gpt-6-and-other-models-in-chatgpt))

Quick Chat *is* ChatGPT on the web, so you keep the ⌥Space chat bar after Classic retires and get every new web feature the day it ships.

Quick Chat fills the gap the simple way: it shows chatgpt.com in a small floating panel, so every message is a regular ChatGPT chat.

## What it does

Two features, both off until you turn them on from the menu-bar icon. Your choices are remembered.

### Quick Chat

- A global shortcut (⌥Space by default; change it with **Change Shortcut…**) toggles a floating panel with chatgpt.com inside.
- The panel is 420×560 by default, so chatgpt.com uses its compact layout. It is resizable; the size and position are remembered. The green title-bar button (or a title-bar double-click, or ⌘F) maximizes the panel to fill the screen, leaving the menu bar and Dock visible, and restores your size on a second click. ⌘O resets it to the default size.
- It stays on top of other windows and doesn't hide when you click elsewhere. The shortcut, Esc, ⌘W or the close button hides it.
- Reopening the panel returns to the conversation you left. Press ⇧⌘O for a new chat.
- Sign in once inside the panel. **Sign Out of Quick Chat** clears the panel's website data.
- Voice works; macOS asks for microphone access the first time.
- It doesn't need the ChatGPT desktop app. If the new app isn't installed, the Show Mini options are simply unavailable and the rest works the same.

#### ChatGPT's own keyboard shortcuts work too

chatgpt.com has built-in keyboard shortcuts, and they all reach the panel. Together they make the panel work almost like a standalone ChatGPT app, without touching the mouse:

| Shortcut | Action |
| --- | --- |
| ⌘K | Switch chat (search your chats) |
| ⇧⌘O | New chat |
| ⇧⌘S | Toggle sidebar |
| ⌘U | Attach files |
| ⇧⌘⌫ | Delete chat |
| ⌘/ | Show all shortcuts (and change them) |

These come from chatgpt.com's own **Keyboard shortcuts** dialog (⌘/), as of October 2026. Quick Chat only reserves Esc and ⌘W (hide the panel) ⌘O (reset the panel size) and ⌘F (maximize or restore the panel).

### Disable Show Mini Shortcut

Unbinds the new ChatGPT app's Show Mini shortcut (⌥Space by default). Mini itself still works from inside the app; only the shortcut is removed.

#### How it interacts with the ChatGPT app's shortcuts

The new ChatGPT app reads its shortcuts from `~/.codex/keybindings.json` (or `$CODEX_HOME/keybindings.json`). To free ⌥Space, Quick Chat adds one entry there:

```json
{"command": "openAvatarOverlay", "key": null}
```

This is the same "unbound" entry the ChatGPT app writes itself when it detects a shortcut clash.

- **Automatic when shortcuts clash.** If Quick Chat's shortcut is the same as Show Mini's, Show Mini is unbound while Quick Chat is on, even if Disable Show Mini Shortcut is off.
- **Restart needed.** ChatGPT reads this file only at launch. Quick Chat offers **Restart ChatGPT to Apply**; it never restarts ChatGPT on its own.
- **Restored on quit.** Turning the features off, or quitting Quick Chat, puts your previous entry back (ChatGPT picks it up at its next restart). A backup in `~/Library/Application Support/ChatGPTCompanion/` restores it on the next launch if Quick Chat crashed.
- If the keymap file isn't valid JSON, Quick Chat leaves it alone.

## Install

**Let an AI assistant walk you through it:** tell Claude, ChatGPT or another assistant
*"Read https://github.com/shuaibird/Quick-Chat/blob/main/INSTALL.md and help me install Quick Chat."*
[INSTALL.md](INSTALL.md) gives it step-by-step instructions for both options below.

### Download (prebuilt)

Get `Quick-Chat-<version>.zip` from the [latest release](https://github.com/shuaibird/Quick-Chat/releases/latest).
It is a universal app (Apple silicon and Intel) and needs macOS 14 Sonoma or later.

1. Double-click the zip to unzip it, then drag **Quick Chat.app** into **Applications**.
   Run it from Applications, not from Downloads.
2. Open Quick Chat. The first time, macOS blocks it with
   *"Apple could not verify 'Quick Chat' is free of malware…"*. Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down to **Security**, and click
   **Open Anyway** next to "Quick Chat was blocked…". Confirm with **Open Anyway** and your
   login password. The button only appears for about an hour after the blocked launch;
   if it's gone, open the app again first.

   Or, in Terminal, after moving the app to Applications:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Quick Chat.app"
   ```

Quick Chat then lives in the menu bar (it has no Dock icon).

**Why the warning?** Quick Chat is open source and each release is built by GitHub Actions
from the tagged source, but it isn't signed with an Apple Developer ID or notarized by Apple,
so macOS warns about it like any such app downloaded from the internet. (On macOS 15 and
later, Control-click → Open no longer skips this.) If you'd rather not trust a prebuilt
binary, [build it yourself](#build-from-source).

**Verify the download** (optional): download the matching `.sha256` file to the same folder, then

```sh
cd ~/Downloads && shasum -a 256 -c Quick-Chat-<version>.zip.sha256
```

**Updating:** quit Quick Chat, replace the app in Applications with the new one, and repeat
the Open Anyway step. See [Permissions](#permissions) for why macOS may ask for the
microphone or camera again.

### Build from source

Requirements: macOS 14 or later and Swift 6.0 or later. Xcode 16 or later is recommended
(developed with Xcode 26.3 / Swift 6.2). The Command Line Tools alone (`xcode-select --install`)
can work for single-architecture builds. If `swift build` fails there with "Unknown error parsing
property list", install Xcode. Universal builds (`UNIVERSAL=1`) need Xcode.

```sh
git clone https://github.com/shuaibird/Quick-Chat.git
cd Quick-Chat
make            # build and sign "build/Quick Chat.app"
make run        # build, quit any running copy, open it
make install    # copy to /Applications (or: make install PREFIX=~/Applications)
make uninstall  # remove it again
make clean      # remove .build and build/
```

Apps you build yourself aren't quarantined, so Gatekeeper doesn't block them.

Build options (environment variables for `make` or `scripts/build-app.sh`):

| Variable | Default | Effect |
| --- | --- | --- |
| `CODESIGN_IDENTITY` | first "Apple Development" identity, else ad-hoc | signing identity; `-` forces ad-hoc |
| `UNIVERSAL=1` | off | build for arm64 and x86_64 |
| `VERSION` | latest `v*` git tag, else `0.0.0-dev` | `CFBundleShortVersionString` |
| `BUNDLE_ID` | `dev.shuaibird.quickchat` | bundle identifier |

To test the keybindings code (uses temp files only): `QUICKCHAT_SELFTEST=keymap .build/debug/QuickChat`

### Permissions

Quick Chat needs no Accessibility or Automation access. macOS asks for the **microphone**
the first time you use voice, and for the **camera** if you take a photo or share video.

Release builds, and local builds without an Apple Development certificate, are signed
ad-hoc. macOS identifies an ad-hoc app by the hash of its code, so after every update or
rebuild it treats Quick Chat as a new app and may ask again. To clear stale entries:

```sh
tccutil reset Microphone dev.shuaibird.quickchat
tccutil reset Camera dev.shuaibird.quickchat
```

If you build from source, signing with a free Apple Development certificate
(Xcode → Settings → Accounts) keeps the grants across rebuilds. The build script picks it
up automatically.

## Limitations

**It's a web wrapper.**
- It runs chatgpt.com in a web view, not a native ChatGPT client. You sign in separately from any ChatGPT app.
- Google sign-in works only because the panel identifies itself as Safari. Google blocks sign-in from embedded web views and may detect this at any time. Email, Apple or Microsoft sign-in avoid that risk.
- Passkeys and security keys don't work in the panel. macOS allows them only in web browsers. If a sign-in page offers a passkey, choose **Try another way** and use your password or a code instead.
- You get the website's interface, not Classic's native chat UI. Your chats are regular ChatGPT conversations in your web history.
- When chatgpt.com changes, the compact layout or focusing the message box can break.

**Downloads and camera.** Files you download (generated images, exports) are saved straight to ~/Downloads and shown in Finder. Camera capture asks for macOS camera access the first time. Some cases may still fail, such as the right-click "Download Image" item, and `alert()`/`confirm()` dialogs from the site aren't shown.

**It depends on ChatGPT app internals.**
- The Show Mini command id (`openAvatarOverlay`) is undocumented. A ChatGPT update may rename it, and the shortcut handling would stop working until Quick Chat is updated.
- ChatGPT must restart before a shortcut change takes effect.

**The usage benefit will narrow** once OpenAI's planned shared allowance goes live (see [Announced, not yet live](#announced-not-yet-live-november-2026)). Only Instant answers will stay off it.

**Ad-hoc signed.** The release isn't signed with an Apple Developer ID or notarized. macOS treats each new build as a different app, so permissions such as microphone access must be granted again after every update.

## Privacy

- Quick Chat has no servers, analytics or telemetry. The panel talks only to chatgpt.com and the sign-in provider you choose; other links open in your default browser.
- Your sign-in session is stored locally in the app's web data. **Sign Out of Quick Chat** deletes it.
- Nothing inside the ChatGPT app bundle is modified. The only file Quick Chat changes is the ChatGPT app's own `keybindings.json`, and it restores that file when you turn the features off or quit.

## Not affiliated with OpenAI

Quick Chat is an independent open-source project. It is not affiliated with, endorsed by or sponsored by OpenAI. ChatGPT is a trademark of OpenAI, used here only to describe what the app works with.

## Releasing (maintainers)

The tag is the version. `git tag -a v0.1.0 -m "Quick Chat 0.1.0" && git push origin v0.1.0`
triggers `.github/workflows/release.yml`. It builds a universal, ad-hoc-signed app,
verifies it, and attaches `Quick-Chat-0.1.0.zip` and its `.sha256` to a GitHub release.
Tags with a `-` (e.g. `v0.2.0-beta.1`) become prereleases. To test without releasing, run
the workflow manually (`gh workflow run release.yml -f version=0.1.0-test`); it uploads the
zip as a workflow artifact.

## License

[MIT](LICENSE)
