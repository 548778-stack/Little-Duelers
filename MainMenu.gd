extends Control

const DEFAULT_PORT = 5000

# FIXED PATH HIERARCHY: We use flexible lookups on ready to avoid path errors
@onready var ip_input = find_child("IPInput", true, false) as LineEdit
@onready var ip_label = find_child("IPLabel", true, false) as Label

func _ready() -> void:
	# Safely verify if the node was successfully fetched by the path processor
	if ip_label:
		var my_ip = get_my_local_ip()
		ip_label.text = "YOUR MATCH IP: " + my_ip
		ip_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2)) # Gold Glow
		print("📡 MainMenu: IP display node found dynamically.")
	else:
		print("⚠️ Warning: IPLabel not found via dynamic search path.")

func _on_host_button_pressed() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 2)
	if error != OK:
		print("❌ Failed to initialize host server on port: ", DEFAULT_PORT)
		return
	multiplayer.multiplayer_peer = peer
	print("📡 Host Room opened. Waiting for guest connection...")
	
	multiplayer.peer_connected.connect(func(id):
		print("✅ Guest connected! Peer ID: ", id)
		rpc("change_scene", "res://Lobby.tscn")
	)

func _on_join_button_pressed() -> void:
	var target_ip = ip_input.text.strip_edges() if ip_input else ""
	if target_ip == "": 
		target_ip = "127.0.0.1"
		
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, DEFAULT_PORT)
	if error != OK:
		print("❌ Client failed to route pathway connection to: ", target_ip)
		return
	multiplayer.multiplayer_peer = peer
	print("🔌 Connecting to Host IP: ", target_ip, "...")

func _on_offline_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Lobby.tscn")

@rpc("any_peer", "call_local", "reliable")
func change_scene(scene_path: String) -> void:
	print("🚀 Handshake complete! Transitioning both clients to staging scene: ", scene_path)
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
