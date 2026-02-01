extends BaseStateMachine
class_name EnemyStateMachine

## State machine for combat enemies
## Extends BaseStateMachine with enemy-specific functionality

# Alias for backward compatibility - owner_node is the character
var character: CharacterBody3D:
	get:
		return owner_node as CharacterBody3D
	set(value):
		owner_node = value


## Override to collect EnemyAIState children specifically
func _collect_states() -> void:
	for child in get_children():
		if child is AIState:
			states[child.state_name] = child
			# Give state references
			child.state_machine = self
			child.owner_node = owner_node
