# Mount inspection

Inspected in the paused game on 27 September 2026. All 36 NPC definitions and their pawn classes loaded through the asynchronous native loader. No creatures were spawned and Coen was not attached during this batch. The development job finishes after the catalogue; it does not run during normal play.

## What the inspection establishes

Definition defaults can be placeholders. Dogs and the Beast of Balaur inherit the Wolf pawn; several livestock entries inherit the same simple-character pawn. Their default mesh does not establish the final mesh, animation layer or movement profile after NPC attachments are applied. Those fields are recorded as unverified where the default object does not supply them.

The loaded locomotion selectors establish these gait choices:

| Family | Asset findings | Riding status |
|---|---|---|
| Wolves | Separate walk, combat run and travelling run samples at pace 0.5, 1 and 3 | Dark Astral Wolf gallop confirmed after selecting SpeedAnimDriven for the private riding profiles. Other variants share this path |
| Bears | Separate walk and run samples at pace 0.5 and 1 | Uses the authored selector, travelling input pace and private SpeedAnimDriven profiles. Earlier visual confirmation was withdrawn; Bear running needs a fresh check |
| Dogs | The initial Wolf layer can be replaced by the final Dog layer after spawn. Dog combat running is a slower gait; the shared skeleton supports the authored travelling gallop | Retain Dog walking and switch to a private compatible travelling-gallop selector with Shift. Gallop and return to walking confirmed on the Astral Dog. Other variants not individually ridden |
| Boar | Distinct walk and run samples and authored movement profiles | Replaced active sample edits with a separate private running selector to refresh the animation cache. Earlier visual confirmation was questioned by the player; updated Boar still needs a visual check |
| Deer, cow, sheep | No native combat AI definition | Removed from the mount roster |
| Pig, goats | No native combat AI definition | Removed from the mount roster |
| Gargoyles | Grounded selector repeats walking samples at both speeds; a separate flying selector exists | Mounted ground movement uses its authored directional profile. Live trace verified walking at 150 cm/s and Shift movement at 400 cm/s at default speed. No distinct ground running animation; flight is not implemented |
| Mare | Live base Mare has directional strafe samples at both pace levels; authored combat profile is 425 cm/s, FaceDirection | Mounted steering now uses that profile and a separate walking profile; no distinct running animation in the native cycle |
| Tatzelwurms | Live base and small variants use stationary combat profiles, an idle-only cycle and burrow animations | Retained as combat-only companions. Ground mounting is explicitly disabled |
| Beast of Balaur | Live spawned creature confirmed to use Wolf locomotion layers and skeleton | Inherits the private Wolf travelling-run selector fix |

Wolf running assigns the unmodified authored travelling blend space to its private running selector. Walking restores the original selector; shared animation assets remain read-only. The initial White Wolf check appeared successful, but the Dark Astral Wolf later reproduced the fast-walk problem. A live trace showed the run profile and selector correctly selected while AnimDriven kept the old physical pace even after Shift release. Switching both private profiles to the native SpeedAnimDriven mode produced a player-confirmed gallop on the Dark Astral Wolf. This is required in addition to the selector change.

The Bear's earlier running confirmation was subsequently withdrawn by the player. It now shares the speed-driven profile correction, with its own authored cycle and travelling input pace. Its visual gait remains unconfirmed. Direct input-size overriding was tested and removed: the native setter clamps it to 1 and did not fix the stride.

Both private movement profiles remain in the native stack for the ride, with the walking profile below the running profile during Shift and above it afterward. This prevents the inactive walking profile from being garbage-collected during a long ride. Both handles are removed on release. Speed changes refresh the profiles while retaining the selected walk/run state.

Movement changes clone profiles and curves under the individual actor. Authored assets, ordinary enemies and other companions are not edited. Static asset inspection is not a substitute for verifying rider posture, steering, collision and camera movement on a live mount.

Running selectors are filled before being assigned to the layer. Switching the actual blend-space reference refreshes animation sampling, instead of relying on edits to samples that may already be cached. Original walking selectors stay unchanged. Wolf, Dog, Bear and Boar mounts recheck only their own linked layers twice per second to handle its final animation attachment arriving late. Private run selectors are reused while valid and rebuilt if garbage-collected; no inactive clone needs to retain a world through a global root.

Mounted steering uses the parent service's controller-tick lease for all combat creatures as well as its directional movement profile. Clearing focus or disabling follower mode alone did not prevent the game restoring Coen as a facing target. With that controller tick suspended, live movement showed the creature's yaw converging to the rider's requested heading instead of circling. The host restores the original tick setting on dismount and interrupted-ride recovery; the creature's movement and animation continue ticking throughout the ride.

## Estimated seat corrections

These are conservative starting guesses relative to the existing `spine_02` and Coen seated-pelvis alignment. They are not measurements of a saddle. Each of the 28 retained definitions saves its own values, even when it shares the initial family estimate. All sideways defaults are zero to keep the rider centred.

| Family | Height (cm) | Forward/back (cm) |
|---|---:|---:|
| Wolf | 0 | 0 |
| Dog | -4 | 0 |
| Bear | 8 | -12 |
| Boar | 4 | -4 |
| Deer | -2 | -10 |
| Pig | 2 | -4 |
| Cow | 6 | -10 |
| Goat | -4 | -6 |
| Sheep | 0 | -4 |
| Gargoyle | 12 | -18 |
| Tatzelwurm | 6 | -18 |
| Beast of Balaur | 6 | -12 |
| Mare | 10 | -16 |

Positive forward values move toward the creature's head; negative values move toward its rear. The Summon sliders apply to the selected definition only. Reset restores its estimate. Size still controls the creature independently, so extreme sizes may need further adjustment.

## Non-combat animals

Cow, Deer, Stag, Doe, Pig, Goat, Billy Goat and Sheep were removed at the player's request. Their definitions do not supply a combat AI. Cow population spawning produced a valid native animal, but the companion loader waited for a combat board that never appeared. It also uses the Animalia RigSpine skeleton instead of the combat creatures' spine_02 layout. No synthetic combat definition is assigned to these animals. Existing world animals are unaffected.

Live batch inspection also confirmed the Great Bear uses the Bear locomotion layer. The batch summoned, inspected and dismissed each owned creature without attaching Coen. Mare steering and individual rider seats still need visual confirmation. Speed slider changes refresh the mounted creature's owned profile handles only when its value changes, preserving its walk/run state.
