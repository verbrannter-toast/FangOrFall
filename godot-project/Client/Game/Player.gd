extends Control

const DIRECTIONS = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

@export var player: int
@export var initial_tile: Vector2

var TileScene = preload("res://Client/Game/Tile.tscn")
var body = []
var current_direction: int = 1

var _tile_size: int
var _player: int  # Die echte Player-Nummer (0 oder 1)

func _ready():
	add_to_group("players")

func setup(tile_size: int, player_num: int, _sprite_idx: int):
	_tile_size = tile_size
	_player = player_num  # WICHTIG: Das ist die echte Player-Nummer!
	
	# Startrichtung basierend auf Spieler
	if player_num == 0:
		current_direction = 1  # RIGHT
	else:
		current_direction = 3  # LEFT
	
	# Erstelle Kopf
	var head = create_body()
	head.is_active = true
	head.is_head = true
	head.direction = current_direction
	head.teleport_to(initial_tile.x, initial_tile.y)
	
	# Erstelle 2 Startkörper-Segmente
	for i in range(2):
		var segment = create_body()
		segment.is_active = true
		var offset = DIRECTIONS[current_direction] * (i + 1) * -1
		segment.teleport_to(initial_tile.x + offset.x, initial_tile.y + offset.y)
		segment.direction = current_direction
		segment.prev_direction = current_direction
		segment.next_direction = current_direction
	
	# Letztes Segment ist Schwanz
	body[-1].is_tail = true
	
	# Refresh alle Texturen
	for tile in body:
		tile.refresh_texture()

func create_body() -> Tile:
	var tile = TileScene.instantiate()
	
	# WICHTIG: Eigenschaften VOR add_child setzen!
	tile.anchor_left = 0
	tile.anchor_top = 0
	tile.anchor_right = 0
	tile.anchor_bottom = 0
	tile.custom_minimum_size = Vector2.ONE * _tile_size
	tile.size = Vector2.ONE * _tile_size
	tile.tile_size = _tile_size
	tile.player = _player
	
	# Standardmäßig ist es Körper (nicht Kopf, nicht Schwanz)
	tile.is_head = false
	tile.is_tail = false
	tile.is_active = false
	
	# Erst DANN zur Scene hinzufügen
	add_child(tile)
	body.append(tile)
	
	# Texture refresh nach add_child
	tile.refresh_texture()
	
	return tile

func move_to_direction():
	if body.is_empty():
		return
	
	var head: Tile = body[0]
	var movement = DIRECTIONS[current_direction]
	
	# Speichere alte Positionen und Richtungen
	var positions = []
	var directions = []
	
	var next_pos = head + movement
	
	# Unerlaubter Schritt nach hinten
	if next_pos == body[1]:
		return
	
	for i in range(body.size()):
		positions.append(Vector2(body[i].tile_x, body[i].tile_y))
		directions.append(body[i].direction)
	
	# Bewege Kopf
	head.direction = current_direction
	head.move_to(head.tile_x + movement.x, head.tile_y + movement.y)
	
	
	# Bewege Rest der Schlange
	for i in range(1, body.size()):
		if body[i].is_active:
			body[i].move_to(positions[i-1].x, positions[i-1].y)
			
			# Update Richtungen für Körpersegmente
			body[i].prev_direction = directions[i-1]
			if i < body.size() - 1:
				body[i].next_direction = get_direction_to(positions[i], positions[i+1])
			else:
				body[i].next_direction = directions[i-1]
			
			body[i].direction = directions[i-1]
		else:
			body[i].is_active = true
			body[i].teleport_to(positions[i-1].x, positions[i-1].y)
	
	# Refresh Texturen
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
	
	if body.size() > 1:
		# WICHTIG: Alten Schwanz zu normalem Körper machen
		var old_tail = body[-1]
		old_tail.is_tail = false
		old_tail.is_head = false
		
		# Neues Segment wird neuer Schwanz
		new_segment.is_tail = true
		new_segment.is_head = false
		new_segment.is_active = false  # Wird erst beim nächsten Move aktiviert
		
		# Position vom vorletzten Segment
		var ref_tile = body[-2] if body.size() > 2 else body[-1]
		new_segment.teleport_to(ref_tile.tile_x, ref_tile.tile_y)
		new_segment.prev_direction = ref_tile.direction
		new_segment.direction = ref_tile.direction
	
	# Refresh: Alten Schwanz (jetzt Körper) und neuen Schwanz
	if body.size() > 1:
		body[-2].refresh_texture()  # Ex-Schwanz, jetzt Körper
	body[-1].refresh_texture()  # Neuer Schwanz

func tick():
	move_to_direction()

func kill():
	for tile in body:
		tile.queue_free()
	queue_free()
