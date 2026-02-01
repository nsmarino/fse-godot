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

# Scene references (registered by main scene)
var navigator: CharacterBody3D = null
var arena_container: Node = null
var overworld_root: Node = null
var overworld_lighting: Node = null

# Current arena instance
var current_arena: Node3D = null

# Stored state for scene tree removal/restoration
var _navigator_parent: Node = null
var _overworld_parent: Node = null
var _lighting_parent: Node = null
var _stored_navigator_position: Vector3 = Vector3.ZERO
var _stored_navigator_rotation: Vector3 = Vector3.ZERO

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


## Register the overworld root node (will be hidden during combat)
func register_overworld(overworld: Node) -> void:
	overworld_root = overworld
	print("[GameManager] Overworld registered: %s" % overworld.name)


## Register the overworld lighting (will be hidden during combat)
func register_overworld_lighting(lighting: Node) -> void:
	overworld_lighting = lighting
	print("[GameManager] Overworld lighting registered: %s" % lighting.name)


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
	
	# Store navigator state before removal
	_store_navigator_state()
	
	# Remove navigator from scene tree (disables all processing, physics, collisions)
	_remove_navigator_from_tree()
	
	# Remove overworld from scene tree (disables all processing, physics, collisions)
	_remove_overworld_from_tree()
	
	# Defer arena spawn to ensure removals complete first
	call_deferred("_spawn_arena", config)
	call_deferred("_finalize_combat_start")


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
		_stored_navigator_position = navigator.global_position
		_stored_navigator_rotation = navigator.rotation
		print("[GameManager] Stored navigator position: %s" % _stored_navigator_position)


func _remove_navigator_from_tree() -> void:
	if navigator and navigator.get_parent():
		# Store parent reference for restoration
		_navigator_parent = navigator.get_parent()
		
		# Disable camera before removal
		var camera: Camera3D = navigator.get_node_or_null("SpringArm3D/Camera3D")
		if camera:
			camera.current = false
		
		# Remove from tree using call_deferred to avoid physics callback issues
		_navigator_parent.call_deferred("remove_child", navigator)
		print("[GameManager] Navigator removal deferred")


func _restore_navigator_to_tree() -> void:
	if navigator and _navigator_parent:
		# Re-add to tree
		_navigator_parent.add_child(navigator)
		
		# Restore position
		navigator.global_position = _stored_navigator_position
		navigator.rotation = _stored_navigator_rotation
		
		# Re-enable the navigator's camera
		var camera: Camera3D = navigator.get_node_or_null("SpringArm3D/Camera3D")
		if camera:
			camera.current = true
		
		# Recapture mouse for navigation
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		print("[GameManager] Navigator restored to scene tree at: %s" % navigator.global_position)


func _remove_overworld_from_tree() -> void:
	# Remove overworld root (Level node containing overworld)
	if overworld_root and overworld_root.get_parent():
		_overworld_parent = overworld_root.get_parent()
		# Use call_deferred to avoid physics callback issues
		_overworld_parent.call_deferred("remove_child", overworld_root)
		print("[GameManager] Overworld removal deferred")
	
	# Remove overworld lighting
	if overworld_lighting and overworld_lighting.get_parent():
		_lighting_parent = overworld_lighting.get_parent()
		# Use call_deferred to avoid physics callback issues
		_lighting_parent.call_deferred("remove_child", overworld_lighting)
		print("[GameManager] Overworld lighting removal deferred")


func _restore_overworld_to_tree() -> void:
	# Restore overworld root
	if overworld_root and _overworld_parent:
		_overworld_parent.add_child(overworld_root)
		print("[GameManager] Overworld restored to scene tree")
	
	# Restore overworld lighting
	if overworld_lighting and _lighting_parent:
		_lighting_parent.add_child(overworld_lighting)
		print("[GameManager] Overworld lighting restored to scene tree")


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


func _finalize_combat_start() -> void:
	current_state = GameState.COMBAT
	print("[GameManager] Combat started - state: COMBAT")


func _cleanup_arena() -> void:
	if current_arena and is_instance_valid(current_arena):
		current_arena.queue_free()
		current_arena = null
		print("[GameManager] Arena cleaned up")


func _return_to_overworld() -> void:
	# Restore overworld to scene tree
	_restore_overworld_to_tree()
	
	# Restore navigator to scene tree
	_restore_navigator_to_tree()
	
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
