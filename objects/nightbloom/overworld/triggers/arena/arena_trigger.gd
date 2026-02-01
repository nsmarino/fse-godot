extends CharacterBody3D
class_name ArenaTrigger

## Arena Trigger - initiates combat when the navigator enters its interaction area

@export var arena_config: ArenaConfig  ## Configuration for the arena encounter
@export var one_shot: bool = true  ## If true, trigger can only activate once
@export var trigger_delay: float = 0.0  ## Optional delay before combat starts

@onready var interaction_area: Area3D = $InteractionArea

var has_triggered: bool = false


func _ready() -> void:
	# Connect to the interaction area's body_entered signal
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		print("[ArenaTrigger] Ready - waiting for navigator collision")
	else:
		push_error("[ArenaTrigger] InteractionArea not found!")


func _on_body_entered(body: Node3D) -> void:
	# Check if already triggered (for one-shot triggers)
	if one_shot and has_triggered:
		return
	
	# Check if the body is the navigator (player in overworld)
	if not _is_navigator(body):
		return
	
	print("[ArenaTrigger] Navigator entered trigger area!")
	_initiate_combat()


func _is_navigator(body: Node3D) -> bool:
	# Check if this is the navigator/player character
	# The navigator is a CharacterBody3D with the navigator.gd script
	if body is CharacterBody3D:
		# Check by script or by checking for characteristic nodes
		if body.has_node("SpringArm3D") and body.has_node("SpringArm3D/Camera3D"):
			return true
		# Also check if it's registered as a navigator
		if body.get_script() and "navigator" in body.get_script().resource_path.to_lower():
			return true
	return false


func _initiate_combat() -> void:
	has_triggered = true
	
	# Validate arena config
	if not arena_config:
		push_warning("[ArenaTrigger] No arena_config set - using default arena")
	
	# Optional delay before combat
	if trigger_delay > 0:
		await get_tree().create_timer(trigger_delay).timeout
	
	# Request combat from GameManager
	if GameManager:
		print("[ArenaTrigger] Requesting combat from GameManager")
		GameManager.start_combat(arena_config)
	else:
		push_error("[ArenaTrigger] GameManager autoload not found!")


## Reset the trigger (for non-one-shot or manual reset)
func reset_trigger() -> void:
	has_triggered = false
	print("[ArenaTrigger] Trigger reset")


## Check if this trigger has been activated
func is_triggered() -> bool:
	return has_triggered
