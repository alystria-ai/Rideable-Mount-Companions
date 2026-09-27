# Rideable Mount Companions

Ride the beasts of The Blood of Dawnwalker and bring them along as companions. Travel on a Wolf, Bear, Boar or Gargoyle, then dismount and fight together. Talk to your creature through text or voice, ask it to follow, wait, come closer or attack nearby enemies, and hear it answer with its own voice and personality.

Choose your creature in Shift+F5, adjust its size, riding speed and seat position, and press Shift+F6 to mount. Ride in first or third person using the camera settings from AI NPC Companions System.

## Features

- **Ride native beasts:** 28 combat-capable creature entries, including 24 riding candidates and four combat-only Tatzelwurm variants. Wolves, bears, dogs, boars, Gargoyles, Mares and the Beast of Balaur are among the choices.
- **Give spoken or typed commands:** ask your creature to follow, stop, come here, look at you, attack nearby enemies or leave. A departing creature walks away before disappearing when its route is clear. Movement orders are available while dismounted.
- **Talk to your companion:** spoken replies are On by default, with individual personalities, species lore and English or multilingual voices. Creatures share the main mod's current quest, surroundings and recent battle context, and can use its automatic reaction settings while unmounted.
- **Fight together:** entering combat triggers a safe dismount, allowing the creature to use its native attacks alongside Coen. Mount again when the fight is over.
- **Make the ride your own:** adjust creature size and riding speed from 50% to 250%, with separate height, forward/back and sideways seat offsets saved for each creature.
- **Choose your view:** switch between first- and third-person riding with F4, using the main mod's camera preferences.
- **Use silent commands if preferred:** disable Spoken replies to enter supported fixed commands locally through text, without a conversation request.
- **A familiar native menu:** Summon, Party, Settings, Controls and Help pages, remappable shortcuts, loading feedback and ten interface languages. One creature is active at a time; summoning another replaces it.
- **One addon download:** uses AI NPC Companions System for conversations and companion services, with no second runtime to install.

This first release includes experimental riding rigs. Wolf galloping, Dog galloping and Gargoyle ground steering have been confirmed in game; other rigs, including the latest Bear gait changes, still need visual confirmation. Gargoyles currently travel on the ground. Tatzelwurms can accompany you in combat but cannot be ridden.

## Requirements

- The Blood of Dawnwalker 1.05.
- [AI NPC Companions System 0.5.5 or later](https://github.com/alystria-ai/AI-Companion-Mod-For-Blood-of-Dawnwalker/releases/latest). Install Complete, or both Scripts and Runtime. Earlier releases lack the required creature service.
- [UE4SS for Dawnwalker 1.2.1 RC6](https://www.nexusmods.com/thebloodofdawnwalker/mods/18) and [Dawnwalker Mod Menu 1.0.7 or later](https://www.nexusmods.com/thebloodofdawnwalker/mods/271).

This add-on uses the main mod's running helper to interpret orders. It does not contain an API key or launch a second helper.

Rideable Mount Companions appears by name in the game's Mod Settings list. Its full Summon, Party, Settings, Controls and Help panel opens with Shift+F5. Both mods' shortcuts depend on the main companion service finishing startup.

## Controls

| Default control | Action |
| --- | --- |
| Shift + F5 | Open the creature menu |
| Shift + F6 near your summoned creature | Mount, or dismount when riding |
| W, A, S, D | Move the ridden creature |
| Shift while riding | Run |
| F4 (or your remapped main-mod camera shortcut) | Switch first- and third-person riding |
| F6 / F7 | Give a single creature a text or voice order |

Open **Controls** to change the menu and mount shortcuts. Select an action, hold Shift and press its new key. Esc cancels. Shift with F1 to F11, letters, digits, Home, End, PageUp, PageDown, Insert and Delete is supported. Each action needs a unique shortcut. The main mod's text and voice shortcuts remain available and are remapped in its own Controls page.

You can also edit `config/keybindings.ini`. Changes are picked up while the game runs; invalid or duplicate values leave the previous working shortcuts active.

```ini
[Controls]
Menu = Shift+F5
Mount = Shift+F6
```

## Creature menu

- **Summon:** choose a creature, set size, riding speed and rider position, then select Summon. Selecting its name alone does not spawn it. Size and speed range from 50% to 250%, with 100% defaults. Dismount before changing size.
- **Party:** view your current creature and operation status, then Mount, Dismount or Dismiss it. A single creature is active per player; summoning a replacement dismisses the previous one after dismounting.
- **Rider positioning on Summon:** height, forward/back and left/right offsets save separately for each creature. Starting values are estimates for its body shape, added to the automatic back-bone and seated-pelvis alignment. Editing a different creature never moves your current rider. Changes to the ridden creature apply live. Positive values move up, forward and right. Height ranges from -60 to 100 cm, forward/back from -100 to 100 cm, and sideways from -75 to 75 cm. Reset rider position restores that creature’s estimated defaults.
- **Settings:** choose interface language, English or multilingual voices, and whether creatures give spoken replies.
- **Controls:** remap both add-on shortcuts or restore their defaults.
- **Help:** read riding instructions, supported orders, settings and troubleshooting. Shortcut labels reflect your saved bindings.

The Summon page shows a loading bar beneath its status while the creature prepares. The menu returns to gameplay when your selected creature finishes summoning. Browsing a different creature keeps it open, and a failed summon stays on screen so you can read the reason. Detailed instructions stay on the Help page.

Riding uses the main mod's first-person preference, including its FOV, height and forward-offset settings. F4 switches between the seated first-person view and the third-person chase camera. Coen's obstructing body and hair are hidden only in first person and restored afterward. Walking and running use separate animation inputs; hold either Shift key to run. Riding speed scales the creature's private movement profile without changing other creatures.

**Spoken replies defaults to On.** Talk through F6 or F7; each creature has its own profile, lore notes, voice and stable personality, answers questions and acknowledges supported orders. Say or type “follow me”, “stop walking”, “come here”, “attack nearby enemies”, “look at me” or “leave”. Leave makes the creature walk away before it disappears. It remains present if the route is blocked. Other companions keep their normal conversations.

With **Spoken replies Off**, use F6 and type **Follow**, **Stop**, **Come here**, **Look at me**, **Attack** or **Leave**. These fixed commands are validated locally and sent to the creature's native action service. There is no Convai connection, language-model request or microphone input for the selected creature in this mode. Unsupported or ambiguous text is rejected. Movement orders require dismounting.

The selector includes 28 combat-capable creatures. Four Tatzelwurm variants are marked combat-only because their native movement uses stationary and burrowing actions; their Mount button is disabled. The remaining 24 entries are riding candidates, including Beast of Balaur, Mare, Greater Mare, Great Bear, Scarred Gargoyle and three Astral Hunt Wolf variants. Individual seats have not all been checked in game.

When Coen or the ridden creature enters combat, the mod stops riding, checks nearby ground for a clear exit and restores Coen's controls. The creature returns to normal allied following and uses its own native combat abilities. A previous Stop order does not keep it idle after the ride. Mount again after the fight; remounting is never automatic.

## Native behavior and session ownership

The parent mod creates the selected NPC definition through its existing loading queue and manages following, native combat, recovery and friendly-fire protection. Riding requests an exclusive control lease and stops the creature's navigation tree until dismount, while its movement and animation remain active. Only the tree stopped by that ride is restarted afterward. Speed changes use a private movement-profile copy, so the underlying enemy type and other copies are unaffected.

The Wolf uses its native travelling run while Shift is held, instead of speeding up its combat gait. Its riding-only animation selector and pace curve are private copies, restored on dismount. Riding also disables head targeting toward Coen. Bears use separate private walk and run profiles. W selects their native walk; holding Shift selects their native run. Both start from the original locomotion profile, so follower catch-up boosts are not multiplied into their riding animation. Replacing a mount waits for rider restoration and native ownership release, without waiting for the old actor's deferred destruction. In mounted first person, the shared camera guard hides the borrowed seated pose's hands and gauntlets; they return in third person and after dismount.

Coen remains the possessed player pawn. The rider controller attaches him to an owned seat component, plays a compatible native seated animation and borrows a separate camera. The main mod first releases its own first-person camera through an acknowledged camera lease. Native ground movement and collision move the creature; this is not a flying or teleporting controller.

Dismount checks the ground and capsule clearance beside the creature, then restores the captured player animation, collision, movement, input and camera. The parent mod also retains a rollback snapshot in case the add-on stops responding. Save or world changes invalidate the old session instead of restoring stale actors into the new save.

## Source layout

| File | Responsibility |
| --- | --- |
| `Scripts/main.lua` | One game-thread dispatcher and lifecycle |
| `Scripts/creature_runtime.lua` | Selected creature, service requests, shared action-interpreter registration and options |
| `Scripts/creature_menu.lua` | Native Summon, Party, Settings, Controls and Help pages, settings and shared shortcut handshake |
| `Scripts/keybindings.lua` | Shortcut validation, persistence and helper configuration |
| `Scripts/roster.lua` | Native creature definitions and species mappings |
| `Scripts/mount.lua` | Camera lease, rider attachment and safe restoration |
| `Scripts/movement.lua` | Private native movement profile and riding input |
| `Scripts/settings.lua` | Shared setting defaults, bounds and file format |
| `config/config.ini` | Size and riding speed preferences |
| `config/keybindings.ini` | Menu and mount shortcuts |
| `config/creature-profiles.lua` and `.json` | Public English and multilingual IDs for each creature |
| `tools/provision_creature_profiles.py` | Checkpointed cloud-profile provisioning using a private local credential |

No human character is included as a mount. Riding requires a compatible back bone, seated pose and native movement. The per-creature inspection findings are recorded in [the mount inspection notes](docs/MOUNT-INSPECTION.md).

## Languages and voices

The interface supports English, Simplified Chinese, Traditional Chinese, Spanish, Brazilian Portuguese, French, German, Russian, Japanese and Korean. **Interface** defaults to **Use main mod language** and can be set separately in the mount Settings page. The game uses its own font fallback for Chinese, Japanese and Korean.

**Voices** defaults to **Auto**: English interface uses Kokoro; other interface languages use Azure multilingual voices. Choose **English** or **Multilingual** explicitly if you prefer to separate voice capability from interface language. Multilingual characters answer in the language you use. No ElevenLabs voices are used.

Ordinary animals have warm female Kokoro voices, with Emma as their multilingual alternative. Supernatural and scarier creatures have male Kokoro voices, with Brian as their multilingual alternative. Each of the 28 definitions has separate English and multilingual IDs. Personality traits are assigned once, not rerolled with every summon. Personalities and speech are creative additions by this mod; verified species lore is distinguished from unknown origins.

Replies use normal dialogue. Profiles explicitly prohibit stage directions, animal noises and narrated actions such as “sniffs”. Supported orders are still sent as structured game actions, independently of the spoken reply. Voices cannot add flying or attacks absent from the native creature.

## Installation

Install the requirements first. Extract the addon ZIP into the game installation folder. Its contents belong under `Dawnwalker/Binaries/Win64/ue4ss/Mods/CreatureCompanionMounts`. Keep that technical folder name even though the displayed mod name is Rideable Mount Companions. Restart after the first install.

Press **Shift+F5**, choose a creature and Summon. The creature menu closes when it is ready. Stand nearby and press **Shift+F6** to ride. The game's Mod Settings list also provides the addon's size, speed, language and voice settings. Rider-position controls live on the Summon page.

Install this addon from **one ZIP**. It includes Lua scripts, configuration, public profile IDs, translations and documentation, with no EXE, DLL, second conversation helper or API key. It does not need its own Scripts/Runtime split. Both modules of the compatible main mod are still required. The empty `runtime` folder is for session data, not another runtime download. Back up `config/config.ini` and `config/keybindings.ini` before installing an update if you want to retain personalised settings.

## Development and publishing

The Git repository and release workflow are prepared locally. No release is published by saving these files or making a commit. `tools/Publish-Repository.ps1` prints the intended repository name by default. Its explicit `-Publish` switch creates `alystria-ai/Rideable-Mount-Companions` and pushes reviewed committed source to `main`.

Run `python tools/build_localization.py` after editing `localization/ui.json`. Run `tools/Build-Release.ps1` to create the addon ZIP and SHA-256 checksum in `dist`. The builder checks that every roster entry has both profile IDs and includes only the addon files. It never provisions characters or reads credentials.

The GitHub Actions workflow is manual only. By default it builds downloadable workflow artifacts. Its separate **publish_draft** option can create a draft release from `main`; it never publishes that draft automatically. This addon build needs no API-key secret because the main mod supplies the conversation service.

For your own cloud roster, use `tools/provision_creature_profiles.py --apply --template YOUR_OWN_MULTILINGUAL_TEMPLATE_ID`. Supply `CONVAI_API_KEY` privately or an ignored configuration file. The template must already permit other response languages in the Convai dashboard. The script checks live voice availability, creates and verifies each profile, checkpoints IDs and exports only public mappings. `characters/creatures.json` contains the authored personalities and source links.

Lua changes reload automatically after two stable file snapshots. Reload closes the addon menu, safely dismounts Coen and dismisses the creature through the normal service before replacing the code. Invalid Lua keeps the last working code active. Configuration and keybindings update separately without dismissing the creature. Changes to the bootstrap or compiled shared helper still require a restart.

Rider positions are saved in `[Rider.<creature ID>]` sections of `config/config.ini`. Existing nonzero global offsets are preserved during migration as independent per-creature values; reset a creature to use its new estimated defaults. The automatic asset audit covers the 28 retained definitions. Livestock without native combat support have been removed from the mount selector. Its findings and the remaining live checks are recorded in [the mount inspection notes](docs/MOUNT-INSPECTION.md).

Creature conversations reuse the main mod’s current quest, location, time, weather, recent battle context and follow-up setting. Speaking creatures can react to fights, gathered loot and Coen’s observations when unmounted, using the main mod’s toggles and shared cooldowns. Local command mode remains offline and silent. Creature lore and personality belong to its own profile; it does not inherit human companions’ private quest memories.
