extends Node

# --- GAME MODE TRACKING ---
var max_allowed_players: int = 2
var is_match_active: bool = false
var is_game_over: bool = false
var is_host_peer: bool = false
var is_single_player: bool = false
# --- GAME MODES & TEAMS ---
const GAME_MODES: Dictionary = {
	"1v1": {"team_size": 1, "label": "Ranked 1v1"},
	"2v2": {"team_size": 2, "label": "Ranked 2v2"},
	"3v3": {"team_size": 3, "label": "Ranked 3v3"},
	# Free For All: 3-5 players, everyone for themselves.
	"ffa": {"team_size": 1, "label": "Free For All", "min": 3, "max": 5},
}
# Free For All: once 3 players are queued, wait this long for more (a 5th
# player starts it right away), then start with whoever is there.
const FFA_WAIT_SECONDS: float = 30.0
const FFA_COLORS: Array = [Color(1.0, 0.85, 0.2), Color(0.3, 0.9, 1.0), Color(1.0, 0.45, 0.9), Color(0.5, 1.0, 0.4), Color(1.0, 0.6, 0.25)]
# Spawns around the arena, everyone facing the middle.
const FFA_SPAWNS: Array = [Vector3(-15, 1, 0), Vector3(15, 1, 0), Vector3(0, 1, -15), Vector3(0, 1, 15), Vector3(-15, 1, -15)]
const TEAM_NAMES: Array = ["BLUE", "RED"]
const TEAM_COLORS: Array = [Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.3)]
# Spawn spread along Z for each team size (team 0 at x = -15, team 1 at x = 15).
const TEAM_SPAWN_Z: Dictionary = {1: [0.0], 2: [-3.5, 3.5], 3: [-7.0, 0.0, 7.0]}

var game_mode: String = "1v1"
var team_size: int = 1
var is_ffa: bool = false
var ffa_wait_timer: float = -1.0 # counts up once enough players are queued
var ffa_places: Dictionary = {} # peer_id -> final placement (1 = winner)
# Everyone in a match gets a peer ID 1..N from the sorted room roster; 1 = host.
var local_peer_id: int = 1
var player_teams: Dictionary = {} # peer_id -> 0 (Blue) / 1 (Red)
var dead_peers: Dictionary = {} # peer_id -> true once eliminated (or left)
var forfeited_peers: Dictionary = {} # peer_id -> true if they quit/disconnected (always a loss)
var match_start_elos: Dictionary = {} # peer_id -> ELO when the match started
var match_setup_done: bool = false
var leave_room_timer: float = -1.0
var team_hud_label: RichTextLabel = null
var dead_banner_label: Label = null
var team_hud_timer: float = 0.0
const LEAVE_CONFIRM_MS: int = 3000
var leave_confirm_ms: int = -100000
var leave_confirm_label: Label = null

# --- MATCHMAKING (per-mode public lobby -> private room per match) ---
# Everyone searching for a mode meets in that mode's lobby room. Groups of 2/4/6
# form there with a leader handshake (invite -> accept -> confirm), then each
# group moves into its own private room so extra players can never merge in.
const MM_HELLO_INTERVAL: float = 1.0
const MM_HANDSHAKE_TIMEOUT: float = 3.0
const MM_INVITE_TIMEOUT: float = 6.0
const MM_SKIP_DURATION_MS: int = 4000
const MM_PRIVATE_JOIN_TIMEOUT: float = 30.0
# If the player who should be leading stays silent this long, skip them.
const MM_LEADER_PATIENCE: float = 5.0
const MM_LEADER_SKIP_MS: int = 10000
# After sending the final "confirm", stay in the lobby briefly so the message is
# actually delivered before leaving the room tears down the connection.
const MM_CONFIRM_LINGER: float = 1.5

var mm_phase: String = "idle" # "idle", "menu", "lobby", "match"

# --- LEADERBOARD ROOM (main menu only) ---
# Everyone on the main menu (or the leaderboard screen) sits in this room. It
# carries no gameplay at all - only nicknames and ELO, so leaderboards stay in
# sync between everyone who's online. Leaving the menu (queueing, practice)
# leaves the room.
const LEADERBOARD_ROOM_CODE: String = "hussle_leaderboard_room"
const LB_HEARTBEAT: float = 4.0
const LB_ONLINE_TIMEOUT_MS: int = 12000
var lb_online: Dictionary = {} # trystero id -> {"nick", "elo", "ms"} for players in the room
var lb_heartbeat_timer: float = 0.0
var lb_ui_dirty: bool = false
var lb_ui_timer: float = 0.0
var menu_online_label: Label = null
var leaderboard_list: VBoxContainer = null
var mm_self_id: String = ""
var mm_lobby_peers: Dictionary = {} # trystero id -> "searching" / "busy" / "unknown"
var mm_skip_until: Dictionary = {} # trystero id -> ticks_msec until we can invite them again
var mm_hello_timer: float = 0.0
var mm_leader_wait_timer: float = 0.0
# Leading a group
var mm_lead_room: String = ""
var mm_lead_roster: Array = []
var mm_lead_accepted: Array = []
var mm_lead_timer: float = 0.0
# Invited into someone else's group
var mm_invited_by: String = ""
var mm_invite_room: String = ""
var mm_invite_roster: Array = []
var mm_invite_timer: float = 0.0
# Leader: confirmed, waiting for the confirms to be delivered
var mm_linger_room: String = ""
var mm_linger_roster: Array = []
var mm_linger_timer: float = 0.0
# Private room
var mm_roster: Array = [] # sorted trystero ids of everyone in this match
var mm_room_joined: Dictionary = {} # trystero id -> true once they joined our room
var mm_room_left: Dictionary = {} # trystero id -> true if they left
var mm_private_join_timer: float = 0.0
# Players who were unresponsive when it was their turn to start a group (e.g. a
# frozen tab): someone else leads instead, but they can still be invited.
var mm_no_lead_until: Dictionary = {}
var last_setup_packet: Dictionary = {}

# --- NETWORK LAYER (relays, heartbeats, background ticking) ---
const NET_HEARTBEAT: float = 1.0
const LOBBY_PEER_TIMEOUT_MS: int = 4000
const ROOM_PEER_TIMEOUT_MS: int = 6000
var direct_peers: Dictionary = {} # trystero id -> true while directly connected in this room
var link_map: Dictionary = {} # trystero id -> Array of ids they're directly connected to
var last_heard: Dictionary = {} # trystero id -> _now_ms() of their last packet
var seen_mids: Dictionary = {} # message id -> _now_ms(), to drop relayed duplicates
var relay_cache: Dictionary = {} # sender id -> should we relay their packets
var msg_seq: int = 0
var net_last_tick_ms: int = -1
var net_heartbeat_timer: float = 0.0
var seen_prune_timer: float = 0.0
var js_tick_cb: JavaScriptObject

# --- GLOBAL COMBAT LOCKS ---
var is_qte_in_progress: bool = false

const FALL_BOUNDARY_Y: float = -30.0

# --- MAP POOL & BANNING SYSTEM ---
var map_pool: Array = [
	{
		"name": "Obsidian Void",
		"color": Color(0.12, 0.08, 0.18),
		"wall_color": Color(0.4, 0.1, 0.6),
		"theme": "Neon Void & Wall Portals",
		"mechanic": "portals"
	},
	{
		"name": "Solar Canyon",
		"color": Color(0.85, 0.5, 0.15),
		"wall_color": Color(0.3, 0.15, 0.05),
		"theme": "Desert Ramps & High Ground",
		"mechanic": "slopes",
		"crystals": true,
		"crystal_high_ground": true
	},
	{
		"name": "Cyber Frost",
		"color": Color(0.2, 0.7, 0.95),
		"wall_color": Color(0.05, 0.25, 0.5),
		"theme": "Glacial Tech & Jump Pads",
		"mechanic": "jump_pads"
	},
	{
		"name": "Toxic Core",
		"color": Color(0.25, 0.85, 0.35),
		"wall_color": Color(0.1, 0.25, 0.1),
		"theme": "Biohazard Acid Pools",
		"mechanic": "toxic_hazards"
	},
	{
		"name": "Glacial Rift",
		"color": Color(0.85, 0.95, 1.0),
		"wall_color": Color(0.35, 0.55, 0.75),
		"theme": "Low Friction Ice Arena",
		"mechanic": "ice_physics",
		"crystals": true,
		"crystal_high_ground": false
	},
	{
		"name": "Nebula Zenith",
		"color": Color(0.45, 0.1, 0.75),
		"wall_color": Color(0.85, 0.2, 0.8),
		"theme": "Cosmic Low Gravity",
		"mechanic": "low_gravity",
		"crystals": true,
		"crystal_high_ground": true
	},
	{
		"name": "Overclock Cyber",
		"color": Color(0.95, 0.75, 0.1),
		"wall_color": Color(0.15, 0.15, 0.2),
		"theme": "Gold Cyber & Recharge Pads",
		"mechanic": "recharge_pads"
	},
	{
		"name": "Prismatic Labyrinth",
		"color": Color(0.9, 0.95, 0.95),
		"wall_color": Color(0.5, 0.75, 0.9, 0.4),
		"theme": "Glass Maze & Corridors",
		"mechanic": "glass_barriers"
	},
	{
		"name": "Rust Inferno",
		"color": Color(0.75, 0.25, 0.1),
		"wall_color": Color(0.35, 0.1, 0.05),
		"theme": "Molten Canyon Ramps",
		"mechanic": "slopes"
	},
	{
		"name": "Emerald Trench",
		"color": Color(0.1, 0.8, 0.45),
		"wall_color": Color(0.05, 0.3, 0.2),
		"theme": "Toxic Green Jump Bouncers",
		"mechanic": "jump_pads"
	},
	{
		"name": "Eclipse Gate",
		"color": Color(0.08, 0.08, 0.12),
		"wall_color": Color(0.8, 0.1, 0.3),
		"theme": "Shadow Teleport Flanks",
		"mechanic": "portals"
	},
	{
		"name": "Hyper Red",
		"color": Color(0.9, 0.15, 0.25),
		"wall_color": Color(0.35, 0.05, 0.1),
		"theme": "Close Quarters Crimson Arena",
		"mechanic": "labyrinth"
	},
	{
		"name": "Skyline Bastion",
		"color": Color(0.36, 0.4, 0.45),
		"wall_color": Color(0.58, 0.47, 0.32),
		"theme": "Tall Ramparts & Ladders",
		"mechanic": "ladders",
		"crystals": true,
		"crystal_high_ground": true
	}
]

# The maps up for banning: one more than the number of players (3 in 1v1 and
# practice, 5 in 2v2, 7 in 3v3). Every player bans one; the last one is played.
var current_3_maps: Array = []
var banned_map_indices: Array = []
# Bans received over the network, by turn number. In team modes the two bans come
# from different players, so they can arrive out of order (or before the match
# setup); they're applied strictly in turn order.
var ban_log: Dictionary = {} # turn -> {"idx": map index, "by": peer_id}
var local_ban_turn: bool = true
var selected_map_data: Dictionary = {}

var map_ban_canvas: CanvasLayer = null
var map_ban_header_label: Label = null
var map_row_container: HFlowContainer = null
var ban_order_label: RichTextLabel = null

# Each ban turn has a time limit; if it runs out, a random map is banned for you.
const MAP_BAN_TURN_TIME: float = 20.0
var map_ban_timer: float = 0.0
var map_ban_timer_label: Label = null

# --- PRACTICE DUMMY DIFFICULTY ---
# Picked after the map bans in practice mode. (There is no level 5 yet.)
const DUMMY_LEVELS: Array = [
	{"name": "Level 1 - Wanderer", "desc": "Just walks around and runs away from you."},
	{"name": "Level 2 - Hopper", "desc": "Jumps around and moves a bit faster."},
	{"name": "Level 3 - Fighter", "desc": "Hunts you with smarter pathfinding and attacks - misses 50% of the time."},
	{"name": "Level 4 - Hunter", "desc": "Misses only 30% of the time and moves at sprint speed."},
]
var dummy_level: int = 1
var dummy_level_canvas: CanvasLayer = null
var sp_fell_off: bool = false

# --- PRACTICE DUMMY PATHFINDING ---
# The arena interior is covered by a 1m grid (49x49 cells, x/z from -24 to 24).
const NAV_HALF_EXTENT: int = 24
var nav_grid: AStarGrid2D = null
var nav_floor_rid: RID

# --- POWER CRYSTALS ---
# Only on maps flagged "crystals". The host decides where/what spawns and who
# picked it up; the other client mirrors that through packets.
const CRYSTAL_FIRST_SPAWN: float = 10.0
const CRYSTAL_RESPAWN_TIME: float = 40.0
const ABILITY_DURATION: float = 20.0
const SPEED_BOOST_MULT: float = 1.6
const LUNGE_COOLDOWN: float = 1.0
const CRYSTAL_ABILITIES: Dictionary = {
	"double_jump": {"name": "Double Jump", "color": Color(0.3, 0.8, 1.0)},
	"double_damage": {"name": "Double Damage", "color": Color(1.0, 0.25, 0.3)},
	"speed_boost": {"name": "Speed Boost", "color": Color(0.35, 1.0, 0.45)},
	"lunge": {"name": "Lunge (press Q)", "color": Color(1.0, 0.75, 0.15)},
}
var crystal_node: Node3D = null
var crystal_spawn_timer: float = 0.0
var crystal_id_counter: int = 0
var ability_label: Label = null

const CRYSTAL_POINTER_COLOR: Color = Color(0.72, 0.3, 1.0)
const CRYSTAL_SPAWN_HALF_EXTENT: float = 22.0 # stay well inside the 25m outer walls
var crystals_enabled: bool = false
var crystal_high_ground: bool = false
var crystal_active: Dictionary = {} # {id, type, pos} of the crystal on the map, if any
var crystal_claim_sent: bool = false

# The local player's current crystal ability ("" = none). One at a time.
var local_ability: String = ""
var local_ability_timer: float = 0.0

var crystal_pointer: Control = null
var crystal_distance_label: Label = null
var crosshair: Control = null

# --- OPPONENT-ABOVE POINTER ---
const OPPONENT_HIGH_THRESHOLD: float = 4.0
const POINTER_RADIUS: float = 90.0
var opponent_pointer: Control = null
var opponent_height_label: Label = null

# --- LOCAL SAVE & LEADERBOARD / ELO DATA ---
const SAVE_PATH: String = "user://player_data.json"
const LEADERBOARD_CACHE_PATH: String = "user://leaderboard_cache.json"

var local_nickname: String = "Player"
var local_elo: int = 0
var pre_match_elo: int = 0
const MAX_ELO: int = 2100

var player_nicknames: Dictionary = {}
var player_elos: Dictionary = {}
var leaderboard_data: Dictionary = {}

# --- COMBAT & COOLDOWN SYNC ---
var combat_cooldown_active: bool = false
var combat_cooldown_timer: float = 0.0
const COMBAT_COOLDOWN_DURATION: float = 3.0

# --- 3D & UI NODES ---
var world_root: Node3D = null
var menu_canvas: CanvasLayer = null
var leaderboard_canvas: CanvasLayer = null
var hud_canvas: CanvasLayer = null
var results_canvas: CanvasLayer = null
var console_list: VBoxContainer = null
var players_container: Node3D = null

var nickname_input: LineEdit = null
var pending_error_message: String = ""

var cooldown_bar_container: VBoxContainer = null
var cooldown_progress_bar: ProgressBar = null
var local_hp_label: Label = null
var waiting_opponent_label: Label = null

# Animated ELO State Variables
var is_animating_elo: bool = false
var anim_start_elo: float = 0.0
var anim_target_elo: float = 0.0
var anim_current_elo: float = 0.0
var anim_timer: float = 0.0
const ANIM_DURATION: float = 2.0

var anim_elo_label: Label = null
var anim_fill_rect: ColorRect = null
var anim_marker_rect: ColorRect = null
var anim_rank_icon: TextureRect = null

# --- ASSET PATHS ---
const TITLE_CARD_PATH: String = "res://CARD.png"
const SPRITE_SHEET_PATH_PNG: String = "res://rank_icons.png"
const SPRITE_SHEET_PATH_JPG: String = "res://rank_icons.jpg"
var loaded_sheet_texture: Texture2D = null

# --- JAVASCRIPT CALLBACK REFERENCES ---
var js_on_peer_join_cb: JavaScriptObject
var js_on_peer_leave_cb: JavaScriptObject
var js_on_data_receive_cb: JavaScriptObject

func _ready() -> void :
	_load_player_data()
	_load_leaderboard_cache()
	_init_sprite_sheet()
	_init_trystero_bridge()
	_build_main_menu()

func _process(delta: float) -> void :
	_net_tick()

	team_hud_timer -= delta
	if team_hud_timer <= 0.0:
		team_hud_timer = 0.2
		_update_team_hud()
		if leave_confirm_label and leave_confirm_label.visible and _now_ms() - leave_confirm_ms > LEAVE_CONFIRM_MS:
			leave_confirm_label.visible = false

	if is_match_active and not is_game_over:
		_tick_local_ability(delta)

	_update_opponent_pointer()

	if combat_cooldown_active:
		combat_cooldown_timer -= delta
		if cooldown_bar_container:
			cooldown_bar_container.visible = true
		if cooldown_progress_bar:
			cooldown_progress_bar.value = combat_cooldown_timer

		if combat_cooldown_timer <= 0.0:
			combat_cooldown_active = false
			combat_cooldown_timer = 0.0
			if cooldown_bar_container:
				cooldown_bar_container.visible = false

	if is_animating_elo:
		anim_timer += delta
		var t = clamp(anim_timer / ANIM_DURATION, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		anim_current_elo = lerp(anim_start_elo, anim_target_elo, t)
		_update_elo_animation_ui()
		if t >= 1.0:
			is_animating_elo = false

func start_combat_cooldown() -> void :
	combat_cooldown_active = true
	combat_cooldown_timer = COMBAT_COOLDOWN_DURATION
	if cooldown_progress_bar:
		cooldown_progress_bar.max_value = COMBAT_COOLDOWN_DURATION
		cooldown_progress_bar.value = COMBAT_COOLDOWN_DURATION
	if cooldown_bar_container:
		cooldown_bar_container.visible = true

func reset_combat_cooldown() -> void :
	combat_cooldown_active = false
	combat_cooldown_timer = 0.0
	if cooldown_bar_container:
		cooldown_bar_container.visible = false

func _unhandled_input(_event: InputEvent) -> void :
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if is_match_active and not is_game_over:
			# In 2v2/3v3 leaving hurts your team and is easy to do by accident
			# (browsers use Esc to release the mouse), so it takes two presses.
			if (team_size > 1 or is_ffa) and not is_single_player and _now_ms() - leave_confirm_ms > LEAVE_CONFIRM_MS:
				leave_confirm_ms = _now_ms()
				if leave_confirm_label:
					leave_confirm_label.visible = true
				log_console("[Match] Press Esc again within 3s to leave the match (counts as a loss).")
				return
			_forfeit_match()
		else:
			_return_to_main_menu()


func _init_trystero_bridge() -> void :
	if not OS.has_feature("web"):
		return

	js_on_peer_join_cb = JavaScriptBridge.create_callback(_on_trystero_peer_joined)
	js_on_peer_leave_cb = JavaScriptBridge.create_callback(_on_trystero_peer_left)
	js_on_data_receive_cb = JavaScriptBridge.create_callback(_on_trystero_data_received)

	# Background tabs stop the game loop, but JS timers keep firing (about once
	# a second), so matchmaking and the ban timer keep working while tabbed out.
	js_tick_cb = JavaScriptBridge.create_callback(_on_js_tick)

	var window = JavaScriptBridge.get_interface("window")
	window._godot_tick = js_tick_cb
	window._godot_on_peer_joined = js_on_peer_join_cb
	window._godot_on_peer_left = js_on_peer_leave_cb
	window._godot_on_data_received = js_on_data_receive_cb

	JavaScriptBridge.eval("""
		window.trysteroRoom = null;
		window.trysteroSendAction = null;
		window.trysteroGetAction = null;

		window.leaveTrysteroRoom = function() {
			if (window.trysteroRoom) {
				window.trysteroRoom.leave();
			}
			window.trysteroRoom = null;
			window.trysteroSendAction = null;
		};

		window.joinTrysteroRoomWhenReady = function(roomCode, attempts = 0) {
			if (typeof window.joinTrysteroRoom !== 'function') {
				if (attempts < 40) {
					setTimeout(() => window.joinTrysteroRoomWhenReady(roomCode, attempts + 1), 250);
				} else {
					console.error(\"[Trystero] HTML bridge never loaded - check the esm.sh import.\");
				}
				return;
			}

			if (window.trysteroRoom) {
				window.leaveTrysteroRoom();
			}

			window.joinTrysteroRoom(roomCode);
		};

		if (!window._godotTickTimer) {
			window._godotTickTimer = setInterval(function() {
				if (window._godot_tick) { window._godot_tick(); }
			}, 500);
		}
	""", true)

func _leave_trystero_room() -> void :
	if not OS.has_feature("web"):
		return
	var window = JavaScriptBridge.get_interface("window")
	window.leaveTrysteroRoom()

func _get_self_trystero_id() -> String:
	if mm_self_id != "":
		return mm_self_id
	if not OS.has_feature("web"):
		return ""
	var window = JavaScriptBridge.get_interface("window")
	var sid = window.trysteroSelfId
	if typeof(sid) == TYPE_STRING:
		mm_self_id = sid
	return mm_self_id

func _on_trystero_peer_joined(args: Array) -> void :
	var peer_id_str: String = String(args[0])

	if _get_self_trystero_id() == "":
		log_console("[Trystero] selfId missing - check the HTML import.")
		return

	direct_peers[peer_id_str] = true
	last_heard[peer_id_str] = _now_ms()
	relay_cache.clear()

	if mm_phase == "menu":
		_lb_on_peer_joined(peer_id_str)
		return

	if mm_phase == "lobby":
		if not mm_lobby_peers.has(peer_id_str):
			mm_lobby_peers[peer_id_str] = "unknown"
		_mm_send_hello(peer_id_str)
		_update_waiting_label()
		return

	if mm_phase != "match":
		return

	# Private room: only the players we grouped with in the lobby are allowed in.
	if not mm_roster.has(peer_id_str):
		log_console("[Matchmaking] Ignoring unexpected peer in private room: " + peer_id_str)
		return

	_mark_room_member_present(peer_id_str)
	# Share our links right away so relaying can start, and announce ourselves.
	net_heartbeat_timer = 0.0
	if not match_setup_done:
		_send_register()

func _send_register() -> void :
	send_p2p_packet({
		"action": "register", 
		"peer_id": local_peer_id, 
		"nickname": local_nickname, 
		"elo": local_elo, 
		"leaderboard": leaderboard_data
	})

func _peer_id_of(trystero_id: String) -> int:
	return mm_roster.find(trystero_id) + 1

func _sort_by_elo_desc(a, b) -> bool:
	var ea = int(player_elos.get(a, 0))
	var eb = int(player_elos.get(b, 0))
	if ea != eb:
		return ea > eb
	return a < b

# Host only: once every player in the room has registered, split them into
# ELO-balanced teams, pick the 3 maps for the ban phase and tell everyone.
func _host_try_setup() -> void :
	if not is_host_peer or match_setup_done or mm_phase != "match":
		return
	var n = mm_roster.size()
	for pid in range(1, n + 1):
		if not player_nicknames.has(pid):
			return

	# Snake draft by ELO: 1v1 A B, 2v2 A B B A, 3v3 A B B A A B.
	var order: Array = range(1, n + 1)
	order.sort_custom(_sort_by_elo_desc)
	var pattern = [0, 1, 1, 0, 0, 1]
	var teams: Dictionary = {}
	for i in range(n):
		teams[order[i]] = pattern[i]
	if is_ffa:
		for pid in range(1, n + 1):
			teams[pid] = pid - 1

	var indices: Array = range(map_pool.size())
	indices.shuffle()
	var picked: Array = indices.slice(0, n + 1)

	var setup = {
		"action": "match_setup", 
		"teams": teams, 
		"map_indices": picked, 
		"nicknames": player_nicknames.duplicate(), 
		"elos": player_elos.duplicate()
	}
	last_setup_packet = setup.duplicate(true)
	send_p2p_packet(setup.duplicate(true))
	_apply_match_setup(setup)

func _apply_match_setup(data: Dictionary) -> void :
	if match_setup_done:
		return
	match_setup_done = true

	player_teams.clear()
	var t = data.get("teams", {})
	for k in t:
		player_teams[int(k)] = int(t[k])
	var nicks = data.get("nicknames", {})
	for k in nicks:
		player_nicknames[int(k)] = String(nicks[k])
	var elos = data.get("elos", {})
	for k in elos:
		player_elos[int(k)] = int(elos[k])
	player_nicknames[local_peer_id] = local_nickname
	player_elos[local_peer_id] = local_elo

	current_3_maps.clear()
	for i in data.get("map_indices", []):
		current_3_maps.append(map_pool[int(i)])

	if waiting_opponent_label:
		waiting_opponent_label.visible = false

	var my_team = get_team(local_peer_id)
	if team_size > 1:
		var mates: Array = []
		for pid in all_player_ids():
			if pid != local_peer_id and get_team(pid) == my_team:
				mates.append(String(player_nicknames.get(pid, "Player")))
		log_console("[Match] You're on " + TEAM_NAMES[my_team] + " team with " + ", ".join(PackedStringArray(mates)) + ".")
	elif is_ffa:
		log_console("[Match] Free For All with " + str(all_player_ids().size()) + " players - last one standing wins!")
	else:
		log_console("[Match] Opponent: " + String(player_nicknames.get(_first_enemy_id(), "Opponent")))

	_start_map_ban_phase()

func _on_trystero_peer_left(args: Array) -> void :
	var peer_id_str: String = String(args[0])
	direct_peers.erase(peer_id_str)
	relay_cache.clear()

	if mm_phase == "menu":
		# Most likely they left the menu (queued / started practice). If they're
		# still around through a relay, their next heartbeat brings them back.
		lb_online.erase(peer_id_str)
		_lb_update_online_label()
		return

	# Losing the direct link doesn't mean they left: they may still reach us
	# through another player. They count as gone once nobody has heard from
	# them for a while (_mm_expire_lobby_peers / _room_tick). In a 1v1 there's
	# nobody to relay, so it's immediate.
	if mm_phase == "lobby":
		# Most likely they left the lobby (e.g. into a match). Stop counting them
		# as searching; if they're still here, their next relayed hello says so.
		if mm_lobby_peers.has(peer_id_str):
			mm_lobby_peers[peer_id_str] = "unknown"
		_update_waiting_label()
	elif mm_phase == "match" and mm_roster.size() <= 2 and mm_roster.has(peer_id_str):
		_on_room_member_gone(peer_id_str)

func _on_room_member_gone(peer_id_str: String) -> void :
	if mm_room_left.has(peer_id_str):
		return
	mm_room_left[peer_id_str] = true
	relay_cache.clear()
	if is_game_over or is_single_player:
		return

	var pid = _peer_id_of(peer_id_str)
	var nick = String(player_nicknames.get(pid, "A player"))
	if not match_setup_done:
		log_console("[Matchmaking] " + nick + " dropped before the match started. Back to the queue...")
		_mm_skip(peer_id_str)
		_mm_enter_lobby()
		return
	if not is_match_active:
		_return_to_main_menu(nick + " disconnected during map selection. No ELO was changed.")
		return

	log_console("[Trystero] " + nick + " disconnected.")
	_mark_player_forfeited(pid)

func _mm_expire_lobby_peers(now: int) -> void :
	for tid in mm_lobby_peers.keys():
		if direct_peers.has(tid) or now - int(last_heard.get(tid, 0)) <= LOBBY_PEER_TIMEOUT_MS:
			continue
		mm_lobby_peers.erase(tid)
		link_map.erase(tid)
		relay_cache.clear()
		if mm_lead_room != "" and mm_lead_roster.has(tid):
			_mm_abort_lead()
		elif mm_invited_by == tid:
			# Our leader left the lobby without us hearing its confirm - it's
			# most likely already in the private room, so meet it there. (If it
			# really quit, the private-room timeout brings us back.)
			_mm_enter_private_room(mm_invite_roster, mm_invite_room)
			return
		_update_waiting_label()

func _on_trystero_data_received(args: Array) -> void :
	var raw_json: String = String(args[0])
	var json = JSON.new()
	if json.parse(raw_json) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	_receive_packet(json.data, raw_json)

func _handle_incoming_p2p_packet(data: Dictionary) -> void :
	var action = String(data.get("action", ""))
	var sender = String(data.get("from", ""))

	if mm_phase == "menu":
		_lb_handle_packet(action, sender, data)
		return

	if mm_phase == "lobby":
		var to = String(data.get("to", ""))
		if to != "" and to != _get_self_trystero_id():
			return
		_mm_handle_lobby_packet(action, sender, data)
		return

	if mm_phase != "match":
		return

	# Only ever accept game packets from the players we grouped with.
	if sender == "" or not mm_roster.has(sender):
		return
	var sender_pid = _peer_id_of(sender)
	# Once our match is over, only the final ELO sync still matters.
	if is_game_over and action != "sync_state":
		return

	match action:
		"register":
			var nick = String(data.get("nickname", "Player"))
			var elo = int(data.get("elo", 0))
			player_nicknames[sender_pid] = nick
			player_elos[sender_pid] = elo

			_lb_merge(data.get("leaderboard", {}))
			_lb_set(nick, elo)
			_save_leaderboard_cache()

			if is_host_peer:
				if match_setup_done:
					# They missed the setup (it was sent before we could reach them).
					if not last_setup_packet.is_empty():
						send_p2p_packet(last_setup_packet.duplicate(true))
				else:
					send_p2p_packet({
						"action": "sync_state", 
						"nicknames": player_nicknames, 
						"elos": player_elos, 
						"leaderboard": leaderboard_data
					})
					_host_try_setup()
		"sync_state":
			var incoming_nicks = data.get("nicknames", {})
			for k in incoming_nicks:
				player_nicknames[int(k)] = String(incoming_nicks[k])
			var incoming_elos = data.get("elos", {})
			for k in incoming_elos:
				player_elos[int(k)] = int(incoming_elos[k])
			_lb_merge(data.get("leaderboard", {}))
			_save_leaderboard_cache()
		"match_setup":
			if sender_pid == 1:
				_apply_match_setup(data)
		"ban_map":
			var turn = int(data.get("turn", banned_map_indices.size()))
			if not ban_log.has(turn):
				ban_log[turn] = {"idx": int(data.get("banned_index", -1)), "by": sender_pid}
			_apply_pending_bans()
		"move":
			var p_node = get_player(int(data.get("peer_id", sender_pid)))
			if p_node and not p_node.is_local_player():
				p_node.global_position = Vector3(data["pos_x"], data["pos_y"], data["pos_z"])
				p_node.rotation_degrees.y = data["rot_y"]
		"set_movement_lock":
			var p_lock = get_player(int(data.get("peer_id", -1)))
			if p_lock and p_lock.is_local_player():
				if bool(data.get("locked", false)):
					p_lock.add_movement_lock(sender_pid)
				else:
					p_lock.remove_movement_lock(sender_pid)
		"qte_start":
			var attacker = get_player(int(data.get("attacker", sender_pid)))
			var target = get_player(int(data.get("target", -1)))
			if attacker:
				attacker.qte_active = true
				attacker.qte_target_peer = target.peer_id if target else -1
			if target and target.is_local_player() and attacker:
				if target.qte_active and target.qte_target_peer == attacker.peer_id:
					# Both players pressed E on each other at the same time: each
					# side sees the other's qte_start while its own QTE is running,
					# so both clients resolve this as a clash and fling apart.
					attacker.qte_active = false
					target.trigger_repulse_clash(attacker)
				elif not target.is_dead:
					target.add_movement_lock(attacker.peer_id)
		"qte_end":
			var attacker_end = get_player(int(data.get("attacker", sender_pid)))
			var target_end = get_player(int(data.get("target", -1)))
			if attacker_end:
				attacker_end.qte_active = false
				attacker_end.qte_target_peer = -1
			if target_end and target_end.is_local_player():
				target_end.remove_movement_lock(attacker_end.peer_id if attacker_end else sender_pid)
		"trigger_clash":
			var clash_a = get_player(int(data.get("a", sender_pid)))
			var clash_b = get_player(int(data.get("b", -1)))
			var me = get_local_player()
			if me and clash_b == me:
				me.trigger_repulse_clash(clash_a)
			else:
				if clash_a:
					clash_a.qte_active = false
				if clash_b:
					clash_b.qte_active = false
		"trigger_cooldown":
			if int(data.get("peer_id", local_peer_id)) == local_peer_id:
				start_combat_cooldown()
		"take_damage":
			var hurt = get_player(int(data.get("peer_id", -1)))
			if hurt:
				hurt.apply_damage(int(data.get("amount", 25)))
		"ffa_place":
			var placed = int(data.get("peer", -1))
			if placed > 0:
				ffa_places[placed] = int(data.get("place", all_player_ids().size()))
				if placed == local_peer_id:
					_show_ffa_dead_banner()
		"match_outcome":
			if data.has("ffa_places"):
				_process_ffa_outcome(data.get("ffa_places", {}))
			elif data.has("winning_team"):
				var dead_list: Array = []
				for d in data.get("dead", []):
					dead_list.append(int(d))
				_process_match_outcome(int(data.get("winning_team", 0)), dead_list if data.has("dead") else null)
		"player_forfeit":
			_mark_player_forfeited(sender_pid)
		"crystal_spawn":
			if not is_host_peer:
				_apply_crystal_spawn({
					"id": int(data.get("id", 0)), 
					"type": String(data.get("type", "speed_boost")), 
					"pos": Vector3(float(data.get("x", 0)), float(data.get("y", 1)), float(data.get("z", 0)))
				})
		"crystal_claim":
			if is_host_peer:
				_host_grant_crystal(int(data.get("id", -1)), sender_pid)
		"crystal_taken":
			if not is_host_peer:
				_apply_crystal_taken(int(data.get("id", -1)), int(data.get("by", 0)), String(data.get("type", "")))
		"ability_end":
			var p_end = get_player(sender_pid)
			if p_end:
				p_end.set_ability_tag("", Color.WHITE)

# --- NETWORK LAYER ---
# Real P2P meshes are messy: some pairs of players can't connect directly
# (home routers / NAT), connections form at different speeds, and background
# tabs pause the game loop. So:
#  - every packet has a unique id, and a player relays packets to anyone it's
#    connected to who has no direct link to the sender (ids stop duplicates)
#  - everyone shares who they're directly connected to, in a heartbeat
#  - matchmaking also runs off a JS timer, so it keeps going in background tabs
#  - a player only counts as gone once nobody has heard from them for a while

func _now_ms() -> int:
	return Time.get_ticks_msec()

func _on_js_tick(_args: Array) -> void :
	_net_tick()

func _net_reset() -> void :
	direct_peers.clear()
	link_map.clear()
	relay_cache.clear()
	seen_mids.clear()
	net_heartbeat_timer = 0.0

func _switch_room(code: String) -> void :
	_net_reset()
	_join_room(code)

# Runs from _process AND from a JS interval (background tabs), using real
# elapsed time, so it only does work every ~30ms however often it's called.
func _net_tick() -> void :
	var now = _now_ms()
	if net_last_tick_ms < 0:
		net_last_tick_ms = now
	var dt = float(now - net_last_tick_ms) / 1000.0
	if dt < 0.03:
		return
	net_last_tick_ms = now
	dt = min(dt, 5.0)

	if mm_phase == "menu":
		_lb_tick(dt, now)
	elif mm_phase == "lobby":
		_mm_expire_lobby_peers(now)
		if mm_phase == "lobby":
			_mm_tick(dt)
	elif mm_phase == "match" and not is_single_player:
		_room_tick(dt, now)

	# After a match ends, stay in the room briefly so the final ELO sync is
	# delivered, then leave.
	if leave_room_timer > 0.0:
		leave_room_timer -= dt
		if leave_room_timer <= 0.0:
			leave_room_timer = -1.0
			if mm_phase == "match":
				mm_phase = "idle"
				_leave_trystero_room()
				_net_reset()

	if map_ban_canvas and map_row_container:
		_tick_map_ban_timer(dt)

	seen_prune_timer -= dt
	if seen_prune_timer <= 0.0:
		seen_prune_timer = 2.0
		var cutoff = now - 15000
		for mid in seen_mids.keys():
			if int(seen_mids[mid]) < cutoff:
				seen_mids.erase(mid)

func send_p2p_packet(data: Dictionary) -> void :
	if is_single_player:
		return
	var me = _get_self_trystero_id()
	if me == "":
		return
	msg_seq += 1
	data["from"] = me
	data["mid"] = me + ":" + str(msg_seq)
	_transport_send(JSON.stringify(data))

func _transport_send(json_string: String) -> void :
	if not OS.has_feature("web"):
		return
	var window = JavaScriptBridge.get_interface("window")
	window.sendTrysteroPacket(json_string)

func _join_room(code: String) -> void :
	if OS.has_feature("web"):
		var window = JavaScriptBridge.get_interface("window")
		window.joinTrysteroRoomWhenReady(code)

func _are_linked(a: String, b: String) -> bool:
	if a == mm_self_id:
		return direct_peers.has(b)
	if b == mm_self_id:
		return direct_peers.has(a)
	return (link_map.get(a, []) as Array).has(b) or (link_map.get(b, []) as Array).has(a)

# Multi-hop relaying: everyone builds the same shortest-path tree from the
# sender over the shared connection map (ties go to the lowest ID), and a
# player re-broadcasts a packet only if it's the designated next hop for
# someone. Players with a direct link to the sender just get it directly;
# players further away get it through one or more relays.
func _should_relay(orig: String) -> bool:
	if relay_cache.has(orig):
		return relay_cache[orig]
	var nodes: Dictionary = {mm_self_id: true, orig: true}
	for d in direct_peers:
		nodes[d] = true
	for k in link_map:
		nodes[k] = true
		for v in link_map[k]:
			nodes[String(v)] = true
	var all_nodes: Array = nodes.keys()
	all_nodes.sort()
	var dist: Dictionary = {orig: 0}
	var frontier: Array = [orig]
	var result = false
	while not frontier.is_empty() and not result:
		frontier.sort()
		var next: Array = []
		for u in frontier:
			for v in all_nodes:
				if dist.has(v) or not _are_linked(u, v):
					continue
				dist[v] = int(dist[u]) + 1
				next.append(v)
				if u == mm_self_id:
					result = true # we're the first-found (lowest-ID) hop to v
		frontier = next
	relay_cache[orig] = result
	return result

func _receive_packet(data: Dictionary, raw: String) -> void :
	var orig = String(data.get("from", ""))
	if orig == "" or orig == _get_self_trystero_id():
		return
	var mid = String(data.get("mid", ""))
	if mid != "":
		if seen_mids.has(mid):
			return
		seen_mids[mid] = _now_ms()
	last_heard[orig] = _now_ms()

	if data.has("links"):
		var links: Array = []
		for l in data["links"]:
			links.append(String(l))
		if link_map.get(orig, []) != links:
			link_map[orig] = links
			relay_cache.clear()

	# Pass it on if we're the next hop towards anyone who can't hear the sender directly.
	if mid != "" and _should_relay(orig):
		_transport_send(raw)

	if mm_phase == "match" and mm_roster.has(orig):
		_mark_room_member_present(orig)

	if String(data.get("action", "")) == "net_links":
		if mm_phase == "match" and mm_roster.has(orig) and data.has("bans"):
			_merge_ban_heartbeat(data["bans"])
		return
	_handle_incoming_p2p_packet(data)

func _mark_room_member_present(tid: String) -> void :
	if mm_room_joined.has(tid) or mm_room_left.has(tid):
		return
	mm_room_joined[tid] = true
	mm_private_join_timer = max(mm_private_join_timer, 20.0)
	_update_waiting_label()

func _room_tick(dt: float, now: int) -> void :
	net_heartbeat_timer -= dt
	if net_heartbeat_timer <= 0.0:
		net_heartbeat_timer = NET_HEARTBEAT
		var hb = {"action": "net_links", "links": direct_peers.keys()}
		# Keep sharing the bans through the match too: whoever banned last has
		# already left the ban screen, so this is how a player who missed that
		# message catches up.
		if not ban_log.is_empty() and not is_game_over:
			var bans: Array = []
			for turn in ban_log:
				bans.append([turn, ban_log[turn]["idx"], ban_log[turn]["by"]])
			hb["bans"] = bans
		send_p2p_packet(hb)
		# Keep announcing ourselves until the host has set the match up.
		if not match_setup_done:
			_send_register()

	# Someone counts as gone once nobody has heard from them for a while (a
	# dropped direct link alone doesn't mean they left - we may be relaying).
	for tid in mm_roster.duplicate():
		if tid == mm_self_id or mm_room_left.has(tid) or not mm_room_joined.has(tid) or direct_peers.has(tid):
			continue
		if now - int(last_heard.get(tid, 0)) > ROOM_PEER_TIMEOUT_MS:
			_on_room_member_gone(tid)
			if mm_phase != "match":
				return

	if not match_setup_done and mm_phase == "match":
		mm_private_join_timer -= dt
		if mm_private_join_timer <= 0.0:
			var missing = 0
			for tid in mm_roster:
				if tid != mm_self_id and not mm_room_joined.has(tid):
					_mm_skip(tid)
					missing += 1
			log_console("[Matchmaking] " + str(missing) + " player(s) never connected, returning to queue...")
			_mm_enter_lobby()

func _merge_ban_heartbeat(bans) -> void :
	var added = false
	for e in bans:
		if typeof(e) != TYPE_ARRAY or e.size() < 3:
			continue
		var turn = int(e[0])
		if not ban_log.has(turn):
			ban_log[turn] = {"idx": int(e[1]), "by": int(e[2])}
			added = true
	if added:
		_apply_pending_bans()


# --- LOBBY MATCHMAKING ---
# Each mode has its own lobby room, and groups of 2/4/6 form like this:
#  - The lowest-ID free player who can see enough free players leads: it
#    invites the next-lowest ones (invite -> accept -> confirm).
#  - A player is only ever in one handshake at a time. If two leaders collide,
#    the lower ID wins and the other steps down.
#  - Any refusal or timeout releases everyone in that group and they retry.
#  - A confirmed group moves into its own private room, so N players in the
#    queue always form floor(N / group size) separate matches.

func _mm_group_size() -> int:
	return team_size * 2

func _mm_min_players() -> int:
	return int(GAME_MODES[game_mode].get("min", team_size * 2))

func _mm_max_players() -> int:
	return int(GAME_MODES[game_mode].get("max", team_size * 2))

func _mm_lobby_code() -> String:
	return "public_" + game_mode + "_lobby"

func _mm_enter_lobby() -> void :
	mm_phase = "lobby"
	mm_lobby_peers.clear()
	mm_roster = []
	mm_room_joined.clear()
	mm_room_left.clear()
	match_setup_done = false
	mm_hello_timer = 0.0
	mm_leader_wait_timer = 0.0
	ffa_wait_timer = -1.0
	_mm_clear_pending()
	_update_waiting_label()
	_switch_room(_mm_lobby_code())

func _update_waiting_label() -> void :
	if not waiting_opponent_label:
		return
	var mode_label = String(GAME_MODES.get(game_mode, {"label": "match"})["label"])
	if mm_phase == "lobby":
		if mm_linger_room != "":
			waiting_opponent_label.text = "Match found! Connecting..."
		else:
			var queued = 1
			for lp in mm_lobby_peers:
				if mm_lobby_peers[lp] != "unknown":
					queued += 1
			if is_ffa and ffa_wait_timer >= 0.0:
				var left = int(ceil(max(FFA_WAIT_SECONDS - ffa_wait_timer, 0.0)))
				waiting_opponent_label.text = "Free For All: " + str(_mm_searching_peers().size() + 1) + " players queued - starting in " + str(left) + "s (or as soon as " + str(_mm_max_players()) + " are in)"
			else:
				waiting_opponent_label.text = "Searching for " + mode_label + "... (" + str(queued) + " in queue, " + str(_mm_min_players()) + " needed)"
		waiting_opponent_label.visible = true
	elif mm_phase == "match" and not match_setup_done:
		waiting_opponent_label.text = "Match found! Connecting players (" + str(mm_room_joined.size() + 1) + "/" + str(mm_roster.size()) + ")..."
		waiting_opponent_label.visible = true

func _mm_is_free() -> bool:
	return mm_lead_room == "" and mm_invited_by == "" and mm_linger_room == ""

func _mm_status() -> String:
	return "searching" if _mm_is_free() else "busy"

func _mm_send_hello(to: String = "") -> void :
	var pkt = {"action": "mm_hello", "status": _mm_status(), "links": direct_peers.keys()}
	if to != "":
		pkt["to"] = to
	send_p2p_packet(pkt)

func _mm_clear_pending() -> void :
	mm_lead_room = ""
	mm_lead_roster = []
	mm_lead_accepted = []
	mm_lead_timer = 0.0
	mm_invited_by = ""
	mm_invite_room = ""
	mm_invite_roster = []
	mm_invite_timer = 0.0
	mm_linger_room = ""
	mm_linger_roster = []
	mm_linger_timer = 0.0

func _mm_skip(peer: String, ms: int = MM_SKIP_DURATION_MS) -> void :
	if peer != "":
		mm_skip_until[peer] = _now_ms() + ms

# Cancel the group we're leading: release everyone we invited.
func _mm_abort_lead(skip_peers: Array = []) -> void :
	for p in mm_lead_roster:
		if p != mm_self_id:
			send_p2p_packet({"action": "mm_release", "to": p, "room": mm_lead_room})
	for p in skip_peers:
		_mm_skip(p)
	_mm_clear_pending()

func _mm_searching_peers() -> Array:
	var now = _now_ms()
	var out: Array = []
	for peer in mm_lobby_peers:
		if mm_lobby_peers[peer] != "searching":
			continue
		if mm_skip_until.has(peer) and now < int(mm_skip_until[peer]):
			continue
		out.append(peer)
	out.sort()
	return out

func _mm_tick(delta: float) -> void :
	if _get_self_trystero_id() == "":
		return

	mm_hello_timer -= delta
	if mm_hello_timer <= 0.0:
		mm_hello_timer = MM_HELLO_INTERVAL
		_mm_send_hello()
		_update_waiting_label()

	# Leader: confirms were sent, give them time to arrive, then switch rooms.
	if mm_linger_room != "":
		mm_linger_timer -= delta
		if mm_linger_timer <= 0.0:
			_mm_enter_private_room(mm_linger_roster, mm_linger_room)
		return

	if mm_lead_room != "":
		mm_lead_timer -= delta
		if mm_lead_timer <= 0.0:
			# Someone never answered: release the group and skip the silent ones.
			var silent: Array = []
			for p in mm_lead_roster:
				if p != mm_self_id and not mm_lead_accepted.has(p):
					silent.append(p)
			_mm_abort_lead(silent)
		return

	if mm_invited_by != "":
		mm_invite_timer -= delta
		if mm_invite_timer <= 0.0:
			# We accepted and were never released, so the leader went ahead even
			# though its confirm got lost. Go meet the group there.
			_mm_enter_private_room(mm_invite_roster, mm_invite_room)
		return

	_mm_try_lead(delta)

func _mm_try_lead(delta: float) -> void :
	var min_n = _mm_min_players()
	var max_n = _mm_max_players()
	var pool = _mm_searching_peers()
	var count = pool.size() + 1
	if count < min_n:
		mm_leader_wait_timer = 0.0
		ffa_wait_timer = -1.0
		return
	if count < max_n:
		# Free For All: enough players to start, but wait up to 30s for more.
		if ffa_wait_timer < 0.0:
			ffa_wait_timer = 0.0
			log_console("[Matchmaking] " + str(count) + " players queued - starting in " + str(int(FFA_WAIT_SECONDS)) + "s unless more join.")
		ffa_wait_timer += delta
		if ffa_wait_timer < FFA_WAIT_SECONDS:
			mm_leader_wait_timer = 0.0
			return
	var n = min(count, max_n)

	# The lowest-ID searching player leads, unless they were unresponsive when
	# it was their turn (frozen tab etc.) - then the next one leads, and they
	# can still be invited.
	var now = _now_ms()
	var leaders: Array = [mm_self_id]
	for p in pool:
		if not (mm_no_lead_until.has(p) and now < int(mm_no_lead_until[p])):
			leaders.append(p)
	leaders.sort()
	if leaders[0] != mm_self_id:
		mm_leader_wait_timer += delta
		if mm_leader_wait_timer >= MM_LEADER_PATIENCE:
			mm_leader_wait_timer = 0.0
			mm_no_lead_until[leaders[0]] = now + MM_LEADER_SKIP_MS
		return

	mm_leader_wait_timer = 0.0
	var roster: Array = pool.slice(0, n - 1)
	roster.append(mm_self_id)
	roster.sort()
	mm_lead_roster = roster
	mm_lead_room = "hussle_" + game_mode + "_" + mm_self_id + "_" + str(randi() % 1000000)
	mm_lead_accepted = []
	mm_lead_timer = MM_HANDSHAKE_TIMEOUT
	log_console("[Matchmaking] Inviting " + str(n - 1) + " players into a group...")
	for p in mm_lead_roster:
		if p != mm_self_id:
			send_p2p_packet({"action": "mm_invite", "to": p, "room": mm_lead_room, "roster": mm_lead_roster})

func _mm_handle_lobby_packet(action: String, sender: String, data: Dictionary) -> void :
	if sender == "" or sender == mm_self_id:
		return
	var room = String(data.get("room", ""))

	match action:
		"mm_hello":
			mm_lobby_peers[sender] = String(data.get("status", "unknown"))
		"mm_invite":
			var roster: Array = []
			for r in data.get("roster", []):
				roster.append(String(r))
			var valid = room != "" and roster.size() >= _mm_min_players() and roster.size() <= _mm_max_players() and roster.has(mm_self_id) and roster.has(sender)
			if valid and mm_lead_room != "" and sender < mm_self_id:
				# Two leaders collided: the lower ID wins, so we step down.
				_mm_abort_lead()
			if valid and _mm_is_free():
				mm_invited_by = sender
				mm_invite_room = room
				mm_invite_roster = roster
				mm_invite_timer = MM_INVITE_TIMEOUT
				mm_leader_wait_timer = 0.0
				send_p2p_packet({"action": "mm_accept", "to": sender, "room": room})
			else:
				send_p2p_packet({"action": "mm_busy", "to": sender, "room": room})
		"mm_accept":
			if mm_lead_room != "" and room == mm_lead_room and mm_lead_roster.has(sender):
				if not mm_lead_accepted.has(sender):
					mm_lead_accepted.append(sender)
				if mm_lead_accepted.size() >= mm_lead_roster.size() - 1:
					for p in mm_lead_roster:
						if p != mm_self_id:
							send_p2p_packet({"action": "mm_confirm", "to": p, "room": mm_lead_room})
					# Don't leave yet - leaving immediately drops the confirms in flight.
					var r_room = mm_lead_room
					var r_roster = mm_lead_roster
					_mm_clear_pending()
					mm_linger_room = r_room
					mm_linger_roster = r_roster
					mm_linger_timer = MM_CONFIRM_LINGER
					log_console("[Matchmaking] Match found! Setting up the room...")
					_update_waiting_label()
			else:
				# They accepted a group we already gave up on: tell them they're free.
				send_p2p_packet({"action": "mm_release", "to": sender, "room": room})
		"mm_confirm":
			if sender == mm_invited_by and room == mm_invite_room:
				_mm_enter_private_room(mm_invite_roster, mm_invite_room)
		"mm_release":
			if sender == mm_invited_by and room == mm_invite_room:
				_mm_clear_pending()
		"mm_busy":
			if mm_lead_room != "" and room == mm_lead_room and mm_lead_roster.has(sender):
				_mm_abort_lead([sender])

func _mm_enter_private_room(roster: Array, room: String) -> void :
	var sorted_roster: Array = roster.duplicate()
	sorted_roster.sort()
	mm_phase = "match"
	mm_roster = sorted_roster
	local_peer_id = _peer_id_of(mm_self_id)
	is_host_peer = local_peer_id == 1
	mm_room_joined.clear()
	mm_room_left.clear()
	match_setup_done = false
	player_nicknames.clear()
	player_elos.clear()
	player_teams.clear()
	current_3_maps.clear()
	banned_map_indices.clear()
	ban_log.clear()
	player_nicknames[local_peer_id] = local_nickname
	player_elos[local_peer_id] = local_elo
	mm_private_join_timer = MM_PRIVATE_JOIN_TIMEOUT
	_mm_clear_pending()
	mm_lobby_peers.clear()
	last_setup_packet = {}
	log_console("[Matchmaking] Grouped! Moving to private room...")
	_update_waiting_label()
	_switch_room(room)


func generate_topdown_map_texture(map_info: Dictionary, is_banned: bool = false) -> Texture2D:
	var width = 160
	var height = 160
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)

	var f_color: Color = map_info["color"]
	var w_color: Color = map_info["wall_color"]

	if is_banned:
		var avg_f = (f_color.r + f_color.g + f_color.b) / 3.0 * 0.25
		f_color = Color(avg_f, avg_f, avg_f)
		var avg_w = (w_color.r + w_color.g + w_color.b) / 3.0 * 0.2
		w_color = Color(avg_w, avg_w, avg_w)

	img.fill(f_color)

	var wall_px = 8
	for x in range(width):
		for y in range(height):
			if x < wall_px or x >= width - wall_px or y < wall_px or y >= height - wall_px:
				img.set_pixel(x, y, w_color)

	_draw_img_rect(img, 30, 40, 16, 40, w_color)
	_draw_img_rect(img, 114, 80, 16, 40, w_color)
	_draw_img_rect(img, 65, 65, 30, 30, w_color)

	return ImageTexture.create_from_image(img)

func _draw_img_rect(img: Image, start_x: int, start_y: int, rect_w: int, rect_h: int, color: Color) -> void :
	for x in range(start_x, clamp(start_x + rect_w, 0, img.get_width())):
		for y in range(start_y, clamp(start_y + rect_h, 0, img.get_height())):
			img.set_pixel(x, y, color)

func _start_map_ban_phase() -> void :
	banned_map_indices.clear()
	local_ban_turn = _is_my_ban_turn()
	_reset_crystal_state()
	_build_map_ban_ui()
	_apply_pending_bans()

func _apply_pending_bans() -> void :
	if not map_ban_canvas or current_3_maps.is_empty():
		return # not in the ban phase yet - keep them for later
	var applied = false
	while true:
		var turn = banned_map_indices.size()
		if not ban_log.has(turn):
			break
		var entry = ban_log[turn]
		var order = _ban_order()
		var idx = int(entry["idx"])
		if turn >= order.size() or int(entry["by"]) != order[turn] or idx < 0 or idx >= current_3_maps.size() or banned_map_indices.has(idx):
			ban_log.erase(turn) # not a valid ban for this turn
			break
		banned_map_indices.append(idx)
		applied = true
	if applied:
		local_ban_turn = _is_my_ban_turn()
		_refresh_map_ban_ui()
		_check_map_ban_completion()

# Ban turns: every player bans one map, alternating teams - Blue 1, Red 1,
# Blue 2, Red 2, ... (by peer ID within each team). In 1v1 that's simply each
# player once; in practice mode you make both bans.
func _team_captain(team: int) -> int:
	var best = -1
	for pid in all_player_ids():
		if get_team(pid) == team and (best == -1 or pid < best):
			best = pid
	return best

func _ban_order() -> Array:
	if is_single_player:
		return [local_peer_id, local_peer_id]
	if is_ffa:
		return all_player_ids()
	var blue: Array = []
	var red: Array = []
	for pid in all_player_ids():
		if get_team(pid) == 0:
			blue.append(pid)
		else:
			red.append(pid)
	var order: Array = []
	for i in range(max(blue.size(), red.size())):
		if i < blue.size():
			order.append(blue[i])
		if i < red.size():
			order.append(red[i])
	return order

func _required_bans() -> int:
	return max(current_3_maps.size() - 1, 0)

func _ban_who(pid: int) -> String:
	if pid == local_peer_id:
		return "You"
	var nick = String(player_nicknames.get(pid, "Player " + str(pid)))
	if team_size > 1:
		return ("Teammate " if is_teammate(pid, local_peer_id) else "Enemy ") + nick
	return nick

func _current_banner() -> int:
	var order = _ban_order()
	var i = banned_map_indices.size()
	return order[i] if i < order.size() else -1

func _is_my_ban_turn() -> bool:
	return _current_banner() == local_peer_id

func _ban_header_text() -> String:
	if local_ban_turn:
		return "MAP BAN PHASE - SELECT MAP TO BAN"
	var banner = _current_banner()
	if banner <= 0:
		return "MAP BAN PHASE"
	if team_size > 1 or is_ffa:
		return _ban_who(banner).to_upper() + " IS BANNING..."
	return "OPPONENT IS BANNING A MAP..."

func _build_map_ban_ui() -> void :
	if map_ban_canvas: map_ban_canvas.queue_free()

	map_ban_canvas = CanvasLayer.new()
	map_ban_canvas.layer = 100
	add_child(map_ban_canvas)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_ban_canvas.add_child(center)

	var many = current_3_maps.size() > 3
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(700 if many else 620, 360)
	center.add_child(panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(main_vbox)

	map_ban_header_label = Label.new()
	map_ban_header_label.text = _ban_header_text()
	map_ban_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_ban_header_label.add_theme_font_size_override("font_size", 22)
	map_ban_header_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	main_vbox.add_child(map_ban_header_label)

	var sub_header = Label.new()
	if is_single_player:
		sub_header.text = "Single Player Mode: You get 2 Bans"
	elif is_ffa:
		sub_header.text = "Free For All: " + str(all_player_ids().size()) + " players, " + str(current_3_maps.size()) + " maps, every player bans 1"
	elif team_size > 1:
		sub_header.text = String(GAME_MODES[game_mode]["label"]) + ": " + str(current_3_maps.size()) + " maps, every player bans 1  -  You are " + TEAM_NAMES[get_team(local_peer_id)] + " team"
	else:
		sub_header.text = "Ranked 1v1: Each Player bans 1 map"
	sub_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_header.add_theme_font_size_override("font_size", 13)
	sub_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_vbox.add_child(sub_header)

	map_ban_timer_label = Label.new()
	map_ban_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_ban_timer_label.add_theme_font_size_override("font_size", 16)
	main_vbox.add_child(map_ban_timer_label)

	# Ban order, e.g. "You > Enemy Kai > Teammate Bea > Enemy Mo"
	ban_order_label = RichTextLabel.new()
	ban_order_label.bbcode_enabled = true
	ban_order_label.fit_content = true
	ban_order_label.scroll_active = false
	ban_order_label.custom_minimum_size = Vector2(660 if many else 580, 0)
	ban_order_label.add_theme_font_size_override("normal_font_size", 12)
	ban_order_label.visible = (team_size > 1 or is_ffa) and not is_single_player
	main_vbox.add_child(ban_order_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	main_vbox.add_child(spacer)

	# 3 maps on one row, 5 as 3 + 2, 7 as 4 + 3 (rows centered).
	# 4 maps: one row; 5: 3 + 2; 6: 3 + 3; 7: 4 + 3
	var cols = {3: 3, 4: 4, 5: 3, 6: 3}.get(current_3_maps.size(), 4)
	var card_w = 150 if many else 180
	var grid_center = CenterContainer.new()
	main_vbox.add_child(grid_center)
	map_row_container = HFlowContainer.new()
	map_row_container.alignment = FlowContainer.ALIGNMENT_CENTER
	map_row_container.custom_minimum_size = Vector2(cols * (card_w + 8), 0)
	map_row_container.add_theme_constant_override("h_separation", 8)
	map_row_container.add_theme_constant_override("v_separation", 8)
	grid_center.add_child(map_row_container)

	var bottom_pad = Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 8)
	main_vbox.add_child(bottom_pad)

	_refresh_map_ban_ui()

func _refresh_map_ban_ui() -> void :
	if not map_ban_canvas or not map_row_container: return

	# Every refresh marks the start of a new ban turn, so restart the clock.
	map_ban_timer = MAP_BAN_TURN_TIME
	_update_map_ban_timer_label()

	if map_ban_header_label:
		map_ban_header_label.text = _ban_header_text()

	if ban_order_label and ban_order_label.visible:
		var parts: Array = []
		var order = _ban_order()
		var cur = banned_map_indices.size()
		for t in range(order.size()):
			var pid = order[t]
			var col = player_color(pid).lerp(Color.WHITE, 0.35).to_html(false)
			var txt = _ban_who(pid).replace("[", "(")
			if t < cur:
				parts.append("[color=#777777][s]" + txt + "[/s][/color]")
			elif t == cur:
				parts.append("[b][color=#ffe066]> " + txt + "[/color][/b]")
			else:
				parts.append("[color=#" + col + "]" + txt + "[/color]")
		ban_order_label.text = "[center]Ban order:  " + "  -  ".join(PackedStringArray(parts)) + "[/center]"

	# Who banned which map (for the "Banned by" line on the cards)
	var banned_by: Dictionary = {}
	for t in ban_log:
		if t < banned_map_indices.size():
			banned_by[int(ban_log[t]["idx"])] = int(ban_log[t]["by"])

	var many = current_3_maps.size() > 3
	var card_w = 150 if many else 180
	var prev_w = 134 if many else 160
	var prev_h = 92 if many else 130

	for child in map_row_container.get_children():
		child.queue_free()

	for i in range(current_3_maps.size()):
		var map_info = current_3_maps[i]
		var is_banned = banned_map_indices.has(i)

		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(card_w, 0)
		map_row_container.add_child(card)

		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		card.add_child(vbox)

		var preview_container = PanelContainer.new()
		preview_container.custom_minimum_size = Vector2(prev_w, prev_h)
		vbox.add_child(preview_container)

		var preview_rect = TextureRect.new()
		preview_rect.texture = generate_topdown_map_texture(map_info, is_banned)
		preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview_rect.stretch_mode = TextureRect.STRETCH_SCALE
		preview_rect.custom_minimum_size = Vector2(prev_w, prev_h)
		preview_container.add_child(preview_rect)

		if is_banned:
			var banned_overlay = Label.new()
			banned_overlay.text = "BANNED"
			banned_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			banned_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			banned_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			banned_overlay.add_theme_font_size_override("font_size", 24)
			banned_overlay.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
			preview_container.add_child(banned_overlay)

		var map_name = Label.new()
		map_name.text = map_info["name"]
		map_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		map_name.add_theme_font_size_override("font_size", 14)
		vbox.add_child(map_name)

		var map_theme_lbl = Label.new()
		map_theme_lbl.text = map_info.get("theme", "")
		map_theme_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		map_theme_lbl.add_theme_font_size_override("font_size", 10)
		map_theme_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		map_theme_lbl.custom_minimum_size = Vector2(card_w - 12, 0)
		map_theme_lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		vbox.add_child(map_theme_lbl)

		if map_info.get("crystals", false):
			var crystal_lbl = Label.new()
			crystal_lbl.text = "+ Power Crystals"
			crystal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			crystal_lbl.add_theme_font_size_override("font_size", 10)
			crystal_lbl.add_theme_color_override("font_color", Color(0.95, 0.5, 1.0))
			vbox.add_child(crystal_lbl)

		if is_banned and banned_by.has(i) and not is_single_player:
			var by_lbl = Label.new()
			by_lbl.text = "by " + _ban_who(banned_by[i])
			by_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			by_lbl.add_theme_font_size_override("font_size", 10)
			by_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
			vbox.add_child(by_lbl)

		# Push the button to the bottom so buttons line up across a row.
		var push = Control.new()
		push.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(push)

		var ban_btn = Button.new()
		if is_banned:
			ban_btn.text = "BANNED"
			ban_btn.disabled = true
		else:
			ban_btn.text = "Ban Map"
			ban_btn.disabled = not local_ban_turn
			ban_btn.pressed.connect( func(): _on_map_ban_clicked(i))
		vbox.add_child(ban_btn)

func _tick_map_ban_timer(delta: float) -> void :
	map_ban_timer = max(0.0, map_ban_timer - delta)
	_update_map_ban_timer_label()

	# Only the player whose turn it is auto-bans, so both clients stay in sync:
	# the resulting ban goes out through the normal ban_map packet.
	if map_ban_timer <= 0.0 and local_ban_turn:
		_auto_ban_random_map()

func _update_map_ban_timer_label() -> void :
	if not map_ban_timer_label:
		return
	var secs = int(ceil(map_ban_timer))
	var who = "Your turn"
	if not local_ban_turn:
		var banner = _current_banner()
		if (team_size > 1 or is_ffa) and banner > 0:
			who = _ban_who(banner) + "'s turn"
		else:
			who = "Opponent's turn"
	map_ban_timer_label.text = who + " - " + str(secs) + "s left"
	if secs <= 5:
		map_ban_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		map_ban_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

func _auto_ban_random_map() -> void :
	var available: Array = []
	for i in range(current_3_maps.size()):
		if not banned_map_indices.has(i):
			available.append(i)
	if available.is_empty():
		return
	var pick: int = available[randi() % available.size()]
	log_console("[Map Ban] Time's up! Randomly banned " + String(current_3_maps[pick]["name"]) + ".")
	_on_map_ban_clicked(pick)

func _on_map_ban_clicked(map_idx: int) -> void :
	if not local_ban_turn or banned_map_indices.has(map_idx):
		return

	var turn = banned_map_indices.size()
	ban_log[turn] = {"idx": map_idx, "by": local_peer_id}
	banned_map_indices.append(map_idx)
	local_ban_turn = _is_my_ban_turn()
	_refresh_map_ban_ui()

	if not is_single_player:
		send_p2p_packet({
			"action": "ban_map", 
			"banned_index": map_idx, 
			"turn": turn
		})

	_check_map_ban_completion()

func _check_map_ban_completion() -> void :
	var required_bans = _required_bans()
	if required_bans > 0 and banned_map_indices.size() >= required_bans:
		for i in range(current_3_maps.size()):
			if not banned_map_indices.has(i):
				selected_map_data = current_3_maps[i]
				break

		if map_ban_canvas:
			map_ban_canvas.queue_free()
			map_ban_canvas = null
			map_row_container = null
			map_ban_header_label = null
			map_ban_timer_label = null
			ban_order_label = null

		if is_single_player:
			_show_dummy_level_picker()
		else:
			_start_p2p_game()

func _show_dummy_level_picker() -> void :
	if dummy_level_canvas:
		dummy_level_canvas.queue_free()
	dummy_level_canvas = CanvasLayer.new()
	dummy_level_canvas.layer = 100
	add_child(dummy_level_canvas)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dummy_level_canvas.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "CHOOSE DUMMY DIFFICULTY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	vbox.add_child(title)

	var map_lbl = Label.new()
	map_lbl.text = "Map: " + String(selected_map_data.get("name", "?"))
	map_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_lbl.add_theme_font_size_override("font_size", 13)
	map_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(map_lbl)

	for i in range(DUMMY_LEVELS.size()):
		var lvl = i + 1
		var btn = Button.new()
		btn.text = String(DUMMY_LEVELS[i]["name"]) + "\n" + String(DUMMY_LEVELS[i]["desc"])
		btn.custom_minimum_size = Vector2(480, 54)
		btn.pressed.connect( func(): _on_dummy_level_chosen(lvl))
		vbox.add_child(btn)

func _on_dummy_level_chosen(level: int) -> void :
	dummy_level = clampi(level, 1, DUMMY_LEVELS.size())
	if dummy_level_canvas:
		dummy_level_canvas.queue_free()
		dummy_level_canvas = null
	log_console("[Practice] " + String(DUMMY_LEVELS[dummy_level - 1]["name"]) + ": " + String(DUMMY_LEVELS[dummy_level - 1]["desc"]))
	_start_p2p_game()


func _reset_match_state() -> void :
	is_match_active = false
	is_game_over = false
	is_qte_in_progress = false
	current_3_maps.clear()
	banned_map_indices.clear()
	ban_log.clear()
	player_nicknames.clear()
	player_elos.clear()
	player_teams.clear()
	dead_peers.clear()
	forfeited_peers.clear()
	match_start_elos.clear()
	match_setup_done = false
	mm_roster = []
	mm_room_joined.clear()
	mm_room_left.clear()
	leave_room_timer = -1.0
	local_peer_id = 1
	ffa_places.clear()
	ffa_wait_timer = -1.0

func _on_find_match_pressed(mode: String = "1v1") -> void :
	_save_nickname_from_input()

	game_mode = mode if GAME_MODES.has(mode) else "1v1"
	team_size = int(GAME_MODES[game_mode]["team_size"])
	is_ffa = game_mode == "ffa"
	is_single_player = false
	is_host_peer = false
	_reset_match_state()
	mm_skip_until.clear()

	_clear_ui()
	_build_hud_console()

	log_console("[Matchmaking] Joining the " + String(GAME_MODES[game_mode]["label"]) + " lobby...")
	_mm_enter_lobby()

func _on_single_player_pressed() -> void :
	_save_nickname_from_input()

	_lb_leave_room()
	game_mode = "1v1"
	team_size = 1
	is_ffa = false
	_reset_match_state()
	sp_fell_off = false
	is_single_player = true
	is_host_peer = true
	is_match_active = true
	local_peer_id = 1
	player_teams = {1: 0, 2: 1}

	_clear_ui()
	_build_hud_console()

	if waiting_opponent_label:
		waiting_opponent_label.visible = false

	var shuffled = map_pool.duplicate()
	shuffled.shuffle()
	current_3_maps = [shuffled[0], shuffled[1], shuffled[2]]

	_start_map_ban_phase()

func _start_p2p_game() -> void :
	max_allowed_players = 2
	pre_match_elo = local_elo
	is_match_active = true
	is_game_over = false
	is_qte_in_progress = false

	dead_peers.clear()
	forfeited_peers.clear()
	player_nicknames[local_peer_id] = local_nickname
	player_elos[local_peer_id] = local_elo
	match_start_elos = player_elos.duplicate()

	_build_3d_environment()

	if is_single_player:
		_spawn_player(1)
		_spawn_test_dummy(2)
	else:
		for pid in all_player_ids():
			_spawn_player(pid)
		if team_size > 1:
			log_console("[Match] Eliminate the whole enemy team to win. If you die, you turn invisible and can roam until the match ends.")
		elif is_ffa:
			log_console("[Match] Everyone is your enemy - be the last one standing. If you die you turn invisible and can watch.")

	crystals_enabled = bool(selected_map_data.get("crystals", false))
	crystal_high_ground = bool(selected_map_data.get("crystal_high_ground", false))
	crystal_spawn_timer = CRYSTAL_FIRST_SPAWN
	if crystals_enabled:
		log_console("[Crystals] Power crystals are active on this map!")
		# The host may have told us about a crystal before our world existed.
		if not crystal_active.is_empty() and crystal_node == null:
			_spawn_crystal_node(crystal_active)


# --- TEAMS & ELIMINATION ---
# Everyone tracks deaths from the same damage packets, but only the host
# (lowest connected peer ID) declares the winner, so all clients agree even when
# the last two players trade hits at the same moment.

func all_player_ids() -> Array:
	var n = 2 if is_single_player else max(mm_roster.size(), 2)
	return range(1, n + 1)

func get_team(pid: int) -> int:
	return int(player_teams.get(pid, 0 if pid == 1 else 1))

func is_teammate(a: int, b: int) -> bool:
	return get_team(a) == get_team(b)

func player_color(pid: int) -> Color:
	if is_ffa:
		return FFA_COLORS[(pid - 1) % FFA_COLORS.size()]
	return TEAM_COLORS[get_team(pid) % TEAM_COLORS.size()]

func _ordinal(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 13:
		return str(n) + "th"
	match n % 10:
		1:
			return str(n) + "st"
		2:
			return str(n) + "nd"
		3:
			return str(n) + "rd"
	return str(n) + "th"

func get_player(pid: int) -> NetworkPlayer:
	if not players_container or not is_instance_valid(players_container):
		return null
	return players_container.get_node_or_null(str(pid)) as NetworkPlayer

func _first_enemy_id() -> int:
	for pid in all_player_ids():
		if not is_teammate(pid, local_peer_id):
			return pid
	return 2

func _team_alive_count(team: int) -> int:
	var c = 0
	for pid in all_player_ids():
		if get_team(pid) == team and not dead_peers.has(pid):
			c += 1
	return c

func _team_avg_elo(team: int) -> int:
	var total = 0
	var count = 0
	for pid in all_player_ids():
		if get_team(pid) == team:
			total += local_elo if pid == local_peer_id else int(match_start_elos.get(pid, player_elos.get(pid, 1000)))
			count += 1
	return int(round(float(total) / float(max(count, 1))))

func _spawn_point(pid: int) -> Vector3:
	if is_ffa:
		return FFA_SPAWNS[(pid - 1) % FFA_SPAWNS.size()]
	var team = get_team(pid)
	var mates: Array = []
	for p in all_player_ids():
		if get_team(p) == team:
			mates.append(p)
	var zs: Array = TEAM_SPAWN_Z.get(team_size, [0.0])
	var z = float(zs[mates.find(pid) % zs.size()])
	return Vector3(-15.0 if team == 0 else 15.0, 1.0, z)

# Called on every client when a player's health reaches 0.
func on_player_killed(p: NetworkPlayer) -> void :
	if dead_peers.has(p.peer_id) or is_game_over:
		return
	dead_peers[p.peer_id] = true

	if is_single_player:
		if p.is_dummy:
			_process_match_outcome(0)
		else:
			# Knocked out by the dummy (levels 3-4) or fell off the map.
			is_game_over = true
			var title = "You fell off the map" if sp_fell_off else "Defeated by the Level " + str(dummy_level) + " Dummy"
			_show_match_results_screen(title, false, 0, local_elo, local_elo, false)
		return

	if p.is_local_player():
		consume_local_ability("died")
		log_console("[Match] You were eliminated!")
	else:
		var side = ""
		if team_size > 1:
			side = " (teammate)" if is_teammate(p.peer_id, local_peer_id) else " (enemy)"
		log_console("[Match] " + String(player_nicknames.get(p.peer_id, "Player")) + side + " was eliminated!")

	p.set_dead_state()
	if is_ffa:
		_ffa_on_eliminated(p.peer_id)
		return
	if p.is_local_player() and team_size > 1 and _team_alive_count(p.team) > 0:
		_show_dead_banner(true)
	_host_check_team_wipe()

# A player quit or disconnected: they're out (and take a loss).
func _mark_player_forfeited(pid: int) -> void :
	if pid <= 0 or forfeited_peers.has(pid) or is_game_over:
		return
	forfeited_peers[pid] = true
	log_console("[Match] " + String(player_nicknames.get(pid, "A player")) + " left the match.")
	var newly_out = false
	if not dead_peers.has(pid):
		dead_peers[pid] = true
		newly_out = true
		var node = get_player(pid)
		if node:
			node.set_dead_state()
	var me = get_local_player()
	if me:
		me.remove_movement_lock(pid)
	_recompute_host()
	if is_ffa and newly_out:
		_ffa_on_eliminated(pid)
	_host_check_team_wipe()

# The host is the lowest peer ID still in the match; if it leaves, the next one
# takes over deciding the winner and running the crystals.
func _recompute_host() -> void :
	if is_single_player:
		return
	var lowest = local_peer_id
	for i in range(mm_roster.size()):
		var pid = i + 1
		if mm_roster[i] == mm_self_id or mm_room_left.has(mm_roster[i]) or forfeited_peers.has(pid):
			continue
		lowest = min(lowest, pid)
	var was_host = is_host_peer
	is_host_peer = lowest == local_peer_id
	crystal_claim_sent = false
	if is_host_peer and not was_host:
		log_console("[Network] You are now the match host.")

func _host_check_team_wipe() -> void :
	if not is_host_peer or is_game_over or not is_match_active or is_single_player:
		return
	if is_ffa:
		_host_check_ffa_end()
		return
	for team in [0, 1]:
		if _team_alive_count(team) == 0:
			var winner = 1 - team
			var dead_list: Array = dead_peers.keys()
			send_p2p_packet({"action": "match_outcome", "winning_team": winner, "dead": dead_list})
			_process_match_outcome(winner, dead_list)
			return

# --- FREE FOR ALL ---
# Placement = how many players were still in when you went out (5 players:
# first out is 5th, last one standing is 1st). Everyone guesses placements
# locally, but the host's call wins, so near-simultaneous eliminations end up
# the same on every screen.
# ELO compares you with every other player: beating someone counts as a win
# against them, finishing below them as a loss, scaled so a 5-player match
# moves about as much ELO as a 1v1.

func _alive_count() -> int:
	var c = 0
	for pid in all_player_ids():
		if not dead_peers.has(pid):
			c += 1
	return c

func _ffa_on_eliminated(pid: int) -> void :
	if not ffa_places.has(pid):
		ffa_places[pid] = _alive_count() + 1
	if pid == local_peer_id:
		_show_ffa_dead_banner()
	if is_host_peer and not is_game_over:
		send_p2p_packet({"action": "ffa_place", "peer": pid, "place": ffa_places[pid]})
	_host_check_team_wipe()

func _host_check_ffa_end() -> void :
	var alive: Array = []
	for pid in all_player_ids():
		if not dead_peers.has(pid):
			alive.append(pid)
	if alive.size() > 1:
		return
	if alive.size() == 1:
		ffa_places[alive[0]] = 1
	send_p2p_packet({"action": "match_outcome", "ffa_places": ffa_places})
	_process_ffa_outcome(ffa_places)

# ELO change for one player from the placements known so far. A player without
# a placement is still in the match, i.e. ahead of everyone who's out.
func _ffa_elo_change(pid: int) -> int:
	var ids = all_player_ids()
	if ids.size() < 2:
		return 0
	var my_rank = int(ffa_places.get(pid, 0))
	var my_elo = local_elo if pid == local_peer_id else int(match_start_elos.get(pid, player_elos.get(pid, 1000)))
	var total = 0.0
	for other in ids:
		if other == pid:
			continue
		var their_rank = int(ffa_places.get(other, 0))
		var score = 0.5
		if my_rank < their_rank:
			score = 1.0
		elif my_rank > their_rank:
			score = 0.0
		var their_elo = int(match_start_elos.get(other, player_elos.get(other, 1000)))
		var expected = 1.0 / (1.0 + pow(10.0, float(their_elo - my_elo) / 400.0))
		total += score - expected
	return int(round(32.0 / float(ids.size() - 1) * total))

func _show_ffa_dead_banner() -> void :
	if not dead_banner_label or is_game_over:
		return
	var n = all_player_ids().size()
	var place = int(ffa_places.get(local_peer_id, n))
	var change = _ffa_elo_change(local_peer_id)
	dead_banner_label.text = "YOU PLACED " + _ordinal(place).to_upper() + " OF " + str(n) + "  (" + ("+" if change >= 0 else "") + str(change) + " ELO)\nYou're invisible - roam freely and watch the rest of the match.\nPress Esc twice to leave whenever you like - your placement is kept."
	dead_banner_label.visible = true

func _process_ffa_outcome(places: Dictionary) -> void :
	if is_game_over:
		return
	is_game_over = true
	_show_dead_banner(false)
	for k in places:
		ffa_places[int(k)] = int(places[k])

	var n = all_player_ids().size()
	var start_elo = local_elo
	var my_change = 0
	var updated: Dictionary = {}
	for pid in all_player_ids():
		var change = _ffa_elo_change(pid)
		var before = local_elo if pid == local_peer_id else int(match_start_elos.get(pid, player_elos.get(pid, 1000)))
		updated[pid] = int(clamp(before + change, 0, MAX_ELO))
		var nick = local_nickname if pid == local_peer_id else String(player_nicknames.get(pid, "Player " + str(pid)))
		_lb_set(nick, int(updated[pid]))
		if pid == local_peer_id:
			my_change = change
	local_elo = int(updated[local_peer_id])
	_save_leaderboard_cache()
	save_player_data()
	send_p2p_packet({
		"action": "sync_state", 
		"nicknames": player_nicknames, 
		"elos": updated, 
		"leaderboard": leaderboard_data
	})
	_schedule_room_leave()

	var place = int(ffa_places.get(local_peer_id, n))
	var title = "You won the Free For All!" if place == 1 else "You placed " + _ordinal(place) + " of " + str(n)
	_show_match_results_screen(title, place == 1, my_change, start_elo, local_elo, local_elo >= MAX_ELO)

# Leaving: if you're still alive you're out now (and placed accordingly); if you
# were already out, you keep the placement you earned.
func _process_ffa_leave() -> void :
	if is_game_over:
		return
	is_game_over = true
	var n = all_player_ids().size()
	var change = _ffa_elo_change(local_peer_id)
	var start_elo = local_elo
	local_elo = int(clamp(local_elo + change, 0, MAX_ELO))
	_lb_set(local_nickname, local_elo)
	_save_leaderboard_cache()
	save_player_data()
	_schedule_room_leave()
	var place = int(ffa_places.get(local_peer_id, n))
	_show_match_results_screen("You left - placed " + _ordinal(place) + " of " + str(n), false, change, start_elo, local_elo, local_elo >= MAX_ELO)

func kill_local_player_from_fall() -> void :
	var me = get_local_player()
	if not me or me.is_dead:
		return
	sp_fell_off = is_single_player
	var amount = me.health
	send_p2p_packet({"action": "take_damage", "peer_id": str(local_peer_id), "amount": amount})
	me.apply_damage(amount)

func _show_dead_banner(show: bool) -> void :
	if dead_banner_label:
		dead_banner_label.visible = show

func _update_team_hud() -> void :
	if not team_hud_label:
		return
	if not is_match_active or is_game_over or is_single_player or (team_size <= 1 and not is_ffa) or players_container == null:
		team_hud_label.visible = false
		return
	if is_ffa:
		var ftext = "[b]FREE FOR ALL[/b] - " + str(_alive_count()) + " left\n"
		for pid in all_player_ids():
			var fcol = player_color(pid).lerp(Color.WHITE, 0.3).to_html(false)
			var fstatus = ""
			if dead_peers.has(pid):
				var placed = int(ffa_places.get(pid, 0))
				fstatus = "[color=#ff5555]OUT" + (" (" + _ordinal(placed) + ")" if placed > 0 else "") + "[/color]"
				if forfeited_peers.has(pid):
					fstatus = "[color=#888888]LEFT" + (" (" + _ordinal(placed) + ")" if placed > 0 else "") + "[/color]"
			else:
				var fnode = get_player(pid)
				fstatus = str(fnode.health if fnode else 100) + " HP"
			var fnick = String(player_nicknames.get(pid, "Player")).replace("[", "(")
			ftext += "  [color=#" + fcol + "]" + ("> " if pid == local_peer_id else "") + fnick + "[/color]  " + fstatus + "\n"
		team_hud_label.text = ftext
		team_hud_label.visible = true
		return
	var my_team = get_team(local_peer_id)
	var text = ""
	for team in [my_team, 1 - my_team]:
		var col = (TEAM_COLORS[team] as Color).lerp(Color.WHITE, 0.3).to_html(false)
		text += "[color=#" + col + "][b]" + TEAM_NAMES[team] + " TEAM" + (" (you)" if team == my_team else "") + "[/b][/color]\n"
		for pid in all_player_ids():
			if get_team(pid) != team:
				continue
			var status = ""
			if forfeited_peers.has(pid):
				status = "[color=#888888]LEFT[/color]"
			elif dead_peers.has(pid):
				status = "[color=#ff5555]DEAD[/color]"
			else:
				var node = get_player(pid)
				status = str(node.health if node else 100) + " HP"
			var nick = String(player_nicknames.get(pid, "Player")).replace("[", "(")
			text += "  " + ("> " if pid == local_peer_id else "") + nick + "  " + status + "\n"
	team_hud_label.text = text
	team_hud_label.visible = true


# --- POWER CRYSTALS ---
# Host-authoritative: the host picks when/where/what spawns and arbitrates who
# picked it up. One crystal on the map at a time; the next spawns
# CRYSTAL_RESPAWN_TIME seconds after the previous one is taken.

func _reset_crystal_state() -> void :
	crystals_enabled = false
	crystal_active = {}
	crystal_claim_sent = false
	crystal_id_counter = 0
	crystal_spawn_timer = CRYSTAL_FIRST_SPAWN
	if crystal_node and is_instance_valid(crystal_node):
		crystal_node.queue_free()
	crystal_node = null
	local_ability = ""
	local_ability_timer = 0.0

func _physics_process(delta: float) -> void :
	# Spawning needs raycasts, which are only valid during physics frames.
	if not crystals_enabled or not is_match_active or is_game_over or not world_root:
		return
	if not crystal_active.is_empty():
		return
	# The countdown runs on every client so a new host can pick up where the
	# old one left off; only the host actually spawns.
	crystal_spawn_timer -= delta
	if crystal_spawn_timer > 0.0 or not is_host_peer:
		return
	var pos = _find_crystal_spawn_point(world_root.get_world_3d().direct_space_state)
	if typeof(pos) != TYPE_VECTOR3:
		return # no valid spot this frame - try again next physics frame
	crystal_id_counter += 1
	var types = CRYSTAL_ABILITIES.keys()
	var data = {"id": crystal_id_counter, "type": String(types[randi() % types.size()]), "pos": pos}
	_apply_crystal_spawn(data)
	send_p2p_packet({
		"action": "crystal_spawn", "id": data["id"], "type": data["type"],
		"x": pos.x, "y": pos.y, "z": pos.z
	})

# Picks a random spot on a walkable surface inside the arena: drop a ray from
# the sky, require a flat solid surface, and make sure the crystal won't sit
# inside a wall or on top of a pad/pool/portal/ladder. Returns null if none of
# this frame's attempts worked.
func _find_crystal_spawn_point(space: PhysicsDirectSpaceState3D):
	var probe = BoxShape3D.new()
	probe.size = Vector3(1.0, 1.6, 1.0)
	var params = PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.exclude = [nav_floor_rid]

	for _attempt in range(12):
		var x = randf_range(-CRYSTAL_SPAWN_HALF_EXTENT, CRYSTAL_SPAWN_HALF_EXTENT)
		var z = randf_range(-CRYSTAL_SPAWN_HALF_EXTENT, CRYSTAL_SPAWN_HALF_EXTENT)
		var ray = PhysicsRayQueryParameters3D.create(Vector3(x, 30, z), Vector3(x, -1, z))
		ray.collide_with_areas = false
		var hit = space.intersect_ray(ray)
		if hit.is_empty() or not (hit["collider"] is StaticBody3D):
			continue
		if hit["normal"].y < 0.85:
			continue # too steep
		var ground: Vector3 = hit["position"]
		if ground.y < -0.5 or ground.y > 7.0:
			continue
		if ground.y > 0.5 and not crystal_high_ground:
			continue # this map keeps crystals on the arena floor
		params.transform = Transform3D(Basis(), ground + Vector3(0, 0.8, 0))
		var blocked = false
		for h in space.intersect_shape(params, 8):
			var c = h.get("collider")
			if c is CharacterBody3D or c is PowerCrystal:
				continue
			if c == hit["collider"] and ground.y > 0.5:
				continue # the wall top we're standing on
			blocked = true
			break
		if blocked:
			continue
		return ground + Vector3(0, 1.0, 0)
	return null

func _apply_crystal_spawn(data: Dictionary) -> void :
	crystal_active = data
	crystal_claim_sent = false
	if world_root:
		_spawn_crystal_node(data)

func _spawn_crystal_node(data: Dictionary) -> void :
	if crystal_node and is_instance_valid(crystal_node):
		crystal_node.queue_free()
	var info = CRYSTAL_ABILITIES.get(data["type"], {"name": "Crystal", "color": CRYSTAL_POINTER_COLOR})
	crystal_node = PowerCrystal.new(int(data["id"]), String(data["type"]), info["color"], info["name"], self)
	crystal_node.position = data["pos"]
	world_root.add_child(crystal_node)
	log_console("[Crystals] A " + String(info["name"]) + " crystal appeared! Follow the purple arrow.")

# Called by the crystal when the local player is touching it.
func on_crystal_touched(crystal: Node) -> void :
	if local_ability != "" or is_game_over:
		return # one ability at a time - leave it for later / the opponent
	var me = get_local_player()
	if not me or me.is_dead:
		return
	if crystal_active.is_empty() or int(crystal.crystal_id) != int(crystal_active["id"]):
		return
	if is_host_peer:
		_host_grant_crystal(int(crystal_active["id"]), local_peer_id)
	elif not crystal_claim_sent:
		crystal_claim_sent = true
		send_p2p_packet({"action": "crystal_claim", "id": int(crystal_active["id"])})

func _host_grant_crystal(id: int, by_peer: int) -> void :
	if crystal_active.is_empty() or int(crystal_active["id"]) != id:
		return # already taken
	if dead_peers.has(by_peer):
		return
	var ability_type = String(crystal_active["type"])
	send_p2p_packet({"action": "crystal_taken", "id": id, "by": by_peer, "type": ability_type})
	_apply_crystal_taken(id, by_peer, ability_type)

func _apply_crystal_taken(id: int, by_peer: int, ability_type: String) -> void :
	if not crystal_active.is_empty() and int(crystal_active["id"]) == id:
		crystal_active = {}
		if crystal_node and is_instance_valid(crystal_node):
			crystal_node.queue_free()
		crystal_node = null
	crystal_claim_sent = false
	crystal_spawn_timer = CRYSTAL_RESPAWN_TIME

	var info = CRYSTAL_ABILITIES.get(ability_type, {"name": ability_type, "color": Color.WHITE})
	if by_peer == local_peer_id:
		_give_local_ability(ability_type)
	else:
		var grabber = get_player(by_peer)
		if grabber:
			grabber.set_ability_tag(String(info["name"]), info["color"])
		var who = "Opponent"
		if team_size > 1:
			who = ("Teammate " if is_teammate(by_peer, local_peer_id) else "Enemy ") + String(player_nicknames.get(by_peer, "player"))
		elif is_ffa:
			who = String(player_nicknames.get(by_peer, "A player"))
		log_console("[Crystals] " + who + " grabbed " + String(info["name"]) + "!")

func _give_local_ability(ability_type: String) -> void :
	local_ability = ability_type
	local_ability_timer = ABILITY_DURATION
	var info = CRYSTAL_ABILITIES.get(ability_type, {"name": ability_type})
	log_console("[Crystals] You got " + String(info["name"]) + " for " + str(int(ABILITY_DURATION)) + "s!")
	_update_ability_hud()

# Ends the local ability, either because it was used or it timed out.
func consume_local_ability(reason: String = "used") -> void :
	if local_ability == "":
		return
	var info = CRYSTAL_ABILITIES.get(local_ability, {"name": local_ability})
	var ending = " wore off."
	if reason == "used":
		ending = " used up."
	elif reason == "died":
		ending = " lost."
	log_console("[Crystals] " + String(info["name"]) + ending)
	local_ability = ""
	local_ability_timer = 0.0
	send_p2p_packet({"action": "ability_end"})
	_update_ability_hud()

func _tick_local_ability(delta: float) -> void :
	if local_ability == "":
		return
	local_ability_timer -= delta
	if local_ability_timer <= 0.0:
		consume_local_ability("expired")
	else:
		_update_ability_hud()

func _update_ability_hud() -> void :
	if not ability_label:
		return
	if local_ability == "":
		ability_label.visible = false
		return
	var info = CRYSTAL_ABILITIES.get(local_ability, {"name": local_ability, "color": Color.WHITE})
	var hint = ""
	match local_ability:
		"double_jump": hint = "Press Space again in mid-air"
		"double_damage": hint = "Next QTE hits for 50 (smaller target)"
		"speed_boost": hint = "Move " + str(int(round((SPEED_BOOST_MULT - 1.0) * 100))) + "% faster"
		"lunge": hint = "Press Q to lunge forward"
	ability_label.text = "CRYSTAL: " + String(info["name"]) + "  (" + str(int(ceil(local_ability_timer))) + "s)\n" + hint
	ability_label.add_theme_color_override("font_color", info["color"])
	ability_label.visible = true


func get_rank_name(elo: int) -> String:
	if elo < 100: return "Humble Husser 1"
	elif elo < 200: return "Humble Husser 2"
	elif elo < 300: return "Humble Husser 3"
	elif elo < 400: return "Rookie Runner 1"
	elif elo < 500: return "Rookie Runner 2"
	elif elo < 600: return "Rookie Runner 3"
	elif elo < 700: return "Rising Hussler 1"
	elif elo < 800: return "Rising Hussler 2"
	elif elo < 900: return "Rising Hussler 3"
	elif elo < 1000: return "Valiant Voyager 1"
	elif elo < 1100: return "Valiant Voyager 2"
	elif elo < 1200: return "Valiant Voyager 3"
	elif elo < 1300: return "Royal Runner 1"
	elif elo < 1400: return "Royal Runner 2"
	elif elo < 1500: return "Royal Runner 3"
	elif elo < 1600: return "Holy Husser 1"
	elif elo < 1700: return "Holy Husser 2"
	elif elo < 1800: return "Holy Husser 3"
	elif elo < 1900: return "Heavenly Huss 1"
	elif elo < 2000: return "Heavenly Huss 2"
	else: return "Heavenly Huss 3"

func _init_sprite_sheet() -> void :
	if ResourceLoader.exists(SPRITE_SHEET_PATH_PNG):
		loaded_sheet_texture = load(SPRITE_SHEET_PATH_PNG) as Texture2D
	elif ResourceLoader.exists(SPRITE_SHEET_PATH_JPG):
		loaded_sheet_texture = load(SPRITE_SHEET_PATH_JPG) as Texture2D

func load_rank_texture(elo: int) -> Texture2D:
	var rank_idx = clamp(floori(elo / 100.0), 0, 20)

	if loaded_sheet_texture:
		var col_count: int = 7
		var col = floori(rank_idx / 3.0)
		var row = rank_idx % 3

		var sheet_w = float(loaded_sheet_texture.get_width())
		var sheet_h = float(loaded_sheet_texture.get_height())

		var raw_cell_w = sheet_w / float(col_count)

		var crop_h: float = sheet_h * 0.14
		var crop_y: float = 0.0

		if row == 0:
			crop_y = sheet_h * 0.145
		elif row == 1:
			crop_y = sheet_h * 0.44
		else:
			crop_y = sheet_h * 0.705

		var pad_side: float = raw_cell_w * 0.12
		var crop_x = (col * raw_cell_w) + pad_side
		var crop_w = raw_cell_w - (pad_side * 2.0)

		var atlas = AtlasTexture.new()
		atlas.atlas = loaded_sheet_texture
		atlas.region = Rect2(crop_x, crop_y, crop_w, crop_h)
		return atlas

	var fallback_path = "res://rank_icons/rank_" + str(rank_idx) + ".png"
	if ResourceLoader.exists(fallback_path):
		return load(fallback_path) as Texture2D

	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var hue = (rank_idx * 17 % 100) / 100.0
	img.fill(Color.from_hsv(hue, 0.85, 0.95))
	return ImageTexture.create_from_image(img)


func _save_nickname_from_input() -> void:
	if nickname_input and nickname_input.text.strip_edges() != "":
		var changed = local_nickname != nickname_input.text.strip_edges()
		local_nickname = nickname_input.text.strip_edges()
		save_player_data()
		if changed:
			_lb_announce()

func _load_player_data() -> void :
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				local_nickname = json.data.get("nickname", "Player")
				local_elo = int(json.data.get("elo", 0))
			file.close()

func save_player_data() -> void :
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"nickname": local_nickname, 
			"elo": local_elo
		}
		file.store_string(JSON.stringify(data))
		file.close()

func export_data_to_obfuscated_string() -> String:
	var raw_dict = {
		"nickname": local_nickname,
		"elo": local_elo
	}
	var json_str = JSON.stringify(raw_dict)
	return Marshalls.utf8_to_base64(json_str)

func import_data_from_obfuscated_string(encoded_string: String) -> bool:
	var clean_str = encoded_string.strip_edges()
	if clean_str.is_empty():
		return false

	var decoded_json_str = Marshalls.base64_to_utf8(clean_str)
	if decoded_json_str.is_empty():
		return false

	var json = JSON.new()
	if json.parse(decoded_json_str) == OK and json.data is Dictionary:
		var dict: Dictionary = json.data
		if dict.has("nickname") and dict.has("elo"):
			local_nickname = String(dict["nickname"])
			local_elo = int(dict["elo"])
			save_player_data()
			_lb_set(local_nickname, local_elo)
			_save_leaderboard_cache()
			return true
	return false

func _on_export_save_pressed() -> void:
	_save_nickname_from_input()
	var obfuscated = export_data_to_obfuscated_string()
	DisplayServer.clipboard_set(obfuscated)
	pending_error_message = "Save code copied to clipboard!"
	_build_main_menu()

func _on_import_save_pressed() -> void:
	_save_nickname_from_input()
	
	var dialog = AcceptDialog.new()
	dialog.title = "Import Save Data"
	dialog.ok_button_text = "Import"
	
	var vbox = VBoxContainer.new()
	
	var lbl = Label.new()
	lbl.text = "Paste your copied save data string below:"
	vbox.add_child(lbl)
	
	var input_field = LineEdit.new()
	input_field.placeholder_text = "Paste save code here..."
	input_field.custom_minimum_size = Vector2(320, 35)
	vbox.add_child(input_field)
	
	dialog.add_child(vbox)
	menu_canvas.add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		var input_text = input_field.text
		if input_text.strip_edges() == "":
			input_text = DisplayServer.clipboard_get()
			
		if import_data_from_obfuscated_string(input_text):
			pending_error_message = "Save data imported successfully!"
		else:
			pending_error_message = "Failed to import save data."
		dialog.queue_free()
		_build_main_menu()
	)
	
	dialog.canceled.connect(func():
		dialog.queue_free()
	)

func _load_leaderboard_cache() -> void :
	if FileAccess.file_exists(LEADERBOARD_CACHE_PATH):
		var file = FileAccess.open(LEADERBOARD_CACHE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var raw_data = json.data
				if raw_data is Dictionary:
					for k in raw_data:
						leaderboard_data[k] = raw_data[k]
			file.close()

func _save_leaderboard_cache() -> void :
	var file = FileAccess.open(LEADERBOARD_CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(leaderboard_data))
		file.close()

# Each entry is {"elo": int, "t": unix time it was last changed}. When two
# copies disagree, the newer one wins, so an old cache can't undo a new result.
func _wall_time() -> float:
	return Time.get_unix_time_from_system()

func _lb_set(nick: String, elo: int, t: float = -1.0) -> void :
	leaderboard_data[nick] = {"elo": elo, "t": _wall_time() if t < 0.0 else t}

# Merges another player's leaderboard into ours. Returns true if anything changed.
func _lb_merge(incoming) -> bool:
	if not (incoming is Dictionary):
		return false
	var changed = false
	for nick in incoming:
		var n = String(nick)
		if n == local_nickname:
			continue # we're the authority on our own ELO
		var e = incoming[nick]
		if not (e is Dictionary) or not e.has("elo"):
			continue
		var t_new = float(e.get("t", 0.0))
		var have = leaderboard_data.get(n, null)
		var t_have = float(have.get("t", -1.0)) if have is Dictionary else -2.0
		if t_new > t_have:
			leaderboard_data[n] = {"elo": int(e["elo"]), "t": t_new}
			changed = true
	return changed

func clear_leaderboard_data() -> void :
	leaderboard_data.clear()
	if FileAccess.file_exists(LEADERBOARD_CACHE_PATH):
		DirAccess.remove_absolute(LEADERBOARD_CACHE_PATH)


func log_console(message: String) -> void :
	print(message)
	if console_list:
		var lbl = Label.new()
		lbl.text = message
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
		console_list.add_child(lbl)
		if console_list.get_child_count() > 30:
			console_list.get_child(0).queue_free()

func _build_hud_console() -> void :
	hud_canvas = CanvasLayer.new()
	hud_canvas.layer = 1
	add_child(hud_canvas)

	var hp_panel = PanelContainer.new()
	hp_panel.custom_minimum_size = Vector2(180, 40)
	hp_panel.position = Vector2(10, 10)
	hud_canvas.add_child(hp_panel)

	local_hp_label = Label.new()
	local_hp_label.text = "YOUR HP: 100 / 100"
	local_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	local_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	local_hp_label.add_theme_font_size_override("font_size", 14)
	local_hp_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	hp_panel.add_child(local_hp_label)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 160)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(10, -170)
	hud_canvas.add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 150)
	panel.add_child(scroll)

	console_list = VBoxContainer.new()
	scroll.add_child(console_list)

	cooldown_bar_container = VBoxContainer.new()
	cooldown_bar_container.custom_minimum_size = Vector2(300, 45)
	cooldown_bar_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cooldown_bar_container.position = Vector2(-150, -60)
	cooldown_bar_container.visible = false
	hud_canvas.add_child(cooldown_bar_container)

	var cd_label = Label.new()
	cd_label.text = "ATTACK COOLDOWN"
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.add_theme_font_size_override("font_size", 12)
	cd_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	cooldown_bar_container.add_child(cd_label)

	cooldown_progress_bar = ProgressBar.new()
	cooldown_progress_bar.custom_minimum_size = Vector2(300, 20)
	cooldown_progress_bar.show_percentage = false
	cooldown_bar_container.add_child(cooldown_progress_bar)

	waiting_opponent_label = Label.new()
	waiting_opponent_label.text = "Searching for Opponent..."
	waiting_opponent_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	waiting_opponent_label.position = Vector2(-260, 10)
	waiting_opponent_label.custom_minimum_size = Vector2(520, 30)
	waiting_opponent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_opponent_label.add_theme_font_size_override("font_size", 16)
	waiting_opponent_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	waiting_opponent_label.visible = true
	hud_canvas.add_child(waiting_opponent_label)

	opponent_pointer = OpponentPointer.new()
	opponent_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opponent_pointer.visible = false
	hud_canvas.add_child(opponent_pointer)

	opponent_height_label = Label.new()
	opponent_height_label.custom_minimum_size = Vector2(220, 24)
	opponent_height_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opponent_height_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opponent_height_label.add_theme_font_size_override("font_size", 14)
	opponent_height_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
	opponent_height_label.add_theme_constant_override("outline_size", 4)
	opponent_height_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	opponent_height_label.visible = false
	hud_canvas.add_child(opponent_height_label)

	# Purple arrow + distance readout pointing at the power crystal.
	crystal_pointer = OpponentPointer.new()
	crystal_pointer.arrow_color = CRYSTAL_POINTER_COLOR
	crystal_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crystal_pointer.visible = false
	hud_canvas.add_child(crystal_pointer)

	crystal_distance_label = Label.new()
	crystal_distance_label.custom_minimum_size = Vector2(220, 24)
	crystal_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crystal_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crystal_distance_label.add_theme_font_size_override("font_size", 14)
	crystal_distance_label.add_theme_color_override("font_color", CRYSTAL_POINTER_COLOR)
	crystal_distance_label.add_theme_constant_override("outline_size", 4)
	crystal_distance_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	crystal_distance_label.visible = false
	hud_canvas.add_child(crystal_distance_label)

	# Active crystal ability (top-left, under HP)
	ability_label = Label.new()
	ability_label.position = Vector2(12, 56)
	ability_label.add_theme_font_size_override("font_size", 14)
	ability_label.add_theme_constant_override("outline_size", 4)
	ability_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	ability_label.visible = false
	hud_canvas.add_child(ability_label)

	# Team roster (top-right) for 2v2 / 3v3
	team_hud_label = RichTextLabel.new()
	team_hud_label.bbcode_enabled = true
	team_hud_label.fit_content = true
	team_hud_label.scroll_active = false
	team_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	team_hud_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	team_hud_label.position = Vector2(-250, 10)
	team_hud_label.custom_minimum_size = Vector2(240, 0)
	team_hud_label.add_theme_font_size_override("normal_font_size", 13)
	team_hud_label.add_theme_font_size_override("bold_font_size", 14)
	team_hud_label.add_theme_constant_override("outline_size", 4)
	team_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	team_hud_label.visible = false
	hud_canvas.add_child(team_hud_label)

	# Shown while you're dead but your team is still fighting
	dead_banner_label = Label.new()
	dead_banner_label.text = "YOU WERE ELIMINATED\nYou're invisible - roam freely while your team fights on.\nStay until the end: if your team wins you still get half the ELO."
	dead_banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	dead_banner_label.position = Vector2(-300, 48)
	dead_banner_label.custom_minimum_size = Vector2(600, 70)
	dead_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dead_banner_label.add_theme_font_size_override("font_size", 15)
	dead_banner_label.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	dead_banner_label.add_theme_constant_override("outline_size", 5)
	dead_banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	dead_banner_label.visible = false
	hud_canvas.add_child(dead_banner_label)

	leave_confirm_label = Label.new()
	leave_confirm_label.text = "Press Esc again to leave the match (counts as a loss)"
	leave_confirm_label.set_anchors_preset(Control.PRESET_CENTER)
	leave_confirm_label.position = Vector2(-260, 40)
	leave_confirm_label.custom_minimum_size = Vector2(520, 30)
	leave_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leave_confirm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leave_confirm_label.add_theme_font_size_override("font_size", 18)
	leave_confirm_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	leave_confirm_label.add_theme_constant_override("outline_size", 5)
	leave_confirm_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	leave_confirm_label.visible = false
	hud_canvas.add_child(leave_confirm_label)

	# Plus-shaped crosshair, always centered (anchored to the middle of the screen).
	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_canvas.add_child(crosshair)

	log_console("[System] Network Console initialized.")

func get_local_player() -> NetworkPlayer:
	return get_player(local_peer_id)

# The (first) enemy player - in 1v1 and practice that's simply the opponent.
func get_opponent_player() -> NetworkPlayer:
	return get_player(_first_enemy_id())

func _update_opponent_pointer() -> void :
	if not opponent_pointer or not opponent_height_label:
		return

	var show_pointer = false
	var show_crystal = false
	var me = get_local_player() if is_match_active and not is_game_over else null
	var center = get_viewport().get_visible_rect().size * 0.5

	if me and me.camera:
		var cam: Camera3D = me.camera
		# Point at the nearest living enemy that's high above us.
		var opp: NetworkPlayer = null
		var best_dist = INF
		for pid in all_player_ids():
			if is_teammate(pid, local_peer_id) or dead_peers.has(pid):
				continue
			var cand = get_player(pid)
			if cand and cand.global_position.y - me.global_position.y > OPPONENT_HIGH_THRESHOLD:
				var d = cand.global_position.distance_to(me.global_position)
				if d < best_dist:
					best_dist = d
					opp = cand
		if opp:
			var height = opp.global_position.y - me.global_position.y
			show_pointer = true
			_aim_pointer(opponent_pointer, cam, center, opp.global_position + Vector3(0, 0.9, 0))
			opponent_height_label.text = ("ENEMY ABOVE: " if team_size > 1 or is_ffa else "OPPONENT ABOVE: ") + str(int(round(height))) + "m"
			opponent_height_label.position = center + Vector2(-110, POINTER_RADIUS + 30)

		if crystal_pointer and crystal_node and is_instance_valid(crystal_node) and not me.is_dead:
			show_crystal = true
			var cpos = crystal_node.global_position
			_aim_pointer(crystal_pointer, cam, center, cpos)
			var dist = cpos.distance_to(me.global_position + Vector3(0, 0.9, 0))
			crystal_distance_label.text = "CRYSTAL: " + str(int(round(dist))) + "m"
			crystal_distance_label.position = center + Vector2(-110, POINTER_RADIUS + (54 if show_pointer else 30))

	opponent_pointer.visible = show_pointer
	opponent_height_label.visible = show_pointer
	if crystal_pointer:
		crystal_pointer.visible = show_crystal
		crystal_distance_label.visible = show_crystal
	if crosshair:
		crosshair.visible = me != null and not me.is_dead

func _aim_pointer(pointer: Control, cam: Camera3D, center: Vector2, target: Vector3) -> void :
	var dir = cam.unproject_position(target) - center
	# Projection of a point behind the camera comes out mirrored.
	if cam.is_position_behind(target):
		dir = -dir
	if dir.length() < 0.001:
		dir = Vector2(0, -1)
	dir = dir.normalized()
	pointer.position = center + dir * POINTER_RADIUS
	pointer.rotation = dir.angle()

func update_local_hud_hp(hp: int) -> void :
	if local_hp_label:
		local_hp_label.text = "YOUR HP: " + str(hp) + " / 100"
		if hp <= 30:
			local_hp_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		elif hp <= 60:
			local_hp_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		else:
			local_hp_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))

func _build_main_menu() -> void :
	_clear_ui()
	if mm_phase != "menu":
		mm_phase = "idle"
		mm_lobby_peers.clear()
		_mm_clear_pending()
		_leave_trystero_room()
		_net_reset()
	_reset_match_state()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	is_single_player = false
	_lb_set(local_nickname, local_elo)

	menu_canvas = CanvasLayer.new()
	add_child(menu_canvas)

	var center_panel = CenterContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_canvas.add_child(center_panel)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 520)
	center_panel.add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(340, 0)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(container)

	# --- Title Card Banner Image (res://CARD.png) ---
	if ResourceLoader.exists(TITLE_CARD_PATH):
		var title_tex = load(TITLE_CARD_PATH) as Texture2D
		if title_tex:
			var title_card_rect = TextureRect.new()
			title_card_rect.texture = title_tex
			title_card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			title_card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			title_card_rect.custom_minimum_size = Vector2(340, 170)
			container.add_child(title_card_rect)

	var nick_label = Label.new()
	nick_label.text = "Enter Nickname:"
	nick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(nick_label)

	nickname_input = LineEdit.new()
	nickname_input.text = local_nickname
	nickname_input.placeholder_text = "Player Name"
	nickname_input.custom_minimum_size = Vector2(320, 35)
	nickname_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nickname_input.focus_exited.connect(_save_nickname_from_input)
	container.add_child(nickname_input)

	var elo_row = HBoxContainer.new()
	elo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(elo_row)

	var tex = load_rank_texture(local_elo)
	if tex:
		var icon = TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(42, 42)
		elo_row.add_child(icon)

	var elo_lbl = Label.new()
	elo_lbl.text = " Current ELO: " + str(local_elo) + " (" + get_rank_name(local_elo) + ")"
	elo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elo_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	elo_row.add_child(elo_lbl)

	menu_online_label = Label.new()
	menu_online_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_online_label.add_theme_font_size_override("font_size", 12)
	menu_online_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	container.add_child(menu_online_label)
	_lb_update_online_label()

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer)

	var play_btn = Button.new()
	play_btn.text = "Find Ranked 1v1 Match"
	play_btn.custom_minimum_size = Vector2(320, 45)
	play_btn.pressed.connect( func(): _on_find_match_pressed("1v1"))
	container.add_child(play_btn)

	var duo_btn = Button.new()
	duo_btn.text = "Find Ranked 2v2 Match (4 players)"
	duo_btn.custom_minimum_size = Vector2(320, 40)
	duo_btn.pressed.connect( func(): _on_find_match_pressed("2v2"))
	container.add_child(duo_btn)

	var trio_btn = Button.new()
	trio_btn.text = "Find Ranked 3v3 Match (6 players)"
	trio_btn.custom_minimum_size = Vector2(320, 40)
	trio_btn.pressed.connect( func(): _on_find_match_pressed("3v3"))
	container.add_child(trio_btn)

	var ffa_btn = Button.new()
	ffa_btn.text = "Find Free For All (3-5 players)"
	ffa_btn.custom_minimum_size = Vector2(320, 40)
	ffa_btn.pressed.connect( func(): _on_find_match_pressed("ffa"))
	container.add_child(ffa_btn)

	var sp_btn = Button.new()
	sp_btn.text = "Single Player Practice (No ELO)"
	sp_btn.custom_minimum_size = Vector2(320, 40)
	sp_btn.pressed.connect(_on_single_player_pressed)
	container.add_child(sp_btn)

	var leaderboard_btn = Button.new()
	leaderboard_btn.text = "Leaderboard"
	leaderboard_btn.custom_minimum_size = Vector2(320, 35)
	leaderboard_btn.pressed.connect(_show_leaderboard_ui)
	container.add_child(leaderboard_btn)

	var clear_btn = Button.new()
	clear_btn.text = "Clear Leaderboard"
	clear_btn.custom_minimum_size = Vector2(320, 35)
	clear_btn.pressed.connect(_on_clear_leaderboard_pressed)
	container.add_child(clear_btn)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer2)

	var backup_info_label = Label.new()
	backup_info_label.text = "Make sure you back up your save data often, you can paste your copied save data into Google Docs."
	backup_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	backup_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	backup_info_label.custom_minimum_size = Vector2(320, 0)
	backup_info_label.add_theme_font_size_override("font_size", 11)
	backup_info_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	container.add_child(backup_info_label)

	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 5)
	container.add_child(spacer3)

	var exp_btn = Button.new()
	exp_btn.text = "Export Save Data"
	exp_btn.custom_minimum_size = Vector2(320, 35)
	exp_btn.pressed.connect(_on_export_save_pressed)
	container.add_child(exp_btn)

	var imp_btn = Button.new()
	imp_btn.text = "Import Save Data"
	imp_btn.custom_minimum_size = Vector2(320, 35)
	imp_btn.pressed.connect(_on_import_save_pressed)
	container.add_child(imp_btn)

	if pending_error_message != "":
		var msg_lbl = Label.new()
		msg_lbl.text = pending_error_message
		msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
		container.add_child(msg_lbl)
		pending_error_message = ""

	# Sit in the leaderboard room while on the menu, and (re)announce ourselves -
	# our ELO or nickname may have just changed.
	if mm_phase == "menu":
		_lb_announce()
	else:
		_lb_enter_room()

# --- LEADERBOARD ROOM ---

func _lb_enter_room() -> void :
	if mm_phase == "menu":
		return
	mm_phase = "menu"
	lb_online.clear()
	lb_heartbeat_timer = 0.0
	_switch_room(LEADERBOARD_ROOM_CODE)

func _lb_leave_room() -> void :
	if mm_phase != "menu":
		return
	mm_phase = "idle"
	lb_online.clear()
	_leave_trystero_room()
	_net_reset()

# Our own entry: everyone in the room hears our nickname and ELO.
func _lb_announce(to: String = "") -> void :
	if mm_phase != "menu":
		return
	_lb_set(local_nickname, local_elo)
	var pkt = {"action": "lb_presence", "nick": local_nickname, "elo": local_elo, "t": leaderboard_data[local_nickname]["t"], "links": direct_peers.keys()}
	if to != "":
		pkt["to"] = to
	send_p2p_packet(pkt)

func _lb_on_peer_joined(tid: String) -> void :
	# Tell the newcomer who we are, and hand them everything we know.
	_lb_announce(tid)
	send_p2p_packet({"action": "lb_sync", "to": tid, "leaderboard": leaderboard_data})

func _lb_handle_packet(action: String, sender: String, data: Dictionary) -> void :
	var to = String(data.get("to", ""))
	if to != "" and to != _get_self_trystero_id():
		return # addressed to someone else (we may still have relayed it)
	match action:
		"lb_presence":
			var nick = String(data.get("nick", ""))
			if nick == "":
				return
			var elo = int(data.get("elo", 0))
			if not lb_online.has(sender) and not direct_peers.has(sender):
				# First time we hear from someone we can only reach through a
				# relay - swap leaderboards with them too.
				send_p2p_packet({"action": "lb_sync", "to": sender, "leaderboard": leaderboard_data})
			lb_online[sender] = {"nick": nick, "elo": elo, "ms": _now_ms()}
			if nick != local_nickname:
				# The player themself is the authority on their own ELO.
				var have = leaderboard_data.get(nick, null)
				if not (have is Dictionary) or int(have.get("elo", -1)) != elo:
					_lb_set(nick, elo, max(float(data.get("t", 0.0)), float(have.get("t", 0.0)) if have is Dictionary else 0.0))
					_save_leaderboard_cache()
				lb_ui_dirty = true
			_lb_update_online_label()
		"lb_sync":
			if _lb_merge(data.get("leaderboard", {})):
				_save_leaderboard_cache()
				lb_ui_dirty = true
		_:
			pass # this room carries leaderboard data only - nothing else is played here

func _lb_tick(dt: float, now: int) -> void :
	lb_heartbeat_timer -= dt
	if lb_heartbeat_timer <= 0.0:
		lb_heartbeat_timer = LB_HEARTBEAT
		_lb_announce()
	for tid in lb_online.keys():
		if not direct_peers.has(tid) and now - int(lb_online[tid]["ms"]) > LB_ONLINE_TIMEOUT_MS:
			lb_online.erase(tid)
			lb_ui_dirty = true
	lb_ui_timer -= dt
	if lb_ui_timer <= 0.0:
		lb_ui_timer = 1.0
		_lb_update_online_label()
		if lb_ui_dirty and leaderboard_list:
			_fill_leaderboard_list()
		lb_ui_dirty = false

func _lb_online_nicks() -> Dictionary:
	var out: Dictionary = {}
	for tid in lb_online:
		out[String(lb_online[tid]["nick"])] = true
	return out

func _lb_update_online_label() -> void :
	if menu_online_label:
		var n = _lb_online_nicks().size()
		menu_online_label.text = "Players online in the menu: " + str(n + 1) + (" (just you)" if n == 0 else "")


func _on_clear_leaderboard_pressed() -> void :
	clear_leaderboard_data()
	pending_error_message = "Leaderboard data successfully cleared!"
	_build_main_menu()

func _show_leaderboard_ui() -> void :
	_clear_ui()

	leaderboard_canvas = CanvasLayer.new()
	add_child(leaderboard_canvas)

	var center_panel = CenterContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	leaderboard_canvas.add_child(center_panel)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 320)
	center_panel.add_child(panel)

	var container = VBoxContainer.new()
	panel.add_child(container)

	var title = Label.new()
	title.text = "--- ELO LEADERBOARD ---"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 220)
	container.add_child(scroll)

	leaderboard_list = VBoxContainer.new()
	scroll.add_child(leaderboard_list)
	_fill_leaderboard_list()

	var back_btn = Button.new()
	back_btn.text = "Back to Menu"
	back_btn.pressed.connect(_build_main_menu)
	container.add_child(back_btn)

# Sorted by ELO; players currently online in the menu are marked. Refreshes
# by itself while open when new data comes in from the leaderboard room.
func _fill_leaderboard_list() -> void :
	if not leaderboard_list:
		return
	for c in leaderboard_list.get_children():
		c.queue_free()
	var list = leaderboard_list
	_lb_set(local_nickname, local_elo, float(leaderboard_data.get(local_nickname, {}).get("t", _wall_time())))
	var online = _lb_online_nicks()
	online[local_nickname] = true
	var names: Array = leaderboard_data.keys()
	names.sort_custom(func(a, b):
		var ea = int(leaderboard_data[a].get("elo", 0)) if leaderboard_data[a] is Dictionary else 0
		var eb = int(leaderboard_data[b].get("elo", 0)) if leaderboard_data[b] is Dictionary else 0
		return ea > eb if ea != eb else String(a) < String(b))

	for player_key in names:
		var entry = leaderboard_data[player_key]
		var elo = int(entry.get("elo", 0)) if entry is Dictionary else 0

		var row = HBoxContainer.new()
		list.add_child(row)

		var tex = load_rank_texture(elo)
		if tex:
			var icon = TextureRect.new()
			icon.texture = tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(32, 32)
			row.add_child(icon)

		var label = Label.new()
		label.text = " " + str(player_key) + ": " + str(elo) + " ELO (" + get_rank_name(elo) + ")"
		row.add_child(label)

		if online.has(String(player_key)):
			var on_lbl = Label.new()
			on_lbl.text = "  online" if String(player_key) != local_nickname else "  you"
			on_lbl.add_theme_font_size_override("font_size", 11)
			on_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
			row.add_child(on_lbl)


func calculate_elo_change(player_elo: int, opponent_elo: int, score: float, k_factor: float = 32.0) -> int:
	var expected: float = 1.0 / (1.0 + pow(10.0, float(opponent_elo - player_elo) / 400.0))
	return int(round(k_factor * (score - expected)))

# Team ELO: each team's rating is its players' average at the start of the
# match, and every player on a team gains/loses the same amount. (1v1 is just
# teams of one, so this is the same formula as before.) In 2v2/3v3, winners who
# were eliminated (killed or fell off) get half the gain, rounded down - so a
# +16 win is +8 for them, and a +1 win is +0. Anyone who quit or disconnected
# always gets the loss, even if their team went on to win.
# `dead_list` is the host's list of eliminated players when it called the
# result, so every client halves exactly the same players.
func _process_match_outcome(winning_team: int, dead_list = null) -> void :
	if is_game_over:
		return
	is_game_over = true
	_show_dead_banner(false)

	if is_single_player:
		_show_match_results_screen("Level " + str(dummy_level) + " Dummy Defeated!", true, 0, local_elo, local_elo, false)
		return

	var my_team = get_team(local_peer_id)
	var is_winner = my_team == winning_team and not forfeited_peers.has(local_peer_id)
	var avg = [_team_avg_elo(0), _team_avg_elo(1)]
	var start_elo = local_elo
	var my_change = 0
	var my_halved = false
	var updated: Dictionary = {}
	var eliminated: Dictionary = {}
	if dead_list == null:
		eliminated = dead_peers.duplicate()
	else:
		for d in dead_list:
			eliminated[int(d)] = true

	for pid in all_player_ids():
		var team = get_team(pid)
		var won = team == winning_team and not forfeited_peers.has(pid)
		var change = calculate_elo_change(avg[team], avg[1 - team], 1.0 if won else 0.0)
		if won and team_size > 1 and eliminated.has(pid):
			change = int(floor(change / 2.0))
			if pid == local_peer_id:
				my_halved = true
		var before = local_elo if pid == local_peer_id else int(match_start_elos.get(pid, player_elos.get(pid, 1000)))
		updated[pid] = int(clamp(before + change, 0, MAX_ELO))
		var nick = local_nickname if pid == local_peer_id else String(player_nicknames.get(pid, "Player " + str(pid)))
		_lb_set(nick, int(updated[pid]))
		if pid == local_peer_id:
			my_change = change

	local_elo = int(updated[local_peer_id])
	_save_leaderboard_cache()
	save_player_data()

	send_p2p_packet({
		"action": "sync_state", 
		"nicknames": player_nicknames, 
		"elos": updated, 
		"leaderboard": leaderboard_data
	})
	_schedule_room_leave()

	var banner_text = "You won the 1v1" if is_winner else "You lost the 1v1"
	if team_size > 1:
		banner_text = ("Your team won the " if is_winner else "Your team lost the ") + game_mode
	var note = "Half ELO - you were eliminated before your team won." if my_halved else ""
	_show_match_results_screen(banner_text, is_winner, my_change, start_elo, local_elo, local_elo >= MAX_ELO, note)

# Leaving a team match early: you take your team's loss right away, while
# your teammates play on.
func _process_forfeit_result() -> void :
	if is_game_over:
		return
	is_game_over = true
	var my_team = get_team(local_peer_id)
	var change = calculate_elo_change(_team_avg_elo(my_team), _team_avg_elo(1 - my_team), 0.0)
	var start_elo = local_elo
	local_elo = int(clamp(local_elo + change, 0, MAX_ELO))
	_lb_set(local_nickname, local_elo)
	_save_leaderboard_cache()
	save_player_data()
	_schedule_room_leave()
	_show_match_results_screen("You left the " + game_mode, false, change, start_elo, local_elo, local_elo >= MAX_ELO)

func _schedule_room_leave() -> void :
	if not is_single_player:
		leave_room_timer = MM_CONFIRM_LINGER + 0.5

func _show_match_results_screen(outcome_title: String, is_winner: bool, elo_change: int, start_elo: int, target_elo: int, hit_max_elo: bool = false, note: String = "") -> void :
	_clear_ui()

	if world_root:
		world_root.queue_free()
		world_root = null
	players_container = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	results_canvas = CanvasLayer.new()
	results_canvas.layer = 100
	add_child(results_canvas)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_canvas.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 340)
	center.add_child(panel)

	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(container)

	var title = Label.new()
	title.text = outcome_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3) if is_winner else Color(1.0, 0.3, 0.3))
	container.add_child(title)

	var delta_lbl = Label.new()
	if is_single_player:
		delta_lbl.text = "+0 ELO (Practice Mode)"
		delta_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	elif hit_max_elo:
		delta_lbl.text = "You have reached the max ELO."
		delta_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		delta_lbl.text = ("+ " if elo_change >= 0 else "- ") + str(abs(elo_change)) + " ELO"
		delta_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3) if elo_change >= 0 else Color(1.0, 0.3, 0.3))

	delta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	delta_lbl.add_theme_font_size_override("font_size", 18 if hit_max_elo else 20)
	container.add_child(delta_lbl)

	if note != "":
		var note_lbl = Label.new()
		note_lbl.text = note
		note_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note_lbl.add_theme_font_size_override("font_size", 13)
		note_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
		container.add_child(note_lbl)

	var rank_row = HBoxContainer.new()
	rank_row.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(rank_row)

	anim_rank_icon = TextureRect.new()
	anim_rank_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	anim_rank_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	anim_rank_icon.custom_minimum_size = Vector2(42, 42)
	rank_row.add_child(anim_rank_icon)

	anim_elo_label = Label.new()
	anim_elo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_row.add_child(anim_elo_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	container.add_child(spacer)

	var bar_outer = MarginContainer.new()
	bar_outer.custom_minimum_size = Vector2(380, 50)
	container.add_child(bar_outer)

	var bar_vbox = VBoxContainer.new()
	bar_outer.add_child(bar_vbox)

	var bar_bg = Panel.new()
	bar_bg.custom_minimum_size = Vector2(380, 28)
	bar_vbox.add_child(bar_bg)

	anim_fill_rect = ColorRect.new()
	anim_fill_rect.color = Color(0.2, 0.6, 0.9, 0.8)
	bar_bg.add_child(anim_fill_rect)

	anim_marker_rect = ColorRect.new()
	anim_marker_rect.color = Color(1.0, 0.9, 0.2, 1.0)
	anim_marker_rect.custom_minimum_size = Vector2(6, 28)
	bar_bg.add_child(anim_marker_rect)

	var text_row = HBoxContainer.new()
	bar_vbox.add_child(text_row)

	var left_lbl = Label.new()
	var current_tier_base = floori(target_elo / 100.0) * 100
	left_lbl.text = str(current_tier_base) + " ELO"
	left_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_lbl.add_theme_font_size_override("font_size", 11)
	text_row.add_child(left_lbl)

	var right_lbl = Label.new()
	if target_elo >= MAX_ELO:
		right_lbl.text = "MAX RANK REACHED"
	else:
		right_lbl.text = "Next Rank: " + str(current_tier_base + 100) + " ELO"
	right_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_lbl.add_theme_font_size_override("font_size", 11)
	text_row.add_child(right_lbl)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 15)
	container.add_child(spacer2)

	var return_btn = Button.new()
	return_btn.text = "Return to Main Menu"
	return_btn.custom_minimum_size = Vector2(240, 40)
	return_btn.pressed.connect(_build_main_menu)
	container.add_child(return_btn)

	anim_start_elo = float(start_elo)
	anim_target_elo = float(target_elo)
	anim_current_elo = float(start_elo)
	anim_timer = 0.0
	is_animating_elo = true
	_update_elo_animation_ui()

func _update_elo_animation_ui() -> void :
	var val_int = int(round(anim_current_elo))
	if anim_elo_label:
		anim_elo_label.text = " Rating: " + str(val_int) + " ELO (" + get_rank_name(val_int) + ")"

	if anim_rank_icon:
		anim_rank_icon.texture = load_rank_texture(val_int)

	var current_step_progress = 1.0 if val_int >= MAX_ELO else (val_int % 100) / 100.0

	if anim_fill_rect:
		anim_fill_rect.size = Vector2(380 * current_step_progress, 28)
	if anim_marker_rect:
		anim_marker_rect.position = Vector2(clamp(380 * current_step_progress - 3, 0, 374), 0)

func _clear_ui() -> void :
	if dummy_level_canvas:
		dummy_level_canvas.queue_free()
		dummy_level_canvas = null
	if map_ban_canvas:
		map_ban_canvas.queue_free()
		map_ban_canvas = null
		map_row_container = null
		map_ban_header_label = null
		map_ban_timer_label = null
		ban_order_label = null
	if menu_canvas:
		menu_canvas.queue_free()
		menu_canvas = null
	if leaderboard_canvas:
		leaderboard_canvas.queue_free()
		leaderboard_canvas = null
	if hud_canvas:
		hud_canvas.queue_free()
		hud_canvas = null
		console_list = null
		local_hp_label = null
		waiting_opponent_label = null
		cooldown_progress_bar = null
		cooldown_bar_container = null
		opponent_pointer = null
		opponent_height_label = null
		crystal_pointer = null
		crystal_distance_label = null
		ability_label = null
		crosshair = null
		team_hud_label = null
		dead_banner_label = null
		leave_confirm_label = null
	menu_online_label = null
	leaderboard_list = null
	if results_canvas:
		results_canvas.queue_free()
		results_canvas = null

func _forfeit_match() -> void :
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_game_over:
		return
	log_console("[Match] You forfeited the match.")

	if is_single_player:
		is_game_over = true
		_return_to_main_menu()
		return

	send_p2p_packet({"action": "player_forfeit"})
	forfeited_peers[local_peer_id] = true
	if is_ffa:
		if not dead_peers.has(local_peer_id):
			ffa_places[local_peer_id] = _alive_count()
			dead_peers[local_peer_id] = true
		_process_ffa_leave()
		return
	if team_size == 1:
		# 1v1: leaving hands the win straight to the opponent.
		_process_match_outcome(1 - get_team(local_peer_id))
	else:
		_process_forfeit_result()

func _return_to_main_menu(error_msg: String = "") -> void :
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pending_error_message = error_msg
	if world_root:
		world_root.queue_free()
		world_root = null
	players_container = null
	_build_main_menu()


func _build_3d_environment() -> void :
	if world_root: world_root.queue_free()

	world_root = Node3D.new()
	world_root.name = "3DWorld"
	add_child(world_root)

	var light = DirectionalLight3D.new()
	light.position = Vector3(0, 15, 0)
	light.rotation_degrees = Vector3(-45, 45, 0)
	world_root.add_child(light)

	var floor_color = selected_map_data.get("color", Color(0.2, 0.2, 0.2))
	var wall_color = selected_map_data.get("wall_color", Color(0.1, 0.1, 0.1))
	var mechanic = selected_map_data.get("mechanic", "default")

	var floor_body = StaticBody3D.new()
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(50, 50)
	floor_mesh.mesh = plane

	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = floor_color
	floor_mesh.material_override = floor_mat

	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(50, 0.1, 50)
	floor_shape.shape = box

	floor_body.add_child(floor_mesh)
	floor_body.add_child(floor_shape)
	world_root.add_child(floor_body)

	# Nav grid is rebuilt for each map, once the physics bodies exist.
	nav_grid = null
	nav_floor_rid = floor_body.get_rid()

	_create_wall_block(Vector3(0, 2, -25), Vector3(50, 4, 1), wall_color)
	_create_wall_block(Vector3(0, 2, 25), Vector3(50, 4, 1), wall_color)
	_create_wall_block(Vector3(-25, 2, 0), Vector3(1, 4, 50), wall_color)
	_create_wall_block(Vector3(25, 2, 0), Vector3(1, 4, 50), wall_color)

	_build_map_mechanics(mechanic, wall_color)

	players_container = Node3D.new()
	players_container.name = "Players"
	world_root.add_child(players_container)

func _build_map_mechanics(mechanic: String, wall_color: Color) -> void :
	match mechanic:
		"portals":
			_create_wall_block(Vector3(-8, 1.5, -6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(8, 1.5, 6), Vector3(2, 3, 6), wall_color)
			_create_portal_pair(Vector3(-20, 1, -10), Vector3(20, 1, 10))
		"slopes":
			_create_ramp(Vector3(-10, 1.5, -10), Vector3(6, 0.5, 12), -25.0, wall_color)
			_create_ramp(Vector3(10, 1.5, 10), Vector3(6, 0.5, 12), 25.0, wall_color)
			_create_wall_block(Vector3(0, 3, 0), Vector3(12, 0.5, 12), wall_color)
		"jump_pads":
			_create_wall_block(Vector3(-8, 1.5, -6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(8, 1.5, 6), Vector3(2, 3, 6), wall_color)
			_create_jump_pad(Vector3(-12, 0.2, -12), 22.0)
			_create_jump_pad(Vector3(12, 0.2, 12), 22.0)
			_create_jump_pad(Vector3(0, 0.2, 0), 26.0)
		"toxic_hazards":
			_create_toxic_pool(Vector3(0, 0.05, 0), Vector3(16, 0.1, 16))
			_create_wall_block(Vector3(-12, 1.5, 0), Vector3(4, 3, 4), wall_color)
			_create_wall_block(Vector3(12, 1.5, 0), Vector3(4, 3, 4), wall_color)
		"ice_physics":
			_create_wall_block(Vector3(0, 1.5, 0), Vector3(6, 3, 6), wall_color)
			_create_jump_pad(Vector3(-15, 0.2, 15), 18.0)
			_create_jump_pad(Vector3(15, 0.2, -15), 18.0)
		"recharge_pads":
			_create_wall_block(Vector3(-8, 1.5, -6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(8, 1.5, 6), Vector3(2, 3, 6), wall_color)
			_create_recharge_pad(Vector3(0, 0.2, 0))
		"labyrinth":
			_create_wall_block(Vector3(-10, 2, -10), Vector3(20, 4, 1), wall_color)
			_create_wall_block(Vector3(10, 2, 10), Vector3(20, 4, 1), wall_color)
			_create_wall_block(Vector3(0, 2, -5), Vector3(1, 4, 15), wall_color)
			_create_wall_block(Vector3(0, 2, 5), Vector3(1, 4, 15), wall_color)
		"ladders":
			# Tall walls with walkable tops, linked by bridges, climbed by ladders.
			var h = 6.0
			_create_wall_block(Vector3(-12, h / 2.0, 0), Vector3(3, h, 20), wall_color)
			_create_wall_block(Vector3(12, h / 2.0, 0), Vector3(3, h, 20), wall_color)
			_create_wall_block(Vector3(0, h / 2.0, 0), Vector3(6, h, 6), wall_color)
			_create_wall_block(Vector3(-6.75, h - 0.25, 0), Vector3(7.5, 0.5, 2.5), wall_color)
			_create_wall_block(Vector3(6.75, h - 0.25, 0), Vector3(7.5, 0.5, 2.5), wall_color)
			for z in [-6.0, 6.0]:
				# Left rampart: outer face (spawn side) and inner face
				_create_ladder(Vector3(-13.5, 0, z), Vector3(-1, 0, 0), h)
				_create_ladder(Vector3(-10.5, 0, z), Vector3(1, 0, 0), h)
				# Right rampart
				_create_ladder(Vector3(13.5, 0, z), Vector3(1, 0, 0), h)
				_create_ladder(Vector3(10.5, 0, z), Vector3(-1, 0, 0), h)
			# Central tower, north and south faces
			_create_ladder(Vector3(0, 0, -3), Vector3(0, 0, -1), h)
			_create_ladder(Vector3(0, 0, 3), Vector3(0, 0, 1), h)
		"glass_barriers":
			var glass_col = Color(0.7, 0.9, 1.0, 0.35)
			_create_wall_block(Vector3(-8, 1.5, 0), Vector3(1, 3, 16), glass_col)
			_create_wall_block(Vector3(8, 1.5, 0), Vector3(1, 3, 16), glass_col)
		_:
			_create_wall_block(Vector3(-8, 1.5, -6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(8, 1.5, 6), Vector3(2, 3, 6), wall_color)
			_create_wall_block(Vector3(0, 1.5, 0), Vector3(4, 3, 4), wall_color)

func _create_wall_block(pos: Vector3, size: Vector3, color: Color) -> void :
	var body = StaticBody3D.new()
	body.position = pos

	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape

	body.add_child(mesh_inst)
	body.add_child(col)
	world_root.add_child(body)

func _create_ramp(pos: Vector3, size: Vector3, rot_x_deg: float, color: Color) -> void :
	var body = StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.x = rot_x_deg

	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape

	body.add_child(mesh_inst)
	body.add_child(col)
	world_root.add_child(body)

func _create_portal_pair(pos_a: Vector3, pos_b: Vector3) -> void :
	var exit_offset_a = Vector3(0, 0, 3)
	var exit_offset_b = Vector3(0, 0, -3)

	var portal_a = MapPortal.new(pos_b + exit_offset_b)
	portal_a.position = pos_a
	world_root.add_child(portal_a)

	var portal_b = MapPortal.new(pos_a + exit_offset_a)
	portal_b.position = pos_b
	world_root.add_child(portal_b)

func _create_jump_pad(pos: Vector3, launch_force: float) -> void :
	var pad = MapJumpPad.new(launch_force)
	pad.position = pos
	world_root.add_child(pad)

func _create_toxic_pool(pos: Vector3, size: Vector3) -> void :
	var pool = MapToxicPool.new(size)
	pool.position = pos
	world_root.add_child(pool)

func _create_ladder(face_pos: Vector3, outward_normal: Vector3, height: float) -> void :
	var ladder = MapLadder.new(outward_normal, height)
	ladder.position = face_pos
	ladder.rotation.y = atan2(outward_normal.x, outward_normal.z) # local +Z faces outward
	world_root.add_child(ladder)

func _create_recharge_pad(pos: Vector3) -> void :
	var pad = MapRechargePad.new(self)
	pad.position = pos
	world_root.add_child(pad)

# --- NAV GRID (practice dummy pathfinding) ---

func nav_world_to_cell(p: Vector3) -> Vector2i:
	var size = NAV_HALF_EXTENT * 2 + 1
	return Vector2i(
		clampi(roundi(p.x) + NAV_HALF_EXTENT, 0, size - 1),
		clampi(roundi(p.z) + NAV_HALF_EXTENT, 0, size - 1))

func nav_cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x - NAV_HALF_EXTENT, 0.0, c.y - NAV_HALF_EXTENT)

# Must be called from _physics_process (direct space state is only valid there).
func build_nav_grid(space_state: PhysicsDirectSpaceState3D) -> void :
	var size = NAV_HALF_EXTENT * 2 + 1
	nav_grid = AStarGrid2D.new()
	nav_grid.region = Rect2i(0, 0, size, size)
	nav_grid.cell_size = Vector2(1, 1)
	nav_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav_grid.update()

	# Probe a body-sized box in each cell, from just above the floor to head
	# height. Slightly wider than the dummy so paths keep clear of walls.
	var probe = BoxShape3D.new()
	probe.size = Vector3(1.2, 1.56, 1.2)
	var params = PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.exclude = [nav_floor_rid]

	var solid_count = 0
	for ix in range(size):
		for iz in range(size):
			var cell = Vector2i(ix, iz)
			var w = nav_cell_to_world(cell)
			params.transform = Transform3D(Basis(), Vector3(w.x, 0.8, w.z))
			for hit in space_state.intersect_shape(params, 16):
				var c = hit.get("collider")
				if c is CharacterBody3D:
					continue
				if c is StaticBody3D or c is MapPortal:
					# Walls, ramps, glass - and portals, so the dummy doesn't
					# teleport away mid-path.
					nav_grid.set_point_solid(cell, true)
					solid_count += 1
					break
				if c is MapToxicPool:
					nav_grid.set_point_weight_scale(cell, 12.0)
				elif c is MapJumpPad or c is MapRechargePad:
					nav_grid.set_point_weight_scale(cell, 3.0)

	log_console("[Practice] Dummy nav grid ready (" + str(size * size - solid_count) + " walkable cells).")

func _nav_nearest_open(c: Vector2i) -> Vector2i:
	if not nav_grid.is_point_solid(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if abs(dx) != r and abs(dz) != r:
					continue
				var n = c + Vector2i(dx, dz)
				if nav_grid.is_in_boundsv(n) and not nav_grid.is_point_solid(n):
					return n
	return c

func get_nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out = PackedVector3Array()
	if not nav_grid:
		return out
	var a = _nav_nearest_open(nav_world_to_cell(from))
	var b = _nav_nearest_open(nav_world_to_cell(to))
	for id in nav_grid.get_id_path(a, b):
		var wp = nav_cell_to_world(id)
		wp.y = from.y
		out.append(wp)
	return out

# True if a body can walk straight from a to b: every grid cell under the line
# (and under lines offset by the body's radius) is open and hazard-free.
func nav_line_clear(a: Vector3, b: Vector3) -> bool:
	if nav_grid == null:
		return false
	var d = Vector2(b.x - a.x, b.z - a.z)
	var length = d.length()
	if length < 0.01:
		return true
	var dir = d / length
	var perp = Vector2(-dir.y, dir.x) * 0.45
	var steps = int(ceil(length / 0.25))
	for i in range(steps + 1):
		var pt = Vector2(a.x, a.z) + dir * (length * float(i) / float(steps))
		for off in [Vector2.ZERO, perp, -perp]:
			var q = pt + off
			var c = nav_world_to_cell(Vector3(q.x, 0.0, q.y))
			if nav_grid.is_point_solid(c) or nav_grid.get_point_weight_scale(c) > 1.0:
				return false
	return true

# Drops grid waypoints that can be skipped in a straight line, so the bot runs
# direct lines instead of zig-zagging cell to cell.
func smooth_nav_path(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() <= 2 or nav_grid == null:
		return path
	var out = PackedVector3Array([path[0]])
	var i = 0
	while i < path.size() - 1:
		var j = path.size() - 1
		while j > i + 1 and not nav_line_clear(path[i], path[j]):
			j -= 1
		out.append(path[j])
		i = j
	return out

func get_random_nav_point() -> Vector3:
	var size = NAV_HALF_EXTENT * 2 + 1
	for _i in range(40):
		var c = Vector2i(randi() % size, randi() % size)
		if not nav_grid.is_point_solid(c) and nav_grid.get_point_weight_scale(c) <= 1.0:
			return nav_cell_to_world(c)
	return Vector3.ZERO

# Picks a reachable open spot that is far from the threat (used to flee).
func get_nav_point_away_from(threat: Vector3, from: Vector3) -> Vector3:
	var best = get_random_nav_point()
	var best_score = -INF
	for _i in range(24):
		var p = get_random_nav_point()
		var score = p.distance_to(Vector3(threat.x, 0, threat.z)) - 0.3 * p.distance_to(Vector3(from.x, 0, from.z))
		if score > best_score:
			best_score = score
			best = p
	return best

func _spawn_player(peer_id: int) -> void :
	var player = NetworkPlayer.new(peer_id, self)
	player.name = str(peer_id)

	# Blue team on the west side facing east, Red team on the east facing west.
	player.position = _spawn_point(peer_id)
	player.rotation_degrees.y = -90 if get_team(peer_id) == 0 else 90
	if is_ffa:
		player.rotation.y = atan2(player.position.x, player.position.z) # face the middle
	player.spawn_position = player.position

	players_container.add_child(player)

func _spawn_test_dummy(peer_id: int) -> void :
	var dummy = NetworkPlayer.new(peer_id, self)
	dummy.name = str(peer_id)
	dummy.position = Vector3(15, 1, 0)
	dummy.rotation_degrees.y = 90
	dummy.spawn_position = dummy.position
	dummy.is_dummy = true
	players_container.add_child(dummy)
	player_nicknames[peer_id] = "Test Dummy"
	player_elos[peer_id] = 0


class Crosshair extends Control:
	# Plus-shaped crosshair drawn around this control's origin (screen center).
	const ARM: float = 9.0
	const GAP: float = 3.0
	const THICK: float = 2.0

	func _draw() -> void:
		var outline = Color(0, 0, 0, 0.75)
		var col = Color(1, 1, 1, 0.95)
		for pass_i in range(2):
			var c = outline if pass_i == 0 else col
			var w = THICK + 2.0 if pass_i == 0 else THICK
			var ext = 1.0 if pass_i == 0 else 0.0
			draw_line(Vector2(-ARM - ext, 0), Vector2(-GAP + ext, 0), c, w)
			draw_line(Vector2(GAP - ext, 0), Vector2(ARM + ext, 0), c, w)
			draw_line(Vector2(0, -ARM - ext), Vector2(0, -GAP + ext), c, w)
			draw_line(Vector2(0, GAP - ext), Vector2(0, ARM + ext), c, w)


class PowerCrystal extends Area3D:
	# A floating crystal. Touching it (local player only) asks the manager to
	# grant its ability; the host decides who actually gets it.
	var crystal_id: int
	var ability: String
	var main_manager: Node
	var crystal_color: Color
	var display_name: String
	var visual: Node3D
	var t: float = 0.0
	var claim_cooldown: float = 0.0

	func _init(id: int, ability_key: String, color: Color, label_text: String, manager: Node) -> void:
		crystal_id = id
		ability = ability_key
		crystal_color = color
		display_name = label_text
		main_manager = manager

	func _ready() -> void:
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(1.4, 1.8, 1.4)
		col.shape = box
		add_child(col)

		visual = Node3D.new()
		add_child(visual)

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = crystal_color
		mat.emission_energy_multiplier = 2.5

		# Two 4-sided cones tip to tip = an octahedron crystal.
		var top = MeshInstance3D.new()
		var top_mesh = CylinderMesh.new()
		top_mesh.top_radius = 0.0
		top_mesh.bottom_radius = 0.42
		top_mesh.height = 0.6
		top_mesh.radial_segments = 4
		top_mesh.rings = 1
		top.mesh = top_mesh
		top.position.y = 0.3
		top.material_override = mat
		visual.add_child(top)

		var bottom = MeshInstance3D.new()
		var bottom_mesh = CylinderMesh.new()
		bottom_mesh.top_radius = 0.42
		bottom_mesh.bottom_radius = 0.0
		bottom_mesh.height = 0.6
		bottom_mesh.radial_segments = 4
		bottom_mesh.rings = 1
		bottom.mesh = bottom_mesh
		bottom.position.y = -0.3
		bottom.material_override = mat
		visual.add_child(bottom)

		var light = OmniLight3D.new()
		light.light_color = crystal_color
		light.light_energy = 1.5
		light.omni_range = 4.0
		add_child(light)

		var tag = Label3D.new()
		tag.text = display_name
		tag.position = Vector3(0, 1.1, 0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 18
		tag.outline_size = 5
		tag.modulate = crystal_color
		add_child(tag)

	func _process(delta: float) -> void:
		t += delta
		if visual:
			visual.rotation.y += 1.8 * delta
			visual.position.y = sin(t * 2.5) * 0.15

	func _physics_process(delta: float) -> void:
		claim_cooldown -= delta
		if claim_cooldown > 0.0:
			return
		for body in get_overlapping_bodies():
			if body is CharacterBody3D and body.has_method("is_local_player") and body.is_local_player():
				claim_cooldown = 0.75
				main_manager.on_crystal_touched(self)
				return


class OpponentPointer extends Control:
	# Arrow drawn around this control's origin, pointing along +X.
	# Position and rotation are set every frame by _update_opponent_pointer().
	var pulse: float = 0.0
	var arrow_color: Color = Color(1.0, 0.35, 0.25)

	func _process(delta: float) -> void:
		if visible:
			pulse += delta
			queue_redraw()

	func _draw() -> void:
		var a = 0.75 + 0.25 * sin(pulse * 6.0)
		var pts = PackedVector2Array([Vector2(24, 0), Vector2(-12, -16), Vector2(-4, 0), Vector2(-12, 16)])
		draw_colored_polygon(pts, Color(arrow_color.r, arrow_color.g, arrow_color.b, a))
		var outline = pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0, 0, 0.7 * a), 2.0, true)


class MapLadder extends Area3D:
	# Placed at the base of a wall face; local +Z points away from the wall.
	var outward_normal: Vector3
	var height: float

	func _init(normal: Vector3, h: float) -> void:
		outward_normal = normal.normalized()
		height = h

	func _ready() -> void:
		collision_mask = 1 | 2 # living players and ghosts (dead teammates roaming)
		# Climb zone: in front of the wall, reaching a little above the top so
		# the player's feet clear the edge before the climb ends.
		var zone_h = height + 0.25
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(1.4, zone_h, 1.0)
		col.shape = box
		col.position = Vector3(0, zone_h / 2.0, 0.5)
		add_child(col)

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.28, 0.12)

		# Two rails plus rungs every 0.4m (visual only, no collision).
		for x in [-0.5, 0.5]:
			_add_box(Vector3(x, height / 2.0, 0.1), Vector3(0.1, height, 0.1), mat)
		var y = 0.3
		while y < height:
			_add_box(Vector3(0, y, 0.1), Vector3(1.0, 0.07, 0.07), mat)
			y += 0.4

		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

	func _add_box(pos: Vector3, size: Vector3, mat: Material) -> void:
		var mesh = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		mesh.position = pos
		mesh.material_override = mat
		add_child(mesh)

	func _on_body_entered(body: Node3D) -> void:
		if body.has_method("enter_ladder"):
			body.enter_ladder(self)

	func _on_body_exited(body: Node3D) -> void:
		if body.has_method("exit_ladder"):
			body.exit_ladder(self)


class MapPortal extends Area3D:
	var dest_pos: Vector3
	var cooldown_players: Dictionary = {}

	func _init(target: Vector3) -> void:
		dest_pos = target

	func _ready() -> void:
		collision_mask = 1 | 2 # living players and ghosts (dead teammates roaming)
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(2.5, 3.5, 0.5)
		col.shape = box
		add_child(col)

		var mesh = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 0.8
		torus.outer_radius = 1.3
		mesh.mesh = torus
		mesh.rotation_degrees.x = 90

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.6, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.5, 1.0)
		mat.emission_energy_multiplier = 3.0
		mesh.material_override = mat
		add_child(mesh)

		body_entered.connect(_on_body_entered)

	func _process(delta: float) -> void:
		for player in cooldown_players.keys():
			cooldown_players[player] -= delta
			if cooldown_players[player] <= 0.0:
				cooldown_players.erase(player)

	func _on_body_entered(body: Node3D) -> void:
		if body is CharacterBody3D and not cooldown_players.has(body):
			cooldown_players[body] = 1.5
			body.global_position = dest_pos


class MapJumpPad extends Area3D:
	var force: float = 20.0

	func _init(boost_force: float = 20.0) -> void:
		force = boost_force

	func _ready() -> void:
		collision_mask = 1 | 2 # living players and ghosts (dead teammates roaming)
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(3.0, 0.5, 3.0)
		col.shape = box
		add_child(col)

		var mesh = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 1.4
		cyl.bottom_radius = 1.6
		cyl.height = 0.2
		mesh.mesh = cyl

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.0)
		mat.emission_energy_multiplier = 2.5
		mesh.material_override = mat
		add_child(mesh)

		body_entered.connect(_on_body_entered)

	func _on_body_entered(body: Node3D) -> void:
		if body is CharacterBody3D:
			body.velocity.y = force


class MapToxicPool extends Area3D:
	var damage_timer: float = 0.0

	func _init(size: Vector3) -> void:
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = size
		col.shape = box
		add_child(col)

		var mesh = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(size.x, size.z)
		mesh.mesh = plane

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.9, 0.3, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.0, 0.8, 0.2)
		mat.emission_energy_multiplier = 1.5
		mesh.material_override = mat
		add_child(mesh)

	func _physics_process(delta: float) -> void:
		damage_timer += delta
		if damage_timer >= 1.0:
			damage_timer = 0.0
			for body in get_overlapping_bodies():
				if body.has_method("apply_damage"):
					body.apply_damage(5)


class MapRechargePad extends Area3D:
	var main_manager: Node

	func _init(manager: Node) -> void:
		main_manager = manager

	func _ready() -> void:
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(2.5, 0.5, 2.5)
		col.shape = box
		add_child(col)

		var mesh = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.2
		cyl.height = 0.15
		mesh.mesh = cyl

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.9, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.1)
		mat.emission_energy_multiplier = 3.0
		mesh.material_override = mat
		add_child(mesh)

		body_entered.connect(_on_body_entered)

	func _on_body_entered(body: Node3D) -> void:
		if main_manager and body is CharacterBody3D and body.has_method("is_local_player") and body.is_local_player():
			main_manager.reset_combat_cooldown()
			main_manager.log_console("[Map] Recharge pad triggered - Cooldown reset!")


class NetworkPlayer extends CharacterBody3D:
	var peer_id: int
	var main_manager: Node
	var camera: Camera3D
	var name_label: Label3D
	var hussing_label: Label3D
	var mesh_inst: MeshInstance3D
	var base_material: StandardMaterial3D
	var outline_material: StandardMaterial3D

	var is_dummy: bool = false
	var is_movement_locked: bool = false
	var lock_sources: Dictionary = {} # attacker peer_id -> true while their QTE holds us
	var team: int = 0
	var is_dead: bool = false
	var spawn_position: Vector3 = Vector3.ZERO
	var qte_target_peer: int = -1
	var mouse_sensitivity: float = 0.003
	var walk_speed: float = 8.0
	var sprint_speed: float = 14.0
	var jump_velocity: float = 7.0

	var health: int = 100
	var targeted_opponent: NetworkPlayer = null

	var qte_active: bool = false
	var qte_delay_timer: float = 0.0
	var qte_e_released: bool = false
	var qte_canvas: CanvasLayer = null
	var qte_indicator: ColorRect = null
	var qte_target_box: ColorRect = null
	var qte_progress: float = 0.0
	var qte_direction: float = 1.0
	var qte_target_start: float = 0.4
	var qte_target_width: float = 0.2

	var qte_elapsed: float = 0.0
	const QTE_MAX_DURATION: float = 4.0
	var lock_failsafe_timer: float = 0.0
	const MOVEMENT_LOCK_FAILSAFE: float = 6.0

	var is_launching: bool = false
	var launch_target_pos: Vector3 = Vector3.ZERO
	var launch_timer: float = 0.0

	var gravity_mult: float = 1.0
	var friction: float = 1.0

	const LADDER_CLIMB_SPEED: float = 5.0
	var ladder_contacts: Array = []

	# Crystal abilities (local player reads main_manager.local_ability)
	var ability_tag: Label3D = null
	var jump_held_last: bool = false
	var q_held_last: bool = false
	var qte_double_damage: bool = false

	# Practice dummy AI
	#  Level 1: wanders and runs away from you.
	#  Level 2: + hops around and moves a bit faster.
	#  Level 3: + hunts you (smoothed paths, re-planned as you move) and attacks
	#           like a player would - it holds you for a moment, then hits for
	#           25 or misses (50% miss).
	#  Level 4: + only misses 30% of the time, moves at sprint speed.
	const DUMMY_SPEED: float = 4.5
	const DUMMY_FLEE_RANGE: float = 9.0
	const BOT_ATTACK_RANGE: float = 4.5
	const BOT_WINDUP: float = 0.9
	const BOT_ATTACK_COOLDOWN: float = 3.0
	var bot_attack_cd: float = 2.5
	var bot_windup: float = 0.0
	var bot_target: NetworkPlayer = null
	var bot_jump_timer: float = 2.0
	var bot_hits: int = 0
	var bot_misses: int = 0
	var bot_jumps: int = 0
	var bot_status_label: Label3D = null
	var nav_path: PackedVector3Array = PackedVector3Array()
	var nav_path_index: int = 0
	var dummy_repath_timer: float = 0.0
	var dummy_stuck_timer: float = 0.0
	var dummy_last_pos: Vector3 = Vector3.ZERO
	var dummy_frames: int = 0

	func _init(id: int = 1, manager: Node = null) -> void :
		peer_id = id
		main_manager = manager

	func set_ability_tag(text: String, color: Color) -> void :
		if not ability_tag:
			return
		ability_tag.text = text
		ability_tag.modulate = color
		ability_tag.visible = text != ""

	func set_movement_lock(locked: bool) -> void :
		lock_sources.clear()
		is_movement_locked = locked
		lock_failsafe_timer = MOVEMENT_LOCK_FAILSAFE if locked else 0.0

	# Several enemies can hold you at once in team modes; you're free again
	# once every one of their QTEs has ended.
	func add_movement_lock(source: int) -> void :
		lock_sources[source] = true
		is_movement_locked = true
		lock_failsafe_timer = MOVEMENT_LOCK_FAILSAFE

	func remove_movement_lock(source: int) -> void :
		lock_sources.erase(source)
		if lock_sources.is_empty():
			is_movement_locked = false
			lock_failsafe_timer = 0.0

	func is_local_player() -> bool:
		if is_dummy:
			return false
		return peer_id == main_manager.local_peer_id

	# Eliminated: invisible to everyone, can't be hit or block anyone, but the
	# local player can still walk, jump and climb around the map.
	func set_dead_state() -> void :
		if is_dead:
			return
		is_dead = true
		health = 0
		_cancel_own_qte()
		lock_sources.clear()
		is_movement_locked = false
		is_launching = false
		set_highlight(false)
		if targeted_opponent:
			targeted_opponent.set_highlight(false)
			targeted_opponent = null
		if mesh_inst:
			mesh_inst.visible = false
		for lbl in [name_label, hussing_label, ability_tag, get_node_or_null("HPLabel")]:
			if lbl:
				lbl.visible = false
		# Layer 2 = ghost: living players (mask 1) pass through us and their
		# targeting rays ignore us; we still stand on the world.
		collision_layer = 2
		var parent = get_parent()
		if parent:
			for other in parent.get_children():
				if other != self and other is PhysicsBody3D:
					add_collision_exception_with(other)

	func _cancel_own_qte() -> void :
		if not qte_active:
			return
		qte_active = false
		qte_target_peer = -1
		if not is_local_player():
			return
		main_manager.is_qte_in_progress = false
		if qte_canvas:
			qte_canvas.queue_free()
			qte_canvas = null
		if targeted_opponent:
			targeted_opponent.is_movement_locked = false
			if not main_manager.is_single_player:
				main_manager.send_p2p_packet({
					"action": "qte_end", 
					"attacker": str(peer_id), 
					"target": str(targeted_opponent.peer_id)
				})

	func _ready() -> void :
		if main_manager:
			team = main_manager.get_team(peer_id)
		if main_manager and main_manager.selected_map_data:
			var mech = main_manager.selected_map_data.get("mechanic", "")
			if mech == "low_gravity":
				gravity_mult = 0.45
				jump_velocity = 9.0
			elif mech == "ice_physics":
				friction = 0.1

		mesh_inst = MeshInstance3D.new()
		var cap = CapsuleMesh.new()
		cap.height = 1.8
		cap.radius = 0.4
		mesh_inst.mesh = cap
		mesh_inst.position.y = 0.9

		base_material = StandardMaterial3D.new()
		if is_dummy:
			base_material.albedo_color = Color(0.6, 0.6, 0.6)
		elif main_manager.is_ffa:
			base_material.albedo_color = main_manager.player_color(peer_id)
		elif main_manager.team_size > 1 and not main_manager.is_single_player:
			var team_col: Color = main_manager.TEAM_COLORS[team]
			base_material.albedo_color = team_col.lerp(Color(randf(), randf(), randf()), 0.15)
		else:
			base_material.albedo_color = Color(randf(), randf(), randf())

		mesh_inst.material_override = base_material
		add_child(mesh_inst)

		outline_material = StandardMaterial3D.new()
		outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
		outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline_material.albedo_color = Color(1.0, 0.9, 0.1)
		outline_material.grow = true
		outline_material.grow_amount = 0.05

		var col = CollisionShape3D.new()
		var cap_shape = CapsuleShape3D.new()
		cap_shape.height = 1.8
		cap_shape.radius = 0.4
		col.shape = cap_shape
		col.position.y = 0.9
		add_child(col)

		name_label = Label3D.new()
		name_label.position = Vector3(0, 2.3, 0)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.font_size = 22
		name_label.outline_size = 6
		add_child(name_label)

		if is_dummy:
			name_label.text = "[Practice Dummy] Level " + str(_bot_level())
			bot_status_label = Label3D.new()
			bot_status_label.position = Vector3(0, 3.0, 0)
			bot_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			bot_status_label.font_size = 20
			bot_status_label.outline_size = 5
			bot_status_label.visible = false
			add_child(bot_status_label)
		else:
			var nick = main_manager.player_nicknames.get(peer_id, "Player " + str(peer_id)) if main_manager else "Player"
			var elo = main_manager.player_elos.get(peer_id, 0) if main_manager else 0
			update_nametag(nick, elo)

		hussing_label = Label3D.new()
		hussing_label.position = Vector3(0, 2.6, 0)
		hussing_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hussing_label.font_size = 16
		hussing_label.outline_size = 4
		hussing_label.modulate = Color(1.0, 0.9, 0.2)
		hussing_label.text = "You're in Hussing range, press 'E'"
		hussing_label.visible = false
		add_child(hussing_label)

		_build_health_label()

		ability_tag = Label3D.new()
		ability_tag.position = Vector3(0, 2.95, 0)
		ability_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ability_tag.font_size = 16
		ability_tag.outline_size = 4
		ability_tag.visible = false
		add_child(ability_tag)

		if is_local_player():
			camera = Camera3D.new()
			camera.position = Vector3(0, 1.5, 0)
			add_child(camera)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	func update_nametag(nickname: String, elo: int) -> void :
		if name_label and main_manager and not is_dummy:
			var rank_title = main_manager.get_rank_name(elo)
			var prefix = ""
			if main_manager.is_ffa:
				name_label.modulate = main_manager.player_color(peer_id).lerp(Color.WHITE, 0.35)
			elif main_manager.team_size > 1 and not main_manager.is_single_player:
				prefix = "[" + main_manager.TEAM_NAMES[team] + "] "
				name_label.modulate = (main_manager.TEAM_COLORS[team] as Color).lerp(Color.WHITE, 0.35)
			name_label.text = prefix + "[" + rank_title + "] " + nickname

	func _build_health_label() -> void :
		var hp_label = Label3D.new()
		hp_label.name = "HPLabel"
		hp_label.position = Vector3(0, 2.0, 0)
		hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hp_label.font_size = 18
		hp_label.outline_size = 4
		hp_label.modulate = Color(0.2, 1.0, 0.2)
		hp_label.text = "HP: " + str(health) + "/100"
		add_child(hp_label)

	func _update_health_display() -> void :
		var hp_label = get_node_or_null("HPLabel") as Label3D
		if hp_label:
			hp_label.text = "HP: " + str(health) + "/100"
			if health <= 30:
				hp_label.modulate = Color(1.0, 0.2, 0.2)
			elif health <= 60:
				hp_label.modulate = Color(1.0, 0.8, 0.2)
			else:
				hp_label.modulate = Color(0.2, 1.0, 0.2)

		if is_local_player() and main_manager:
			main_manager.update_local_hud_hp(health)

	func apply_damage(amount: int) -> void :
		if is_dead:
			return
		health = max(0, health - amount)
		_update_health_display()

		if health <= 0:
			main_manager.on_player_killed(self)

	func _unhandled_input(event: InputEvent) -> void :
		if not is_local_player() or is_dummy or is_movement_locked:
			return

		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y( - event.relative.x * mouse_sensitivity)
			if camera:
				camera.rotate_x( - event.relative.y * mouse_sensitivity)
				camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	func _physics_process(delta: float) -> void :
		_update_health_display()

		if global_position.y < FALL_BOUNDARY_Y:
			if is_dummy:
				apply_damage(100)
			elif is_local_player():
				if is_dead:
					# Ghosts can't die twice - just send them home.
					global_position = spawn_position
					velocity = Vector3.ZERO
					main_manager.log_console("[Match] You fell off the map - back to your spawn.")
					_send_p2p_position()
				else:
					main_manager.log_console("[Match] You fell off the map!")
					main_manager.kill_local_player_from_fall()
					if is_dead and (main_manager.team_size > 1 or main_manager.is_ffa):
						# 2v2/3v3: you're out but your team plays on - roam
						# invisibly from your spawn.
						global_position = spawn_position
						velocity = Vector3.ZERO
						_send_p2p_position()
			return

		if is_dummy:
			_process_dummy_ai(delta)
			return

		if not is_local_player():
			return

		# Your own QTE keeps running even if an enemy grabs you mid-attack.
		if qte_active:
			_process_qte(delta)
			return

		if is_movement_locked:
			# Failsafe: never stay frozen forever if the unlock packet is lost.
			lock_failsafe_timer -= delta
			if lock_failsafe_timer <= 0.0:
				lock_sources.clear()
				is_movement_locked = false
				main_manager.log_console("[Combat] Movement lock expired.")
			velocity.x = 0
			velocity.z = 0
			if get_active_ladder() and not is_on_floor():
				velocity.y = 0.0 # hang on the ladder while frozen
			elif not is_on_floor():
				velocity.y -= 20.0 * gravity_mult * delta
			move_and_slide()
			_send_p2p_position()
			return

		if is_launching:
			launch_timer -= delta
			var launch_dir = (launch_target_pos - global_position).normalized()
			velocity = launch_dir * 32.0 + Vector3(0, 3, 0)
			move_and_slide()
			_send_p2p_position()
			if launch_timer <= 0.0:
				is_launching = false
			return

		if Input.is_key_pressed(KEY_TAB):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		if not is_dead:
			_detect_and_highlight_opponents()

			if Input.is_key_pressed(KEY_E) and targeted_opponent and not main_manager.combat_cooldown_active and not main_manager.is_qte_in_progress:
				_start_qte()

		if not is_on_floor():
			velocity.y -= 20.0 * gravity_mult * delta

		var is_sprinting: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)
		var current_speed: float = sprint_speed if is_sprinting else walk_speed
		var ability: String = main_manager.local_ability
		if ability == "speed_boost":
			current_speed *= main_manager.SPEED_BOOST_MULT

		var jump_pressed: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("ui_accept")
		var jump_just_pressed = jump_pressed and not jump_held_last
		jump_held_last = jump_pressed
		if jump_pressed and is_on_floor():
			velocity.y = jump_velocity * (1.2 if is_sprinting else 1.0)
		elif jump_just_pressed and ability == "double_jump" and get_active_ladder() == null:
			# Second jump in mid-air - uses up the crystal.
			velocity.y = jump_velocity * 1.1
			main_manager.consume_local_ability("used")

		var q_pressed = Input.is_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_Q)
		var q_just_pressed = q_pressed and not q_held_last
		q_held_last = q_pressed
		if q_just_pressed and ability == "lunge":
			_start_lunge()
			return

		var input_dir: Vector3 = Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1

		var direction = (transform.basis * input_dir).normalized()
		if direction != Vector3.ZERO:
			velocity.x = lerp(velocity.x, direction.x * current_speed, friction)
			velocity.z = lerp(velocity.z, direction.z * current_speed, friction)
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed * friction)
			velocity.z = move_toward(velocity.z, 0, current_speed * friction)

		var ladder = get_active_ladder()
		if ladder:
			_apply_ladder_climb(ladder, direction, jump_pressed)

		move_and_slide()
		_send_p2p_position()

	# --- LADDERS ---
	func enter_ladder(ladder: Node) -> void :
		if not ladder_contacts.has(ladder):
			ladder_contacts.append(ladder)

	func exit_ladder(ladder: Node) -> void :
		ladder_contacts.erase(ladder)

	func get_active_ladder() -> MapLadder:
		for l in ladder_contacts:
			if is_instance_valid(l):
				return l
		return null

	# Walking into a ladder climbs it, walking away from it climbs down,
	# no input hangs in place, and jump kicks off it.
	func _apply_ladder_climb(ladder: MapLadder, direction: Vector3, jump_pressed: bool) -> void :
		var push = direction.dot(-ladder.outward_normal)
		if jump_pressed and not is_on_floor():
			velocity = ladder.outward_normal * 6.0 + Vector3(0, 5.0, 0)
			ladder_contacts.clear()
			return

		if not is_on_floor():
			# While on the ladder, don't drift away from the wall (that's what
			# jump is for) and slow sideways movement so you stay on it.
			var n = ladder.outward_normal
			var horiz = Vector3(velocity.x, 0.0, velocity.z)
			var away = horiz.dot(n)
			if away > 0.0:
				horiz -= n * away
			var into = horiz.dot(-n)
			var lateral = horiz + n * into
			horiz = (-n) * max(into, 0.0) + lateral * 0.5
			velocity.x = horiz.x
			velocity.z = horiz.z

		if push > 0.3:
			velocity.y = LADDER_CLIMB_SPEED
		elif push < -0.3 and not is_on_floor():
			velocity.y = -LADDER_CLIMB_SPEED
		elif not is_on_floor():
			velocity.y = 0.0

	func _start_lunge() -> void :
		# Dash forward (where you're facing, flat) using the launch movement.
		var forward = -global_transform.basis.z
		forward.y = 0.0
		if forward.length() < 0.01:
			forward = Vector3(0, 0, -1)
		forward = forward.normalized()
		is_launching = true
		launch_timer = 0.3
		# Farther than the dash can travel, so the direction never flips mid-dash.
		launch_target_pos = global_position + forward * 20.0
		main_manager.consume_local_ability("used")
		_send_p2p_position()

	func _bot_level() -> int:
		return int(main_manager.dummy_level) if main_manager else 1

	func _dummy_speed() -> float:
		match _bot_level():
			1:
				return DUMMY_SPEED
			2, 3:
				return 5.5
			_:
				return sprint_speed # level 4: as fast as a player holding Shift

	func bot_miss_chance() -> float:
		match _bot_level():
			3:
				return 0.5
			4:
				return 0.3
			_:
				return 1.0 # levels 1-2 never attack

	func _bot_roll_hit() -> bool:
		return randf() >= bot_miss_chance()

	func _bot_face(target: Vector3, delta: float) -> void :
		var to = target - global_position
		if Vector2(to.x, to.z).length() > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 12.0 * delta)

	func _set_bot_status(text: String, color: Color = Color.WHITE) -> void :
		if bot_status_label:
			bot_status_label.text = text
			bot_status_label.modulate = color
			bot_status_label.visible = text != ""

	# In range, roughly level, and nothing in the way.
	func _bot_can_hit(target: NetworkPlayer) -> bool:
		if target == null or target.is_dead:
			return false
		if global_position.distance_to(target.global_position) > BOT_ATTACK_RANGE:
			return false
		if abs(target.global_position.y - global_position.y) > 2.5:
			return false
		var q = PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), target.global_position + Vector3(0, 0.9, 0))
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var hit = get_world_3d().direct_space_state.intersect_ray(q)
		return hit.get("collider") == target

	# Like a player's QTE: the target is held while the bot "times" its hit.
	func _bot_start_attack(target: NetworkPlayer) -> void :
		bot_target = target
		bot_windup = BOT_WINDUP
		qte_active = true
		qte_target_peer = target.peer_id
		target.add_movement_lock(peer_id)
		velocity.x = 0.0
		velocity.z = 0.0
		_set_bot_status("ATTACKING!", Color(1.0, 0.35, 0.25))

	func _bot_process_windup(delta: float) -> void :
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		var t = bot_target
		if t == null or not is_instance_valid(t) or t.is_dead or not qte_active:
			_bot_end_attack(false, true) # cancelled (e.g. clash)
			return
		_bot_face(t.global_position, delta)
		bot_windup -= delta
		if bot_windup <= 0.0:
			_bot_end_attack(_bot_roll_hit(), false)

	func _bot_end_attack(hit: bool, cancelled: bool) -> void :
		var t = bot_target
		bot_windup = 0.0
		bot_target = null
		qte_active = false
		qte_target_peer = -1
		bot_attack_cd = BOT_ATTACK_COOLDOWN
		_set_bot_status("")
		if t and is_instance_valid(t):
			t.remove_movement_lock(peer_id)
		if cancelled or t == null or not is_instance_valid(t):
			return
		if hit:
			bot_hits += 1
			is_launching = true
			launch_timer = 0.45
			launch_target_pos = t.global_position
			main_manager.log_console("[Practice] The dummy hit you for 25!")
			t.apply_damage(25) # may end the match - nothing after this
		else:
			bot_misses += 1
			main_manager.log_console("[Practice] The dummy missed!")

	func _process_dummy_ai(delta: float) -> void :
		if not is_on_floor():
			velocity.y -= 20.0 * gravity_mult * delta

		# Build the nav grid a few physics frames in, once the map's collision
		# shapes are registered with the physics server.
		dummy_frames += 1
		if main_manager.nav_grid == null:
			if dummy_frames >= 3:
				main_manager.build_nav_grid(get_world_3d().direct_space_state)
				dummy_last_pos = global_position
			move_and_slide()
			return

		var level = _bot_level()
		var speed = _dummy_speed()

		# Flung by a clash, or dashing into you after landing a hit.
		if is_launching:
			launch_timer -= delta
			var launch_dir = (launch_target_pos - global_position).normalized()
			velocity = launch_dir * 32.0 + Vector3(0, 3, 0)
			move_and_slide()
			if launch_timer <= 0.0:
				is_launching = false
			return

		if bot_windup > 0.0:
			_bot_process_windup(delta)
			move_and_slide()
			return

		# Stand still while being hit by a QTE (or once defeated).
		if is_movement_locked or health <= 0:
			velocity.x = move_toward(velocity.x, 0.0, speed * friction)
			velocity.z = move_toward(velocity.z, 0.0, speed * friction)
			move_and_slide()
			return

		var player = main_manager.get_local_player()
		var hunting = level >= 3 and player != null and not player.is_dead
		bot_attack_cd -= delta
		if hunting and bot_attack_cd <= 0.0 and not main_manager.is_game_over and _bot_can_hit(player):
			_bot_start_attack(player)
			move_and_slide()
			return

		dummy_repath_timer -= delta
		if nav_path_index >= nav_path.size() or dummy_repath_timer <= 0.0:
			_dummy_pick_new_path()

		var desired = Vector3.ZERO
		if hunting and global_position.distance_to(player.global_position) < 2.2:
			# Close enough to strike: hold position and face the player.
			_bot_face(player.global_position, delta)
		elif nav_path_index < nav_path.size():
			var wp = nav_path[nav_path_index]
			var to_wp = Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
			if to_wp.length() < (0.35 if speed < 8.0 else 0.7):
				nav_path_index += 1
			else:
				desired = to_wp.normalized() * speed

		velocity.x = lerp(velocity.x, desired.x, friction)
		velocity.z = lerp(velocity.z, desired.z, friction)
		if desired.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-desired.x, -desired.z), 10.0 * delta)

		# Level 2+: hop every now and then while moving.
		if level >= 2 and is_on_floor():
			bot_jump_timer -= delta
			if bot_jump_timer <= 0.0 and desired.length() > 0.1:
				velocity.y = jump_velocity
				bot_jumps += 1
				bot_jump_timer = randf_range(1.5, 4.0)

		move_and_slide()

		# If we've barely moved for a second while trying to, pick a new path
		# (jumping first on level 2+, in case something low is in the way).
		dummy_stuck_timer += delta
		if dummy_stuck_timer >= 1.0:
			if nav_path_index < nav_path.size() and global_position.distance_to(dummy_last_pos) < 0.3:
				if level >= 2 and is_on_floor():
					velocity.y = jump_velocity
					bot_jumps += 1
				_dummy_pick_new_path()
			dummy_last_pos = global_position
			dummy_stuck_timer = 0.0

	func _dummy_pick_new_path() -> void :
		var target: Vector3
		var player = main_manager.get_local_player()
		var level = _bot_level()
		if level >= 3 and player and not player.is_dead:
			# Hunt: head for the player, re-planning often as they move.
			target = player.global_position
			dummy_repath_timer = 0.4
		elif player and global_position.distance_to(player.global_position) < DUMMY_FLEE_RANGE:
			# Player is close: run away, re-evaluating often.
			target = main_manager.get_nav_point_away_from(player.global_position, global_position)
			dummy_repath_timer = 1.5
		else:
			target = main_manager.get_random_nav_point()
			dummy_repath_timer = randf_range(4.0, 7.0)

		nav_path = main_manager.get_nav_path(global_position, target)
		if level >= 3:
			nav_path = main_manager.smooth_nav_path(nav_path)
		# Index 0 is the cell we're standing in; head for the next one.
		nav_path_index = 1 if nav_path.size() > 1 else nav_path.size()

	func _send_p2p_position() -> void :
		main_manager.send_p2p_packet({
			"action": "move", 
			"peer_id": str(peer_id), 
			"pos_x": global_position.x, 
			"pos_y": global_position.y, 
			"pos_z": global_position.z, 
			"rot_y": rotation_degrees.y
		})

	func is_in_camera_vision(target: NetworkPlayer) -> bool:
		if not camera:
			return false

		var target_pos = target.global_position + Vector3(0, 0.9, 0)
		if not camera.is_position_in_frustum(target_pos):
			return false

		var cam_forward = - camera.global_transform.basis.z.normalized()
		var dir_to_target = (target_pos - camera.global_position).normalized()
		var dot = cam_forward.dot(dir_to_target)

		if dot < 0.5:
			return false

		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(camera.global_position, target_pos)
		query.exclude = [self.get_rid()]
		query.collision_mask = 1 # world + living players (ghosts are on layer 2)

		var result = space_state.intersect_ray(query)
		if result and result.get("collider") == target:
			return true

		return false

	func _detect_and_highlight_opponents() -> void :
		var players_container = get_parent()
		if not players_container:
			return

		var closest_opponent: NetworkPlayer = null
		var min_distance: float = 6.0

		for child in players_container.get_children():
			if child is NetworkPlayer and child != self and not child.is_dead and not main_manager.is_teammate(child.peer_id, peer_id):
				var dist = global_position.distance_to(child.global_position)
				if dist < min_distance and is_in_camera_vision(child):
					min_distance = dist
					closest_opponent = child

		if targeted_opponent and targeted_opponent != closest_opponent:
			targeted_opponent.set_highlight(false)

		targeted_opponent = closest_opponent
		if targeted_opponent:
			targeted_opponent.set_highlight(true)

	func set_highlight(active: bool) -> void :
		if base_material:
			base_material.next_pass = outline_material if active else null
		if hussing_label:
			hussing_label.visible = active

	func trigger_repulse_clash(opp: NetworkPlayer) -> void:
		qte_active = false
		qte_target_peer = -1
		main_manager.is_qte_in_progress = false
		lock_sources.clear()
		is_movement_locked = false

		if qte_canvas:
			qte_canvas.queue_free()
			qte_canvas = null

		main_manager.start_combat_cooldown()

		if opp:
			opp.is_movement_locked = false
			opp.qte_active = false
			var repulse_dir = global_position - opp.global_position
			repulse_dir.y = 0.0
			if repulse_dir.length() < 0.01:
				# Standing on top of each other: push along our own back direction.
				repulse_dir = global_transform.basis.z
				repulse_dir.y = 0.0
			repulse_dir = repulse_dir.normalized()
			is_launching = true
			launch_timer = 0.45
			# Target is farther than the launch can travel (32 u/s * 0.45s), so the
			# fling direction never flips mid-flight.
			launch_target_pos = global_position + repulse_dir * 20.0

		main_manager.log_console("[Combat] Simultaneous attack clash! Both players repelled!")

	func _start_qte() -> void :
		# Clash only when the two players are attacking EACH OTHER (in team modes
		# the target may be busy attacking someone else).
		if targeted_opponent and targeted_opponent.qte_active and targeted_opponent.qte_target_peer == peer_id:
			trigger_repulse_clash(targeted_opponent)
			targeted_opponent.trigger_repulse_clash(self)
			if not main_manager.is_single_player:
				main_manager.send_p2p_packet({"action": "trigger_clash", "a": peer_id, "b": targeted_opponent.peer_id})
			return

		qte_active = true
		qte_target_peer = targeted_opponent.peer_id if targeted_opponent else -1
		qte_delay_timer = 0.35
		qte_e_released = false
		qte_progress = 0.0
		qte_direction = 1.0
		qte_elapsed = 0.0
		main_manager.is_qte_in_progress = true

		# Double Damage crystal: hits for 50, but the green target is half as wide.
		qte_double_damage = main_manager.local_ability == "double_damage"
		if qte_double_damage:
			qte_target_width = 0.1
			qte_target_start = 0.45
		else:
			qte_target_width = 0.2
			qte_target_start = 0.4

		if targeted_opponent:
			targeted_opponent.is_movement_locked = true
			if not main_manager.is_single_player:
				# One packet both announces our QTE and locks the target. If the
				# target is already in its own QTE when this arrives (both pressed E
				# at once), the receiver resolves it as a clash instead of a lock.
				main_manager.send_p2p_packet({
					"action": "qte_start",
					"attacker": str(peer_id),
					"target": str(targeted_opponent.peer_id)
				})

		qte_canvas = CanvasLayer.new()
		add_child(qte_canvas)

		var bg = Panel.new()
		bg.custom_minimum_size = Vector2(400, 40)
		bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		bg.position = Vector2(-200, -80)
		qte_canvas.add_child(bg)

		qte_target_box = ColorRect.new()
		qte_target_box.color = Color(0.2, 0.9, 0.3, 0.8)
		qte_target_box.custom_minimum_size = Vector2(400 * qte_target_width, 30)
		qte_target_box.position = Vector2(400 * qte_target_start, 5)
		bg.add_child(qte_target_box)

		qte_indicator = ColorRect.new()
		qte_indicator.color = Color(1.0, 0.2, 0.2, 1.0)
		qte_indicator.custom_minimum_size = Vector2(8, 36)
		qte_indicator.position = Vector2(0, 2)
		bg.add_child(qte_indicator)

	func _process_qte(delta: float) -> void :
		if not Input.is_key_pressed(KEY_E):
			qte_e_released = true

		# Don't let an unanswered QTE hold the opponent frozen forever.
		qte_elapsed += delta
		if qte_elapsed >= QTE_MAX_DURATION:
			qte_progress = -1.0
			_evaluate_qte()
			return

		if qte_delay_timer > 0.0:
			qte_delay_timer -= delta
			return

		qte_progress += delta * 1.5 * qte_direction
		if qte_progress >= 1.0:
			qte_progress = 1.0
			qte_direction = -1.0
		elif qte_progress <= 0.0:
			qte_progress = 0.0
			qte_direction = 1.0

		if qte_indicator:
			qte_indicator.position.x = qte_progress * (400 - 8)

		if qte_e_released and Input.is_key_pressed(KEY_E):
			_evaluate_qte()

	func _evaluate_qte() -> void :
		qte_active = false
		qte_target_peer = -1
		main_manager.is_qte_in_progress = false

		if qte_canvas:
			qte_canvas.queue_free()
			qte_canvas = null

		if targeted_opponent:
			targeted_opponent.is_movement_locked = false
			if not main_manager.is_single_player:
				main_manager.send_p2p_packet({
					"action": "qte_end",
					"attacker": str(peer_id),
					"target": str(targeted_opponent.peer_id)
				})

		main_manager.start_combat_cooldown()

		var damage = 50 if qte_double_damage else 25
		var hit = qte_progress >= qte_target_start and qte_progress <= (qte_target_start + qte_target_width)
		if qte_double_damage:
			qte_double_damage = false
			if main_manager.local_ability == "double_damage":
				main_manager.consume_local_ability("used")

		if hit and targeted_opponent and targeted_opponent.is_dead:
			main_manager.log_console("[Combat] Too late - they were already eliminated.")
		elif hit:
			if targeted_opponent:
				is_launching = true
				launch_timer = 0.45
				launch_target_pos = targeted_opponent.global_position

				if not main_manager.is_single_player:
					main_manager.send_p2p_packet({
						"action": "take_damage", 
						"peer_id": str(targeted_opponent.peer_id), 
						"amount": damage
					})
					main_manager.send_p2p_packet({
						"action": "trigger_cooldown", 
						"peer_id": str(targeted_opponent.peer_id)
					})
				targeted_opponent.apply_damage(damage)
				main_manager.log_console("[Combat] " + ("DOUBLE DAMAGE strike" if damage > 25 else "Precision strike") + " landed on " + targeted_opponent.name_label.text + "!")
		else:
			main_manager.log_console("[Combat] Timing missed! Cooldown triggered.")
