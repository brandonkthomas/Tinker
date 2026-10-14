<div align="center">
  <a href="https://github.com/brandonkthomas/Tinker">
    <img src="Public/AppIcon/AppIcon-256.png" alt="Tinker icon" width="128" height="128">
  </a>

  <h3 align="center">Tinker</h3>

  <p align="center">
    macOS app for hidden and hard-to-reach system settings
    <br />
    <br />
    <a href="https://swift.org"><img alt="Swift" src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white"></a>
    <a href="https://developer.apple.com/swiftui/"><img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-0A84FF?logo=swift&logoColor=white"></a>
    <a href="https://www.apple.com/macos/"><img alt="macOS" src="https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white"></a>
  </p>
</div>

## About the Project

Tinker puts the macOS settings a developer usually changes on a new Mac in one window: the ones buried in System Settings, the ones only reachable with `defaults write`, and a few that need a system command.

It started as a shell script ([macos-deploy-helper.zsh](https://github.com/brandonkthomas/deployment-scripts)) and covers everything that script did, plus the hidden preferences that tools like OnyX expose.

### Feature Highlights

- **About 120 settings in 12 categories**: Dock, Finder, menu bar, windows, security, login window, keyboard, screenshots, Safari, Terminal, TextEdit and more.
- **Three profiles**: every setting is tagged Recommended, Personal or Advanced, and the list can be filtered to one of them.
- **Apply the Recommended profile in one step**: review every change first, untick the ones you do not want, then apply.
- **Reset per setting**: any preference can be returned to the system default.
- **Honest state**: each row shows the current value on this Mac. A value Tinker cannot read shows as Unknown instead of a guess.
- **Search**: by name, group, or preference key.
- **System checks**: Gatekeeper, firewall, FileVault, System Integrity Protection, Remote Login, Homebrew and the Xcode Command Line Tools.

## Screenshots

Work in progress...

## Getting Started

Requires macOS 27 and Xcode 27.

```bash
git clone https://github.com/brandonkthomas/Tinker.git
```

Open `Tinker.xcodeproj`, choose your own team under Signing & Capabilities for the `Tinker` and `TinkerHelper` targets, and run the `Tinker` scheme.

To build under your own team, also change the team identifier in `TinkerShared/HelperInterface.swift`. The helper only accepts requests from an app signed by the team named there.

## Permissions

Tinker works without any setup, but two kinds of setting need a permission. Both are granted once in System Settings and are listed under Settings in the app.

| Permission | Needed for | Granted in |
|---|---|---|
| Full Disk Access | Reading and changing Safari and TextEdit settings, which those apps keep in a protected folder | Privacy & Security > Full Disk Access |
| Administrator access | Settings stored for the whole Mac: login window, software updates, firewall, Gatekeeper, Remote Login, computer names | General > Login Items & Extensions |

Administrator access uses a small helper (`TinkerHelper`) that macOS runs as root only while a change is being made. It accepts requests only from Tinker, and it can only write the preference keys and run the commands compiled into it (`TinkerShared/HelperInterface.swift`). It never runs a shell or takes a command from the app.

## How It Works

Every setting is one entry in [`Tinker/Resources/Catalog.json`](Tinker/Resources/Catalog.json): its category, group, profile, control, and either a preference key or a named system setting. Adding a preference-backed setting means adding an entry there; no code changes are needed.

| Folder | Contents |
|---|---|
| `Tinker/Model` | Catalog types, preference reading and writing, profiles, system settings |
| `Tinker/Views` | The window: sidebar, dashboard, setting rows and controls |
| `TinkerShared` | Code compiled into both the app and the helper |
| `TinkerHelper` | The root helper |
| `LaunchDaemons` | The helper's launch daemon definition |
| `TinkerTests` | Unit tests |

## Notes

- Tinker is not sandboxed, because a sandboxed app cannot change other apps' preferences. It cannot be distributed through the Mac App Store.
- Hidden preferences are undocumented and can change between macOS releases. Keys were checked on macOS 27.0.
- Some changes only show after the Dock, Finder or the affected app restarts. Tinker offers to restart the Dock and Finder and tells you which apps to reopen.

## Releases

Release builds are signed with a Developer ID certificate and notarized by Apple.
