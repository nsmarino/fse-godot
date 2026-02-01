extends Node3D
## Arena controller - wires up combat system components

@export var arena_config: ArenaConfig  ## Configuration set by GameManager before adding to scene

@onready var combat_manager: Node = $CombatManager
@onready var pawn: CharacterBody3D = $Pawn
@onready var combat_hud: CanvasLayer = $HUD/CombatHud
@onready var enemy_group: Node = $EnemyGroup

# Level structure references
@onready var nav_region: NavigationRegion3D = $Level/Ground/NavigationRegion3D
@onready var floor_mesh: MeshInstance3D = $Level/Ground/NavigationRegion3D/FloorBody/FloorMesh
@onready var directional_light: DirectionalLight3D = $Lighting/DirectionalLight3D


func _ready() -> void:
	print("Arena controller initializing...")
	
	# Wait for all nodes to be ready
	await get_tree().process_frame
	
	# Apply arena configuration if provided
	if arena_config:
		_apply_arena_config()
	
	# Wire up references
	_setup_connections()
	
	print("Arena controller ready - combat can begin")


## Set arena configuration (called by GameManager before adding to tree)
func set_arena_config(config: ArenaConfig) -> void:
	arena_config = config


## Apply arena configuration to the scene
func _apply_arena_config() -> void:
	print("[ArenaController] Applying arena config...")
	
	# Apply custom ground mesh if provided
	if arena_config.ground_mesh and floor_mesh:
		floor_mesh.mesh = arena_config.ground_mesh
		print("[ArenaController] Applied custom ground mesh")
	
	# Apply custom navigation mesh if provided
	if arena_config.nav_mesh and nav_region:
		nav_region.navigation_mesh = arena_config.nav_mesh
		print("[ArenaController] Applied custom nav mesh")
	
	# Configure enemy group
	if arena_config.enemy_data and enemy_group:
		if enemy_group.has_method("configure"):
			enemy_group.configure(arena_config.enemy_data, arena_config.enemy_count)
			print("[ArenaController] Configured enemy group: %s x%d" % [arena_config.enemy_data.display_name, arena_config.enemy_count])
	
	# Apply lighting if custom
	if arena_config.use_custom_lighting and directional_light:
		directional_light.light_color = arena_config.light_color
		directional_light.light_energy = arena_config.light_energy
		print("[ArenaController] Applied custom lighting")


func _setup_connections() -> void:
	# Give CombatManager references to resource nodes
	if combat_manager:
		combat_manager.player_resources = pawn.group_resources
		combat_manager.enemy_resources = enemy_group.group_resources
	
	# Give Pawn reference to enemy group
	if pawn:
		pawn.set_enemy_group(enemy_group)
	
	# Give HUD reference to player state machine
	if combat_hud and pawn:
		combat_hud.set_player_state_machine(pawn.state_machine)
		# Initialize party portraits
		if combat_hud.has_method("initialize_party_portraits"):
			combat_hud.initialize_party_portraits(pawn)
	
	# Make sure enemy group has the pawn reference
	if enemy_group and pawn:
		enemy_group.Pawn = pawn
