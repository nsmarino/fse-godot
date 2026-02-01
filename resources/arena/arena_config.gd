extends Resource
class_name ArenaConfig

## Configuration resource for arena encounters
## Defines the visual appearance and enemy composition of a combat arena

@export_category("Ground & Navigation")
@export var ground_mesh: Mesh  ## Custom ground mesh (uses default if null)
@export var nav_mesh: NavigationMesh  ## Custom navigation mesh (uses default if null)
@export var ground_size: Vector2 = Vector2(40, 40)  ## Size of the ground plane

@export_category("Enemy Configuration")
@export var enemy_data: EnemyData  ## Enemy type to spawn
@export var enemy_count: int = 3  ## Number of enemies to spawn

@export_category("Lighting")
@export var use_custom_lighting: bool = false
@export var light_color: Color = Color(1.0, 0.99, 0.87, 1.0)
@export var light_energy: float = 1.0
