extends Node

class_name ClientManager

@export var websocket_url: String = "192.168.178.130"
@export var port: int = 9080

var _match = []
var _id = 0
var _player_number = 0
var _client: WebSocketPeer
var _initialised = false
var players_ready: bool = false
var _is_connected: bool = false

var uri: String

signal on_message(message: Message)
signal on_players_ready()

func send_data(message: Message):
	if not _is_connected:
		return
	
	if _client == null or not is_instance_valid(_client):
		_is_connected = false
		return
	
	if _client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	
	var err = _client.send(message.get_raw())
	if err != OK:
		print("ERROR sending data: ", err)
	
	if message.is_echo:
		emit_signal("on_message", message)

func connect_to_server():
	uri = "ws://" + websocket_url + ":" + str(port)
	
	print("Connecting to: ", uri)
	
	players_ready = false
	_match = []
	_id = 0
	_player_number = 0
	_client = WebSocketPeer.new()
	_initialised = false
	_is_connected = false

	var err = _client.connect_to_url(uri)
	if err != OK:
		print("ERROR: Failed to connect: ", err)
		set_process(false)
	else:
		print("WebSocket connection initiated...")
		set_process(true)

func disconnect_from_server():
	_is_connected = false
	if _client != null and is_instance_valid(_client):
		_client.close()
	_client = null
	set_process(false)

func _process(_delta):
	# Guard: Früher Exit wenn nicht verbunden oder Client null
	if not _is_connected and _client == null:
		return
	
	# Try-Catch Pattern mit frühen Returns
	if _client == null:
		_is_connected = false
		set_process(false)
		return
	
	if not is_instance_valid(_client):
		_client = null
		_is_connected = false
		set_process(false)
		return
	
	# Ab hier ist _client garantiert valid
	_client.poll()
	
	var state = _client.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_CONNECTING:
			# Still connecting
			pass
			
		WebSocketPeer.STATE_OPEN:
			# Mark as connected
			if not _is_connected:
				_is_connected = true
			
			# Connection established
			if not _initialised:
				print("✓ WebSocket connected!")
			
			# Process packets mit extra Safety
			_process_packets()
			
		WebSocketPeer.STATE_CLOSING:
			# Connection closing
			_is_connected = false
			
		WebSocketPeer.STATE_CLOSED:
			if _client != null and is_instance_valid(_client):
				var code = _client.get_close_code()
				var reason = _client.get_close_reason()
				print("WebSocket closed with code: %d, reason: %s" % [code, reason])
			
			_client = null
			_is_connected = false
			set_process(false)

func _process_packets():
	# Extra sichere Packet-Verarbeitung
	if _client == null or not is_instance_valid(_client):
		return
	
	# Prüfe State nochmal
	if _client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	
	var packet_count = _client.get_available_packet_count()
	
	# Limit: Max 100 packets pro Frame (verhindert Freeze)
	var max_packets = min(packet_count, 100)
	
	for i in range(max_packets):
		# Check vor JEDEM Packet
		if _client == null or not is_instance_valid(_client):
			print("WARNING: Client became null during packet processing")
			break
		
		if _client.get_ready_state() != WebSocketPeer.STATE_OPEN:
			break
		
		if _client.get_available_packet_count() == 0:
			break
		
		var packet = _client.get_packet()
		if packet.size() > 0:
			_on_data(packet)

func _on_data(data: PackedByteArray):
	var message = Message.new()
	message.from_raw(data)
	
	# SERVER LOGIN - Receive our ID
	if message.server_login:
		_id = message.content
		_initialised = true
		print("✓ Logged in with ID: ", _id)
		emit_signal("on_message", message)
		return
	
	# MATCH START - Game begins
	if message.match_start:
		if _id == 0:
			print("ERROR: Received match_start but no ID!")
			return
		
		_match = message.content as Array
		_player_number = _match.find(_id)
		
		if _player_number == -1:
			print("ERROR: My ID ", _id, " not in match: ", _match)
			return
		
		print("✓ Match started!")
		print("  My ID: ", _id)
		print("  My Player Number: ", _player_number)
		print("  All Players: ", _match)
		
		# Mark as ready
		players_ready = true
		emit_signal("on_players_ready")
		emit_signal("on_message", message)
		return
	
	# REGULAR MESSAGE - Game data
	emit_signal("on_message", message)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		disconnect_from_server()
