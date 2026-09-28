# Block player models

Adds an original voxel-style avatar under each existing `Player/Body`. Cuboid
heads, torsos, separate arms and legs, pixel face details, shirts and boots replace
the capsule visual. Shirt colors are deterministic from the player's peer ID, so
every peer sees the same color during a connection. Player collision and movement
are unchanged. The existing F3 camera displays your own model in third person;
your body remains hidden in first person.

## Animation

`block_player_motion.gd` derives poses from velocity:

- Idle below 0.12 m/s, blending limbs back to rest.
- Walking below 55% of the player's configured maximum speed.
- Running above that threshold, with longer strides, stronger arm swing and lean.
- Jump takeoff and falling poses, followed by a brief landing compression.

Stride phase advances with horizontal speed, with reversed steps when backing up
and side lean when strafing. The model blends pose transitions and turns its head
with view pitch. This adds no sprint binding or gameplay speed changes.

Local models use the player's velocity and floor contact. Remote models use
existing replicated velocity and a short floor ray to distinguish standing from
the apex of a jump. Animation is cosmetic and does not write shared network state
or need extra RPCs. The feature attaches rigs to new players and respawns once;
rigs are children of players and disappear with them.

## Held items

`Hand.support_grip()` exposes the existing item support marker. Occupied avatar
arms are hidden while Holdables draws its gripping gloves and blocky sleeves;
free arms keep swinging. `Hand` follows the animated shoulder markers and shirt
color. One-handed items leave the other arm free; two-handed weapons keep both
grips while the legs continue animating. First-person gloves keep their existing
camera mount.

Run `harness/verify.sh`. Tests under `tests/features/player_models` cover locomotion,
backwards and sideways movement, airborne detection, landing, model attachment,
visibility, and the item-grip integration.
