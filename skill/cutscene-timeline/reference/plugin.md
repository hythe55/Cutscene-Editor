# The Cutscene Editor plugin

The user guide is the repo's `README.md`. This file covers how the plugin is built and the traps met while building it.

## Repo and build

- `src/Plugin/Main.server.luau` is the entry Script. `src/Editor/` holds the editor. `src/Runtime/Timeline/` is the canonical runtime.
- `node build.js` writes and verifies `dist/CutsceneEditor.rbxmx`. `--install` copies it into `%LOCALAPPDATA%\Roblox\Plugins`, and Studio hot-reloads it with no restart.
- `--sync-runtime <dir>` mirrors the runtime into a game. `--dev-mirror` puts Editor and Runtime ModuleScripts into a game's ServerStorage for MCP tests. `--dev-mirror-clean` removes them.
- Every build also mirrors `skill/cutscene-timeline` into `.claude/skills/cutscene-timeline`. `--install-skill` copies it into `~/.claude/skills` so it triggers in every project.
- Sources are normalised to LF. VS Code and PowerShell `Set-Content` write CRLF on Windows, and an early build refused them.

## Modules

| Folder | Job |
|---|---|
| `Document/` | The only writer. Every edit goes through `_record` (one ChangeHistory recording), and it owns keyframe sources and replica sync |
| `App/` | State, rows (tracks, joint groups, joints), selection, settings, the shell and splitters |
| `TimelineView/` | Lanes, blocks, sub-keys, hit testing, drags, snapping |
| `LaneHeaders/` | Track, group and joint headers with mute, lock and expand |
| `Inspector/`, `ScriptPanel/`, `Toolbar/` | Panels generated from `Timeline.Schema` |
| `Tools/` | Pose tool (joint pick, rings, range edit, key roles), key gizmos for Camera, Move and Attach |
| `Preview/` | Runs the real runtime on copies, with stand-ins, camera lock and restore |
| `Export/` | Collect, bake, upload, pick id, store |
| `JointGroups.luau` | Sorts joint keys into Body, Head, arms, hands, legs and cloth by name and side |

## Undo model

- One user action is one recording: a block move, a retime, a key move, a gizmo drag, a pose nudge, a range edit. Moving the playhead or scrolling records nothing.
- Drags patch the live preview while moving and write the Document once on release.
- Deletes inside a recording use `Parent = nil`. `Destroy()` locks Parent, and undo then fails with "The Parent property ... is locked".
- ChangeHistory records nothing under an `Archivable=false` ancestor, even after Archivable is set to true later. Build undo test fixtures archivable from creation.
- `FinishRecording(id, Cancel)` reverts *every* change made during the window, including the user's unrelated edits. Restore the world first. Commit if anything outside changed, and cancel only when nothing did. Never hold a recording open while the user edits.
- An open recording makes every other `TryBeginRecording` fail, including other tools'. Keep recordings short.
- `GetCanUndo` returns the recording *identifier*, not the display name. Give each tool distinct identifiers, and check the top waypoint before calling `Undo()`. Several scripted `Undo()` calls in one frame restored only some edits, so space them across frames.
- The preview must rebuild after undo or redo without touching recordings. Committing and restarting a preview recording on each undo wiped the redo stack.
- Hiding originals with `LocalTransparencyModifier` creates undo waypoints, even when the value does not change.

## Drags and input

- **Release detection.** A capture button created on mouse-down never received that press's release inside a DockWidget, so drags stuck to the pointer ("click to grab, click to drop"). Watch the press's own InputObject: `input:GetPropertyChangedSignal("UserInputState")` reaching End or Cancel. As a fallback, end the drag on the next press seen by the capture overlay.
- Use a small movement threshold before a press becomes a drag, and let Escape cancel mid-drag with no recording.
- `UserInputService:GetFocusedTextBox()` returns nil inside a DockWidget. Track `TextBox.Focused` and `FocusLost` yourself, so shortcuts do not fire while typing. Never bind Backspace to delete.
- `plugin:Activate(true)` for PluginMouse picking blocks Studio's own selection. Activate only during an explicit pick mode.

## Rendering

- Rotated GuiObjects ignore `ClipsDescendants`, so diamonds and diagonals drew over the headers. Draw ramps with an unrotated frame plus a UIGradient (`UIGradient.Rotation` works in pixel space). Keep rotated key diamonds inside a clipped parent that does not scroll past headers.
- Take every colour from `settings().Studio.Theme` and re-skin on theme change. Fixed pastels had 1.6:1 contrast in the Light theme.
- Handles and ArcHandles parented to CoreGui render and create no undo step. A skinned MeshPart adornee puts handles at the part's bounds, not at a bone, so drive bone gizmos from invisible proxy Parts placed at `bone.TransformedWorldCFrame`.
- `screen_capture` never shows AlwaysOnTop adornments or CoreGui ScreenGuis. Hide markers within about 1.5 studs of the camera, or they fill the shot when viewing through a key.

## Preview

- Run the real runtime with `Preview = true` on copies under an `Archivable=false` container, and hide originals with `LocalTransparencyModifier`. Stop restores everything, including the camera's CFrame, Focus, FieldOfView and CameraType.
- After unlocking the camera, set Focus straight ahead at the saved distance, or the view re-aims about 4 degrees on the next frame. Take "from view" keys from the camera the viewport actually shows.
- While the preview runs, measure and select against the preview copy, never the world original. "Add key from actor pivot" once moved the real character.
- Rebuilding the preview on every write cost about 80 ms on a 200-clip cutscene. Patch live state during drags instead.
- Build R15 stand-ins once and reuse them, with WrapTarget, WrapLayer, WrapDeformer and FaceControls removed. Debounce start and stop (0.3 s). Studio crashed natively while a test started and stopped the preview twice within a second.
- Sound objects do not play in edit mode (`Playing` is true but `TimePosition` never moves). Preview 2D audio with AudioPlayer into AudioDeviceOutput, and 3D audio with AudioEmitter and an AudioListener on the camera.

## Plugin API notes

- Use `CreateDockWidgetPluginGuiAsync`. The non-Async form is deprecated.
- `PluginManager():CreatePlugin()` gives a working Plugin for tests, but its settings do not persist, so keep an in-memory fallback.
- A modal waiting on `done:Wait()` never resumes if the widget is destroyed. Fire the result with nil on `Destroying`.
- Properties-window edits inside a KeyframeSequence fire nothing unless you listen to that sequence's descendants. Wiring all 23,000 poses of a cutscene costs about 54 ms. Watch the selected clip lazily.
- Undo does not restore a runtime install's previous script sources. Keep the previous version in order to reinstall it.
