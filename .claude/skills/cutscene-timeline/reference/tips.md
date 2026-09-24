# Tips

## Working habits

- Build timelines from one script that copies assets fresh, sets every attribute and resolves tags at build time. Rebuilding then fixes drift instead of adding it.
- Pair every build script with a read-only check script (`scripts/check_template.luau`) and fail on any miss.
- Screenshot sparingly. A few shots from the real shot cameras with the dialogue box on beat dozens from free angles.
- Time dialogue with the provider's `ReadingTime`, then add pace. Kids need readable holds, but a gap longer than about 2 s with no line and no action drags.
- When the user says an animation is "choppy", measure speed through the keys first. It is usually stop-and-go easing, not frame rate.
- Keep scene-specific numbers (pivots, marks, jamb planes) in one notes file next to the build script, and update it when a model is regrouped.

## Checks worth automating

- Zero NaN poses, zero bad pose parents, and every animated joint keyed at t=0.
- `scripts/stop_and_go.luau` at zero hits outside deliberate snaps.
- Fingertip-to-surface distance at 240 fps for every contact clip.
- Camera near plane, line of sight and subject-in-frame at 30 fps.
- Dialogue duration at least `ReadingTime`, and no camera cut while a line types.
- Hash of a regenerated clip equal to the saved one.

## Running several agents on one Studio

- **One lease.** Use a single Studio lease (for example the roblox-playtest-queue) only for playtests, edits while in play mode, visible setup plus capture, and changes to shared instances. Prepare the batch first, hold under about 60 s, clean up, then release. File edits, reading and thinking need no lease.
- **Isolation.** Work on `Archivable=false` clones parked far from the set. Never pose shared originals. Fingerprint the scene before and after.
- **Namespaces.** Namespace `_G` keys and temp folders per agent. Re-read shared docs right before writing, and change only your own section.
- **Build, review, fix.** Build, then review adversarially, then fix. Reviewers found criticals in 7 of 8 units that builders had tested past. Give reviewers different harnesses: random seek orders, engine playback, captures from shot cameras, archivable undo fixtures.
- **Fix the spec before launching.** Rule changes do not reach running agents. Settle the spec first, report conflicts instead of improvising, and give every new file an owner.
