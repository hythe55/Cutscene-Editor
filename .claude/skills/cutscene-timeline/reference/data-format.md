# Timeline data format

`Timeline/Schema.luau` is the source of truth for every field, default and label. The plugin inspector is generated from it, so a new field goes there first.

## Layout

```
ReplicatedStorage.Cutscenes : Folder
  attrs: DialogueModule, DialogueGui, RuntimePath   (per-game registration, see dialogue-providers.md)
  <Name> : Folder                                    attrs: Timeline = true
    Actors : Folder
      <ActorId> : Configuration
        attrs: Source ("Tag"|"Template"|"Role"|"Group"), Tag, Role, Group, Mode ("Clone"|"Original"),
               DisplayName, Portrait ("Viewport"|"Headshot"|"None"), PortraitJoint,
               TalkJoints (comma list), TalkOffset (Vector3), Anchor (bool, default true)
        children: Template (Model, when Source = Template), Idle (KeyframeSequence, optional)
    Tracks : Folder
      <TrackName> : Folder       attrs: Kind, Actor, Order (lane), Muted, Locked
        <ClipName> : Configuration   attrs: Start, Duration, Speed (default 1), plus the kind's fields

ServerStorage.CutsceneSources : Folder
  <Name> : Folder
    <SourceId> : KeyframeSequence    attrs: SourceId, Clip (clip name, for humans)
```

## Clip kinds

| Kind | Fields beyond Start, Duration, Speed | Children |
|---|---|---|
| Animation | FadeIn 0.25, FadeOut 0.25, Loop, Weight 1, ClipOffset 0, AnimationId, ExportedHash, ContentHash, SourceId | `Keyframes` replica (only while the actor is not fully exported) |
| Move | Interpolation "Smooth"\|"Linear" | `Keys` Folder of CFrameValues (world pivot). Per key: Time, Easing, EasingDirection |
| Attach | Target, TargetJoint, Offset, BlendIn 0.15, OnExit "Stay"\|"Hide"\|"Return" | |
| Camera | Anchor, AnchorJoint, Interpolation, Shake, ShakeFrequency, LookAtActor, LookAtJoint, LookAtWeight, FocusActor, FocusJoint | `Keys` Folder of CFrameValues. Per key: Time, FOV (70), Easing, EasingDirection. With an Anchor, keys are relative to it |
| Sound | FadeIn, FadeOut, StartOffset, Anchor, AnchorJoint | one `Sound` template |
| VFX | Anchor, AnchorJoint, Offset, Mode "Burst"\|"Continuous", EmitScale 1 | one Attachment, BasePart or Model template |
| Dialogue | Speaker, Text (tokens like `{Hero}` name a role's player), TypeSpeed (0 = provider default), Blips, Mood, `X_*` provider fields | |
| Overlay | Color, Opacity, FadeIn, FadeOut, Text, SubText, Style "Fade"\|"Title"\|"Clock" | |
| PostFX | FadeIn, FadeOut, Blur, Saturation, Contrast, Brightness, TintColor | |
| Property | Target, Path (`/` separated, "" = model), Property, From, To, Easing, EasingDirection | |
| Event | Name, Side "Client"\|"Server"\|"Both", Data | |
| LookAt | Target (actor or "Speaker"), TargetJoint, Weight, FadeIn, FadeOut, MaxYaw 70, MaxPitch 35 | |
| Visibility | FadeIn, FadeOut | |

Talk is not a clip. The runtime moves `TalkJoints` automatically while the actor speaks. Set `TalkJoints = ""` to turn it off, and author mouth motion as an Animation clip on its own track when it must be exact.

## Roles and groups

- A `Role` actor is one player. The role id is any string (`Hero`, `Buyer2`). The editor's Student1 to Student4 entries are only suggestions.
- `Timeline.new` fills roles from `options.Roles`, then from `options.Students` in order. With fewer players than roles, players repeat.
- A `Group` actor (`Students`) is every player in `options.Students`. The name is historical and means "the players taking part" in any game.

## Joint keys

- A joint key is the pose names below the root pose joined with `/`, for example `Root/COG/CTRL_Hips/Hips`.
- A Motor6D is keyed by its Part1 name under its Part0's path.
- The root pose must carry the real root part's name (`HumanoidRootPart`, `RootPart`). Joints directly under the root part only play when it does.

## Evaluation rules

- **Layering.** Per joint, start at identity. The Idle layer blends first and always. Then each Animation track in ascending Order, and each active clip that keys the joint: `result = result:Lerp(sample, fadeWeight * Weight)`. Joints a clip does not key keep whatever was below, usually the idle. LookAt and Talk multiply on top.
- **Clip time.** `localTime = (t - Start) * Speed` and `alpha = clamp((t - Start) / Duration, 0, 1)`. Animation clips add `ClipOffset` and wrap when `Loop` is on.
- **Spline keys** (Camera, Move). A key without an Easing attribute is Linear. Ease only the ends: In on the first key, Out on the key before the last, InOut for a 2-key move. A default easing on every key stops the camera at each one.
- **Camera lane gaps** mean the gameplay camera. Cuts happen between clips.
- **Move.** The actor holds the last pivot it reached. Before its first Move clip it sits at its source position.
- **Visibility.** An actor with any Visibility clip is visible only inside those clips.
- **Uploaded mode.** The runtime uses the Animator for an actor only in a running game, and only when every Animation clip of that actor and its Idle are exported and current. See export-and-sources.md.

## Edge cases

- Clip names must be unique within a track, or `FindFirstChild` lookups pick the wrong one.
- Unknown kinds and muted tracks must be skipped when computing length and events. Use `Timeline.GetLength` and `Timeline.GetServerEvents` on both client and server, so the server's Finished is not late.
- Attributes on synced scripts are dropped by Script Sync, so timeline data lives in Studio-only instances.
- Resolve tagged objects at build time. Do not hard-code pivots, because tags and pivots move when someone regroups a model.
- A rebuild script that recreates the timeline wipes hand-set attributes. Set every attribute in the script, or edit the script instead of the data.
- Library KeyframeSequences are copied into clips, so a library fix does not reach a timeline until you rebuild it or recopy the clip.
