extends Control

@export var round_tick: float = 0.5
@export var map_width: int = 18
@export var map_height: int = 12

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

signal on_game_over

func setup(player_number: int, relay_client: ClientManager):
	_is_host = player_number == 0
	_relay_client = relay_client
	_player_number = player_number
	
	tile_size = int(size.y / map_height)
	position.x = (size.x - (tile_size * map_width)) / 2.0
	
	players = get_tree().get_nodes_in_group("players")
	_players_alive = players.size()
	
	# WICHTIG: Alle Spieler bekommen ihre echte Player-Nummer!
	for i in range(players.size()):
		players[i].setup(tile_size, i, i)  # Hier wird sprite_idx übergeben aber nicht genutzt
	
	$PlayerInput.player = players[player_number]
	$PlayerInput.is_host = _is_host
	$PlayerInput.relay_client = relay_client
	
	# Erstelle Wände
	for n in range(map_width):
		for m in range(map_height):
			if n == 0 or m == 0 or n == map_width - 1 or m == map_height - 1:
				var tile = TileScene.instantiate()
				add_child(tile)
				tile.refresh_texture()
				tile.size = Vector2.ONE * tile_size
				tile.tile_size = tile_size
				tile.teleport_to(n, m)

func _set_direction(player_number: int, direction: int):
	if players[player_number] != null:
		players[player_number].current_direction = direction

func _process(delta):
	if _is_host:
		turn_timer += delta
		if turn_timer > round_tick:
			turn_timer -= round_tick
			tick()
			
			# Sende Game State nur wenn Client noch verbunden
			if _relay_client != null and is_instance_valid(_relay_client):
				send_game_state()

func send_game_state():
	var message = Message.new()
	message.content = {}
	message.content["host_tick"] = true
	message.content["directions"] = []
	
	for player in get_tree().get_nodes_in_group("players"):
		message.content["directions"].append(Vector2(player.player, player.current_direction))
	
	# Food-Positionen
	message.content["food_positions"] = []
	for food in foods:
		message.content["food_positions"].append(Vector2(food.tile_x, food.tile_y))
	
	# Snake-Längen
	message.content["snake_lengths"] = []
	for player in players:
		message.content["snake_lengths"].append(player.body.size())
	
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

# NEU: Spawne Food an spezifischer Position
func spawn_food_at(x: int, y: int):
	var tile = TileScene.instantiate()
	add_child(tile)
	tile.size = Vector2.ONE * tile_size
	tile.tile_size = tile_size
	tile.teleport_to(x, y)
	tile.is_food = true
	foods.append(tile)
	tile.refresh_texture()

# NEU: Sync Food-Positionen vom Host
func sync_food_positions(positions: Array):
	# Prüfe ob sich was geändert hat
	if positions.size() != foods.size():
		# Anzahl hat sich geändert - kompletter Rebuild
		for food in foods:
			food.queue_free()
		foods.clear()
		
		for pos in positions:
			spawn_food_at(int(pos.x), int(pos.y))
	else:
		# Nur Positionen updaten (schneller)
		for i in range(min(positions.size(), foods.size())):
			var pos = positions[i]
			if foods[i].tile_x != int(pos.x) or foods[i].tile_y != int(pos.y):
				foods[i].teleport_to(int(pos.x), int(pos.y))

# NEU: Sync Snake-Längen vom Host
func sync_snake_lengths(lengths: Array):
	for i in range(min(lengths.size(), players.size())):
		var target_length = lengths[i]
		var current_length = players[i].body.size()
		
		# Nur wachsen wenn wirklich nötig
		if current_length < target_length:
			var grow_amount = target_length - current_length
			print("[SYNC] Player ", i, " grows by ", grow_amount)
			for j in range(grow_amount):
				players[i].grow()

func rand_free_pos():
	var occupied = []
	
	for player in players:
		for tile in player.body:
			occupied.append(Vector2(tile.tile_x, tile.tile_y))
	
	for food in foods:
		occupied.append(Vector2(food.tile_x, food.tile_y))
	
	var rand_pos = Vector2.ZERO
	var tries = 0
	while true:
		rand_pos = Vector2(2 + randi() % (map_width - 4), 2 + randi() % (map_height - 4))
		if not occupied.has(rand_pos):
			break
		else:
			tries += 1
		if tries > 50:
			break
	
	return rand_pos

func tick():
	check_collisions()
	check_game_over()
	
	var alive_players = get_tree().get_nodes_in_group("players")
	for player in alive_players:
		player.tick()

func check_game_over():
	# NUR wenn wirklich nur noch 1 oder 0 Spieler leben
	if _players_alive <= 1:
		print("[GAME OVER] Only ", _players_alive, " player(s) alive. Ending game.")
		
		if _relay_client != null and is_instance_valid(_relay_client):
			var message = Message.new()
			message.content = {}
			message.content["gameover"] = true
			_relay_client.send_data(message)
		
		emit_signal("on_game_over")

func check_collisions():
	var tiles = get_tree().get_nodes_in_group("tiles")
	var tile_positions = {}
	var mark_for_deletion = []
	
	for tile in tiles:
		tile = tile as Tile
		if tile.is_disabled:
			continue
		
		var pos = Vector2(tile.tile_x, tile.tile_y)
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
					
					# NEU: Nur Host bewegt Food
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
