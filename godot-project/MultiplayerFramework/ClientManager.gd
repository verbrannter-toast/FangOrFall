extends Node

class_name ClientManager

@export var websocket_url: String = "game.fangorfall.win"
@export var port: int = 443

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
	# clean the URL
	var clean_url = websocket_url.strip_edges()
	clean_url = clean_url.replace("https://", "")
	clean_url = clean_url.replace("http://", "")
	clean_url = clean_url.replace("ws://", "")
	clean_url = clean_url.replace("wss://", "")
	
	# remove port from URL if present
	if ":" in clean_url:
		var parts = clean_url.split(":")
		clean_url = parts[0]
		# optionally extract port from URL
		if parts.size() > 1:
			var url_port = parts[1].to_int()
			if url_port > 0:
				port = url_port
	
	# remove trailing slash
	clean_url = clean_url.trim_suffix("/")
	
	# determine if this is a secure connection
	var is_secure = not (clean_url == "localhost" or clean_url.begins_with("127.0.0.1") or clean_url.begins_with("192.168.") or clean_url.begins_with("10."))
	
	# build WebSocket URI
	if is_secure:
		# use WSS on port 443 (default, no need to specify)
		uri = "wss://" + clean_url
	else:
		# use WS with specified port
		uri = "ws://" + clean_url + ":" + str(port)
	
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
		print("ERROR: Failed to connect - Error code: ", err)
		print("Possible reasons:")
		print("  - Server not running")
		print("  - Wrong URL or port")
		print("  - Firewall blocking connection")
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
	if not _is_connected and _client == null:
		return
	
	# Try-Catch Pattern with early returns
	if _client == null:
		_is_connected = false
		set_process(false)
		return
	
	if not is_instance_valid(_client):
		_client = null
		_is_connected = false
		set_process(false)
		return
	
	# _client is guaranteed to be valid here
	_client.poll()
	
	var state = _client.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_CONNECTING:
			# still connecting
			pass
			
		WebSocketPeer.STATE_OPEN:
			if not _is_connected:
				_is_connected = true
			if not _initialised:
				print("  WebSocket connected!")
				_initialised = true
			_process_packets()
			
		WebSocketPeer.STATE_CLOSING:
			# connection closing
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
	if _client == null or not is_instance_valid(_client):
		return
	
	# check state again
	if _client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	
	var packet_count = _client.get_available_packet_count()
	
	# max 100 packets per frame to prevent freeze
	var max_packets = min(packet_count, 100)
	
	for i in range(max_packets):
		# check before every packet
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
	
	# SERVER LOGIN - Receive ID
	if message.server_login:
		_id = message.content
		_initialised = true
		print("  Logged in with ID: ", _id)
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
		
		print("  Match started!")
		print("  My ID: ", _id)
		print("  My Player Number: ", _player_number)
		print("  All Players: ", _match)
		
		# mark as ready
		players_ready = true
		emit_signal("on_players_ready")
		emit_signal("on_message", message)
		return
	
	# REGULAR MESSAGE - Game data
	emit_signal("on_message", message)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		disconnect_from_server()
