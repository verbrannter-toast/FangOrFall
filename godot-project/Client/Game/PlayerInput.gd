extends Node

# is_host removed — both players send input to the server
var relay_client: ClientManager
var player

func _input(event):
	if player == null:
		return

	if event is InputEventKey and event.is_pressed():
		var new_direction = -1
		if event.keycode == KEY_UP or event.keycode == KEY_W:
			new_direction = 0
		if event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			new_direction = 1
		if event.keycode == KEY_DOWN or event.keycode == KEY_S:
			new_direction = 2
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			new_direction = 3
		if new_direction != -1:
			if is_turn(player.current_direction, new_direction):
				print("[INPUT] 180 turn detected — ignoring")
				return
		set_direction(new_direction)

func set_direction(dir: int):
	if dir == -1:
		return

	# Apply locally for responsive feel
	player.current_direction = dir

	# Send to server — server collects and broadcasts on next tick
	var message = Message.new()
	message.is_echo = false
	message.content = { "player_input": dir }
	relay_client.send_data(message)

func is_turn(current_dir: int, new_dir: int) -> bool:
	return (current_dir + 2) % 4 == new_dir
