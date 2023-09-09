class_name GameBoard3D
extends GridMap
################################################################################
## Defines a truly 3-dimentional grid map with its own graphs for grid-based
## traversal.
################################################################################


## Defines bitfield constants for specifying which underlying AStar3D graph to
## access.
## Current implementation treats them as mutually exlusive, but bitfield allows
## for more flexibility if later desired.
const MASTER: int = 0xFF
const USED_CELLS: int = 0x00
const LAND: int = 0x01
const LAND_AND_AIR: int = 0x02
const WATER: int = 0x04
const WATER_SURFACE: int = 0x08


@export_node_path("MultiMeshInstance3D") var path_to_multimesh_instance: NodePath


var _size: int = 16
var size: int:
	get:
		return _size


## Graphs.
var _a_star_master: AStar3D = AStar3D.new()
var _a_star_land: AStar3D = AStar3D.new()

## A graph only containing all used cells of this GridMap object.
## This is typically only used for checking if a cell is being used by this
## GridMap, rather than for traversal.
## Sometimes it is useful to be able to look a certain cell by a hash ID.
var _a_star_used_cells: AStar3D = AStar3D.new()


var _graphs: Dictionary = {
	MASTER:_a_star_master,
	USED_CELLS:_a_star_used_cells,
	LAND:_a_star_land,
	# TODO: the below three
	LAND_AND_AIR:_a_star_master,
	WATER:_a_star_master,
	WATER_SURFACE:_a_star_master,
}


## Comparison Callable for sorting Arrays of Vector3is in reverse order base on
## their y member.
var _reverse_sort_on_y: Callable = func(a: Vector3i, b: Vector3i): 
	return a.y > b.y


## Comparison Callable for sorting Arrays of Vector3is in  order base on their y
## member.
var _sort_on_y: Callable = func(a: Vector3i, b: Vector3i): 
	return a.y < b.y


@export_group("Required Nodes")
@onready var _multimesh_instance: MultiMeshInstance3D = get_node(path_to_multimesh_instance)


func _ready() -> void:
	_calculate_size()
	_build_all_graphs()
	_connect_cells()
	show_cells(true)
#	_register_with_interface()


## Gets a path of Vector3s from from to to.
## This path will be limited to land only.
func get_land_path(from: Vector3i, to: Vector3i) -> PackedVector3Array:
	return _a_star_land.get_point_path(_hash(from), _hash(to))


## Gets a path of Vector3s from from to to.
## This path will not have any limitations.
func get_master_path(from: Vector3i, to: Vector3i) -> PackedVector3Array:
	return _a_star_master.get_point_path(_hash(from), _hash(to))


## Sets whether the given cell should be disabled for pathfinding in all of this
## map's graphs.
## Returns the number of graphs the cell was disabled/enabled in.
func set_cell_disabled(cell: Vector3i, disabled: bool = true) -> int:
	var result: int = 0
	var id: int = _hash(cell)
	if !_a_star_master.is_point_disabled(id):
		_a_star_master.set_point_disabled(id, disabled)
		result += 1
	if !_a_star_land.is_point_disabled(id):
		_a_star_land.set_point_disabled(id, disabled)
		result += 1
	return result


func get_cell_path_in_range(from: Vector3i, to: Vector3i, cell_range: int, graph_bitfield: int = MASTER) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var id_path: PackedInt64Array = PackedInt64Array()
	var a_star: AStar3D = _graphs[graph_bitfield]
	
	id_path = a_star.get_id_path(_hash(from), _hash(to))
	if !id_path.is_empty():
		result.append(a_star.get_point_position(id_path[0]))
		var range_accumulator: int = 0
		for i in range(1, id_path.size()):
			range_accumulator += int(a_star.get_point_weight_scale(id_path[i]))
			if range_accumulator <= cell_range:
				result.append(a_star.get_point_position(id_path[i]))
	return result


## Gets the path of cells from from to to, limiting to the graph(s) mapped to
## the given graph_bitfield value.
## Returns the path of cells, which are real positions.
## O(N) time complexity in respect to the number of cells in the path.
func get_cell_path(from: Vector3i, to: Vector3i, graph_bitfield: int = MASTER) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var a_star: AStar3D = _graphs[graph_bitfield]
	result = a_star.get_point_path(_hash(from), _hash(to))
	return result


func get_ids_of_reachable_cells_in_range_array(from: Vector3i, cell_range: int, graph_bitfield: int = MASTER) -> Array[int]:
	return get_ids_of_reachable_cells_in_range_dictionary(from, cell_range, graph_bitfield).keys() as Array[int]


func get_ids_of_reachable_cells_in_range_dictionary(from: Vector3i, cell_range: int, graph_bitfield: int = MASTER) -> Dictionary:
	var from_id: int = _hash(from)
	var visited_ids_in_range: Dictionary = { from_id:from_id }
	var a_star: AStar3D = _graphs[graph_bitfield]
	
	if a_star.has_point(from_id):
		var current_visited_ids: Dictionary = visited_ids_in_range
		var frontier_ids: PackedInt64Array = a_star.get_point_connections(from_id)
		var next_frontier_ids: PackedInt64Array = []
		for depth in range(cell_range):
			for id in frontier_ids:
				if !visited_ids_in_range.has(id): 
					next_frontier_ids.append_array(a_star.get_point_connections(id))
					current_visited_ids[id] = id
			frontier_ids = next_frontier_ids
			next_frontier_ids = []
	return visited_ids_in_range


func get_cells_of_ids(ids: Array[int], graph_bitfield: int = MASTER) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var a_star: AStar3D = _graphs[graph_bitfield]
	for id in ids:
		cells.append(Vector3i(a_star.get_point_position(id)))
	return cells


## Gets the reachable cells in the given graph from from within the given range.
## A cell is considered reachable if it is connected and not disabled.
## Returns a 2D array, both of type Array[Vector3i].
## The first contains the cells within the given range, the second contains the
## cells beyond the range.
## O(N^2) - essentially a breadth-first search.
func get_reachable_cells_in_range(from: Vector3i, cell_range: int, layers_of_cells_out_of_range_to_include: int = 0, excluded_cell_ids: Dictionary = {}, graph_bitfield: int = MASTER) -> Array:
	var in_range_cells: Array[Vector3i] = []
	var out_of_range_cells: Array[Vector3i] = []
	var from_id: int = _hash(from)
	var visited_ids_in_range: Dictionary = excluded_cell_ids
	var visited_ids_out_of_range: Dictionary = {}
	var a_star: AStar3D = _graphs[graph_bitfield]
	
	if a_star.has_point(from_id):
		var current_visited_ids: Dictionary = visited_ids_in_range
		var frontier_ids: PackedInt64Array = a_star.get_point_connections(from_id)
		var next_frontier_ids: PackedInt64Array = []
		for depth in range(cell_range + layers_of_cells_out_of_range_to_include):
			if depth == cell_range: # Keep the in-range cells separate from out-of-range cells.
				current_visited_ids = visited_ids_out_of_range
			for id in frontier_ids:
				if !visited_ids_in_range.has(id) && !visited_ids_out_of_range.has(id): 
					next_frontier_ids.append_array(a_star.get_point_connections(id))
					current_visited_ids[id] = id
			frontier_ids = next_frontier_ids
			next_frontier_ids = []
	for id in visited_ids_in_range.keys():
		in_range_cells.append(Vector3i(a_star.get_point_position(id)))
	for id in visited_ids_out_of_range.keys():
		out_of_range_cells.append(Vector3i(a_star.get_point_position(id)))
	return [in_range_cells, out_of_range_cells]


## Displays debug information.
func show_cells(value: bool = true, graph_bitfield: int = MASTER) -> void:
	if value:
		var a_star: AStar3D = _graphs[graph_bitfield]
		_multimesh_instance.multimesh.instance_count = a_star.get_point_count()
		
		var i: int = 0
		for id in a_star.get_point_ids():
			var cell: Vector3i = a_star.get_point_position(id)
			var cell_transform: Transform3D = Transform3D(Basis.IDENTITY, cell)
			_multimesh_instance.multimesh.set_instance_transform(i, cell_transform)
			i += 1
	else:
		_multimesh_instance.multimesh.instance_count = 0


func toggle_show_cells(graph_bitfield: int = MASTER) -> bool:
	var result: bool = false
	show_cells(!is_cells_visible(), graph_bitfield)
	return result


func is_cells_visible() -> bool:
	return _multimesh_instance.multimesh.instance_count > 0


## Calculates the size of this object's graph.
func _calculate_size() -> void:
	for cell in get_used_cells():
		var max_axis_index: int = cell.max_axis_index()
		if cell[max_axis_index] >= _size:
			_size = maxi(_size + 1, cell[max_axis_index])
	print(_size)


## Builds all of this object's graphs.
func _build_all_graphs() -> void:
	var used_cells: Array[Vector3i] = get_used_cells()
	used_cells.sort_custom(_reverse_sort_on_y)
	
	for cell in used_cells:
		var id: int = _hash(cell)
		_a_star_used_cells.add_point(id, cell)
	
	for cell in used_cells:
		var id: int = _hash(cell)
		var cell_above: Vector3i = Vector3i.UP + cell
		if !_a_star_used_cells.has_point(_hash(cell_above)):
				_a_star_master.add_point(id, cell)
		if !_a_star_used_cells.has_point(_hash(cell_above)):
				_a_star_land.add_point(id, cell)
		_a_star_used_cells.add_point(id, cell)
	
	used_cells.sort_custom(_sort_on_y)
	for cell in used_cells:
		for y in range(cell.y + 1, _size):
			var _cell: Vector3i = Vector3i(cell.x, y, cell.z)
			var should_add_cell: bool = true
			var is_cell_above_in_map: bool = y < _size - 2 # _hash() only works with cells inside map size
			if is_cell_above_in_map:
				var cell_above: Vector3i = Vector3i.UP + _cell
				should_add_cell = !_a_star_used_cells.has_point(_hash(cell_above))
			if should_add_cell:
				_a_star_master.add_point(_hash(_cell), _cell)
	
	_build_ledges()


## Builds this object's master graph.
func _build_master() -> void:
	var used_cells: Array[Vector3i] = get_used_cells()
	used_cells.sort_custom(_reverse_sort_on_y)
	
	for cell in used_cells:
		var id: int = _hash(cell)
		var cell_above: Vector3i = Vector3i.UP + cell
		if !_a_star_used_cells.has_point(_hash(cell_above)):
				_a_star_master.add_point(id, cell)
	
	for cell in get_used_cells():
		for y in range(cell.y + 1, _size):
			var _cell: Vector3i = Vector3i(cell.x, y, cell.z)
			var cell_above: Vector3i = Vector3i.UP + _cell
			
			if !_a_star_used_cells.has_point(_hash(cell_above)):
				_a_star_master.add_point(_hash(_cell), _cell)


## Builds this object's land graph.
func _build_land() -> void:
	for cell in get_used_cells():
		var id: int = _hash(cell)
		var cell_above: Vector3i = Vector3i.UP + cell
		if !_a_star_used_cells.has_point(_hash(cell_above)):
				_a_star_land.add_point(id, cell)
	
	_build_ledges()


## Builds this object's land graph's ledges.
func _build_ledges() -> void:
	var ledge_cell_diagonals: Array[Vector3i] = [
		Vector3i.UP + Vector3i.FORWARD,
		Vector3i.UP + Vector3i.BACK,
		Vector3i.UP + Vector3i.LEFT,
		Vector3i.UP + Vector3i.RIGHT,
	]
	
	var ledge_cells: Dictionary = {}
	
	for id in _a_star_land.get_point_ids():
		var cell: Vector3i = _a_star_land.get_point_position(id)
		for diagonal_check_cell in ledge_cell_diagonals:
			var diagonal_cell: Vector3i = cell + diagonal_check_cell
			if diagonal_cell >= Vector3i.ZERO:
				var diagonal_id: int = _hash(diagonal_cell)
				if _a_star_land.has_point(diagonal_id):
					var ledge_cell: Vector3i = cell + Vector3i.UP
					ledge_cells[_hash(ledge_cell)] = ledge_cell
	
	for id in ledge_cells.keys():
		_a_star_land.add_point(id, ledge_cells[id])


## Connects the cells in all of this object's graphs, if they have cells to
## connect.
func _connect_cells() -> void:
	var neighbors: Array[Vector3i] = [
		Vector3i.FORWARD,
		Vector3i.BACK,
		Vector3i.LEFT,
		Vector3i.RIGHT,
		Vector3i.UP,
		Vector3i.DOWN,
	]
	
	_connect_cells_in(_a_star_master, neighbors)
	_connect_cells_in(_a_star_land, neighbors)


## Connects the cells in the given AStar3D object, given the neighbors.
func _connect_cells_in(a_star_3d: AStar3D, neighbors: Array[Vector3i]) -> void:
	for id in a_star_3d.get_point_ids():
		var cell: Vector3i = a_star_3d.get_point_position(id)
		for neighbor in neighbors:
			var neighbor_cell: Vector3i = cell + neighbor
			var is_non_negative: bool = neighbor_cell[neighbor_cell.min_axis_index()] >= 0
			var is_in_map_size: bool = neighbor_cell[neighbor_cell.max_axis_index()] < _size
			if is_non_negative && is_in_map_size:
				var neighbor_id: int = _hash(neighbor_cell)
				if a_star_3d.has_point(neighbor_id):
					var _neighbor_cell: Vector3i = a_star_3d.get_point_position(neighbor_id)
					if !a_star_3d.are_points_connected(id, neighbor_id):
						a_star_3d.connect_points(id, neighbor_id)


## Hashes the given Vector3i value, returning a unique ID associated with its
## x, y, z members and this object's graph size.
func _hash(cell: Vector3i) -> int:
	return cell.x + (_size * cell.y) + (_size * _size * cell.z)


## Registers this map with the global singleton that serves as an interface for
## other nodes to access necessary information about this map's grid.
func _register_with_interface() -> void: ##todo
#	MapInterface.register_map(self)
	pass
