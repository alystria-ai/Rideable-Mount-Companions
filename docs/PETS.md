# Passive pets

The Summon panel has Beasts and Pets categories. Pets are ordered White House Cat, Rabbit, Chicken, Goat and Sheep. One active creature remains the default: choosing another replaces the current beast or pet.

Pets are owned by the addon's Scripts/pets.lua module. It loads the existing ai_state and companion_native utilities from the installed 0.5.5 main mod in a private module environment and reuses its native population bridge. No main-mod source files are installed or patched. They have no combat AI board and are accepted only when their native stub reports non-targetable. Damage is disabled on each summoned actor. Their scare/wander actor tick is suspended while component animation, gravity and native path following remain active. Camera movement does not change their destination. Walking resumes near Coen; a private copy of the authored running profile handles catch-up.

The white cat uses a private coat material with white albedo. Its native fur normal and roughness maps and separate eye material remain. No game definition, shared material or wild animal is edited.

Pets are quiet, follow-only companions. Mounting, attack commands, riding speed and rider offsets are unavailable. Beasts register automaticReactions=false through the shared SDK, retaining direct conversations and commands. Main mod 0.5.6 checks this flag during speaker selection and before submitting a reaction.

The addon routes pet IDs locally, independently of the shared combat-creature protocol. World changes and live reload dismiss owned pets; they never wait for an absent combat board. Failed loads retain a diagnostic result before their population owner is removed. Pet loading uses utilities already present in main mod 0.5.5; this release requires 0.5.6 for the separate reaction opt-out. Pet updates are bounded to once per second, while world identity is checked on each addon update.

The white cat was inspected live: spawning and path following worked, the stub reported non-targetable, and the player confirmed following. Its authored running profile has a native maximum speed of 600 cm/s. Rabbit, Chicken, Goat and Sheep use captured native SimpleCharacter definitions; their individual visual behavior still needs confirmation.
