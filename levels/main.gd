extends Node3D

## Main scene controller - manages overworld and arena transitions

@onready var navigator: CharacterBody3D = $Navigator
@onready var arena_container: Node3D = $ArenaContainer
@onready var level: Node3D = $Level  # Contains overworld - hidden during combat
@onready var lighting: Node3D = $Lighting  # Overworld lighting - hidden during combat


func _ready() -> void:
	Events.player_killed.connect(_on_player_killed)
	
	# Register references with GameManager
	_register_with_game_manager()


func _register_with_game_manager() -> void:
	# Wait a frame to ensure GameManager autoload is ready
	await get_tree().process_frame
	
	if GameManager:
		GameManager.register_navigator(navigator)
		GameManager.register_arena_container(arena_container)
		GameManager.register_overworld(level)
		GameManager.register_overworld_lighting(lighting)
		print("[Main] Registered navigator, arena container, overworld, and lighting with GameManager")
	else:
		push_error("[Main] GameManager autoload not found!")


func _process(_delta: float) -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _on_player_killed() -> void:
	get_tree().quit()


#func _start_windmill_animation() -> void:
	## Find AnimationPlayer in the windmill scene
	#var anim_player: AnimationPlayer = windmill.find_child("AnimationPlayer", true, false)
	#if anim_player:
		## Get the first animation and play it looped
		#var animations := anim_player.get_animation_list()
		#if animations.size() > 0:
			#var anim_name: String = animations[0]
			## Set the animation to loop
			#var animation := anim_player.get_animation(anim_name)
			#if animation:
				#animation.loop_mode = Animation.LOOP_LINEAR
			#anim_player.play(anim_name)
			#print("Playing windmill animation: ", anim_name)
		#else:
			#push_warning("Windmill has AnimationPlayer but no animations")
	#else:
		#push_warning("No AnimationPlayer found in Windmill")
