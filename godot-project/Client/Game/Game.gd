extends Control

@export var round_tick: float = 0.2
@export var map_width: int = 30
@export var map_height: int = 30

var TileScene = preload("res://Client/Game/Tile.tscn")

var tile_size = 0
var turn_timer = 0

var _is_host: bool
var _relay_client: ClientManager
var _player_number: int
var _player_is_dead: bool
var _players_alive: int

var foods = []
var players = []
var player_scores = []

@onready var tilemap: TileMap = $"TileMap-Walls"
@onready var camera: Camera2D = $Camera2D

signal on_game_over

func setup(player_number: int, relay_client: ClientManager):
	_is_host = player_number == 0
	_relay_client = relay_client
	_player_number = player_number
	
	tile_size = int(size.y / map_height)
	
	print("[SETUP] Viewport size: ", size)
	print("[SETUP] Map dimensions: ", map_width, "x", map_height)
	print("[SETUP] Calculated tile_size: ", tile_size)
	
	if tilemap:
		var used_rect = tilemap.get_used_rect()
		map_width = used_rect.size.x
		map_height = used_rect.size.y
		print("Map size from TileMap: ", map_width, "x", map_height)
	
	# recalculate in case size has changed
	tile_size = int(size.y / map_height)
	position.x = (size.x - (tile_size * map_width)) / 2.0
	
	if tilemap:
		var svg_size = 16.0
		var scale_factor = tile_size / svg_size
		
		tilemap.scale = Vector2(scale_factor, scale_factor)
		tilemap.position = Vector2.ZERO
	
	players = get_tree().get_nodes_in_group("players")
	_players_alive = players.size()
	
	# Initialize scores
	player_scores = []
	for i in range(players.size()):
		player_scores.append(0)
	
	# Setup players
	for i in range(players.size()):
		players[i].setup(tile_size, i, i)  # Hier wird sprite_idx übergeben aber nicht genutzt
	
	# Setup camera
	if camera:
		camera.setup(player_number)
	
	$PlayerInput.player = players[player_number]
	$PlayerInput.is_host = _is_host
	$PlayerInput.relay_client = relay_client

func _set_direction(player_number: int, direction: int):
	if players[player_number] != null:
		players[player_number].current_direction = direction

func _process(delta):
	if _is_host:
		turn_timer += delta
		if turn_timer > round_tick:
			turn_timer -= round_tick
			
			# DEBUG
			print("[TICK] Alive: ", _players_alive)
			for i in range(players.size()):
				var p = players[i]
				print("  Player ", i, ": ", "valid" if (p != null and is_instance_valid(p)) else "INVALID")
			
			tick()
			
			# Game State nur wenn Client noch verbunden
			if _relay_client != null and is_instance_valid(_relay_client):
				send_game_state()

func send_game_state():
	# Safety Check: Nur senden wenn alle Spieler noch valid sind
	for player in players:
		if player == null or not is_instance_valid(player):
			return  # Stop sending if any player is freed
	
	var message = Message.new()
	message.content = {}
	message.content["host_tick"] = true
	message.content["directions"] = []
	
	for player in get_tree().get_nodes_in_group("players"):
		if player != null and is_instance_valid(player):
			message.content["directions"].append(Vector2(player.player, player.current_direction))
	
	# Food-Positionen
	message.content["food_positions"] = []
	for food in foods:
		if food != null and is_instance_valid(food):
			message.content["food_positions"].append(Vector2(food.tile_x, food.tile_y))
	
	# Snake-Längen
	message.content["snake_lengths"] = []
	for player in players:
		if player != null and is_instance_valid(player) and player.body != null:
			message.content["snake_lengths"].append(player.body.size())
		else:
			message.content["snake_lengths"].append(0)
	
	# Scores
	message.content["scores"] = player_scores
	
	_relay_client.send_data(message)

func spawn_food_tile_at_random():
	var new_pos = rand_free_pos()
	var tile = TileScene.instantiate()
	add_child(tile)
	tile.size = Vector2.ONE * tile_size
	tile.tile_size = tile_size
	tile.teleport_to(new_pos.x, new_pos.y)
	tile.is_food = true
	foods.append(tile)
	tile.refresh_texture()

# Spawne Food
func spawn_food_at(x: int, y: int):
	var tile = TileScene.instantiate()
	add_child(tile)
	tile.size = Vector2.ONE * tile_size
	tile.tile_size = tile_size
	tile.teleport_to(x, y)
	tile.is_food = true
	foods.append(tile)
	tile.refresh_texture()

# Sync Food-Positionen vom Host
func sync_food_positions(positions: Array):
	if positions.size() != foods.size():
		for food in foods:
			food.queue_free()
		foods.clear()
		
		for pos in positions:
			spawn_food_at(int(pos.x), int(pos.y))
	else:
		# Only Update Positions
		for i in range(min(positions.size(), foods.size())):
			var pos = positions[i]
			if foods[i].tile_x != int(pos.x) or foods[i].tile_y != int(pos.y):
				foods[i].teleport_to(int(pos.x), int(pos.y))

# Sync Snake-Längen vom Host
func sync_snake_lengths(lengths: Array):
	for i in range(min(lengths.size(), players.size())):
		var target_length = lengths[i]
		var current_length = players[i].body.size()
		
		# Nur wachsen wenn Unterschied vorhanden
		if current_length < target_length:
			var grow_amount = target_length - current_length
			
			# Mehrfaches Wachstum bedeutet Desync
			if grow_amount > 1:
				print("[SYNC WARNING] Player ", i, " length difference is ", grow_amount, " (should be max 1!)")
				# Nur um 1 wachsen, nicht mehr
				grow_amount = 1
			
			print("[SYNC] Player ", i, " grows by ", grow_amount)
			for j in range(grow_amount):
				players[i].grow()

func sync_scores(scores: Array):
	if scores.size() >= player_scores.size():
		for i in range(player_scores.size()):
			player_scores[i] = scores[i]
		print("[SYNC] Scores updated: ", player_scores)

func rand_free_pos() -> Vector2:
	if not tilemap:
		print("ERROR: No TileMap found!")
		return Vector2(5, 5)
	
	# get map dimensions
	var used_rect = tilemap.get_used_rect()
	var min_x = used_rect.position.x
	var min_y = used_rect.position.y
	var max_x = used_rect.end.x - 1
	var max_y = used_rect.end.y - 1
	
	var occupied = []
	
	# Snake-Positionen
	for player in players:
		if player == null or not is_instance_valid(player):
			continue
		if player.body == null:
			continue
		
		for tile in player.body:
			if tile != null and is_instance_valid(tile):
				occupied.append(Vector2(tile.tile_x, tile.tile_y))
	
	# Food-Positionen
	for food in foods:
		occupied.append(Vector2(food.tile_x, food.tile_y))
	
	# TileMap Walls
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			if is_wall_at(Vector2i(x, y)):
				occupied.append(Vector2i(x, y))
	
	# look for free positions
	var max_tries = 200
	var tries = 0
	
	while tries < max_tries:
		# random position within map boundaries
		var rand_x = randi_range(min_x + 1, max_x - 1)
		var rand_y = randi_range(min_y + 1, max_y - 1)
		var rand_pos = Vector2i(rand_x, rand_y)
		
		# check if position is free
		if not occupied.has(rand_pos):
			print("[FOOD SPAWN] Found free position: ", rand_pos, " after ", tries, " tries")
			return Vector2(rand_pos.x, rand_pos.y)
		
		tries += 1
	
	# Fallback: return any position
	print("WARNING: Could not find free position after ", max_tries, " tries!")
	return Vector2(min_x + 2, min_y + 2)

func tick():
	if _players_alive <= 1:
		return
	
	check_collisions()
	check_game_over()
	
	var alive_players = get_tree().get_nodes_in_group("players")
	for player in alive_players:
		player.tick()

func check_game_over():
	# Game Over when max 1 player is alive
	if _players_alive <= 1:
		print("[GAME OVER] Only ", _players_alive, " player(s) alive.")
		
		var winner = -1
		
		if _players_alive == 1:
			# find both surviving players
			for player in players:
				if player != null and is_instance_valid(player) and player.body.size() > 0:
					winner = player.player
					print("[GAME OVER] Survivor found: Player ", winner)
					break
		else:
			# _players_alive == 0 -> DRAW
			print("[GAME OVER] No survivors - DRAW")
		
		print("[GAME OVER] Winner: Player ", winner if winner != -1 else "NONE")
		
		if _is_host:
			if _relay_client != null and is_instance_valid(_relay_client):
				var message = Message.new()
				message.content = {}
				message.content["gameover"] = true
				message.content["winner"] = winner
				_relay_client.send_data(message)
		
		emit_signal("on_game_over", winner, player_scores)

func check_collisions():
	var tiles = get_tree().get_nodes_in_group("tiles")
	var tile_positions = {}
	var mark_for_deletion = []
	
	for tile in tiles:
		tile = tile as Tile
		if tile.is_disabled:
			continue
		
		var pos = Vector2(tile.tile_x, tile.tile_y)
		
		if tilemap and is_wall_at(pos):
			if tile.is_head:
				print("[WALL COLLISION] Player ", tile.player, " hit wall at ", pos)
				mark_for_deletion.append(tile)
				continue
		
		if not tile_positions.has(pos):
			tile_positions[pos] = tile
		else:
			# Collision detected!
			var tile1 = tile
			var tile2 = tile_positions[pos]
			
			# FOOD COLLISION
			if tile1.is_food or tile2.is_food:
				var head_tile = null
				var food_tile = null
				
				if tile1.is_head and tile2.is_food:
					head_tile = tile1
					food_tile = tile2
				elif tile2.is_head and tile1.is_food:
					head_tile = tile2
					food_tile = tile1
				
				if head_tile != null and food_tile != null:
					print("[FOOD] Player ", head_tile.player, " ate food at ", pos)
					
					# Player wächst
					players[head_tile.player].grow()
					player_scores[head_tile.player] += 1
					
					# Nur Host bewegt Food
					if _is_host:
						var free_pos = rand_free_pos()
						food_tile.teleport_to(free_pos.x, free_pos.y)
						print("[FOOD] Host moved food to ", free_pos)
					# Client wartet auf Sync
			
			# SNAKE COLLISION (Tod)
			else:
				# Beide Tiles sind Snake-Teile
				if tile1.is_head:
					mark_for_deletion.append(tile1)
					print("[COLLISION] Player ", tile1.player, " head collision!")
				if tile2.is_head:
					mark_for_deletion.append(tile2)
					print("[COLLISION] Player ", tile2.player, " head collision!")
	
	# NUR bei echten Toden Players killen
	if mark_for_deletion.size() > 0:
		print("[DEATH] ", mark_for_deletion.size(), " snake(s) died")
		var alive_players = get_tree().get_nodes_in_group("players")
		for tile in mark_for_deletion:
			for player in alive_players:
				if player.player == tile.player:
					if player.player == _player_number:
						_player_is_dead = true
					player.kill()
					_players_alive -= 1
					print("[DEATH] Player ", player.player, " killed. Alive: ", _players_alive)

func is_wall_at(pos: Vector2i) -> bool:
	if not tilemap:
		return false
	
	var cell = tilemap.get_cell_source_id(0, pos)
	return cell != -1

func is_position_blocked(pos: Vector2i) -> bool:
	# Prüfe TileMap
	if is_wall_at(pos):
		return true
	
	# Prüfe Snake-Körper
	for player in players:
		if player == null or not is_instance_valid(player):
			continue
		if player.body == null:
			continue
		
		for tile in player.body:
			if tile != null and is_instance_valid(tile):
				if Vector2i(tile.tile_x, tile.tile_y) == pos:
					return true
	
	return false
