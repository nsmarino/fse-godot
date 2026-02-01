extends Node
class_name EnemyManager

@export var Spawns: Node
@export var Pawn: CharacterBody3D
@export var EnemyScene: PackedScene
@export var EnemyDataResource: EnemyData
@export var enemy_count: int = 3
@export var delay_between_attacks: float = 0.5  # Delay after one enemy finishes before next starts

@onready var group_resources: Node = $GroupResources

# Flag to track if configuration was applied before _ready
var _configured_before_ready: bool = false


## Configure enemy type and count at runtime (called by ArenaController)
func configure(enemy_data: EnemyData, count: int) -> void:
	EnemyDataResource = enemy_data
	enemy_count = count
	_configured_before_ready = true
	print("[EnemyManager] Configured: %s x%d" % [enemy_data.display_name if enemy_data else "null", count])

var active_enemies: Array[BaseEnemy] = []
var attack_queue: Array[BaseEnemy] = []  # Randomized order for this turn
var current_attacker: BaseEnemy = null
var is_enemy_turn: bool = false
var waiting_for_attack_complete: bool = false

# Reference to combat manager for time checking
var combat_manager: Node = null


# State storage for pause/resume
var stored_enemy_states: Dictionary = {}  # enemy -> state_name


func _ready() -> void:
	print("[EnemyManager] Initialized")
	
	# Connect to combat events
	Events.turn_intro_started.connect(_on_turn_intro_started)
	Events.turn_started.connect(_on_turn_started)
	Events.turn_ended.connect(_on_turn_ended)
	Events.combat_started.connect(_on_combat_started)
	Events.combat_paused.connect(_on_combat_paused)
	
	# Find combat manager for time checking
	await get_tree().process_frame
	combat_manager = get_tree().get_first_node_in_group("combat_manager")
	if not combat_manager:
		# Try to find by type
		combat_manager = get_node_or_null("/root/Arena/CombatManager")
	
	# Spawn enemies after a short delay
	_spawn_enemies()


func _spawn_enemies() -> void:
	print("[EnemyManager] Starting enemy spawn...")
	
	if not Spawns:
		push_error("[EnemyManager] ERROR: Spawns node not set!")
		return
	if not EnemyScene:
		push_error("[EnemyManager] ERROR: EnemyScene not set!")
		return
	
	print("[EnemyManager] Spawns node: %s" % Spawns.name)
	print("[EnemyManager] EnemyScene: %s" % EnemyScene.resource_path)
	print("[EnemyManager] Pawn reference: %s" % [Pawn.name if Pawn else "NULL"])
	
	var spawn_markers: Array[Node] = []
	for child in Spawns.get_children():
		if child is Marker3D:
			spawn_markers.append(child)
	
	print("[EnemyManager] Found %d spawn markers" % spawn_markers.size())
	
	# Shuffle spawn markers
	spawn_markers.shuffle()
	
	# Spawn enemies at random markers
	var count: int = min(enemy_count, spawn_markers.size())
	for i in range(count):
		var marker: Marker3D = spawn_markers[i] as Marker3D
		var enemy: BaseEnemy = EnemyScene.instantiate() as BaseEnemy
		
		if enemy:
			print("[EnemyManager] Spawning enemy %d at %s" % [i, marker.global_position])
			
			# Configure enemy
			if EnemyDataResource:
				enemy.enemy_data = EnemyDataResource
				print("[EnemyManager] Using enemy data: %s" % EnemyDataResource.display_name)
			
			enemy.set_player(Pawn)
			enemy.set_enemy_manager(self)
			
			# Connect to attack_cycle_complete signal
			enemy.attack_cycle_complete.connect(_on_enemy_attack_cycle_complete.bind(enemy))
			
			# Add to scene
			add_child(enemy)
			# Spawn at ground level (navmesh is at Y=0)
			enemy.global_position = Vector3(marker.global_position.x, 0.0, marker.global_position.z)
			
			active_enemies.append(enemy)
			print("[EnemyManager] Enemy spawned: %s" % enemy.name)
	
	print("[EnemyManager] Spawn complete. Total enemies: %d" % active_enemies.size())


func _on_combat_started() -> void:
	print("[EnemyManager] Combat started - setting all enemies to IDLE")
	for enemy in active_enemies:
		enemy.command_state("idle")


func _on_turn_intro_started(_is_player_turn: bool) -> void:
	# During turn intro, snap all non-staggered enemies to idle immediately
	print("[EnemyManager] Turn intro started - snapping non-staggered enemies to idle")
	is_enemy_turn = false
	attack_queue.clear()
	current_attacker = null
	waiting_for_attack_complete = false
	
	for enemy in active_enemies:
		if not enemy.is_staggered():
			enemy.command_state("idle")


func _on_turn_started(is_player_turn: bool) -> void:
	print("[EnemyManager] Turn started - is_player_turn: %s" % is_player_turn)
	is_enemy_turn = not is_player_turn
	
	if is_player_turn:
		_start_player_turn()
	else:
		_start_enemy_turn()


func _on_turn_ended(is_player_turn: bool) -> void:
	print("[EnemyManager] Turn ended - is_player_turn: %s" % is_player_turn)
	if not is_player_turn:
		_end_enemy_turn()


func _start_player_turn() -> void:
	print("[EnemyManager] Player turn - enemies enter LOCOMOTION_SLOW")
	is_enemy_turn = false
	attack_queue.clear()
	current_attacker = null
	waiting_for_attack_complete = false
	
	for enemy in active_enemies:
		# Don't change state of staggered enemies
		if not enemy.is_staggered():
			enemy.command_state("locomotion_slow")


func _start_enemy_turn() -> void:
	print("[EnemyManager] === ENEMY TURN START ===")
	is_enemy_turn = true
	waiting_for_attack_complete = false
	
	if active_enemies.is_empty():
		print("[EnemyManager] No active enemies!")
		return
	
	# Create randomized attack queue - only include non-staggered enemies
	attack_queue.clear()
	for enemy in active_enemies:
		if not enemy.is_staggered():
			attack_queue.append(enemy)
	attack_queue.shuffle()
	
	print("[EnemyManager] Attack queue (non-staggered): %s" % [attack_queue.map(func(e): return e.name)])
	
	# All non-staggered enemies start in idle while waiting
	for enemy in active_enemies:
		if not enemy.is_staggered():
			enemy.command_state("idle")
	
	# Start the first attack
	_start_next_attack()


func _end_enemy_turn() -> void:
	print("[EnemyManager] === ENEMY TURN END ===")
	is_enemy_turn = false
	attack_queue.clear()
	current_attacker = null
	waiting_for_attack_complete = false


func _start_next_attack() -> void:
	if not is_enemy_turn:
		print("[EnemyManager] Not enemy turn, skipping attack")
		return
	
	if attack_queue.is_empty():
		print("[EnemyManager] Attack queue empty - all enemies have attacked")
		return
	
	# Check if we have enough time for the next attack
	var time_remaining: float = _get_turn_time_remaining()
	var next_enemy: BaseEnemy = attack_queue[0]
	var attack_duration: float = _get_enemy_attack_duration(next_enemy)
	
	print("[EnemyManager] Time check: %.1fs remaining, attack needs %.1fs" % [time_remaining, attack_duration])
	
	if time_remaining < attack_duration:
		print("[EnemyManager] Not enough time for attack - remaining enemies stay idle")
		attack_queue.clear()
		return
	
	# Pop the next enemy from queue and start their attack
	current_attacker = attack_queue.pop_front()
	waiting_for_attack_complete = true
	
	print("[EnemyManager] Starting attack: %s" % current_attacker.name)
	current_attacker.command_state("pursue")


func _on_enemy_attack_cycle_complete(enemy: BaseEnemy) -> void:
	print("[EnemyManager] Enemy %s completed attack cycle" % enemy.name)
	
	if enemy != current_attacker:
		print("[EnemyManager] WARNING: Received complete from non-current attacker")
		return
	
	if not is_enemy_turn:
		print("[EnemyManager] Turn ended, ignoring")
		return
	
	waiting_for_attack_complete = false
	current_attacker = null
	
	# Delay before starting next attack
	if not attack_queue.is_empty():
		print("[EnemyManager] Waiting %.1fs before next attack" % delay_between_attacks)
		await get_tree().create_timer(delay_between_attacks).timeout
		
		# Check if still enemy turn after delay
		if is_enemy_turn:
			_start_next_attack()


func _get_turn_time_remaining() -> float:
	if combat_manager and combat_manager.has_method("get_turn_time_remaining"):
		return combat_manager.get_turn_time_remaining()
	elif combat_manager and "turn_timer" in combat_manager:
		return combat_manager.turn_timer
	return 999.0  # Default to allowing attacks if we can't check


func _get_enemy_attack_duration(enemy: BaseEnemy) -> float:
	# Get the attack state from the enemy's state machine
	if enemy.state_machine:
		var attack_state: Node = enemy.state_machine.get_node_or_null("Attack")
		if attack_state and "fallback_duration" in attack_state:
			return attack_state.fallback_duration
	return 1.0  # Default estimate


func on_enemy_died(enemy: BaseEnemy) -> void:
	active_enemies.erase(enemy)
	attack_queue.erase(enemy)
	
	if current_attacker == enemy:
		current_attacker = null
		waiting_for_attack_complete = false
		# Start next attack if there are more
		if is_enemy_turn and not attack_queue.is_empty():
			_start_next_attack()
	
	# Disconnect signal
	if enemy.attack_cycle_complete.is_connected(_on_enemy_attack_cycle_complete):
		enemy.attack_cycle_complete.disconnect(_on_enemy_attack_cycle_complete.bind(enemy))
	
	print("[EnemyManager] Enemy died. %d remaining" % active_enemies.size())


func get_active_enemy_count() -> int:
	return active_enemies.size()


func get_closest_enemy_to(position: Vector3) -> BaseEnemy:
	var closest: BaseEnemy = null
	var closest_dist: float = INF
	
	for enemy in active_enemies:
		var dist: float = enemy.global_position.distance_to(position)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy
	
	return closest


func command_all_enemies(state_name: String) -> void:
	print("[EnemyManager] Commanding all enemies to: %s" % state_name)
	for enemy in active_enemies:
		enemy.command_state(state_name)


func on_enemy_staggered(enemy: BaseEnemy) -> void:
	print("[EnemyManager] Enemy %s became staggered" % enemy.name)
	
	# Remove from attack queue if present
	attack_queue.erase(enemy)
	
	# If this was the current attacker, handle it
	if current_attacker == enemy:
		current_attacker = null
		waiting_for_attack_complete = false
		if is_enemy_turn and not attack_queue.is_empty():
			_start_next_attack()
	
	# Check if all enemies are now staggered
	if are_all_enemies_staggered():
		print("[EnemyManager] === ALL ENEMIES STAGGERED! ===")
		Events.group_all_staggered.emit(false)  # false = enemy group


func are_all_enemies_staggered() -> bool:
	if active_enemies.is_empty():
		return false
	
	for enemy in active_enemies:
		if not enemy.is_staggered():
			return false
	return true


func get_non_staggered_enemies() -> Array[BaseEnemy]:
	var result: Array[BaseEnemy] = []
	for enemy in active_enemies:
		if not enemy.is_staggered():
			result.append(enemy)
	return result


func _on_combat_paused(paused: bool) -> void:
	if paused:
		# Store current states and freeze all non-staggered enemies
		stored_enemy_states.clear()
		for enemy in active_enemies:
			if not enemy.is_staggered():
				stored_enemy_states[enemy] = enemy.get_current_state_name()
				enemy.command_state("idle")
		print("[EnemyManager] Combat paused - enemies frozen")
	else:
		# Restore previous states
		for enemy in stored_enemy_states:
			if is_instance_valid(enemy) and not enemy.is_staggered():
				enemy.command_state(stored_enemy_states[enemy])
		stored_enemy_states.clear()
		print("[EnemyManager] Combat resumed - enemies unfrozen")
