extends Node

## Central game state manager
## Controls transitions between overworld exploration and arena combat

enum GameState {
	OVERWORLD,
	TRANSITIONING,
	COMBAT,
}

# Current game state
var current_state: GameState = GameState.OVERWORLD

# Scene references
var navigator: CharacterBody3D = null
var arena_container: Node = null
var current_arena: Node3D = null

# Stored navigator state for returning from combat
var stored_navigator_position: Vector3 = Vector3.ZERO
var stored_navigator_rotation: Vector3 = Vector3.ZERO

# Arena scene to instantiate
const ARENA_SCENE_PATH: String = "res://levels/combat/arena.tscn"
var arena_scene: PackedScene = null


func _ready() -> void:
	print("[GameManager] Initialized")
	
	# Preload arena scene
	arena_scene = load(ARENA_SCENE_PATH)
	
	# Connect to combat end signal
	Events.combat_ended.connect(_on_combat_ended)


## Register the navigator for state management
func register_navigator(nav: CharacterBody3D) -> void:
	navigator = nav
	print("[GameManager] Navigator registered: %s" % nav.name)


## Register the container node where arena instances will be added
func register_arena_container(container: Node) -> void:
	arena_container = container
	print("[GameManager] Arena container registered: %s" % container.name)


## Start a combat encounter with the given arena configuration
func start_combat(config: ArenaConfig) -> void:
	if current_state != GameState.OVERWORLD:
		push_warning("[GameManager] Cannot start combat - not in OVERWORLD state")
		return
	
	if not navigator:
		push_error("[GameManager] Cannot start combat - navigator not registered")
		return
	
	if not arena_container:
		push_error("[GameManager] Cannot start combat - arena container not registered")
		return
	
	print("[GameManager] === STARTING COMBAT ===")
	current_state = GameState.TRANSITIONING
	
	# Store navigator state
	_store_navigator_state()
	
	# Disable navigator
	_disable_navigator()
	
	# Instantiate and configure arena
	_spawn_arena(config)
	
	# Transition to combat state
	current_state = GameState.COMBAT
	print("[GameManager] Combat started - state: COMBAT")


## Called when combat ends (victory or defeat)
func _on_combat_ended(player_won: bool) -> void:
	if current_state != GameState.COMBAT:
		return
	
	print("[GameManager] === COMBAT ENDED === Player won: %s" % player_won)
	current_state = GameState.TRANSITIONING
	
	# Emit signal for any listeners
	Events.returning_to_overworld.emit(player_won)
	
	# Clean up arena
	_cleanup_arena()
	
	# Handle result
	if player_won:
		_return_to_overworld()
	else:
		_handle_defeat()


func _store_navigator_state() -> void:
	if navigator:
		stored_navigator_position = navigator.global_position
		stored_navigator_rotation = navigator.rotation
		print("[GameManager] Stored navigator position: %s" % stored_navigator_position)


func _disable_navigator() -> void:
	if navigator:
		# Disable processing and hide
		navigator.set_physics_process(false)
		navigator.set_process(false)
		navigator.set_process_input(false)
		navigator.visible = false
		
		# Disable the navigator's camera
		var camera: Camera3D = navigator.get_node_or_null("SpringArm3D/Camera3D")
		if camera:
			camera.current = false
		
		print("[GameManager] Navigator disabled")


func _enable_navigator() -> void:
	if navigator:
		# Restore position
		navigator.global_position = stored_navigator_position
		navigator.rotation = stored_navigator_rotation
		
		# Re-enable processing
		navigator.set_physics_process(true)
		navigator.set_process(true)
		navigator.set_process_input(true)
		navigator.visible = true
		
		# Re-enable the navigator's camera
		var camera: Camera3D = navigator.get_node_or_null("SpringArm3D/Camera3D")
		if camera:
			camera.current = true
		
		# Recapture mouse for navigation
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		print("[GameManager] Navigator enabled at: %s" % navigator.global_position)


func _spawn_arena(config: ArenaConfig) -> void:
	if not arena_scene:
		push_error("[GameManager] Arena scene not loaded!")
		return
	
	current_arena = arena_scene.instantiate()
	
	# Configure the arena before adding to tree
	var arena_controller: Node = current_arena
	if arena_controller.has_method("set_arena_config"):
		arena_controller.set_arena_config(config)
	elif "arena_config" in arena_controller:
		arena_controller.arena_config = config
	
	# Add to container
	arena_container.add_child(current_arena)
	print("[GameManager] Arena spawned and configured")


func _cleanup_arena() -> void:
	if current_arena and is_instance_valid(current_arena):
		current_arena.queue_free()
		current_arena = null
		print("[GameManager] Arena cleaned up")


func _return_to_overworld() -> void:
	_enable_navigator()
	current_state = GameState.OVERWORLD
	print("[GameManager] Returned to overworld - state: OVERWORLD")


func _handle_defeat() -> void:
	# For now, just return to overworld
	# This can be expanded to show game over screen, respawn at checkpoint, etc.
	print("[GameManager] Player defeated - returning to overworld")
	_return_to_overworld()


## Get current game state
func get_state() -> GameState:
	return current_state


## Check if currently in combat
func is_in_combat() -> bool:
	return current_state == GameState.COMBAT


## Check if currently in overworld
func is_in_overworld() -> bool:
	return current_state == GameState.OVERWORLD
