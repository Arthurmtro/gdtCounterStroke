# This source code is provided as reference/companion material for the Godot Multiplayer Setup tutorial
# that can be freely found at http://kehomsforge.com and should not be commercialized
# in any form. It should remain free!
#
# By Yuri Sarudiansky

extends Node2D

var player_row = {}
onready var current_time = 0
var from_to = {}
var move_dir = Vector2()

func _ready():
	# Connect event handler to the player_list_changed signal
	network.connect("player_list_changed", self, "_on_player_list_changed")
	# Must act if disconnected from the server
	network.connect("disconnected", self, "_on_disconnected")
	# Once a new ping measurement is given, let's update the value within the HUD
	network.connect("ping_updated", self, "_on_ping_updated")
	# If we are in the server, connect to the event that will deal with player despawning
	if (get_tree().is_network_server()):
		network.connect("player_removed", self, "_on_player_removed")
	
	# After receiving and fully decoding a new snapshot, apply it to the game world
	gamestate.connect("snapshot_received", self, "apply_snapshot")
	
	# Update the lblLocalPlayer label widget to display the local player name
	$HUD/PanelPlayerList/lblLocalPlayer.text = gamestate.player_info.name
	
	# Hide the server info panel if on the server - it doesn't make any sense anyway
	if (get_tree().is_network_server()):
		$HUD/PanelServerInfo.hide()
	
	# Spawn the players
	if (get_tree().is_network_server()):
		spawn_players(gamestate.player_info, 1)
	else:
		rpc_id(1, "spawn_players", gamestate.player_info, -1)


func _process(delta):
	if (Input.is_action_pressed("toggle_score")):
		$HUD/PanelPlayerList.visible = true
	else:
		$HUD/PanelPlayerList.visible = false
	
	# Interpolate the state
	var count_time = gamestate.update_delta
	for p in from_to:
		if (from_to[p].time >= count_time):
			continue
		
		from_to[p].time += delta
		var alpha = from_to[p].time / count_time
		from_to[p].node.position = lerp(from_to[p].from_loc, from_to[p].to_loc, alpha)
		from_to[p].node.rotation = lerp(from_to[p].from_rot, from_to[p].to_rot, alpha)
	
	# Update the timeout counter
	current_time += delta
	if (current_time < gamestate.update_delta):
		return
	
	# "Reset" the time counting
	current_time -= gamestate.update_delta
	
	# And update the game state
	update_state()
	
	


# Update and generate a game state snapshot. 
func update_state():
	# If not on the server, bail
	if (!get_tree().is_network_server()):
		return
	
	# Initialize the "high level" snapshot
	var snapshot = {
		signature = gamestate.snapshot_signature,
		player_data = [],
		bot_data = [],
	}
	
	# Iterate through each player.
	for p_id in network.players:
		# Locate the player's node. Even if there is no input/update, it's state will be dumped
		# into the snapshot anyway.
		var player_node = get_node(str(p_id))
		
		if (!player_node):
			# Ideally should give a warning that a player node wasn't found
			continue
		
		var p_pos = player_node.position
		var p = player_node
		var p_rot = player_node.rotation
		
		# Check if there is any input for this player. In that case, update the state
		if (gamestate.player_input.has(p_id) && gamestate.player_input[p_id].size() > 0):
			# Calculate the delta
			var delta = gamestate.update_delta / float(gamestate.player_input[p_id].size())
			
			# Now, for each input entry, calculate the resulting state
			for input in gamestate.player_input[p_id]:
				var move_dir = Vector2()
				# Build the movement direction vector based on the input
				if (input.up):
					move_dir.y -= 1
				if (input.down):
					move_dir.y += 1
				if (input.left):
					move_dir.x -= 1
				if (input.right):
					move_dir.x += 1
				
				# Update the position
				p_pos += p.move_and_slide(move_dir.normalized() * player_node.move_speed * delta)
				# And rotation
				p_rot = p_pos.angle_to_point(input.mouse_pos)
			
			# Cleanup the input vector
			#move_dir = p.move_and_slide(p_pos)
			gamestate.player_input[p_id].clear()
		
		# Build player_data entry
		var pdata_entry = {
			net_id = p_id,
			location = p_pos,
			rot = p_rot,
			col = network.players[p_id].char_color,
		}
		# Append into the snapshot
		snapshot.player_data.append(pdata_entry)
	
	# Encode and broadcast the snapshot - if there is at least one connected client
	if (network.players.size() > 1):
		gamestate.encode_snapshot(snapshot)
	apply_snapshot(snapshot)
	# Make sure the next update will have the correct snapshot signature
	gamestate.snapshot_signature += 1
	
	# Update amount of Ammo of the player
	$HUD/PanelPlayer/EquipedWeapon/Label.set_text(str(gamestate.player_info.ammo))


func apply_snapshot(snapshot):
	# In here we assume the obtained snapshot is newer than the last one
	# Iterate through player data
	for p in snapshot.player_data:
		# Locate the avatar node belonging to the currently iterated player
		var pnode = get_node(str(p.net_id))
		if (!pnode):
			# Depending on the synchronization mechanism, this may not be an error!
			# For now assume the entities are spawned and kept in sync so just continue
			# the loop
			continue
		
		if (from_to.has(p.net_id)):
			# Currently iterated player already has previous data. Update the interpolation
			# control variables
			var crot = from_to[p.net_id].to_rot
			
			from_to[p.net_id].from_loc = from_to[p.net_id].to_loc
			from_to[p.net_id].from_rot = from_to[p.net_id].to_rot
			from_to[p.net_id].to_loc = p.location
			from_to[p.net_id].to_rot = p.rot
			from_to[p.net_id].time = 0.0
			from_to[p.net_id].node = pnode
			
			$lblTMPDebug.text = "from: " + str(from_to[p.net_id].from_rot) + " | to: " + str(from_to[p.net_id].to_rot)
			
		else:
			# There isn't any previous data for this player. Create the initial interpolation
			# data. The next _process() iteration will take care of applying the state
			from_to[p.net_id] = {
				from_loc = p.location,
				from_rot = p.rot,
				to_loc = p.location,
				to_rot = p.rot,
				time = gamestate.update_delta,
				node = pnode,
			}
		
		# There is no point in interpolating the color so just apply it
		pnode.set_dominant_color(p.col)
		
		
	# Iterate through bot data
	for b in snapshot.bot_data:
		# Locate the bot node belonging to the currently iterated bot
		var bnode = get_node(gamestate.bot_info[b.bot_id].name)
		if (!bnode):
			continue
		
		# Apply location, rotation and color to the bot
		bnode.update_state(b)



func _on_player_list_changed():
	# Update the server name
	$HUD/PanelServerInfo/lblServerName.text = "Server: " + network.server_info.name
	
	# First remove all children from the boxList widget
	for c in $HUD/PanelPlayerList/boxListBlue.get_children():
		c.queue_free()
	for c in $HUD/PanelPlayerList/boxListRed.get_children():
		c.queue_free()
	
	# Reset the row dictionary
	player_row.clear()
	
	# Preload the entry control
	var entry_class = load("res://scenes/ui_player_list_entry.tscn")
	
	# Now iterate through the player list creating a new entry into the boxList
	for p in network.players:
		if (p != gamestate.player_info.net_id):
			var nentry = entry_class.instance()
			nentry.net_id = p
			nentry.set_info(network.players[p].name, network.players[p].char_color)
			nentry.connect("whisper_clicked", $HUD/ChatRoot, "_on_whisper")
			if (gamestate.player_info.team_id == 2) :
				$HUD/PanelPlayerList/boxListBlue.add_child(nentry)
				player_row[network.players[p].net_id] = nentry
			else :
				$HUD/PanelPlayerList/boxListRed.add_child(nentry)
				player_row[network.players[p].net_id] = nentry


func _on_player_removed(pinfo):
	gamestate.player_input.erase(pinfo.net_id)
	from_to.erase(pinfo.net_id)
	despawn_player(pinfo)


func _on_disconnected():
	# Ideally pause the internal simulation and display a message box here.
	# From the answer in the message box change back into the main menu scene
	get_tree().change_scene("res://scenes/main_menu.tscn")


func _on_ping_updated(peer_id, value):
	if (peer_id == gamestate.player_info.net_id):
		# Updating the ping for local machine
		$HUD/PanelServerInfo/lblPing.text = "Ping: " + str(int(value))
	else:
		# Updating the ping for someone else in the game
		if (player_row.has(peer_id)):
			player_row[peer_id].set_latency(value)


# Spawns a new player actor, using the provided player_info structure and the given spawn index
remote func spawn_players(pinfo, spawn_index):
	if (network.fake_latency > 0):
		yield(get_tree().create_timer(network.fake_latency / 1000), "timeout")
	
	# If the spawn_index is -1 then we define it based on the size of the player list
	if (spawn_index == -1):
		spawn_index = network.players.size()
	
	if (get_tree().is_network_server() && pinfo.net_id != 1): # Blue spaws
		# We are on the server and the requested spawn does not belong to the server
		# Iterate through the connected players
		var s_index = 1      # Will be used as spawn index
		for id in network.players:
			# Spawn currently iterated player within the new player's scene, skipping the new player for now
			if (id != pinfo.net_id):
				rpc_id(pinfo.net_id, "spawn_players", network.players[id], s_index)
			
			# Spawn the new player within the currently iterated player as long it's not the server
			# Because the server's list already contains the new player, that one will also get itself!
			if (id != 1):
				rpc_id(id, "spawn_players", pinfo, spawn_index)
			
			s_index += 1
			
	
	print("Spawning actor for player ", pinfo.name, "(", pinfo.net_id, ") - ", spawn_index)
	
	# Load the scene and create an instance
	if (pinfo.team_id == 2):
		pinfo.actor_path = "res://scenes/player2.tscn"
	var pclass = load(pinfo.actor_path)
	var nactor = pclass.instance()
	# Setup player customization (well, the color)
	nactor.set_dominant_color(pinfo.char_color)
	# And the actor position
	if (pinfo.team_id == 1):
		nactor.position = $SpawnPoints.get_node('b' + str(spawn_index)).position
	elif (pinfo.team_id == 2):
		nactor.position = $SpawnPoints.get_node('r' + str(spawn_index)).position
	# If this actor does not belong to the server, change the node name and network master accordingly
	if (pinfo.net_id != 1):
		nactor.set_network_master(pinfo.net_id)
	nactor.set_name(str(pinfo.net_id))
	# Finally add the actor into the world
	add_child(nactor)


remote func despawn_player(pinfo):
	if (network.fake_latency > 0):
		yield(get_tree().create_timer(network.fake_latency / 1000), "timeout")
	
	if (get_tree().is_network_server()):
		for id in network.players:
			# Skip disconnecte player and server from replication code
			if (id == pinfo.net_id || id == 1):
				continue
			
			# Replicate despawn into currently iterated player
			rpc_id(id, "despawn_player", pinfo)
	
	# Try to locate the player actor
	var player_node = get_node(str(pinfo.net_id))
	if (!player_node):
		print("Cannoot remove invalid node from tree")
		return
	
	# Mark the node for deletion
	player_node.queue_free()


func _on_txtFakeLatency_value_changed(value):
	network.fake_latency = value


func _on_btClearFocus_pressed():
	$HUD/btClearFocus.release_focus()
