extends Node

const DEFAULT_PORT = 5000
var vs_ai: bool = false

# --- INSTRUCTION FIXED: CENTRALIZED P2P PLAYER CHOICE VAULT ---
var player_choices: Dictionary = {
	1: {"class": "Slingshotter", "ability": "Piercing Shot"},
	"guest": {"class": "Slingshotter", "ability": "Piercing Shot"}
}

var selected_map: String = "Standard Field"
var starting_lives: int = 3


# --- THE LIFELONG P2P CONNECTION & DATA VAULT ---
var lobby_data: Dictionary = {
	1: {"character": "Slingshotter", "ability": "Piercing Shot"},
	"guest": {"character": "Slingshotter", "ability": "Piercing Shot"}
}


func _ready() -> void:
	# Keep network listeners permanently alive in the background
	multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(id: int) -> void:
	print("✅ NetworkManager: Guest connected to background thread pipeline! Peer ID: ", id)
	# Initialize default fallback slot for the newly arrived client
	lobby_data[id] = {"character": "Slingshotter", "ability": "Piercing Shot"}
	
	if multiplayer.is_server():
		# Host triggers the global synchronized staging room scene switch!
		rpc("change_scene", "res://Lobby.tscn")

@rpc("any_peer", "call_local", "reliable")
func change_scene(scene_path: String) -> void:
	if scene_path == "res://MainMenu.tscn":
		vs_ai = false # Clean slate reset on menu exit
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
