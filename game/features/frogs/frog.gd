class_name Frog
extends CharacterBody3D
## The server chooses safe hops and reacts to players. Clients only render synced
## state; appearance and individual movement traits arrive through spawn data.

const REMOTE_SMOOTHING := 18.0
const ALERT_RADIUS := 5.0
const CALM_RADIUS := 7.0

@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0
@export var net_phase := -1.0

var body_color := Color(0.3, 0.8, 0.35)
var body_size := 1.0
var jump_distance := 1.5
var jump_height := 0.5
var jump_duration := 0.45
var rest_time := 1.0

var _hopping := false
var _settling := true
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_elapsed := 0.0
var _hop_duration := 0.45
var _hop_height := 0.5
var _rest_timer := 0.0
var _sense_timer := 0.0
var _threat := Vector3.INF
var _fleeing := false
var _heading := Vector3.FORWARD
var _navigation := FrogNavigation.new()

@onready var _body: FrogModel = $Body
@onready var _collider: CollisionShape3D = $Collider


func _ready() -> void:
	net_position = position
	_navigation.configure(body_size, get_rid())
	_collider.shape = _navigation.body_shape
	_collider.position.y = _navigation.radius + 0.04
	_body.build(body_color, body_size)
	if multiplayer.is_server():
		_rest_timer = randf_range(0.3, rest_time)
		_heading = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	else:
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = 0.12
		_sense_players()
	if _settling:
		velocity.y -= 18.0 * delta
		move_and_slide()
		if is_on_floor():
			# The collision sphere rests slightly below the visual foot origin.
			# Restore probe clearance before planning the next arc.
			global_position.y += 0.04
			_settling = false
			velocity = Vector3.ZERO
	elif _hopping:
		_hop_elapsed += delta
		net_phase = minf(_hop_elapsed / _hop_duration, 1.0)
		var next := FrogHop.arc_position(_hop_from, _hop_to, net_phase, _hop_height)
		var collision := move_and_collide(next - global_position)
		if collision != null:
			# A player/prop may move into a hop after it was planned. Stop at the
			# contact and fall onto the floor instead of passing through it.
			_finish_hop()
			_settling = true
		elif net_phase >= 1.0:
			_finish_hop()
	else:
		_rest_timer -= delta
		if _rest_timer <= 0.0:
			_start_hop()
	net_position = position


func _process(delta: float) -> void:
	var smoothing := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	if not multiplayer.is_server():
		position = position.lerp(net_position, smoothing)
	_body.rotation.y = lerp_angle(_body.rotation.y, net_yaw, smoothing)
	_body.animate(net_phase, delta)


func _sense_players() -> void:
	var nearest := CALM_RADIUS if _fleeing else ALERT_RADIUS
	_threat = Vector3.INF
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player == null or absf(player.global_position.y - global_position.y) > 2.5:
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance < nearest:
			nearest = distance
			_threat = player.global_position
	var was_fleeing := _fleeing
	_fleeing = _threat.is_finite()
	if _fleeing and not was_fleeing:
		_rest_timer = minf(_rest_timer, 0.08)


func _start_hop() -> void:
	var direction := _heading.rotated(Vector3.UP, randf_range(-0.65, 0.65))
	if _fleeing:
		direction = FrogHop.escape_direction(global_position, _threat, _heading)
	var distance := jump_distance * randf_range(0.75, 1.15) * (1.5 if _fleeing else 1.0)
	_hop_height = jump_height * (1.2 if _fleeing else 1.0)
	var hop := _navigation.find_hop(
		get_world_3d().direct_space_state,
		global_position,
		direction,
		distance,
		_hop_height,
		_threat
	)
	if hop.is_empty():
		_rest_timer = 0.25
		_heading = _heading.rotated(Vector3.UP, PI * 0.5)
		return
	_hop_from = global_position
	_hop_to = hop["target"]
	_heading = (_hop_to - _hop_from) * Vector3(1, 0, 1)
	_heading = _heading.normalized()
	net_yaw = FrogHop.facing_yaw(_hop_from, _hop_to)
	_hop_duration = jump_duration * (0.85 if _fleeing else 1.0)
	_hop_elapsed = 0.0
	net_phase = 0.0
	_hopping = true


func _finish_hop() -> void:
	_hopping = false
	net_phase = -1.0
	_rest_timer = randf_range(0.08, 0.18) if _fleeing else rest_time * randf_range(0.7, 1.3)
