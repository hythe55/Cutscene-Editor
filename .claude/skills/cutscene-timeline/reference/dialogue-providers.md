# Dialogue providers

The timeline stores what is said. Each game draws it its own way through a provider module.

## Registration

Set attributes on the `ReplicatedStorage.Cutscenes` Folder:

- `DialogueModule`: path to a ModuleScript, for example `ReplicatedStorage.DialogueBox`.
- `DialogueGui` (optional): path to a ScreenGui template, for example `StarterGui.DialogueUI`.
- `RuntimePath` (optional): where the game keeps its Timeline runtime.

Resolution order: `options.DialogueBox` passed to `Timeline.new`, then the registered module (`.new({ GuiParent, Gui = clone of DialogueGui, Preview })`), then `Timeline/Fallback/DialogueBox.luau`. The plugin preview runs the same resolution on fresh clones under CoreGui with `Preview = true`.

## Module shape

```lua
Provider.new(options) -> box            -- options = { Gui?, GuiParent, Preview }
Provider.ReadingTime(text) -> seconds   -- optional; typing plus hold time
Provider.Moods -> { "Normal", ... }     -- optional; the plugin's mood dropdown
Provider.Fields -> { schema fields }    -- optional; stored on clips as X_<Name>, passed as line.Extra

box:Open()  box:Close()  box:Destroy()
box:Say(line) -> handle                 -- handle.Done, handle.Finished, handle:Complete(), handle.StartDelay?
box:Render(line, visibleCharacters)     -- draw a line at a typing point, no animation (scrubbing)
box:VisibleCharacters(line, elapsed)    -- optional; the provider's own typewriter rule

line = { Speaker = { Id, Name, UserId?, PortraitModel?, PortraitJoint?, Color? }, Text, TypeSpeed?, Mood?, Blips?, Extra }
```

Speaker tokens such as `{Hero}` in Text resolve to the player in that role. A speaker with `UserId` gets a headshot, and an actor gets a ViewportFrame portrait framed on `PortraitJoint`.

## Edge cases

- **Reading time must include the start delay.** Typing starts some time after `Say`: 0.45 s after the box opens, 0.22 s after a speaker swap, and 0 for the same speaker in one game's box. Clips sized without it lose hold time. Expose it as `handle.StartDelay`.
- **Scrub must equal live.** The track used 40 cps while the box typed at 30 cps with punctuation pauses. Implement `VisibleCharacters(line, elapsed)` in the provider so both use one rule.
- **Overlaps.** When lines overlap, the active line with the latest Start owns the box, whatever the seek order or lane order.
- **Chains.** Keep the box open across gaps of 0.35 s or less, across all Dialogue tracks. A seek into a chain gap shows the held line.
- **Late entry.** Entering a line up to about 0.25 s late should still play it live (blips, shake). After that, fall back to Render.
- **Never cap the text clock.** A 0.1 s delta cap made the box fall behind the timeline after a hitch.
- **Rapid speaker swaps.** A to B to A within the swap-out animation left a 2.5 px portrait and an invisible name for every later line. Test 10 `Say` calls in one frame, and reset the swap-in state when returning to the current speaker.
- **Stop and Pause.** Stop closes the box at once and must not reopen a line that starts at t=0. Pause freezes the frame, switching a typing line to Render at its current point.
- **Edit mode looks like a client.** `RunService:IsClient()` is true and `Players.LocalPlayer` is set in Studio edit mode. Gate runtime-only lookups on `RunService:IsRunning()`, and never `WaitForChild` in a provider's constructor (it blocked the preview for 10 to 20 s).
- **Viewport portraits** of skinned rigs are expensive. Throttle portrait animation to about 30 Hz, skip UI writes when nothing moves, and strip tags from the portrait clone.
- **Draw order.** Put the box above overlays (DisplayOrder 100, overlays 50 to 99), and check the order in a capture.
- **Talk.** Automatic mouth motion follows `TalkJoints` and stops when `VisibleCharacters` reaches the full line. Turn it off with `TalkJoints = ""` when the rig's mouth does not read well. Author special mouth moves (a burp) as their own Animation clip on a higher-Order track.
