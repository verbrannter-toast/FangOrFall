extends Control

var _relay_client: ClientManager
var _game

func _ready():
	_relay_client = $WebsocketClient
	_relay_client.connect("on_message", _on_message)
	_relay_client.connect("on_players_ready", _on_players_ready)
	
	$StartScreen/StartGameButton.connect("pressed", _on_start_game)
	
	$StartScreen.show()
	$Lobby.hide()

func _on_start_game():
	print("=== START GAME PRESSED ===")
	_relay_client.connect_to_server()
	
	$StartScreen.hide()
	$Lobby.show()

func _on_players_ready():
	print("=== PLAYERS READY SIGNAL ===")
	process_match_start()

func _on_game_over():
	print("=== GAME OVER ===")
	if _game == null:
		return
	
	_relay_client.disconnect_from_server()
	
	_game.queue_free()
	_game = null
	$StartScreen.show()

func _on_message(message: Message):
	if message.server_login:
		return
	if message.match_start:
		return
	
	if message.content is Dictionary:
		# Game Over Check
		if message.content.has("gameover"):
			print("[CLIENT] Received gameover signal")
			_on_game_over()
			return
		
		# Seed Message
		if message.content.has("seed"):
			process_seed_message(message)
			return
		
		# Direction/Game State Messages
		if message.content.has("directions"):
			process_directions_message(message)
			return

func process_match_start():
	print("=== STARTING GAME SETUP ===")
	
	_game = load("res://Client/Game/Game.tscn").instantiate()
	add_child(_game)
	_game.connect("on_game_over", _on_game_over)
	
	$Lobby.hide()
	
	var peers = _relay_client._match
	var my_id = _relay_client._id
	var my_player_number = peers.find(my_id)
	
	print("Setting up game:")
	print("  My ID: ", my_id)
	print("  My Player Number: ", my_player_number)
	print("  All Peers: ", peers)
	
	_game.setup(my_player_number, _relay_client)
	
	var is_host = my_player_number == 0
	if is_host:
		print("→ I am HOST - sending seed")
		await get_tree().create_timer(0.1).timeout
		
		var msg = Message.new()
		msg.is_echo = true
		msg.content = {}
		msg.content["seed"] = randi()
		print("  Sending seed: ", msg.content["seed"])
		_relay_client.send_data(msg)
	else:
		print("→ I am CLIENT - waiting for seed")

func process_directions_message(message: Message):
	if _game == null:
		return
	
	# Sichere Checks
	if not is_instance_valid(_game):
		return
	
	# Update Richtungen
	if message.content.has("directions"):
		for dir in message.content["directions"]:
			_game._set_direction(int(dir.x), int(dir.y))
	
	# NEU: Sync Food-Positionen (nur für Clients)
	if not _game._is_host and message.content.has("food_positions"):
		_game.sync_food_positions(message.content["food_positions"])
	
	# NEU: Sync Snake-Längen (nur für Clients)
	if not _game._is_host and message.content.has("snake_lengths"):
		_game.sync_snake_lengths(message.content["snake_lengths"])
	
	# Host tick
	if message.content.get("host_tick", false):
		_game.tick()

func process_seed_message(message: Message):
	if _game == null:
		print("ERROR: Received seed but game not initialized!")
		return
	
	print("✓ Received seed: ", message.content["seed"])
	seed(message.content["seed"])
	
	# NUR HOST spawnt Food initial!
	if _game._is_host:
		print("→ HOST: Spawning initial food")
		for i in range(4):
			_game.spawn_food_tile_at_random()
	else:
		print("→ CLIENT: Waiting for food sync from host")
