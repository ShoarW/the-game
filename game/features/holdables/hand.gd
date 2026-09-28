class_name Hand
extends Node3D
## One player's held item: what they're holding, and where its visual sits, for
## everyone watching. Spawned by the holdables feature (holdables.gd) as a companion
## of the matching Player, since core/player isn't ours to edit — see
## `_mount_transform` for how it tracks the player without being parented to it.
##
## Holding is server-authoritative like the rest of shared state (game/AGENTS.md), so
## unlike Player's client-authoritative movement this keeps the default multiplayer
## authority (1, the server). Clients only ever request an action; the server decides.

const THROW_DISTANCE := 5.0
const DROP_DISTANCE := 1.2
const HITSCAN_RANGE_M := 50.0
const FLASH_DURATION_S := 0.06

## Replicated (server -> everyone). See the synchronizer config in hand.tscn.
@export var net_item_id := ""

## Set from spawn data (see holdables.gd), identically on every peer, before this node
## enters the tree, so it doesn't need its own synchronizer property.
var peer_id := 0

var _mounted_item_id := ""
var _view: Node3D
var _arms := HeldArms.new()
var _flash_timer := 0.0
var _fire_cooldown := 0.0

@onready var _mount: Node3D = $Mount


func _ready() -> void:
	# Player updates at priority 0; third-person camera updates at 10.
	process_priority = 20
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arms.name = "Arms"
	add_child(_arms)
	add_to_group(&"hands")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
	Controls.ensure_action(&"primary_action", [mouse, pad])
	var drop_key := InputEventKey.new()
	drop_key.physical_keycode = KEY_G
	var drop_pad := InputEventJoypadButton.new()
	drop_pad.button_index = JOY_BUTTON_LEFT_SHOULDER
	Controls.ensure_action(&"drop_item", [drop_key, drop_pad])
	_rebuild_view()


func _process(delta: float) -> void:
	if net_item_id != _mounted_item_id:
		_rebuild_view()
	var player := _player()
	visible = player != null and not net_item_id.is_empty()
	if player != null:
		global_transform = _mount_transform(player)
		_pose_arms(player)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_set_flash(false)
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta


func _unhandled_input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id() or not Controls.gameplay_active():
		return
	if net_item_id.is_empty():
		return
	if event.is_action_pressed(&"primary_action"):
		request_primary_action.rpc_id(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"drop_item"):
		request_drop_item.rpc_id(1)
		get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func request_primary_action() -> void:
	if not multiplayer.is_server() or not _is_own_request():
		return
	var def := ItemCatalog.find(net_item_id)
	if def == null:
		return
	match def.category:
		ItemDefinition.Category.WEAPON:
			_fire(def)
		ItemDefinition.Category.FOOD:
			_eat(def)
		ItemDefinition.Category.PROP:
			_throw(def)


## Drops whatever is held, regardless of category, a short toss in front of the
## player — the only way to get rid of a weapon once picked up, since firing and
## eating never empty the hand.
@rpc("any_peer", "call_local", "reliable")
func request_drop_item() -> void:
	if not multiplayer.is_server() or not _is_own_request() or net_item_id.is_empty():
		return
	var def := ItemCatalog.find(net_item_id)
	if def != null:
		_toss(def, DROP_DISTANCE)


## Server: hands this an item, if it's empty. Called by pickups and landed throws.
func try_equip(item_id: String) -> bool:
	if not multiplayer.is_server() or not net_item_id.is_empty():
		return false
	net_item_id = item_id
	return true


## A Hand tracks its owner by peer id (see `peer_id`), not scene position, so any
## script holding a `Player` can find its hand this way.
static func for_peer(tree: SceneTree, target_peer_id: int) -> Hand:
	for node: Node in tree.get_nodes_in_group(&"hands"):
		var hand := node as Hand
		if hand != null and hand.peer_id == target_peer_id:
			return hand
	return null


func _is_own_request() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	var effective := sender if sender != 0 else multiplayer.get_unique_id()
	return effective == peer_id


func _fire(def: ItemDefinition) -> void:
	if _fire_cooldown > 0.0:
		return
	_fire_cooldown = def.fire_cooldown_s
	_play_fire.rpc()
	if def.damage <= 0.0:
		return
	var player := _player()
	if player == null:
		return
	var combat := get_tree().get_first_node_in_group(&"combat")
	var origin := _aim_origin(player)
	for _pellet: int in maxi(def.pellet_count, 1):
		var jitter := deg_to_rad(def.spread_degrees)
		var yaw := player.net_yaw + randf_range(-jitter, jitter)
		var pitch := clampf(
			player.net_pitch + randf_range(-jitter, jitter), deg_to_rad(-89.0), deg_to_rad(89.0)
		)
		var target := _hitscan(player, origin, ThrowMath.aim_direction(yaw, pitch))
		if target == null:
			continue
		var target_player := target as Player
		if target_player != null and combat != null:
			combat.call(
				"apply_damage", target_player.get_multiplayer_authority(), def.damage, peer_id
			)
		elif target_player == null and target.is_in_group(&"killable"):
			target.call("take_hit", peer_id)


## Returns whatever physics body the shot hit — a `Player` for combat damage, or
## anything else (e.g. features/penguin's `killable` group) for features that handle
## being shot on their own terms.
func _hitscan(shooter: Player, origin: Vector3, direction: Vector3) -> Node3D:
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * HITSCAN_RANGE_M, 1, [shooter.get_rid()]
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["collider"] as Node3D if hit else null


@rpc("authority", "call_local", "reliable")
func _play_fire() -> void:
	_flash_timer = FLASH_DURATION_S
	_set_flash(true)


func _eat(def: ItemDefinition) -> void:
	net_item_id = ""
	_play_eaten.rpc(def.id)


## An event, not saved state: late joiners don't need to replay an old bite.
@rpc("authority", "call_local", "reliable")
func _play_eaten(_item_id: String) -> void:
	pass


func _throw(def: ItemDefinition) -> void:
	_toss(def, THROW_DISTANCE)


## Empties the hand and asks holdables to spawn `def` on the ground `distance` ahead
## of where the player's looking — a full throw for a PROP's primary action, or a
## short toss for a plain drop (see `_throw` and `request_drop_item`).
func _toss(def: ItemDefinition, distance: float) -> void:
	var player := _player()
	if player == null:
		net_item_id = ""
		return
	net_item_id = ""
	var from := (
		HeldItemPose.world_grip(player.net_position, player.net_yaw, player.net_pitch).origin
	)
	var direction := ThrowMath.aim_direction(player.net_yaw, player.net_pitch)
	var to := _landing_point(from, direction, distance)
	var holdables := get_tree().get_first_node_in_group(&"holdables_root")
	if holdables:
		holdables.call("spawn_thrown_item", def.id, from, to)


func _landing_point(from: Vector3, direction: Vector3, distance: float) -> Vector3:
	var flat := ThrowMath.toss_target(from, direction, distance)
	var query := PhysicsRayQueryParameters3D.create(
		flat + Vector3.UP * 10.0, flat + Vector3.DOWN * 10.0
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else flat


## Use the first-person camera only while the owner's body is hidden. F3 and
## remote peers use the same body-relative grip, including the aim pitch.
func _mount_transform(player: Player) -> Transform3D:
	var body := player.get_node("Body") as Node3D
	if player.is_local() and not body.visible:
		var camera := player.get_node("Camera") as Node3D
		var def := ItemCatalog.find(net_item_id)
		var offset := def.first_person_offset if def != null else HeldItemPose.FIRST_PERSON_OFFSET
		return camera.global_transform * Transform3D(Basis.IDENTITY, offset)
	var yaw := player.yaw if player.is_local() else body.global_rotation.y
	var pitch := player.pitch if player.is_local() else player.net_pitch
	var origin := (
		player.get_global_transform_interpolated().origin
		if player.is_local()
		else player.global_position
	)
	return HeldItemPose.world_grip(origin, yaw, pitch)


func _aim_origin(player: Player) -> Vector3:
	return (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5)
	)


func support_grip() -> Node3D:
	return _view.get_node_or_null("SupportGrip") as Node3D if _view != null else null


func _pose_arms(player: Player) -> void:
	if _view == null:
		return
	var body := player.get_node("Body") as Node3D
	var avatar := body.get_node_or_null("Avatar")
	if avatar != null and avatar.has_method("sleeve_color"):
		_arms.set_sleeve_color(avatar.call("sleeve_color"))
	var first_person := player.is_local() and not body.visible
	if not first_person and avatar != null and avatar.has_method("shoulder_position"):
		_arms.pose(
			_arms.to_local(avatar.call("shoulder_position", true)),
			_arms.to_local(avatar.call("shoulder_position", false)),
			support_grip()
		)
		return
	var shoulders: Transform3D
	if first_person:
		shoulders = (player.get_node("Camera") as Node3D).global_transform
		shoulders.origin += shoulders.basis * Vector3(0, -0.36, 0.10)
	else:
		var yaw := player.yaw if player.is_local() else body.global_rotation.y
		shoulders = Transform3D(Basis(Vector3.UP, yaw), body.global_position)
		shoulders.origin.y += 0.30
	_arms.pose(
		_arms.to_local(shoulders * Vector3(0.32, 0, 0)),
		_arms.to_local(shoulders * Vector3(-0.32, 0, 0)),
		support_grip()
	)


func _player() -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.name == str(peer_id):
			return player
	return null


func _rebuild_view() -> void:
	_mounted_item_id = net_item_id
	for child: Node in _mount.get_children():
		_mount.remove_child(child)
		child.queue_free()
	_view = null
	var def := ItemCatalog.find(net_item_id)
	if def != null and def.view_scene != null:
		_view = def.view_scene.instantiate() as Node3D
		_mount.add_child(_view)
		HeldItemPose.align_grip(_view)


func _set_flash(active: bool) -> void:
	if _view == null:
		return
	var muzzle := _view.get_node_or_null("Muzzle")
	if muzzle == null:
		return
	var existing := muzzle.get_node_or_null("MuzzleFlash")
	if active and existing == null:
		var light := OmniLight3D.new()
		light.name = "MuzzleFlash"
		light.light_energy = 3.0
		light.omni_range = 2.5
		light.light_color = Color(1.0, 0.85, 0.5)
		muzzle.add_child(light)
	elif not active and existing != null:
		existing.queue_free()
