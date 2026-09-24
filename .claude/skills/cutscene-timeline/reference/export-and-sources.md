# Export, sources and uploaded playback

## Where keyframes live

- Every Animation clip's keyframes live in `ServerStorage.CutsceneSources.<Cutscene>.<SourceId>`, a KeyframeSequence. The clip stores `SourceId` and `ContentHash` (the hash of that sequence).
- Clients cannot see ServerStorage. A clip also keeps a `Keyframes` child, a replica, for as long as its actor may play from keyframes in game.
- The replica rule works **per actor**. Replicas are removed only when every Animation clip of the actor and the actor's Idle are exported and current. When any of them changes, all of that actor's replicas come back.
- Why: the runtime decides uploaded mode per actor, so one stale clip sends every clip of that actor back to keyframes. A per-clip rule would leave the exported clips with no keyframes on the client, and they would silently not play.
- **Idle loops follow the same rule.** The Idle KeyframeSequence stays under the actor as the owner of `AnimationId`, `ExportedHash`, `SourceId` and `ContentHash`. Its keyframes are copied to a source in CutsceneSources, and they are stripped (leaving an empty stub) while the actor is fully exported. Anything that samples an Idle directly, such as a game's pre-cutscene idle loop, must use `Sources.Keyframes(idle)` and fall back to playing the AnimationId, or the rig stands in its rest pose.
- The runtime has a fallback for data edited outside the plugin. An exported clip with no keyframes on the client plays through the Animator, even when the rest of its actor is on keyframes.

Read keyframes with `Timeline.Sources.Keyframes(clip)` (source first, then the replica) or `Document:GetSequence(clip)` in the editor. Never read `clip.Keyframes` directly.

## When the game uses AnimationIds

An actor uses `Animator:LoadAnimation` only when all of this holds:

- The game is running. The preview and edit mode always sample keyframes.
- Every Animation clip of the actor has a non-empty `AnimationId` and `ExportedHash == ContentHash`.
- The actor's Idle, if any, has `AnimationId` and `ExportedHash == Timeline.ComputeHash(idle)`.

Otherwise the actor plays from keyframes (the replicas). The mode is decided after all clips are prepared, never earlier.

## Export flow (plugin)

1. Collect the clips that need uploading: never exported, or `ExportedHash ~= ContentHash`. Include every animated actor's Idle. Clips with identical content share one upload, keyed by hash.
2. One window shows the queue and **Upload to**, which defaults to the experience owner (`game.CreatorType`, `game.CreatorId`). The user can instead pick their own account (`StudioService:GetUserId()`) or enter a group id.
3. Each item uploads with `AssetService:CreateAssetAsync(keyframeSequence, Enum.AssetType.Animation, { Name, Description, CreatorType, CreatorId })`, which returns `Enum.CreateAssetResult.Success` and the new asset id. A clip with `Interpolation = "Smooth"` uploads `Timeline.Bake(sequence, 30)` instead, because the engine ignores Smooth.
4. The id and the hash are written to every clip sharing that upload in one undo step. That write re-evaluates the actor's replicas.
5. A summary lists uploaded, failed and not reached items, and which actors still play from keyframes.

## Edge cases

- **Upload owner.** Animations must be uploaded to the group or user that owns the experience, or they will not play in game. Say so in the upload prompt.
- **CreateAssetAsync needs a beta and a local plugin.** It works only from locally installed plugins (or the command bar), and only with File > Beta Features > "CreateAssetAsync Lua API" on. Without it, the call warns "not available yet" instead of uploading. Detect that and fall back.
- **Animation is not in the documented type list** (Model, Plugin, Mesh, Image), but uploading a KeyframeSequence as `Enum.AssetType.Animation` works in practice (2026). Treat a failure as a possible API change and keep the by-hand fallback.
- **`plugin:SaveSelectedToRoblox()` does not wait and returns nothing.** It opens Roblox's upload window and returns at once, so a prompt shown right after it asks for an id before the user has uploaded anything. The by-hand fallback must say the window is open, wait for the pasted id, and offer to reopen the window.
- **Result handling.** `PermissionDenied` means the user's role cannot create assets for that group, so stop the queue. Retry after a pause when the message mentions too many requests. Space uploads a little apart.
- **Agents cannot test a real upload** without publishing to the user's account. Stub `Create`, `Save` and `Ask` in tests, and put one real export on the user's checklist.
- **Downloading.** `KeyframeSequenceProvider:GetKeyframeSequenceAsync` returned empty sequences after the first call. `AnimationClipProvider:GetAnimationClipAsync` works every time.
- **Registering clips in edit mode.** `RegisterActiveAnimationClip` works only in Solo play. `RegisterAnimationClip` or `KeyframeSequenceProvider:RegisterKeyframeSequence` work everywhere and give the same hash on server and client.
- **Smooth is not an engine feature.** Animator checks and uploads of a Smooth clip do not match the game. Sample Smooth clips through the runtime, and upload the bake. The bake matched the runtime within 0.3 degrees.
- **Hashing cost.** Hashing every clip on every change took about 100 ms at 200 clips and 400 ms at 300 clips. Cache hashes per KeyframeSequence and invalidate on change.
- **Pause before storing ids.** A running preview rebuilds on each write and can hold stale state.
- **Mark as exported** lets a user paste an id without uploading. It stores the current `ContentHash` as `ExportedHash`.
- **Legacy clips** (a `Keyframes` child, no `SourceId`) are migrated the first time they are edited. Migration moves the original sequence into CutsceneSources instead of cloning it, so references to its Keyframes and Poses stay valid inside the same edit.
- **Duplicate and split** fork the source (a new SourceId). Two clips must never share one source, or an edit to one changes the other.
