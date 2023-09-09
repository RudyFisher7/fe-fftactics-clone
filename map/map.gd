class_name Map
extends Node3D


@export var grid_map: GridMap = null


var _a_star_3d := AStar3D.new()


func _ready() -> void:
	pass


func _build_graph() -> void:
	var used_cells: Array[Vector3i] = grid_map.get_used_cells()
	
#	for cell in used_cells:
#		_a_star_3d.add_point()
