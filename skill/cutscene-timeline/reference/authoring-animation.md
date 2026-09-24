# Authoring animation by code

Most of this came from building skinned bone rigs (imported characters) and R15 rigs. Measure everything against real `Animator` playback, because the engine differs from textbook maths in several places.

## Engine semantics

- **Segment easing.** A Pose's EasingStyle and EasingDirection apply to the segment that *starts* at that key. A new Pose defaults to Linear/In.
- **CubicV2 vs Cubic.** CubicV2 follows TweenService. Legacy `Cubic` has In and Out swapped. Never use legacy Cubic.
- **Constant.** In jumps to the next value at once, Out holds until the next key, and InOut switches at the midpoint. Use Constant/Out for a stepped hold.
- **Available styles.** `Enum.PoseEasingStyle` has no Sine. Use Linear, Constant, CubicV2, Elastic or Bounce. Bounce InOut uses the In curve on both halves. Elastic InOut uses period 0.45 (0.3 for In and Out).
- **Rotation blending is not slerp.** Linear-to-Linear neighbours use nlerp. Other segments interpolate rotation vectors, choosing quaternion signs that keep the keys closest. A slerp sampler was off by up to 15 degrees on large swings. Use the runtime Sampler, which matched the engine within 0.04 degrees.
- **Weights.** Weight 0 poses are ignored. Any non-zero Weight acts like 1 on a single track.
- **Before and after keys.** Before a joint's first key the engine forces identity, overwriting any manual Transform. After the last key it holds. The Animator still stops a non-looped track at its length, and then the pose relaxes. Add an explicit hold key about 1 s after the end pose when a clip must hold.
- **Hierarchy.** Bones animate only when the pose path mirrors the Bone tree exactly: Keyframe, then one root Pose, then bones nested as in the rig. Flat poses, wrong parents, or bone poses directly under the Keyframe are silently ignored.
- **Root pose name.** Joints directly under the root part play only when the root pose has the root part's name.
- **Scale.** The Animator multiplies Pose translations by `Model:GetScale()`. Store offsets divided by the scale, and multiply back in every sampler, gizmo and check.
- **Drift even in the runtime Sampler.** A 2-key Linear clip keyed at 0.5 and 0.53, chords of 90 to 150 degrees inside Linear chains, and joints first keyed late all drifted from the engine. Key every animated joint at t=0, and keep adjacent-key rotations well under 90 degrees.

## Playing a clip in edit mode

- Create an `Archivable=false` Animator if the rig has none. Imported rigs often have an AnimationController without one.
- Load with `RegisterAnimationClip` (or `KeyframeSequenceProvider:RegisterKeyframeSequence`), then `Animator:LoadAnimation`, then `StepAnimations`.
- `track.Length` can be 0 right after loading, which leaves you with a T-pose. Wait for `Length > 0`, then `AdjustSpeed(0)`, set `TimePosition`, and `StepAnimations(1/60)`.
- `StepAnimations(0)` does not apply a fresh track.
- A track stopped with `Stop(0)` stays in `GetPlayingAnimationTracks()` for about 18 steps.
- KeyframeReached and marker signals never fire under StepAnimations. Use Event clips.
- Work on an `Archivable=false` clone parked far from the set, and restore every Transform to identity afterwards.

## Rigs

- **Joint types.** Code must accept Bone, Motor6D and AnimationConstraint joints. Player characters here had 15 AnimationConstraints and no Motor6D. R15 stand-ins from `CreateHumanoidModelFromDescription` use them too, and they do not move in edit mode.
- **Imported rigs** can ship unanchored parts and importer metadata folders (`InitialPoses`). Anchor the root, and leave the metadata alone.
- **Character space.** The skinned rigs measured were +X right, +Y up, -Z forward, with chain bones pointing at their child along local +Y. Control bones pointed backward, left arm bones had local X flipped, and one rig's legs were rolled 55 degrees. Author in character space (RigKit `rotateLocal`, `natural`, `twoBoneIK`) rather than raw local axes.
- **Skinned collision stays in bind pose.** Raycasts and spatial queries never hit the posed mesh. For picking or contact checks, transform the point into bind pose through the nearest bone, or measure distance to bone segments.
- **Check that a joint deforms the mesh before building on it.** One rig's "jaw" bones only moved the mouth corners when translated. Rotating them did nothing. Take a screenshot first.
- **Cloth.** Deep hip bends push knees through skirts and coats. Keep hip flexion near 30 degrees, or rotate the front skirt chains with the thigh.
- **Wrist twist.** A large twist on the hand bone alone makes a candy-wrapper wrist. Split roll between forearm and hand (about 60/40) and cap the hand at 60 degrees.

## Smooth motion (the "choppy" problem)

- **Symptom.** Keying every bone on every key with CubicV2 InOut makes each key a dead stop. The arm went 313 to 0 to 241 degrees per second through one key.
- **Fix, part 1.** Key each bone group only at its own extremes, and leave passing poses unkeyed or Linear.
- **Fix, part 2.** Set `Interpolation = "Smooth"` on the KeyframeSequence. The runtime then uses velocity-continuous curves:
  - A Linear key is a **pass**: motion flows through it.
  - A CubicV2 InOut key is a **stop**. First and last keys are stops, and a key equal to its neighbour is a hold.
  - CubicV2 In or Out, Constant, Elastic and Bounce keep their native easing, so deliberate snaps survive.
- **Traps in Smooth mode:**
  - Take junction tangents from the native segment's end velocity. Forcing zero velocity where a Linear key follows an In segment adds a stop, because a CubicV2 In segment arrives at 3x chord speed.
  - Give one IK chain one role per key. Mixing pass and stop inside an arm chain made a 14.6 studs/s jab.
  - A contact needs a forced stop.
  - A planted stance key needs a twin key 1/240 s away, or feet slip.
  - A snap needs a stop key 1/60 s before it.
- **Easing a passing key In or Out** only works when the incoming and outgoing speeds are within 1.5x and 30 degrees of each other. Otherwise it pops. Decide per bone group, not per bone, or IK chains desync.
- **Detector.** Run `scripts/stop_and_go.luau` on every clip. It flags a speed minimum under 30% between two moves above 45 degrees per second in the same direction. The target is zero outside deliberate snaps.
- **Generators.** Run post-process passes last. One clip copied another clip's pose before smoothing had run, so regenerating it gave a different hash. After regenerating, check that the hash matches the saved clip.

## Locomotion and contact

- **Planted feet need Linear keys** on pelvis, legs and skirt about every 0.05 s. Eased keys slid the stance foot 0.43 studs. Shape the swing so the heel lands at about 0 world speed.
- **Stride fixes Move speed.** Record stride and speed per locomotion clip, and drive Move at exactly that speed. Turning the pivot while a walk loops skates the planted foot. Turn with an authored step-turn clip.
- **Baked aim and contact** (pointing at a prop, grabbing it) line up only when the actor's pivot is exactly on the mark the clip was authored at. Document each clip's mark, and end Move keys on it.
- **Fades are linear per-joint lerps.** A big pose change inside a fade moves at constant speed and stops dead. Keep big changes inside authored clips, and chain clips on a shared neutral pose.
- **IK keys drift between keys.** Joint-space interpolation between two IK-solved keys pulled a hand 0.6 studs into the face. Add in-between keys where clearance matters, and use one explicit pole across consecutive keys.
- **Measure fingertips, not joints, every frame.** Joint checks at keys missed fingers in the desk, thumbs in the face and chalk buried in a fist. Measure joint plus segment length against prop surfaces at 240 fps, then screenshot from the real shot cameras.
- **NaN guards.** Slerp between identical rotations and IK at the edge of reach both produced NaN. Assert zero NaN poses on every built clip.
- **Held props.** Verify every Attach Offset with a temporary part and a close-up capture, and publish the prop's axis convention next to the offset. Hide or drain liquid parts with Property clips before a container tilts past about 50 degrees.

## Unkeyed joints

The Idle layer always blends first, and a full-weight clip overrides only the joints it keys. Key every joint a clip must own for its whole duration, or the idle leaks through.
