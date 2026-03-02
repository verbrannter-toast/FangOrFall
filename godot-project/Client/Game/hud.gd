extends CanvasLayer

@onready var my_panel = $MyPanel/Label
@onready var opp_panel = $OppPanel/Label

var _my_player: int

func setup(my_player: int, players: Array):
	_my_player = my_player
	
func update(scores: Array):
	for i in range(scores.size()):
		if i == _my_player:
			my_panel.text = " My Score: %d"%[scores[i]]
		else:
			opp_panel.text = " Opp Score: %d"%[scores[i]]

func countdown(text: String):
	$CountdownContainer/CountdownLabel.text = text
	$CountdownContainer/CountdownLabel.show()
	await get_tree().create_timer(1.0).timeout
	$CountdownContainer/CountdownLabel.hide()
