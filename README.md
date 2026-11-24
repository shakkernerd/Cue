# Cue

Cue is a small macOS menu-bar app that fires an action when you push the pointer onto a screen edge while holding modifier keys. Hold Control, push the pointer against the right edge for a moment, and Cue presses a keyboard shortcut for you, system-wide, or runs a shell command.

It was built to switch a monitor's input from the same gesture that moves a shared mouse between two Macs: BenQ Display Pilot 2 switches the input on Ctrl+Shift+1 / Ctrl+Shift+4, and Logi Flow moves the mouse on Control + screen edge.

Cue only listens to pointer movement. It never blocks, delays or changes your own mouse events, and it does not watch the keyboard: it reads which modifier keys are held from the pointer events themselves.

## How a trigger fires

A rule fires when all of these hold:

- The pointer is on an **outer** edge of its display: an edge, or the part of an edge, that no other display adjoins. Where another display adjoins, the pointer crosses over instead of resting, so that part never fires.
- The pointer was **pushed** into the edge: it moved toward the edge while on it. A pointer placed or moved onto the edge by software (for example Logi Flow bringing it in from another Mac) has no push and does not arm the rule.
- **Exactly** the rule's modifier keys are held. Control + Option does not fire a Control rule. Caps Lock and Fn are ignored.
- The pointer **rests** there for 150 ms, and the same modifiers are still held at the end of it. A quick pass over the edge does nothing.

A rule fires once per arrival. To fire it again, move the pointer off that edge and push into it again.

## Requirements

- macOS 14 or later
- Xcode or the Xcode Command Line Tools with Swift 6

## Build and install

```bash
scripts/build-app.sh
```

This builds `build/Cue.app` and signs it. Copy it to `/Applications` and open it:

```bash
cp -R build/Cue.app /Applications/
open /Applications/Cue.app
```

Cue appears in the menu bar (no Dock icon).

Signing: the script signs with the first Apple Development certificate in your keychain. Set `CUE_SIGN_IDENTITY` to a different codesign identity (name or SHA-1 hash), or to `-` for ad-hoc signing. Without a certificate it signs ad-hoc and prints a warning: macOS ties the Accessibility permission to the signature, so an ad-hoc build loses it on every rebuild.

To build and test without the app bundle:

```bash
swift build
swift test
```

## Allow Accessibility

Accessibility is the only permission Cue needs: it lets Cue watch the pointer and post keystrokes. On first launch macOS asks for it; choose **Open System Settings** and turn on **Cue** under **Privacy & Security → Accessibility**. Cue never changes this setting itself.

Until the permission is on, the menu shows **Accessibility: not allowed** with an **Allow in System Settings…** item, and the menu-bar icon is crossed out. Cue starts watching within a second of the permission being turned on.

## Launch at login

Choose **Launch at Login** in the menu to start Cue automatically when you log in. The item is checked while Cue is registered as a login item, and choosing it again removes the login item. Cue reads the real status from macOS each time the menu opens, so the checkmark also follows changes you make under **System Settings → General → Login Items**.

macOS may ask you to allow the login item. Until you do, the item shows a dash instead of a checkmark, with **Launch at Login needs approval in System Settings** and an **Open Login Items Settings…** item that opens the pane. Cue never changes that setting itself. If macOS refuses to register or remove the login item, the menu shows the reason.

Cue registers the app you are running, so launch the copy you want at login, for example the one in `/Applications`, before turning it on.

## Configure

Rules live in `~/.config/cue/config.json`. Cue creates it on first launch with no rules:

```json
{
  "rules": []
}
```

Choose **Open Config** in the menu to edit it. Cue applies the file as soon as you save it, with no restart, however your editor saves: in place, by replacing the file, or by deleting and recreating it. **Reload Config** in the menu reads it again on demand.

Each rule has a `trigger` and an `action`:

```json
{
  "rules": [
    {
      "trigger": { "edge": "right", "modifiers": ["control"] },
      "action": { "keys": "ctrl+shift+1" }
    }
  ]
}
```

- `trigger.edge`: `left`, `right`, `top` or `bottom`.
- `trigger.modifiers`: the modifier keys that must be held, exactly: any of `control` (`ctrl`), `option` (`opt`, `alt`), `shift`, `command` (`cmd`). An empty list means no modifiers held.
- `action`: exactly one of
  - `keys`: the keystroke to post, written as modifiers and one key joined by `+`, such as `ctrl+shift+4`, `cmd+option+left` or `f13`. Case and spaces around `+` do not matter.
  - `shell`: a command to run, such as `"open -a Safari"` or `"~/bin/desk.sh"`. See [Shell commands](#shell-commands).

Two rules may not share the same edge and modifiers. If the config has an error, the menu shows it with its location, for example `rules[0].trigger.edge: expected one of left, right, top, bottom`, and no rules from that file are used. While Cue runs, a save with an error, or deleting the file, keeps the rules from the last working save in force; the error shows until a save fixes it. **Open Config** on a deleted file starts a new config with no rules.

### Keys

| Name | Keys |
|---|---|
| Letters and digits | `a`–`z`, `0`–`9` |
| Punctuation | `-` (`minus`), `=` (`equal`), `[` (`leftbracket`), `]` (`rightbracket`), `\` (`backslash`), `;` (`semicolon`), `'` (`quote`), `,` (`comma`), `.` (`period`), `/` (`slash`), `` ` `` (`grave`) |
| Function keys | `f1`–`f20` |
| Navigation | `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown` |
| Other | `return` (`enter`), `tab`, `space`, `delete` (`backspace`), `forwarddelete`, `escape` (`esc`) |

Key names refer to positions on the **US ANSI** keyboard layout. Cue posts the key at that position, so with another layout active the character produced may differ: on a German layout `y` posts the key labeled Z.

The posted keystroke carries only the modifiers written in `keys`. The modifiers you are holding for the trigger are not added: a Control trigger with `"keys": "shift+f1"` posts Shift+F1, not Control+Shift+F1.

### Shell commands

```json
{
  "trigger": { "edge": "bottom", "modifiers": ["control", "option"] },
  "action": { "shell": "date >> ~/cue.log" }
}
```

Cue runs the command with your login shell, the shell set for your user account (zsh unless you changed it), as `<shell> -l -c '<command>'`. So `~`, `$HOME`, pipes and redirection work, and so does the `PATH` your shell's login files set (`.zprofile`, `.bash_profile`, Homebrew's `shellenv`). Files read only by interactive shells, such as `.zshrc`, are not read. csh and tcsh do not accept `-l` together with `-c`, so with them Cue runs `<shell> -c '<command>'`, which reads `.cshrc` but not `.login`.

- The command starts in your home directory with Cue's environment.
- Cue does not wait for it. It starts the command and keeps watching, so a slow command such as `sleep 5` does not delay the next trigger. Each trigger starts a new run, even while an earlier one is still going, and a running command keeps running when Cue quits.
- Input is empty and output is discarded. Redirect inside the command to keep it: `"my-script >> ~/cue.log 2>&1"`.
- Cue logs each run's process ID when it starts and its exit status when it ends; a non-zero exit status or a signal is logged as an error (see [Troubleshooting](#troubleshooting)). The command text is not logged, since it can hold secrets.

### Example: switch a BenQ monitor's input with Display Pilot 2

Display Pilot 2 switches the input on Ctrl+Shift+4 (HDMI1) and Ctrl+Shift+1 (USB-C). With a MacBook on USB-C, a Mac Studio on HDMI1 to its left, and Logi Flow moving the mouse between them on Control + screen edge:

On the MacBook, Control + left edge switches to the Mac Studio:

```json
{
  "rules": [
    {
      "trigger": { "edge": "left", "modifiers": ["control"] },
      "action": { "keys": "ctrl+shift+4" }
    }
  ]
}
```

On the Mac Studio, Control + right edge switches back to the MacBook:

```json
{
  "rules": [
    {
      "trigger": { "edge": "right", "modifiers": ["control"] },
      "action": { "keys": "ctrl+shift+1" }
    }
  ]
}
```

When Logi Flow brings the pointer back onto the other Mac with Control still held, the pointer arrives without a push into the edge, so Cue does not switch the input back.

## Troubleshooting

Cue logs to the unified log under the subsystem `com.shakkernerd.cue`. Fired rules, failed shell commands and config errors:

```bash
log show --last 1h --predicate 'subsystem == "com.shakkernerd.cue"'
```

Add `--info` to also see shell commands that ended successfully.

Every pointer event Cue sees, with its position, delta, modifier keys and timing, while you reproduce a problem:

```bash
log stream --level debug --predicate 'subsystem == "com.shakkernerd.cue"'
```

## License

MIT
