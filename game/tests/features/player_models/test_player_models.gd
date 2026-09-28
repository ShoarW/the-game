extends GutTest

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const HAND_SCENE := preload("res://features/holdables/hand.tscn")
const FEATURE_SCENE := preload("res://features/player_models/feature.tscn")

var _player: Player
var _feature: Node
var _model: BlockPlayerModel


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_feature = FEATURE_SCENE.instantiate()
	add_child_autofree(_feature)
	_feature._process(0.0)
	_model = _player.get_node("Body/Avatar") as BlockPlayerModel
	_model.set_process(false)


func test_model_replaces_visuals_without_changing_collision_or_authority() -> void:
	assert_not_null(_model)
	assert_false((_player.get_node("Body/Mesh") as Node3D).visible)
	assert_false((_player.get_node("Body/Visor") as Node3D).visible)
	assert_true((_player.get_node("Collider") as CollisionShape3D).shape is CapsuleShape3D)
	assert_eq(_player.get_multiplayer_authority(), 1)
	_feature._process(0.0)
	assert_eq(_player.get_node("Body").get_child_count(), 3, "Attach once per player")


func test_first_person_hides_avatar_and_third_person_reveals_it() -> void:
	var body := _player.get_node("Body") as Node3D
	assert_false(_model.is_visible_in_tree())
	body.visible = true
	assert_true(_model.is_visible_in_tree())
	assert_false((_player.get_node("Body/Mesh") as Node3D).visible)


func test_late_player_starts_in_underwear_with_its_own_rig() -> void:
	var remote := PLAYER_SCENE.instantiate() as Player
	remote.name = "7"
	remote.set_multiplayer_authority(7)
	add_child_autofree(remote)
	_feature._process(0.0)
	var other := remote.get_node("Body/Avatar") as BlockPlayerModel
	assert_not_null(other)
	assert_ne(other, _model)
	assert_eq(other.shirt_color, _model.shirt_color)
	assert_true(other.is_visible_in_tree())


func test_jump_landing_blends_back_into_idle() -> void:
	_model.animate(0.1, Vector3(0, 6, 0), false, 8.0)
	assert_eq(_model.locomotion, &"jump")
	assert_gt(absf(_model.get_node("Rig/LeftLeg").rotation.x), 0.1)
	_model.animate(0.016, Vector3.ZERO, true, 8.0)
	assert_lt(_model.get_node("Rig").scale.y, 1.0, "Landing compresses the body briefly")
	for index: int in 30:
		_model.animate(0.016, Vector3.ZERO, true, 8.0)
	assert_eq(_model.locomotion, &"idle")
	assert_almost_eq(_model.get_node("Rig").scale.y, 1.0, 0.001)
	assert_almost_eq(_model.get_node("Rig/LeftLeg").rotation.x, 0.0, 0.002)


func test_held_arms_replace_only_occupied_limbs_and_follow_shoulders() -> void:
	(_player.get_node("Body") as Node3D).visible = true
	var hand := HAND_SCENE.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	hand.net_item_id = "banana"
	hand._process(0.0)
	_model._process(0.1)
	hand._process(0.0)
	assert_false(_model.get_node("Rig/Torso/RightArm").visible)
	assert_true(_model.get_node("Rig/Torso/LeftArm").visible)
	assert_eq(hand._arms._sleeve.albedo_color, _model.shirt_color)
	var sleeve := hand._arms._segments[0]
	var shoulder := sleeve.to_global(Vector3(0, -0.5, 0))
	assert_true(shoulder.is_equal_approx(_model.shoulder_position(true)))
	hand.net_item_id = "shotgun"
	hand._process(0.0)
	_model._process(0.1)
	assert_false(_model.get_node("Rig/Torso/LeftArm").visible)
	hand.net_item_id = ""
	hand._process(0.0)
	_model._process(0.1)
	assert_true(_model.get_node("Rig/Torso/RightArm").visible)
	assert_true(_model.get_node("Rig/Torso/LeftArm").visible)
	await get_tree().process_frame


func test_remote_ground_probe_keeps_jump_pose_through_apex() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 1, 10)
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	add_child_autofree(floor_body)
	await wait_physics_frames(2)
	_player.net_position.y = _player.movement.hull_height_m() * 0.5
	_player.net_velocity = Vector3.ZERO
	assert_true(_model._remote_grounded())
	_player.net_velocity.y = 6.0
	assert_false(_model._remote_grounded(), "Takeoff counts as airborne even near the floor")
	_player.net_position.y += 2.0
	_player.net_velocity.y = 0.0
	assert_false(_model._remote_grounded(), "Zero vertical speed at the apex is not grounded")
