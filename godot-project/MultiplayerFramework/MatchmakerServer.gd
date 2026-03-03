extends Node

@export var match_size: int = 2

var PORT = 9080
var _server = TCPServer.new()
var _peers = {}
var _connected_players = {}
var _match_queue = []
var _next_id = 1

var _match_sessions: Dictionary = {}
var _tick_rate: float = 0.2
var _creating_match: bool = false

# Loaded once from Game.tscn at startup
var _walls: Array[Vector2i] = []
var _floor_tiles: Array[Vector2i] = []
var _map_loaded: bool = false

const SPAWN_POSITIONS = [Vector2i(9, 12), Vector2i(27, 22)]
const SPAWN_DIRECTIONS = [1, 3]  # RIGHT, LEFT
const DIR_VECTORS = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

signal client_connected(id: int)
signal client_disconnected(id: int)
signal match_created(player_ids: Array)
signal message_received(from_id: int, message_type: String)

func _ready():
	var env_port = OS.get_environment("PORT")
	if env_port != "":
		PORT = int(env_port)

	print("=== MATCHMAKING SERVER ===")
	_load_map_from_scene()

	var err = _server.listen(PORT, "127.0.0.1")
	if err != OK:
		print("ERROR: Unable to start server: ", err)
		set_process(false)
		return
	print("Listening on port ", PORT)
	_logger_coroutine()
	_heartbeat_coroutine()

func _load_map_from_scene():
	# Instantiate the game scene temporarily just to read its TileMap
	var game_scene = load("res://Client/Game/Game.tscn").instantiate()
	# Don't add to tree — we just need the TileMap node directly
	var tilemap: TileMap = game_scene.get_node("TileMap-Walls")
	if not tilemap:
		print("[SERVER] ERROR: Could not find TileMap-Walls in Game.tscn")
		game_scene.queue_free()
		return

	var used_rect = tilemap.get_used_rect()
	_walls.clear()
	_floor_tiles.clear()

	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			var pos = Vector2i(x, y)
			if tilemap.get_cell_source_id(0, pos) != -1:
				_walls.append(pos)
			else:
				_floor_tiles.append(pos)

	game_scene.free()  # free() not queue_free() since it was never added to the tree
	_map_loaded = true
	print("[SERVER] Map loaded: ", _walls.size(), " wall tiles, ", _floor_tiles.size(), " floor tiles")

func _logger_coroutine():
	while true:
		await get_tree().create_timer(5.0).timeout
		print("\n--- Sessions: ", _match_sessions.keys(), " Queue: ", _match_queue, " ---\n")

func _heartbeat_coroutine():
	while true:
		await get_tree().create_timer(25.0).timeout
		for id in _peers.keys():
			var msg = Message.new()
			msg.is_echo = true
			msg.content = "ping"
			_send_to_peer(id, msg)

func _process(delta):
	if _server.is_connection_available():
		var peer = _server.take_connection()
		peer.set_no_delay(true)
		var ws_peer = WebSocketPeer.new()
		if ws_peer.accept_stream(peer) != OK:
			return
		var id = _next_id
		_next_id += 1
		_peers[id] = {"ws": ws_peer, "tcp": peer, "ready": false}
		print("-> Client ", id, " connecting...")

	var to_remove = []
	for id in _peers.keys():
		var peer_data = _peers[id]
		var ws_peer = peer_data["ws"]
		ws_peer.poll()
		match ws_peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if not peer_data["ready"]:
					peer_data["ready"] = true
					_connected(id)
				var processed = 0
				while ws_peer.get_available_packet_count() > 0 and processed < 50:
					_on_data(id, ws_peer.get_packet())
					processed += 1
			WebSocketPeer.STATE_CLOSED:
				_disconnected(id)
				to_remove.append(id)
	for id in to_remove:
		_peers.erase(id)

	if _match_queue.size() >= match_size and not _creating_match:
		create_new_match()

	for match_id in _match_sessions.keys():
		var session = _match_sessions[match_id]
		if not session.get("started", false):
			continue
		session["tick_timer"] += delta
		if session["tick_timer"] >= _tick_rate:
			session["tick_timer"] -= _tick_rate
			_tick_session(match_id, session)

func _connected(id):
	print("  Client ", id, " connected")
	_connected_players[id] = []
	_match_queue.append(id)
	var message = Message.new()
	message.server_login = true
	message.content = id
	_send_to_peer(id, message)
	emit_signal("client_connected", id)
	var parent = get_parent()
	if parent and parent.has_method("add_log"):
		parent.add_log("[color=green]Client " + str(id) + " connected[/color]")
		if _match_queue.size() < match_size:
			parent.add_log("[color=gray]Waiting for " + str(match_size - _match_queue.size()) + " more player(s)...[/color]")

func create_new_match():
	_creating_match = true
	print("\n Creating new match")
	var new_match = []
	for i in range(match_size):
		new_match.append(_match_queue[i])

	for i in range(match_size):
		var player_id = _match_queue[0]
		var message = Message.new()
		message.match_start = true
		message.content = new_match
		_send_to_peer(player_id, message)
		_match_queue.remove_at(0)

	for i in range(new_match.size()):
		_connected_players[new_match[i]] = new_match

	var match_id = _make_match_id(new_match)
	var session = _create_session(new_match)
	_match_sessions[match_id] = session
	emit_signal("match_created", new_match)

	# Send initial state so clients can render the board before countdown
	await get_tree().create_timer(0.1).timeout
	_broadcast_state(match_id, session)
	_start_countdown(match_id, new_match, 3)

func _create_session(players: Array) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	var snakes = []
	var snake_dirs = []
	var directions = []
	var alive = []
	var scores = []

	for i in range(players.size()):
		var spawn = SPAWN_POSITIONS[i]
		var dir = SPAWN_DIRECTIONS[i]
		var body: Array[Vector2i] = [spawn]
		var dirs: Array[int] = [dir]
		for j in range(1, 3):
			body.append(spawn + DIR_VECTORS[dir] * -j)
			dirs.append(dir)
		snakes.append(body)
		snake_dirs.append(dirs)
		directions.append(dir)
		alive.append(true)
		scores.append(0)

	var food = []
	for i in range(4):
		food.append(_spawn_food_item(snakes, [], rng))

	return {
		"players": players,
		"inputs": {},
		"tick_timer": 0.0,
		"started": false,
		"snakes": snakes,
		"snake_dirs": snake_dirs,
		"directions": directions,
		"alive": alive,
		"scores": scores,
		"food": food,
		"powerups": [],
		"rng": rng,
		"tick": 0,
	}

func _start_countdown(match_id: String, players: Array, seconds: int):
	for i in range(seconds, 0, -1):
		var msg = Message.new()
		msg.content = {"countdown": i}
		for pid in players:
			_send_to_peer(pid, msg)
		await get_tree().create_timer(1.0).timeout

	var go_msg = Message.new()
	go_msg.content = {"countdown": 0}
	for pid in players:
		_send_to_peer(pid, go_msg)

	if _match_sessions.has(match_id):
		_match_sessions[match_id]["started"] = true
	_creating_match = false

func _tick_session(match_id: String, session: Dictionary):
	session["tick"] += 1

	# Apply inputs — reject 180 turns server-side
	for i in range(session["players"].size()):
		var pid = session["players"][i]
		var dir = session["inputs"].get(pid, -1)
		if dir != -1 and not _is_180(session["directions"][i], dir):
			session["directions"][i] = dir
		session["inputs"][pid] = -1

	# Magnet effect
	for pw in session["powerups"]:
		if pw["type"] != "magnet":
			continue
		var pi = pw["player"]
		if not session["alive"][pi]:
			continue
		var head = session["snakes"][pi][0]
		for fi in range(session["food"].size()):
			var food_pos = session["food"][fi]["pos"]
			var diff = food_pos - head
			if abs(diff.x) <= 3 and abs(diff.y) <= 3:
				# Move one step closer on whichever axis is larger
				var step = Vector2i.ZERO
				if abs(diff.x) >= abs(diff.y):
					step.x = -1 if diff.x > 0 else (1 if diff.x < 0 else 0)
				else:
					step.y = -1 if diff.y > 0 else (1 if diff.y < 0 else 0)
				var new_pos = food_pos + step
				# Only move if not into a wall or another food
				if not _walls.has(new_pos):
					session["food"][fi]["pos"] = new_pos

	# Tick down powerup durations and remove expired ones
	for pw in session["powerups"]:
		pw["ticks"] -= 1
	session["powerups"] = session["powerups"].filter(func(p): return p["ticks"] > 0)

	# Move snakes — shift positions and per-segment directions together
	for i in range(session["snakes"].size()):
		if not session["alive"][i]:
			continue
		var snake = session["snakes"][i]
		var dirs = session["snake_dirs"][i]
		var new_head = snake[0] + DIR_VECTORS[session["directions"][i]]
		snake.push_front(new_head)
		dirs.push_front(session["directions"][i])
		snake.pop_back()
		dirs.pop_back()

	# Wall collision — checks against real TileMap tiles
	var deaths = []
	for i in range(session["snakes"].size()):
		if not session["alive"][i]:
			continue
		var head = session["snakes"][i][0]
		if _walls.has(head):
			print("[SERVER] P", i, " hit wall at ", head)
			deaths.append(i)
			continue
		# Self collision
		for j in range(1, session["snakes"][i].size()):
			if head == session["snakes"][i][j]:
				print("[SERVER] P", i, " self-collision at ", head)
				deaths.append(i)
				break

	# Snake vs snake collision
	for i in range(session["snakes"].size()):
		if not session["alive"][i] or deaths.has(i):
			continue
		for j in range(session["snakes"].size()):
			if i == j or not session["alive"][j]:
				continue
			for seg in session["snakes"][j]:
				if session["snakes"][i][0] == seg:
					deaths.append(i)
					break

	# Food collection
	var food_eaten = {}
	for i in range(session["snakes"].size()):
		if not session["alive"][i] or deaths.has(i):
			continue
		for fi in range(session["food"].size()):
			if session["snakes"][i][0] == session["food"][fi]["pos"]:
				food_eaten[fi] = i
				break

	# Apply food effects
	for fi in food_eaten.keys():
		var pi = food_eaten[fi]
		var food_type = session["food"][fi]["type"]
		var grow_amount = 3 if food_type == "golden" else 1
		var score_amount = 3 if food_type == "golden" else 1
		
		for _h in range(grow_amount):
			session["snakes"][pi].append(session["snakes"][pi][-1])
			session["snake_dirs"][pi].append(session["snake_dirs"][pi][-1])
		
		session["scores"][pi] += score_amount
		
		if food_type == "magnet":
			session["powerups"].append({"player": pi, "type": "magnet", "ticks": 25})
			print("[SERVER] P", pi, " picked up magnet")
		
		session["food"][fi] = _spawn_food_item(session["snakes"], session["food"], session["rng"])
		print("[SERVER] P", pi, " ate food, score: ", session["scores"][pi], " new food: ", session["food"][fi])

	# Apply deaths
	for i in deaths:
		if session["alive"][i]:
			session["alive"][i] = false
			print("[SERVER] P", i, " died")

	# Game over check
	if session["alive"].count(true) <= 1:
		var winner = -1
		for i in range(session["alive"].size()):
			if session["alive"][i]:
				winner = i
				break
		print("[SERVER] Game over — winner: ", winner)
		_broadcast_gameover(match_id, session, winner)
		_match_sessions.erase(match_id)
		return

	_broadcast_state(match_id, session)

func _broadcast_state(match_id: String, session: Dictionary):
	var msg = Message.new()
	msg.content = {
		"server_tick": true,
		"tick": session["tick"],
		"snakes": session["snakes"],
		"snake_dirs": session["snake_dirs"],
		"directions": session["directions"],
		"alive": session["alive"],
		"scores": session["scores"],
		"food": session["food"],
	}
	for pid in session["players"]:
		_send_to_peer(pid, msg)

func _broadcast_gameover(match_id: String, session: Dictionary, winner: int):
	var msg = Message.new()
	msg.content = {"gameover": true, "winner": winner, "scores": session["scores"]}
	for pid in session["players"]:
		_send_to_peer(pid, msg)

func _is_180(current_dir: int, new_dir: int) -> bool:
	return (current_dir + 2) % 4 == new_dir

func _rand_free_pos(snakes: Array, food: Array, rng: RandomNumberGenerator) -> Vector2i:
	var occupied: Array[Vector2i] = []
	for snake in snakes:
		for seg in snake:
			occupied.append(seg)
	for f in food:
		occupied.append(f)
	# Sample randomly from the pre-built floor tile list
	var attempts = 0
	while attempts < 1000:
		var idx = rng.randi_range(0, _floor_tiles.size() - 1)
		var pos = _floor_tiles[idx]
		if not occupied.has(pos):
			return pos
		attempts += 1
	print("[SERVER] WARNING: Could not find free food position")
	return _floor_tiles[0]

func _spawn_food_item(snakes: Array, food: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pos = _rand_free_pos(snakes, food, rng)
	var roll = rng.randf()
	var type: String
	if roll < 0.80:
		type = "apple"
	elif roll < 0.90:
		type = "golden"
	else:
		type = "magnet"
	return {"pos": pos, "type": type}

func _make_match_id(players: Array) -> String:
	var sorted = players.duplicate()
	sorted.sort()
	return "_".join(sorted.map(func(x): return str(x)))

func remove_player_from_connections(id):
	if _match_queue.has(id):
		_match_queue.erase(id)
	if _connected_players.has(id):
		if _connected_players[id] != null:
			_connected_players[id].erase(id)
		_connected_players.erase(id)

func _remove_session_for_player(id: int):
	for match_id in _match_sessions.keys():
		var session = _match_sessions[match_id]
		if id in session["players"]:
			for pid in session["players"]:
				if pid != id:
					var msg = Message.new()
					msg.content = {"gameover": true, "winner": session["players"].find(pid), "scores": session["scores"]}
					_send_to_peer(pid, msg)
			_match_sessions.erase(match_id)
			return

func _disconnected(id):
	print("<- Client ", id, " disconnected")
	_remove_session_for_player(id)
	remove_player_from_connections(id)
	emit_signal("client_disconnected", id)
	var parent = get_parent()
	if parent and parent.has_method("add_log"):
		parent.add_log("[color=red]Client " + str(id) + " disconnected[/color]")

func _on_data(id, packet: PackedByteArray):
	var message = Message.new()
	message.from_raw(packet)
	if message.content is Dictionary and message.content.has("player_input"):
		var dir = int(message.content["player_input"])
		for match_id in _match_sessions.keys():
			var session = _match_sessions[match_id]
			if id in session["players"]:
				session["inputs"][id] = dir
				break
		return
	emit_signal("message_received", id, "data")

func _send_to_peer(id: int, message: Message) -> bool:
	if not _peers.has(id):
		return false
	var ws_peer = _peers[id]["ws"]
	if ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return ws_peer.send(message.get_raw()) == OK
