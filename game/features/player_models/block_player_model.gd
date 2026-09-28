class_name BlockPlayerModel
extends Node3D
## Original voxel-style avatar. Its parent is Player/Body, so the existing camera
## feature controls first/third-person visibility and player replication owns yaw.

const SHIRT_COLORS: Array[Color] = [
	Color(0.13, 0.53, 0.55),
	Color(0.76, 0.36, 0.16),
	Color(0.45, 0.34, 0.68),
	Color(0.22, 0.43, 0.72),
	Color(0.38, 0.55, 0.24),
	Color(0.76, 0.59, 0.18),
]

var player: Player
var shirt_color := SHIRT_COLORS[0]
var locomotion: StringName = &"idle"
var _phase := 0.0
var _landing := 0.0
var _was_grounded := true
var _rig := Node3D.new()
var _torso := Node3D.new()
var _head := Node3D.new()
var _left_arm := Node3D.new()
var _right_arm := Node3D.new()
var _left_leg := Node3D.new()
var _right_leg := Node3D.new()
var _left_shoulder := Marker3D.new()
var _right_shoulder := Marker3D.new()


func _ready() -> void:
	process_priority = 15
	_build()
	set_process(player != null)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var motion := player.velocity if player.is_local() else player.net_velocity
	var yaw := player.yaw if player.is_local() else (get_parent() as Node3D).global_rotation.y
	var local_motion := Basis(Vector3.UP, -yaw) * motion
	var grounded := player.is_on_floor() if player.is_local() else _remote_grounded()
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	var holding := hand != null and ItemCatalog.find(hand.net_item_id) != null
	var support := holding and hand.support_grip() != null
	var pitch := player.pitch if player.is_local() else player.net_pitch
	animate(delta, local_motion, grounded, player.movement.max_speed_m(), pitch, holding, support)


func animate(
	delta: float,
	motion: Vector3,
	grounded: bool,
	max_speed: float,
	pitch: float = 0.0,
	right_held: bool = false,
	left_held: bool = false
) -> void:
	var speed := Vector2(motion.x, motion.z).length()
	if grounded and speed > BlockPlayerMotion.IDLE_SPEED:
		_phase = fmod(_phase + BlockPlayerMotion.phase_step(speed, max_speed, delta), TAU)
	if grounded and not _was_grounded:
		_landing = 1.0
	_was_grounded = grounded
	_landing = maxf(_landing - delta * 7.0, 0.0)
	var pose := BlockPlayerMotion.pose(_phase, motion, grounded, max_speed)
	locomotion = pose["state"]
	var blend := 1.0 - exp(-14.0 * delta)
	_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, pose["left_leg"], blend)
	_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, pose["right_leg"], blend)
	_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, pose["left_arm"], blend)
	_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, pose["right_arm"], blend)
	_left_arm.visible = not left_held
	_right_arm.visible = not right_held
	_torso.rotation.x = lerp_angle(_torso.rotation.x, pose["lean"], blend)
	_torso.rotation.z = lerp_angle(_torso.rotation.z, pose["roll"], blend)
	_head.rotation.x = lerp_angle(_head.rotation.x, pitch - _torso.rotation.x, blend)
	_rig.scale.y = 1.0 - _landing * 0.055
	_rig.position.y = float(pose["bob"]) - _landing * 0.049


func shoulder_position(right: bool) -> Vector3:
	return _right_shoulder.global_position if right else _left_shoulder.global_position


func sleeve_color() -> Color:
	return shirt_color


func _remote_grounded() -> bool:
	if player.net_velocity.y > 1.0:
		return false
	var feet := player.net_position - Vector3.UP * player.movement.hull_height_m() * 0.5
	var ray := PhysicsRayQueryParameters3D.create(
		feet + Vector3.UP * 0.12, feet + Vector3.DOWN * 0.18, 1, [player.get_rid()]
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit["normal"].y >= 0.7


func _build() -> void:
	var skin := _material(Color(0.69, 0.45, 0.29))
	var shirt := _material(shirt_color)
	var trim := _material(shirt_color.lightened(0.22))
	var pants := _material(Color(0.13, 0.19, 0.27))
	var boots := _material(Color(0.085, 0.10, 0.13))
	var hair := _material(Color(0.12, 0.075, 0.05))
	var whites := _material(Color(0.92, 0.94, 0.88))
	var eyes := _material(Color(0.12, 0.20, 0.22))
	_pivot(_rig, self, "Rig", Vector3.ZERO)
	_pivot(_torso, _rig, "Torso", Vector3(0, -0.17, 0))
	_box(_torso, "Shirt", Vector3(0, 0.31, 0), Vector3(0.46, 0.62, 0.25), shirt)
	_box(_torso, "Hem", Vector3(0, 0.028, 0), Vector3(0.468, 0.055, 0.26), trim)
	_box(_torso, "Collar", Vector3(0, 0.59, -0.131), Vector3(0.15, 0.06, 0.012), skin)
	_box(_torso, "Pocket", Vector3(-0.115, 0.41, -0.134), Vector3(0.11, 0.10, 0.014), trim)
	_pivot(_head, _torso, "Head", Vector3(0, 0.65, 0))
	_box(_head, "Face", Vector3(0, 0.19, 0), Vector3(0.43, 0.42, 0.43), skin)
	_box(_head, "HairTop", Vector3(0, 0.405, 0), Vector3(0.45, 0.075, 0.45), hair)
	_box(_head, "HairBack", Vector3(0, 0.24, 0.211), Vector3(0.44, 0.27, 0.025), hair)
	_box(_head, "Fringe", Vector3(-0.075, 0.342, -0.22), Vector3(0.29, 0.07, 0.025), hair)
	_box(_head, "FringeLock", Vector3(-0.15, 0.295, -0.22), Vector3(0.085, 0.07, 0.025), hair)
	for side: float in [-1.0, 1.0]:
		_box(_head, "Eye", Vector3(side * 0.105, 0.23, -0.22), Vector3(0.085, 0.048, 0.014), whites)
		_box(_head, "Pupil", Vector3(side * 0.09, 0.23, -0.23), Vector3(0.035, 0.048, 0.01), eyes)
	_box(_head, "Nose", Vector3(0, 0.16, -0.23), Vector3(0.065, 0.055, 0.045), skin)
	_box(_head, "Mouth", Vector3(0, 0.09, -0.22), Vector3(0.095, 0.02, 0.014), hair)
	for side: float in [-1.0, 1.0]:
		var arm := _left_arm if side < 0 else _right_arm
		var leg := _left_leg if side < 0 else _right_leg
		var shoulder := _left_shoulder if side < 0 else _right_shoulder
		_pivot(arm, _torso, "LeftArm" if side < 0 else "RightArm", Vector3(side * 0.335, 0.56, 0))
		_pivot(shoulder, _torso, "LeftShoulder" if side < 0 else "RightShoulder", arm.position)
		_box(arm, "Sleeve", Vector3(0, -0.20, 0), Vector3(0.19, 0.40, 0.24), shirt)
		_box(arm, "Cuff", Vector3(0, -0.39, 0), Vector3(0.195, 0.05, 0.245), trim)
		_box(arm, "Hand", Vector3(0, -0.52, 0), Vector3(0.18, 0.22, 0.23), skin)
		_pivot(leg, _rig, "LeftLeg" if side < 0 else "RightLeg", Vector3(side * 0.12, -0.17, 0))
		_box(leg, "Trousers", Vector3(0, -0.30, 0), Vector3(0.22, 0.60, 0.25), pants)
		_box(leg, "Boot", Vector3(0, -0.66, -0.025), Vector3(0.225, 0.12, 0.30), boots)


func _pivot(node: Node3D, parent: Node3D, label: String, at: Vector3) -> void:
	node.name = label
	node.position = at
	parent.add_child(node)


func _box(
	parent: Node3D, label: String, at: Vector3, dimensions: Vector3, material: Material
) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material
