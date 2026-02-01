extends BaseAIState
class_name AIState

## State for combat enemies
## Extends BaseAIState with combat-specific helpers and references

@export var animation: String = ""

# Combat-specific references (set by BaseEnemy)
var player: CharacterBody3D
var character: CharacterBody3D
var animator: AnimationPlayer
var spawn_point: Vector3
var nav_agent: NavigationAgent3D
var attack_area: Area3D
var enemy_data: EnemyData
var enemy_manager: Node


#region Lifecycle Overrides

## Override on_enter to emit combat event
func on_enter() -> void:
	Events.enemy_state_changed.emit(character, state_name)

#endregion


#region Combat Helper Methods

## Get distance to the player
func get_distance_to_player() -> float:
	if player:
		return character.global_position.distance_to(player.global_position)
	return 999.0


## Navigate toward a target position using navigation (with avoidance)
func navigate_to(target: Vector3, speed: float, delta: float) -> void:
	# Project target to ground level (navmesh is typically at Y=0)
	var ground_target: Vector3 = Vector3(target.x, character.global_position.y, target.z)
	var current_pos: Vector3 = character.global_position
	
	# Check if we're already close enough
	var direct_distance: float = current_pos.distance_to(ground_target)
	if direct_distance < 0.5:
		stop_with_avoidance()
		return
	
	var direction: Vector3
	var use_direct_movement: bool = false
	
	# Try navigation if we have an agent
	if nav_agent:
		nav_agent.target_position = ground_target
		
		# Check if navigation is viable
		if nav_agent.is_target_reachable() and not nav_agent.is_navigation_finished():
			# Use navmesh pathfinding
			var next_pos: Vector3 = nav_agent.get_next_path_position()
			direction = (next_pos - current_pos)
			direction.y = 0
			
			if direction.length() < 0.1:
				# Waypoint too close, use direct movement
				use_direct_movement = true
			else:
				direction = direction.normalized()
		else:
			use_direct_movement = true
			if Engine.get_physics_frames() % 30 == 0:
				print("[AIState:%s] Nav unavailable, using direct movement. Reachable=%s, Finished=%s" % [
					state_name, nav_agent.is_target_reachable(), nav_agent.is_navigation_finished()
				])
	else:
		use_direct_movement = true
	
	# Fallback: direct movement toward target
	if use_direct_movement:
		direction = (ground_target - current_pos)
		direction.y = 0
		if direction.length() > 0.1:
			direction = direction.normalized()
		else:
			stop_with_avoidance()
			return
		
		if Engine.get_physics_frames() % 30 == 0:
			print("[AIState:%s] DIRECT: pos=%s -> target=%s, dist=%.2f" % [
				state_name, current_pos, ground_target, direct_distance
			])
	
	# Calculate desired velocity
	var desired_velocity: Vector3 = direction * speed
	
	# Rotate to face movement direction
	var target_rotation: float = atan2(direction.x, direction.z)
	character.rotation.y = lerp_angle(character.rotation.y, target_rotation, delta * 10.0)
	
	# Move with avoidance
	move_with_avoidance(desired_velocity)


## Move away from a target position (with avoidance)
func move_away_from(target: Vector3, speed: float, delta: float) -> void:
	var direction: Vector3 = (character.global_position - target).normalized()
	direction.y = 0
	
	if direction.length() < 0.1:
		stop_with_avoidance()
		return
	
	# Rotate to face away from target
	var target_rotation: float = atan2(direction.x, direction.z)
	character.rotation.y = lerp_angle(character.rotation.y, target_rotation, delta * 10.0)
	
	# Move away with avoidance
	var desired_velocity: Vector3 = direction * speed
	move_with_avoidance(desired_velocity)


## Face the player
func face_player(delta: float) -> void:
	if player:
		var direction: Vector3 = (player.global_position - character.global_position).normalized()
		direction.y = 0
		if direction.length() > 0.1:
			var target_rotation: float = atan2(direction.x, direction.z)
			character.rotation.y = lerp_angle(character.rotation.y, target_rotation, delta * 10.0)


## Move with avoidance (uses NavigationAgent3D's RVO avoidance)
## Sets the desired velocity and lets the avoidance system compute a safe velocity
## The actual movement happens in BaseEnemy._on_velocity_computed()
func move_with_avoidance(desired_velocity: Vector3) -> void:
	if nav_agent and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(desired_velocity)
	else:
		# Fallback if no avoidance
		character.velocity = desired_velocity
		character.move_and_slide()


## Stop with avoidance (still participates in avoidance calculations)
func stop_with_avoidance() -> void:
	if nav_agent and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(Vector3.ZERO)
	else:
		character.velocity = Vector3.ZERO
		character.move_and_slide()

#endregion
