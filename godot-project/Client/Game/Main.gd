extends Node

func _ready():
	# Check command line arguments
	var is_server = false
	for arg in OS.get_cmdline_args():
		if arg == "--server":
			is_server = true
			break
	
	# Also check feature tags
	if OS.has_feature("dedicated_server"):
		is_server = true
	
	# Load appropriate scene
	if is_server:
		print("=================================================")
		print("STARTING DEDICATED SERVER")
		print("=================================================")
		get_tree().change_scene_to_file("res://Server/Server.tscn")
	else:
		print("Starting client...")
		get_tree().change_scene_to_file("res://Client/Client.tscn")
