# Studio, MCP and Script Sync gotchas

## Roblox Studio MCP (`execute_luau`)

- **Environment.** Code runs at plugin security with `plugin == nil`, and only `shared` and `_G` persist. Some property reads fail ("lacking capability RobloxScript"), so pcall reads you are unsure of. Load long helper files with `loadstring(source)()`.
- **Stale state.** `_G`, the require cache and signal connections persist across calls and across agents. `require` returns the cached table even after Source changes. Always `require(module:Clone())`, and keep your state under a unique `_G.<Label>` key.
- **Error text.** Errors arrive wrapped, as `...ExecuteLuauTool:66: ...CommandExecution:54: <real error>`. Read after the last `:54:`. A module that fails while loading only says "Requested module experienced an error while loading", so get the real message with `loadstring` or from the console output.
- **Never `WaitForChild`.** A miss hangs the call for about 2 minutes. Long waits and awaiting `TextChannel:SendAsync` time out. Use FindFirstChild, `task.spawn` anything that yields, and poll with calls that return at once.
- **Recordings.** Each call is wrapped in its own ChangeHistory recording ("Assistant N"). Inside a call, `TryBeginRecording` returns nil. No recording can start while *any* call is running, even one that only waits. Each call also clears Studio's redo list, so redo cannot be tested through the MCP. Run undo tests from `task.delay` and poll. Destroying handlers run after the call returns.
- **Camera type.** The MCP resets `Camera.CameraType` after each call, even during playtests. Set it from a deferred thread or every frame, and do not blame the cutscene for flips seen while polling.
- **Screen captures:**
  - They skip CoreGui ScreenGuis and AlwaysOnTop adornments.
  - They include StarterGui dev leftovers.
  - They work with the window covered, and use the window's aspect rather than 16:9.
  - They can leave the edit camera pointing elsewhere. Record CFrame, Focus and FOV before capturing, and restore them afterwards.
  - They work during playtests, but the frame arrives later than the time you polled. Read the live state in the same batch to label the frame.
- **Studio ids change** when a place is reopened or Script Sync reconnects. On "Place is not open" or "studio_id is not connected", call `list_roblox_studios` and pick by name.
- **Transient errors.** "Target is not reachable (createExecuteLuauBridge_loadCodeAsync)" means the call did not run. Check a `_G` marker, then retry.
- **Play mode.** "Edit datamodel is not available in Play mode" means a playtest is running. During a playtest, target the Server or Client datamodel.
- **What agents cannot check:** the MCP mouse tool works only in play mode, `http_get` refuses untrusted URLs, HttpService may be off, and no agent can hear audio. Drive UI handlers from code, and put real mouse, upload and listening checks on the user's checklist.

## Script Sync

- **Mapping.** `.luau` is a ModuleScript. `.server.luau`, `.client.luau` and `.legacy.luau` are Scripts with that RunContext, and `.local.luau` is a LocalScript. `Folder/init.luau` makes the folder that script. Non-script children survive but never reach disk. Attributes and tags on synced scripts are dropped.
- **It is two-way.** Scripts a test creates under a synced path get written back to disk. Keep harness clones unparented, or under non-synced `Archivable=false` containers.
- **It can stop silently.** For 35 minutes new ServerStorage files never reached Studio while ReplicatedStorage still synced, and agents tested stale code. Before testing changed code, compare `#Source` of one changed module with the file (normalise CRLF). If sync is down, use `scripts/push_to_studio.py --paths ...` and then `--verify`. Disk stays the source of truth, and the user reconnects sync choosing the disk version.

## Edit-mode engine behaviour

- PreSimulation, PostSimulation, Stepped and PreAnimation do not fire in edit mode. Heartbeat and PreRender do. Rendering drops to about 14 fps when Studio is unfocused.
- `Bone.Transform` and `LocalTransparencyModifier` render in edit mode and are not saved. Changes under an `Archivable=false` root or in CoreGui are not recorded in undo.
- `PivotTo` adds float drift, and a Model without a PrimaryPart keeps the WorldPivot that PivotTo gave it. Snapshot part CFrames plus the pivot, restore with `workspace:BulkMoveTo`, then reassign WorldPivot.
- Clones keep CollectionService tags. `Clone()` on an `Archivable=false` instance returns nil. Clone through one helper that toggles Archivable, handles nil and strips tags.
- `RunService:IsClient()` is true in edit mode with `Players.LocalPlayer` set.
- Asset loading in edit mode proves little. Sounds report `IsLoaded` in Edit while the game logs "not approved for the requester". Watch the playtest console for "Failed to load sound".
- Moving instances between places works with `SerializationService:SerializeInstancesAsync` to a buffer, base64 in Luau, then `DeserializeInstancesAsync`. Bundle related instances in one call so references survive, and chunk with a checksum (about 4,000 characters per call).

## Game startup traps

- One `WaitForChild` at require time hung every service that required it, on server and client. A sequential `Init` then delays everything after it. Never yield at require.
- Fixing a startup hang can wake dormant systems. An NPC tagger turned two cutscene rigs into chasers. Audit tags on every actor first.
- Server end-of-cutscene logic:
  - Do not wait for Finished from every client. Schedule world-after state on the server at StartAt + length.
  - Put a RunId in the payload and require it in Finished.
  - Always run an idempotent Finish, even on error paths.
- A chat command made with a TextChatCommand at runtime replicates, and any player can trigger it. Resolve the player from `origin.UserId`, authorise with `RunService:IsStudio()` or an allowlist, and debounce while a cutscene runs.
- Other game code fights the camera and controls, for example a shake bound at render priority 201, an FOV tween, or a crawl re-enabling controls. Write the camera at priority 200, and set FOV every frame.

## Measuring

- Angle checks bottom out near 0.03 degrees because CFrames are float32. Use thresholds of 0.05 degrees or more.
- Avoid sampling exactly at a Constant InOut midpoint.
- When comparing live playback with scrubbing, record the time the frame was drawn (the render phase), not a `TimePosition` read later.
- Velocity checks at 60 fps hid or faked key jumps through extrapolation curvature. Use 240 fps with a two-frame window.
