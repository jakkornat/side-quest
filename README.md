<p align="center">
  <img src="docs/images/app-icon.png" alt="Side Quest app icon" width="128" height="128">
</p>

<h1 align="center">Side Quest</h1>

<p align="center"><em>Your quest log, beyond Azeroth.</em></p>

Turn everyday tasks into quests. Side Quest is a native macOS app with a parchment journal and a floating desktop tracker, inspired by the classic World of Warcraft interface. Gather your objectives, choose your next adventure, and turn in each quest when the work is done.

Stone panels, gold trim, and red buttons set the mood. Textures are generated procedurally, and the app runs locally without accounts, network access, or downloaded assets.

## Requirements

- **Apple Silicon Mac (arm64)** — Intel Macs are not supported.
- **macOS 14 or later.**
- To build from source: **Xcode with Swift 6** and **Lua**.

## Build and launch

### Grab & Go

You can download the latest ready-to-use app from [GitHub Releases](https://github.com/jakkornat/side-quest/releases) without building it from source.

**Good to know** that the app is signed locally with an ad hoc signature and is not notarized, so macOS may require you to approve it before opening.

### Install with Homebrew

```sh
brew install --cask jakkornat/tap/side-quest
```

This installs the latest release for Apple Silicon. The app is signed locally with an ad hoc signature and is not notarized, so macOS may require you to approve it before opening.

### Build from source

Install Lua if needed:

```sh
brew install lua
```

From the repository root:

```sh
lua scripts/build-app.lua
open "dist/Side Quest.app"
```

The script builds an arm64 release, packages the icon, fonts, and licenses, and applies a local ad hoc signature with `codesign --sign -`. It recreates the resource bundle and app package to keep obsolete files out of the build. Quit the running app before rebuilding.

You can move `dist/Side Quest.app` to your Applications folder. This build uses local signing; it is not a Developer ID-signed, notarized distribution.

For development, open `Package.swift` in Xcode and run the `SideQuest` target. The Lua build script also accepts paths containing spaces and can be invoked from another directory using its full path.

## Pick up a quest

1. Press **⌘N** to create a quest. Give it a name, priority, difficulty, and a list of objectives.
2. Press **⌘S** to save. Switching quests or closing the journal also attempts to save a valid form.
3. Work through your objectives in the journal or desktop tracker. The tracker always shows the first incomplete objective in your chosen order.
4. Complete every objective, then choose **Turn In Quest** in the journal. The quest moves to the Completed tab. Victory earned.

A quest needs at least one objective before it can be turned in. Checking the final box makes it ready to turn in tho it does not finish the quest automatically.


### Keep the trail in sight

- Drag the **Quests** header to move the tracker.
- Use **− / +** to collapse or expand the tracker, or the arrow beside a quest to toggle its details.
- The tracker floats above ordinary windows across desktops and is configured to appear alongside fullscreen apps.
- The tracker's **⚙** button opens the journal. A quest ready to turn in also has an **Open Journal** button.
- In the journal, use the overlay button to show or hide the tracker. The **⚙** menu adjusts its background opacity or resets its position.
- Closing the journal leaves the tracker running. Click the app's Dock icon to reopen the journal; use **⌘Q** to quit.

## Your journal stays on your Mac

Data is stored in `~/Library/Application Support/SideQuest/`:

| File | Contents |
| --- | --- |
| `quests.json` | Quests, objectives, progress, and the focused quest. |
| `settings.json` | Tracker position, visibility, collapsed state, and opacity. |

Each file is written atomically. Changing tracker settings does not rewrite quest data, and editing quests does not rewrite settings. The app does not use the network or require Accessibility permissions.

For a separate journal, launch with `--data-file /path/to/quests.json`. Its settings are stored beside it as `/path/to/quests.settings.json`.

## Take a practice run

Explore a few example quests without changing your own journal:

```sh
open "dist/Side Quest.app" --args --demo
```

Demo mode keeps quests and settings in memory. Quit any running instance before launching it.

## Optional sound cues

The repository and app bundle contain **no audio files**. By default, your adventures are silent.

To add your own cues, place MP3 files in `~/Library/Application Support/SideQuest/Sounds/`:

| File | Played when |
| --- | --- |
| `quest-created.mp3` | A new quest is saved or a completed quest is resumed. |
| `quest-completed.mp3` | A quest is turned in. |
| `quest-abandoned.mp3` | A quest is abandoned. |

Missing or unreadable files are skipped. These files stay on your computer and are never copied into the app by the build script. Demo mode uses the same local sound cues.

## Fonts and artwork

The interface uses **Cinzel Decorative** by Natanael Gama for headings and buttons, and **Metamorphous** by Sorkin Type Co for body text and input fields. Both are bundled with their SIL Open Font License 1.1 notices and registered with Core Text for the app process.

The app's stone and parchment textures are generated in code. No texture downloads are needed.

## Languages

The interface supports **English and Polish**, selected through macOS language preferences. English is the default. Regional preferences such as `en-GB` and `pl-PL` resolve to the corresponding supported language. Restart the app after changing language preferences.

Quest names and objectives remain as you wrote them. Demo quests use the interface language.


## License

Source code is available under the [MIT License](LICENSE).

Bundled fonts retain their own SIL Open Font License 1.1 terms:

- [Cinzel Decorative](Sources/SideQuest/Resources/fonts/OFL_Cinzel.txt)
- [Metamorphous](Sources/SideQuest/Resources/fonts/OFL_Metamorphous.txt)

The code's MIT license does not cover third-party materials.
