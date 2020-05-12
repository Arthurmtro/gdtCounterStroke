extends CanvasLayer


func _ready():
	network.connect("server_created", self, "_on_ready_to_play")
	network.connect("join_success", self, "_on_ready_to_play")
	network.connect("join_fail", self, "_on_join_fail")
	get_tree().paused = false
	
	# option Button
	$PanelPlayer/btSelectTeam.add_item("Equipe blueu", 1)
	$PanelPlayer/btSelectTeam.add_item("Equipe rouge", 2)

func set_player_info():
	if (!$PanelPlayer/txtPlayerName.text.empty()):
		gamestate.player_info.name = $PanelPlayer/txtPlayerName.text
	gamestate.player_info.char_color = $PanelPlayer/btColor.color
	gamestate.player_info.team_id = $PanelPlayer/btSelectTeam.get_selected_id()

func _on_btCreate_pressed():
	# Properly set the local player information
	set_player_info()
	
	# Gather values from the GUI and fill the network.server_info dictionary
	if (!$PanelHost/txtServerName.text.empty()):
		network.server_info.name = $PanelHost/txtServerName.text
	network.server_info.max_players = int($PanelHost/txtMaxPlayers.value)
	network.server_info.used_port = int($PanelHost/txtServerPort.text)
	
	# And create the server, using the function previously added into the code
	network.create_server()
	print(gamestate.player_info)


func _on_btJoin_pressed():
	# Properly set the local player information
	set_player_info()
	
	var port = int($PanelJoin/txtJoinPort.text)
	var ip = $PanelJoin/txtJoinIP.text
	network.join_server(ip, port)


func _on_ready_to_play():
	get_tree().change_scene("res://scenes/game_world.tscn")


func _on_join_fail():
	print("Failed to join server")


func _on_btColor_color_changed(color):
	$PanelPlayer/PlayerIcon.modulate = color


func _on_btDefaultColor_pressed():
	$PanelPlayer/PlayerIcon.modulate = Color(1, 1, 1)
	$PanelPlayer/btColor.color = Color(1, 1, 1)

