extends Control

# FIXED: Added the port constant at the top so your print statements can read it!
const DEFAULT_PORT = 5000

@onready var ip_input = $IPInput as LineEdit
@onready var ip_label = $IPLabel as Label

func _on_host_button_pressed() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 2)
	if error != OK:
		print("❌ Failed to initialize host server on port: ", DEFAULT_PORT)
		return
	multiplayer.multiplayer_peer = peer
	print("📡 Host Room opened on port ", DEFAULT_PORT, ". Waiting for guest connection...")
	
	# Automatically connect a listener to launch the scene swap RPC once the guest hooks in
	multiplayer.peer_connected.connect(func(id):
		print("✅ Guest connected! Peer ID: ", id)
		# Host triggers the global synchronized scene switch!
		rpc("change_scene", "res://CombatArena.tscn")
	)

func _on_join_button_pressed() -> void:
	var target_ip = ip_input.text.strip_edges() if ip_input else ""
	if target_ip == "": 
		target_ip = "127.0.0.1"
		
	var peer = ENetMultiplayerPeer.new()
	# FIXED: Changed DEFAULT_PORT to read the variable cleanly
	var error = peer.create_client(target_ip, DEFAULT_PORT)
	if error != OK:
		print("❌ Client failed to route pathway connection to: ", target_ip)
		return
	multiplayer.multiplayer_peer = peer
	print("🔌 Connecting to Host IP: ", target_ip, "...")

func _on_offline_button_pressed() -> void:
	# Offline vs AI Bot shortcut bypasses networking completely
	get_tree().change_scene_to_file("res://CombatArena.tscn")

# --- REQUIRED INSTRUCTION FIXED: THE GLOBAL SYNCHRONIZED SCENE SWITCH RPC ---
@rpc("any_peer", "call_local", "reliable")
func change_scene(scene_path: String) -> void:
	print("🚀 Handshake complete! Transitioning both clients to scene: ", scene_path)
	get_tree().change_scene_to_file(scene_path)

func get_my_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for ip in addresses:
		if ip.begins_with("10.220."): return ip
	for ip in addresses:
		if not ":" in ip and ip != "127.0.0.1":
			if ip.begins_with("10.") or ip.begins_with("172."): return ip
	for ip in addresses:
		if not ":" in ip and ip != "127.0.0.1":
			if ip.begins_with("192.168."): return ip
	return "127.0.0.1"
