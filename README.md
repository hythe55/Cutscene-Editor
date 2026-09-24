# CutsceneEditor

A Studio plugin for block-timeline cutscenes, plus the runtime that plays them in game and in the plugin preview. The remote is `github.com/hythe55/Cutscene-Editor`, branch `main`.

## Using the editor

### Install

1. Run `node build.js --install`. It writes `%LOCALAPPDATA%\Roblox\Plugins\CutsceneEditor.rbxmx`.
2. Studio picks the file up without a restart: the output shows `Detected add/change: user_CutsceneEditor.rbxmx; loading/reloading the plugin now!`. Reinstalling reloads it the same way.
3. The Plugins tab gets a **Cutscenes** toolbar with two buttons. **Cutscene Editor** opens and closes the editor window. **Reload** rebuilds the editor from fresh module copies; if a module fails to load, the window shows the error text instead.

### Open a cutscene

- A cutscene is a Folder under `ReplicatedStorage.Cutscenes` with the attribute `Timeline = true`, holding `Actors` and `Tracks` (the data format is in SPEC §5).
- The editor reopens the last cutscene you had open. The name button at the left of the toolbar lists every cutscene in the place and has **New cutscene…** and **Close cutscene**.
- In a place with no cutscenes, the window only offers **Create cutscene**.

### Edit on the timeline

- Each track is a 30 px lane under its actor's header. Collapse an actor with its header arrow. Each lane header has Mute (skip the track in previews and in game) and Lock (refuse edits) buttons, and its menus add tracks and actors, rename and delete.
- Click a block to select it. Shift adds, Ctrl toggles, and dragging on empty space draws a selection box.
- Drags are press-and-hold: press on a block, key or the playhead, move, and let go. A press that does not move is a click. Esc cancels a drag in progress.
- Drag a block to move it. Drag it up or down to move it to another track of the same kind.
- Drag a block's edge to retime it. Animation, Camera and Move clips change Speed; hold Shift to trim instead (Animation trims move ClipOffset, Sound trims move StartOffset). On looped animations it is the other way round: an edge drag adds or removes cycles and Shift changes Speed.
- Drag the small handle at the top corners of a selected block to change FadeIn or FadeOut. Drag a key diamond to move that key.
- Snapping catches clip edges, keys, the playhead and 1/30 s frames. Hold Alt to drag freely, or turn **Snap** off.
- Ctrl+wheel zooms around the pointer, the wheel scrolls lanes, and Shift+wheel scrolls time. While you drag, the timeline scrolls when the pointer nears its edge.
- Right-click a block for add, delete, duplicate, split at playhead, rename, set camera key from view, and select in Explorer.
- Double-click an Animation block to open the **Pose** tab, or a Camera or Move block to open the **Keys** tab.
- Keys: Space plays or pauses, Delete deletes, Ctrl+D duplicates, S splits at the playhead, Ctrl+A selects all, Home and End jump, Left and Right step one frame (Shift: one second), F frames the selection, Esc cancels a drag or clears the selection, and C toggles the camera lock. Shortcuts are ignored while you type in a text box.
- Every action is one undo step, so Ctrl+Z undoes the last move, retime, key drag, pose change or range edit, and Ctrl+Y redoes it. Moving the playhead and scrolling are not undo steps. Locked tracks refuse edits.
- Animation track headers have an arrow that expands the track into body-part groups (Body, Head, Left Arm, Left Hand, Right Arm, Right Hand, legs, Cloth, Other), and each group expands into its joints. Their rows show that group's or joint's keys as diamonds.
  - Click a diamond to select it, move the playhead there and pick that joint in the Pose tab. Double-click opens the Pose tab.
  - Drag a diamond to move only those joints' keys in time. Delete removes them.
- A dialogue line shorter than its reading time gets a red stripe and a "!" badge. Hover it to see the time it needs.

### Inspector and Script panel

- The **Inspector** tab shows the selected clip, or else the selected track, actor or cutscene. Fields commit on Enter or when they lose focus. Number fields also scrub when you drag them.
- Sound clips can play their part of the sound and pick a replacement from `ServerStorage.CutsceneAssets.Sounds`. VFX, prop and actor templates can be replaced from the library, selected in the Explorer, or burst in the viewport.
- Animation clips show their export status, the Animation id, **Mark as exported**, **Smooth keys**, and their keyframe list (click a keyframe to jump there).
- Dialogue clips have the speaker, the text with token buttons such as `{Player1}`, the mood, the type speed, the provider's extra fields (stored as `X_` attributes) and **Fit to reading time**.
- The **Script** tab lists every dialogue line in time order. Edit a line in place, click a row to jump there, click its duration badge to fit it to its reading time, use **Add line** after the selected line, and **Auto-fit** for all lines. The **Ripple** menu chooses whether a longer line pushes later lines on its lane, every later clip, or nothing.

### Preview

- Press Play or Space, or drag the playhead in the ruler (or anywhere with the middle mouse button). The preview plays the real runtime on copies of the actors, with stand-in players in the first tagged chairs (the cutscene's `ChairTag`), or in a row in front of the scene. The provider menu sets how many stand-ins sit down.
- Sounds and VFX play only while playing. Scrubbing updates rigs, props, the camera, overlays, post effects and the dialogue box at once.
- **Stop** removes every preview copy, unhides the originals and puts the camera back.
- You can edit while the preview is paused; it rebuilds after each edit. Pause before editing while it plays.
- The preview does not add undo steps. If you change something else in the place while it runs, the preview notices it (property changes, added or removed instances, attribute edits on the selection, edits to the cutscene outside the editor) and keeps it as one "Cutscene preview" undo step when it stops. A change it cannot see is undone when the preview stops, so stop the preview before other work. Stopping a preview clears Studio's redo list.

### Camera lock

- The eye button (or C) makes the viewport look through the cutscene camera, at its FOV, while you play or scrub.
- In a gap between camera clips the view holds the last shot and the status bar shows a "Gameplay camera" badge.
- Turning the lock off or stopping the preview restores your own camera exactly. Moving the camera yourself while locked turns the lock off, so the editor never fights you.

### Keys tab (Camera, Move and Attach clips)

- The viewport shows each key, the path between keys and camera frustums. Drag the rings or arrows on the selected key; the drag becomes one undo step when you let go.
- Camera clips: **Add key from view at playhead**, **View through key** and **Update key from view**. With the lock on, "from view" uses the cutscene camera you are looking through.
- Move clips: **Add key from actor's current pivot** and **Select actor** (both use the preview copy).
- Attach clips: drag the offset, **Offset from prop's pivot** and **Reset offset**.

### Fixing a pose (Pose tab)

1. Double-click the Animation block, or select it and open the **Pose** tab. The preview starts so you can see the rig.
2. Put the playhead on a keyframe: use the keyframe strip or the previous and next buttons.
3. Pick a joint: click the rig in the viewport or use the joint dropdown. The parent button walks up the chain.
4. Drag the rings to rotate (or switch to **Move** for the arrows), or use the nudge buttons: 1°, 5° or 15° in Rotate mode, and 0.1, 0.5 or 1.5 studs in Move mode.
5. **Key pose at playhead** adds a keyframe holding the current pose. **Copy pose** and **Paste pose** move a whole pose, **Reset joint** returns a joint to rest, and **Delete keyframe** removes one.
6. Key roles control smooth playback: **Pass** keys let the motion flow through, **Stop** keys ease to rest, and **Snap** keeps a deliberate In, Out or Constant snap. **Auto** picks roles from the motion. The role applies to this joint or the whole keyframe.

7. **Edit: This key / Range** decides where a correction goes. With **Range**, the same change also goes onto this joint's keys from **Before** seconds before the playhead to **After** seconds after it, then fades out over **Soft** seconds. Use it to fix a joint across a whole move in one go.

Every change is one undo step, including a range edit, and the preview re-samples right away.

### Dialogue providers

- A game draws dialogue its own way through a provider module (SPEC §7a). Register it with attributes on `ReplicatedStorage.Cutscenes`: `DialogueModule` (a module path) and optionally `DialogueGui` (a ScreenGui template path).
- The provider button on the toolbar shows which provider the preview uses, for example "Game: DialogueBox", "Built-in fallback" or "Dialogue: error" (shorter in a narrow window). Its menu can pick a game module, switch back to the built-in fallback, select the module in the Explorer and set the number of stand-in players. If the game module fails, the preview uses the fallback and the menu shows the real error.

### Runtime install

- Games play cutscenes with the Timeline runtime bundled in the plugin. The **Runtime** button shows the version found at the path in the `RuntimePath` attribute of `ReplicatedStorage.Cutscenes` (default `ReplicatedStorage.Timeline`) next to the bundled version.
- The menu installs, updates or reinstalls the runtime in one undo step, and can change the location. If the place has a newer runtime than the plugin, it offers a red "Downgrade to …" behind a confirmation instead.
- Places using Script Sync get the copy written to disk.

### Export animations

1. Press **Export**. One window lists everything that needs uploading: clips never uploaded and clips changed since their upload, plus each animated actor's Idle. Clips with identical keyframes share one upload. "All cutscenes in this place" widens the list to every cutscene.
2. Under **Upload to**, pick where the animations go. It starts on the experience's owner (for a group game, that group), which is what the game needs: animations owned by anyone else will not play in it. You can also pick your account or type another group's id. The choice is remembered.
3. Press **Upload**. Each animation uploads straight to Roblox (Smooth clips as a 30 fps bake), and its new id is saved on every clip that uses it, one undo step per upload. **Stop** ends the queue after the current upload.
4. A summary lists what was uploaded and linked, what failed and why, and which actors still play from keyframes. An actor uses uploaded animations only when all its clips and its Idle are uploaded and unchanged.

Direct uploads use `AssetService:CreateAssetAsync`, which works only in locally installed plugins and only with a Studio beta turned on: **File > Beta Features > CreateAssetAsync Lua API**, then restart Studio. Without it, Export says so and offers to upload by hand instead. Roblox's upload window then opens for each animation, and you paste the id it shows.

You can also type an id into an Animation clip and press **Mark as exported**.

### Where keyframes live

- Keyframes are kept in `ServerStorage.CutsceneSources.<Cutscene>`, so clients do not download them once they are exported. Each Animation clip stores `SourceId` and `ContentHash`.
- A clip also keeps a `Keyframes` copy for clients while its actor still plays from keyframes in game. The copies go away only when every Animation clip of that actor and its Idle are exported and unchanged. They come back as soon as one of them changes, because one changed clip makes the whole actor play from keyframes again.
- An actor's Idle works the same way. Its keyframes live in `CutsceneSources`, and once the actor is fully exported the `Idle` under the actor is an empty stub that only holds its `AnimationId`, `ExportedHash`, `SourceId` and `ContentHash`.
- The editor creates and updates all of this itself. Opening a cutscene tidies anything left over (for example keyframes from before this system, or an Idle that is already exported) in one "Move keyframes to ServerStorage" undo step.
- Game code that reads an Idle directly should use `Timeline.Sources.Keyframes(idle)`, and play `idle:GetAttribute("AnimationId")` through the Animator when that returns nil.

## Layout

- `src/Plugin/Main.server.luau` is the plugin entry Script.
- `src/Editor/` holds the editor modules. `src/Editor/init.luau` becomes the `Editor` ModuleScript.
- `src/Runtime/Timeline/` is the canonical timeline runtime (version in `Version.luau`). Edit the runtime here and nowhere else.

## Built model

`node build.js` writes `dist/CutsceneEditor.rbxmx`:

```
Folder CutsceneEditor
  Script Main              src/Plugin/Main.server.luau
  ModuleScript Editor      src/Editor/init.luau and its children
  Folder Runtime
    ModuleScript Timeline  src/Runtime/Timeline/init.luau and its children
```

Main reaches the runtime as `script.Parent.Runtime.Timeline` and the editor as `script.Parent.Editor`.

File names map the same way Script Sync maps them:

- `.luau` is a ModuleScript, `.server.luau` a Script, and `.client.luau` or `.local.luau` a LocalScript.
- A folder with an `init` script becomes that script, with the other files as children. A folder without one becomes a Folder.
- Two children with the same name fail the build.

Sources are read as UTF-8, and CRLF or lone CR line endings become LF, as Studio stores them, so files saved by Windows editors build too. They go into CDATA sections, and any `]]>` in a source is split across two sections. Each referent is the MD5 of the instance path, so the same tree always produces the same file. Every build parses its own output back and compares names, classes and sources before it writes anything.

## Commands

| Command | What it does |
|---|---|
| `node build.js` | Builds and verifies `dist/CutsceneEditor.rbxmx`. |
| `node build.js --install` | Builds, then copies the model to `%LOCALAPPDATA%\Roblox\Plugins\CutsceneEditor.rbxmx`. `--plugins-dir <dir>` installs somewhere else, for tests. |
| `node build.js --sync-runtime <dir>` | Mirrors `src/Runtime/Timeline` into a game's Timeline folder. |
| `node build.js --dev-mirror` | Mirrors `src/Editor` and `src/Runtime/Timeline` into `Schooltime\ServerStorage\CutsceneEditorDev\Editor` and `...\CutsceneEditorDev\Runtime\Timeline`. |
| `node build.js --dev-mirror-clean` | Deletes every `.luau` file under `CutsceneEditorDev`, then the empty folders. |
| `node build.js --install-skill [dir]` | Copies `skill/cutscene-timeline` into `~/.claude/skills/cutscene-timeline` (or `dir`), so Claude Code uses it in every project. Every normal build also mirrors it into `.claude/skills/cutscene-timeline` in this repo. |
| `node build.js --test-snippet` | Writes `dist/mount-snippet.luau`, a chunk that rebuilds the model under an `Archivable=false` `ServerStorage.CutsceneEditorMount` and returns it. Each source is a Luau long string whose level is raised until nothing inside, including a trailing `]` or `]=`, can close it early. Destroy the folder afterwards. |

## Changing the runtime

1. Edit `src/Runtime/Timeline`.
2. Run `node build.js --sync-runtime "C:\Users\caden\OneDrive\Desktop\Schooltime\ReplicatedStorage\Classes\Timeline"`. The sync writes only the files that changed and deletes `.luau` files the source no longer has. It never touches other files. It refuses a non-empty folder without `init.luau` unless you pass `--force`.
3. Script Sync pushes the files into Studio.

## Testing in Studio without installing

- `--dev-mirror` turns the editor and runtime into ModuleScripts under `ServerStorage.CutsceneEditorDev`. The folder is in the Schooltime `.gitignore`. Require clones, for example `require(game.ServerStorage.CutsceneEditorDev.Runtime.Timeline:Clone())`.
- Editor writes are ChangeHistory recordings, and a recording cannot start while any `execute_luau` call is running, including one that is only waiting in `task.wait`. Run writes and undos in a `task.delay` thread and poll for the result with calls that return at once. Every `execute_luau` call also clears Studio's redo list.
- The MCP Luau VM caches requires across calls and agents. Its cached `ReplicatedStorage.Classes.DialogueBox` and `ReplicatedStorage.Settings.DialogueSettings` are stale stage-1 builds. The old DialogueBox throws when `.new` gets an options table, and the old settings still have `DisplayOrder = 10`. Require clones, and copy fresh settings values into the cached table when a test needs them.

## Skill

`skill/cutscene-timeline` is a Claude Code skill: the data format, the runtime API, export, dialogue providers, animation authoring, and the Studio and MCP edge cases found while building a full cutscene with it, plus helper scripts. The raw notes it was distilled from stay local (`skill/notes/` is ignored).

## Runtime contract (0.5.3)

- **Prewarm.** In game, `Timeline.new` loads every uploaded animation track and preloads animations and sound templates (`ContentProvider:PreloadAsync`) straight away, and sets `timeline.Loaded` when that finishes. An animation or sound that still loads after its start time jumps to the right position on its first loaded frame.
- **Player visibility.** While a timeline plays in game, player actors are kept at their cutscene visibility every frame after the camera update. Roblox's first-person camera would otherwise hide the local character.
- **Props put down from a hand** (Attach with `OnExit = "Stay"`) stay where the hand last held them in game. The pose is only recomputed from keyframes in the preview, because clients do not have the keyframes of uploaded clips.

- **Idle stubs.** When an actor is fully exported, its `Idle` KeyframeSequence has no keyframes. `Timeline.Sources.Keyframes(idle)` returns the ServerStorage source (server and plugin) or nil (client). The runtime then plays the Idle's `AnimationId` through the Animator. `Sources.IsExported(idle)` uses the stored `ContentHash`.

- **Players.** `Timeline.new` takes `Players = { userId, ... }`, the players taking part in order. It fills Role actors that `Roles` leaves empty, and Group actors use all of them. The old name `Students` still works when `Players` is absent. Role ids are any string. The editor suggests Player1 to Player4, and existing ids such as Student1 keep working. The Group attribute's value is not read, so old `Group = "Students"` actors play unchanged.

- **Keyframe sources.** `Timeline.Sources` finds a clip's keyframes: `ServerStorage.CutsceneSources` by `SourceId` first, then the clip's `Keyframes` replica. An actor uses uploaded animations only when every Animation clip and its Idle have `AnimationId` and `ExportedHash == ContentHash`. An exported clip with no keyframes on the client plays through the Animator even when the rest of its actor plays from keyframes.

- **Smooth keys.** A KeyframeSequence with the attribute `Interpolation = "Smooth"` is sampled with velocity-continuous curves: Linear keys pass through, CubicV2 InOut keys and holds stop, and In, Out, Constant, Elastic and Bounce keys keep their native easing. Without the attribute, sampling matches the engine exactly. `Timeline.Bake(sequence, 30)` returns dense Linear keys that reproduce the curve, and export uploads that bake. `Timeline.ComputeHash` includes the attribute.

- **Halt hook.** A track module may export `Kind.Halt(state, ctx, reason)`, where `reason` is `"Stop"` or `"Pause"`. The core calls it on every prepared clip before it exits clips on Stop or Pause.
  - Dialogue: Stop closes the box at once. Stop then shows the t=0 frame with `ctx.Stopping` set, and the Dialogue track does not reopen the box for a line that starts at 0. The next seek or Play shows that line again.
  - Dialogue: Pause freezes the frame. A line in the middle of typing switches to Render at the current typing point, and a line held in a chain gap stays on screen. Resuming continues from there.
  - Sound and VFX stop and remove everything at once, including lingering particles.
- **Dialogue typing.**
  - A provider box may implement `box:VisibleCharacters(line, elapsed)`, where `elapsed` counts from the moment `Say` would be called. It may also set `handle.StartDelay`.
  - After `Say`, the track copies `handle.StartDelay` into `line.StartDelay`.
  - When the track renders a line because of a seek, it sets `line.PreviousSpeaker` if the line follows another one while the box stays open. The provider can then predict its own start delay.
  - Chapter 2's box and `Fallback/DialogueBox` implement all of this. Scrubbed typing matches live typing.
  - Chaining (keeping the box open across a gap of 0.35 s or less) works across all Dialogue tracks, not only within one track. `Lines.luau` holds the chain rules, which the Dialogue track and `Speech` share.
- **Scrub equals live.**
  - A seek into a chain gap shows the held line, as live play does.
  - When lines overlap, the active line with the latest Start owns the box. This holds whatever the seek order or the lane order.
  - Mouth timing while scrubbing ends when the provider's `VisibleCharacters` reaches the full line, using the same chained start delay (Chapter 2: 0.45 s fresh, 0 s for the same speaker, 0.22 s for a new speaker).
- **Draw order.** The dialogue box uses DisplayOrder 100. Overlays use 50 + track Order, capped at 99.
- **Spline keys.** A key with no `Easing` attribute is Linear, in `Spline.ReadKeys` and in `Schema.KeyFields`.
- **Tags.** `Util/Copy.luau` makes every runtime clone (actors, VFX, sounds, the dialogue GUI) and strips all CollectionService tags from the root and its descendants before the clone is parented. The Tag resolver skips instances that have an `Archivable=false` ancestor. It prefers Workspace, then ReplicatedStorage (for example `ReplicatedStorage.CutsceneActors`), then anywhere else.
- **Module split.** `init.luau` holds the public API. `Phases.luau` prepares clips and dispatches them each frame. `Clock.luau` owns the connections and the clock.
