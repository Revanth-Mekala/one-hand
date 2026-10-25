# One Hand

A tiny macOS menu bar app that turns single keys into shortcuts, so you can drive your Mac with one hand.

Hold **⌥ Option for 3 seconds** to switch **one-hand mode** on or off. While it's on, the keys below do
their shortcut instead of typing. Any key that isn't mapped still types normally. When it's off, nothing
is remapped.

| Key | Does |
| --- | --- |
| tap `⌥ Option` | Escape |
| hold `⌥ Option` 3 s | Turn one-hand mode on/off (works whether the mode is on or off) |
| `n` | Screenshot (`⌘⇧4`) |
| `v` | Copy (`⌘C`) |
| `b` | Paste (`⌘V`) |
| `⇧ ,` | Tab to the left (`⌘⇧[`) |
| `⇧ .` | Tab to the right (`⌘⇧]`) |
| `space` | Scroll down. Hold to keep scrolling. |
| `u` | Scroll up. Hold to keep scrolling. |

The menu bar icon is a hand: an outline when the mode is off, filled and tinted when it's on. You'll also
hear a short sound when it switches.

## Build and install

You need the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh install     # builds build/OneHand.app, copies it to ~/Applications and starts it
```

`./build.sh` on its own only builds the app.

The first time it runs, macOS asks for **Accessibility** access. That's how it sees and remaps keys.
Turn on **One Hand** in System Settings → Privacy & Security → Accessibility. It starts working within a
couple of seconds, with no restart needed.

> The app has an ad-hoc signature, so macOS treats each rebuild as a new app. After you rebuild, remove
> One Hand from the Accessibility list and add it back.

To start it at login, add `~/Applications/OneHand.app` under System Settings → General → Login Items.

## Customising

Click the menu bar icon and choose **Show Shortcuts** to open the editor (choose **Hide Shortcuts** or
close the window to put it away). Double-click a cell to edit it. **Record Trigger** captures the next key
you press for the selected row. **Save** applies your changes right away. Shortcuts are paused while this
window is focused, so you can type in it.

Everything is stored in `~/Library/Application Support/OneHand/config.json`. To edit the file directly,
use **Open Config File**, then **Reload Config**.

**Triggers** are a key plus optional modifiers: `n`, `space`, `shift+,`, `ctrl+j`, `f5`. A modifier on
its own (`opt`) means *tap that modifier*. Shifted symbols also work, so `<` is the same as `shift+,`.

**Actions** can be:

- a keystroke: `cmd+c`, `esc`, `cmd+shift+4`, `ctrl+tab`, `cmd+left`
- `scroll:up`, `scroll:down`, `scroll:left`, `scroll:right` (keeps scrolling while the key is held)
- `shell:<command>`, for example `shell:open -a Safari`
- `toggle`, which switches one-hand mode

Key names: `a`–`z`, `0`–`9`, `,` `.` `/` `;` `'` `[` `]` `\` `-` `=` `` ` ``, `space`, `tab`, `return`, `esc`, `delete`,
`fwddelete`, `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`, `f1`–`f20`. For any other
key, use `keyNN` with its raw key code. Modifiers: `cmd`, `shift`, `opt` (or `alt`), `ctrl`.

Settings:

| Setting | Default | Meaning |
| --- | --- | --- |
| `toggleKey` | `opt` | Modifier you hold to toggle the mode |
| `toggleHoldSeconds` | `3` | How long to hold it |
| `tapMaxSeconds` | `0.5` | A modifier released faster than this counts as a tap |
| `scrollSpeed` | `14` | Pixels per scroll step (about 60 steps per second) |
| `playSounds` | `true` | Play a sound when the mode switches |
| `startEnabled` | `false` | Start in one-hand mode |

## Notes

- **No CPU while idle.** The app only wakes up when a key is pressed. There's no polling. The only
  timers are the one that runs while you hold Option on its own and the one that runs while you hold a
  scroll key.
- Scrolling goes to whatever is under the mouse pointer, the same as a trackpad or mouse wheel.
- Key names follow the US keyboard layout. On other layouts, use `keyNN` codes or **Record Trigger**.
- Tab switching uses `⌘⇧[` / `⌘⇧]`, which works in Safari, Chrome, Firefox, Terminal, iTerm and VS Code.
  Change it to `ctrl+shift+tab` / `ctrl+tab` if your app prefers those.
- Option still works as a modifier: pressing another key or clicking while you hold it cancels both the
  tap and the 3-second hold.
