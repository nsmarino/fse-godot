extends CharacterBody3D

@export var dialogue_config: DialogueConfig  ## Configuration for the dialogue encounter
@export var one_shot: bool = true  ## If true, trigger can only activate once
@export var trigger_delay: float = 0.0  ## Optional delay before dialogue starts

@onready var interaction_area: Area3D = $InteractionArea

var has_triggered: bool = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
