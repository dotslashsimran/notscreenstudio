# notscreenstudio plan

## Goal

The goal is a free, native macOS 15 screen recorder like Screen Studio. It differs from Screen Studio in four ways. It is free. Recording starts with one click. The preview is smooth at 60 fps. Everything stays on the user's Mac, with no network use, no telemetry and no accounts.

## Frontend

You record in one click from the menu bar. You pick a display, a window or an area. A timeline lets you trim the recording and add zoom blocks. An inspector controls the background, the frame, the cursor and the camera. A camera bubble can be dragged anywhere on the video. Export is available at 1080p or 4K.

## Backend

The app captures the screen, the microphone and the webcam. It logs the mouse 120 times a second, plus clicks. Spring physics drive the zooms and the cursor. A GPU renderer built on Metal draws every frame. A 60 fps MP4 exporter writes the result. Projects are autosaved.

## Must-haves

Auto-zoom on clicks, a smooth cursor with motion blur, click ripples, backgrounds with rounded corners and a shadow, a camera bubble in any shape, and the 16:9, 1:1 and 9:16 aspect ratios.

## Modules

| Target | Responsibility | Owning worker |
| --- | --- | --- |
| NSSCore | Shared models, conventions and protocols (the contracts) | Phase 0 skeleton, then additive changes only |
| NSSCapture | Screen, mic and camera recording into a project bundle | Recording |
| NSSInput | 120 Hz cursor and click logging into a CursorTrack | Input + Projects |
| NSSProject | `.nssproj` bundles: create, load, save, autosave | Input + Projects |
| NSSMotion | Pure Swift MotionModel: spring camera, cursor smoothing, ripples (Opus) | Motion |
| NSSRender | Metal FrameRenderer and shader sources compiled at runtime (Opus) | Renderer |
| NSSExport | 60 fps MP4 exporter using MotionModel and FrameRenderer | Export |
| NSSUI/Shell | Menu bar, source picker, recording HUD, camera bubble overlay | App shell UI |
| NotScreenStudio | App entry point and scene wiring | App shell UI |
| NSSUI/Editor | Preview, timeline and inspector | Editor UI |

## Phases

Phase 0 is the shared skeleton: this PR, with the package layout, the NSSCore contracts, stub implementations, CI, PLAN.md and AGENTS.md.

Phase 1 has seven parallel workers. Each owns its folder and opens its own PR.

1. Recording owns NSSCapture.
2. Input + Projects owns NSSInput and NSSProject.
3. Motion owns NSSMotion (Opus).
4. Renderer owns NSSRender (Opus).
5. Export owns NSSExport.
6. App shell UI owns NSSUI/Shell and NotScreenStudio.
7. Editor UI owns NSSUI/Editor.

Phase 2 is one integration worker. It wires record, edit and export end to end, verifies that the preview holds 60 fps, and exports a test clip in all three aspect ratios at both 1080p and 4K.

## Data flow

Recording writes a `.nssproj` bundle in `~/Movies/notscreenstudio`. The bundle holds the media files, `cursor.json` and `project.json`. The editor loads that bundle. The MotionModel turns the cursor track and the timeline into a FrameState for each frame. The FrameRenderer composites the frame from the screen pixels, the camera pixels, the FrameState and the Style. The preview and the export share the same MotionModel and the same FrameRenderer, so they match exactly.
