extends Control

@onready var ip_input = find_child("IPInput", true, false) as LineEdit
@onready var ip_label = find_child("IPLabel", true, false) as Label

func _ready() -> void:
	if ip_label:
		var my_ip = NetworkManager.get_my_local_ip()
		ip_label.text = "YOUR MATCH IP: " + my_ip
		ip_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))

func _on_host_button_pressed() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(NetworkManager.DEFAULT_PORT, 2)
	if error != OK: return
	multiplayer.multiplayer_peer = peer
	print("📡 Host Room opened on port 5000. Waiting for client...")

func _on_join_button_pressed() -> void:
	var target_ip = ip_input.text.strip_edges() if ip_input else "127.0.0.1"
	if target_ip == "": target_ip = "127.0.0.1"
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, NetworkManager.DEFAULT_PORT)
	if error != OK: return
	multiplayer.multiplayer_peer = peer
	print("🔌 Connecting to Host IP: ", target_ip, "...")

func _on_offline_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Lobby.tscn")
