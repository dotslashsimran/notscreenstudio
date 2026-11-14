# Manual test checklist

Follow these steps on your Mac (macOS 15). Each step says what "good" looks like. If a step does not match, note the step number and what you saw.

Recordings are saved in `~/Movies/notscreenstudio/` as `.nssproj` folders. Exports go to `~/Movies/` by default.

## 1. Build and launch

1. In the repo folder run `./scripts/bundle.sh`. It builds a release app, signs it ad hoc, and runs a self check.
   - Good: the last lines are `smoke-test OK: renderer=Metal sources=wired` and `Built build/NotScreenStudio.app`.
2. Run `open build/NotScreenStudio.app`.
   - Good: a record icon (a circle) appears in the menu bar. There is no Dock icon and no window yet.
3. If no permission window opens by itself, click the menu bar icon.
   - Good: the menu shows a big Record button, a source choice, a microphone choice and a camera choice.

## 2. Permissions

4. Open the Permissions window from the menu (or let it open on first launch). Click Allow for Screen Recording, Camera and Microphone.
   - Good: the system asks for each one. After you allow them, each row shows as granted.
5. Quit the app (menu bar icon, then Quit) and open it again once. Screen Recording only takes effect after a restart.
   - Good: the source list in the menu now shows your displays and windows, with no permission warning.

Note: every time you rebuild with `bundle.sh` the app is signed ad hoc again, so macOS may treat it as a new app. If recording suddenly fails with a permission message, open System Settings, Privacy & Security, remove notscreenstudio from Screen Recording, Camera and Microphone, then add it again and restart the app.

## 3. Record

6. Choose your main display. Turn on the microphone and the camera in the menu. Click Record.
   - Good: a small recording bar with a running timer appears. A camera bubble shows your face over the screen. Recording starts at once, with no extra dialog.
7. Move the mouse around, click a few different places in different corners of the screen (wait about one second between clicks), and speak a sentence.
   - Good: nothing lags and the screen stays smooth.
8. While recording, drag the camera bubble to another corner and make it larger or smaller if you can.
   - Good: the bubble follows the mouse and stays where you drop it.
9. Stop with the Stop button on the recording bar (or the global stop shortcut shown in the menu).
   - Good: the editor window opens by itself within a few seconds, showing your recording.
10. In Finder open `~/Movies/notscreenstudio/` and right-click the newest `.nssproj` folder, then Show Package Contents.
    - Good: it holds `project.json`, `screen.mov`, `camera.mov`, `mic.m4a` and `cursor.json`. `cursor.json` is more than a few kilobytes.
11. Record again, this time choosing a single window as the source. Drag that window around while recording, click inside it, then stop.
    - Good: the editor shows only that window. In the editor the cursor stays on the right spot inside the window even though the window moved.
12. Record again, this time choosing Area and dragging a rectangle over part of the screen. Click inside the area, then stop.
    - Good: the editor shows only that area, and clicks land where you made them.

## 4. Edit

Open each recording in the editor and check the following.

13. Press Space to play.
    - Good: playback is smooth (no stutter), your voice plays in sync with the picture, and the camera bubble moves with the video.
14. Auto-zoom: watch the moment after each click.
    - Good: the view eases in toward the click, holds for a moment, then eases out. It does not jump. It should not zoom for clicks that are far apart in a way that makes the picture swing wildly.
15. Smooth cursor: watch the arrow while you moved the mouse.
    - Good: the cursor glides along a smooth path instead of jittering. Raise Smoothing in the inspector and the path gets softer.
16. Motion blur: find a fast mouse move and pause on it, then raise Motion blur in the inspector.
    - Good: the arrow smears along the direction it moved. A still cursor stays sharp.
17. Click ripples: step through frames right after a click (Right Arrow).
    - Good: a ring grows out from the click point and fades. Turning Click ripples off in the inspector removes it.
18. Background: change the background to a solid color, a gradient and a wallpaper.
    - Good: the preview updates at once, with no flicker. A gradient shows no visible banding.
19. Rounded corners and shadow: raise Corner radius, Shadow blur and Shadow opacity in the inspector, and change Padding.
    - Good: the screen has rounded corners, a soft shadow sits under it, and more padding shrinks the screen inside the frame.
20. Camera bubble shapes: try circle, rounded rectangle, squircle and rectangle. Drag the bubble in the preview.
    - Good: each shape draws cleanly with smooth edges, the bubble sits where you left it while recording (mapped over the same part of the screen), and it follows your drag.
21. Aspect ratio: switch between 16:9, 1:1 and 9:16.
    - Good: the preview changes shape. The screen stays centered and fits, the zoom still follows your clicks, and the camera bubble stays inside the picture.
22. Trim and zoom blocks: drag the trim handles on the timeline to cut the start and end. Then add a zoom block, drag it, change its zoom level and pick its focus point in the preview.
    - Good: playback stays inside the trim. The new zoom block shows on the timeline and the preview zooms to the point you picked during that block. Undo and Redo (Command Z, Shift Command Z) revert each change.

## 5. Export

23. Choose Export. Pick 1080p and click Export.
    - Good: a progress bar fills, and when it ends the file exists at the chosen path. It does not take much longer than the video itself.
24. Open the MP4 in QuickTime Player and check the details (Command I).
    - Good for 16:9: 1920×1080 at 60 fps. For 1:1: 1080×1080. For 9:16: 1080×1920. Voice and picture are in sync, and the video matches the trim you set.
25. Compare the MP4 with the editor preview: zoom timing, cursor, ripples, background and the camera bubble position.
    - Good: they look the same.
26. Export again at 4K.
    - Good: sizes are 3840×2160, 2160×2160 and 2160×3840 for the three shapes. The file plays smoothly. It takes longer than 1080p, but the app stays responsive.
27. Quit and reopen the app, then choose Open Last Recording in the menu.
    - Good: your edits (trim, style, zoom blocks) were saved automatically.

## 6. Quick regression check for the automated tests

28. In the repo run `swift test -j 2`. Optionally run `NSS_E2E_4K=1 swift test -j 2 --filter EndToEndExportTests` for the 4K exports, and `NSS_BENCH=1 swift test -j 2 --filter PreviewPerformanceTests` for the preview timing budget.
    - Good: all tests pass.
