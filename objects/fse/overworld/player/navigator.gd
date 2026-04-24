extends CharacterBody3D

## Exploration character controller with third-person camera
## Movement is relative to camera direction

@export_category("Movement")
@export var move_speed: float = 12.0
@export var vertical_speed: float = 8.0  # Fly mode vertical speed

@export_category("Gravity Mode")
@export var use_gravity: bool = false  # Toggle in Inspector
@export var gravity_strength: float = 30.0
@export var jump_velocity: float = 10.0
@export var air_control: float = 0.3  # Movement control while airborne (0-1)

@export_category("Camera")
@export var mouse_sensitivity: float = 0.003
@export var gamepad_look_sensitivity: float = 3.0

@export_category("Combat")
@export var default_weapon_scene: PackedScene
@export var aim_ray_length: float = 1000.0

# Camera spring arm - add as child of this CharacterBody3D
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var elena: Node3D = $elena  # Player model - faces camera when moving

var camera_rotation := Vector2.ZERO  # x = yaw, y = pitch
var pitch_limit := deg_to_rad(89.0)
var weapon_socket: Node3D = null
var equipped_weapon: Node3D = null


func _ready() -> void:
	# Capture mouse for camera control
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	weapon_socket = _resolve_weapon_socket()
	_equip_default_weapon()


func _input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_rotation.x -= event.relative.x * mouse_sensitivity
		camera_rotation.y -= event.relative.y * mouse_sensitivity
		camera_rotation.y = clamp(camera_rotation.y, -pitch_limit, pitch_limit)
	
	# Toggle mouse capture with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	_handle_camera_input(delta)
	_handle_combat_input()
	
	if use_gravity:
		_process_gravity_movement(delta)
	else:
		_process_fly_movement(delta)
	
	move_and_slide()
	_update_elena_facing()


func _handle_camera_input(delta: float) -> void:
	# Gamepad camera look (right stick)
	var look_input := Vector2.ZERO
	look_input.x = Input.get_axis("LookLeft", "LookRight")
	look_input.y = Input.get_axis("LookUp", "LookDown")
	
	if look_input.length() > 0.1:
		camera_rotation.x -= look_input.x * gamepad_look_sensitivity * delta
		camera_rotation.y -= look_input.y * gamepad_look_sensitivity * delta
		camera_rotation.y = clamp(camera_rotation.y, -pitch_limit, pitch_limit)
	
	# Apply camera rotation to spring arm
	spring_arm.rotation.y = camera_rotation.x
	spring_arm.rotation.x = camera_rotation.y


func _handle_combat_input() -> void:
	if _is_dialogue_locked():
		return
	if not equipped_weapon:
		return

	if Input.is_action_pressed("CombatAttack"):
		equipped_weapon.try_fire(_get_camera_aim_direction())


func _get_movement_direction() -> Vector3:
	if _is_dialogue_locked():
		return Vector3.ZERO
	
	# Movement input (left stick / WASD)
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("MoveLeft", "MoveRight")
	input_dir.y = Input.get_axis("MoveForward", "MoveBackward")
	
	# Get camera's forward and right vectors (flattened for horizontal movement)
	var cam_basis := spring_arm.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	# Calculate movement direction
	var move_dir := Vector3.ZERO
	move_dir += forward * -input_dir.y  # Forward/backward
	move_dir += right * input_dir.x      # Left/right
	
	if move_dir.length() > 0:
		move_dir = move_dir.normalized()
	
	return move_dir


func _process_fly_movement(_delta: float) -> void:
	var move_dir := _get_movement_direction()
	var vertical_input := 0.0 if _is_dialogue_locked() else Input.get_axis("FlyDown", "FlyUp")
	
	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
	velocity.y = vertical_input * vertical_speed


func _process_gravity_movement(delta: float) -> void:
	var move_dir := _get_movement_direction()
	var on_floor := is_on_floor()
	
	# Apply gravity
	if not on_floor:
		velocity.y -= gravity_strength * delta
	
	# Jump (use FlyUp action or Jump action)
	var wants_jump := false
	if not _is_dialogue_locked():
		wants_jump = Input.is_action_just_pressed("FlyUp") or Input.is_action_just_pressed("Jump")
	if wants_jump and on_floor:
		velocity.y = jump_velocity
	
	# Horizontal movement (reduced control in air)
	var control := 1.0 if on_floor else air_control
	var target_velocity_x := move_dir.x * move_speed
	var target_velocity_z := move_dir.z * move_speed
	
	velocity.x = lerp(velocity.x, target_velocity_x, control)
	velocity.z = lerp(velocity.z, target_velocity_z, control)


func _update_elena_facing() -> void:
	# Rotate player model to face movement direction only when in motion
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.5:
		return

	var move_dir := Vector3(velocity.x, 0, velocity.z).normalized()
	if move_dir.length_squared() < 0.01:
		return

	elena.rotation.y = atan2(move_dir.x, move_dir.z)


func _is_dialogue_locked() -> bool:
	return Events and Events.is_dialogue_active


func _equip_default_weapon() -> void:
	if not default_weapon_scene:
		push_warning("[Navigator] No default weapon scene assigned.")
		return
	if not weapon_socket:
		push_error("[Navigator] WeaponSocket not found in navigator scene.")
		return

	var inst: Node = default_weapon_scene.instantiate()
	if not inst.has_method("try_fire"):
		push_error("[Navigator] default_weapon_scene root must expose try_fire().")
		return
	if not inst is Node3D:
		push_error("[Navigator] default_weapon_scene root must inherit Node3D.")
		return

	equipped_weapon = inst as Node3D
	weapon_socket.add_child(equipped_weapon)
	equipped_weapon.owner_character = self


func _resolve_weapon_socket() -> Node3D:
	if elena and elena.has_node("WeaponSocket"):
		var socket: Node = elena.get_node("WeaponSocket")
		if socket is Node3D:
			return socket as Node3D

	if has_node("WeaponSocket"):
		var root_socket: Node = get_node("WeaponSocket")
		if root_socket is Node3D:
			return root_socket as Node3D

	return null


func _get_camera_aim_direction() -> Vector3:
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var target: Vector3 = origin + forward * aim_ray_length

	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		target = result["position"]

	var muzzle_origin: Vector3 = weapon_socket.global_position if weapon_socket else global_position + Vector3(0, 1.5, 0)
	var aim_direction: Vector3 = target - muzzle_origin
	if aim_direction.length_squared() < 0.0001:
		return forward
	return aim_direction.normalized()


## Stub for FSE enemy melee; expand with HP if you add a combat resource to the navigator.
func receive_attack(_damage: int) -> void:
	pass
