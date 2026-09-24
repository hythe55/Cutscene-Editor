# Staging and cameras

## Before authoring

- **Inventory the set.** Names lie. One place had 8 identically named flasks, 36 chairs all named `Model`, a door named `Model`, a leftover dummy in a tagged chair, and 18 floating light slabs visible in every wide shot. Find actors by tag, find props by geometry (`GetPartBoundsInBox`), and list stray objects first.
- **Check what a tag covers.** A door tag sat on the whole door model, so the frame swung too. Hide the tagged parts in a capture to see what is under the tag. Animate only the moving sub-model, with its pivot on the hinge.
- **Compute reach and clearance first.** A rig's reach (3.25) was short of the prop (3.78), a T-pose span (9.2) was wider than a door leaf (6.8), and a run passed 0.19 studs from a closed leaf. IK-test every reach, and sweep every path with a 3-stud box every 1.5 studs plus a head-zone sweep.
- **List every prop and state change the dialogue implies.** A chalkboard stayed blank through 17 s of "writing the warning signs". Persist after-cutscene world state on the server. A prop that lives on a timeline clone vanishes when the timeline ends.

## Camera checks that caught real problems

Run these in a read-only validation script (`scripts/check_template.luau`) and fail the build on any miss:

- **Near plane.** Use `GetPartBoundsInRadius(position, 0.5)` plus about 14 short rays, and keep at least 0.4 studs of clearance. Sample every camera clip at 30 fps.
- **Line of sight** from the camera to the shot's subject, ignoring invisible parts.
- **Subject in frame.** Project with the shot's FOV at 16:9. Captures from the MCP use the Studio window's aspect, not 16:9.
- **Every seat.** Test player-anchored shots against every chair a player could sit in.
- **Hidden actors.** Raycast body points from every shot camera through the whole clip. A hidden character showed through a gap under a desk panel from far cameras, and elbows showed from every student-side shot.

## Composition

- Review every clip and insert from the exact shot camera with the dialogue box on. A gesture that looked fine from the students' view filled an over-the-shoulder shot, and a key insert sat under the dialogue box.
- Keep subjects above about 0.75 of frame height while a line is showing.
- Do not cut while a line is still typing.
- **Spline easing.** Ease the ends only: In on the first key, Out on the key before the last, Linear in between, InOut for 2-key moves. The editor's "Add key" follows this.
- **Stretching a shot** (a slower crane) means scaling the clip's Start and Duration and dividing its Speed by the stretch. Later clips shift by the added time.
- **Dutch angles.** Studio's edit camera drops roll, so a dutch shot looks level in the editor unless the camera lock drives it.

## Doors and frames

- Big arched frame meshes have bounding boxes that cover the whole doorway, so box sweeps fire on every pass. Exclude the frame from box sweeps, and add a raycast or plane test against the jamb faces at 60 fps. Excluding the frame alone once hid a real jamb hit.
- Rotate the door leaf about its own hinge pivot: `closedPivot * CFrame.Angles(0, math.rad(angle), 0)`. Check which sign swings away from walls with a sweep.

## Players in the scene

- **Solo play makes every student role the same player.** Write student lines that still work as one voice, or give extra roles NPC identities. Test with 1, 2 and 4 players.
- **Random seats.** Fixed per-role eyeline sides can cross the line when seats are random.
- **Seating.** Unseat on the server. Stand players about 2.6 studs behind the chair with feet on the floor. Hold network ownership briefly, or the client snaps them back onto the chair. Raycast only anchored parts when finding the seat top.
- **Streaming.** With StreamingEnabled, actors, props, chairs and doors need `ModelStreamingMode = Persistent`. Players who spawn far away or join mid-cutscene may not have them.
- **Cutscene-only NPCs.** Rigs tagged for the game's NPC systems turn into roaming chasers once startup works. Tag cutscene-only rigs (for example `CutsceneOnly`) and move them out of Workspace at server start.
