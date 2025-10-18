extends Control

const DIRECTIONS = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

@export var player: int

var body = []
var current_direction: int = 1

var _tile_size: int
var _player: int
var _spawn_position: Vector2i

func _ready():
	add_to_group("players")

func setup(tile_size: int, player_num: int, _sprite_idx: int):
	_tile_size = tile_size  # WICHTIG: ZUERST setzen!
	_player = player_num
	
	print("[PLAYER ", _player, "] Setup starting with tile_size: ", _tile_size)
	
	# Finde SpawnPoint
	var spawn_point = _find_spawn_point()
	if spawn_point:
		_spawn_position = spawn_point.get_grid_position(tile_size)
		current_direction = spawn_point.get_direction()
		print("[PLAYER ", _player, "] Spawning at: ", _spawn_position, " (from SpawnPoint)")
	else:
		_spawn_position = Vector2i(5, 5) if player_num == 0 else Vector2i(25, 25)
		current_direction = 1 if player_num == 0 else 3
		print("[PLAYER ", _player, "] WARNING: No SpawnPoint found! Using fallback: ", _spawn_position)
	
	# Kopf erstellen
	var head = create_body()
	if head == null:
		print("[ERROR] Failed to create head for player ", _player)
		return
	
	head.is_active = true
	head.is_head = true
	head.direction = current_direction
	head.teleport_to(_spawn_position.x, _spawn_position.y)
	
	print("[PLAYER ", _player, "] Head spawned at pixel position: ", head.position)
	
	# 2 Startkörper-Segmente
	for i in range(2):
		var segment = create_body()
		if segment == null:
			continue
		
		segment.is_active = true
		var offset = DIRECTIONS[current_direction] * (i + 1) * -1
		segment.teleport_to(_spawn_position.x + offset.x, _spawn_position.y + offset.y)
		segment.direction = current_direction
		segment.prev_direction = current_direction
		segment.next_direction = current_direction
	
	# Letztes Segment ist Schwanz
	if body.size() > 0:
		body[-1].is_tail = true
	
	# Refresh alle Texturen
	for tile in body:
		tile.refresh_texture()
	
	print("[PLAYER ", _player, "] Setup complete. Head at grid(", _spawn_position, ") pixel(", head.position, ")")

func _find_spawn_point() -> SpawnPoint:
	for child in get_children():
		if child is SpawnPoint:
			return child
	return null

func create_body() -> Tile:
	var tile_scene = load("res://Client/Game/Tile.tscn")
	
	if tile_scene == null:
		print("[ERROR] Could not load Tile.tscn!")
		return null
	
	var tile = tile_scene.instantiate()
	
	if not (tile is Tile):
		print("[ERROR] Instantiated node is not a Tile! Type: ", tile.get_class())
		tile.queue_free()
		return null
	
	# KRITISCH: tile_size ZUERST setzen!
	tile.tile_size = _tile_size
	
	# Dann Anchors
	tile.anchor_left = 0
	tile.anchor_top = 0
	tile.anchor_right = 0
	tile.anchor_bottom = 0
	
	# Dann Größe
	tile.custom_minimum_size = Vector2.ONE * _tile_size
	tile.size = Vector2.ONE * _tile_size
	tile.player = _player
	
	# Flags
	tile.is_head = false
	tile.is_tail = false
	tile.is_active = false
	
	# Zur Scene hinzufügen
	add_child(tile)
	body.append(tile)
	
	# Texture refresh
	tile.refresh_texture()
	
	print("[PLAYER ", _player, "] Created tile with tile_size: ", tile.tile_size, " size: ", tile.size)
	
	return tile

func move_to_direction():
	if body.is_empty():
		return
	
	var head: Tile = body[0]
	var movement = DIRECTIONS[current_direction]
	
	var positions = []
	var directions = []
	
	for i in range(body.size()):
		positions.append(Vector2(body[i].tile_x, body[i].tile_y))
		directions.append(body[i].direction)
	
	head.direction = current_direction
	head.move_to(head.tile_x + movement.x, head.tile_y + movement.y)
	
	for i in range(1, body.size()):
		if body[i].is_active:
			body[i].move_to(positions[i-1].x, positions[i-1].y)
			body[i].prev_direction = directions[i-1]
			if i < body.size() - 1:
				body[i].next_direction = get_direction_to(positions[i], positions[i+1])
			else:
				body[i].next_direction = directions[i-1]
			body[i].direction = directions[i-1]
		else:
			body[i].is_active = true
			body[i].teleport_to(positions[i-1].x, positions[i-1].y)
	
	for tile in body:
		tile.refresh_texture()

func get_direction_to(from: Vector2, to: Vector2) -> int:
	var diff = to - from
	if abs(diff.y) > abs(diff.x):
		return 0 if diff.y < 0 else 2
	else:
		return 1 if diff.x > 0 else 3

func grow():
	var new_segment = create_body()
	if new_segment == null:
		return
	
	if body.size() > 1:
		var old_tail_idx = body.size() - 2
		var old_tail = body[old_tail_idx]
		
		old_tail.is_tail = false
		old_tail.is_head = false
		
		new_segment.is_tail = true
		new_segment.is_head = false
		new_segment.is_active = false
		
		var ref_tile = body[old_tail_idx]
		new_segment.teleport_to(ref_tile.tile_x, ref_tile.tile_y)
		new_segment.prev_direction = ref_tile.direction
		new_segment.direction = ref_tile.direction

		old_tail.refresh_texture()
		new_segment.refresh_texture()

func tick():
	move_to_direction()

func kill():
	for tile in body:
		if tile != null and is_instance_valid(tile):
			tile.queue_free()
	queue_free()
