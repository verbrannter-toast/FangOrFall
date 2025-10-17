extends Node

func _ready():
	print("=================================================")
	print("STARTING DEDICATED SERVER")
	print("=================================================")
	get_tree().change_scene_to_file("res://Server/Server.tscn")
