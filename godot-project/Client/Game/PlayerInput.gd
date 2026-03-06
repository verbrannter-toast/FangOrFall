extends Node

var relay_client: ClientManager
var player

var _committed_direction: int = -1

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
		if new_direction == -1:
			return

		# validate against last server-confirmed direction to fix 180 turn
		var base = _committed_direction if _committed_direction != -1 else player.current_direction
		if is_180(base, new_direction):
			return

		set_direction(new_direction)

func set_committed_direction(dir: int):
	_committed_direction = dir

func set_direction(dir: int):
	if dir == -1:
		return
	player.current_direction = dir
	var message = Message.new()
	message.is_echo = false
	message.content = { "player_input": dir }
	relay_client.send_data(message)

func is_180(current_dir: int, new_dir: int) -> bool:
	return (current_dir + 2) % 4 == new_dir
