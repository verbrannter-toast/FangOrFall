extends CanvasLayer

@onready var winner_label = $CenterContainer/VBoxContainer/WinnerLabel
@onready var player1_score = $CenterContainer/VBoxContainer/ScoreContainer/Player1Score
@onready var player2_score = $CenterContainer/VBoxContainer/ScoreContainer/Player2Score
@onready var info_label = $CenterContainer/VBoxContainer/InfoLabel

var winner: int = -1
var my_player: int = 0
var scores: Array = [0, 0]  # [Player0, Player1]

signal return_to_menu

func setup(winner_player: int, my_player_number: int, player_scores: Array):
	winner = winner_player
	my_player = my_player_number
	scores = player_scores
	
	print("[GAMEOVER] Setup called - Winner:", winner, " MyPlayer:", my_player)
	
	# Winner Text
	if winner == -1:
		winner_label.text = "DRAW!"
		winner_label.add_theme_color_override("font_color", Color.YELLOW)
	elif winner == my_player:
		winner_label.text = "YOU WIN!"
		winner_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		winner_label.text = "YOU LOSE!"
		winner_label.add_theme_color_override("font_color", Color.RED)
	
	# Scores
	if player1_score != null and scores.size() >= 1:
		player1_score.text = "Player 1: " + str(scores[0]) + " points"
	if player2_score != null and scores.size() >= 2:
		player2_score.text = "Player 2: " + str(scores[1]) + " points"
	
	start_countdown(5)

func start_countdown(seconds: int):
	for i in range(seconds, 0, -1):
		if info_label == null:
			break
		info_label.text = "Returning to menu in " + str(i) + " second" + ("s" if i > 1 else "") + "..."
		await get_tree().create_timer(1.0).timeout
	
	if info_label != null:
		info_label.text = "Returning to menu..."
	emit_signal("return_to_menu")

func _input(event):
	# Allow skipping with Space/Enter
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			emit_signal("return_to_menu")
