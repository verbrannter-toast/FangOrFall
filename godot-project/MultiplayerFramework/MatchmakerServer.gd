extends Node

@export var match_size: int = 2

var PORT = 9080
var _server = TCPServer.new()
var _peers = {}
var _connected_players = {}
var _match_queue = []
var _next_id = 1

# sessions: match_id -> dict
var _match_sessions: Dictionary = {}
var _tick_rate: float = 0.2
var _creating_match: bool = false

signal client_connected(id: int)
signal client_disconnected(id: int)
signal match_created(player_ids: Array)
signal message_received(from_id: int, message_type: String)

# Grid movement directions: 0=UP,1=RIGHT,2=DOWN,3=LEFT
const DIRS := [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0)]

# --- CONFIG ---
# If you want walls from a TileMap, set these and implement _load_walls_from_scene().
# Otherwise it behaves as simple bounds-only walls.
const USE_TILEMAP_WALLS := false
const GAME_SCENE_PATH := "res://Client/Game/Game.tscn"  # adjust if needed
const WALL_TILEMAP_NODE := "TileMap-Walls"              # adjust if needed

const DEFAULT_MAP_W := 30
const DEFAULT_MAP_H := 30
const FOOD_COUNT := 4

func _ready():
	var env_port = OS.get_environment("PORT")
	if env_port != "":
		PORT = int(env_port)

	print("=== MATCHMAKING SERVER (Authoritative) ===")
	print("Starting on port ", PORT)
	print("Match size: ", match_size, " players")
	print("Tick rate: ", _tick_rate, "s")

	var err = _server.listen(PORT, "127.0.0.1")
	if err != OK:
		print("ERROR: Unable to start server: ", err)
		set_process(false)
		return

	_logger_coroutine()
	_heartbeat_coroutine()

func _logger_coroutine():
	while true:
		await get_tree().create_timer(5.0).timeout
		print("
--- SERVER STATUS ---")
		print("Connected players: ", _connected_players.keys())
		print("Match queue: ", _match_queue)
		print("Active sessions: ", _match_sessions.keys())
		print("--------------------
")

func _heartbeat_coroutine():
	while true:
		await get_tree().create_timer(25.0).timeout
		for id in _peers.keys():
			var msg = Message.new()
			msg.is_echo = true
			msg.content = "ping"
			_send_to_peer(id, msg)

func _process(delta):
	# Accept connections
	if _server.is_connection_available():
		var peer = _server.take_connection()
		peer.set_no_delay(true)
		var ws_peer = WebSocketPeer.new()
		var err = ws_peer.accept_stream(peer)
		if err != OK:
			print("ERROR: Failed to accept WebSocket: ", err)
			return
		var id = _next_id
		_next_id += 1
		_peers[id] = {"ws": ws_peer, "tcp": peer, "ready": false}
		print("-> Client ", id, " connecting...")

	# Poll connections
	var to_remove := []
	for id in _peers.keys():
		var peer_data = _peers[id]
		var ws_peer: WebSocketPeer = peer_data["ws"]
		ws_peer.poll()
		match ws_peer.get_ready_state():
			WebSocketPeer.STATE_CONNECTING:
				pass
			WebSocketPeer.STATE_OPEN:
				if not peer_data["ready"]:
					peer_data["ready"] = true
					_connected(id)
				var processed := 0
				while ws_peer.get_available_packet_count() > 0 and processed < 50:
					_on_data(id, ws_peer.get_packet())
					processed += 1
			WebSocketPeer.STATE_CLOSING:
				pass
			WebSocketPeer.STATE_CLOSED:
				_disconnected(id)
				to_remove.append(id)

	for id in to_remove:
		_peers.erase(id)

	# Create matches
	if _match_queue.size() >= match_size and not _creating_match:
		create_new_match()

	# Tick active sessions
	for match_id in _match_sessions.keys():
		var session = _match_sessions[match_id]
		session["tick_timer"] += delta
		if session["tick_timer"] >= _tick_rate:
			session["tick_timer"] -= _tick_rate
			_tick_session(match_id, session)

func _connected(id: int) -> void:
	print("  Client ", id, " connected")
	_connected_players[id] = []
	_match_queue.append(id)

	var message = Message.new()
	message.server_login = true
	message.content = id
	_send_to_peer(id, message)

	emit_signal("client_connected", id)

func _disconnected(id: int) -> void:
	print("<- Client ", id, " disconnected")
	_remove_session_for_player(id)
	if _match_queue.has(id):
		_match_queue.erase(id)
	_connected_players.erase(id)
	emit_signal("client_disconnected", id)

func _remove_session_for_player(id: int) -> void:
	for match_id in _match_sessions.keys():
		if id in _match_sessions[match_id]["players"]:
			_match_sessions.erase(match_id)
			return

func _on_data(id: int, packet: PackedByteArray) -> void:
	var message := Message.new()
	message.from_raw(packet)

	# Input messages: store latest input for that peer in its session
	if message.content is Dictionary and message.content.has("player_input"):
		var dir := int(message.content["player_input"])
		for match_id in _match_sessions.keys():
			var session = _match_sessions[match_id]
			if id in session["players"]:
				session["inputs"][id] = dir
				break
		return

	# (Optional) forward other messages if you still need chat/debug

func create_new_match() -> void:
	_creating_match = true

	var new_match := []
	for i in range(match_size):
		new_match.append(_match_queue[i])

	# Send match_start with player peer IDs
	for i in range(match_size):
		var player_id = _match_queue[0]
		var msg := Message.new()
		msg.match_start = true
		msg.content = new_match
		_send_to_peer(player_id, msg)
		_match_queue.remove_at(0)

	# Update connected player groups
	for pid in new_match:
		_connected_players[pid] = new_match

	# Create authoritative session
	var match_id := _make_match_id(new_match)
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var session := {
		"players": new_match,
		"inputs": {},
		"tick_timer": 0.0,
		"started": false,
		"tick": 0,
		"rng": rng,
		"map_w": DEFAULT_MAP_W,
		"map_h": DEFAULT_MAP_H,
		"walls": {},    # Dictionary used as a set: key="x,y" -> true
		"foods": [],    # Array[Vector2i]
		"snakes": [],   # Array[Dictionary] index 0..match_size-1
		"scores": []
	}

	# Optional: load walls/map size from a TileMap scene
	if USE_TILEMAP_WALLS:
		_load_walls_from_scene(session)

	# Init per-peer input slots
	for pid in new_match:
		session["inputs"][pid] = -1

	# Init snakes in match order (index 0..1)
	for i in range(new_match.size()):
		session["snakes"].append(_make_initial_snake(session, i))
		session["scores"].append(0)

	# Init foods
	for i in range(FOOD_COUNT):
		session["foods"].append(_random_free_pos(session))

	_match_sessions[match_id] = session
	emit_signal("match_created", new_match)

	_start_countdown(match_id, new_match, 3)

func _start_countdown(match_id: String, players: Array, seconds: int) -> void:
	for i in range(seconds, 0, -1):
		var msg := Message.new()
		msg.content = {"countdown": str(i)}
		for pid in players:
			_send_to_peer(pid, msg)
		await get_tree().create_timer(1.0).timeout

	var go := Message.new()
	go.content = {"countdown": 0}
	for pid in players:
		_send_to_peer(pid, go)

	if _match_sessions.has(match_id):
		_match_sessions[match_id]["started"] = true
	_creating_match = false

# --- Authoritative tick ---
func _tick_session(match_id: String, session: Dictionary) -> void:
	if not session.get("started", false):
		return

	# 1) Apply inputs to snake directions
	for i in range(session["players"].size()):
		var peer_id: int = session["players"][i]
		var inp: int = int(session["inputs"][peer_id])
		if inp != -1:
			_apply_dir(session["snakes"][i], inp)
		# reset so stale values never carry
		session["inputs"][peer_id] = -1

	# 2) Advance simulation
	session["tick"] += 1
	_simulate_step(session)

	# 3) Broadcast state
	_broadcast_state(session)

# --- Simulation helpers ---
func _apply_dir(snake: Dictionary, new_dir: int) -> void:
	# disallow instant reverse
	var cur: int = snake["dir"]
	if (cur + 2) % 4 == new_dir:
		return
	snake["dir"] = new_dir

func _simulate_step(session: Dictionary) -> void:
	var map_w: int = session["map_w"]
	var map_h: int = session["map_h"]

	# Prepare occupancy sets
	var body_set := {}  # key="x,y" -> ownerIndex
	for si in range(session["snakes"].size()):
		var s = session["snakes"][si]
		if not s["alive"]:
			continue
		for p in s["body"]:
			body_set[_k(p)] = si

	# Compute next heads first (for head-head)
	var next_heads: Array = []
	next_heads.resize(session["snakes"].size())
	for si in range(session["snakes"].size()):
		var s = session["snakes"][si]
		if not s["alive"]:
			next_heads[si] = null
			continue
		var head: Vector2i = s["body"][0]
		next_heads[si] = head + DIRS[s["dir"]]

	# Resolve deaths from wall/bounds and head-head
	var died := []
	died.resize(session["snakes"].size())
	for i in range(died.size()):
		died[i] = false

	# head-head same cell => both die
	if session["snakes"].size() == 2:
		if next_heads[0] != null and next_heads[1] != null and next_heads[0] == next_heads[1]:
			died[0] = true
			died[1] = true

	# bounds / walls
	for si in range(session["snakes"].size()):
		if next_heads[si] == null:
			continue
		var nh: Vector2i = next_heads[si]
		if nh.x < 0 or nh.y < 0 or nh.x >= map_w or nh.y >= map_h:
			died[si] = true
			continue
		if session["walls"].has(_k(nh)):
			died[si] = true

	# Move snakes that are still alive (tentatively)
	for si in range(session["snakes"].size()):
		var s = session["snakes"][si]
		if not s["alive"]:
			continue
		if died[si]:
			s["alive"] = false
			continue

		var nh: Vector2i = next_heads[si]
		s["body"].insert(0, nh)

		# check food
		var ate_idx := _food_index_at(session, nh)
		if ate_idx != -1:
			session["scores"][si] += 1
			# respawn that food
			session["foods"][ate_idx] = _random_free_pos(session)
			# keep tail (grow): do NOT pop
		else:
			# normal move: pop tail
			s["body"].pop_back()

	# After movement, resolve body collisions (including into other bodies)
	# Rebuild body_set from new positions
	body_set.clear()
	for si in range(session["snakes"].size()):
		var s = session["snakes"][si]
		if not s["alive"]:
			continue
		for bi in range(s["body"].size()):
			var p: Vector2i = s["body"][bi]
			var key := _k(p)
			if body_set.has(key):
				# two bodies overlap => if any head involved, kill that snake
				# simplest: kill both owners
				s["alive"] = false
				var other := int(body_set[key])
				session["snakes"][other]["alive"] = false
			else:
				body_set[key] = si

	# head into body (including own body)
	for si in range(session["snakes"].size()):
		var s = session["snakes"][si]
		if not s["alive"]:
			continue
		var head: Vector2i = s["body"][0]
		# check against all other segments excluding own head
		for oi in range(session["snakes"].size()):
			var o = session["snakes"][oi]
			if not o["alive"]:
				continue
			for seg_i in range(o["body"].size()):
				if oi == si and seg_i == 0:
					continue
				if o["body"][seg_i] == head:
					s["alive"] = false
					break

	# Determine gameover
	var alive_count := 0
	var last_alive := -1
	for si in range(session["snakes"].size()):
		if session["snakes"][si]["alive"]:
			alive_count += 1
			last_alive = si

	if alive_count <= 1:
		_send_gameover(session, last_alive)

func _broadcast_state(session: Dictionary) -> void:
	var msg := Message.new()
	msg.content = {
		"state": true,
		"tick": session["tick"],
		"players": [],
		"foods": []
	}

	for si in range(session["snakes"].size()):
		var s = session["snakes"][si]
		var body_out := []
		for p in s["body"]:
			body_out.append([p.x, p.y])
		msg.content["players"].append({
			"alive": s["alive"],
			"dir": s["dir"],
			"score": session["scores"][si],
			"body": body_out
		})

	for f in session["foods"]:
		msg.content["foods"].append([f.x, f.y])

	for pid in session["players"]:
		_send_to_peer(pid, msg)

func _send_gameover(session: Dictionary, winner_index: int) -> void:
	# prevent repeated gameover spam
	if session.get("gameover_sent", false):
		return
	session["gameover_sent"] = true

	var msg := Message.new()
	msg.content = {
		"gameover": true,
		"winner": winner_index,
		"scores": session["scores"]
	}
	for pid in session["players"]:
		_send_to_peer(pid, msg)

# --- Spawn / map helpers ---
func _make_initial_snake(session: Dictionary, index: int) -> Dictionary:
	# Replace with your SpawnPoint logic if you want.
	var map_w: int = session["map_w"]
	var map_h: int = session["map_h"]
	var head := Vector2i(5, 5) if index == 0 else Vector2i(map_w - 6, map_h - 6)
	var dir := 1 if index == 0 else 3
	return {
		"alive": true,
		"dir": dir,
		"body": [head, head - DIRS[dir], head - DIRS[dir]*2]
	}

func _random_free_pos(session: Dictionary) -> Vector2i:
	var rng: RandomNumberGenerator = session["rng"]
	var map_w: int = session["map_w"]
	var map_h: int = session["map_h"]

	for _tries in range(5000):
		var p := Vector2i(rng.randi_range(0, map_w - 1), rng.randi_range(0, map_h - 1))
		if session["walls"].has(_k(p)):
			continue
		if _pos_in_snakes(session, p):
			continue
		if _pos_in_foods(session, p):
			continue
		return p

	# Fallback (should never happen unless map is full)
	return Vector2i(1, 1)

func _pos_in_snakes(session: Dictionary, p: Vector2i) -> bool:
	for s in session["snakes"]:
		for bp in s["body"]:
			if bp == p:
				return true
	return false

func _pos_in_foods(session: Dictionary, p: Vector2i) -> bool:
	for f in session["foods"]:
		if f == p:
			return true
	return false

func _food_index_at(session: Dictionary, p: Vector2i) -> int:
	for i in range(session["foods"].size()):
		if session["foods"][i] == p:
			return i
	return -1

func _k(p: Vector2i) -> String:
	return str(p.x) + "," + str(p.y)

func _load_walls_from_scene(session: Dictionary) -> void:
	# Optional: load TileMap walls into a set.
	# This runs on the server; make sure the resource exists in the server build.
	var packed := load(GAME_SCENE_PATH)
	if packed == null:
		push_warning("Could not load game scene for walls; using defaults")
		return
	var inst = packed.instantiate()
	add_child(inst)
	var tm: TileMap = inst.get_node_or_null(WALL_TILEMAP_NODE)
	if tm == null:
		push_warning("Could not find TileMap node; using defaults")
		inst.queue_free()
		return
	var used := tm.get_used_rect()
	session["map_w"] = used.size.x
	session["map_h"] = used.size.y
	for cell in tm.get_used_cells(0):
		session["walls"][_k(cell)] = true
	inst.queue_free()

# --- networking ---
func _send_to_peer(id: int, msg: Message) -> void:
	if not _peers.has(id):
		return
	var ws_peer: WebSocketPeer = _peers[id]["ws"]
	if ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	ws_peer.send(msg.get_raw())

func _make_match_id(players: Array) -> String:
	var a := Array(players)
	a.sort()
	return ":".join(a.map(func(x): return str(x)))
