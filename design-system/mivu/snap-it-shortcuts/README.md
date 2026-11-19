# Snap It shortcut videos

The three clips in `ios/Mivu/Resources/SnapItShortcuts/` show how to add the
Snap It control to the Lock Screen, Control Center and Action button. They play
in `SnapItShortcutsView` (`ios/Mivu/Diary/SnapItTip.swift`). iOS has no API to
add the control for the user, so the app shows the real system flow instead.

They are screen recordings of the iPhone 17 Pro simulator (iOS 27.0, en_US),
with the tap markers the recorder draws. Re-record them when a new iOS changes
any of these screens.

## Recording

1. Install a Debug build so the simulator knows the Snap It control.
2. Start state: Lock Screen with its default buttons, Control Center without
   Snap It, Action Button set to Silent Mode.
3. Record the whole screen while doing each flow by hand or by script:
   - Lock Screen: touch and hold, Customize, remove a bottom button, +, type
     "Snap", pick Snap It, Done, tap the wallpaper.
   - Control Center: from Mivu, swipe down from the top right, touch and hold,
     Add a Control, type "Snap", pick Snap It, tap an empty area.
   - Action Button: Settings, Action Button, swipe to Controls, Choose a
     Control, type "Snap", pick Snap It.
4. Trim and encode each recording:

   ```sh
   python3 tighten.py raw.mp4 snap-it-lock-screen.mp4 1.3 "27.4-29.2"
   ```

   The third argument is how many seconds to drop from the start; the optional
   fourth lists extra idle ranges to drop, in source seconds. The script
   shortens every still stretch to 0.5 s, holds the final frame 1.6 s, and
   writes 600-pixel-wide HEVC without audio (about 0.5 MB per clip).

Simulator limits to know: its Control Center has almost no controls, and its
Action Button list has four entries, so Controls is one swipe away instead of
several.
