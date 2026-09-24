# Runtime API

The runtime is a ModuleScript tree named `Timeline`. Games install a copy at the path in `ReplicatedStorage.Cutscenes`'s `RuntimePath` attribute (default `ReplicatedStorage.Timeline`). The plugin bundles the same code and can install or update it.

## Public API

```lua
local Timeline = require(path.to.Timeline)

local timeline = Timeline.new(folder, {
	Roles = { Hero = userId, ... },      -- role id (any string) -> userId; unfilled roles take players from Students in order
	Students = { userId, ... },          -- the players taking part, in order; Group actors use it (the name is historical)
	StartAt = serverTime,                -- in game, time = workspace:GetServerTimeNow() - StartAt
	Preview = false,                     -- true in the plugin (edit mode)
	DialogueBox = box,                   -- wins over the registered provider
	GuiParent = instance,                -- Overlay ScreenGuis: PlayerGui in game, CoreGui in preview
	Container = instance,                -- parent for clones and effects; Archivable=false in preview
})

timeline:OnEvent(name, function(phase, data) end)
timeline:Play() timeline:Pause() timeline:Seek(t) timeline:Stop() timeline:Destroy()
timeline:Wait() timeline:PlayAndWait()
timeline.TimePosition timeline.Length timeline.Playing timeline.Ended timeline.Context

Timeline.GetLength(folder)            -- same number on server and client
Timeline.GetServerEvents(folder)      -- Event clips with Side Server or Both
Timeline.ComputeHash(sequence)        -- content hash, includes the Interpolation attribute
Timeline.Bake(sequence, fps)          -- dense Linear copy of a Smooth sequence, for upload
Timeline.Sources                      -- Find, Replica, Keyframes, Hash, ContentHash, IsExported
Timeline.Schema  Timeline.Sampler  Timeline.Version  Timeline.FallbackDialogueBox
```

`Destroy()` must leave the world exactly as it was: clones destroyed, originals unhidden, camera, UI, HUD and effects restored.

## Track modules

`Timeline/Tracks/<Kind>.luau` returns:

```lua
Kind.Priority = number   -- Move 10, Animation 20, LookAt 30, rig apply 40, Attach 50, Visibility 55,
                         -- Property 60, Camera 70, PostFX 75, Overlay 80, Sound 85, VFX 90, Dialogue 95, Event 100
Kind.Seekable = boolean  -- false: exited on seek, re-entered only during forward play (Sound, VFX)
function Kind.Prepare(clip, props, track, ctx) return state end
function Kind.Enter(state, ctx) end
function Kind.Update(state, localTime, alpha, ctx) end
function Kind.Exit(state, ctx) end
function Kind.Destroy(state, ctx) end
function Kind.Halt(state, ctx, reason) end   -- optional; "Stop" or "Pause"
```

The `ctx` gives `GetActor`, `GetRig`, `GetJointCFrame`, `ResolveSpeaker`, `Dialogue`, `Track` (destroy on Destroy), `OnCleanup`, `Remember(instance, property)` (restore once), `FireEvent`, `ClaimCamera`, `ReleaseCamera`, `ActiveSpeaker`. For offline checks it also has `PoseAt(id, t)`, `PivotAt(id, t)` and `ProbeJointCFrame(id, joint, t)`, which compute from the data without playing.

## Stepping

- **In game.** Rigs are written on PreSimulation, after the Animator. PreAnimation fires first, so put back a recorded base pose there, and apply additive layers after the Animator. The camera binds at `Enum.RenderPriority.Camera.Value`, so a shake at 201 layers on top.
- **In edit mode.** PreSimulation, PostSimulation, Stepped and PreAnimation never fire. Use PreRender or Heartbeat, chosen with `RunService:IsRunning()`, and advance time with `os.clock()` deltas. PreRender drops to about 14 fps when Studio is unfocused, while Heartbeat stays at 60.

## Portability rules

- Require only descendants of `Timeline` and Roblox services. A game's Signal, Settings or UI module inside the runtime breaks every other game.
- The runtime carries its own `Util/Signal.luau` (pure Luau, deferred) and `Fallback/DialogueBox.luau`.
- Optional game objects, such as a `workspace.Sounds.SFX` SoundGroup, are used only if they exist, and never waited for.
- Relative requires fail from an unparented clone when they reach outside it. Tools that require a module through `:Clone()` need that module to use absolute service paths.

## Edge cases

- **Missing anchor.** When an anchor actor cannot be resolved, anchor-relative keys become world coordinates and the camera jumps near the origin. Hold the last resolved anchor, fall back to the previous shot, or leave the camera alone and warn once.
- **Path dependence.** Seek order must not matter. Pose the world at t=0 on construction. An Attach-only prop must return when seeking before its first clip. Stop inside a gap or at t=0 must not reopen a line that starts at 0. Test with random seek orders against a fresh timeline.
- **Transform read-back.** `Motor6D.Transform` never reads back bit-exact. Never detect "the Animator's value" by comparing with what you wrote. Record the base and write it back each frame, or LookAt compounds until the head spins.
- **Weak tables.** Instance keys in a weak-keyed table can be collected while the instance still exists. Keep restore bookkeeping in strong tables and clear it yourself.
- **Signals.** A BindableEvent-based signal copies arguments, loses metatables and leaks unless destroyed. Use a pure Luau signal and destroy it on Destroy.
- **Allocation.** Per-frame allocation adds up (5 KB per spline evaluation, 54 KB per frame on a heavy rig). Cache tangents, closures and rig lists, and register one cleanup per clip state.
- **Particle emitters.** Library VFX often ship Enabled with burst rates in the thousands. Disable emitters on clone, honour `EmitCount`, `EmitDelay` and `EmitDuration` attributes, and clamp `Rate * EmitScale` to 1000.
- **Draw order.** The dialogue box uses DisplayOrder 100, and overlays use 50 + track Order capped at 99. With every overlay at one value, a black fade can cover a title card.
- **Controls and HUD.** Hide ScreenGuis added during the cutscene too (watch `PlayerGui.ChildAdded`), and restore only what was on before.
