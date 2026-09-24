---
name: cutscene-timeline
description: Use when a task touches Roblox cutscenes built on the block-timeline system. That covers a Folder under ReplicatedStorage.Cutscenes with Timeline=true, the Timeline runtime (Timeline.new, Play, Seek, Bake, Sources), the Cutscene Editor Studio plugin or its CutsceneEditor repo, ServerStorage.CutsceneSources, and exporting or uploading cutscene animations. It also covers dialogue providers (DialogueModule, DialogueGui) and any job where you write KeyframeSequences, Poses, Bone or Motor6D transforms, camera shots or staging for a Roblox rig by code, including through the Roblox Studio MCP. Use it when an animation looks choppy or stops at keys, when the preview and in-game playback disagree, when a rig does not move, or when Studio undo, ChangeHistory, plugin drags or Script Sync misbehave.
---

# Cutscene timeline

A cutscene is data: a Folder of actors and tracks of timed clips. One runtime plays it in game and in the editor preview. The Studio plugin (repo `CutsceneEditor`) edits the data, previews it without touching the place, and exports animations. Most time goes into the edge cases below, not the happy path.

## Read first, by task

| Task | Read |
|---|---|
| Build or edit a timeline by script | `reference/data-format.md`, then `reference/staging-and-cameras.md` |
| Call the runtime from game code, or change the runtime | `reference/runtime-api.md` |
| Author or fix a KeyframeSequence, rig pose or IK | `reference/authoring-animation.md` and `scripts/RigKit.luau` |
| Export, upload, or "why does the game not use my AnimationId" | `reference/export-and-sources.md` |
| Hook a game's dialogue UI | `reference/dialogue-providers.md` |
| Change the plugin, or explain its UX | `reference/plugin.md` |
| Anything through the Studio MCP, Script Sync or ChangeHistory | `reference/studio-gotchas.md` |
| Short list of habits that saved time | `reference/tips.md` |

## Rules that prevent most bugs

1. **Edit the runtime in one place.** The canonical copy is `CutsceneEditor/src/Runtime/Timeline`. A game holds an installed copy, updated with `node build.js --sync-runtime <game Timeline folder>`. The runtime requires only its own descendants and Roblox services, never game modules.
2. **Keyframes live in ServerStorage.** An Animation clip points at `ServerStorage.CutsceneSources.<Cutscene>.<SourceId>`. The clip keeps a `Keyframes` replica for clients only while its actor still plays from keyframes. Read keyframes through `Timeline.Sources.Keyframes(clip)` or the editor's `Document:GetSequence(clip)`, never `clip.Keyframes` directly.
3. **An actor plays uploaded animations only when all of it is exported.** Every Animation clip of that actor and its Idle need `AnimationId` plus `ExportedHash == ContentHash`. One stale clip sends the whole actor back to keyframes.
4. **Translations are divided by model scale.** The Animator multiplies Pose positions by `Model:GetScale()`.
5. **Pose paths must mirror the rig.** Nest Poses exactly like the Bone or Motor6D tree, give ancestors Weight 0, and name the root Pose after the real root part. Anything else is silently ignored.
6. **Key every animated joint at t=0** and add an explicit hold key at the end. The engine forces a joint to identity before its first key and stops a non-looped track at its length.
7. **Do not ease every key.** CubicV2 InOut on every key makes a dead stop at each one, which reads as choppy. Key each bone group at its own extremes. Use `Interpolation = "Smooth"` with Linear pass keys and InOut stop keys, then run `scripts/stop_and_go.luau`.
8. **Deletes inside a recording use `Parent = nil`, never `Destroy()`.** A destroyed instance cannot come back on undo.
9. **Each user action is one ChangeHistory recording.** Moving the playhead is not an action. Do not hold a recording open across user edits, and do not cancel a recording that other edits might share.
10. **In MCP code, never use `WaitForChild`, always `require` a fresh `:Clone()`, and run undo tests from `task.delay`.** Every MCP call is its own recording and clears the redo list.
11. **Clones never keep CollectionService tags.** Strip tags before parenting, or taggers and actor resolvers grab the clone.
12. **Check from the real shot camera.** A gesture that looks fine from the planned angle can fill another shot. Sample cameras, contacts and hidden actors every frame at 30 fps or more, not only at keys.

## Scripts

- `scripts/RigKit.luau` poses skinned bone rigs in character space (natural motions, two-bone IK, buildKeyframeSequence, stepPreview). Load it with `loadstring` in execute_luau. The role table covers two rigs, so extend `ROLE_NAMES` for others.
- `scripts/stop_and_go.luau` finds keys where a bone moving through a key stops dead. The target is 0 hits outside deliberate snaps.
- `scripts/check_template.luau` is a read-only validation pass for one cutscene: structure, dialogue reading time, camera near-plane clearance, pose sanity and sources. Copy it and add scene-specific checks.
- `scripts/push_to_studio.py` pushes `.luau` files from disk into Studio through execute_luau when Script Sync is down, and verifies them.

## When something looks wrong

- **The rig does not move:** check the pose paths, the root pose name, a missing Animator (create one), AnimationConstraint joints on player rigs, and the edit-mode stepping signal (use PreRender or Heartbeat).
- **The preview is right but the game is wrong:** check whether the actor is in uploaded mode (`ExportedHash` stale?), whether the clip has `Interpolation = "Smooth"` (the engine ignores it, so export a bake), and whether a stale runtime copy is installed.
- **Something moved by a tiny amount:** remember `PivotTo` drift, Motor6D Transform read-back error and float32 CFrames. Compare with a tolerance of at least 1e-4 or 0.05 degrees.
- **Undo does the wrong thing:** look for a `Destroy()`, an `Archivable=false` ancestor, a second recording opened in the same frame, or an MCP call running while the recording should start.
