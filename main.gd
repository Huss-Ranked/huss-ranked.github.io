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
	# Huss Royale: 4-15 players on one big map with swords and shields.
	"royale": {"team_size": 1, "label": "Huss Royale", "min": 4, "max": 15},
}
# Free For All: once 3 players are queued, wait this long for more (a 5th
# player starts it right away), then start with whoever is there.
const FFA_WAIT_SECONDS: float = 30.0
const ROYALE_WAIT_SECONDS: float = 45.0 # 4+ queued: wait this long for more (15 starts right away)
const ROYALE_MAX_PLAYERS: int = 15
const ROYALE_SPAWN_RADIUS: float = 55.0
const ROYALE_START_ITEMS: int = 18
const ROYALE_MAX_ITEMS: int = 30 # swords + shields lying around at once
const ROYALE_ITEM_RESPAWN: float = 30.0 # a new batch of weapons every 30s...
const ROYALE_WEAPON_WAVE: int = 6 # ...this many at a time
const SWORD_BONUS: int = 5
const SHIELD_BLOCK: int = 5
const ROYALE_POS_SEND_MS: int = 50 # 20 position updates/s with up to 15 players
const ROYALE_MAP: Dictionary = {"name": "Huss Island", "color": Color(0.36, 0.56, 0.32), "wall_color": Color(0.52, 0.5, 0.46), "mechanic": "royale", "size": 130.0, "wall_height": 6.0,
	"desc": "A grassy island: houses, corner towers and a lookout tower in the middle.", "weapons": ["sword", "shield"], "special": "",
	"storm": "HUSS STORM", "storm_color": Color(0.62, 0.38, 1.0), "storm_end": 8.0}
const DESERT_MAP: Dictionary = {"name": "The Desert", "color": Color(0.87, 0.74, 0.49), "wall_color": Color(0.74, 0.58, 0.38), "mechanic": "desert", "size": 170.0, "wall_height": 9.0,
	"desc": "Five pyramids to explore (4 floors each). The best loot is inside - and a Genie waits at the top of whichever pyramid rises to 8 floors.",
	"weapons": ["sword", "bow"], "special": "genie",
	"storm": "SANDSTORM", "storm_color": Color(1.0, 0.55, 0.15), "storm_end": 10.0, "nav_top": 40.0, "nav_bottom": -1.0,
	"sky_top": Color(0.42, 0.6, 0.86), "sky_horizon": Color(0.98, 0.84, 0.62), "fog": Color(0.95, 0.8, 0.55), "fog_density": 0.0035,
	"ambient": Color(0.95, 0.85, 0.7), "sun": Color(1.0, 0.92, 0.78)}
const WASTELAND_MAP: Dictionary = {"name": "The Wasteland", "color": Color(0.33, 0.36, 0.24), "wall_color": Color(0.42, 0.3, 0.2), "mechanic": "wasteland", "size": 150.0, "wall_height": 7.0,
	"desc": "Radiation burns on the surface (-5 HP every 5s). Hide in the bunker under the middle of the map, or find a gas mask. Two bunker exits open at random each round.",
	"weapons": ["machete", "ballistic", "rifle", "gasmask"], "special": "gasmask", "custom_ground": true,
	"storm": "RADIATION STORM", "storm_color": Color(0.35, 1.0, 0.25), "storm_end": 9.0, "nav_top": 15.0, "nav_bottom": -13.0,
	"sky_top": Color(0.3, 0.38, 0.26), "sky_horizon": Color(0.52, 0.62, 0.34), "fog": Color(0.42, 0.58, 0.26), "fog_density": 0.0075,
	"ambient": Color(0.68, 0.76, 0.6), "ambient_energy": 0.7, "sun": Color(0.85, 0.95, 0.6), "sun_energy": 0.75}
const MOON_MAP: Dictionary = {"name": "The Moon", "color": Color(0.6, 0.6, 0.63), "wall_color": Color(0.5, 0.5, 0.52), "mechanic": "moon", "size": 120.0, "wall_height": 0.0,
	"desc": "Walk all the way round a little moon. Launch pads throw you to the asteroids - fall into the gap between them and you're lost in space. Portals lead to the other side.",
	"weapons": ["plasma", "raygun"], "special": "blackhole", "custom_ground": true, "no_walls": true,
	"storm": "DARK MATTER", "storm_color": Color(0.1, 0.0, 0.16), "storm_end": 7.0,
	"space": Color(0.0, 0.0, 0.015), "ambient": Color(0.55, 0.55, 0.66), "ambient_energy": 0.6, "sun": Color(1.0, 0.98, 0.94), "sun_energy": 1.15}
# Huss Royale: at the start of every round the players vote for one of these.
var ROYALE_MAPS: Array = [ROYALE_MAP, DESERT_MAP, WASTELAND_MAP, MOON_MAP]
const ROYALE_VOTE_SECONDS: float = 15.0
var royale_map_index: int = 0
var royale_seed: int = 0 # from the host with the vote result: the map's random details are the same for everyone
var royale_votes: Dictionary = {} # peer_id -> map index
var royale_vote_canvas: CanvasLayer = null
var royale_vote_cards: Array = []
var royale_vote_timer_label: Label = null
var royale_vote_deadline_ms: int = 0
var royale_vote_done: bool = false
var royale_vote_packet: Dictionary = {}
var royale_pending_choice: Dictionary = {}
var royale_start_at_ms: int = -1
var royale_vote_ask_ms: int = 0
# Huss Royale gear. slot: melee (adds to your hits), shield (takes damage off
# hits on you), ranged (left click / SHOOT), mask, special (F / USE), genie.
# You carry one of each slot; a better one (higher rank) replaces yours.
const GEAR: Dictionary = {
	"sword": {"name": "Sword", "slot": "melee", "bonus": 5, "rank": 1, "color": Color(0.75, 0.85, 1.0)},
	"machete": {"name": "Machete", "slot": "melee", "bonus": 5, "rank": 1, "color": Color(0.8, 0.95, 0.65)},
	"plasma": {"name": "Plasma Sword", "slot": "melee", "bonus": 5, "reach": 9.0, "rank": 1, "color": Color(0.3, 0.9, 1.0)},
	"gold_sword": {"name": "Pharaoh's Blade", "slot": "melee", "bonus": 10, "rank": 2, "color": Color(1.0, 0.8, 0.25)},
	"shield": {"name": "Shield", "slot": "shield", "block": 5, "block_ranged": 5, "rank": 1, "color": Color(1.0, 0.8, 0.35)},
	"ballistic": {"name": "Ballistic Shield", "slot": "shield", "block": 5, "block_ranged": 10, "rank": 1, "color": Color(0.65, 0.72, 0.85)},
	"bow": {"name": "Bow", "slot": "ranged", "dmg": 20, "cd": 1.0, "range": 70.0, "rank": 1, "color": Color(0.9, 0.65, 0.35)},
	"sun_bow": {"name": "Sun Bow", "slot": "ranged", "dmg": 30, "cd": 0.9, "range": 85.0, "rank": 2, "color": Color(1.0, 0.75, 0.2)},
	"rifle": {"name": "Hunting Rifle", "slot": "ranged", "dmg": 30, "cd": 1.6, "range": 120.0, "rank": 1, "color": Color(0.85, 0.6, 0.35)},
	"raygun": {"name": "Raygun", "slot": "ranged", "dmg": 15, "cd": 0.45, "range": 75.0, "rank": 1, "color": Color(0.35, 0.7, 1.0)},
	"gasmask": {"name": "Gas Mask", "slot": "mask", "rank": 1, "color": Color(0.55, 0.95, 0.45)},
	"blackhole": {"name": "Black Hole", "slot": "special", "rank": 1, "color": Color(0.75, 0.45, 1.0)},
	"genie": {"name": "Genie", "slot": "genie", "rank": 1, "color": Color(0.45, 0.85, 1.0)},
}
# The storm: from the 1 minute mark it closes in on the middle of the map,
# reaching it at 6 minutes. 10 seconds in it and you're out.
const STORM_START: float = 60.0
const STORM_FULL: float = 360.0
const STORM_GRACE: float = 10.0
var storm_root: Node3D = null
var storm_wall: MeshInstance3D = null
var storm_mm: MultiMeshInstance3D = null
var storm_parts: Array = []
var storm_outside_t: float = 0.0
var storm_label: Label = null
var storm_tint: ColorRect = null
var bot_storm_t: Dictionary = {}
# Huss Royale ELO by placement (scaled by your ELO - see royale_elo_change).
const ROYALE_PLACE_GAINS: Array = [40, 35, 30, 25, 20]
var is_royale: bool = false
var royale_items: Dictionary = {} # id -> {type, spot, pos}
var royale_item_nodes: Dictionary = {}
var royale_claims: Dictionary = {} # id -> ms we last asked the host for it
var player_gear: Dictionary = {} # peer_id -> {"sword": bool, "shield": bool}
var royale_seeded: bool = false
var royale_item_counter: int = 0
var royale_item_timer: float = 0.0
# Bots: a Royale that starts with fewer than 10 players is filled up to 10 with
# bots. The host runs them; how good they are depends on the room's average
# ELO (royale_bot_skill). They can sprint and jump from the start.
const ROYALE_FILL_TO: int = 10
const ROYALE_BOT_NAMES: Array = ["Bolt", "Rusty", "Sprocket", "Gizmo", "Turbo", "Nitro", "Clank", "Ziggy", "Pixel", "Widget", "Dash", "Blip", "Cog", "Spark", "Rivet"]
var royale_bots: Dictionary = {} # peer_id -> {"name", "level", "miss"}
var royale_fill_bots: bool = true
const ROYALE_BOT_SEND_MS: int = 66 # all bot positions in one packet, 15x a second
var royale_bot_send_ms: int = -100000
# Sky drop: everyone starts high above the island with low gravity for 15s and
# glides down to wherever they want to land.
const ROYALE_DROP_HEIGHT: float = 56.0
const ROYALE_GLIDE_TIME: float = 15.0
const ROYALE_GLIDE_GRAVITY: float = 0.15
const ROYALE_GLIDE_FALL: float = 3.7 # top falling speed while gliding (m/s)
var royale_time: float = 0.0 # seconds since this Royale match began
var royale_drop_label: Label = null
# Crystals: a wave every 40s - Regen crystals (+25 HP) plus the other kinds.
const ROYALE_CRYSTAL_WAVE_TIME: float = 40.0
const ROYALE_CRYSTAL_WAVE: Array = ["regen", "regen", "regen", "", ""] # "" = a random ability crystal
const ROYALE_MAX_CRYSTALS: int = 12
var royale_crystal_timer: float = 0.0
const REGEN_HEAL: int = 25
const REGEN_INFO: Dictionary = {"name": "Regen +25 HP", "color": Color(1.0, 0.3, 0.85)}
# Huss Royale only: Ctrl while sprinting (Shift) = slide.
const SLIDE_TIME: float = 0.8
const SLIDE_BOOST: float = 1.35
const SLIDE_COOLDOWN: float = 0.9
var mobile_slide_held: bool = false
var royale_ladders: Array = [] # [face_pos, outward_normal, height] - for bot pathfinding
var royale_spots_cache: Array = []
# Bot pathfinding on the island: a 1m grid of walkable surfaces (ground, ramps,
# platforms, tower tops) linked into an A* graph, with ladders as extra links.
# Built a few rows per physics frame on the host (during the sky drop).
const RNAV_HALF: int = 63
var rnav: AStar3D = null
var rnav_h: PackedFloat32Array = PackedFloat32Array()
var rnav_w: PackedFloat32Array = PackedFloat32Array()
var rnav_row: int = -1
var rnav_ready: bool = false
var third_person: bool = false # F5
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

# --- SOCIAL (challenges + parties) ---
const CHALLENGE_IS_RANKED: bool = true
const SOCIAL_REQUEST_TIMEOUT_MS: int = 20000
const SOCIAL_LINGER: float = 1.5
const PARTY_MAX: int = 5
const PARTY_PRUNE_MS: int = 600000 # drop a party member nobody has heard from in 10 min
const PARTY_LOBBY_WAIT_MS: int = 20000
var challenge_out: Dictionary = {} # {cid, to, nick, ms}
var challenge_in: Array = [] # [{cid, from, nick, ms}]
var party_id: String = ""
var party_leader: String = ""
var party_members: Array = [] # [[trystero id, nick], ...]
var party_joining: String = ""
var party_joining_ms: int = 0
var party_invites_in: Array = [] # [{pid, from, nick, size, ms}]
var party_invites_out: Dictionary = {} # trystero id -> ms
var party_leader_heard_ms: int = 0
var party_ver: int = 0 # bumped on every membership change, so late/stale updates are ignored
var party_queued: bool = false # queueing together with our party
var party_lobby_missing_since: int = 0
var party_lobby_seen: Dictionary = {}
var social_status: String = ""
var social_dirty: bool = false
var social_ui_timer: float = 0.0
var social_linger: Dictionary = {} # waiting a moment before switching rooms
var popup_canvas: CanvasLayer = null
var popup_key: String = ""
var popup_sub_label: Label = null
# Party codes: a 6-digit code the whole party can share; anyone on the main
# menu can type it in to join without an invite.
const PARTY_CODE_WAIT_MS: int = 6000
var party_code: String = ""
var party_code_joining: String = ""
var party_code_join_ms: int = 0
var party_code_joined: String = ""
var party_code_input: LineEdit = null
var party_panel_sig: String = ""
var lb_list_sig: String = ""
var party_panel_box: VBoxContainer = null
var party_panel_w: float = 265.0
var lb_status_label: Label = null
var mm_custom_match: bool = false # a challenge (not from the queue)
var mm_lobby_party: Dictionary = {} # lobby peer id -> [party id, party size]
var mm_peer_party: Dictionary = {} # match peer_id -> party id (for team assignment)
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
# --- CHARACTER COLOR ---
# Picked on the main menu (a preset or any hex code), saved with your profile,
# and sent to the other players so everyone sees the same color.
const COLOR_PRESETS: Array = [
	["Red", "e53935"], ["Orange", "fb8c00"], ["Yellow", "fdd835"],
	["Green", "43a047"], ["Blue", "1e88e5"], ["Purple", "8e24aa"],
	["Brown", "795548"], ["Black", "111111"], ["Pink", "f06292"],
]
var local_color_hex: String = ""
var player_colors: Dictionary = {} # peer_id -> "rrggbb"
# Per-part colors on top of the main color: part -> "rrggbb" (only the parts
# that differ). Parts: head, torso, arm_l, arm_r, leg_l, leg_r.
var local_part_colors: Dictionary = {}
# Crash test dummy: unlocked for good once you reach Rookie Runner 3 (500 ELO).
const DUMMY_UNLOCK_ELO: int = 500
var unlocked_dummy: bool = false
var dummy_just_unlocked: bool = false
var local_model: String = "mannequin" # "mannequin" or "dummy"
var player_models: Dictionary = {} # peer_id -> model
var color_preview_mats: Dictionary = {}
var player_part_colors: Dictionary = {} # peer_id -> {part: "rrggbb"}
const BODY_PART_NAMES: Dictionary = {"": "Whole Body", "head": "Head", "torso": "Torso", "arm_l": "Left Arm", "arm_r": "Right Arm", "leg_l": "Left Leg", "leg_r": "Right Leg"}
var color_edit_part: String = "" # "" = whole body
var color_preview_vp: SubViewport = null
var color_preview_body: Node3D = null
var color_preview_cam: Camera3D = null
var color_preview_outline: StandardMaterial3D = null
var color_part_label: Label = null
var color_preview_press: Vector2 = Vector2(-1, -1)
var color_preview_dragged: bool = false
# Admin commands from the browser console (see _admin_help)
var js_admin_cb: JavaScriptObject = null
var admin_pending_level: int = 0
const CLASH_WINDOW_MS: int = 300 # pressing E this close together vs the bot = a clash
var color_canvas: CanvasLayer = null
var color_preview: Control = null
var color_hex_input: LineEdit = null
var color_status_label: Label = null
var color_current_label: Label = null
var color_field: Control = null
# --- CONTROLS: PC or MOBILE (touch) ---
# Picked on the main menu and saved. Mobile shows on-screen controls (joystick,
# SPRINT toggle, HUSS = E, JUMP, Q when lunge is active, LEAVE), hides the
# console, lets you drag anywhere else on the screen to look around, and adds
# aim assist that pulls the camera toward a nearby opponent.
const MOBILE_LOOK_SENSITIVITY: float = 0.006
const AIM_ASSIST_RANGE: float = 12.0
const AIM_ASSIST_CONE_DEG: float = 20.0 # they have to be roughly in your sights already
const AIM_ASSIST_STRENGTH: float = 1.2 # (fades to nothing at the edge of the cone)
const AIM_ASSIST_MAX_TURN: float = 12.0 # degrees per second, at most
var mobile_controls: bool = false
var mobile_ui: Control = null
var console_panel: Control = null
var mobile_move: Vector2 = Vector2.ZERO
var mobile_jump_held: bool = false
var mobile_e_held: bool = false
var mobile_q_held: bool = false
var mobile_sprint_on: bool = false
# Dead players can fly (look where you want to go, hold W; Shift = faster).
const GHOST_FLY_MAX_HEIGHT: float = 60.0
const GHOST_FAST_MULT: float = 2.0 # Shift while flying: 2x sprint speed (28)
const GHOSTS_FLY_IN_FFA: bool = true
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
var ranks_canvas: CanvasLayer = null
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
# Where each rank icon sits on rank_icons.png (7 columns = ranks, 3 rows =
# tiers 1-3), as fractions of the sheet's size: the top-left corner of a crop
# that is the same size for every icon and centered on the icon, so all ranks
# line up and none of the text above / below an icon is shown.
const RANK_ICON_CROPS: Array = [
	Vector2(0.02051, 0.20015), Vector2(0.02051, 0.42302), Vector2(0.02051, 0.65543),
	Vector2(0.16162, 0.20381), Vector2(0.16064, 0.42522), Vector2(0.16016, 0.65762),
	Vector2(0.30371, 0.20161), Vector2(0.30322, 0.42375), Vector2(0.30322, 0.65543),
	Vector2(0.44531, 0.20381), Vector2(0.44482, 0.42669), Vector2(0.44434, 0.65836),
	Vector2(0.59033, 0.20601), Vector2(0.59033, 0.42815), Vector2(0.59082, 0.66129),
	Vector2(0.73340, 0.20674), Vector2(0.73340, 0.43035), Vector2(0.73340, 0.66496),
	Vector2(0.87109, 0.20161), Vector2(0.87109, 0.42522), Vector2(0.87012, 0.65762),
]
const RANK_ICON_CROP_SIZE: Vector2 = Vector2(0.11328, 0.15836)
const RANK_COUNT: int = 21
const RANK_FAMILY_COLORS: Array = [Color(0.86, 0.78, 0.68), Color(0.45, 0.85, 0.42), Color(1.0, 0.58, 0.22), Color(0.4, 0.65, 1.0), Color(0.7, 0.5, 1.0), Color(0.95, 0.95, 0.95), Color(0.5, 0.82, 1.0)]
var rank_tex_cache: Dictionary = {}
var rank_panel_w: float = 240.0
var rank_panel_box: VBoxContainer = null

# --- JAVASCRIPT CALLBACK REFERENCES ---
var js_on_peer_join_cb: JavaScriptObject
var js_on_peer_leave_cb: JavaScriptObject
var js_on_data_receive_cb: JavaScriptObject

func _ready() -> void :
	_load_player_data()
	_load_leaderboard_cache()
	_init_sprite_sheet()
	_init_trystero_bridge()
	_init_admin_console()
	_init_view_key_guard()
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	_build_main_menu()

func _input(event: InputEvent) -> void :
	if _osk_visible():
		_osk_input(event)

func _process(delta: float) -> void :
	_net_tick()
	_osk_tick(delta)

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
		_on_leave_requested()
	if _event is InputEventKey and _event.pressed and not _event.echo and _event.keycode == KEY_F5:
		if is_match_active and get_local_player():
			toggle_view()
			get_viewport().set_input_as_handled()

# Esc on PC, the LEAVE button on mobile.
func _on_leave_requested() -> void :
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_match_active and not is_game_over:
		# In 2v2/3v3/FFA leaving hurts and is easy to do by accident (browsers
		# use Esc to release the mouse), and on mobile a stray tap is even
		# easier - so those take two presses.
		var ranked_team = (team_size > 1 or is_ffa) and not is_single_player
		if (ranked_team or mobile_controls) and _now_ms() - leave_confirm_ms > LEAVE_CONFIRM_MS:
			leave_confirm_ms = _now_ms()
			var what = "Tap LEAVE" if mobile_controls else "Press Esc"
			var cost = "" if is_single_player else " (counts as a loss)"
			if leave_confirm_label:
				leave_confirm_label.text = what + " again to leave the match" + cost
				leave_confirm_label.visible = true
			log_console("[Match] " + what + " again within 3s to leave the match" + cost + ".")
			return
		_forfeit_match()
	else:
		_return_to_main_menu()



# --- DIRECT CONNECT (join codes - for Wi-Fi that blocks the relay servers) ---
# Players swap codes that carry their computer's connection details (WebRTC)
# and get a direct link, with no relay or signalling server in between. The
# links work as a second transport next to Trystero (same rooms, same
# packets), so a group linked this way can queue and play like normal - in
# its own private lobby. The browser side is HX_JS.
# Swapping: A sends B a join code; B enters it and gets a reply code; A enters
# that and they're linked (a browser needs both sides' details). Everyone A
# links with gets linked with each other automatically.
var js_on_direct_cb: JavaScriptObject
var dc_canvas: CanvasLayer = null
var dc_open: bool = false
var dc_my_code: String = ""
var dc_my_tok: int = -1
var dc_making: bool = false
var dc_entries: Array = [] # {kind: "answer"/"offer", id, code, state, nick, num}
var dc_entry_seq: int = 0
var dc_group: Array = [] # [{id, n, d, me}] from the browser side
var dc_status_text: String = ""
var dc_status_bad: bool = false
var dc_lobby: String = "" # queueing with the group: its private lobby room
var dc_n: int = 0 # ...and how many of us there are
var dc_queue_ms: int = 0
var dc_sig: String = ""
var dc_inner_w: float = 500.0
var dc_code_label: Label = null
var dc_input: LineEdit = null
var dc_status_label: Label = null
var dc_dyn_box: VBoxContainer = null
var dc_party_label: Label = null
var dc_paste_to_input: bool = false
const DC_MODES: Array = [["1v1", "1v1", "2 players"], ["2v2", "2v2", "4 players"], ["3v3", "3v3", "6 players"], ["ffa", "Free For All", "3-5 players"], ["royale", "Huss Royale", "2-15 + bots"]]

# ---- the browser side (overridden by the tests) ----
func _hx_obj():
	if not OS.has_feature("web"):
		return null
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		return null
	return window.hx

func _hx_available() -> bool:
	return _hx_obj() != null

func _hx_set_room(code: String) -> void:
	var hx = _hx_obj()
	if hx:
		hx.setRoom(code)

func _hx_make_code() -> void:
	var hx = _hx_obj()
	if hx:
		hx.makeCode(local_nickname)

func _hx_enter_code(text: String) -> void:
	var hx = _hx_obj()
	if hx:
		hx.enterCode(text, local_nickname)

func _hx_ctl(d: Dictionary) -> void:
	var hx = _hx_obj()
	if hx:
		hx.ctl(JSON.stringify(d))

func _hx_group() -> Array:
	var hx = _hx_obj()
	if hx == null:
		return []
	var s = hx.groupJson()
	if typeof(s) != TYPE_STRING:
		return []
	var j = JSON.parse_string(s)
	return j if j is Array else []

func _hx_copy(text: String) -> void:
	var hx = _hx_obj()
	if hx:
		hx.copyText(text)

func _hx_arm_paste() -> bool:
	var hx = _hx_obj()
	if hx:
		hx.armPaste()
		return true
	return false

func _hx_reset() -> void:
	var hx = _hx_obj()
	if hx:
		hx.reset()

func _hx_set_nick(nick: String) -> void:
	var hx = _hx_obj()
	if hx:
		hx.setNick(nick)

# ---- events from the browser side ----
func _on_hx_event(args: Array) -> void:
	if args.is_empty():
		return
	var d = JSON.parse_string(String(args[0]))
	if d is Dictionary:
		_dc_event(d)

func _dc_entry(kind: String, id: String) -> Dictionary:
	for en in dc_entries:
		if String(en["kind"]) == kind and String(en["id"]) == id:
			return en
	dc_entry_seq += 1
	var made = {"kind": kind, "id": id, "code": "", "state": "making", "nick": "", "num": dc_entry_seq}
	dc_entries.append(made)
	return made

func _dc_status(text: String, bad: bool) -> void:
	dc_status_text = text
	dc_status_bad = bad

func _dc_event(d: Dictionary) -> void:
	match String(d.get("e", "")):
		"code":
			dc_my_code = String(d.get("code", ""))
			dc_my_tok = int(d.get("tok", -1))
			dc_making = false
		"used":
			# A friend's reply used up our code: make a fresh one for anyone else.
			if int(d.get("tok", -1)) == dc_my_tok:
				dc_my_code = ""
				dc_my_tok = -1
				_dc_make_code()
		"reply":
			var ea = _dc_entry("answer", String(d.get("key", "")))
			ea["code"] = String(d.get("code", ""))
			if String(ea["state"]) != "connected":
				ea["state"] = "waiting"
			if dc_input and is_instance_valid(dc_input):
				dc_input.text = ""
			_dc_status("Got it! Now send your friend the reply code below.", false)
		"applied":
			var eo = _dc_entry("offer", str(int(d.get("tok", -1))))
			if String(eo["state"]) != "connected":
				eo["state"] = "connecting"
			if dc_input and is_instance_valid(dc_input):
				dc_input.text = ""
			_dc_status("Reply code accepted - connecting...", false)
		"state":
			var sk = String(d.get("kind", ""))
			if sk == "answer" or sk == "offer":
				var es = _dc_entry(sk, String(d.get("key", "")) if sk == "answer" else str(int(d.get("tok", -1))))
				if String(es["state"]) != "connected" or String(d.get("s", "")) == "failed":
					es["state"] = String(d.get("s", es["state"]))
				if String(d.get("n", "")) != "":
					es["nick"] = String(d.get("n", ""))
				if String(es["state"]) == "failed":
					_dc_status("A connection didn't go through. Swap new codes and try again (you both need to be in the game while you do).", true)
		"link":
			var nick = String(d.get("n", "Player"))
			var lk = String(d.get("kind", ""))
			if lk == "answer" or lk == "offer":
				var el = _dc_entry(lk, String(d.get("key", "")) if lk == "answer" else str(int(d.get("tok", -1))))
				el["state"] = "connected"
				el["nick"] = nick
				_dc_status("Connected with " + nick + "!", false)
			log_console("[Direct] Connected with " + nick + ".")
			dc_group = _hx_group()
		"unlink":
			log_console("[Direct] Lost the connection to " + String(d.get("n", "a player")) + ".")
			dc_group = _hx_group()
		"group":
			dc_group = _hx_group()
		"ctl":
			var j = d.get("j", {})
			if j is Dictionary:
				_dc_on_ctl(String(d.get("from", "")), j)
		"err":
			_dc_status(String(d.get("m", "Something went wrong.")), true)
		"copied":
			_dc_status("Copied! Now paste it to your friend.", false)
		"copyfail":
			_dc_status("Couldn't copy it automatically - select the code and copy it by hand.", true)
		"paste":
			_dc_pasted(String(d.get("t", "")))
	_dc_refresh()

# ---- the panel ----
func _open_direct_panel() -> void:
	_save_nickname_from_input()
	dc_open = true
	_hx_set_nick(local_nickname)
	if dc_my_code == "" and not dc_making:
		_dc_make_code()
	dc_group = _hx_group()
	_build_direct_panel()

func _close_direct_panel() -> void:
	dc_open = false
	if osk_target and is_instance_valid(osk_target) and osk_target == dc_input:
		_osk_hide()
	_free_direct_panel()

func _free_direct_panel() -> void:
	if dc_canvas and is_instance_valid(dc_canvas):
		dc_canvas.queue_free()
	dc_canvas = null
	dc_code_label = null
	dc_input = null
	dc_status_label = null
	dc_dyn_box = null

func _dc_make_code() -> void:
	if not _hx_available():
		dc_making = false
		_dc_status("Join codes only work in the browser version of the game.", true)
		return
	dc_making = true
	_hx_set_nick(local_nickname)
	_hx_make_code()

func _dc_new_code() -> void:
	dc_my_code = ""
	dc_my_tok = -1
	_dc_make_code()
	_dc_refresh()

func _dc_label(text: String, size: int, color: Color, width: float) -> Label:
	var l = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _build_direct_panel() -> void:
	_free_direct_panel()
	var vp = get_viewport().get_visible_rect().size
	dc_canvas = CanvasLayer.new()
	dc_canvas.layer = 40
	add_child(dc_canvas)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dc_canvas.add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dc_canvas.add_child(center)
	var w = min(600.0, vp.x - 16.0)
	var h = min(vp.y - 16.0, 720.0)
	dc_inner_w = w - 44.0
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, 0)
	var psb = StyleBoxFlat.new()
	psb.bg_color = Color(0.1, 0.11, 0.14, 0.98)
	psb.border_color = Color(1.0, 0.9, 0.2, 0.45)
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	psb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(w - 16.0, h - 16.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 7)
	scroll.add_child(box)
	var yellow = Color(1.0, 0.9, 0.2)
	var grey = Color(0.78, 0.78, 0.8)

	var head = HBoxContainer.new()
	box.add_child(head)
	var title = Label.new()
	title.text = "DIRECT CONNECT"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", yellow)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_b = Button.new()
	close_b.text = "Close"
	close_b.custom_minimum_size = Vector2(80, 34)
	close_b.pressed.connect(_close_direct_panel)
	head.add_child(close_b)
	box.add_child(_dc_label("Wi-Fi blocking the relay servers? Swap codes with your friends and your games connect straight to each other.", 12, grey, dc_inner_w))
	box.add_child(HSeparator.new())

	box.add_child(_dc_label("1. YOUR JOIN CODE", 15, yellow, dc_inner_w))
	dc_code_label = _dc_label("", 15, Color(0.45, 0.9, 1.0), dc_inner_w)
	box.add_child(dc_code_label)
	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	box.add_child(row1)
	var copy_b = Button.new()
	copy_b.text = "Copy code"
	copy_b.custom_minimum_size = Vector2(130, 36)
	copy_b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS # (copying needs the tap that's still going on)
	copy_b.pressed.connect(func(): _dc_copy(dc_my_code))
	row1.add_child(copy_b)
	var new_b = Button.new()
	new_b.text = "New code"
	new_b.custom_minimum_size = Vector2(110, 36)
	new_b.pressed.connect(_dc_new_code)
	row1.add_child(new_b)
	box.add_child(_dc_label("Send it to a friend. When they enter it, their game gives them a reply code - they send that back to you, and you enter it in step 2.", 12, grey, dc_inner_w))
	box.add_child(HSeparator.new())

	box.add_child(_dc_label("2. ENTER A CODE", 15, yellow, dc_inner_w))
	box.add_child(_dc_label("A friend's join code (you'll get a reply code to send back), or the reply code a friend sent you.", 12, grey, dc_inner_w))
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	box.add_child(row2)
	dc_input = LineEdit.new()
	dc_input.placeholder_text = "Paste a code here (HX-...)"
	dc_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dc_input.custom_minimum_size = Vector2(120, 36)
	dc_input.set_meta("osk_upper", true)
	dc_input.text_submitted.connect(func(_t): _dc_submit())
	_osk_prep(dc_input)
	row2.add_child(dc_input)
	var paste_b = Button.new()
	paste_b.text = "Paste"
	paste_b.custom_minimum_size = Vector2(70, 36)
	paste_b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	paste_b.pressed.connect(_dc_paste_pressed)
	row2.add_child(paste_b)
	var enter_b = Button.new()
	enter_b.text = "Enter"
	enter_b.custom_minimum_size = Vector2(70, 36)
	enter_b.pressed.connect(_dc_submit)
	row2.add_child(enter_b)
	dc_status_label = _dc_label("", 13, Color(0.6, 1.0, 0.7), dc_inner_w)
	box.add_child(dc_status_label)
	dc_dyn_box = VBoxContainer.new()
	dc_dyn_box.add_theme_constant_override("separation", 6)
	box.add_child(dc_dyn_box)
	dc_sig = ""
	_dc_refresh()

func _dc_refresh() -> void:
	var n = max(dc_group.size(), 1)
	if dc_party_label and is_instance_valid(dc_party_label):
		dc_party_label.visible = n > 1
		dc_party_label.text = "Direct group: " + str(n) + " players connected"
	if not dc_canvas or not is_instance_valid(dc_canvas):
		return
	if dc_code_label:
		if dc_my_code != "":
			dc_code_label.text = dc_my_code
		elif dc_making:
			dc_code_label.text = "Making your code..."
		else:
			dc_code_label.text = "Press New code to make one."
	if dc_status_label:
		dc_status_label.text = dc_status_text
		dc_status_label.visible = dc_status_text != ""
		dc_status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4) if dc_status_bad else Color(0.6, 1.0, 0.7))
	if not dc_dyn_box:
		return
	var sig = str([dc_entries, dc_group, mm_phase])
	if sig == dc_sig and dc_dyn_box.get_child_count() > 0:
		return
	dc_sig = sig
	for c in dc_dyn_box.get_children():
		c.queue_free()
	var yellow = Color(1.0, 0.9, 0.2)
	var grey = Color(0.78, 0.78, 0.8)
	var green = Color(0.6, 1.0, 0.7)
	var red = Color(1.0, 0.55, 0.4)

	var shown: Array = []
	for en in dc_entries:
		if String(en["state"]) != "replaced":
			shown.append(en)
	if not shown.is_empty():
		dc_dyn_box.add_child(_dc_label("CONNECTIONS", 13, yellow, dc_inner_w))
	for en in shown:
		var who = String(en["nick"]) if String(en["nick"]) != "" else "Friend #" + str(int(en["num"]))
		var st = String(en["state"])
		if st == "connected":
			dc_dyn_box.add_child(_dc_label("Connected with " + who, 13, green, dc_inner_w))
		elif st == "failed":
			dc_dyn_box.add_child(_dc_label(who + ": didn't connect - swap new codes and try again.", 13, red, dc_inner_w))
		elif String(en["kind"]) == "answer":
			if String(en["code"]) == "":
				dc_dyn_box.add_child(_dc_label(who + ": making your reply code...", 13, grey, dc_inner_w))
			else:
				dc_dyn_box.add_child(_dc_label(who + ": send them this reply code -", 13, Color(1, 1, 1), dc_inner_w))
				dc_dyn_box.add_child(_dc_label(String(en["code"]), 14, Color(0.45, 0.9, 1.0), dc_inner_w))
				var cb = Button.new()
				cb.text = "Copy reply code"
				cb.custom_minimum_size = Vector2(160, 34)
				cb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				cb.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
				var rc = String(en["code"])
				cb.pressed.connect(func(): _dc_copy(rc))
				dc_dyn_box.add_child(cb)
				dc_dyn_box.add_child(_dc_label("(waiting for them to enter it...)", 11, grey, dc_inner_w))
		else:
			dc_dyn_box.add_child(_dc_label("Connecting to your friend...", 13, grey, dc_inner_w))

	dc_dyn_box.add_child(HSeparator.new())
	dc_dyn_box.add_child(_dc_label("3. PLAY TOGETHER", 15, yellow, dc_inner_w))
	if dc_group.size() <= 1:
		dc_dyn_box.add_child(_dc_label("Nobody's connected yet. Swap codes above - for 2v2 and up, swap with each player (or let one player collect everyone's codes).", 12, grey, dc_inner_w))
		return
	var names: Array = []
	for g in dc_group:
		if bool(g.get("me", false)):
			names.push_front("You")
		else:
			names.append(String(g.get("n", "Player")))
	dc_dyn_box.add_child(_dc_label("Your group (" + str(dc_group.size()) + "): " + ", ".join(PackedStringArray(names)), 14, green, dc_inner_w))
	dc_dyn_box.add_child(_dc_label("Pick a mode - everyone in the group queues together into a private match:", 12, grey, dc_inner_w))
	var grid = GridContainer.new()
	grid.columns = 3 if dc_inner_w >= 430.0 else 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	dc_dyn_box.add_child(grid)
	for m in DC_MODES:
		var b = Button.new()
		b.text = String(m[1]) + "\n(" + String(m[2]) + ")"
		b.custom_minimum_size = Vector2(min(170.0, (dc_inner_w - 12.0) / grid.columns), 52)
		b.disabled = not _dc_mode_fits(String(m[0]), dc_group.size()) or mm_phase != "menu"
		b.pressed.connect(_dc_queue.bind(String(m[0])))
		grid.add_child(b)
	var leave_b = Button.new()
	leave_b.text = "Leave group"
	leave_b.custom_minimum_size = Vector2(130, 32)
	leave_b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	leave_b.pressed.connect(_dc_leave_group)
	dc_dyn_box.add_child(leave_b)

func _dc_mode_fits(mode: String, n: int) -> bool:
	match mode:
		"1v1":
			return n == 2
		"2v2":
			return n == 4
		"3v3":
			return n == 6
		"ffa":
			return n >= 3 and n <= 5
		"royale":
			return n >= 2 and n <= 15
	return false

func _dc_submit() -> void:
	var t = dc_input.text.strip_edges() if dc_input and is_instance_valid(dc_input) else ""
	if t == "":
		_dc_status("Paste (or type) a code first.", true)
		_dc_refresh()
		return
	if not _hx_available():
		_dc_status("Join codes only work in the browser version of the game.", true)
		_dc_refresh()
		return
	_dc_status("Checking the code...", false)
	_hx_set_nick(local_nickname)
	_hx_enter_code(t)
	_dc_refresh()

func _dc_copy(text: String) -> void:
	if text == "":
		return
	DisplayServer.clipboard_set(text)
	_hx_copy(text)
	_dc_status("Copied! Now paste it to your friend." if not OS.has_feature("web") else "Copying...", false)
	_dc_refresh()

func _dc_paste_pressed() -> void:
	if _hx_arm_paste():
		dc_paste_to_input = true
		return
	var t = DisplayServer.clipboard_get().strip_edges()
	if t != "" and dc_input and is_instance_valid(dc_input):
		dc_input.text = t
		_dc_submit()

func _dc_pasted(t: String) -> void:
	var clean = t.strip_edges().replace("\r", " ").replace("\n", " ")
	if clean == "":
		return
	if osk_target and is_instance_valid(osk_target) and osk_canvas and osk_canvas.visible:
		_osk_paste_text(clean)
	elif dc_paste_to_input and dc_input and is_instance_valid(dc_input):
		dc_input.text = clean
		_dc_submit()
	dc_paste_to_input = false

func _dc_leave_group() -> void:
	_hx_reset()
	dc_entries.clear()
	dc_group = _hx_group()
	_dc_status("You left the group.", false)
	_dc_refresh()

# ---- queueing together ----
func _dc_queue(mode: String) -> void:
	var n = dc_group.size()
	if mm_phase != "menu" or not _dc_mode_fits(mode, n):
		return
	var me = _get_self_trystero_id()
	if me == "":
		return
	var ids: Array = []
	for g in dc_group:
		ids.append(String(g.get("id", "")))
	var lobby = "direct_" + mode + "_" + me.substr(0, 8) + "_" + str(randi() % 1000000)
	_hx_ctl({"a": "dq", "mode": mode, "lobby": lobby, "n": n, "ids": ids, "by": local_nickname})
	log_console("[Direct] Queueing your group of " + str(n) + " for " + String(GAME_MODES[mode]["label"]) + "...")
	_dc_start_queue(mode, lobby, n)

func _dc_on_ctl(from: String, j: Dictionary) -> void:
	var me = _get_self_trystero_id()
	match String(j.get("a", "")):
		"dq":
			var ids = j.get("ids", [])
			if me == "" or not (ids is Array) or not ids.has(me):
				return
			var mode = String(j.get("mode", ""))
			var lobby = String(j.get("lobby", ""))
			if not GAME_MODES.has(mode) or lobby == "":
				return
			var by = String(j.get("by", "Someone"))
			var label = String(GAME_MODES[mode]["label"])
			if mm_phase != "menu" or is_match_active or is_single_player:
				_hx_ctl({"a": "dq_busy", "to": from, "by": local_nickname})
				log_console("[Direct] " + by + " queued your group for " + label + ", but you're not on the menu - go back to it to play with them.")
				return
			log_console("[Direct] " + by + " picked " + label + " - queueing with your group!")
			_dc_start_queue(mode, lobby, clampi(int(j.get("n", 2)), 2, 15))
		"dq_busy":
			if String(j.get("to", "")) == me:
				log_console("[Direct] " + String(j.get("by", "Someone")) + " isn't on the menu, so they can't join this queue yet.")

func _dc_start_queue(mode: String, lobby: String, n: int) -> void:
	dc_lobby = lobby
	dc_n = n
	dc_queue_ms = _now_ms()
	dc_open = false
	_osk_hide()
	_free_direct_panel()
	_on_find_match_pressed(mode, true)


# --- ON-SCREEN KEYBOARD (mobile controls) ---
# Tapping any text box (nickname, party code, join codes...) brings it up;
# tapping anywhere else closes it. The strip on top shows what you're typing,
# in case the box itself is hidden behind the keyboard.
var osk_canvas: CanvasLayer = null
var osk_panel: PanelContainer = null
var osk_target: LineEdit = null
var osk_preview: Label = null
var osk_shift: bool = false
var osk_letter_buttons: Array = []
var osk_shift_button: Button = null
var osk_bs_held: bool = false
var osk_bs_t: float = 0.0
var osk_vp_size: Vector2 = Vector2.ZERO
var osk_font: int = 16
var osk_shown_ms: int = -100000
const OSK_ROWS: Array = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]

# Text boxes use our keyboard on mobile, not the browser's.
func _osk_prep(le: LineEdit) -> void:
	if le:
		le.virtual_keyboard_enabled = not mobile_controls

func _on_gui_focus_changed(c: Control) -> void:
	if not mobile_controls:
		return
	if c is LineEdit and c.editable and c.is_visible_in_tree():
		_osk_show(c)

func _osk_visible() -> bool:
	return osk_canvas != null and is_instance_valid(osk_canvas) and osk_canvas.visible

func _osk_build() -> void:
	var vp = get_viewport().get_visible_rect().size
	osk_vp_size = vp
	if osk_canvas and is_instance_valid(osk_canvas):
		osk_canvas.queue_free()
	osk_canvas = CanvasLayer.new()
	osk_canvas.layer = 120
	osk_canvas.visible = false
	add_child(osk_canvas)
	var kh = clamp(vp.y * 0.085, 30.0, 54.0)
	osk_font = int(clamp(kh * 0.46, 13.0, 24.0))
	osk_panel = PanelContainer.new()
	osk_panel.anchor_left = 0.0
	osk_panel.anchor_right = 1.0
	osk_panel.anchor_top = 1.0
	osk_panel.anchor_bottom = 1.0
	osk_panel.offset_left = 0.0
	osk_panel.offset_right = 0.0
	osk_panel.offset_top = -(kh * 5.0 + kh * 0.9 + 40.0)
	osk_panel.offset_bottom = 0.0
	osk_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	sb.border_color = Color(1.0, 0.9, 0.2, 0.5)
	sb.border_width_top = 2
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 5
	sb.content_margin_bottom = 6
	osk_panel.add_theme_stylebox_override("panel", sb)
	osk_canvas.add_child(osk_panel)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	osk_panel.add_child(col)
	osk_preview = Label.new()
	osk_preview.custom_minimum_size = Vector2(0, kh * 0.9)
	osk_preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	osk_preview.clip_text = true
	osk_preview.add_theme_font_size_override("font_size", osk_font)
	osk_preview.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	col.add_child(osk_preview)
	osk_letter_buttons.clear()
	for r in range(OSK_ROWS.size()):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.custom_minimum_size = Vector2(0, kh)
		col.add_child(row)
		if r == 2:
			_osk_spacer(row, 0.5)
		if r == 3:
			osk_shift_button = _osk_key(row, "SHIFT", int(osk_font * 0.8), 1.5, _osk_toggle_shift)
		for ch in String(OSK_ROWS[r]):
			var b = _osk_key(row, ch, osk_font, 1.0, _osk_type.bind(ch))
			if ch >= "a" and ch <= "z":
				osk_letter_buttons.append(b)
		if r == 2:
			_osk_spacer(row, 0.5)
		if r == 3:
			var bs = _osk_key(row, "DEL", int(osk_font * 0.8), 1.5, Callable())
			bs.button_down.connect(_osk_bs_down)
			bs.button_up.connect(_osk_bs_up)
	var last = HBoxContainer.new()
	last.add_theme_constant_override("separation", 4)
	last.custom_minimum_size = Vector2(0, kh)
	col.add_child(last)
	var paste = _osk_key(last, "PASTE", int(osk_font * 0.8), 1.6, _osk_paste)
	paste.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS # (reading the clipboard needs the tap that's still going on)
	_osk_key(last, "-", osk_font, 1.0, _osk_type.bind("-"))
	_osk_key(last, "_", osk_font, 1.0, _osk_type.bind("_"))
	_osk_key(last, "SPACE", int(osk_font * 0.8), 3.6, _osk_type.bind(" "))
	_osk_key(last, ".", osk_font, 1.0, _osk_type.bind("."))
	var done = _osk_key(last, "DONE", int(osk_font * 0.8), 1.8, _osk_done)
	done.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))

func _osk_spacer(row: HBoxContainer, ratio: float) -> void:
	var s = Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_stretch_ratio = ratio
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(s)

func _osk_key(row: HBoxContainer, text: String, fs: int, ratio: float, cb: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE # (the text box keeps the focus)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = ratio
	b.custom_minimum_size = Vector2(8, 0)
	b.clip_text = true
	b.add_theme_font_size_override("font_size", fs)
	if cb.is_valid():
		b.pressed.connect(cb)
	row.add_child(b)
	return b

func _osk_show(le: LineEdit) -> void:
	if not osk_canvas or not is_instance_valid(osk_canvas) or get_viewport().get_visible_rect().size != osk_vp_size:
		_osk_build()
	osk_target = le
	le.virtual_keyboard_enabled = false
	DisplayServer.virtual_keyboard_hide()
	osk_shift = false
	osk_bs_held = false
	osk_canvas.visible = true
	osk_shown_ms = Time.get_ticks_msec()
	_osk_relabel()
	_osk_refresh()

func _osk_hide(release: bool = true) -> void:
	osk_bs_held = false
	if osk_canvas and is_instance_valid(osk_canvas):
		osk_canvas.visible = false
	var t = osk_target
	osk_target = null
	if release and t and is_instance_valid(t) and t.has_focus():
		t.release_focus()

# Any tap outside the keyboard closes it (and still does whatever it tapped).
func _osk_input(event: InputEvent) -> void:
	var pos = null
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	if pos == null or not osk_panel or not is_instance_valid(osk_panel):
		return
	if osk_panel.get_global_rect().has_point(pos):
		return
	# A tap on the box you're typing in just moves the cursor. (Browsers send
	# every tap twice - as a touch and as a click - so this also keeps the
	# second half of the tap that opened the keyboard from closing it.)
	if osk_target and is_instance_valid(osk_target) and osk_target.get_global_rect().has_point(pos):
		return
	if Time.get_ticks_msec() - osk_shown_ms < 250:
		return
	_osk_hide()

func _osk_tick(delta: float) -> void:
	if not _osk_visible():
		return
	if not osk_target or not is_instance_valid(osk_target) or not osk_target.is_visible_in_tree():
		_osk_hide(false)
		return
	if osk_bs_held:
		osk_bs_t += delta
		if osk_bs_t > 0.45:
			osk_bs_t -= 0.06
			_osk_backspace()
	_osk_refresh()

func _osk_upper() -> bool:
	var base_up = osk_target != null and is_instance_valid(osk_target) and osk_target.has_meta("osk_upper")
	return base_up != osk_shift

func _osk_relabel() -> void:
	var up = _osk_upper()
	for b in osk_letter_buttons:
		if is_instance_valid(b):
			b.text = b.text.to_upper() if up else b.text.to_lower()
	if osk_shift_button and is_instance_valid(osk_shift_button):
		osk_shift_button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2) if osk_shift else Color(1, 1, 1))

func _osk_refresh() -> void:
	if not osk_preview or not osk_target or not is_instance_valid(osk_target):
		return
	var t = osk_target.text
	var shown = ""
	if t == "":
		shown = "|   " + osk_target.placeholder_text
	else:
		var c = clampi(osk_target.caret_column, 0, t.length())
		shown = t.substr(0, c) + "|" + t.substr(c)
		var maxc = int(osk_vp_size.x / (osk_font * 0.62))
		if shown.length() > maxc and maxc > 10:
			var start = clampi(c + 8 - maxc, 0, shown.length() - maxc)
			shown = ("..." if start > 0 else "") + shown.substr(start + (3 if start > 0 else 0), maxc - (3 if start > 0 else 0))
	if osk_preview.text != shown:
		osk_preview.text = shown

func _osk_insert(s: String) -> void:
	var le = osk_target
	if not le or not is_instance_valid(le):
		return
	var t = le.text
	var c = clampi(le.caret_column, 0, t.length())
	if le.max_length > 0:
		var room = le.max_length - t.length()
		if room <= 0:
			return
		s = s.substr(0, room)
	le.text = t.substr(0, c) + s + t.substr(c)
	le.caret_column = c + s.length()
	le.text_changed.emit(le.text)
	_osk_refresh()

func _osk_type(ch: String) -> void:
	_osk_insert(ch.to_upper() if _osk_upper() else ch)
	if osk_shift:
		osk_shift = false
		_osk_relabel()

func _osk_toggle_shift() -> void:
	osk_shift = not osk_shift
	_osk_relabel()

func _osk_backspace() -> void:
	var le = osk_target
	if not le or not is_instance_valid(le):
		return
	var c = clampi(le.caret_column, 0, le.text.length())
	if c <= 0:
		return
	le.text = le.text.substr(0, c - 1) + le.text.substr(c)
	le.caret_column = c - 1
	le.text_changed.emit(le.text)
	_osk_refresh()

func _osk_bs_down() -> void:
	osk_bs_held = true
	osk_bs_t = 0.0
	_osk_backspace()

func _osk_bs_up() -> void:
	osk_bs_held = false

func _osk_done() -> void:
	var le = osk_target
	_osk_hide()
	if le and is_instance_valid(le):
		le.text_submitted.emit(le.text)

func _osk_paste() -> void:
	if _hx_arm_paste():
		return # (the browser hands it over when the tap ends)
	_osk_paste_text(DisplayServer.clipboard_get())

func _osk_paste_text(t: String) -> void:
	var clean = t.strip_edges().replace("\r", " ").replace("\n", " ")
	if clean == "" or not osk_target or not is_instance_valid(osk_target):
		return
	if osk_target == dc_input:
		# A pasted code goes straight in.
		dc_input.text = clean
		_osk_hide()
		_dc_submit()
		return
	_osk_insert(clean)

# The browser side of direct connect (see DIRECT CONNECT above). It has no
# backslashes in it, so it can live in this string as-is.
const HX_JS: String = """(function () {
	// Direct connect: players swap join/reply codes (their WebRTC details) and
	// get a data channel without any relay/signalling server. The links act as
	// a second transport next to Trystero: same rooms, same packets.
	if (window.hx) { return; }
	var hx = {};
	window.hx = hx;
	var NL = String.fromCharCode(10);
	var CRLF = String.fromCharCode(13, 10);
	var ICE_SERVERS = [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] }, { urls: ['stun:stun.cloudflare.com:3478'] }];
	var GATHER_MS = 2500;
	hx.room = null;
	hx.nick = 'Player';
	hx.links = {};   // remote id -> conn (open + said hi)
	hx.pend = {};    // my join codes: tok -> conn
	hx.ans = {};     // join codes I entered: key -> conn
	hx.mesh = {};    // automatic links to the rest of the group: sid -> conn
	hx.meshTried = {};
	hx.tP = {};      // present in the current room through Trystero
	hx.dP = {};      // present in the current room through a direct link
	hx.graph = {};   // origin -> {t, l, n, msg} (who each player is linked to)
	hx.seen = {};
	hx.q = 0;
	hx.fixedId = null;
	hx.myTok = -1;
	hx.pendingCopy = null;
	hx.pendingPaste = false;

	function now() { return Date.now(); }
	function rid(n) {
		var a = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
		var r = new Uint8Array(n);
		crypto.getRandomValues(r);
		var s = '';
		for (var i = 0; i < n; i++) { s += a.charAt(r[i] % a.length); }
		return s;
	}
	function emit(o) {
		setTimeout(function () {
			try { if (typeof window._godot_on_direct === 'function' || window._godot_on_direct) { window._godot_on_direct(JSON.stringify(o)); } } catch (e) { console.error('[Direct]', e); }
		}, 0);
	}
	function log(m) { try { console.log('[Direct] ' + m); } catch (e) {} }

	hx.selfId = function () {
		if (!hx.fixedId) {
			var t = window.trysteroSelfId;
			if (typeof t === 'string' && t.length > 0) {
				hx.fixedId = t;
			} else {
				// Trystero never loaded (blocked?) - use our own id for everything.
				hx.fixedId = rid(20);
				window.trysteroSelfId = hx.fixedId;
			}
		}
		return hx.fixedId;
	};

	// ---------- compact codes ----------
	var B32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
	var ICEC = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
	function b32enc(bytes) {
		var out = '', buf = 0, bits = 0;
		for (var i = 0; i < bytes.length; i++) {
			buf = ((buf << 8) | bytes[i]) & 65535;
			bits += 8;
			while (bits >= 5) { out += B32.charAt((buf >>> (bits - 5)) & 31); bits -= 5; }
			buf &= (1 << bits) - 1;
		}
		if (bits > 0) { out += B32.charAt((buf << (5 - bits)) & 31); }
		return out;
	}
	function b32dec(str) {
		var out = [], buf = 0, bits = 0;
		for (var i = 0; i < str.length; i++) {
			var v = B32.indexOf(str.charAt(i));
			if (v < 0) { return null; }
			buf = ((buf << 5) | v) & 65535;
			bits += 5;
			if (bits >= 8) { out.push((buf >>> (bits - 8)) & 255); bits -= 8; buf &= (1 << bits) - 1; }
		}
		return out;
	}
	function cleanCode(text) {
		var s = String(text || '').toUpperCase();
		var out = '';
		for (var i = 0; i < s.length; i++) {
			var c = s.charAt(i);
			if (c === 'O') { c = '0'; } else if (c === 'I' || c === 'L') { c = '1'; }
			if (B32.indexOf(c) >= 0) { out += c; }
		}
		return out;
	}
	function crc16(b, n) {
		var c = 65535;
		for (var i = 0; i < n; i++) {
			c ^= (b[i] << 8);
			for (var k = 0; k < 8; k++) { c = (c & 32768) ? (((c << 1) ^ 4129) & 65535) : ((c << 1) & 65535); }
		}
		return c;
	}
	function W() { this.b = []; }
	W.prototype.u8 = function (v) { this.b.push(v & 255); };
	W.prototype.u16 = function (v) { this.u8(v >> 8); this.u8(v); };
	W.prototype.bytes = function (a) { for (var i = 0; i < a.length; i++) { this.u8(a[i]); } };
	function R(b, n) { this.b = b; this.i = 0; this.n = n; }
	R.prototype.u8 = function () { if (this.i >= this.n) { throw new Error('short code'); } return this.b[this.i++]; };
	R.prototype.u16 = function () { var h = this.u8(); return (h << 8) | this.u8(); };
	R.prototype.bytes = function (k) { var o = []; for (var i = 0; i < k; i++) { o.push(this.u8()); } return o; };
	function packIce(w, s) {
		w.u8(s.length);
		var buf = 0, bits = 0;
		for (var i = 0; i < s.length; i++) {
			var v = ICEC.indexOf(s.charAt(i));
			if (v < 0) { throw new Error('odd ICE credentials'); }
			buf = ((buf << 6) | v) & 65535;
			bits += 6;
			while (bits >= 8) { w.u8((buf >>> (bits - 8)) & 255); bits -= 8; buf &= (1 << bits) - 1; }
		}
		if (bits > 0) { w.u8((buf << (8 - bits)) & 255); }
	}
	function unpackIce(r) {
		var n = r.u8();
		var nb = Math.ceil(n * 6 / 8);
		var buf = 0, bits = 0, s = '';
		for (var i = 0; i < nb; i++) {
			buf = ((buf << 8) | r.u8()) & 65535;
			bits += 8;
			while (bits >= 6 && s.length < n) { s += ICEC.charAt((buf >>> (bits - 6)) & 63); bits -= 6; buf &= (1 << bits) - 1; }
		}
		return s;
	}
	function isHex(s) {
		if (s.length === 0) { return false; }
		for (var i = 0; i < s.length; i++) { if ('0123456789abcdefABCDEF'.indexOf(s.charAt(i)) < 0) { return false; } }
		return true;
	}
	function isDigits(s) {
		if (s.length === 0 || s.length > 3) { return false; }
		for (var i = 0; i < s.length; i++) { if ('0123456789'.indexOf(s.charAt(i)) < 0) { return false; } }
		return Number(s) <= 255;
	}
	function parseV6(a) {
		var z = a.indexOf('%');
		if (z >= 0) { a = a.substr(0, z); }
		var halves = a.split('::');
		if (halves.length > 2) { return null; }
		var head = halves[0] ? halves[0].split(':') : [];
		var tail = (halves.length === 2 && halves[1]) ? halves[1].split(':') : [];
		if (halves.length === 1 && head.length !== 8) { return null; }
		var fill = 8 - head.length - tail.length;
		if (fill < 0) { return null; }
		var groups = head.slice();
		if (halves.length === 2) { for (var f = 0; f < fill; f++) { groups.push('0'); } }
		groups = groups.concat(tail);
		if (groups.length !== 8) { return null; }
		var out = [];
		for (var i = 0; i < 8; i++) {
			var g = groups[i];
			if (!isHex(g) || g.length > 4) { return null; }
			var v = parseInt(g, 16);
			out.push(v >> 8, v & 255);
		}
		return out;
	}
	function encAddr(a) {
		var p4 = a.split('.');
		if (p4.length === 4 && p4.every(isDigits)) { return { fam: 0, bytes: p4.map(Number) }; }
		var low = a.toLowerCase();
		if (low.length === 42 && low.substr(36) === '.local') {
			var hex = low.substr(0, 36).split('-').join('');
			if (hex.length === 32 && isHex(hex)) {
				var b = [];
				for (var i = 0; i < 32; i += 2) { b.push(parseInt(hex.substr(i, 2), 16)); }
				return { fam: 2, bytes: b };
			}
		}
		if (a.indexOf(':') >= 0) {
			var v6 = parseV6(a);
			if (v6) { return { fam: 1, bytes: v6 }; }
		}
		return null;
	}
	function hx2(v) { var s = v.toString(16); return s.length < 2 ? '0' + s : s; }
	function decAddr(fam, b) {
		if (fam === 0) { return b.join('.'); }
		if (fam === 1) {
			var g = [];
			for (var i = 0; i < 16; i += 2) { g.push(((b[i] << 8) | b[i + 1]).toString(16)); }
			return g.join(':');
		}
		var h = b.map(hx2).join('');
		return h.substr(0, 8) + '-' + h.substr(8, 4) + '-' + h.substr(12, 4) + '-' + h.substr(16, 4) + '-' + h.substr(20, 12) + '.local';
	}
	function parseCand(s) {
		var p = s.split(' ');
		if (p.length < 8 || p[1] !== '1' || p[2].toLowerCase() !== 'udp' || p[6] !== 'typ') { return null; }
		var type = p[7] === 'host' ? 0 : (p[7] === 'srflx' ? 1 : -1);
		if (type < 0) { return null; }
		var port = parseInt(p[5], 10);
		if (!(port > 0 && port < 65536)) { return null; }
		var ad = encAddr(p[4]);
		if (!ad) { return null; }
		return { type: type, fam: ad.fam, bytes: ad.bytes, port: port, addr: p[4] };
	}
	function parseSdp(sdp) {
		var info = { ufrag: '', pwd: '', fpAlg: 'sha-256', fp: '', setup: 'actpass', mid: '0', cands: [] };
		var lines = String(sdp).split(NL);
		for (var i = 0; i < lines.length; i++) {
			var l = lines[i];
			if (l.charCodeAt(l.length - 1) === 13) { l = l.substr(0, l.length - 1); }
			if (l.indexOf('a=ice-ufrag:') === 0) { if (!info.ufrag) { info.ufrag = l.substr(12); } }
			else if (l.indexOf('a=ice-pwd:') === 0) { if (!info.pwd) { info.pwd = l.substr(10); } }
			else if (l.indexOf('a=fingerprint:') === 0) { var fp = l.substr(14).split(' '); info.fpAlg = fp[0].toLowerCase(); info.fp = fp[1] || ''; }
			else if (l.indexOf('a=setup:') === 0) { info.setup = l.substr(8); }
			else if (l.indexOf('a=mid:') === 0) { info.mid = l.substr(6); }
			else if (l.indexOf('a=candidate:') === 0) { var c = parseCand(l.substr(12)); if (c) { info.cands.push(c); } }
		}
		return info;
	}
	function pickCands(list) {
		var seen = {}, host = [], host6 = [], srf = [], srf6 = [];
		for (var i = 0; i < list.length; i++) {
			var c = list[i];
			var k = c.type + '/' + c.fam + '/' + c.bytes.join('.') + '/' + c.port;
			if (seen[k]) { continue; }
			seen[k] = true;
			if (c.type === 0) { (c.fam === 1 ? host6 : host).push(c); } else { (c.fam === 1 ? srf6 : srf).push(c); }
		}
		return srf.slice(0, 2).concat(host.slice(0, 2), srf6.slice(0, 1), host6.slice(0, 1));
	}
	function encodeInfo(kind, tok, info) {
		var w = new W();
		w.u8(16 | kind);
		w.u16(tok);
		var setup = info.setup === 'active' ? 1 : (info.setup === 'passive' ? 2 : 0);
		var alg = info.fpAlg === 'sha-384' ? 1 : (info.fpAlg === 'sha-512' ? 2 : 0);
		w.u8(setup | (alg << 2));
		packIce(w, info.ufrag);
		packIce(w, info.pwd);
		var fpb = info.fp.split(':').map(function (h) { return parseInt(h, 16); });
		if (fpb.length !== [32, 48, 64][alg] || fpb.some(isNaN)) { throw new Error('odd fingerprint'); }
		w.bytes(fpb);
		w.u8(info.mid.length);
		for (var i = 0; i < info.mid.length; i++) { w.u8(info.mid.charCodeAt(i)); }
		var cands = pickCands(info.cands);
		w.u8(cands.length);
		for (var j = 0; j < cands.length; j++) {
			var c = cands[j];
			w.u8((c.type << 4) | c.fam);
			w.bytes(c.bytes);
			w.u16(c.port);
		}
		w.u16(crc16(w.b, w.b.length));
		return w.b;
	}
	function codeText(bytes) {
		var s = b32enc(bytes);
		var g = [];
		for (var i = 0; i < s.length; i += 5) { g.push(s.substr(i, 5)); }
		return 'HX-' + g.join('-');
	}
	function parsePayload(b, n) {
		var r = new R(b, n);
		var v = r.u8();
		if ((v >> 4) !== 1) { throw new Error('version'); }
		var info = { kind: v & 15, tok: r.u16(), cands: [] };
		var sa = r.u8();
		info.setup = ['actpass', 'active', 'passive', 'actpass'][sa & 3];
		var alg = (sa >> 2) & 3;
		info.fpAlg = ['sha-256', 'sha-384', 'sha-512', 'sha-256'][alg];
		info.ufrag = unpackIce(r);
		info.pwd = unpackIce(r);
		if (info.ufrag.length < 4 || info.pwd.length < 22) { throw new Error('credentials'); }
		var fp = r.bytes([32, 48, 64, 32][alg]);
		info.fp = fp.map(function (x) { return hx2(x).toUpperCase(); }).join(':');
		var ml = r.u8();
		info.mid = '';
		for (var i = 0; i < ml; i++) { info.mid += String.fromCharCode(r.u8()); }
		var nc = r.u8();
		for (var j = 0; j < nc; j++) {
			var tf = r.u8();
			var fam = tf & 15;
			var bytes = r.bytes(fam === 0 ? 4 : 16);
			var port = r.u16();
			info.cands.push({ type: tf >> 4, fam: fam, addr: decAddr(fam, bytes), port: port });
		}
		if (r.i !== n) { throw new Error('length'); }
		return info;
	}
	function decodeCode(text) {
		var s = cleanCode(text);
		var tries = [];
		if (s.substr(0, 2) === 'HX') { tries.push(s.substr(2)); }
		tries.push(s);
		for (var i = 0; i < tries.length; i++) {
			var b = b32dec(tries[i]);
			if (!b || b.length < 40) { continue; }
			var n = b.length - 2;
			if (crc16(b, n) !== ((b[n] << 8) | b[n + 1])) { continue; }
			try { return parsePayload(b, n); } catch (e) { continue; }
		}
		return null;
	}
	function buildSdp(info) {
		var L = ['v=0', 'o=- ' + (Math.floor(Math.random() * 900000000) + 100000000) + ' 2 IN IP4 127.0.0.1', 's=-', 't=0 0',
			'a=group:BUNDLE ' + info.mid,
			'm=application 9 UDP/DTLS/SCTP webrtc-datachannel', 'c=IN IP4 0.0.0.0',
			'a=ice-ufrag:' + info.ufrag, 'a=ice-pwd:' + info.pwd, 'a=ice-options:trickle',
			'a=fingerprint:' + info.fpAlg + ' ' + info.fp, 'a=setup:' + info.setup, 'a=mid:' + info.mid,
			'a=sctp-port:5000', 'a=max-message-size:262144'];
		for (var i = 0; i < info.cands.length; i++) {
			var c = info.cands[i];
			var prio = (c.type === 0 ? 126 : 100) * 16777216 + (65535 - i) * 256 + 255;
			L.push('a=candidate:' + (i + 1) + ' 1 udp ' + prio + ' ' + c.addr + ' ' + c.port + ' typ ' + (c.type === 0 ? 'host' : 'srflx') + (c.type === 1 ? ' raddr 0.0.0.0 rport 0' : ''));
		}
		L.push('a=end-of-candidates');
		return L.join(CRLF) + CRLF;
	}
	function fpKey(fp) { return String(fp).split(':').join('').substr(0, 10).toUpperCase(); }
	hx._codec = { encodeInfo: encodeInfo, decodeCode: decodeCode, codeText: codeText, parseSdp: parseSdp, buildSdp: buildSdp, b32enc: b32enc, b32dec: b32dec };

	// ---------- connections ----------
	function makeConn(kind) {
		var pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
		var dc = pc.createDataChannel('hx', { negotiated: true, id: 0, ordered: true });
		var c = { pc: pc, dc: dc, kind: kind, t: now(), lastRx: now(), state: 'making', id: '', nick: '', room: null, key: '', dead: false };
		dc.onopen = function () {
			c.lastRx = now();
			sendRaw(c, { t: 'hi', id: hx.selfId(), n: hx.nick, r: hx.room, k: c.key, v: 1 });
		};
		dc.onmessage = function (ev) { onMsg(c, ev.data); };
		dc.onclose = function () { drop(c, 'closed'); };
		pc.onconnectionstatechange = function () {
			if (pc.connectionState === 'closed') { drop(c, 'closed'); }
		};
		return c;
	}
	function gathered(pc, ms) {
		return new Promise(function (res) {
			var done = false;
			function fin() { if (!done) { done = true; res(); } }
			if (pc.iceGatheringState === 'complete') { fin(); return; }
			pc.addEventListener('icegatheringstatechange', function () { if (pc.iceGatheringState === 'complete') { fin(); } });
			pc.addEventListener('icecandidate', function (e) { if (!e.candidate) { fin(); } });
			setTimeout(fin, ms);
		});
	}
	function sendRaw(c, obj) {
		if (!c || c.dead || !c.dc || c.dc.readyState !== 'open') { return false; }
		try { c.dc.send(JSON.stringify(obj)); return true; } catch (e) { return false; }
	}
	function liveLinks() {
		var out = [];
		for (var id in hx.links) { if (!hx.links[id].dead) { out.push(hx.links[id]); } }
		return out;
	}
	function state(c, s) {
		if (c.state === s) { return; }
		c.state = s;
		if (c.kind === 'offer') { emit({ e: 'state', kind: 'offer', tok: c.tok, s: s, n: c.nick, id: c.id }); }
		else if (c.kind === 'answer') { emit({ e: 'state', kind: 'answer', key: c.key, s: s, n: c.nick, id: c.id }); }
	}
	function forget(c) {
		for (var t in hx.pend) { if (hx.pend[t] === c) { delete hx.pend[t]; } }
		for (var k in hx.ans) { if (hx.ans[k] === c) { delete hx.ans[k]; } }
		for (var s in hx.mesh) { if (hx.mesh[s] === c) { delete hx.mesh[s]; } }
	}
	function close(c) {
		if (c.dead) { return; }
		c.dead = true;
		try { c.dc.close(); } catch (e) {}
		try { c.pc.close(); } catch (e) {}
	}
	function drop(c, why) {
		if (c.dropped) { return; }
		c.dropped = true;
		var wasLinked = c.id && hx.links[c.id] === c;
		close(c);
		forget(c);
		if (wasLinked) {
			delete hx.links[c.id];
			dLeave(c.id);
			log('lost ' + c.nick + ' (' + why + ')');
			emit({ e: 'unlink', id: c.id, n: c.nick });
			floodPeers();
			groupChanged();
		} else if (c.state !== 'failed' && c.state !== 'replaced' && (c.kind === 'offer' || c.kind === 'answer')) {
			state(c, 'failed');
		}
	}
	function onMsg(c, raw) {
		if (c.dead) { return; }
		c.lastRx = now();
		var m;
		try { m = JSON.parse(raw); } catch (e) { return; }
		if (!m || typeof m !== 'object') { return; }
		if (m.t === 'hi') {
			if (typeof m.id !== 'string' || !m.id || m.id === hx.fixedId) { drop(c, 'self'); return; }
			c.id = m.id;
			c.nick = String(m.n || 'Player').substr(0, 24);
			c.room = (typeof m.r === 'string') ? m.r : null;
			if (!c.key && m.k) { c.key = String(m.k); }
			var prev = hx.links[c.id];
			if (prev && prev !== c && !prev.dead) {
				// Two links to the same player: both sides keep the same one.
				if (String(prev.key) <= String(c.key)) { c.state = 'replaced'; drop(c, 'duplicate'); return; }
				prev.state = 'replaced';
				prev.dropped = true;
				close(prev);
				forget(prev);
			}
			hx.links[c.id] = c;
			forget(c);
			c.linked = true;
			state(c, 'connected');
			log('linked with ' + c.nick);
			emit({ e: 'link', id: c.id, n: c.nick, kind: c.kind, tok: c.tok, key: c.key });
			if (hx.room && c.room === hx.room) { dJoin(c.id); }
			// catch the newcomer up on who's linked to whom
			for (var o in hx.graph) { if (hx.graph[o].msg) { sendRaw(c, hx.graph[o].msg); } }
			floodPeers();
			groupChanged();
			return;
		}
		if (!c.linked) { return; }
		if (m.t === 'd') {
			if (hx.room && m.r === hx.room && typeof m.j === 'string') { deliver(m.j, c.id); }
		} else if (m.t === 'room') {
			var old = c.room;
			c.room = (typeof m.r === 'string') ? m.r : null;
			if (hx.room && old === hx.room && c.room !== hx.room) { dLeave(c.id); }
			if (hx.room && c.room === hx.room) { dJoin(c.id); }
		} else if (m.t === 'f') {
			onFlood(c, m);
		} else if (m.t === 'n') {
			c.nick = String(m.n || c.nick).substr(0, 24);
			groupChanged();
		}
	}

	// ---------- rooms / presence (merged with Trystero) ----------
	function godotJoin(id) { try { if (window._godot_real_join) { window._godot_real_join(id); } } catch (e) { console.error(e); } }
	function godotLeave(id) { try { if (window._godot_real_leave) { window._godot_real_leave(id); } } catch (e) { console.error(e); } }
	function deliver(json, from) { try { if (window._godot_on_data_received) { window._godot_on_data_received(json, from); } } catch (e) { console.error(e); } }
	function dJoin(id) {
		if (hx.dP[id]) { return; }
		hx.dP[id] = true;
		if (!hx.tP[id]) { var r = hx.room; setTimeout(function () { if (hx.room === r && hx.dP[id]) { godotJoin(id); } }, 0); }
	}
	function dLeave(id) {
		if (!hx.dP[id]) { return; }
		delete hx.dP[id];
		if (!hx.tP[id]) { setTimeout(function () { if (!hx.dP[id] && !hx.tP[id]) { godotLeave(id); } }, 0); }
	}
	// Trystero events go through these: they return whether Godot should hear it.
	hx.tJoin = function (id) { var had = !!hx.dP[id]; hx.tP[id] = true; return !had; };
	hx.tLeave = function (id) { delete hx.tP[id]; return !hx.dP[id]; };
	hx.setRoom = function (code) {
		var r = (typeof code === 'string' && code.length > 0) ? code : null;
		hx.room = r;
		hx.dP = {};
		hx.tP = {};
		var links = liveLinks();
		for (var i = 0; i < links.length; i++) {
			sendRaw(links[i], { t: 'room', r: r });
			if (r && links[i].room === r) { dJoin(links[i].id); }
		}
	};
	hx.send = function (json) {
		if (!hx.room) { return; }
		var msg = JSON.stringify({ t: 'd', r: hx.room, j: String(json) });
		var links = liveLinks();
		for (var i = 0; i < links.length; i++) {
			var c = links[i];
			if (c.room === hx.room && c.dc.readyState === 'open') { try { c.dc.send(msg); } catch (e) {} }
		}
	};

	// ---------- group gossip, control messages, automatic mesh ----------
	function flood(kind, data, to) {
		var me = hx.selfId();
		hx.q += 1;
		var msg = { t: 'f', o: me, q: hx.q, k: kind, d: data };
		if (to) { msg.to = to; }
		hx.seen[me + ':' + hx.q] = now();
		if (kind === 'peers') { hx.graph[me] = { t: data.t, l: data.l, n: data.n, msg: msg }; }
		if (to && hx.links[to]) { sendRaw(hx.links[to], msg); return; }
		var links = liveLinks();
		for (var i = 0; i < links.length; i++) { sendRaw(links[i], msg); }
	}
	function onFlood(from, m) {
		if (typeof m.o !== 'string') { return; }
		var key = m.o + ':' + m.q;
		if (hx.seen[key]) { return; }
		hx.seen[key] = now();
		var me = hx.fixedId;
		if (m.o === me) { return; }
		if (!m.to || m.to === me) {
			var d = m.d || {};
			if (m.k === 'peers') {
				var g = hx.graph[m.o];
				if (!g || d.t >= g.t) { hx.graph[m.o] = { t: d.t, l: Array.isArray(d.l) ? d.l : [], n: String(d.n || ''), msg: m, rx: now() }; groupChanged(); }
			} else if (m.k === 'ctl') {
				emit({ e: 'ctl', from: m.o, j: d });
			} else if (m.k === 'sig') {
				onSig(m.o, d);
			}
		}
		if (m.to === me) { return; }
		if (m.to && hx.links[m.to]) { sendRaw(hx.links[m.to], m); return; }
		var links = liveLinks();
		for (var i = 0; i < links.length; i++) { if (links[i] !== from) { sendRaw(links[i], m); } }
	}
	function floodPeers() {
		if (!hx.fixedId) { return; }
		flood('peers', { t: now(), l: Object.keys(hx.links), n: hx.nick });
	}
	function groupIds() {
		var me = hx.fixedId;
		if (!me) { return []; }
		var out = [me], seen = {};
		seen[me] = true;
		var frontier = [me];
		var fresh = now() - 30000;
		while (frontier.length > 0) {
			var next = [];
			for (var i = 0; i < frontier.length; i++) {
				var u = frontier[i];
				var nb = [];
				if (u === me) { nb = Object.keys(hx.links); }
				else if (hx.graph[u] && (hx.graph[u].rx || now()) >= fresh) { nb = hx.graph[u].l; }
				for (var j = 0; j < nb.length; j++) {
					var v = String(nb[j]);
					if (!seen[v]) { seen[v] = true; out.push(v); next.push(v); }
				}
			}
			frontier = next;
		}
		return out;
	}
	hx.groupJson = function () {
		var ids = groupIds();
		var out = [];
		for (var i = 0; i < ids.length; i++) {
			var id = ids[i];
			var l = hx.links[id];
			var n = id === hx.fixedId ? hx.nick : (l ? l.nick : (hx.graph[id] ? hx.graph[id].n : ''));
			out.push({ id: id, n: n || 'Player', d: !!l, me: id === hx.fixedId });
		}
		return JSON.stringify(out);
	};
	var groupTimer = null;
	function groupChanged() {
		if (groupTimer) { return; }
		groupTimer = setTimeout(function () { groupTimer = null; emit({ e: 'group' }); }, 60);
	}
	function onSig(from, d) {
		if (!d || typeof d.s !== 'string') { return; }
		if (typeof d.o === 'string') {
			if (hx.links[from] || hx.mesh[d.s]) { return; }
			var c = makeConn('mesh');
			c.key = 'm' + d.s;
			c.peer = from;
			hx.mesh[d.s] = c;
			c.pc.setRemoteDescription({ type: 'offer', sdp: d.o })
				.then(function () { return c.pc.createAnswer(); })
				.then(function (a) { return c.pc.setLocalDescription(a); })
				.then(function () { return gathered(c.pc, GATHER_MS); })
				.then(function () { if (!c.dead) { flood('sig', { s: d.s, a: c.pc.localDescription.sdp }, from); } })
				.catch(function () { drop(c, 'mesh answer'); });
		} else if (typeof d.a === 'string') {
			var m = hx.mesh[d.s];
			if (!m || m.peer !== from || m.dead) { return; }
			m.pc.setRemoteDescription({ type: 'answer', sdp: d.a }).catch(function () { drop(m, 'mesh'); });
		}
	}
	function meshTick() {
		var me = hx.fixedId;
		if (!me) { return; }
		var ids = groupIds();
		for (var i = 0; i < ids.length; i++) {
			var id = ids[i];
			if (id === me || hx.links[id] || me > id) { continue; }
			var busy = false;
			for (var s in hx.mesh) { if (hx.mesh[s].peer === id) { busy = true; } }
			if (busy || now() - (hx.meshTried[id] || 0) < 45000) { continue; }
			hx.meshTried[id] = now();
			startMesh(id);
		}
	}
	function startMesh(peer) {
		var c = makeConn('mesh');
		var sid = rid(10);
		c.key = 'm' + sid;
		c.peer = peer;
		hx.mesh[sid] = c;
		c.pc.createOffer()
			.then(function (o) { return c.pc.setLocalDescription(o); })
			.then(function () { return gathered(c.pc, GATHER_MS); })
			.then(function () { if (!c.dead) { flood('sig', { s: sid, o: c.pc.localDescription.sdp }, peer); } })
			.catch(function () { drop(c, 'mesh offer'); });
	}

	// ---------- the API Godot calls ----------
	hx.setNick = function (n) {
		var nn = String(n || 'Player').substr(0, 24);
		if (nn === hx.nick) { return; }
		hx.nick = nn;
		var links = liveLinks();
		for (var i = 0; i < links.length; i++) { sendRaw(links[i], { t: 'n', n: nn }); }
		floodPeers();
	};
	hx.makeCode = function (nick) {
		if (nick) { hx.nick = String(nick).substr(0, 24); }
		hx.selfId();
		// keep a few older codes alive (a friend may still be entering one)
		var toks = Object.keys(hx.pend);
		if (toks.length >= 4) {
			toks.sort(function (a, b) { return hx.pend[a].t - hx.pend[b].t; });
			var oldest = hx.pend[toks[0]];
			oldest.state = 'replaced';
			drop(oldest, 'too many codes');
		}
		var tok = Math.floor(Math.random() * 65536);
		while (hx.pend[tok]) { tok = Math.floor(Math.random() * 65536); }
		var c = makeConn('offer');
		c.tok = tok;
		hx.pend[tok] = c;
		hx.myTok = tok;
		c.pc.createOffer()
			.then(function (o) { return c.pc.setLocalDescription(o); })
			.then(function () { return gathered(c.pc, GATHER_MS); })
			.then(function () {
				var info = parseSdp(c.pc.localDescription.sdp);
				c.key = 'c' + tok + fpKey(info.fp);
				c.code = codeText(encodeInfo(0, tok, info));
				c.state = 'ready';
				emit({ e: 'code', code: c.code, tok: tok, cands: pickCands(info.cands).length });
			})
			.catch(function (err) { c.state = 'failed'; drop(c, 'make'); emit({ e: 'err', m: 'Could not make a join code (' + err + ').' }); });
	};
	hx.enterCode = function (text, nick) {
		if (nick) { hx.nick = String(nick).substr(0, 24); }
		var info = decodeCode(text);
		if (!info) { emit({ e: 'err', m: "That code isn't right - check it, or copy it again." }); return; }
		hx.selfId();
		if (info.kind === 1) { applyReply(info); } else if (info.kind === 0) { answerJoin(info); }
		else { emit({ e: 'err', m: "That code isn't right - check it, or copy it again." }); }
	};
	function answerJoin(info) {
		var key = 'c' + info.tok + fpKey(info.fp);
		for (var t in hx.pend) {
			if (hx.pend[t].key === key) { emit({ e: 'err', m: "That's your own join code - send it to a friend instead." }); return; }
		}
		for (var id in hx.links) {
			if (hx.links[id].key === key) { emit({ e: 'err', m: "You're already connected with that code (" + hx.links[id].nick + ")." }); return; }
		}
		var old = hx.ans[key];
		if (old && !old.dead) {
			if (old.reply) { emit({ e: 'reply', key: key, code: old.reply, again: true }); }
			return;
		}
		var c = makeConn('answer');
		c.key = key;
		c.tok = info.tok;
		hx.ans[key] = c;
		emit({ e: 'state', kind: 'answer', key: key, s: 'making' });
		c.pc.setRemoteDescription({ type: 'offer', sdp: buildSdp(info) })
			.then(function () { return c.pc.createAnswer(); })
			.then(function (a) { return c.pc.setLocalDescription(a); })
			.then(function () { return gathered(c.pc, GATHER_MS); })
			.then(function () {
				if (c.dead) { return; }
				c.reply = codeText(encodeInfo(1, info.tok, parseSdp(c.pc.localDescription.sdp)));
				if (!c.linked) { c.state = 'waiting'; }
				emit({ e: 'reply', key: key, code: c.reply });
			})
			.catch(function (err) { c.state = 'failed'; drop(c, 'answer'); emit({ e: 'err', m: 'Could not use that code (' + err + ').' }); });
	}
	function applyReply(info) {
		var c = hx.pend[info.tok];
		if (!c) {
			for (var id in hx.links) {
				if (hx.links[id].kind === 'offer' && hx.links[id].tok === info.tok) { emit({ e: 'err', m: "You're already connected to " + hx.links[id].nick + '.' }); return; }
			}
			emit({ e: 'err', m: "That reply is for a join code you don't have any more - make a new code and swap again." });
			return;
		}
		if (c.pc.signalingState !== 'have-local-offer') { emit({ e: 'err', m: 'That join code is already being used.' }); return; }
		c.applied = now();
		state(c, 'connecting');
		c.pc.setRemoteDescription({ type: 'answer', sdp: buildSdp(info) })
			.then(function () { emit({ e: 'applied', tok: info.tok }); })
			.catch(function (err) { c.state = 'failed'; drop(c, 'reply'); emit({ e: 'err', m: "Couldn't use that reply code (" + err + ')' }); });
		if (hx.myTok === info.tok) { hx.myTok = -1; emit({ e: 'used', tok: info.tok }); }
	}
	hx.ctl = function (json) {
		var d;
		try { d = JSON.parse(String(json)); } catch (e) { return; }
		flood('ctl', d);
	};
	hx.reset = function () {
		var all = [];
		var k;
		for (k in hx.links) { all.push(hx.links[k]); }
		for (k in hx.ans) { all.push(hx.ans[k]); }
		for (k in hx.mesh) { all.push(hx.mesh[k]); }
		for (var i = 0; i < all.length; i++) { all[i].state = 'replaced'; drop(all[i], 'reset'); }
		hx.graph = {};
		hx.meshTried = {};
		floodPeers();
		groupChanged();
	};
	hx.linkCount = function () { return liveLinks().length; };

	// ---------- clipboard (needs a real tap/click to be allowed) ----------
	function copyFallback(t) {
		try {
			var ta = document.createElement('textarea');
			ta.value = t;
			ta.setAttribute('readonly', '');
			ta.style.position = 'fixed';
			ta.style.top = '-1000px';
			document.body.appendChild(ta);
			ta.select();
			ta.setSelectionRange(0, t.length);
			var ok = document.execCommand('copy');
			document.body.removeChild(ta);
			emit({ e: ok ? 'copied' : 'copyfail' });
		} catch (e) { emit({ e: 'copyfail' }); }
	}
	function copyNow(t) {
		try {
			if (navigator.clipboard && navigator.clipboard.writeText) {
				navigator.clipboard.writeText(t).then(function () { emit({ e: 'copied' }); }, function () { copyFallback(t); });
				return;
			}
		} catch (e) {}
		copyFallback(t);
	}
	function promptPaste() {
		setTimeout(function () {
			var t = window.prompt('Paste the code here:', '');
			if (t) { emit({ e: 'paste', t: String(t) }); }
		}, 0);
	}
	function pasteNow() {
		try {
			if (navigator.clipboard && navigator.clipboard.readText) {
				navigator.clipboard.readText().then(function (t) {
					if (t) { emit({ e: 'paste', t: String(t) }); } else { promptPaste(); }
				}, function () { promptPaste(); });
				return;
			}
		} catch (e) {}
		promptPaste();
	}
	hx.copyText = function (t) {
		hx.pendingCopy = String(t);
		hx.pendingCopyMs = now();
	};
	hx.armPaste = function () { hx.pendingPaste = true; hx.pendingPasteMs = now(); };
	function gesture() {
		if (hx.pendingCopy !== null) {
			var t = hx.pendingCopy;
			hx.pendingCopy = null;
			if (now() - hx.pendingCopyMs < 4000) { copyNow(t); }
		}
		if (hx.pendingPaste) {
			hx.pendingPaste = false;
			if (now() - hx.pendingPasteMs < 4000) { pasteNow(); }
		}
	}
	['pointerup', 'touchend', 'mouseup', 'keyup'].forEach(function (ev) { window.addEventListener(ev, gesture, true); });

	// ---------- housekeeping ----------
	setInterval(function () {
		var t = now();
		var links = liveLinks();
		for (var i = 0; i < links.length; i++) {
			var c = links[i];
			if (t - c.lastRx > 15000) { drop(c, 'timeout'); continue; }
			sendRaw(c, { t: 'p' });
		}
		var k;
		for (k in hx.pend) {
			var p = hx.pend[k];
			if (p.applied && !p.linked && t - p.applied > 60000) { drop(p, 'no answer'); }
			else if (!p.applied && t - p.t > 1800000) { p.state = 'replaced'; drop(p, 'old'); }
		}
		for (k in hx.ans) {
			var a = hx.ans[k];
			if (!a.linked && t - a.t > 600000) { drop(a, 'old'); }
		}
		for (k in hx.mesh) {
			var m = hx.mesh[k];
			if (!m.linked && t - m.t > 30000) { m.state = 'replaced'; drop(m, 'mesh timeout'); }
		}
		for (k in hx.seen) { if (t - hx.seen[k] > 120000) { delete hx.seen[k]; } }
	}, 2000);
	setInterval(function () {
		if (liveLinks().length > 0) { floodPeers(); }
		meshTick();
	}, 8000);
	setInterval(meshTick, 2500);
})();
"""

func _init_trystero_bridge() -> void :
	if not OS.has_feature("web"):
		return

	js_on_peer_join_cb = JavaScriptBridge.create_callback(_on_trystero_peer_joined)
	js_on_peer_leave_cb = JavaScriptBridge.create_callback(_on_trystero_peer_left)
	js_on_data_receive_cb = JavaScriptBridge.create_callback(_on_trystero_data_received)
	js_on_direct_cb = JavaScriptBridge.create_callback(_on_hx_event)

	# Background tabs stop the game loop, but JS timers keep firing (about once
	# a second), so matchmaking and the ban timer keep working while tabbed out.
	js_tick_cb = JavaScriptBridge.create_callback(_on_js_tick)

	var window = JavaScriptBridge.get_interface("window")
	window._godot_tick = js_tick_cb
	window._godot_real_join = js_on_peer_join_cb
	window._godot_real_leave = js_on_peer_leave_cb
	window._godot_on_data_received = js_on_data_receive_cb
	window._godot_on_direct = js_on_direct_cb

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

		// Trystero's joins/leaves pass through the direct-connect layer, so
		// someone linked both ways is still just one player to the game.
		window._godot_on_peer_joined = function (id) {
			var fwd = true;
			try { if (window.hx) { fwd = window.hx.tJoin(String(id)); } } catch (e) { console.error(e); }
			if (fwd && window._godot_real_join) { window._godot_real_join.apply(null, arguments); }
		};
		window._godot_on_peer_left = function (id) {
			var fwd = true;
			try { if (window.hx) { fwd = window.hx.tLeave(String(id)); } } catch (e) { console.error(e); }
			if (fwd && window._godot_real_leave) { window._godot_real_leave.apply(null, arguments); }
		};
		// Every packet goes out through Trystero and any direct links.
		window.hxSendAll = function (j) {
			try { if (typeof window.sendTrysteroPacket === 'function') { window.sendTrysteroPacket(j); } } catch (e) { console.error(e); }
			try { if (window.hx) { window.hx.send(j); } } catch (e) { console.error(e); }
		};
	""", true)
	JavaScriptBridge.eval("try {\n" + HX_JS + "\n} catch (e) { console.error('[Direct] could not start', e); }", true)

func _leave_trystero_room() -> void :
	if not OS.has_feature("web"):
		return
	var window = JavaScriptBridge.get_interface("window")
	window.leaveTrysteroRoom()
	_hx_set_room("")

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
		"color": local_color_hex, 
		"parts": local_part_colors, 
		"model": _my_model(), 
		"party": party_id if party_queued and _in_party() else "", 
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

	var teams: Dictionary = _assign_teams(n)
	var bots: Dictionary = {}
	if is_royale and royale_fill_bots and n < ROYALE_FILL_TO:
		bots = _royale_make_bots(n)
		for k in bots:
			teams[k] = k - 1 # everyone for themselves
			player_nicknames[k] = String(bots[k]["name"])
			player_elos[k] = int(bots[k]["elo"])
			player_colors[k] = String(bots[k]["color"])
			player_models[k] = "mannequin"

	var indices: Array = range(map_pool.size())
	indices.shuffle()
	var picked: Array = indices.slice(0, n + 1)

	var setup = {
		"action": "match_setup", 
		"teams": teams, 
		"map_indices": picked, 
		"nicknames": player_nicknames.duplicate(), 
		"elos": player_elos.duplicate(), 
		"colors": player_colors.duplicate(), 
		"part_colors": player_part_colors.duplicate(true), 
		"models": player_models.duplicate(),
		"bots": bots
	}
	last_setup_packet = setup.duplicate(true)
	send_p2p_packet(setup.duplicate(true))
	_apply_match_setup(setup)

# Splits players into two teams as evenly by ELO as possible, keeping each
# party (that queued together) on one team. FFA: everyone on their own.
func _assign_teams(n: int) -> Dictionary:
	var teams: Dictionary = {}
	if is_ffa:
		for pid in range(1, n + 1):
			teams[pid] = pid - 1
		return teams
	var units: Array = []
	var by_party: Dictionary = {}
	for pid in range(1, n + 1):
		var pt = String(mm_peer_party.get(pid, ""))
		if pt == "":
			units.append([pid])
		elif by_party.has(pt):
			by_party[pt].append(pid)
		else:
			var u: Array = [pid]
			by_party[pt] = u
			units.append(u)
	var best_mask = -1
	var best_diff = INF
	for mask in range(1 << units.size()):
		if mask & 1:
			continue # the unit with peer 1 stays on Blue (skips mirror copies)
		var size0 = 0
		var elo0 = 0
		var elo1 = 0
		for i in range(units.size()):
			for pid in units[i]:
				var e = int(player_elos.get(pid, 0))
				if mask & (1 << i):
					elo1 += e
				else:
					size0 += 1
					elo0 += e
		if size0 != team_size:
			continue
		var diff = abs(elo0 - elo1)
		if diff < best_diff:
			best_diff = diff
			best_mask = mask
	if best_mask < 0:
		# Shouldn't happen (party sizes are checked when queueing): snake draft.
		var order: Array = range(1, n + 1)
		order.sort_custom(_sort_by_elo_desc)
		var pattern = [0, 1, 1, 0, 0, 1]
		for i in range(n):
			teams[order[i]] = pattern[i]
		return teams
	for i in range(units.size()):
		for pid in units[i]:
			teams[pid] = 1 if best_mask & (1 << i) else 0
	return teams

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
	var cols = data.get("colors", {})
	for k in cols:
		if Color.html_is_valid(String(cols[k])):
			player_colors[int(k)] = String(cols[k])
	var pcols = data.get("part_colors", {})
	if pcols is Dictionary:
		for k in pcols:
			player_part_colors[int(k)] = _clean_part_colors(pcols[k])
	var mods = data.get("models", {})
	if mods is Dictionary:
		for k in mods:
			player_models[int(k)] = _clean_model(mods[k])
	royale_bots.clear()
	var bots_in = data.get("bots", {})
	if is_royale and bots_in is Dictionary:
		for k in bots_in:
			var b = bots_in[k]
			if b is Dictionary and int(k) > mm_roster.size():
				royale_bots[int(k)] = {"name": String(b.get("name", "Bot")), "level": clampi(int(b.get("level", 3)), 3, 4), "miss": clampf(float(b.get("miss", 0.5)), 0.0, 1.0)}
	player_models[local_peer_id] = _my_model()
	player_nicknames[local_peer_id] = local_nickname
	player_elos[local_peer_id] = local_elo
	player_colors[local_peer_id] = local_color_hex
	player_part_colors[local_peer_id] = local_part_colors.duplicate()

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
	elif is_royale:
		log_console("[Match] HUSS ROYALE with " + str(all_player_ids().size()) + " players" + (" (" + str(royale_bots.size()) + " of them bots)" if not royale_bots.is_empty() else "") + " - vote for the map, then grab weapons: last one standing wins!")
	elif is_ffa:
		log_console("[Match] Free For All with " + str(all_player_ids().size()) + " players - last one standing wins!")
	else:
		log_console("[Match] Opponent: " + String(player_nicknames.get(_first_enemy_id(), "Opponent")))

	if is_royale:
		# Huss Royale: vote for the map (no bans).
		_start_royale_vote()
		return
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
		if mm_custom_match:
			_return_to_main_menu(nick + " left before the challenge started.")
			return
		log_console("[Matchmaking] " + nick + " dropped before the match started. Back to the queue...")
		_mm_skip(peer_id_str)
		_mm_enter_lobby()
		return
	if not is_match_active:
		if is_royale:
			# Royale: they're out (last place); everyone else plays on.
			log_console("[Royale] " + nick + " left during the map vote.")
			_mark_player_forfeited(pid)
			_royale_check_all_voted()
			return
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
			if Color.html_is_valid(String(data.get("color", ""))):
				player_colors[sender_pid] = String(data.get("color", ""))
			player_part_colors[sender_pid] = _clean_part_colors(data.get("parts", {}))
			player_models[sender_pid] = _clean_model(data.get("model", "mannequin"))
			mm_peer_party[sender_pid] = String(data.get("party", ""))

			_lb_merge(data.get("leaderboard", {}))
			_lb_set(nick, elo)
			_lb_mark_seen(nick)
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
		"royale_vote":
			if is_royale:
				_on_royale_vote(sender_pid, int(data.get("map", -1)))
		"royale_map":
			if is_royale:
				_apply_royale_choice(data)
		"crown":
			if is_royale:
				desert_set_crown(int(data.get("k", -1)))
		"bh_use":
			if is_royale and is_host_peer:
				_host_start_black_hole(sender_pid)
		"bh_start":
			if is_royale:
				_apply_black_hole(data)
		"bh_enter":
			if is_royale and is_host_peer:
				_host_bunker_claim(sender_pid, int(data.get("b", -1)))
		"bh_slots":
			if is_royale:
				_apply_bunker_slots(data.get("s", []))
		"bh_full":
			if is_royale and int(data.get("pid", -1)) == local_peer_id:
				_bunker_turned_away(int(data.get("b", -1)))
		"bh_collapse":
			if is_royale:
				_apply_bh_collapse(data)
		"med_heal":
			var healed = get_player(int(data.get("peer_id", -1)))
			if healed and is_royale:
				healed.heal(int(data.get("amount", 0)))
		"ban_map":
			var turn = int(data.get("turn", banned_map_indices.size()))
			if not ban_log.has(turn):
				ban_log[turn] = {"idx": int(data.get("banned_index", -1)), "by": sender_pid}
			_apply_pending_bans()
		"move":
			var p_node = get_player(int(data.get("peer_id", sender_pid)))
			if p_node and not p_node.is_local_player():
				var np = Vector3(data["pos_x"], data["pos_y"], data["pos_z"])
				if is_royale and p_node.global_position.distance_to(np) < 6.0:
					p_node.net_target = np # glide there (fewer updates in Royale)
					p_node.net_has_target = true
				else:
					p_node.global_position = np
					p_node.net_has_target = false
				if data.has("q") and data["q"] is Array and data["q"].size() == 4:
					var mq = data["q"]
					p_node.global_transform.basis = Basis(Quaternion(float(mq[0]), float(mq[1]), float(mq[2]), float(mq[3])).normalized())
				else:
					p_node.rotation_degrees.y = data["rot_y"]
				if is_royale:
					p_node.gliding = data.has("gl")
					if data.has("sl"):
						p_node.remote_slide_t = 0.25
		"bots_move":
			# The host's bots (one packet for all of them).
			if is_royale and not is_host_peer:
				for e in data.get("b", []):
					if typeof(e) != TYPE_ARRAY or e.size() < 5:
						continue
					var bn = get_player(int(e[0]))
					if bn == null or not bn.is_bot or bn.is_dead:
						continue
					var bp = Vector3(float(e[1]), float(e[2]), float(e[3]))
					if bn.global_position.distance_to(bp) < 6.0:
						bn.net_target = bp
						bn.net_has_target = true
					else:
						bn.global_position = bp
						bn.net_has_target = false
					if e.size() >= 12:
						bn.global_transform.basis = Basis(Quaternion(float(e[8]), float(e[9]), float(e[10]), float(e[11])).normalized())
					else:
						bn.rotation_degrees.y = float(e[4])
					bn.gliding = e.size() > 5 and int(e[5]) == 1
					bn.net_vel = Vector3(float(e[6]), 0.0, float(e[7])).limit_length(16.0) if e.size() > 7 and not is_moon() else Vector3.ZERO
					bn.net_age = 0.0
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
			if target and target.is_bot and is_host_peer and attacker and not target.is_dead:
				if target.bot_windup > 0.0 and target.bot_target == attacker:
					# This player and the bot attacked each other at the same
					# moment: clash, both flung back (their client does its half).
					attacker.qte_active = false
					target.trigger_repulse_clash(attacker, true)
				else:
					target.add_movement_lock(attacker.peer_id)
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
			if target_end and (target_end.is_local_player() or (target_end.is_bot and is_host_peer)):
				target_end.remove_movement_lock(attacker_end.peer_id if attacker_end else sender_pid)
		"trigger_clash":
			var clash_a = get_player(int(data.get("a", sender_pid)))
			var clash_b = get_player(int(data.get("b", -1)))
			var me = get_local_player()
			if me and clash_b == me:
				me.trigger_repulse_clash(clash_a)
			elif clash_b and clash_b.is_bot and is_host_peer:
				clash_b.trigger_repulse_clash(clash_a, true)
				if clash_a:
					clash_a.qte_active = false
			else:
				if clash_a:
					clash_a.qte_active = false
				if clash_b:
					clash_b.qte_active = false
		"trigger_cooldown":
			if int(data.get("peer_id", local_peer_id)) == local_peer_id:
				start_combat_cooldown()
			else:
				var cd_bot = get_player(int(data.get("peer_id", -1)))
				if cd_bot and cd_bot.is_bot and is_host_peer:
					cd_bot.bot_attack_cd = max(cd_bot.bot_attack_cd, COMBAT_COOLDOWN_DURATION)
		"take_damage":
			var hurt = get_player(int(data.get("peer_id", -1)))
			if hurt:
				if data.has("w") and hurt.is_local_player() and GEAR.has(String(data["w"])):
					log_console("[Royale] " + String(player_nicknames.get(int(data.get("by", sender_pid)), "Someone")) + " shot you with a " + String(GEAR[String(data["w"])]["name"]).to_lower() + " (-" + str(int(data.get("amount", 0))) + ")!")
				hurt.apply_damage(int(data.get("amount", 25)))
		"shot":
			if is_royale:
				_on_shot_packet(data)
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
		"items_spawn":
			if is_royale:
				for it in data.get("items", []):
					if typeof(it) == TYPE_ARRAY and it.size() >= 3:
						_apply_item_spawn(int(it[0]), String(it[1]), int(it[2]))
				_royale_wave_note(String(data.get("wave", "")))
		"item_claim":
			if is_royale and is_host_peer:
				_host_grant_item(int(data.get("id", -1)), sender_pid)
		"item_taken":
			if is_royale:
				_apply_item_taken(int(data.get("id", -1)), int(data.get("by", 0)), String(data.get("type", "")), int(data.get("heal", 0)))
		"crystal_taken":
			if not is_host_peer:
				_apply_crystal_taken(int(data.get("id", -1)), int(data.get("by", 0)), String(data.get("type", "")), int(data.get("heal", 0)))
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
	if is_royale and match_setup_done and mm_phase == "match" and not is_single_player:
		_royale_vote_tick(now)

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
	window.hxSendAll(json_string)

func _join_room(code: String) -> void :
	if OS.has_feature("web"):
		_hx_set_room(code)
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
	if orig == party_leader:
		party_leader_heard_ms = _now_ms()

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
			if mm_custom_match:
				_return_to_main_menu("Your opponent didn't connect, so the challenge was cancelled.")
				return
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
	if dc_lobby != "":
		return dc_n # (a direct group plays as soon as everyone's in)
	return int(GAME_MODES[game_mode].get("min", team_size * 2))

func _mm_max_players() -> int:
	if dc_lobby != "":
		return dc_n
	return int(GAME_MODES[game_mode].get("max", team_size * 2))

func _mm_wait_seconds() -> float:
	return ROYALE_WAIT_SECONDS if game_mode == "royale" else FFA_WAIT_SECONDS

func _mm_lobby_code() -> String:
	if dc_lobby != "":
		return dc_lobby
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
	mm_lobby_party.clear()
	mm_custom_match = false
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
		elif dc_lobby != "":
			var here = min(_mm_searching_peers().size() + 1, dc_n)
			waiting_opponent_label.text = mode_label + " with your direct group: " + str(here) + "/" + str(dc_n) + " here..."
			if here < dc_n and _now_ms() - dc_queue_ms > 20000:
				waiting_opponent_label.text += " Still waiting for the others (they need to be on the menu) - leave to go back."
		elif party_queued and _in_party() and not _mm_units(_mm_searching_peers()).has(_mm_my_unit()):
			waiting_opponent_label.text = "Waiting for your party to join the queue..."
		else:
			var queued = 1
			for lp in mm_lobby_peers:
				if mm_lobby_peers[lp] != "unknown":
					queued += 1
			if is_ffa and ffa_wait_timer >= 0.0:
				var left = int(ceil(max(_mm_wait_seconds() - ffa_wait_timer, 0.0)))
				waiting_opponent_label.text = mode_label + ": " + str(_mm_searching_peers().size() + 1) + " players queued - starting in " + str(left) + "s (or as soon as " + str(_mm_max_players()) + " are in)"
			else:
				waiting_opponent_label.text = "Searching for " + mode_label + "... (" + str(queued) + " in queue, " + str(_mm_min_players()) + " needed)"
				if party_queued and _in_party():
					waiting_opponent_label.text += " - with your party of " + str(party_members.size())
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
	if party_queued and _in_party():
		pkt["party"] = party_id
		pkt["psize"] = party_members.size()
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

	# Queueing as a party: if someone in the party never shows up in the lobby
	# (or leaves it), go back to the menu together instead of waiting forever.
	if party_queued and _in_party():
		var all_here = true
		var left_after_joining = false
		for pm in _party_ids():
			if pm == mm_self_id:
				continue
			if mm_lobby_peers.has(pm):
				if mm_lobby_peers[pm] != "unknown":
					party_lobby_seen[pm] = true
			else:
				all_here = false
				if party_lobby_seen.has(pm):
					left_after_joining = true
		# Someone who was here and left gets a short grace period (a dropped
		# link); someone who hasn't arrived yet gets longer (slow connection).
		var limit = 6000 if left_after_joining else PARTY_LOBBY_WAIT_MS
		if all_here:
			party_lobby_missing_since = 0
		elif party_lobby_missing_since == 0:
			party_lobby_missing_since = _now_ms()
		elif _now_ms() - party_lobby_missing_since > limit:
			_return_to_main_menu("Someone in your party left the queue (or never got into it), so your party went back to the menu.")
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

# Groups are built from "units": a party queueing together (only once all of
# its members are in the lobby) or a solo player. Units are never split.
func _mm_my_unit() -> Array:
	if party_queued and _in_party():
		var ids = _party_ids()
		ids.sort()
		return ids
	return [mm_self_id]

func _mm_units(pool: Array) -> Array:
	var units: Array = []
	var parties: Dictionary = {}
	var psizes: Dictionary = {}
	var everyone: Array = pool.duplicate()
	everyone.append(mm_self_id)
	for p in everyone:
		var info = mm_lobby_party.get(p, ["", 1])
		if p == mm_self_id:
			info = [party_id, party_members.size()] if party_queued and _in_party() else ["", 1]
		var pt = String(info[0])
		if pt == "" or int(info[1]) <= 1:
			units.append([p])
		else:
			if not parties.has(pt):
				parties[pt] = []
			parties[pt].append(p)
			psizes[pt] = int(info[1])
	for pt in parties:
		if parties[pt].size() == psizes[pt]: # complete parties only
			var u: Array = parties[pt]
			u.sort()
			units.append(u)
	units.sort_custom(func(x, y): return String(x[0]) < String(y[0]))
	return units

func _mm_unit_sum(units: Array) -> int:
	var n = 0
	for u in units:
		n += u.size()
	return n

# Can these unit sizes be split into two teams of exactly `team` players?
func _mm_splittable(sizes: Array, team: int) -> bool:
	var reach: Dictionary = {0: true}
	for sz in sizes:
		if sz > team:
			return false
		var next: Dictionary = reach.duplicate()
		for r in reach:
			if int(r) + sz <= team:
				next[int(r) + sz] = true
		reach = next
	return reach.has(team)

# Picks our group: our own unit plus other units (lowest IDs first), never
# splitting a party. 2v2/3v3 need exactly 2 x team_size players that divide
# into two full teams; 1v1/FFA take as many as fit (at least the minimum).
func _mm_pick_group(units: Array, my_unit: Array, min_n: int, max_n: int) -> Array:
	var team_mode = team_size > 1 and not is_ffa
	var others: Array = []
	for u in units:
		if u != my_unit:
			others.append(u)
	var best: Array = []
	var best_total = 0
	var stack: Array = [[0, [my_unit], my_unit.size()]]
	var steps = 0
	while not stack.is_empty() and steps < 5000:
		steps += 1
		var st = stack.pop_back()
		var idx: int = st[0]
		var chosen: Array = st[1]
		var total: int = st[2]
		var usable = total >= min_n and total > best_total
		if usable and team_mode:
			var sizes: Array = []
			for u in chosen:
				sizes.append(u.size())
			usable = total == max_n and _mm_splittable(sizes, team_size)
		if usable:
			best = chosen
			best_total = total
			if total == max_n:
				break
		if total == max_n:
			continue
		for i in range(others.size() - 1, idx - 1, -1):
			var u2: Array = others[i]
			if total + u2.size() <= max_n and (not team_mode or u2.size() <= team_size):
				var nc = chosen.duplicate()
				nc.append(u2)
				stack.append([i + 1, nc, total + u2.size()])
	var flat: Array = []
	for u in best:
		flat.append_array(u)
	return flat

func _mm_try_lead(delta: float) -> void :
	var min_n = _mm_min_players()
	var max_n = _mm_max_players()
	var pool = _mm_searching_peers()
	var units = _mm_units(pool)
	var my_unit = _mm_my_unit()
	var mine_ready = units.has(my_unit)
	var count = _mm_unit_sum(units)
	if count < min_n or not mine_ready:
		mm_leader_wait_timer = 0.0
		if count < min_n:
			ffa_wait_timer = -1.0
		return
	if count < max_n:
		# Free For All: enough players to start, but wait up to 30s for more.
		if ffa_wait_timer < 0.0:
			ffa_wait_timer = 0.0
			log_console("[Matchmaking] " + str(count) + " players queued - starting in " + str(int(_mm_wait_seconds())) + "s unless more join.")
		ffa_wait_timer += delta
		if ffa_wait_timer < _mm_wait_seconds():
			mm_leader_wait_timer = 0.0
			return

	# The lowest-ID player among the ready units leads, unless they were
	# unresponsive when it was their turn (frozen tab etc.) - then the next one
	# leads, and they can still be invited.
	var now = _now_ms()
	var leaders: Array = [mm_self_id]
	for u in units:
		for p in u:
			if p != mm_self_id and not (mm_no_lead_until.has(p) and now < int(mm_no_lead_until[p])):
				leaders.append(p)
	leaders.sort()
	if leaders[0] != mm_self_id:
		mm_leader_wait_timer += delta
		if mm_leader_wait_timer >= MM_LEADER_PATIENCE:
			mm_leader_wait_timer = 0.0
			mm_no_lead_until[leaders[0]] = now + MM_LEADER_SKIP_MS
		return
	mm_leader_wait_timer = 0.0

	var roster = _mm_pick_group(units, my_unit, min_n, max_n)
	if roster.is_empty():
		return
	roster.sort()
	mm_lead_roster = roster
	mm_lead_room = "hussle_" + game_mode + "_" + mm_self_id + "_" + str(randi() % 1000000)
	mm_lead_accepted = []
	mm_lead_timer = MM_HANDSHAKE_TIMEOUT
	log_console("[Matchmaking] Inviting " + str(roster.size() - 1) + " players into a group...")
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
			mm_lobby_party[sender] = [String(data.get("party", "")), int(data.get("psize", 1))]
		"mm_invite":
			var roster: Array = []
			for r in data.get("roster", []):
				roster.append(String(r))
			var valid = room != "" and roster.size() >= _mm_min_players() and roster.size() <= _mm_max_players() and roster.has(mm_self_id) and roster.has(sender)
			if valid and party_queued and _in_party():
				# Only join a group that takes our whole party.
				for pmember in _party_ids():
					if not roster.has(pmember):
						valid = false
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
	player_colors.clear()
	player_colors[local_peer_id] = local_color_hex
	player_part_colors.clear()
	player_part_colors[local_peer_id] = local_part_colors.duplicate()
	player_models.clear()
	player_models[local_peer_id] = _my_model()
	mm_peer_party.clear()
	mm_peer_party[local_peer_id] = party_id if party_queued and _in_party() else ""
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
	if admin_pending_level > 0:
		# practice(<level>) from the browser console: skip the picker.
		var lvl = admin_pending_level
		admin_pending_level = 0
		_on_dummy_level_chosen(lvl)
		return
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
	player_colors.clear()
	player_part_colors.clear()
	player_models.clear()
	dead_peers.clear()
	forfeited_peers.clear()
	match_start_elos.clear()
	match_setup_done = false
	mm_roster = []
	mm_room_joined.clear()
	mm_room_left.clear()
	leave_room_timer = -1.0
	local_peer_id = 1
	mm_custom_match = false
	_royale_reset()
	_set_in_match_flag(false)
	ffa_places.clear()
	ffa_wait_timer = -1.0

func _on_find_match_pressed(mode: String = "1v1", from_party: bool = false) -> void :
	_save_nickname_from_input()

	if not from_party and _in_party():
		var err = _party_queue_error(mode)
		if err != "":
			_social_status(err)
			pending_error_message = err
			_build_main_menu()
			return
		for m in party_members:
			if String(m[0]) != mm_self_id:
				send_p2p_packet({"action": "pt_queue", "to": String(m[0]), "pid": party_id, "mode": mode})
		_social_status("Queueing your party for " + String(GAME_MODES[mode]["label"]) + "...")
		# Stay a moment so the party hears it, then queue ourselves.
		social_linger = {"kind": "queue", "mode": mode, "t": SOCIAL_LINGER}
		return

	_social_leave_menu()
	party_queued = from_party and _in_party() and dc_lobby == ""
	party_lobby_missing_since = 0
	party_lobby_seen.clear()
	game_mode = mode if GAME_MODES.has(mode) else "1v1"
	team_size = int(GAME_MODES[game_mode]["team_size"])
	is_ffa = game_mode == "ffa" or game_mode == "royale" # Royale plays like a big FFA
	is_royale = game_mode == "royale"
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
	is_royale = false
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

	var gone_before: Dictionary = forfeited_peers.duplicate() if is_royale else {}
	dead_peers.clear()
	forfeited_peers.clear()
	for k in gone_before:
		forfeited_peers[k] = true
		dead_peers[k] = true
	player_nicknames[local_peer_id] = local_nickname
	player_elos[local_peer_id] = local_elo
	player_colors[local_peer_id] = local_color_hex
	player_part_colors[local_peer_id] = local_part_colors.duplicate()
	player_models[local_peer_id] = _my_model()
	match_start_elos = player_elos.duplicate()

	_build_3d_environment()
	_set_in_match_flag(true)
	if is_royale:
		royale_item_timer = ROYALE_ITEM_RESPAWN
		royale_crystal_timer = ROYALE_CRYSTAL_WAVE_TIME
		royale_time = 0.0
		_build_storm()
		for id in royale_items: # items announced before our world existed
			_spawn_item_node(id)

	if is_single_player:
		_spawn_player(1)
		_spawn_test_dummy(2)
	else:
		for pid in all_player_ids():
			_spawn_player(pid)
		for pid in forfeited_peers:
			var gone = get_player(pid)
			if gone:
				gone.set_dead_state()
		if team_size > 1:
			log_console("[Match] Eliminate the whole enemy team to win. If you die, you turn invisible and can roam until the match ends.")
		elif is_ffa:
			log_console("[Match] Everyone is your enemy - be the last one standing. If you die you turn invisible and can watch.")
		if is_royale:
			log_console("[Royale] " + String(selected_map_data.get("name", "")) + "! " + _royale_weapons_line() + " Follow the light beams! (F5: 1st/3rd person)")
			log_console("[Royale] The " + String(selected_map_data.get("storm", "storm")).to_lower() + " starts closing in at 1:00 and reaches the middle at 6:00 - 10s inside it and you're out.")
			log_console("[Royale] SKY DROP: you have low gravity for " + str(int(ROYALE_GLIDE_TIME)) + "s - steer to where you want to land!")
			log_console("[Royale] New weapons every " + str(int(ROYALE_ITEM_RESPAWN)) + "s, crystals (pink = Regen +" + str(REGEN_HEAL) + " HP) every " + str(int(ROYALE_CRYSTAL_WAVE_TIME)) + "s. " + ("Tap SLIDE while sprinting to slide." if mobile_controls else "Ctrl while sprinting (Shift) = slide."))

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
	if is_royale and not is_single_player:
		n += royale_bots.size() # bots come right after the real players
	return range(1, n + 1)

func is_bot(pid: int) -> bool:
	return is_royale and royale_bots.has(pid)

func human_ids() -> Array:
	return all_player_ids().filter(func(p): return not is_bot(p))

func get_team(pid: int) -> int:
	return int(player_teams.get(pid, 0 if pid == 1 else 1))

func is_teammate(a: int, b: int) -> bool:
	return get_team(a) == get_team(b)

# Keeps only known parts with valid colors (data from other players).
func _clean_part_colors(d) -> Dictionary:
	var out: Dictionary = {}
	if not (d is Dictionary):
		return out
	for k in d:
		var part = String(k)
		var hex = String(d[k]).trim_prefix("#").to_lower()
		if BODY_PART_NAMES.has(part) and part != "" and hex.length() == 6 and Color.html_is_valid(hex):
			out[part] = hex
	return out

func _clean_model(m) -> String:
	return "dummy" if String(m) == "dummy" else "mannequin"

func player_model(pid: int) -> String:
	return _clean_model(player_models.get(pid, "mannequin"))

func _my_model() -> String:
	return "dummy" if local_model == "dummy" and unlocked_dummy else "mannequin"

# Reaching 500 ELO unlocks the crash test dummy - and it stays unlocked even
# if you drop below 500 later.
func _check_dummy_unlock() -> void :
	if not unlocked_dummy and local_elo >= DUMMY_UNLOCK_ELO:
		unlocked_dummy = true
		dummy_just_unlocked = true
		log_console("[Unlock] You reached " + get_rank_name(DUMMY_UNLOCK_ELO) + " - the Crash Test Dummy is unlocked! Pick him in Customize Character.")

# The color a player picked for one body part ("" if it's just their main color).
func player_part_override(pid: int, part: String) -> String:
	return String(player_part_colors.get(pid, {}).get(part, ""))

# Body color: the color the player picked (falls back to the old defaults).
func player_body_color(pid: int) -> Color:
	var hex = String(player_colors.get(pid, ""))
	if Color.html_is_valid(hex):
		var c = Color.html(hex)
		c.a = 1.0
		return c
	if is_ffa:
		return FFA_COLORS[(pid - 1) % FFA_COLORS.size()]
	if team_size > 1:
		return TEAM_COLORS[get_team(pid) % TEAM_COLORS.size()]
	return Color(randf(), randf(), randf())

# Text color for HUD lists: team color in team modes, the player's own color
# in FFA (lightened if it's too dark to read, e.g. black).
func player_color(pid: int) -> Color:
	if is_ffa:
		var c = player_body_color(pid)
		if c.get_luminance() < 0.45:
			c = c.lerp(Color.WHITE, 0.5)
		return c
	return TEAM_COLORS[get_team(pid) % TEAM_COLORS.size()]

func ghosts_can_fly() -> bool:
	if is_single_player:
		return false
	return team_size > 1 or (is_ffa and GHOSTS_FLY_IN_FFA)

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
	if is_royale:
		# Sky drop: spread around the island, high up.
		var pts = _royale_spawn_points()
		var total = max(all_player_ids().size(), 1)
		var idx = int(floor(float(pid - 1) * float(pts.size()) / float(total)))
		if is_moon():
			return pts[idx % pts.size()] # (already out in space above the moon)
		return pts[idx % pts.size()] + Vector3(0, ROYALE_DROP_HEIGHT - 1.0, 0)
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
# Living players never see ghosts. Once you're a ghost yourself (2v2, 3v3,
# FFA), you see the other ghosts at 50% transparency.
func refresh_ghost_visibility() -> void :
	if not players_container or is_single_player:
		return
	var me = get_local_player()
	var i_am_ghost = me != null and me.is_dead
	for p in players_container.get_children():
		if p is NetworkPlayer and p != me and p.is_dead:
			p.show_as_ghost(i_am_ghost)

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
		_royale_bots_take_over()

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
	if alive.size() > 1 and is_royale and not royale_bots.is_empty() and alive.all(func(p): return is_bot(p)):
		# Every real player is out: the match is over. The bots still standing
		# are ranked by health (their order doesn't change anyone's ELO).
		alive.sort_custom(func(a, b):
			var na = get_player(a)
			var nb = get_player(b)
			return (na.health if na else 0) > (nb.health if nb else 0))
		for i in range(alive.size()):
			ffa_places[alive[i]] = i + 1
		send_p2p_packet({"action": "match_outcome", "ffa_places": ffa_places})
		_process_ffa_outcome(ffa_places)
		return
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
	if is_royale:
		# Huss Royale has its own placement table (the other modes don't change).
		var r_elo = local_elo if pid == local_peer_id else int(match_start_elos.get(pid, player_elos.get(pid, 0)))
		var r_place = int(ffa_places.get(pid, 0))
		if r_place <= 0:
			r_place = 1 # still in = ahead of everyone who's out
		return royale_elo_change(r_elo, r_place, ids.size())
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

# Huss Royale ELO: 1st-5th gain 40/35/30/25/20, 6th and below lose 10 - all
# scaled by your ELO. Low ranks gain more and lose less (100 ELO: 1st is about
# +58, a loss about -10); high ranks gain less and lose more (1000 ELO: last
# place is -50; max rank: 1st is +20). Further down the order = a bigger loss.
func royale_elo_change(elo: int, place: int, n: int) -> int:
	var e = clamp(float(elo), 0.0, float(MAX_ELO))
	if place <= ROYALE_PLACE_GAINS.size():
		var gain_k = lerp(1.5, 0.5, e / float(MAX_ELO))
		return int(round(float(ROYALE_PLACE_GAINS[place - 1]) * gain_k))
	var first_loser = ROYALE_PLACE_GAINS.size() + 1
	var depth = clamp(float(place - first_loser) / float(max(n - first_loser, 1)), 0.0, 1.0)
	var base = 10.0 + 40.0 * clamp((e - 100.0) / 900.0, 0.0, 1.5)
	return -int(round(base * (0.6 + 0.4 * depth)))

func _show_ffa_dead_banner() -> void :
	if not dead_banner_label or is_game_over:
		return
	var n = all_player_ids().size()
	var place = int(ffa_places.get(local_peer_id, n))
	var change = _ffa_elo_change(local_peer_id)
	dead_banner_label.text = "YOU PLACED " + _ordinal(place).to_upper() + " OF " + str(n) + "  (" + ("+" if change >= 0 else "") + str(change) + " ELO)\nYou're an invisible ghost" + (": look where you want to go and hold W to fly (Shift = faster)." if ghosts_can_fly() else " - roam freely and watch the rest of the match.") + "\nPress Esc twice to leave whenever you like - your placement is kept."
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
		if not is_bot(pid): # bots aren't on the leaderboard
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
	var title = ("You won the Huss Royale!" if is_royale else "You won the Free For All!") if place == 1 else "You placed " + _ordinal(place) + " of " + str(n)
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
	if is_royale:
		team_hud_label.text = _royale_hud_text()
		team_hud_label.visible = true
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
	_royale_tick(delta)
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
	var types = CRYSTAL_ABILITIES.keys() + ["regen"]
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
	var info = crystal_info(String(data["type"]))
	crystal_node = PowerCrystal.new(int(data["id"]), String(data["type"]), info["color"], info["name"], self)
	crystal_node.position = data["pos"]
	world_root.add_child(crystal_node)
	log_console("[Crystals] A " + String(info["name"]) + " crystal appeared! Follow the purple arrow.")

# Called by the crystal when the local player is touching it.
func on_crystal_touched(crystal: Node) -> void :
	if is_game_over:
		return
	var me = get_local_player()
	if not me or me.is_dead:
		return
	if crystal_active.is_empty() or int(crystal.crystal_id) != int(crystal_active["id"]):
		return
	if String(crystal_active.get("type", "")) == "regen":
		if me.health >= 100:
			return # full health - leave it for later / the opponent
	elif local_ability != "":
		return # one ability at a time - leave it for later / the opponent
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
	var heal = 0
	if ability_type == "regen":
		var p = get_player(by_peer)
		if p == null or p.health >= 100:
			return
		heal = min(REGEN_HEAL, 100 - p.health)
	send_p2p_packet({"action": "crystal_taken", "id": id, "by": by_peer, "type": ability_type, "heal": heal})
	_apply_crystal_taken(id, by_peer, ability_type, heal)

# Regen crystal (+25 HP) or one of the abilities.
func crystal_info(type: String) -> Dictionary:
	if type == "regen":
		return REGEN_INFO
	return CRYSTAL_ABILITIES.get(type, {"name": type, "color": CRYSTAL_POINTER_COLOR})

# Every client adds the same amount (the host worked it out), so health stays
# in step however the packets are ordered.
func _apply_heal(pid: int, amount: int) -> void :
	var p = get_player(pid)
	if p and not p.is_dead and amount > 0:
		p.heal(amount)
	if amount <= 0:
		return
	var who = String(player_nicknames.get(pid, "A player"))
	if pid == local_peer_id:
		log_console("[Crystals] Regen crystal: +" + str(amount) + " HP!")
	elif not is_royale:
		log_console("[Crystals] " + who + " grabbed a Regen crystal (+" + str(amount) + " HP).")

func _apply_crystal_taken(id: int, by_peer: int, ability_type: String, heal: int = 0) -> void :
	if not crystal_active.is_empty() and int(crystal_active["id"]) == id:
		crystal_active = {}
		if crystal_node and is_instance_valid(crystal_node):
			crystal_node.queue_free()
		crystal_node = null
	crystal_claim_sent = false
	crystal_spawn_timer = CRYSTAL_RESPAWN_TIME

	if ability_type == "regen":
		_apply_heal(by_peer, heal)
		return
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
		"double_jump": hint = "Tap JUMP again in mid-air" if mobile_controls else "Press Space again in mid-air"
		"double_damage": hint = "Next QTE hits for 50 (smaller target)"
		"speed_boost": hint = "Move " + str(int(round((SPEED_BOOST_MULT - 1.0) * 100))) + "% faster"
		"lunge": hint = "Tap Q to lunge forward" if mobile_controls else "Press Q to lunge forward"
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
	rank_tex_cache.clear()
	if ResourceLoader.exists(SPRITE_SHEET_PATH_PNG):
		loaded_sheet_texture = load(SPRITE_SHEET_PATH_PNG) as Texture2D
	elif ResourceLoader.exists(SPRITE_SHEET_PATH_JPG):
		loaded_sheet_texture = load(SPRITE_SHEET_PATH_JPG) as Texture2D

func rank_index(elo: int) -> int:
	return clamp(floori(elo / 100.0), 0, RANK_COUNT - 1)

func rank_name_by_index(i: int) -> String:
	return get_rank_name(clamp(i, 0, RANK_COUNT - 1) * 100)

func rank_texture_by_index(i: int) -> Texture2D:
	return load_rank_texture(clamp(i, 0, RANK_COUNT - 1) * 100)

func load_rank_texture(elo: int) -> Texture2D:
	var rank_idx = rank_index(elo)
	if rank_tex_cache.has(rank_idx):
		return rank_tex_cache[rank_idx]

	if loaded_sheet_texture:
		var sheet = Vector2(loaded_sheet_texture.get_width(), loaded_sheet_texture.get_height())
		var corner: Vector2 = RANK_ICON_CROPS[rank_idx]
		var atlas = AtlasTexture.new()
		atlas.atlas = loaded_sheet_texture
		atlas.region = Rect2((corner * sheet).round(), (RANK_ICON_CROP_SIZE * sheet).round())
		atlas.filter_clip = true # no bleeding from the neighbouring icons/text
		rank_tex_cache[rank_idx] = atlas
		return atlas

	var fallback_path = "res://rank_icons/rank_" + str(rank_idx) + ".png"
	if ResourceLoader.exists(fallback_path):
		return load(fallback_path) as Texture2D

	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var hue = (rank_idx * 17 % 100) / 100.0
	img.fill(Color.from_hsv(hue, 0.85, 0.95))
	var fb = ImageTexture.create_from_image(img)
	rank_tex_cache[rank_idx] = fb
	return fb


func _save_nickname_from_input() -> void:
	if is_instance_valid(nickname_input) and nickname_input.text.strip_edges() != "":
		var changed = local_nickname != nickname_input.text.strip_edges()
		local_nickname = nickname_input.text.strip_edges()
		save_player_data()
		if changed:
			_lb_announce()
			_hx_set_nick(local_nickname)

func _load_player_data() -> void :
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				local_nickname = json.data.get("nickname", "Player")
				local_elo = int(json.data.get("elo", 0))
				local_color_hex = String(json.data.get("color", ""))
				local_part_colors = _clean_part_colors(json.data.get("parts", {}))
				third_person = String(json.data.get("view", "1p")) == "3p"
				unlocked_dummy = _truthy(json.data.get("unlocked_dummy", false))
				local_model = _clean_model(json.data.get("model", "mannequin"))
				if json.data.has("controls"):
					mobile_controls = String(json.data.get("controls", "pc")) == "mobile"
				else:
					mobile_controls = _looks_like_mobile()
			file.close()
	else:
		mobile_controls = _looks_like_mobile()
	_check_dummy_unlock()
	dummy_just_unlocked = false # (an old save that was already past 500)
	if not Color.html_is_valid(local_color_hex):
		# First launch: start with a random preset.
		local_color_hex = String(COLOR_PRESETS[randi() % COLOR_PRESETS.size()][1])
		save_player_data()

func _truthy(v) -> bool:
	if typeof(v) == TYPE_STRING:
		return String(v).strip_edges().to_lower() == "true"
	return bool(v)

func save_player_data() -> void :
	_check_dummy_unlock()
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"nickname": local_nickname, 
			"elo": local_elo, 
			"color": local_color_hex, 
			"parts": local_part_colors, 
			"view": "3p" if third_person else "1p", 
			"unlocked_dummy": unlocked_dummy, 
			"model": local_model, 
			"controls": "mobile" if mobile_controls else "pc"
		}
		file.store_string(JSON.stringify(data))
		file.close()

func export_data_to_obfuscated_string() -> String:
	var raw_dict = {
		"nickname": local_nickname,
		"elo": local_elo,
		"color": local_color_hex,
		"parts": local_part_colors,
		"Unlocked_dummy": unlocked_dummy,
		"model": local_model
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
			if dict.has("color") and Color.html_is_valid(String(dict["color"])):
				local_color_hex = String(dict["color"]).trim_prefix("#").to_lower()
			local_part_colors = _clean_part_colors(dict.get("parts", {}))
			unlocked_dummy = _truthy(dict.get("Unlocked_dummy", dict.get("unlocked_dummy", false)))
			local_model = _clean_model(dict.get("model", "mannequin"))
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
	var old = leaderboard_data.get(nick, null)
	var seen = float(old.get("seen", 0.0)) if old is Dictionary else 0.0
	leaderboard_data[nick] = {"elo": elo, "t": _wall_time() if t < 0.0 else t, "seen": seen}

# "seen" = the last time this player was online (in the menu or in a match).
func _lb_mark_seen(nick: String) -> void :
	var e = leaderboard_data.get(nick, null)
	if e is Dictionary:
		e["seen"] = _wall_time()

func _ago(seconds: float) -> String:
	var s = int(max(seconds, 0.0))
	if s < 60:
		return "just now"
	if s < 3600:
		return str(s / 60) + " min ago"
	if s < 86400:
		return str(s / 3600) + " h ago"
	return str(s / 86400) + " d ago"

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
		var seen_have = float(have.get("seen", 0.0)) if have is Dictionary else 0.0
		var seen_new = max(seen_have, float(e.get("seen", 0.0)))
		if t_new > t_have:
			leaderboard_data[n] = {"elo": int(e["elo"]), "t": t_new, "seen": seen_new}
			changed = true
		elif seen_new > seen_have:
			leaderboard_data[n]["seen"] = seen_new
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
	console_panel = panel
	panel.visible = not mobile_controls # mobile: no console

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
	dead_banner_label.text = "YOU WERE ELIMINATED\nYou're an invisible ghost: look where you want to go and hold W to fly (Shift = faster).\nStay until the end: if your team wins you still get half the ELO."
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

	# Huss Royale sky drop: "steer to where you want to land (12s)"
	royale_drop_label = Label.new()
	royale_drop_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	royale_drop_label.position = Vector2(-300, 70)
	royale_drop_label.custom_minimum_size = Vector2(600, 50)
	royale_drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	royale_drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	royale_drop_label.add_theme_font_size_override("font_size", 20)
	royale_drop_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	royale_drop_label.add_theme_constant_override("outline_size", 6)
	royale_drop_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	royale_drop_label.visible = false
	hud_canvas.add_child(royale_drop_label)

	# Huss Royale storm: a tint while you're in it, and a timer / warning line.
	storm_tint = ColorRect.new()
	storm_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	storm_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	storm_tint.visible = false
	hud_canvas.add_child(storm_tint)
	hud_canvas.move_child(storm_tint, 0)
	storm_label = Label.new()
	storm_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	storm_label.position = Vector2(-320, 128)
	storm_label.custom_minimum_size = Vector2(640, 26)
	storm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	storm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	storm_label.add_theme_font_size_override("font_size", 17)
	storm_label.add_theme_constant_override("outline_size", 6)
	storm_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	storm_label.visible = false
	hud_canvas.add_child(storm_label)
	hazard_label = Label.new()
	hazard_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hazard_label.position = Vector2(-340, 156)
	hazard_label.custom_minimum_size = Vector2(680, 26)
	hazard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hazard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hazard_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hazard_label.add_theme_font_size_override("font_size", 16)
	hazard_label.add_theme_constant_override("outline_size", 6)
	hazard_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hazard_label.visible = false
	hud_canvas.add_child(hazard_label)
	bh_label = Label.new()
	bh_label.set_anchors_preset(Control.PRESET_CENTER)
	bh_label.position = Vector2(-340, -150)
	bh_label.custom_minimum_size = Vector2(680, 30)
	bh_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bh_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bh_label.add_theme_font_size_override("font_size", 22)
	bh_label.add_theme_constant_override("outline_size", 7)
	bh_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	bh_label.visible = false
	hud_canvas.add_child(bh_label)

	# Plus-shaped crosshair, always centered (anchored to the middle of the screen).
	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_canvas.add_child(crosshair)

	_mobile_reset_inputs()
	mobile_sprint_on = false
	if mobile_controls:
		mobile_ui = MobileControls.new(self)
		hud_canvas.add_child(mobile_ui)

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
			if cand and (cand.gliding or me.gliding):
				continue # (Royale sky drop: everyone's up there)
			if cand and not is_moon() and cand.global_position.y - me.global_position.y > OPPONENT_HIGH_THRESHOLD:
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

		var cnode: Node3D = crystal_node if crystal_node and is_instance_valid(crystal_node) else null
		var cname = "CRYSTAL"
		if cnode == null and is_royale and not me.is_dead:
			# Royale: point at the nearest crystal (Regen first if you're hurt).
			var best_d = INF
			for id in royale_item_nodes:
				var n = royale_item_nodes[id]
				if not is_instance_valid(n) or not royale_items.has(id):
					continue
				var ty = String(royale_items[id]["type"])
				if not _is_royale_crystal(ty):
					continue
				var dd = n.global_position.distance_to(me.global_position)
				if ty == "regen" and me.health < 100:
					dd *= 0.5
				if dd < best_d:
					best_d = dd
					cnode = n
					cname = "REGEN" if ty == "regen" else "CRYSTAL"
		if crystal_pointer and cnode and not me.is_dead:
			show_crystal = true
			var cpos = cnode.global_position
			_aim_pointer(crystal_pointer, cam, center, cpos)
			var dist = cpos.distance_to(me.global_position + Vector3(0, 0.9, 0))
			crystal_distance_label.text = cname + ": " + str(int(round(dist))) + "m"
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
		var me_hp = get_local_player()
		local_hp_label.text = "YOUR HP: " + str(hp) + " / " + str(me_hp.max_health if me_hp else 100)
		if hp <= 30:
			local_hp_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		elif hp <= 60:
			local_hp_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		else:
			local_hp_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))

func _build_main_menu() -> void :
	_clear_ui()
	dc_lobby = ""
	dc_n = 0
	if dummy_just_unlocked and pending_error_message == "":
		dummy_just_unlocked = false
		pending_error_message = "NEW! You reached " + get_rank_name(DUMMY_UNLOCK_ELO) + " and unlocked the Crash Test Dummy - pick him under Customize Character!"
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
	_osk_prep(nickname_input)
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

	var color_row = HBoxContainer.new()
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(color_row)
	var color_btn = Button.new()
	color_btn.text = "Customize Character"
	color_btn.custom_minimum_size = Vector2(270, 36)
	color_btn.pressed.connect(_show_color_picker_ui)
	color_row.add_child(color_btn)
	var swatch = ColorRect.new()
	swatch.color = _local_color()
	swatch.custom_minimum_size = Vector2(36, 36)
	color_row.add_child(swatch)

	var controls_row = HBoxContainer.new()
	controls_row.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(controls_row)
	var controls_lbl = Label.new()
	controls_lbl.text = "Controls: "
	controls_row.add_child(controls_lbl)
	var controls_group = ButtonGroup.new()
	for opt in [["PC", false], ["Mobile", true]]:
		var b = Button.new()
		b.text = String(opt[0])
		b.toggle_mode = true
		b.button_group = controls_group
		b.button_pressed = mobile_controls == bool(opt[1])
		b.custom_minimum_size = Vector2(110, 34)
		var is_mobile = bool(opt[1])
		b.pressed.connect( func(): _set_controls(is_mobile))
		controls_row.add_child(b)

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

	var royale_btn = Button.new()
	royale_btn.text = "Huss Royale (4-15 players)"
	royale_btn.custom_minimum_size = Vector2(320, 40)
	royale_btn.pressed.connect( func(): _on_find_match_pressed("royale"))
	container.add_child(royale_btn)

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

	_build_party_panel()
	_build_rank_panel()

	# Sit in the leaderboard room while on the menu, and (re)announce ourselves -
	# our ELO or nickname may have just changed.
	if mm_phase == "menu":
		_lb_announce()
	else:
		_lb_enter_room()
	if dc_open:
		_build_direct_panel()

# --- LEADERBOARD ROOM ---

func _lb_enter_room() -> void :
	if mm_phase == "menu":
		return
	mm_phase = "menu"
	lb_online.clear()
	lb_heartbeat_timer = 0.0
	party_leader_heard_ms = _now_ms()
	party_queued = false
	_switch_room(LEADERBOARD_ROOM_CODE)

func _lb_leave_room() -> void :
	if mm_phase != "menu":
		return
	_social_leave_menu()
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
				_lb_mark_seen(nick)
				lb_ui_dirty = true
			_lb_update_online_label()
		"lb_sync":
			if _lb_merge(data.get("leaderboard", {})):
				_save_leaderboard_cache()
				lb_ui_dirty = true
		"ch_req", "ch_reply", "ch_cancel", "pt_invite", "pt_reply", "pt_full", "pt_state", "pt_leave", "pt_queue", "pt_code_join":
			_social_handle_packet(action, sender, data)
		_:
			pass # leaderboard + social messages only - nothing is played in this room

func _lb_tick(dt: float, now: int) -> void :
	lb_heartbeat_timer -= dt
	if lb_heartbeat_timer <= 0.0:
		lb_heartbeat_timer = LB_HEARTBEAT
		_lb_announce()
		if _is_party_leader() and _in_party():
			_party_send_state()
	_social_tick(dt, now)
	if mm_phase != "menu":
		return # a challenge / party queue just took us out of the menu
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


# --- SOCIAL: CHALLENGES AND PARTIES (main menu / leaderboard room) ---
# Challenge to 1v1: the other player gets a popup; if they accept, both move
# into a fresh private room and play a 1v1 (it counts for ELO like ranked 1v1
# - set CHALLENGE_IS_RANKED to false to make challenges friendly).
# Parties: up to 5 players. Only the leader queues, for everyone; party members
# always end up in the same match, and on the same team in 2v2/3v3.

func _in_party() -> bool:
	return party_members.size() > 1

func _is_party_leader() -> bool:
	return party_id != "" and party_leader == mm_self_id

func _party_ids() -> Array:
	var out: Array = []
	for m in party_members:
		out.append(String(m[0]))
	return out

func _party_nick(tid: String) -> String:
	for m in party_members:
		if String(m[0]) == tid:
			return String(m[1])
	return "a player"

func _lb_tid_for_nick(nick: String) -> String:
	for tid in lb_online:
		if String(lb_online[tid]["nick"]) == nick:
			return tid
	return ""

func _social_status(msg: String) -> void :
	social_status = msg
	social_dirty = true
	lb_ui_dirty = true
	log_console("[Social] " + msg)

func _social_rand() -> String:
	return str(randi() % 1000000)

# ----- challenges -----

func _challenge_player(tid: String, nick: String) -> void :
	if mm_phase != "menu":
		return
	if not challenge_out.is_empty():
		_social_status("You already have a challenge waiting for an answer.")
		return
	var cid = mm_self_id + ":" + _social_rand()
	challenge_out = {"cid": cid, "to": tid, "nick": nick, "ms": _now_ms()}
	send_p2p_packet({"action": "ch_req", "to": tid, "cid": cid, "nick": local_nickname})
	_social_status("Challenge sent to " + nick + " - waiting for them to accept...")

func _answer_challenge(cid: String, accept: bool) -> void :
	var req = null
	for c in challenge_in:
		if String(c["cid"]) == cid:
			req = c
	if req == null:
		return
	challenge_in.erase(req)
	social_dirty = true
	if not accept:
		send_p2p_packet({"action": "ch_reply", "to": req["from"], "cid": cid, "accept": false})
		_social_status("You declined " + String(req["nick"]) + "'s challenge.")
		return
	for other in challenge_in:
		send_p2p_packet({"action": "ch_reply", "to": other["from"], "cid": other["cid"], "accept": false})
	challenge_in.clear()
	var room = "hussle_challenge_" + mm_self_id + "_" + _social_rand()
	send_p2p_packet({"action": "ch_reply", "to": req["from"], "cid": cid, "accept": true, "room": room})
	_social_status("Starting your 1v1 against " + String(req["nick"]) + "...")
	# Stay a moment so the answer gets delivered, then switch rooms.
	social_linger = {"kind": "challenge", "room": room, "roster": [String(req["from"]), mm_self_id], "t": SOCIAL_LINGER}

func _start_challenge_match(roster: Array, room: String) -> void :
	_social_leave_menu()
	_save_nickname_from_input()
	game_mode = "1v1"
	team_size = 1
	is_ffa = false
	is_royale = false
	is_single_player = false
	is_host_peer = false
	_reset_match_state()
	mm_skip_until.clear()
	party_queued = false
	_clear_ui()
	_build_hud_console()
	mm_custom_match = true
	log_console("[Challenge] Setting up your 1v1...")
	_mm_enter_private_room(roster, room)
	mm_private_join_timer = 20.0

# ----- parties -----

func _party_create_if_needed() -> void :
	if party_id == "":
		party_id = mm_self_id + ":" + _social_rand()
		party_leader = mm_self_id
		party_members = [[mm_self_id, local_nickname]]
		party_ver = 0

func _party_send_state(changed: bool = false) -> void :
	if not _is_party_leader():
		return
	if changed:
		party_ver += 1
		social_dirty = true
		lb_ui_dirty = true
	for m in party_members:
		if String(m[0]) != mm_self_id:
			send_p2p_packet({"action": "pt_state", "to": String(m[0]), "pid": party_id, "leader": party_leader, "members": party_members, "ver": party_ver, "code": party_code})

func _invite_to_party(tid: String, nick: String) -> void :
	if mm_phase != "menu":
		return
	if _in_party() and not _is_party_leader():
		_social_status("Only the party leader (" + _party_nick(party_leader) + ") can invite players.")
		return
	if party_members.size() >= PARTY_MAX:
		_social_status("Your party is full (" + str(PARTY_MAX) + " players max).")
		return
	if _party_ids().has(tid):
		_social_status(nick + " is already in your party.")
		return
	_party_create_if_needed()
	party_invites_out[tid] = _now_ms()
	send_p2p_packet({"action": "pt_invite", "to": tid, "pid": party_id, "nick": local_nickname, "size": party_members.size()})
	_social_status("Party invite sent to " + nick + ".")

func _answer_party_invite(pid: String, accept: bool) -> void :
	var inv = null
	for i in party_invites_in:
		if String(i["pid"]) == pid:
			inv = i
	if inv == null:
		return
	party_invites_in.erase(inv)
	social_dirty = true
	if not accept:
		send_p2p_packet({"action": "pt_reply", "to": inv["from"], "pid": pid, "accept": false, "nick": local_nickname})
		_social_status("You declined " + String(inv["nick"]) + "'s party invite.")
		return
	if party_id != "" and party_id != pid:
		_party_leave(true)
	party_joining = pid
	party_joining_ms = _now_ms()
	send_p2p_packet({"action": "pt_reply", "to": inv["from"], "pid": pid, "accept": true, "nick": local_nickname})
	_social_status("Joining " + String(inv["nick"]) + "'s party...")

func _party_leave(quiet: bool = false) -> void :
	if party_id == "":
		return
	if _is_party_leader():
		var rest: Array = []
		for m in party_members:
			if String(m[0]) != mm_self_id:
				rest.append(m)
		if not rest.is_empty():
			# Hand the party to the next player (lowest ID).
			var ids: Array = []
			for m in rest:
				ids.append(String(m[0]))
			ids.sort()
			for m in rest:
				send_p2p_packet({"action": "pt_state", "to": String(m[0]), "pid": party_id, "leader": ids[0], "members": rest, "ver": party_ver + 1, "code": party_code})
	else:
		send_p2p_packet({"action": "pt_leave", "to": party_leader, "pid": party_id})
	party_id = ""
	party_leader = ""
	party_members = []
	party_code = ""
	party_queued = false
	party_invites_out.clear()
	if not quiet:
		_social_status("You left the party.")
	social_dirty = true
	lb_ui_dirty = true

func _party_new_code() -> String:
	return "%06d" % (randi() % 1000000)

func _is_party_code(t: String) -> bool:
	if t.length() != 6:
		return false
	for ch in t:
		if ch < "0" or ch > "9":
			return false
	return true

# Leader (or someone not in a party yet): make / replace the party's code.
func _create_party_code() -> void :
	if mm_phase != "menu":
		return
	if _in_party() and not _is_party_leader():
		_social_status("Only the party leader (" + _party_nick(party_leader) + ") can make a party code.")
		return
	_party_create_if_needed()
	var old = party_code
	party_code = _party_new_code()
	while party_code == old:
		party_code = _party_new_code()
	_party_send_state(true)
	_social_status("Your party code is " + party_code + " - share it so friends can join.")

func _copy_party_code() -> void :
	if party_code == "":
		return
	DisplayServer.clipboard_set(party_code)
	_social_status("Party code " + party_code + " copied.")

func _join_party_code(text: String) -> void :
	if mm_phase != "menu":
		return
	var code = text.strip_edges()
	if not _is_party_code(code):
		_social_status("Party codes are 6 digits - check the code and try again.")
		return
	if party_code != "" and code == party_code:
		_social_status("That's your own party's code.")
		return
	party_code_joining = code
	party_code_join_ms = _now_ms()
	send_p2p_packet({"action": "pt_code_join", "code": code, "nick": local_nickname})
	_social_status("Looking for the party with code " + code + "...")

func _on_party_code_typed(t: String) -> void :
	var digits = ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != t and party_code_input:
		var caret = party_code_input.caret_column
		party_code_input.text = digits.substr(0, 6)
		party_code_input.caret_column = min(caret, party_code_input.text.length())

func _party_remove(tid: String) -> void :
	if not _is_party_leader() or tid == mm_self_id:
		return
	var nick = _party_nick(tid)
	for m in party_members.duplicate():
		if String(m[0]) == tid:
			party_members.erase(m)
	_party_send_state(true)
	# Tell them too (if they can still hear us).
	send_p2p_packet({"action": "pt_state", "to": tid, "pid": party_id, "leader": party_leader, "members": party_members, "ver": party_ver, "code": party_code})
	_social_status("You removed " + nick + " from the party.")

func _party_queue_error(mode: String) -> String:
	if not _is_party_leader():
		return "Only the party leader (" + _party_nick(party_leader) + ") can start a queue."
	var n = party_members.size()
	match mode:
		"1v1":
			return "Parties can't queue for 1v1 - use 'Challenge to 1v1' on the Leaderboard instead."
		"2v2":
			if n > 2:
				return "Your party is too large for 2v2 (max 2 players)."
		"3v3":
			if n > 3:
				return "Your party is too large for 3v3 (max 3 players)."
		"ffa", "royale":
			if n > PARTY_MAX:
				return "Your party is too large for " + String(GAME_MODES[mode]["label"]) + " (max " + str(PARTY_MAX) + " players)."
	for m in party_members:
		if String(m[0]) != mm_self_id and not lb_online.has(String(m[0])):
			return String(m[1]) + " isn't on the main menu right now."
	return ""

# ----- social packets (leaderboard room) -----

func _social_handle_packet(action: String, sender: String, data: Dictionary) -> void :
	match action:
		"ch_req":
			var cid = String(data.get("cid", ""))
			for c in challenge_in:
				if String(c["cid"]) == cid:
					return
			challenge_in.append({"cid": cid, "from": sender, "nick": String(data.get("nick", "Player")), "ms": _now_ms()})
			social_dirty = true
			log_console("[Social] " + String(data.get("nick", "Player")) + " challenged you to a 1v1!")
		"ch_reply":
			var cid2 = String(data.get("cid", ""))
			if challenge_out.is_empty() or String(challenge_out["cid"]) != cid2 or String(challenge_out["to"]) != sender:
				return
			var nick = String(challenge_out["nick"])
			challenge_out = {}
			if bool(data.get("accept", false)) and String(data.get("room", "")) != "":
				_social_status(nick + " accepted! Starting your 1v1...")
				_start_challenge_match([mm_self_id, sender], String(data.get("room", "")))
			else:
				_social_status(nick + " declined your challenge.")
		"ch_cancel":
			var cid3 = String(data.get("cid", ""))
			for c in challenge_in.duplicate():
				if String(c["cid"]) == cid3:
					challenge_in.erase(c)
					social_dirty = true
		"pt_invite":
			var pid = String(data.get("pid", ""))
			if pid == "" or pid == party_id:
				return
			for i in party_invites_in:
				if String(i["pid"]) == pid:
					return
			party_invites_in.append({"pid": pid, "from": sender, "nick": String(data.get("nick", "Player")), "size": int(data.get("size", 1)), "ms": _now_ms()})
			social_dirty = true
			log_console("[Social] " + String(data.get("nick", "Player")) + " invited you to their party.")
		"pt_reply":
			if not party_invites_out.has(sender):
				return
			party_invites_out.erase(sender)
			var rnick = String(data.get("nick", "Player"))
			if String(data.get("pid", "")) != party_id or not _is_party_leader():
				send_p2p_packet({"action": "pt_full", "to": sender, "pid": String(data.get("pid", ""))})
				return
			if not bool(data.get("accept", false)):
				_social_status(rnick + " declined your party invite.")
				return
			if party_members.size() >= PARTY_MAX:
				send_p2p_packet({"action": "pt_full", "to": sender, "pid": party_id})
				_social_status(rnick + " couldn't join - your party is full.")
				return
			if not _party_ids().has(sender):
				party_members.append([sender, rnick])
			_party_send_state(true)
			_social_status(rnick + " joined your party.")
		"pt_full":
			if party_code_joining != "" and String(data.get("code", "")) == party_code_joining:
				party_code_joining = ""
				_social_status("That party is full (" + str(PARTY_MAX) + " players max).")
			elif String(data.get("pid", "")) == party_joining:
				party_joining = ""
				_social_status("Couldn't join - that party is full or no longer exists.")
		"pt_code_join":
			# Someone typed in a party code - only that party's leader answers.
			var jcode = String(data.get("code", ""))
			if jcode == "" or jcode != party_code or not _is_party_leader():
				return
			var jnick = String(data.get("nick", "Player"))
			if _party_ids().has(sender):
				_party_send_state()
				return
			if party_members.size() >= PARTY_MAX:
				send_p2p_packet({"action": "pt_full", "to": sender, "pid": party_id, "code": jcode})
				_social_status(jnick + " tried your code, but the party is full.")
				return
			party_members.append([sender, jnick])
			_party_send_state(true)
			_social_status(jnick + " joined your party with the code.")
		"pt_state":
			var spid = String(data.get("pid", ""))
			var members: Array = []
			for m in data.get("members", []):
				if typeof(m) == TYPE_ARRAY and m.size() >= 2:
					members.append([String(m[0]), String(m[1])])
			var ids: Array = []
			for m in members:
				ids.append(m[0])
			var ver = int(data.get("ver", 0))
			if spid != "" and spid == party_id and ver < party_ver:
				return # an older update that arrived late
			var scode = String(data.get("code", ""))
			if ids.has(mm_self_id):
				var via_code = party_code_joining != "" and scode == party_code_joining and spid != party_id
				if spid == "" or (spid != party_id and spid != party_joining and not via_code):
					if spid != "" and spid != party_id and party_code_joined != "" and scode == party_code_joined:
						# Another party happened to have the same code - leave it.
						send_p2p_packet({"action": "pt_leave", "to": sender, "pid": spid})
					return # not our party (or one we just left), and we're not joining it
				if via_code:
					if party_id != "" and party_id != spid:
						_party_leave(true)
					party_code_joined = party_code_joining
					party_code_joining = ""
				var was_leader = _is_party_leader()
				var was_in = party_id == spid
				var new_leader = String(data.get("leader", sender))
				var changed = not was_in or members != party_members or new_leader != party_leader or scode != party_code
				party_id = spid
				party_leader = new_leader
				party_members = members
				party_code = scode
				party_ver = ver
				party_joining = ""
				party_leader_heard_ms = _now_ms()
				if not was_in:
					_social_status("You joined " + _party_nick(party_leader) + "'s party.")
				if _is_party_leader() and not was_leader:
					_social_status("You're now the party leader.")
					_party_send_state(true)
				if changed:
					social_dirty = true
					lb_ui_dirty = true
			elif spid == party_id and party_id != "":
				party_id = ""
				party_leader = ""
				party_members = []
				party_code = ""
				_social_status("You're no longer in that party.")
		"pt_leave":
			if String(data.get("pid", "")) != party_id or not _is_party_leader():
				return
			var lnick = _party_nick(sender)
			for m in party_members.duplicate():
				if String(m[0]) == sender:
					party_members.erase(m)
			_party_send_state(true)
			_social_status(lnick + " left the party.")
		"pt_queue":
			if String(data.get("pid", "")) == party_id and sender == party_leader and mm_phase == "menu":
				var mode = String(data.get("mode", "2v2"))
				_social_status("Your party leader started a " + String(GAME_MODES.get(mode, {"label": mode})["label"]) + " queue.")
				_on_find_match_pressed(mode, true)

func _social_tick(dt: float, now: int) -> void :
	if not social_linger.is_empty():
		social_linger["t"] = float(social_linger["t"]) - dt
		if float(social_linger["t"]) <= 0.0:
			var L = social_linger
			social_linger = {}
			if String(L["kind"]) == "challenge":
				_start_challenge_match(L["roster"], String(L["room"]))
			else:
				_on_find_match_pressed(String(L["mode"]), true)
			return
	if not challenge_out.is_empty() and now - int(challenge_out["ms"]) > SOCIAL_REQUEST_TIMEOUT_MS + 3000:
		send_p2p_packet({"action": "ch_cancel", "to": challenge_out["to"], "cid": challenge_out["cid"]})
		_social_status(String(challenge_out["nick"]) + " didn't answer your challenge.")
		challenge_out = {}
	for c in challenge_in.duplicate():
		if now - int(c["ms"]) > SOCIAL_REQUEST_TIMEOUT_MS:
			send_p2p_packet({"action": "ch_reply", "to": c["from"], "cid": c["cid"], "accept": false})
			challenge_in.erase(c)
			social_dirty = true
	for i in party_invites_in.duplicate():
		if now - int(i["ms"]) > SOCIAL_REQUEST_TIMEOUT_MS:
			send_p2p_packet({"action": "pt_reply", "to": i["from"], "pid": i["pid"], "accept": false, "nick": local_nickname})
			party_invites_in.erase(i)
			social_dirty = true
	if party_code_joining != "" and now - party_code_join_ms > PARTY_CODE_WAIT_MS:
		_social_status("No party found with code " + party_code_joining + ". Check the code (its leader has to be on the main menu).")
		party_code_joining = ""
	if party_joining != "" and now - party_joining_ms > 10000:
		party_joining = ""
		_social_status("Couldn't join that party - the leader may have left the menu.")
	for tid in party_invites_out.keys():
		if now - int(party_invites_out[tid]) > SOCIAL_REQUEST_TIMEOUT_MS + 3000:
			party_invites_out.erase(tid)
			lb_ui_dirty = true
	if _in_party():
		if not _is_party_leader() and now - party_leader_heard_ms > PARTY_PRUNE_MS:
			party_id = ""
			party_leader = ""
			party_members = []
			party_code = ""
			_social_status("Lost contact with your party leader - you've left the party.")
		elif _is_party_leader():
			var removed = false
			for m in party_members.duplicate():
				var tid2 = String(m[0])
				if tid2 != mm_self_id and now - int(last_heard.get(tid2, now)) > PARTY_PRUNE_MS:
					party_members.erase(m)
					removed = true
			if removed:
				_party_send_state(true)
				_social_status("A party member was away too long and was removed.")
	social_ui_timer -= dt
	if social_ui_timer <= 0.0 or social_dirty:
		social_ui_timer = 1.0
		social_dirty = false
		_refresh_popup()
		_fill_party_panel()

# Leaving the menu (queueing, practice, a challenge): answer anything pending.
func _social_leave_menu() -> void :
	for c in challenge_in:
		send_p2p_packet({"action": "ch_reply", "to": c["from"], "cid": c["cid"], "accept": false})
	challenge_in.clear()
	for i in party_invites_in:
		send_p2p_packet({"action": "pt_reply", "to": i["from"], "pid": i["pid"], "accept": false, "nick": local_nickname})
	party_invites_in.clear()
	if not challenge_out.is_empty():
		send_p2p_packet({"action": "ch_cancel", "to": challenge_out["to"], "cid": challenge_out["cid"]})
		challenge_out = {}
	party_invites_out.clear()
	party_code_joining = ""
	social_linger = {}
	_hide_popup()

# ----- popup (top of the screen on any menu page) -----

func _hide_popup() -> void :
	if popup_canvas:
		popup_canvas.queue_free()
		popup_canvas = null
	popup_key = ""
	popup_sub_label = null

func _refresh_popup() -> void :
	if mm_phase != "menu" or (challenge_in.is_empty() and party_invites_in.is_empty()):
		_hide_popup()
		return
	var is_challenge = not challenge_in.is_empty()
	var item = challenge_in[0] if is_challenge else party_invites_in[0]
	var key = ("ch:" + String(item["cid"])) if is_challenge else ("pt:" + String(item["pid"]))
	var left = int(ceil(max(SOCIAL_REQUEST_TIMEOUT_MS - (_now_ms() - int(item["ms"])), 0) / 1000.0))
	var sub_text = ("Accept to start the match right away." if is_challenge else "You'll queue together when the leader picks a mode.") + "  (" + str(left) + "s)"
	if popup_canvas and popup_key == key and is_instance_valid(popup_sub_label):
		popup_sub_label.text = sub_text # same request: just tick the countdown
		return
	if not popup_canvas:
		popup_canvas = CanvasLayer.new()
		popup_canvas.layer = 110
		add_child(popup_canvas)
	for c in popup_canvas.get_children():
		c.queue_free()
	popup_key = key

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-230, 60)
	panel.custom_minimum_size = Vector2(460, 0)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.16, 0.96)
	sb.border_color = Color(1.0, 0.85, 0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	popup_canvas.add_child(panel)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var msg = Label.new()
	if is_challenge:
		msg.text = String(item["nick"]) + " challenges you to a 1v1!"
	else:
		msg.text = String(item["nick"]) + " invited you to their party (" + str(int(item["size"])) + "/" + str(PARTY_MAX) + ")."
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 17)
	msg.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vb.add_child(msg)
	popup_sub_label = Label.new()
	popup_sub_label.text = sub_text
	popup_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_sub_label.add_theme_font_size_override("font_size", 12)
	vb.add_child(popup_sub_label)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var acc = Button.new()
	acc.text = "Accept"
	acc.custom_minimum_size = Vector2(140, 40)
	var dec = Button.new()
	dec.text = "Decline"
	dec.custom_minimum_size = Vector2(140, 40)
	if is_challenge:
		var cid = String(item["cid"])
		acc.pressed.connect( func(): _answer_challenge(cid, true))
		dec.pressed.connect( func(): _answer_challenge(cid, false))
	else:
		var pid = String(item["pid"])
		acc.pressed.connect( func(): _answer_party_invite(pid, true))
		dec.pressed.connect( func(): _answer_party_invite(pid, false))
	row.add_child(acc)
	row.add_child(dec)

# ----- rank panel (middle-left of the main menu) -----
# Previous rank on the left, your rank in the middle, next rank on the right,
# and the same progress bar as the end-of-match screen.

func _rank_color(i: int) -> Color:
	return RANK_FAMILY_COLORS[clamp(i, 0, RANK_COUNT - 1) / 3]

func _rank_progress(elo: int) -> float:
	if elo >= MAX_ELO:
		return 1.0
	var base = rank_index(elo) * 100
	var top = MAX_ELO if rank_index(elo) == RANK_COUNT - 1 else base + 100
	return clamp(float(elo - base) / float(top - base), 0.0, 1.0)

func _rank_slot(caption: String, idx: int, icon_size: float, is_current: bool, placeholder: String) -> VBoxContainer:
	var w = icon_size + (18.0 if is_current else 8.0)
	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size = Vector2(w, 0)
	var cap = Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	box.add_child(cap)
	if placeholder != "":
		var ph = Label.new()
		ph.name = "Placeholder"
		ph.text = placeholder
		ph.custom_minimum_size = Vector2(w, icon_size)
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.add_theme_font_size_override("font_size", 12)
		ph.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		box.add_child(ph)
		var blank = Label.new()
		blank.text = " "
		blank.add_theme_font_size_override("font_size", 10)
		box.add_child(blank)
		return box
	var icon_holder = CenterContainer.new()
	icon_holder.custom_minimum_size = Vector2(w, icon_size)
	box.add_child(icon_holder)
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.texture = rank_texture_by_index(idx)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	if not is_current:
		icon.modulate = Color(1, 1, 1, 0.7)
	icon_holder.add_child(icon)
	var nm = Label.new()
	nm.name = "RankName"
	nm.text = rank_name_by_index(idx)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(w, 0)
	nm.add_theme_font_size_override("font_size", 13 if is_current else 10)
	nm.add_theme_color_override("font_color", _rank_color(idx) if is_current else _rank_color(idx).darkened(0.15))
	box.add_child(nm)
	return box

func _build_rank_panel() -> void :
	# Full-height strip on the left that centers the panel vertically.
	var strip = VBoxContainer.new()
	strip.anchor_left = 0.0
	strip.anchor_right = 0.0
	strip.anchor_top = 0.0
	strip.anchor_bottom = 1.0
	strip.offset_left = 12.0
	strip.offset_right = 12.0 + rank_panel_w
	strip.offset_top = 8.0
	strip.offset_bottom = -8.0
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_canvas.add_child(strip)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(rank_panel_w, 0)
	# Same dark color as the sprite sheet's background, so the icons blend in.
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color8(14, 17, 19, 250)
	sb.border_color = Color(0.32, 0.32, 0.38)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	strip.add_child(panel)
	rank_panel_box = VBoxContainer.new()
	rank_panel_box.add_theme_constant_override("separation", 6)
	panel.add_child(rank_panel_box)

	var idx = rank_index(local_elo)
	var inner = rank_panel_w - 18.0
	var big = clamp(inner * 0.4, 40.0, 92.0)
	var small = clamp(inner * 0.24, 26.0, 56.0)

	# Title, with a button in the top-right corner that lists every rank.
	var title_row = HBoxContainer.new()
	rank_panel_box.add_child(title_row)
	var ranks_btn = Button.new()
	ranks_btn.name = "AllRanksButton"
	ranks_btn.text = "All Ranks"
	ranks_btn.tooltip_text = "See every rank and how far away it is"
	ranks_btn.add_theme_font_size_override("font_size", 10 if rank_panel_w < 200.0 else 11)
	ranks_btn.pressed.connect(_show_all_ranks_ui)
	var spacer = Control.new() # balances the button so the title stays centered
	title_row.add_child(spacer)
	var title = Label.new()
	title.text = "YOUR RANK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 18 if rank_panel_w >= 200.0 else 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	title_row.add_child(title)
	title_row.add_child(ranks_btn)
	spacer.custom_minimum_size = Vector2(ranks_btn.get_combined_minimum_size().x, 0)

	var row = HBoxContainer.new()
	row.name = "RankRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	rank_panel_box.add_child(row)
	var prev = _rank_slot("Previous", idx - 1, small, false, "Lowest Rank" if idx == 0 else "")
	prev.name = "Prev"
	row.add_child(prev)
	var cur = _rank_slot("Current", idx, big, true, "")
	cur.name = "Current"
	row.add_child(cur)
	var nxt = _rank_slot("Next", idx + 1, small, false, "Highest Rank" if idx == RANK_COUNT - 1 else "")
	nxt.name = "Next"
	row.add_child(nxt)

	# Progress bar (same look as the one after a match)
	var bar_w = inner
	var frac = _rank_progress(local_elo)
	var bar_bg = Panel.new()
	bar_bg.name = "Bar"
	bar_bg.custom_minimum_size = Vector2(bar_w, 20)
	rank_panel_box.add_child(bar_bg)
	var fill = ColorRect.new()
	fill.name = "Fill"
	fill.color = Color(0.2, 0.6, 0.9, 0.8)
	fill.size = Vector2(bar_w * frac, 20)
	bar_bg.add_child(fill)
	var marker = ColorRect.new()
	marker.color = Color(1.0, 0.9, 0.2, 1.0)
	marker.size = Vector2(5, 20)
	marker.position = Vector2(clamp(bar_w * frac - 2.5, 0.0, bar_w - 5.0), 0)
	bar_bg.add_child(marker)

	var ends = HBoxContainer.new()
	rank_panel_box.add_child(ends)
	var base = idx * 100
	var top = MAX_ELO if idx == RANK_COUNT - 1 else base + 100
	var l = Label.new()
	l.text = str(base) + " ELO"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 10)
	ends.add_child(l)
	var r = Label.new()
	r.text = ("Max: " if idx == RANK_COUNT - 1 else "Next: ") + str(top) + " ELO"
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("font_size", 10)
	ends.add_child(r)

	var info = Label.new()
	info.name = "Info"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(inner, 0)
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	if local_elo >= MAX_ELO:
		info.text = "MAX RANK REACHED"
		info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	elif idx == RANK_COUNT - 1:
		info.text = str(local_elo) + " ELO - " + str(MAX_ELO - local_elo) + " to the max ELO"
	else:
		info.text = str(local_elo) + " ELO - " + str(top - local_elo) + " to " + rank_name_by_index(idx + 1)
	rank_panel_box.add_child(info)

# ----- all ranks (opened from the rank panel) -----
# Every rank from lowest to highest: icon, name, the ELO it starts at, and how
# much more ELO you need to get there.
func _show_all_ranks_ui() -> void :
	_save_nickname_from_input()
	_clear_ui()
	ranks_canvas = CanvasLayer.new()
	add_child(ranks_canvas)

	var vp = get_viewport().get_visible_rect().size
	var w = clamp(vp.x - 24.0, 360.0, 640.0)
	var h = clamp(vp.y - 190.0, 120.0, 460.0)
	var narrow = w < 480.0

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ranks_canvas.add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, 0)
	var psb = StyleBoxFlat.new()
	psb.bg_color = Color8(14, 17, 19, 250) # the sprite sheet's background, so icons blend in
	psb.border_color = Color(0.32, 0.32, 0.38)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(10)
	psb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title = Label.new()
	title.text = "ALL RANKS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	box.add_child(title)
	var cur_idx = rank_index(local_elo)
	var you = Label.new()
	you.text = "You: " + str(local_elo) + " ELO - " + get_rank_name(local_elo)
	you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	you.add_theme_font_size_override("font_size", 13)
	you.add_theme_color_override("font_color", _rank_color(cur_idx))
	box.add_child(you)

	# column headings
	var head = HBoxContainer.new()
	box.add_child(head)
	var hcells = [["Rank", 0.0], ["ELO needed", 110.0 if not narrow else 80.0], ["How far", 150.0 if not narrow else 110.0]]
	for i in range(hcells.size()):
		var hl = Label.new()
		hl.text = String(hcells[i][0])
		hl.add_theme_font_size_override("font_size", 11)
		hl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
		if i == 0:
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hl.text = "      Rank"
		else:
			hl.custom_minimum_size = Vector2(float(hcells[i][1]), 0)
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(hl)

	var scroll = ScrollContainer.new()
	scroll.name = "RanksScroll"
	scroll.custom_minimum_size = Vector2(w - 20.0, h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list = VBoxContainer.new()
	list.name = "RanksList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)

	var icon_size = 40.0 if not narrow else 32.0
	var cur_row: Control = null
	for i in range(RANK_COUNT):
		var needed = i * 100
		var row = PanelContainer.new()
		row.name = "Rank%d" % i
		var rsb = StyleBoxFlat.new()
		rsb.set_corner_radius_all(6)
		rsb.set_content_margin_all(4)
		if i == cur_idx:
			rsb.bg_color = Color(1.0, 0.85, 0.2, 0.16)
			rsb.border_color = Color(1.0, 0.85, 0.2, 0.9)
			rsb.set_border_width_all(2)
			cur_row = row
		else:
			rsb.bg_color = Color(1, 1, 1, 0.035 if i % 2 == 0 else 0.0)
		row.add_theme_stylebox_override("panel", rsb)
		list.add_child(row)
		var hb = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		row.add_child(hb)

		var icon = TextureRect.new()
		icon.name = "Icon"
		icon.texture = rank_texture_by_index(i)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		if i > cur_idx:
			icon.modulate = Color(1, 1, 1, 0.75) # not reached yet
		hb.add_child(icon)

		var nm = Label.new()
		nm.name = "Name"
		nm.text = rank_name_by_index(i)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.add_theme_font_size_override("font_size", 16 if not narrow else 13)
		nm.add_theme_color_override("font_color", _rank_color(i))
		hb.add_child(nm)

		var need_lbl = Label.new()
		need_lbl.name = "Needed"
		need_lbl.text = str(needed) + " ELO"
		need_lbl.custom_minimum_size = Vector2(110.0 if not narrow else 80.0, 0)
		need_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		need_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		need_lbl.add_theme_font_size_override("font_size", 14 if not narrow else 12)
		hb.add_child(need_lbl)

		var st = Label.new()
		st.name = "Status"
		st.custom_minimum_size = Vector2(150.0 if not narrow else 110.0, 0)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		st.add_theme_font_size_override("font_size", 13 if not narrow else 11)
		if i == cur_idx:
			st.text = "You're here"
			st.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
		elif i < cur_idx:
			st.text = "Reached"
			st.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
		else:
			st.text = str(needed - local_elo) + " ELO to go"
			st.add_theme_color_override("font_color", Color(0.6, 0.82, 1.0))
		hb.add_child(st)

	var foot = Label.new()
	foot.text = "Max ELO: " + str(MAX_ELO) + "   (every rank is 100 ELO)"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	box.add_child(foot)

	var back = Button.new()
	back.text = "Back to Menu"
	back.custom_minimum_size = Vector2(220, 38)
	back.pressed.connect(_build_main_menu)
	var back_row = CenterContainer.new()
	back_row.add_child(back)
	box.add_child(back_row)

	if cur_row:
		_scroll_ranks_to(scroll, cur_row)

# Opens the list scrolled to your rank (once the layout has been worked out).
func _scroll_ranks_to(scroll: ScrollContainer, row: Control) -> void :
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(row):
		var target = row.position.y - (scroll.size.y - row.size.y) * 0.5
		scroll.scroll_vertical = int(max(target, 0.0))

# ----- party panel (middle-right of the main menu) -----

func _build_party_panel() -> void :
	# Rank panel on the left, party panel on the right. On narrow (phone)
	# screens both get narrower and the menu sits between them.
	var vp = get_viewport().get_visible_rect().size
	party_panel_w = 265.0
	rank_panel_w = 240.0
	if (vp.x - 380.0) / 2.0 - 24.0 < party_panel_w:
		# The party panel has more in it, so it gets the bigger share.
		var avail = vp.x - 380.0 - 32.0
		party_panel_w = clamp(avail * 0.58, 150.0, 265.0)
		rank_panel_w = clamp(avail - party_panel_w, 120.0, 240.0)
		var menu_center = menu_canvas.get_child(0) if menu_canvas.get_child_count() > 0 else null
		if menu_center is Control:
			menu_center.offset_left = rank_panel_w + 16.0
			menu_center.offset_right = -(party_panel_w + 16.0)
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.position = Vector2(-(party_panel_w + 12.0), -min(200.0, vp.y * 0.5 - 8.0))
	panel.custom_minimum_size = Vector2(party_panel_w, 0)
	menu_canvas.add_child(panel)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	if vp.y < 600.0:
		# Short screen: the panel scrolls instead of running off the bottom.
		var sc = ScrollContainer.new()
		sc.custom_minimum_size = Vector2(party_panel_w, vp.y - 16.0)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(sc)
		outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(outer)
	else:
		panel.add_child(outer)
	party_panel_box = VBoxContainer.new()
	party_panel_box.add_theme_constant_override("separation", 6)
	outer.add_child(party_panel_box)
	party_panel_sig = ""
	_fill_party_panel()

	# Join with a code (kept outside the refreshing part so typing isn't interrupted)
	outer.add_child(HSeparator.new())
	var jl = Label.new()
	jl.text = "Have a party code?"
	jl.add_theme_font_size_override("font_size", 12)
	outer.add_child(jl)
	var jrow = HBoxContainer.new()
	outer.add_child(jrow)
	party_code_input = LineEdit.new()
	party_code_input.placeholder_text = "6-digit code"
	party_code_input.max_length = 6
	party_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	party_code_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	party_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_code_input.text_changed.connect(_on_party_code_typed)
	party_code_input.text_submitted.connect( func(t): _join_party_code(t))
	jrow.add_child(party_code_input)
	var jb = Button.new()
	jb.text = "Join"
	jb.custom_minimum_size = Vector2(64, 0)
	jb.pressed.connect( func(): _join_party_code(party_code_input.text if party_code_input else ""))
	jrow.add_child(jb)
	_osk_prep(party_code_input)

	# Direct connect, for Wi-Fi that blocks the relay servers
	outer.add_child(HSeparator.new())
	var dlab = Label.new()
	dlab.text = "Relay servers blocked?"
	dlab.add_theme_font_size_override("font_size", 12)
	outer.add_child(dlab)
	var dbtn = Button.new()
	dbtn.text = "Get join code"
	dbtn.custom_minimum_size = Vector2(0, 34)
	dbtn.pressed.connect(_open_direct_panel)
	outer.add_child(dbtn)
	dc_party_label = Label.new()
	dc_party_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dc_party_label.custom_minimum_size = Vector2(party_panel_w - 20.0, 0)
	dc_party_label.add_theme_font_size_override("font_size", 11)
	dc_party_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	dc_party_label.visible = false
	outer.add_child(dc_party_label)
	_dc_refresh()

func _fill_party_panel() -> void :
	if not party_panel_box:
		return
	# Only rebuild when something shown here changed (a rebuild under the
	# cursor would eat a click).
	var online_flags: Array = []
	for m in party_members:
		online_flags.append(lb_online.has(String(m[0])))
	var inv_ids: Array = []
	for inv in party_invites_in:
		inv_ids.append(String(inv["pid"]))
	var sig = str([party_members, party_leader, party_code, inv_ids, social_status, online_flags, mm_self_id])
	if sig == party_panel_sig and party_panel_box.get_child_count() > 0:
		return
	party_panel_sig = sig
	for c in party_panel_box.get_children():
		c.queue_free()
	var title = Label.new()
	title.text = "PARTY" + ("  (" + str(party_members.size()) + "/" + str(PARTY_MAX) + ")" if _in_party() or party_code != "" else "")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	party_panel_box.add_child(title)

	if _in_party():
		for m in party_members:
			var mrow = HBoxContainer.new()
			party_panel_box.add_child(mrow)
			var l = Label.new()
			var tid = String(m[0])
			var here = lb_online.has(tid) or tid == mm_self_id
			l.text = ("* " if tid == party_leader else "   ") + String(m[1]) + (" (you)" if tid == mm_self_id else "") + ("  - leader" if tid == party_leader else "") + ("" if here else "  (not on menu)")
			l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7) if here else Color(0.65, 0.65, 0.65))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			mrow.add_child(l)
			if _is_party_leader() and not here:
				# e.g. they closed the game - so they don't block queueing.
				var rm = Button.new()
				rm.text = "Remove"
				rm.add_theme_font_size_override("font_size", 11)
				rm.pressed.connect( func(): _party_remove(tid))
				mrow.add_child(rm)
		var hint = Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(party_panel_w - 20.0, 0)
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		if _is_party_leader():
			hint.text = "You lead: pick a mode to queue your whole party (2v2 max 2, 3v3 max 3, FFA max 5)."
		else:
			hint.text = "Waiting for " + _party_nick(party_leader) + " to pick a mode."
		party_panel_box.add_child(hint)
	elif party_code != "":
		var solo = Label.new()
		solo.text = "Just you so far - share your code, or invite online players from the Leaderboard."
		solo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		solo.custom_minimum_size = Vector2(party_panel_w - 20.0, 0)
		solo.add_theme_font_size_override("font_size", 12)
		party_panel_box.add_child(solo)
	else:
		var none = Label.new()
		none.text = "You're not in a party.\nInvite online players from the Leaderboard."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(party_panel_w - 20.0, 0)
		none.add_theme_font_size_override("font_size", 12)
		party_panel_box.add_child(none)

	# Party code
	if party_code != "":
		var code_row = HBoxContainer.new()
		party_panel_box.add_child(code_row)
		var cl = Label.new()
		cl.text = "Code: " + party_code
		cl.add_theme_font_size_override("font_size", 18 if party_panel_w >= 240.0 else 15)
		cl.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_row.add_child(cl)
		var cp = Button.new()
		cp.text = "Copy"
		cp.add_theme_font_size_override("font_size", 12)
		cp.pressed.connect(_copy_party_code)
		code_row.add_child(cp)
		if _is_party_leader():
			var nb = Button.new()
			nb.text = "New"
			nb.tooltip_text = "Make a new code (the old one stops working)"
			nb.add_theme_font_size_override("font_size", 12)
			nb.pressed.connect(_create_party_code)
			code_row.add_child(nb)
	elif not _in_party() or _is_party_leader():
		var mkc = Button.new()
		mkc.text = "Create Party Code"
		mkc.custom_minimum_size = Vector2(0, 32)
		mkc.pressed.connect(_create_party_code)
		party_panel_box.add_child(mkc)

	if not party_invites_in.is_empty():
		var inv_title = Label.new()
		inv_title.text = "Invitations:"
		inv_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		party_panel_box.add_child(inv_title)
		for inv in party_invites_in:
			var row = HBoxContainer.new()
			party_panel_box.add_child(row)
			var nl = Label.new()
			nl.text = String(inv["nick"])
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nl)
			var pid = String(inv["pid"])
			var a = Button.new()
			a.text = "Accept"
			a.pressed.connect( func(): _answer_party_invite(pid, true))
			row.add_child(a)
			var d = Button.new()
			d.text = "Decline"
			d.pressed.connect( func(): _answer_party_invite(pid, false))
			row.add_child(d)

	if _in_party():
		var leave = Button.new()
		leave.text = "Leave Party"
		leave.custom_minimum_size = Vector2(0, 34)
		leave.pressed.connect( func(): _party_leave())
		party_panel_box.add_child(leave)

	if social_status != "":
		var st = Label.new()
		st.text = social_status
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size = Vector2(party_panel_w - 20.0, 0)
		st.add_theme_font_size_override("font_size", 11)
		st.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
		party_panel_box.add_child(st)


# --- ADMIN COMMANDS (browser console) ---
# Open the browser's developer console (F12) while the game is running and
# type el_comando_el_listo for the list. Every command also works as text:
# hussle("set elo 1500"). (The console runs JavaScript, so a phrase with
# spaces has to go inside hussle("...").)

const ADMIN_JS: String = """
(function () {
	var run = function (t) { if (window._hussleAdmin) { window._hussleAdmin(String(t)); } };
	window.hussle = function (t) { run(t === undefined ? 'el comando el listo' : t); };
	try {
		Object.defineProperty(window, 'el_comando_el_listo', { configurable: true, get: function () { run('el comando el listo'); } });
	} catch (e) {}
	var arg = function (v) { return v === undefined ? '' : String(v); };
	window.setElo = function (n) { run('set elo ' + arg(n)); };
	window.addElo = function (n) { run('add elo ' + arg(n)); };
	window.setNick = function (s) { run('set nick ' + arg(s)); };
	window.setColor = function (h) { run('set color ' + arg(h)); };
	window.setPartColor = function (p, h) { run('set part color ' + arg(p) + ' ' + arg(h)); };
	window.resetPartColors = function () { run('reset part colors'); };
	window.matchmake = function (m) { run('matchmake ' + arg(m)); };
	window.practice = function (l) { run('practice ' + arg(l)); };
	window.mainMenu = function (force) { run(force ? 'menu force' : 'menu'); };
	window.gameStatus = function () { run('status'); };
	window.onlinePlayers = function () { run('online'); };
	window.challenge = function (n) { run('challenge ' + arg(n)); };
	window.invite = function (n) { run('invite ' + arg(n)); };
	window.partyCode = function () { run('party code'); };
	window.joinParty = function (c) { run('join party ' + arg(c)); };
	window.leaveParty = function () { run('leave party'); };
	window.setControls = function (m) { run('controls ' + arg(m)); };
	window.giveCrystal = function (t) { run('give crystal ' + arg(t)); };
	window.heal = function () { run('heal'); };
	window.clearLeaderboard = function () { run('clear leaderboard'); };
	console.log('%cHussle%c admin commands ready - type el_comando_el_listo to see them.', 'color:#ffd400;font-weight:bold', 'color:inherit');
})();
"""

func _init_admin_console() -> void :
	if not OS.has_feature("web"):
		return
	js_admin_cb = JavaScriptBridge.create_callback(_on_js_admin)
	var window = JavaScriptBridge.get_interface("window")
	window._hussleAdmin = js_admin_cb
	JavaScriptBridge.eval(ADMIN_JS, true)

func _on_js_admin(args: Array) -> void :
	var text = String(args[0]) if args.size() > 0 else ""
	_admin_print(admin_command(text))

func _admin_print(text: String) -> void :
	if OS.has_feature("web"):
		var console = JavaScriptBridge.get_interface("console")
		if console:
			console.log(text)
	else:
		print(text)

func _admin_help() -> String:
	var lines: Array = [
		"===================== HUSSLE ADMIN COMMANDS =====================",
		"Type these here in the browser console. Each also works as text,",
		"e.g. hussle(\"set elo 1500\")  or  hussle(\"el comando el listo\").",
		"",
		"  el_comando_el_listo           show this list",
		"",
		"  YOU",
		"  setElo(1500)                  set your ELO (0-%d)" % MAX_ELO,
		"  addElo(-50)                   add to / take from your ELO",
		"  setNick(\"Name\")               change your nickname",
		"  setColor(\"#ff8800\")           color your whole character",
		"  setPartColor(\"head\", \"#00ff00\") color one part: head, torso,",
		"                                arm_l, arm_r, leg_l, leg_r",
		"  resetPartColors()             every part back to your main color",
		"  setControls(\"mobile\")         \"pc\" or \"mobile\" controls",
		"",
		"  PLAY",
		"  matchmake(\"2v2\")              queue for \"1v1\", \"2v2\", \"3v3\", \"ffa\" or \"royale\"",
		"  practice(3)                   practice vs the bot, level 1-4",
		"  mainMenu()                    back to the main menu",
		"  mainMenu(true)                ...even from a ranked match (counts as a loss)",
		"  giveCrystal(\"lunge\")          practice only: double_jump, double_damage,",
		"                                speed_boost, lunge or regen",
		"  heal()                        practice only: back to 100 HP",
		"",
		"  PLAYERS & PARTY  (on the main menu)",
		"  onlinePlayers()               who's on the main menu right now",
		"  challenge(\"Name\")             challenge a player to a 1v1",
		"  invite(\"Name\")                invite a player to your party",
		"  partyCode()                   make / show your party's code",
		"  joinParty(\"123456\")           join a party by its code",
		"  leaveParty()                  leave your party",
		"",
		"  INFO",
		"  gameStatus()                  where you are, your ELO, party, match",
		"  clearLeaderboard()            wipe your saved leaderboard",
		"=================================================================",
	]
	return "\n".join(lines)

func _admin_in_match() -> bool:
	return mm_phase == "match" or is_match_active or (map_ban_canvas != null) or (dummy_level_canvas != null) or (royale_vote_canvas != null)

func _admin_find_online(name: String) -> String:
	var want = name.strip_edges().to_lower()
	for tid in lb_online:
		if String(lb_online[tid]["nick"]).to_lower() == want:
			return tid
	return ""

func _admin_refresh_menu() -> void :
	if menu_canvas:
		_build_main_menu()
	elif color_canvas:
		_show_color_picker_ui()

func _admin_clean_hex(t: String) -> String:
	var h = t.strip_edges().trim_prefix("#").to_lower()
	if h.length() == 3:
		h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
	return h if h.length() == 6 and Color.html_is_valid(h) else ""

# Runs one admin command and returns what to print.
func admin_command(text: String) -> String:
	var raw: PackedStringArray = text.strip_edges().split(" ", false)
	var w: Array = []
	for x in raw:
		w.append(String(x).to_lower())
	var line = " ".join(w)
	if line == "" or line in ["el comando el listo", "el_comando_el_listo", "help", "commands", "?"]:
		return _admin_help()

	var first = w[0]
	# --- you ---
	if w.size() >= 2 and (first == "set" or first == "add") and w[1] == "elo":
		if w.size() < 3 or not w[2].is_valid_int():
			return "Usage: setElo(1500) / addElo(-50)"
		if _admin_in_match():
			return "Finish or leave your match first - your ELO is locked in while you play."
		var n = int(w[2])
		var new_elo = clampi(n if first == "set" else local_elo + n, 0, MAX_ELO)
		local_elo = new_elo
		save_player_data()
		_lb_set(local_nickname, local_elo)
		_save_leaderboard_cache()
		if mm_phase == "menu":
			_lb_announce()
		lb_ui_dirty = true
		_admin_refresh_menu()
		return "ELO set to %d (%s)." % [local_elo, get_rank_name(local_elo)]
	if w.size() >= 3 and first == "set" and w[1] == "nick":
		var nick = " ".join(raw.slice(2)).strip_edges().substr(0, 24)
		if nick == "":
			return "Usage: setNick(\"Name\")"
		if _admin_in_match():
			return "Change your nickname on the main menu, not during a match."
		local_nickname = nick
		save_player_data()
		_lb_set(local_nickname, local_elo)
		_save_leaderboard_cache()
		if mm_phase == "menu":
			_lb_announce()
		_admin_refresh_menu()
		return "Nickname set to \"%s\"." % nick
	if w.size() >= 2 and first == "set" and w[1] == "color":
		var hx = _admin_clean_hex(w[2] if w.size() > 2 else "")
		if hx == "":
			return "Usage: setColor(\"#ff8800\")"
		local_color_hex = hx
		local_part_colors.clear()
		save_player_data()
		_admin_refresh_menu()
		return "Whole body color set to #%s (shows from your next match)." % hx.to_upper()
	if w.size() >= 3 and first == "set" and w[1] == "part" and w[2] == "color":
		var part = w[3] if w.size() > 3 else ""
		var hx2 = _admin_clean_hex(w[4] if w.size() > 4 else "")
		if not BODY_PART_NAMES.has(part) or part == "" or hx2 == "":
			return "Usage: setPartColor(\"head\", \"#00ff00\")  - parts: head, torso, arm_l, arm_r, leg_l, leg_r"
		if hx2 == local_color_hex:
			local_part_colors.erase(part)
		else:
			local_part_colors[part] = hx2
		save_player_data()
		_admin_refresh_menu()
		return "%s color set to #%s." % [BODY_PART_NAMES[part], hx2.to_upper()]
	if line == "reset part colors":
		local_part_colors.clear()
		save_player_data()
		_admin_refresh_menu()
		return "Every part is your main color again."
	if first == "controls":
		var m = w[1] if w.size() > 1 else ""
		if m != "pc" and m != "mobile":
			return "Usage: setControls(\"pc\") or setControls(\"mobile\")"
		_set_controls(m == "mobile")
		_admin_refresh_menu()
		return "Controls set to %s%s." % [m.to_upper() if m == "pc" else "Mobile", " (applies from your next match)" if is_match_active else ""]

	# --- play ---
	if first == "matchmake" or first == "queue":
		var mode = w[1] if w.size() > 1 else ""
		if mode in ["free", "freeforall", "free-for-all"]:
			mode = "ffa"
		if not GAME_MODES.has(mode):
			return "Usage: matchmake(\"1v1\") - modes: 1v1, 2v2, 3v3, ffa, royale"
		if _admin_in_match():
			return "You're in a match - use mainMenu() first."
		if _in_party():
			var err = _party_queue_error(mode)
			if err != "":
				return err
		call_deferred("_on_find_match_pressed", mode)
		return "Queueing for %s%s..." % [GAME_MODES[mode]["label"], " with your party" if _in_party() else ""]
	if first == "practice":
		var lvl = 0
		if w.size() > 1:
			if not w[1].is_valid_int() or int(w[1]) < 1 or int(w[1]) > DUMMY_LEVELS.size():
				return "Usage: practice(3) - levels 1-%d" % DUMMY_LEVELS.size()
			lvl = int(w[1])
		if _admin_in_match() and not is_single_player:
			return "You're in a match - use mainMenu() first."
		admin_pending_level = lvl
		call_deferred("_admin_start_practice")
		return "Starting practice" + (" vs a level %d bot" % lvl if lvl > 0 else "") + " (ban a map, then play)."
	if first == "menu":
		var force = w.size() > 1 and w[1] == "force"
		if is_match_active and not is_game_over and not is_single_player:
			if not force:
				return "You're in a ranked match - leaving counts as a loss. Use mainMenu(true) to leave anyway."
			call_deferred("_forfeit_match")
			return "Leaving the match (counted as a loss)..."
		call_deferred("_return_to_main_menu")
		return "Back to the main menu."
	if first == "give" and w.size() >= 2 and w[1] == "crystal":
		var ab = w[2] if w.size() > 2 else ""
		if not CRYSTAL_ABILITIES.has(ab) and ab != "regen":
			return "Usage: giveCrystal(\"lunge\") - double_jump, double_damage, speed_boost, lunge, regen"
		if not (is_single_player and is_match_active and not is_game_over):
			return "giveCrystal only works in practice (it would be cheating in a real match)."
		if ab == "regen":
			var rme = get_local_player()
			var amt = 0
			if rme:
				amt = min(REGEN_HEAL, 100 - rme.health)
				_apply_heal(local_peer_id, amt)
			return "Regen: +%d HP." % amt if amt > 0 else "Regen: you're already at full health."
		_give_local_ability(ab)
		return "You got %s." % CRYSTAL_ABILITIES[ab]["name"]
	if first == "heal":
		var me = get_local_player()
		if not (is_single_player and is_match_active and not is_game_over) or me == null:
			return "heal only works in practice."
		me.health = 100
		return "Back to 100 HP."

	# --- players & party ---
	if first == "online":
		if mm_phase != "menu":
			return "Go to the main menu to see who's online."
		var names: Array = []
		for tid in lb_online:
			names.append("  %s - %d ELO" % [lb_online[tid]["nick"], int(lb_online[tid]["elo"])])
		names.sort()
		return ("%d other player(s) on the main menu:\n" % names.size() + "\n".join(names)) if not names.is_empty() else "Nobody else is on the main menu right now."
	if first == "challenge" or first == "invite":
		var who = " ".join(raw.slice(1)).strip_edges()
		if who == "":
			return "Usage: %s(\"Name\")" % first
		if mm_phase != "menu":
			return "Go to the main menu first."
		var tid2 = _admin_find_online(who)
		if tid2 == "":
			return "\"%s\" isn't on the main menu right now (see onlinePlayers())." % who
		var real = String(lb_online[tid2]["nick"])
		if first == "challenge":
			_challenge_player(tid2, real)
		else:
			_invite_to_party(tid2, real)
		return social_status if social_status != "" else "Sent."
	if line == "party code":
		if mm_phase != "menu":
			return "Go to the main menu first."
		if party_code == "":
			_create_party_code()
		return ("Your party code: " + party_code) if party_code != "" else social_status
	if w.size() >= 2 and first == "join" and w[1] == "party":
		if mm_phase != "menu":
			return "Go to the main menu first."
		_join_party_code(w[2] if w.size() > 2 else "")
		return social_status
	if line == "leave party":
		if party_id == "":
			return "You're not in a party."
		_party_leave()
		return "You left the party."

	# --- info ---
	if first == "status":
		return _admin_status()
	if line == "clear leaderboard":
		clear_leaderboard_data()
		_admin_refresh_menu()
		return "Leaderboard cleared."
	return "Unknown command \"%s\". Type el_comando_el_listo for the list." % text.strip_edges()

func _admin_start_practice() -> void :
	if mm_phase == "lobby" or is_match_active:
		_return_to_main_menu()
	_on_single_player_pressed()

func _admin_status() -> String:
	var where = "main menu"
	match mm_phase:
		"lobby":
			where = "queueing for " + String(GAME_MODES.get(game_mode, {"label": game_mode})["label"])
		"match":
			where = "in a " + String(GAME_MODES.get(game_mode, {"label": game_mode})["label"]) + " match" + (" (map ban)" if map_ban_canvas else "")
		"idle":
			where = "practice" if is_single_player and is_match_active else "offline / between screens"
	var out: Array = [
		"Player:   %s  (%d ELO, %s)" % [local_nickname, local_elo, get_rank_name(local_elo)],
		"Where:    " + where,
		"Controls: " + ("Mobile" if mobile_controls else "PC"),
		"Color:    #%s%s" % [local_color_hex.to_upper(), "" if local_part_colors.is_empty() else "  + %d colored part(s)" % local_part_colors.size()],
	]
	if party_id != "" and party_members.size() > 0:
		var names: Array = []
		for m in party_members:
			names.append(String(m[1]) + (" (leader)" if String(m[0]) == party_leader else ""))
		out.append("Party:    " + ", ".join(names) + ("   code " + party_code if party_code != "" else ""))
	if mm_phase == "menu":
		out.append("Online:   %d other player(s) on the main menu" % lb_online.size())
	if is_match_active and not is_single_player:
		var ps: Array = []
		for pid in all_player_ids():
			ps.append("%s%s" % [player_nicknames.get(pid, "?"), " (out)" if dead_peers.has(pid) else ""])
		out.append("Match:    %s on %s - %s" % [game_mode, selected_map_data.get("name", "?"), ", ".join(ps)])
	elif is_single_player and is_match_active:
		out.append("Practice: level %d bot on %s" % [dummy_level, selected_map_data.get("name", "?")])
	return "\n".join(out)


# --- HUSS ROYALE ---
# 4-15 players on one big map (Huss Island), everyone for themselves, last one
# standing wins (ELO by placement, like Free For All). No map vote. Swords and
# shields lie around the map: a sword adds +5 to your hits, a shield takes 5
# off every hit you take. You can carry one of each.
# Items are host-authoritative like crystals: the host decides what spawns
# where and who got it.

func _royale_spawn_points() -> Array:
	match String(selected_map_data.get("mechanic", "royale")):
		"moon":
			return _moon_spawn_points()
		"wasteland":
			return _waste_spawn_points()
		"desert":
			return _desert_spawn_points()
	return _huss_spawn_points()

func _huss_spawn_points() -> Array:
	var out: Array = []
	for i in range(ROYALE_MAX_PLAYERS):
		var a = TAU * float(i) / float(ROYALE_MAX_PLAYERS) + 0.21
		out.append(Vector3(cos(a) * ROYALE_SPAWN_RADIUS, 1.0, sin(a) * ROYALE_SPAWN_RADIUS))
	return out

# Where swords and shields can appear (each one floats ~1m above the ground).
func _royale_weapon_spots() -> Array:
	match String(selected_map_data.get("mechanic", "royale")):
		"moon":
			return _moon_weapon_spots()
		"wasteland":
			return _waste_weapon_spots()
		"desert":
			return _desert_weapon_spots()
	return _huss_weapon_spots()

func _huss_weapon_spots() -> Array:
	var spots: Array = []
	for sx in [-5.0, 5.0]:
		for sz in [-5.0, 5.0]:
			spots.append(Vector3(sx, 4.0, sz)) # plaza top
	spots.append(Vector3(0, 11.0, 0)) # lookout tower top
	for h in _royale_houses():
		var c: Vector3 = h[0]
		var along_x: bool = h[1]
		for d in [-3.0, 3.0]:
			spots.append(c + (Vector3(0, 1, d) if along_x else Vector3(d, 1, 0)))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			spots.append(Vector3(sx * 52.0, 6.0, sz * 52.0)) # corner tower tops
			spots.append(Vector3(sx * 11.5, 1.0, sz * 11.5)) # beside the plaza
	for i in range(8):
		var a = TAU * float(i) / 8.0
		spots.append(Vector3(cos(a) * 23.0, 1.0, sin(a) * 23.0)) # between the pillars
	for i in range(12):
		var a2 = TAU * (float(i) + 0.5) / 12.0
		spots.append(Vector3(cos(a2) * 47.0, 1.0, sin(a2) * 47.0)) # the open field
	return spots

# Where crystals can appear: rings across the island, inside the houses and
# on the plaza.
func _royale_crystal_spots() -> Array:
	match String(selected_map_data.get("mechanic", "royale")):
		"moon":
			return _moon_crystal_spots()
		"wasteland":
			return _waste_crystal_spots()
		"desert":
			return _desert_crystal_spots()
	return _huss_crystal_spots()

# Spots for a map's own special items (Desert: treasure + the Genie).
func _royale_special_spots() -> Array:
	match String(selected_map_data.get("mechanic", "royale")):
		"desert":
			return _desert_special_spots()
		"moon":
			return _moon_special_spots()
	return []

var royale_weapon_count_cache: int = -1
var royale_crystal_count_cache: int = -1

# Item spots: [weapons][crystals][special]
func _royale_special_start() -> int:
	_royale_item_spots()
	return royale_weapon_count_cache + royale_crystal_count_cache

func _huss_crystal_spots() -> Array:
	var out: Array = []
	for i in range(8):
		var a = TAU * (float(i) + 0.5) / 8.0
		out.append(Vector3(cos(a) * 30.0, 1.0, sin(a) * 30.0))
	for i in range(8):
		var a2 = TAU * float(i) / 8.0 + 0.2
		out.append(Vector3(cos(a2) * 58.0, 1.0, sin(a2) * 58.0))
	for h in _royale_houses():
		out.append(h[0] + Vector3(0, 1, 0))
	for d in [Vector3(0, 0, 6.5), Vector3(0, 0, -6.5), Vector3(6.5, 0, 0), Vector3(-6.5, 0, 0)]:
		out.append(d + Vector3(0, 4.0, 0))
	return out

# Every spot an item can appear at: the weapon spots, then the crystal spots.
var royale_spots_map: String = ""

func _royale_item_spots() -> Array:
	if royale_spots_cache.is_empty() or royale_spots_map != String(selected_map_data.get("name", "")):
		royale_spots_map = String(selected_map_data.get("name", ""))
		var w = _royale_weapon_spots()
		var c = _royale_crystal_spots()
		royale_weapon_count_cache = w.size()
		royale_crystal_count_cache = c.size()
		royale_spots_cache = w + c + _royale_special_spots()
	return royale_spots_cache

func _royale_weapon_spot_count() -> int:
	_royale_item_spots()
	return royale_weapon_count_cache

func _is_weapon(type: String) -> bool:
	return GEAR.has(type)

func _is_royale_crystal(type: String) -> bool:
	return type == "regen" or CRYSTAL_ABILITIES.has(type)

# [center, wall runs along x (doorways face +-x)]
func _royale_houses() -> Array:
	return [[Vector3(0, 0, -36), false], [Vector3(0, 0, 36), false], [Vector3(-36, 0, 0), true], [Vector3(36, 0, 0), true]]

func _create_slab(pos: Vector3, size: Vector3, rot_deg: Vector3, color: Color) -> void :
	var body = StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(mi)
	body.add_child(col)
	world_root.add_child(body)

func _build_royale_map(wall_color: Color) -> void :
	royale_ladders.clear()
	var stone = wall_color
	var dark = wall_color.darkened(0.3)
	var wood = Color(0.55, 0.38, 0.22)
	# Center plaza: a raised square, a ramp on each side, a lookout tower.
	_create_wall_block(Vector3(0, 1.5, 0), Vector3(18, 3, 18), stone)
	var run = 10.0
	var rise = 3.0
	var ang = rad_to_deg(atan2(rise, run))
	var length = sqrt(run * run + rise * rise)
	_create_slab(Vector3(0, 1.25, -9.0 - run / 2.0), Vector3(6, 0.5, length), Vector3(-ang, 0, 0), dark)
	_create_slab(Vector3(0, 1.25, 9.0 + run / 2.0), Vector3(6, 0.5, length), Vector3(ang, 0, 0), dark)
	_create_slab(Vector3(9.0 + run / 2.0, 1.25, 0), Vector3(length, 0.5, 6), Vector3(0, 0, -ang), dark)
	_create_slab(Vector3(-9.0 - run / 2.0, 1.25, 0), Vector3(length, 0.5, 6), Vector3(0, 0, ang), dark)
	_create_wall_block(Vector3(0, 6.5, 0), Vector3(4, 7, 4), dark)
	# A ladder up the tower on each of its four sides.
	_create_ladder(Vector3(0, 3.0, -2.0), Vector3(0, 0, -1), 7.0)
	_create_ladder(Vector3(0, 3.0, 2.0), Vector3(0, 0, 1), 7.0)
	_create_ladder(Vector3(2.0, 3.0, 0), Vector3(1, 0, 0), 7.0)
	_create_ladder(Vector3(-2.0, 3.0, 0), Vector3(-1, 0, 0), 7.0)

	# A ring of pillars around the plaza to hide behind.
	for i in range(8):
		var a = TAU * (float(i) + 0.5) / 8.0
		_create_wall_block(Vector3(cos(a) * 23.0, 2.0, sin(a) * 23.0), Vector3(2.2, 4, 2.2), stone)

	# Four roofless houses, 36m out on each axis, with a doorway front and back.
	for h in _royale_houses():
		var c: Vector3 = h[0]
		var along_x: bool = h[1]
		var hh = 3.5
		for side in [-6.0, 6.0]:
			# solid side walls
			if along_x:
				_create_wall_block(c + Vector3(0, hh / 2.0, side), Vector3(12.6, hh, 0.6), wood)
			else:
				_create_wall_block(c + Vector3(side, hh / 2.0, 0), Vector3(0.6, hh, 12.6), wood)
			# front/back walls with a 3m doorway in the middle
			for half in [-3.75, 3.75]:
				if along_x:
					_create_wall_block(c + Vector3(side, hh / 2.0, half), Vector3(0.6, hh, 4.5), wood)
				else:
					_create_wall_block(c + Vector3(half, hh / 2.0, side), Vector3(4.5, hh, 0.6), wood)

	# Corner towers: 5m platforms with a ladder facing the middle.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_create_wall_block(Vector3(sx * 52.0, 2.5, sz * 52.0), Vector3(9, 5, 9), stone)
			_create_ladder(Vector3(sx * 47.5, 0, sz * 52.0), Vector3(-sx, 0, 0), 5.0)

	# Crates between the houses and the towers.
	for i in range(8):
		var a = TAU * (float(i) + 0.5) / 8.0
		var p = Vector3(cos(a) * 40.0, 1.25, sin(a) * 40.0)
		var side_dir = Vector3(-sin(a), 0, cos(a))
		_create_wall_block(p, Vector3(2.5, 2.5, 2.5), wood)
		_create_wall_block(p + side_dir * 3.2 + Vector3(0, -0.5, 0), Vector3(1.5, 1.5, 1.5), wood)

	# Jump pads on the diagonals.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_create_jump_pad(Vector3(sx * 21.0, 0.2, sz * 21.0), 20.0)

func _royale_reset() -> void :
	for id in royale_item_nodes:
		var n = royale_item_nodes[id]
		if is_instance_valid(n):
			n.queue_free()
	royale_items.clear()
	royale_item_nodes.clear()
	royale_claims.clear()
	player_gear.clear()
	genie_wishes.clear()
	mobile_shoot_held = false
	mobile_use_held = false
	royale_seeded = false
	royale_item_counter = 0
	royale_item_timer = ROYALE_ITEM_RESPAWN
	royale_crystal_timer = ROYALE_CRYSTAL_WAVE_TIME
	royale_time = 0.0
	royale_bots.clear()
	royale_votes.clear()
	royale_vote_done = false
	royale_vote_packet = {}
	royale_pending_choice = {}
	royale_start_at_ms = -1
	royale_map_index = 0
	royale_seed = 0
	royale_spots_cache = []
	royale_weapon_count_cache = -1
	royale_crystal_count_cache = -1
	desert_crown = -1
	desert_crowns.clear()
	desert_crown_nav.clear()
	desert_crown_links.clear()
	desert_nav_crowns_done = false
	storm_root = null
	storm_wall = null
	storm_mm = null
	storm_parts.clear()
	storm_outside_t = 0.0
	bot_storm_t.clear()
	waste_open_exits = []
	waste_rad_t = 0.0
	waste_med_t = 0.0
	waste_flash_t = 0.0
	waste_bot_rad.clear()
	waste_bot_med.clear()
	moon_asteroids = []
	moon_pads = []
	bh_active = false
	bh_t = 0.0
	bh_by = -1
	bh_bunkers = []
	bh_fx = null
	bh_my_bunker = -1
	bh_suck = {}
	moon_storm_shell = null
	moon_storm_mat = null
	royale_bot_send_ms = -100000
	mobile_slide_held = false
	rnav = null
	rnav_ready = false
	rnav_row = -1
	rnav_ids = PackedInt64Array()

# --- HUSS ROYALE GEAR ---
# player_gear[pid] = {"melee": "sword", "shield": "shield", "ranged": "bow",
# "mask": "gasmask", "special": "blackhole", "genie": "genie", plus each held
# type -> true}. One item per slot; a better one (higher rank) replaces yours.
const GENIE_HEALTH: int = 150
const GENIE_BASE_DAMAGE: int = 40
const GENIE_SPEED: float = 2.0
const GENIE_GRAVITY: float = 0.55
var genie_wishes: Dictionary = {} # peer_id -> true once they've had a wish
var mobile_shoot_held: bool = false
var mobile_use_held: bool = false

func gear_slot(pid: int, slot: String) -> String:
	return String(gear_of(pid).get(slot, ""))

func has_genie(pid: int) -> bool:
	return gear_of(pid).has("genie")

# A punch before swords / shields: 25, or 40 with a Genie wish.
func melee_base(pid: int) -> int:
	return GENIE_BASE_DAMAGE if is_royale and has_genie(pid) else 25

# How far away you can start an attack (E): 6m, more with the Plasma Sword.
func melee_reach(pid: int) -> float:
	if not is_royale:
		return 6.0
	var m = gear_slot(pid, "melee")
	return float(GEAR[m].get("reach", 6.0)) if GEAR.has(m) else 6.0

# A player can have one Genie wish; once every player still in has had one,
# anyone can wish again.
func genie_allowed(pid: int) -> bool:
	if not genie_wishes.has(pid):
		return true
	for p in all_player_ids():
		if not dead_peers.has(p) and not genie_wishes.has(p):
			return false
	return true

func can_take_gear(pid: int, type: String) -> bool:
	if not GEAR.has(type):
		return false
	var slot = String(GEAR[type]["slot"])
	if slot == "genie":
		return genie_allowed(pid)
	var cur = gear_slot(pid, slot)
	if cur == "":
		return true
	return int(GEAR[type].get("rank", 1)) > int(GEAR.get(cur, {}).get("rank", 1))

func _gear_pickup_note(type: String) -> String:
	var g: Dictionary = GEAR.get(type, {})
	var what = String(g.get("name", type)).to_upper()
	match String(g.get("slot", "")):
		"ranged":
			return what + ": " + gear_effect_text(type) + " - " + ("tap SHOOT" if mobile_controls else "left click to shoot") + "!"
		"special":
			return what + " - " + ("tap USE" if mobile_controls else "press F") + " to unleash it: " + gear_effect_text(type) + "!"
		"genie":
			return "GENIE - your wish is granted: " + gear_effect_text(type) + "!"
	return what + " - " + gear_effect_text(type) + "!"

# Whoever fired calls this (the local player, or the host for a bot): shows
# the shot everywhere and deals the damage if it hit someone.
func royale_shot(shooter: int, type: String, from: Vector3, to: Vector3, victim: int) -> void :
	if not GEAR.has(type):
		return
	send_p2p_packet({"action": "shot", "s": shooter, "w": type, "o": [snappedf(from.x, 0.01), snappedf(from.y, 0.01), snappedf(from.z, 0.01)], "e": [snappedf(to.x, 0.01), snappedf(to.y, 0.01), snappedf(to.z, 0.01)]})
	_shot_fx(type, from, to)
	if victim <= 0:
		return
	var v = get_player(victim)
	if v == null or v.is_dead or v.gliding:
		return
	var dmg = gear_damage(shooter, victim, int(GEAR[type].get("dmg", 20)), "ranged")
	send_p2p_packet({"action": "take_damage", "peer_id": str(victim), "amount": dmg, "by": shooter, "w": type})
	if shooter == local_peer_id:
		log_console("[Royale] Hit " + String(player_nicknames.get(victim, "them")) + " with your " + String(GEAR[type]["name"]).to_lower() + " for " + str(dmg) + "!")
		if crosshair:
			crosshair.flash()
	v.apply_damage(dmg) # may end the match - nothing after this

func _shot_fx(type: String, from: Vector3, to: Vector3) -> void :
	if not world_root or not is_instance_valid(world_root):
		return
	var fx = ShotFx.new()
	fx.kind = type
	fx.a = from
	fx.b = to
	world_root.add_child(fx)

func _on_shot_packet(data: Dictionary) -> void :
	var o = data.get("o", [])
	var e = data.get("e", [])
	if not (o is Array and e is Array) or o.size() < 3 or e.size() < 3:
		return
	var shooter = get_player(int(data.get("s", -1)))
	if shooter and not shooter.is_local_player():
		shooter.remote_shot()
	_shot_fx(String(data.get("w", "bow")), Vector3(float(o[0]), float(o[1]), float(o[2])), Vector3(float(e[0]), float(e[1]), float(e[2])))

# Item types for the next batch of weapons on this map (taking turns).
func _royale_weapon_types() -> Array:
	var w = selected_map_data.get("weapons", ["sword", "shield"])
	return w if w is Array and not w.is_empty() else ["sword", "shield"]

func gear_of(pid: int) -> Dictionary:
	return player_gear.get(pid, {})

# melee: base + the attacker's blade; a shield takes some off (more off shots
# for the ballistic shield); a gas mask takes 40% off what's left.
func gear_damage(attacker: int, target: int, base: int, kind: String = "melee") -> int:
	if not is_royale:
		return base
	var d = float(base)
	if kind == "melee":
		var m = gear_slot(attacker, "melee")
		if GEAR.has(m):
			d += float(GEAR[m].get("bonus", 0))
	var sh = gear_slot(target, "shield")
	if GEAR.has(sh):
		d -= float(GEAR[sh].get("block_ranged" if kind == "ranged" else "block", 0))
	if gear_slot(target, "mask") != "":
		d *= 0.6
	return max(int(round(d)), 1)

# Host: drop the starting items, then a batch of weapons every 30s and a wave
# of crystals every 40s. Also runs the bots (pathfinding grid + positions).
func _royale_tick(delta: float) -> void :
	if not is_royale or not is_match_active or is_game_over or not world_root:
		return
	royale_time += delta
	_update_drop_label()
	_storm_tick(delta)
	if String(selected_map_data.get("mechanic", "")) == "wasteland":
		_waste_tick(delta)
	elif is_moon():
		_moon_tick(delta)
	if is_host_peer and not royale_bots.is_empty():
		if not is_moon():
			_rnav_tick()
		_royale_bots_broadcast()
	if is_host_peer and not royale_seeded:
		royale_seeded = true
		var spots: Array = range(_royale_weapon_spot_count())
		spots.shuffle()
		var batch: Array = []
		var wt = _royale_weapon_types()
		for i in range(min(ROYALE_START_ITEMS, spots.size())):
			batch.append(_royale_new_item(int(spots[i]), String(wt[i % wt.size()])))
		_royale_send_items(batch)
		if String(selected_map_data.get("mechanic", "")) == "desert":
			_desert_treasure_wave()
		return
	# (The timers run on every client so a new host carries on from them.)
	royale_item_timer -= delta
	if royale_item_timer <= 0.0:
		royale_item_timer = ROYALE_ITEM_RESPAWN
		if is_host_peer:
			_royale_weapon_wave()
	royale_crystal_timer -= delta
	if royale_crystal_timer <= 0.0:
		royale_crystal_timer = ROYALE_CRYSTAL_WAVE_TIME
		if is_host_peer:
			_royale_crystal_wave()

# Free spots in [from, to) of _royale_item_spots(), shuffled.
func _royale_free_spots(from: int, to: int) -> Array:
	var used: Dictionary = {}
	for id in royale_items:
		used[int(royale_items[id]["spot"])] = true
	var free: Array = []
	var spots = _royale_item_spots()
	for i in range(from, to):
		if not used.has(i) and not storm_outside(spots[i], 6.0):
			free.append(i)
	free.shuffle()
	return free

func _royale_weapon_wave() -> void :
	if String(selected_map_data.get("mechanic", "")) == "desert":
		_desert_treasure_wave()
	var have = 0
	for id in royale_items:
		if _is_weapon(String(royale_items[id]["type"])):
			have += 1
	var free = _royale_free_spots(0, _royale_weapon_spot_count())
	var n = min(ROYALE_WEAPON_WAVE, ROYALE_MAX_ITEMS - have, free.size())
	var batch: Array = []
	var wt = _royale_weapon_types()
	var first = randi() % wt.size()
	for i in range(n):
		batch.append(_royale_new_item(int(free[i]), String(wt[(first + i) % wt.size()])))
	if not batch.is_empty():
		_royale_send_items(batch, "weapons")

func _royale_crystal_wave() -> void :
	if String(selected_map_data.get("mechanic", "")) == "desert":
		_desert_genie_wave()
	elif is_moon():
		_moon_special_wave()
	var have = 0
	for id in royale_items:
		if _is_royale_crystal(String(royale_items[id]["type"])):
			have += 1
	var free = _royale_free_spots(_royale_weapon_spot_count(), _royale_special_start())
	var n = min(ROYALE_CRYSTAL_WAVE.size(), ROYALE_MAX_CRYSTALS - have, free.size())
	var abilities = CRYSTAL_ABILITIES.keys()
	var batch: Array = []
	for i in range(n):
		var t = String(ROYALE_CRYSTAL_WAVE[i])
		if t == "":
			t = String(abilities[randi() % abilities.size()])
		batch.append(_royale_new_item(int(free[i]), t))
	if not batch.is_empty():
		_royale_send_items(batch, "crystals")

func _royale_wave_note(wave: String) -> void :
	if wave == "blackhole":
		log_console("[Moon] A BLACK HOLE appeared on the moon! Whoever grabs it can unleash it (" + ("USE" if mobile_controls else "F") + ").")
	elif wave == "treasure":
		log_console("[Desert] Treasure appeared deep inside the pyramids!")
	elif wave == "genie":
		log_console("[Desert] A GENIE appeared at the top of the risen pyramid - no beam shows the way. One wish each!")
	elif wave == "weapons":
		log_console("[Royale] New weapons dropped around the map - follow the light beams!")
	elif wave == "crystals":
		log_console("[Royale] Crystals appeared - pink ones are Regen (+" + str(REGEN_HEAL) + " HP)!")

func _royale_new_item(spot: int, type: String) -> Array:
	royale_item_counter += 1
	var id = local_peer_id * 100000 + royale_item_counter
	return [id, type, spot]

func _royale_send_items(batch: Array, wave: String = "") -> void :
	for it in batch:
		_apply_item_spawn(int(it[0]), String(it[1]), int(it[2]))
	send_p2p_packet({"action": "items_spawn", "items": batch, "wave": wave})
	_royale_wave_note(wave)

func _apply_item_spawn(id: int, type: String, spot: int) -> void :
	var spots = _royale_item_spots()
	if royale_items.has(id) or spot < 0 or spot >= spots.size() or not (_is_weapon(type) or _is_royale_crystal(type)):
		return
	royale_seeded = true
	royale_items[id] = {"type": type, "spot": spot, "pos": spots[spot]}
	if world_root:
		_spawn_item_node(id)

func _spawn_item_node(id: int) -> void :
	if royale_item_nodes.has(id) and is_instance_valid(royale_item_nodes[id]):
		return
	var it = royale_items[id]
	var node = RoyaleItem.new(id, String(it["type"]), self)
	node.position = it["pos"]
	if is_moon():
		node.transform = Transform3D(basis_up(item_up(it["pos"])), it["pos"])
	world_root.add_child(node)
	royale_item_nodes[id] = node

# The local player is standing on an item.
func on_item_touched(id: int) -> void :
	if not royale_items.has(id) or is_game_over:
		return
	var me = get_local_player()
	if not me or me.is_dead:
		return
	var type = String(royale_items[id]["type"])
	if type == "regen":
		if me.health >= me.max_health:
			return # full health - leave it for someone else
	elif _is_royale_crystal(type):
		if local_ability != "":
			return # one crystal ability at a time
	elif not can_take_gear(local_peer_id, type):
		return # already carrying one as good - leave it for someone else
	if is_host_peer:
		_host_grant_item(id, local_peer_id)
	elif _now_ms() - int(royale_claims.get(id, -100000)) > 1500:
		royale_claims[id] = _now_ms()
		send_p2p_packet({"action": "item_claim", "id": id})

func _host_grant_item(id: int, by_peer: int) -> void :
	if not royale_items.has(id) or dead_peers.has(by_peer):
		return
	var type = String(royale_items[id]["type"])
	var heal = 0
	if type == "regen":
		var p = get_player(by_peer)
		if p == null or p.health >= p.max_health:
			return
		heal = min(REGEN_HEAL, p.max_health - p.health)
	elif _is_royale_crystal(type):
		if is_bot(by_peer):
			return # bots don't use abilities
	elif not can_take_gear(by_peer, type):
		return
	send_p2p_packet({"action": "item_taken", "id": id, "by": by_peer, "type": type, "heal": heal})
	_apply_item_taken(id, by_peer, type, heal)

func _apply_item_taken(id: int, by_peer: int, type: String, heal: int = 0) -> void :
	royale_items.erase(id)
	royale_claims.erase(id)
	if royale_item_nodes.has(id):
		var n = royale_item_nodes[id]
		if is_instance_valid(n):
			n.queue_free()
		royale_item_nodes.erase(id)
	if type == "regen":
		_apply_heal(by_peer, heal)
		return
	if CRYSTAL_ABILITIES.has(type):
		var info = CRYSTAL_ABILITIES[type]
		if by_peer == local_peer_id:
			_give_local_ability(type)
		else:
			var grabber = get_player(by_peer)
			if grabber:
				grabber.set_ability_tag(String(info["name"]), info["color"])
		return
	if not GEAR.has(type):
		return
	var slot = String(GEAR[type]["slot"])
	var g = gear_of(by_peer).duplicate()
	var old = String(g.get(slot, ""))
	g[slot] = type
	player_gear[by_peer] = g
	var p = get_player(by_peer)
	if slot == "genie":
		genie_wishes[by_peer] = true
		if p:
			p.apply_genie()
	if p:
		p.refresh_gear()
	if by_peer == local_peer_id:
		log_console("[Royale] You got the " + _gear_pickup_note(type))
	else:
		log_console("[Royale] " + String(player_nicknames.get(by_peer, "A player")) + (" made a Genie wish!" if slot == "genie" else " picked up a " + String(GEAR[type]["name"]).to_lower() + "."))
	_update_team_hud()

# The bots for a room of n players (peer IDs n+1 .. 10).
func _royale_make_bots(n: int) -> Dictionary:
	var total = 0
	for pid in range(1, n + 1):
		total += int(player_elos.get(pid, 0))
	var avg = int(round(float(total) / float(max(n, 1))))
	var names = ROYALE_BOT_NAMES.duplicate()
	names.shuffle()
	var out: Dictionary = {}
	for i in range(ROYALE_FILL_TO - n):
		var skill = royale_bot_skill(avg, i)
		var col = COLOR_PRESETS[randi() % COLOR_PRESETS.size()]
		out[n + 1 + i] = {"name": String(names[i % names.size()]), "level": int(skill[0]), "miss": float(skill[1]), "elo": avg, "color": String(col[1])}
	return out

# How good the bots are, from the room's average ELO: [level, miss chance]
#   below 550 (Humble Husser / Rookie Runner): level 3, misses 75% of hits
#   550 - 1099: a mix of level 3 and level 4, both miss 50%
#   1100 and up: level 4 (misses 30%, like the level 4 practice bot)
func royale_bot_skill(avg_elo: int, index: int = 0) -> Array:
	if avg_elo < 550:
		return [3, 0.75]
	if avg_elo < 1100:
		return [3 if index % 2 == 0 else 4, 0.5]
	return [4, 0.3]

func _royale_bots_broadcast() -> void :
	var now = _now_ms()
	if now - royale_bot_send_ms < ROYALE_BOT_SEND_MS:
		return
	royale_bot_send_ms = now
	var arr: Array = []
	for pid in royale_bots:
		var b = get_player(pid)
		if b and not b.is_dead:
			var p = b.global_position
			var entry = [pid, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(b.rotation_degrees.y, 0.1), 1 if b.gliding else 0, snappedf(b.velocity.x, 0.1), snappedf(b.velocity.z, 0.1)]
			if is_moon():
				var bq = b.global_transform.basis.get_rotation_quaternion()
				entry.append_array([snappedf(bq.x, 0.001), snappedf(bq.y, 0.001), snappedf(bq.z, 0.001), snappedf(bq.w, 0.001)])
			arr.append(entry)
	if not arr.is_empty():
		send_p2p_packet({"action": "bots_move", "b": arr})

# Host: a bot walked into an item (the same rules as for players).
func royale_bot_pickups(bot: NetworkPlayer) -> void :
	for id in royale_items.keys():
		if not royale_items.has(id):
			continue
		var ipos: Vector3 = royale_items[id]["pos"]
		if item_touching(ipos, item_up(ipos), bot):
			_host_grant_item(id, bot.peer_id)

# Host: the nearest item a bot would like (a missing sword / shield, or a
# Regen crystal when hurt). null if there's none close enough.
func royale_bot_wanted_item(bot: NetworkPlayer):
	var best = null
	var best_d = 32.0
	for id in royale_items:
		var type = String(royale_items[id]["type"])
		var want = false
		if GEAR.has(type):
			want = can_take_gear(bot.peer_id, type)
		elif type == "regen":
			want = bot.health <= bot.max_health - 25
		if not want:
			continue
		var pos: Vector3 = royale_items[id]["pos"]
		if is_moon() and pos.length() > MOON_R + 5.0:
			continue # (bots stay on the moon)
		var dist = bot.global_position.distance_to(pos)
		if dist < best_d:
			best_d = dist
			best = pos
	return best

func kill_bot_from_fall(bot: NetworkPlayer) -> void :
	var amount = bot.health
	send_p2p_packet({"action": "take_damage", "peer_id": str(bot.peer_id), "amount": amount})
	bot.apply_damage(amount)

# We just became the host: the bots are ours to run now. Let go of anyone the
# old host's bots were holding.
func _royale_bots_take_over() -> void :
	if not is_royale or royale_bots.is_empty() or not players_container:
		return
	for pid in royale_bots:
		var b = get_player(pid)
		if b == null:
			continue
		b.net_has_target = false
		if b.qte_active and b.qte_target_peer > 0:
			send_p2p_packet({"action": "qte_end", "attacker": str(pid), "target": str(b.qte_target_peer)})
			var t = get_player(b.qte_target_peer)
			if t and (t.is_local_player() or t.is_bot):
				t.remove_movement_lock(pid)
		b.qte_active = false
		b.qte_target_peer = -1
		b.bot_windup = 0.0
		b.bot_target = null
		b.lock_sources.clear()
		b.is_movement_locked = false
		b.rb_think = 0.0
		b.rb_repath = 0.0
		# (bots were never ours, so their attack timers never ran here)
		b.bot_attack_cd = randf_range(0.2, 1.0)

func _update_drop_label() -> void :
	if not royale_drop_label:
		return
	var me = get_local_player()
	var show = me != null and me.gliding and not me.is_dead
	royale_drop_label.visible = show
	if show:
		var left = int(ceil(max(ROYALE_GLIDE_TIME - royale_time, 0.0)))
		royale_drop_label.text = "SKY DROP - steer to where you want to land (" + str(left) + "s)\n" + ("Move with the joystick" if mobile_controls else "W A S D to glide, Shift = faster")

# --- Bot pathfinding grid (host only) ---
# A 1m grid over the whole map with up to RNAV_LAYERS walkable surfaces per
# square (ground, a floor inside a pyramid, a bunker room below, a roof...).
# Each surface is a point in an A* graph, linked to the surfaces next to it at
# about the same height; ladders add links up and down. Point id =
# (cell * RNAV_LAYERS + layer).
const RNAV_LAYERS: int = 12
var rnav_half: int = RNAV_HALF
var rnav_ids: PackedInt64Array = PackedInt64Array()
var rnav_col: int = 0

func _rnav_size() -> int:
	return rnav_half * 2 + 1

func _rnav_cell(x: float, z: float) -> int:
	var size = _rnav_size()
	var ix = roundi(x) + rnav_half
	var iz = roundi(z) + rnav_half
	if ix < 0 or iz < 0 or ix >= size or iz >= size:
		return -1
	return ix * size + iz

func _rnav_cell_pos(cell: int) -> Vector2:
	var size = _rnav_size()
	return Vector2(float(cell / size - rnav_half), float(cell % size - rnav_half))

# The layer of this cell closest to height y (within tol), or -1.
func _rnav_layer_at(cell: int, y: float, tol: float) -> int:
	if cell < 0:
		return -1
	var best = -1
	var best_d = tol
	for l in range(RNAV_LAYERS):
		var h = rnav_h[cell * RNAV_LAYERS + l]
		if h < -999.0:
			break
		var d = abs(h - y)
		if d <= best_d:
			best_d = d
			best = l
	return best

func _rnav_tick() -> void :
	if rnav_ready or not world_root:
		return
	if rnav_row < 0:
		if String(selected_map_data.get("mechanic", "")) == "desert":
			_desert_before_nav()
		rnav_half = int(ceil(float(selected_map_data.get("size", 130.0)) / 2.0)) + 1
		var size = _rnav_size()
		rnav_h = PackedFloat32Array()
		rnav_h.resize(size * size * RNAV_LAYERS)
		rnav_h.fill(-1000.0)
		rnav_w = PackedFloat32Array()
		rnav_w.resize(size * size * RNAV_LAYERS)
		rnav_w.fill(1.0)
		rnav = AStar3D.new()
		rnav.reserve_space(size * size * 2)
		rnav_row = 0
		rnav_col = 0
		return
	var size = _rnav_size()
	if rnav_row >= size:
		_rnav_link_step()
		return
	var space = world_root.get_world_3d().direct_space_state
	var ex: Array = []
	if players_container:
		for c in players_container.get_children():
			if c is CollisionObject3D:
				ex.append(c.get_rid())
	var ray = PhysicsRayQueryParameters3D.new()
	ray.exclude = ex
	ray.collide_with_areas = false
	var probe = BoxShape3D.new()
	probe.size = Vector3(0.9, 1.5, 0.9)
	var params = PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.collide_with_areas = true
	params.exclude = ex
	var top = float(selected_map_data.get("nav_top", 30.0))
	var bottom = float(selected_map_data.get("nav_bottom", -1.0))
	# A few milliseconds' worth of rows per frame (the host never stutters).
	var t_start = Time.get_ticks_usec()
	var ix = rnav_row
	while ix < size:
		var iz_from = rnav_col
		var iz_end = size
		for iz in range(iz_from, size):
			if (iz & 7) == 0 and iz > iz_from and Time.get_ticks_usec() - t_start > 4000:
				iz_end = iz
				break
			var x = float(ix - rnav_half)
			var z = float(iz - rnav_half)
			var cell = ix * size + iz
			var layer = 0
			# (a hair off the grid line, so the ray never runs exactly along
			# a wall's face)
			ray.from = Vector3(x + 0.013, top, z + 0.017)
			ray.to = Vector3(x + 0.013, bottom, z + 0.017)
			for _k in range(RNAV_LAYERS + 36): # (walls are stacks of boxes)
				var hit = space.intersect_ray(ray)
				if hit.is_empty():
					break
				var hp: Vector3 = hit["position"]
				if hit["normal"].y >= 0.7 and hit["collider"] is StaticBody3D:
					# (starts 0.35m up, so a ramp's own slope doesn't count as in the way)
					params.transform = Transform3D(Basis(), Vector3(x, hp.y + 1.1, z))
					var ok = true
					var w = 1.0
					for c in space.intersect_shape(params, 8):
						var col = c.get("collider")
						if col is MapJumpPad:
							w = 4.0
						elif col is StaticBody3D:
							ok = false
							break
					if ok:
						var id = cell * RNAV_LAYERS + layer
						rnav_h[id] = hp.y
						rnav_w[id] = w
						rnav.add_point(id, Vector3(x, hp.y, z), w)
						layer += 1
						if layer >= RNAV_LAYERS:
							break
				# carry on below this surface (a ray that starts inside a
				# body doesn't see it)
				ray.from = hp - Vector3(0, 0.05, 0)
				if ray.from.y <= bottom:
					break
		if iz_end < size:
			rnav_col = iz_end # (out of time: carry on from here next frame)
			break
		rnav_col = 0
		ix += 1
		if Time.get_ticks_usec() - t_start > 4000:
			break
	rnav_row = ix

# After the scan: the links between neighbours a few rows per frame (so the
# host never freezes), then the ladders.
func _rnav_link_step() -> void :
	var size = _rnav_size()
	var from = rnav_row - size
	var t_start = Time.get_ticks_usec()
	var to = from
	while to < size and (to == from or Time.get_ticks_usec() - t_start < 4000):
		_rnav_link(to, to + 1)
		to += 1
	rnav_row += to - from
	if to >= size:
		_rnav_link_ladders()
		rnav_ids = rnav.get_point_ids()
		rnav_ready = true
		if String(selected_map_data.get("mechanic", "")) == "desert":
			_desert_after_nav()

func _rnav_link(from: int, to: int) -> void :
	var size = _rnav_size()
	var steps = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for ix in range(from, to):
		for iz in range(size):
			var ca = ix * size + iz
			for la in range(RNAV_LAYERS):
				var a = ca * RNAV_LAYERS + la
				var ha = rnav_h[a]
				if ha < -999.0:
					break
				for d in steps:
					var jx = ix + d.x
					var jz = iz + d.y
					if jx >= size or jz < 0 or jz >= size:
						continue
					var cb = jx * size + jz
					var lb = _rnav_layer_at(cb, ha, 0.6)
					if lb < 0:
						continue
					if d.x != 0 and d.y != 0:
						# diagonal: don't cut corners
						if _rnav_layer_at(ix * size + jz, ha, 0.6) < 0 or _rnav_layer_at(jx * size + iz, ha, 0.6) < 0:
							continue
					rnav.connect_points(a, cb * RNAV_LAYERS + lb)

# Ladders: from the foot of the ladder to the top of the wall. (one_way:
# ladders you can only climb up - the Wasteland's bunker exits.)
func _rnav_link_ladders() -> void :
	for l in royale_ladders:
		var fp: Vector3 = l[0]
		var n: Vector3 = l[1]
		var lh: float = l[2]
		var bottom = _rnav_cell_near(fp + n * 1.0, fp.y)
		var top_p: Vector3 = l[3] if l.size() > 3 else fp - n * 1.0 + Vector3(0, lh, 0)
		var top = _rnav_cell_near(top_p, top_p.y)
		if bottom >= 0 and top >= 0:
			rnav.connect_points(bottom, top, not (l.size() > 4 and bool(l[4])))

# A walkable point near p at about height y (-1 if none).
func _rnav_cell_near(p: Vector3, y: float) -> int:
	var best = -1
	var best_d = INF
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var c = _rnav_cell(p.x + dx, p.z + dz)
			var l = _rnav_layer_at(c, y, 0.7)
			if l < 0:
				continue
			var d = Vector2(float(dx), float(dz)).length()
			if d < best_d:
				best_d = d
				best = c * RNAV_LAYERS + l
	return best

func _rnav_point_for(p: Vector3) -> int:
	var c = _rnav_cell(p.x, p.z)
	var l = _rnav_layer_at(c, p.y - 0.3, 1.6)
	if l >= 0:
		return c * RNAV_LAYERS + l
	var near = _rnav_cell_near(p, p.y)
	if near >= 0:
		return near
	return rnav.get_closest_point(p) if rnav else -1

# Can a bot run straight from a to b? (open, hazard-free cells all the way on
# the same floor, no steps up or down bigger than a ramp.)
func _rnav_line_ok(a: Vector3, b: Vector3) -> bool:
	if abs(a.y - b.y) > 3.5:
		return false
	var d = Vector2(b.x - a.x, b.z - a.z)
	var length = d.length()
	if length < 0.01:
		return true
	var dir = d / length
	var perp = Vector2(-dir.y, dir.x) * 0.35
	var steps = int(ceil(length / 0.5))
	var prev_h = a.y
	for k in range(steps + 1):
		var pt = Vector2(a.x, a.z) + dir * (length * float(k) / float(steps))
		var c0 = _rnav_cell(pt.x, pt.y)
		var l0 = _rnav_layer_at(c0, prev_h, 0.6)
		if l0 < 0 or rnav_w[c0 * RNAV_LAYERS + l0] > 1.0:
			return false
		var h0 = rnav_h[c0 * RNAV_LAYERS + l0]
		for off in [perp, -perp]:
			var q = pt + off
			var c = _rnav_cell(q.x, q.y)
			var l = _rnav_layer_at(c, h0, 0.6)
			if l < 0 or rnav_w[c * RNAV_LAYERS + l] > 1.0:
				return false
		prev_h = h0
	return true

# A path for a bot (waypoints with heights); empty if there's no grid yet or
# no way there.
func rnav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out = PackedVector3Array()
	if not rnav_ready or rnav == null:
		return out
	var a = _rnav_point_for(from)
	var b = _rnav_point_for(to)
	if a < 0 or b < 0:
		return out
	var path = rnav.get_point_path(a, b)
	if path.size() <= 2:
		return path
	# Skip waypoints that can be run past in a straight line.
	out.append(path[0])
	var i = 0
	while i < path.size() - 1:
		var j = min(i + 24, path.size() - 1)
		while j > i + 1 and not _rnav_line_ok(path[i], path[j]):
			j -= 1
		out.append(path[j])
		i = j
	return out

# Somewhere to wander to (not in the storm). ground_only: outdoors, at ground level.
func rnav_random_point(ground_only: bool = false) -> Vector3:
	if rnav_ready and rnav_ids.size() > 0:
		for _i in range(40):
			var id = int(rnav_ids[randi() % rnav_ids.size()])
			var p = rnav.get_point_position(id)
			if rnav_w[id] > 1.0 or rnav.is_point_disabled(id):
				continue
			if ground_only and abs(p.y) > 0.5:
				continue
			if storm_outside(p, -6.0):
				continue
			return p
	var r = float(selected_map_data.get("size", 100.0)) * 0.35
	return Vector3(randf_range(-r, r), 0, randf_range(-r, r))

# What a piece of Royale gear does, in a few words.
func gear_effect_text(type: String) -> String:
	var g: Dictionary = GEAR.get(type, {})
	match String(g.get("slot", "")):
		"melee":
			return "+" + str(int(g.get("bonus", 5))) + " damage" + (", long reach" if g.has("reach") else "")
		"shield":
			if int(g.get("block_ranged", 5)) != int(g.get("block", 5)):
				return "-" + str(int(g.get("block", 5))) + " damage from hits, -" + str(int(g.get("block_ranged", 5))) + " from shots"
			return "-" + str(int(g.get("block", 5))) + " damage taken"
		"ranged":
			return str(int(g.get("dmg", 20))) + " damage shots"
		"mask":
			return "40% less damage, safe from the radiation"
		"special":
			return "everyone has 30s to find a bunker"
		"genie":
			return "150 HP, 40 damage hits, 2x speed, low gravity"
	return ""

func _royale_weapons_line() -> String:
	var parts: Array = []
	for t in selected_map_data.get("weapons", []):
		if GEAR.has(t):
			parts.append(String(GEAR[t]["name"]) + " (" + gear_effect_text(String(t)) + ")")
	return "Weapons here: " + ", ".join(PackedStringArray(parts)) + "." if not parts.is_empty() else ""

# --- HUSS ROYALE MAP VOTE ---
# Every round starts with a vote: 15s (ends early once all the real players
# have voted). The host counts the votes - most votes wins, a tie is a coin
# flip - and tells everyone the map plus a random seed for that map's random
# details (so every screen builds exactly the same map).

func _start_royale_vote() -> void :
	royale_votes.clear()
	royale_vote_done = false
	royale_vote_packet = {}
	royale_start_at_ms = -1
	royale_vote_deadline_ms = _now_ms() + int(ROYALE_VOTE_SECONDS * 1000.0)
	royale_vote_ask_ms = _now_ms()
	log_console("[Royale] Vote for the map! (" + str(int(ROYALE_VOTE_SECONDS)) + "s)")
	_build_royale_vote_ui()
	if not royale_pending_choice.is_empty():
		var pend = royale_pending_choice
		royale_pending_choice = {}
		_apply_royale_choice(pend)

func royale_cast_vote(idx: int) -> void :
	if royale_vote_done or idx < 0 or idx >= ROYALE_MAPS.size():
		return
	royale_votes[local_peer_id] = idx
	send_p2p_packet({"action": "royale_vote", "map": idx})
	_refresh_royale_vote_ui()
	_royale_check_all_voted()

func _on_royale_vote(pid: int, idx: int) -> void :
	if royale_vote_done:
		# A late / repeated vote: they may have missed the result.
		if is_host_peer and not royale_vote_packet.is_empty():
			send_p2p_packet(royale_vote_packet.duplicate(true))
		return
	if idx >= 0 and idx < ROYALE_MAPS.size():
		royale_votes[pid] = idx
	_refresh_royale_vote_ui()
	_royale_check_all_voted()

func _royale_voters() -> Array:
	return human_ids().filter(func(p): return not forfeited_peers.has(p))

func _royale_check_all_voted() -> void :
	if not is_host_peer or royale_vote_done or royale_vote_canvas == null:
		return
	if _royale_voters().all(func(p): return royale_votes.has(p)):
		royale_vote_deadline_ms = min(royale_vote_deadline_ms, _now_ms() + 1200)

func _royale_vote_tick(now: int) -> void :
	if royale_start_at_ms > 0 and now >= royale_start_at_ms:
		royale_start_at_ms = -1
		_begin_royale_round()
		return
	if royale_vote_done or royale_vote_canvas == null:
		return
	if royale_vote_timer_label:
		royale_vote_timer_label.text = "Voting ends in " + str(int(ceil(max(royale_vote_deadline_ms - now, 0) / 1000.0))) + "s"
	if is_host_peer and now >= royale_vote_deadline_ms:
		_host_decide_royale_map()
	elif not is_host_peer and now > royale_vote_deadline_ms + 3000 and now - royale_vote_ask_ms > 2000:
		# Still no result: ask again (the host answers with the result).
		royale_vote_ask_ms = now
		send_p2p_packet({"action": "royale_vote", "map": int(royale_votes.get(local_peer_id, -1))})

func _royale_tally() -> Array:
	var tally: Array = []
	tally.resize(ROYALE_MAPS.size())
	tally.fill(0)
	for pid in royale_votes:
		var vi = int(royale_votes[pid])
		if vi >= 0 and vi < tally.size():
			tally[vi] += 1
	return tally

func _host_decide_royale_map() -> void :
	var tally = _royale_tally()
	var best = tally.max()
	var tied: Array = []
	for i in range(tally.size()):
		if tally[i] == best:
			tied.append(i)
	var pick = int(tied[randi() % tied.size()])
	var pkt = {"action": "royale_map", "map": pick, "seed": randi() % 1000000000, "votes": tally}
	royale_vote_packet = pkt
	send_p2p_packet(pkt.duplicate(true))
	_apply_royale_choice(pkt)

func _apply_royale_choice(data: Dictionary) -> void :
	if royale_vote_done or is_match_active:
		return
	if royale_vote_canvas == null:
		royale_pending_choice = data # the vote screen isn't up yet
		return
	royale_vote_done = true
	royale_map_index = clampi(int(data.get("map", 0)), 0, ROYALE_MAPS.size() - 1)
	royale_seed = int(data.get("seed", 0))
	# (items the host sends from now on are for this map)
	selected_map_data = ROYALE_MAPS[royale_map_index]
	royale_spots_cache = []
	var tally = data.get("votes", [])
	var n = int(tally[royale_map_index]) if tally is Array and tally.size() > royale_map_index else 0
	var mname = String(ROYALE_MAPS[royale_map_index]["name"])
	log_console("[Royale] " + mname + " wins the vote" + (" (" + str(n) + " vote" + ("s" if n != 1 else "") + ")" if n > 0 else "") + "!")
	if royale_vote_timer_label:
		royale_vote_timer_label.text = mname.to_upper() + " WINS!"
		royale_vote_timer_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	_refresh_royale_vote_ui()
	royale_start_at_ms = _now_ms() + 1500

func _begin_royale_round() -> void :
	if is_match_active or is_game_over:
		return
	_free_royale_vote_ui()
	selected_map_data = ROYALE_MAPS[royale_map_index]
	_start_p2p_game()

func _free_royale_vote_ui() -> void :
	if royale_vote_canvas and is_instance_valid(royale_vote_canvas):
		royale_vote_canvas.queue_free()
	royale_vote_canvas = null
	royale_vote_cards.clear()
	royale_vote_timer_label = null

func _build_royale_vote_ui() -> void :
	_free_royale_vote_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	royale_vote_canvas = CanvasLayer.new()
	royale_vote_canvas.layer = 50
	add_child(royale_vote_canvas)
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	royale_vote_canvas.add_child(bg)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	royale_vote_canvas.add_child(scroll)
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	center.add_child(col)
	var title = Label.new()
	title.text = "HUSS ROYALE - VOTE FOR THE MAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	col.add_child(title)
	var sub = Label.new()
	sub.text = str(all_player_ids().size()) + " players" + (" (" + str(royale_bots.size()) + " bots)" if not royale_bots.is_empty() else "") + " - the map with the most votes wins"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	col.add_child(sub)
	royale_vote_timer_label = Label.new()
	royale_vote_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	royale_vote_timer_label.add_theme_font_size_override("font_size", 16)
	royale_vote_timer_label.text = "Voting ends in " + str(int(ROYALE_VOTE_SECONDS)) + "s"
	col.add_child(royale_vote_timer_label)
	var vw = get_viewport().get_visible_rect().size.x if get_viewport() else 1280.0
	var per_row = 4 if vw >= 1100 else 2
	var grid = GridContainer.new()
	grid.columns = min(per_row, ROYALE_MAPS.size())
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	var card_w = 250.0 if per_row == 4 else clamp((vw - 50.0) / 2.0, 150.0, 300.0)
	royale_vote_cards.clear()
	for i in range(ROYALE_MAPS.size()):
		var info: Dictionary = ROYALE_MAPS[i]
		var card = PanelContainer.new()
		card.name = "Card_" + str(i)
		card.custom_minimum_size = Vector2(card_w, 0)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.13, 0.17)
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(3)
		sb.border_color = Color(0.25, 0.27, 0.33)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", sb)
		grid.add_child(card)
		var v = VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		var prev = RoyaleMapPreview.new()
		prev.clip_contents = true
		prev.mechanic = String(info["mechanic"])
		prev.ground = info["color"]
		prev.custom_minimum_size = Vector2(card_w - 20.0, 110 if per_row == 4 else 80)
		v.add_child(prev)
		var nm = Label.new()
		nm.text = String(info["name"]).to_upper()
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 18)
		v.add_child(nm)
		var d = Label.new()
		d.text = String(info.get("desc", ""))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(card_w - 20.0, 0)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.add_theme_font_size_override("font_size", 11)
		d.add_theme_color_override("font_color", Color(0.78, 0.8, 0.85))
		v.add_child(d)
		var w = Label.new()
		var wn: Array = []
		for t in info.get("weapons", []):
			wn.append(String(GEAR[t]["name"]) if GEAR.has(t) else String(t))
		var special = String(info.get("special", ""))
		w.text = "Weapons: " + ", ".join(PackedStringArray(wn)) + ("\nSpecial: " + String(GEAR[special]["name"]) if GEAR.has(special) else "") + "\nStorm: " + String(info.get("storm", "")).capitalize()
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.custom_minimum_size = Vector2(card_w - 20.0, 0)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		w.add_theme_font_size_override("font_size", 11)
		w.add_theme_color_override("font_color", (info["storm_color"] as Color).lerp(Color.WHITE, 0.45))
		v.add_child(w)
		var count = Label.new()
		count.name = "Count"
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.add_theme_font_size_override("font_size", 14)
		v.add_child(count)
		var btn = Button.new()
		btn.name = "Vote"
		btn.text = "VOTE"
		btn.custom_minimum_size = Vector2(0, 36)
		var idx = i
		btn.pressed.connect(func(): royale_cast_vote(idx))
		v.add_child(btn)
		royale_vote_cards.append({"panel": card, "style": sb, "count": count, "button": btn})
	_refresh_royale_vote_ui()

func _refresh_royale_vote_ui() -> void :
	if royale_vote_canvas == null:
		return
	var tally = _royale_tally()
	var mine = int(royale_votes.get(local_peer_id, -1))
	for i in range(royale_vote_cards.size()):
		var c = royale_vote_cards[i]
		(c["count"] as Label).text = str(tally[i]) + " vote" + ("s" if tally[i] != 1 else "")
		var won = royale_vote_done and i == royale_map_index
		var sb: StyleBoxFlat = c["style"]
		sb.border_color = Color(0.4, 1.0, 0.5) if won else (Color(1.0, 0.85, 0.2) if i == mine else Color(0.25, 0.27, 0.33))
		var b: Button = c["button"]
		b.text = "WINNER" if won else ("YOUR VOTE" if i == mine else "VOTE")
		b.disabled = royale_vote_done

# Royale maps with their own sky, light and haze.
func _royale_environment() -> void :
	var m = selected_map_data
	if not m.has("sky_top") and not m.has("space"):
		return
	var env = WorldEnvironment.new()
	env.name = "RoyaleSky"
	var e = Environment.new()
	if m.has("space"):
		e.background_mode = Environment.BG_COLOR
		e.background_color = m["space"]
	else:
		var sky = Sky.new()
		var psm = ProceduralSkyMaterial.new()
		psm.sky_top_color = m["sky_top"]
		psm.sky_horizon_color = m["sky_horizon"]
		psm.ground_horizon_color = m["sky_horizon"]
		psm.ground_bottom_color = (m["sky_horizon"] as Color).darkened(0.35)
		sky.sky_material = psm
		e.background_mode = Environment.BG_SKY
		e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = m.get("ambient", Color(0.7, 0.7, 0.7))
	e.ambient_light_energy = float(m.get("ambient_energy", 0.65))
	if m.has("fog"):
		e.fog_enabled = true
		e.fog_light_color = m["fog"]
		e.fog_density = float(m.get("fog_density", 0.004))
	env.environment = e
	world_root.add_child(env)
	for c in world_root.get_children():
		if c is DirectionalLight3D:
			c.light_color = m.get("sun", Color.WHITE)
			c.light_energy = float(m.get("sun_energy", 1.0))

# --- THE DESERT (Huss Royale) ---
# Open sand with five pyramids you can go inside: four floors each (ramps
# inside, ladders and doorways out to the terraces). The best loot - golden
# swords and Sun Bows - only turns up inside the pyramids. Every 40s, with the
# crystals, a Genie appears at the top of one pyramid, which rises to eight
# floors (the last four only by ladder). No beam points at the Genie.
const DESERT_PYRAMIDS: Array = [Vector3(0, 0, 0), Vector3(-46, 0, -46), Vector3(46, 0, -46), Vector3(-46, 0, 46), Vector3(46, 0, 46)]
const PYR_TIER_H: float = 4.0
const PYR_HALF: Array = [14.0, 11.0, 8.0, 5.0] # outer half-size of each floor
const PYR_WALL: float = 0.8
# Ramps inside: [floor it climbs to, direction along x, z of the ramp, x of its top]
const PYR_RAMPS: Array = [[1, 1.0, -3.5, 4.5], [2, -1.0, 3.0, -3.5], [3, 1.0, -1.8, 2.2]]
const CROWN_HALF: float = 5.0
const CROWN_WALL: float = 0.5
# Ladders up the Genie tower (floor 4 -> 5 -> 6 -> 7 -> 8):
# [foot of the ladder (relative to the pyramid), normal away from the wall, hatch rect x0, x1, z0, z1]
const CROWN_LADDERS: Array = [
	[Vector3(-4.2, 12.0, 1.5), Vector3(1, 0, 0), -4.2, -2.8, 0.8, 2.2],
	[Vector3(1.5, 16.0, 4.5), Vector3(0, 0, -1), 0.8, 2.2, 3.1, 4.5],
	[Vector3(4.5, 20.0, -1.5), Vector3(-1, 0, 0), 3.1, 4.5, -2.2, -0.8],
	[Vector3(-1.5, 24.0, -4.5), Vector3(0, 0, 1), -2.2, -0.8, -4.5, -3.1],
]
const DESERT_TREASURE: Array = ["gold_sword", "sun_bow"]
const DESERT_MAX_TREASURE: int = 5
var desert_crown: int = -1 # which pyramid has risen (the Genie's), -1 = none
var desert_crowns: Array = [] # per pyramid: {"root", "body", "lid", "ladders", "cap", "mats"}
var desert_crown_nav: Array = [] # host: nav points inside each crown
var desert_crown_fade: float = 0.0
var desert_crown_links: Array = [] # host: the nav link up the ladder through each roof hatch
var desert_nav_crowns_done: bool = false

func _desert_mat() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m

func _build_desert_map(_wall_color: Color) -> void :
	royale_ladders.clear()
	desert_crowns.clear()
	desert_crown_nav.clear()
	desert_nav_crowns_done = false
	var mat = _desert_mat()
	var rng = RandomNumberGenerator.new()
	rng.seed = 4242 # (the same desert on every screen)
	var stone = Color(0.84, 0.69, 0.45)
	for k in range(DESERT_PYRAMIDS.size()):
		_build_pyramid(k, DESERT_PYRAMIDS[k], mat, stone.darkened(0.04 * float(k % 3)))
	# Outside: rocks, broken columns, an oasis with palms, cacti.
	var g = GeoBuilder.new()
	var rock = Color(0.66, 0.52, 0.36)
	for i in range(16):
		var a = TAU * float(i) / 16.0 + rng.randf_range(-0.1, 0.1)
		var r = rng.randf_range(24.0, 74.0)
		var p = Vector3(cos(a) * r, 0, sin(a) * r)
		if _desert_near_pyramid(p, 17.0):
			continue
		var s = Vector3(rng.randf_range(2.0, 4.5), rng.randf_range(1.2, 3.2), rng.randf_range(2.0, 4.0))
		g.box(p + Vector3(0, s.y / 2.0, 0), s, rock.darkened(rng.randf_range(0.0, 0.15)), Basis(Vector3.UP, rng.randf() * TAU))
		g.box(p + Vector3(s.x * 0.45, s.y * 0.3, 0), s * 0.55, rock.lightened(0.05), Basis(Vector3.UP, rng.randf() * TAU))
	# ruins: rows of columns (some fallen)
	for c in [Vector3(-24, 0, 0), Vector3(24, 0, 0), Vector3(0, 0, 70), Vector3(0, 0, -70)]:
		for j in range(5):
			var off = Vector3(0, 0, -6 + j * 3) if abs(c.x) > 0 else Vector3(-6 + j * 3, 0, 0)
			var hgt = rng.randf_range(1.5, 4.5)
			if j % 2 == 0:
				g.box(c + off + Vector3(0, hgt / 2.0, 0), Vector3(1.0, hgt, 1.0), Color(0.9, 0.82, 0.66))
			else:
				g.box(c + off + Vector3(0.9, 0.45, 0.3), Vector3(2.6, 0.9, 0.9), Color(0.88, 0.8, 0.64), Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)))
	# oasis (between the middle and the east pyramids)
	var oasis = Vector3(28, 0, 26)
	var water = MeshInstance3D.new()
	var wm = CylinderMesh.new()
	wm.top_radius = 6.0
	wm.bottom_radius = 6.0
	wm.height = 0.06
	water.mesh = wm
	water.position = oasis + Vector3(0, 0.04, 0)
	var wmat = StandardMaterial3D.new()
	wmat.albedo_color = Color(0.2, 0.55, 0.75, 0.85)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.metallic = 0.3
	wmat.roughness = 0.1
	water.material_override = wmat
	world_root.add_child(water)
	for i in range(6):
		var a2 = TAU * float(i) / 6.0 + 0.4
		_desert_palm(g, oasis + Vector3(cos(a2) * 7.5, 0, sin(a2) * 7.5), rng)
	for i in range(14):
		var cp = Vector3(rng.randf_range(-78, 78), 0, rng.randf_range(-78, 78))
		if _desert_near_pyramid(cp, 16.0) or cp.distance_to(oasis) < 10.0:
			continue
		_desert_cactus(g, cp, rng)
	# dunes (low, you can walk over them)
	for i in range(10):
		var dp = Vector3(rng.randf_range(-75, 75), 0, rng.randf_range(-75, 75))
		if _desert_near_pyramid(dp, 20.0) or dp.distance_to(oasis) < 12.0:
			continue
		var dune = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = rng.randf_range(5.0, 9.0)
		sm.height = sm.radius * 2.0
		dune.mesh = sm
		dune.scale = Vector3(1.6, 0.09, 1.0)
		dune.rotation.y = rng.randf() * TAU
		dune.position = dp
		var dmat = StandardMaterial3D.new()
		dmat.albedo_color = Color(0.9, 0.77, 0.52)
		dmat.roughness = 1.0
		dune.material_override = dmat
		world_root.add_child(dune)
	g.finish(world_root, mat)
	_royale_environment()
	if desert_crown >= 0:
		_set_crown_visual(desert_crown, true) # (the host raised one before our world existed)

func _desert_near_pyramid(p: Vector3, r: float) -> bool:
	for c in DESERT_PYRAMIDS:
		if Vector2(p.x - c.x, p.z - c.z).length() < r:
			return true
	return false

func _desert_palm(g: GeoBuilder, p: Vector3, rng: RandomNumberGenerator) -> void:
	var h = rng.randf_range(5.0, 7.0)
	var lean = Basis(Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU), rng.randf_range(0.05, 0.2))
	for i in range(int(h / 0.7)):
		var y = 0.35 + float(i) * 0.7
		g.box(p + lean * Vector3(0, y, 0), Vector3(0.45 - 0.02 * i, 0.68, 0.45 - 0.02 * i), Color(0.5, 0.36, 0.2).darkened(0.08 * float(i % 2)), lean, i < 3)
	var top = p + lean * Vector3(0, h, 0)
	for j in range(6):
		var a = TAU * float(j) / 6.0
		var dir = Vector3(cos(a), 0, sin(a))
		var leaf_rot = Basis(Vector3.UP, -a) * Basis(Vector3(0, 0, 1), -0.35)
		g.box(top + dir * 1.4 + Vector3(0, -0.3, 0), Vector3(2.8, 0.08, 0.7), Color(0.25, 0.55, 0.2), leaf_rot, false)

func _desert_cactus(g: GeoBuilder, p: Vector3, rng: RandomNumberGenerator) -> void:
	var h = rng.randf_range(1.6, 3.0)
	var green = Color(0.32, 0.55, 0.28)
	g.box(p + Vector3(0, h / 2.0, 0), Vector3(0.5, h, 0.5), green)
	var side = 1.0 if rng.randf() < 0.5 else -1.0
	g.box(p + Vector3(0.5 * side, h * 0.55, 0), Vector3(0.6, 0.35, 0.35), green, Basis(), false)
	g.box(p + Vector3(0.7 * side, h * 0.55 + 0.45, 0), Vector3(0.35, 0.9, 0.35), green, Basis(), false)

# One pyramid: four floors you can walk around inside, with terraces outside.
func _build_pyramid(k: int, c: Vector3, mat: Material, stone: Color) -> void:
	var g = GeoBuilder.new()
	var trim = stone.darkened(0.18)
	var inner = stone.darkened(0.3)
	var holes: Dictionary = {} # floor -> hatch rect
	for r in PYR_RAMPS:
		var t = int(r[0])
		var dir = float(r[1])
		var zr = float(r[2])
		var xt = float(r[3])
		holes[t] = [min(xt, xt - dir * 5.2), max(xt, xt - dir * 5.2), zr - 1.4, zr + 1.4]
	for t in range(PYR_HALF.size()):
		var hh: float = PYR_HALF[t]
		var y0 = PYR_TIER_H * float(t)
		# Floor (above ground: the slab the floor below is roofed with, which
		# also makes the terrace around this floor).
		if t > 0:
			var below: float = PYR_HALF[t - 1]
			_slab_with_hole(g, c, y0, below, holes.get(t, []), stone)
		# Walls with doorways: all four sides on the ground floor, two above.
		var door_w = 3.0 if t == 0 else 2.2
		var door_h = 3.0 if t == 0 else 2.6
		var sides = [[1, 0], [-1, 0], [0, 1], [0, -1]]
		for sd in sides:
			var with_door = t == 0 or (t % 2 == 1 and sd[1] == 0) or (t % 2 == 0 and sd[0] == 0)
			_pyr_wall(g, c, y0, hh, sd, with_door, door_w, door_h, stone if t % 2 == 0 else stone.lightened(0.04), trim)
		# a stripe of trim around the top of each floor
		for sd in sides:
			var along_x = sd[1] != 0
			var pos = c + Vector3(float(sd[0]) * (hh + 0.02), y0 + PYR_TIER_H - 0.25, float(sd[1]) * (hh + 0.02))
			g.box(pos, Vector3(2.0 * hh + 0.1 if along_x else 0.12, 0.3, 0.12 if along_x else 2.0 * hh + 0.1), trim, Basis(), false)
		# torches inside
		if t < 3:
			var tl = OmniLight3D.new()
			tl.light_color = Color(1.0, 0.7, 0.35)
			tl.light_energy = 1.2
			tl.omni_range = hh * 1.3
			tl.position = c + Vector3(0, y0 + 3.0, -hh + 1.5)
			world_root.add_child(tl)
		g.box(c + Vector3(-hh + PYR_WALL + 0.1, y0 + 2.4, 0), Vector3(0.15, 0.5, 0.3), Color(1.0, 0.6, 0.2), Basis(), false)
	# Ramps between floors (inside).
	for r in PYR_RAMPS:
		var t2 = int(r[0])
		var dir2 = float(r[1])
		var zr2 = float(r[2])
		var xt2 = float(r[3])
		var ya = PYR_TIER_H * float(t2 - 1)
		var a = c + Vector3(xt2 - dir2 * 8.0, ya, zr2)
		var b = c + Vector3(xt2, ya + PYR_TIER_H, zr2)
		g.ramp(a, b, 2.4, 0.4, inner)
	# The roof of the 4th floor (open sky unless the Genie raised the tower).
	var top_y = PYR_TIER_H * 4.0
	var hatch = CROWN_LADDERS[0]
	_slab_with_hole(g, c, top_y, PYR_HALF[3], [hatch[2], hatch[3], hatch[4], hatch[5]], stone)
	# Ladders outside: ground -> 1st terrace on two sides, and up the others.
	var lad_specs = [
		[Vector3(7.0, 0, 14.0), Vector3(0, 0, 1)], [Vector3(-7.0, 0, -14.0), Vector3(0, 0, -1)],
		[Vector3(11.0, 4.0, 5.0), Vector3(1, 0, 0)], [Vector3(-11.0, 4.0, -5.0), Vector3(-1, 0, 0)],
		[Vector3(4.0, 8.0, 8.0), Vector3(0, 0, 1)], [Vector3(-4.0, 8.0, -8.0), Vector3(0, 0, -1)],
	]
	for ls in lad_specs:
		_create_ladder(c + ls[0], ls[1], PYR_TIER_H)
	g.finish(world_root, mat)
	# golden cap (sits on the roof while the tower is down)
	var cap = _pyr_cap(c + Vector3(0, top_y, 0), 1.6)
	world_root.add_child(cap)
	_build_crown(k, c, stone, trim, mat, cap)

func _pyr_cap(pos: Vector3, size: float) -> MeshInstance3D:
	var cap = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = size
	cm.height = size * 1.1
	cm.radial_segments = 4
	cm.rings = 1
	cap.mesh = cm
	cap.rotation.y = PI / 4.0
	cap.position = pos + Vector3(0, size * 0.55, 0)
	var gm = StandardMaterial3D.new()
	gm.albedo_color = Color(1.0, 0.78, 0.25)
	gm.metallic = 0.9
	gm.roughness = 0.25
	gm.emission_enabled = true
	gm.emission = Color(0.6, 0.4, 0.05)
	gm.emission_energy_multiplier = 0.3
	cap.material_override = gm
	return cap

# A floor slab of half-size hh at height y (top surface), with a rectangular
# hole [x0, x1, z0, z1] (relative to the pyramid) for a ramp or a ladder.
func _slab_with_hole(g: GeoBuilder, c: Vector3, y: float, hh: float, hole: Array, col: Color) -> void:
	var t = 0.3
	var yc = y - t / 2.0
	if hole.is_empty():
		g.box(c + Vector3(0, yc, 0), Vector3(hh * 2.0, t, hh * 2.0), col)
		return
	var x0: float = hole[0]
	var x1: float = hole[1]
	var z0: float = hole[2]
	var z1: float = hole[3]
	if x0 > -hh:
		g.box(c + Vector3((-hh + x0) / 2.0, yc, 0), Vector3(x0 + hh, t, hh * 2.0), col)
	if x1 < hh:
		g.box(c + Vector3((x1 + hh) / 2.0, yc, 0), Vector3(hh - x1, t, hh * 2.0), col)
	if z0 > -hh:
		g.box(c + Vector3((x0 + x1) / 2.0, yc, (-hh + z0) / 2.0), Vector3(x1 - x0, t, z0 + hh), col)
	if z1 < hh:
		g.box(c + Vector3((x0 + x1) / 2.0, yc, (z1 + hh) / 2.0), Vector3(x1 - x0, t, hh - z1), col)

# One wall of a floor; sd = which side ([1,0] = +x ...).
func _pyr_wall(g: GeoBuilder, c: Vector3, y0: float, hh: float, sd: Array, door: bool, door_w: float, door_h: float, col: Color, trim: Color) -> void:
	var along_x = sd[1] != 0 # the wall runs along x (it's on a +-z side)
	var w = PYR_WALL
	var length = hh * 2.0
	var off = hh - w / 2.0
	var center = c + Vector3(float(sd[0]) * off, y0, float(sd[1]) * off)
	var wall_h = PYR_TIER_H
	if not door:
		g.box(center + Vector3(0, wall_h / 2.0, 0), Vector3(length if along_x else w, wall_h, w if along_x else length), col)
		return
	var seg = (length - door_w) / 2.0
	for s in [-1.0, 1.0]:
		var o = s * (door_w / 2.0 + seg / 2.0)
		g.box(center + Vector3(o if along_x else 0.0, wall_h / 2.0, 0.0 if along_x else o), Vector3(seg if along_x else w, wall_h, w if along_x else seg), col)
	var lintel_h = wall_h - door_h
	g.box(center + Vector3(0, door_h + lintel_h / 2.0, 0), Vector3(door_w if along_x else w, lintel_h, w if along_x else door_w), trim)

# The Genie tower: four more floors on top of a pyramid, built hidden and
# switched on when the Genie appears there.
func _build_crown(k: int, c: Vector3, stone: Color, trim: Color, mat: Material, base_cap: Node3D) -> void:
	var root = Node3D.new()
	root.name = "Crown" + str(k)
	world_root.add_child(root)
	var g = GeoBuilder.new()
	var base_y = PYR_TIER_H * 4.0
	var hh = CROWN_HALF
	var w = CROWN_WALL
	var col = stone.lightened(0.06)
	for f in range(4):
		var y0 = base_y + PYR_TIER_H * float(f)
		# walls with a small window in each
		for sd in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var along_x = sd[1] != 0
			var off = hh - w / 2.0
			var center = c + Vector3(float(sd[0]) * off, y0, float(sd[1]) * off)
			var length = hh * 2.0
			var win_w = 1.4
			var sill = 1.3
			var win_top = 2.3
			g.box(center + Vector3(0, sill / 2.0, 0), Vector3(length if along_x else w, sill, w if along_x else length), col)
			g.box(center + Vector3(0, (win_top + PYR_TIER_H) / 2.0, 0), Vector3(length if along_x else w, PYR_TIER_H - win_top, w if along_x else length), col)
			var seg = (length - win_w) / 2.0
			for s in [-1.0, 1.0]:
				var o = s * (win_w / 2.0 + seg / 2.0)
				g.box(center + Vector3(o if along_x else 0.0, (sill + win_top) / 2.0, 0.0 if along_x else o), Vector3(seg if along_x else w, win_top - sill, w if along_x else seg), col)
			g.box(center + Vector3(float(sd[0]) * (w / 2.0 + 0.02), PYR_TIER_H - 0.2, float(sd[1]) * (w / 2.0 + 0.02)), Vector3(length + 0.1 if along_x else 0.1, 0.25, 0.1 if along_x else length + 0.1), trim, Basis(), false)
		# the floor above (with the hatch for the next ladder); the roof on top
		var above_y = y0 + PYR_TIER_H
		if f < 3:
			var lad = CROWN_LADDERS[f + 1]
			_slab_with_hole(g, c, above_y, hh, [lad[2], lad[3], lad[4], lad[5]], stone)
		else:
			_slab_with_hole(g, c, above_y, hh, [], stone)
	var body = g.finish(root, mat)
	var cap = _pyr_cap(c + Vector3(0, base_y + PYR_TIER_H * 4.0, 0), 2.2)
	root.add_child(cap)
	var light = OmniLight3D.new()
	light.light_color = Color(0.45, 0.85, 1.0)
	light.light_energy = 1.5
	light.omni_range = 6.0
	light.position = c + Vector3(0, base_y + PYR_TIER_H * 3.0 + 2.5, 0)
	root.add_child(light)
	# ladders (the first from the 4th floor up through the roof hatch)
	var ladders: Array = []
	for lad2 in CROWN_LADDERS:
		var fp: Vector3 = c + lad2[0]
		var n: Vector3 = lad2[1]
		var ladder = MapLadder.new(n, PYR_TIER_H + 1.0)
		ladder.hatch = true
		ladder.position = fp
		ladder.rotation.y = atan2(n.x, n.z)
		root.add_child(ladder)
		ladders.append(ladder)
		royale_ladders.append([fp, n, PYR_TIER_H + 1.0, fp + n * 2.0 + Vector3(0, PYR_TIER_H, 0)])
	# the lid over the roof hatch while the tower is down
	var lg = GeoBuilder.new()
	var h0 = CROWN_LADDERS[0]
	lg.box(c + Vector3((h0[2] + h0[3]) / 2.0, base_y - 0.15, (h0[4] + h0[5]) / 2.0), Vector3(h0[3] - h0[2], 0.3, h0[5] - h0[4]), stone)
	var lid = lg.finish(world_root, mat)
	desert_crowns.append({"root": root, "body": body, "lid": lid, "ladders": ladders, "cap": base_cap, "mat": mat})
	_set_crown_visual(k, false)

# Host, while the bots' map of the desert is made: every tower stands (but
# can't be seen), so their floors and ladders are in it.
func _desert_before_nav() -> void:
	for i in range(desert_crowns.size()):
		_set_crown_visual(i, true, i == desert_crown)

func _set_crown_visual(k: int, on: bool, show: bool = true) -> void:
	if k < 0 or k >= desert_crowns.size():
		return
	var cr: Dictionary = desert_crowns[k]
	(cr["root"] as Node3D).visible = on and show
	var body: StaticBody3D = cr["body"]
	body.collision_layer = 1 if on else 0
	var lid: StaticBody3D = cr["lid"]
	lid.collision_layer = 0 if on else 1
	lid.visible = not (on and show)
	(cr["cap"] as Node3D).visible = not (on and show)
	for l in cr["ladders"]:
		var ladder: MapLadder = l
		ladder.monitoring = on
		if not on and players_container:
			for p in players_container.get_children():
				if p is NetworkPlayer:
					p.exit_ladder(ladder)

# The Genie's pyramid rises (k = -1: none). Everyone runs this when the host says.
func desert_set_crown(k: int) -> void:
	if desert_crowns.is_empty():
		desert_crown = k
		return
	for i in range(desert_crowns.size()):
		_set_crown_visual(i, i == k)
	if k >= 0 and k != desert_crown:
		log_console("[Desert] The ground shakes... one of the pyramids rose to 8 floors!")
		_crown_dust(k)
	desert_crown = k
	_desert_crown_nav()

# Host: bots can only use the tower that's standing.
func _desert_crown_nav() -> void:
	if not rnav_ready or rnav == null or desert_crown_nav.is_empty():
		return
	for i in range(desert_crown_nav.size()):
		for id in desert_crown_nav[i]:
			rnav.set_point_disabled(int(id), i != desert_crown)
	for i in range(desert_crown_links.size()):
		var a = int(desert_crown_links[i][0])
		var b = int(desert_crown_links[i][1])
		if a < 0 or b < 0:
			continue
		if i == desert_crown:
			rnav.connect_points(a, b)
		elif rnav.are_points_connected(a, b):
			rnav.disconnect_points(a, b)

# After the host's bot map is built (with every tower up): note which points
# are inside each tower, then put the towers away.
func _desert_after_nav() -> void:
	desert_nav_crowns_done = true
	desert_crown_nav.clear()
	for k in range(DESERT_PYRAMIDS.size()):
		desert_crown_nav.append([])
	var reach = int(ceil(CROWN_HALF + 0.5))
	for k in range(DESERT_PYRAMIDS.size()):
		var c: Vector3 = DESERT_PYRAMIDS[k]
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				var cell = _rnav_cell(c.x + dx, c.z + dz)
				if cell < 0:
					continue
				for l in range(RNAV_LAYERS):
					var id = cell * RNAV_LAYERS + l
					if rnav_h[id] < -999.0:
						break
					if rnav_h[id] >= PYR_TIER_H * 4.0 + 0.5:
						desert_crown_nav[k].append(id)
	desert_crown_links.clear()
	for k2 in range(DESERT_PYRAMIDS.size()):
		var c2: Vector3 = DESERT_PYRAMIDS[k2]
		var l0 = CROWN_LADDERS[0]
		var fp: Vector3 = c2 + l0[0]
		var n: Vector3 = l0[1]
		var top_p = fp + n * 2.0 + Vector3(0, PYR_TIER_H, 0)
		desert_crown_links.append([_rnav_cell_near(fp + n * 1.0, fp.y), _rnav_cell_near(top_p, top_p.y)])
	for i in range(desert_crowns.size()):
		_set_crown_visual(i, i == desert_crown)
	_desert_crown_nav()

func _crown_dust(k: int) -> void:
	var c: Vector3 = DESERT_PYRAMIDS[k]
	var fx = ShotFx.new()
	fx.kind = "dust"
	fx.a = c + Vector3(0, PYR_TIER_H * 4.0, 0)
	fx.b = fx.a + Vector3(0, PYR_TIER_H * 4.0, 0)
	world_root.add_child(fx)

# Sky drop points: a ring around the desert.
func _desert_spawn_points() -> Array:
	var out: Array = []
	for i in range(ROYALE_MAX_PLAYERS):
		var a = TAU * float(i) / float(ROYALE_MAX_PLAYERS) + 0.13
		out.append(Vector3(cos(a) * 62.0, 1.0, sin(a) * 62.0))
	return out

# Swords and bows: out on the sand and on the pyramids' ground floors.
func _desert_weapon_spots() -> Array:
	var out: Array = []
	for i in range(10):
		var a = TAU * (float(i) + 0.5) / 10.0
		out.append(Vector3(cos(a) * 30.0, 1.0, sin(a) * 30.0))
	for i in range(12):
		var a2 = TAU * float(i) / 12.0 + 0.2
		out.append(Vector3(cos(a2) * 72.0, 1.0, sin(a2) * 72.0))
	for c in DESERT_PYRAMIDS:
		out.append(c + Vector3(-8.0, 1.0, 8.0))
		out.append(c + Vector3(8.0, 1.0, 8.0))
		out.append(c + Vector3(0, 5.0, 12.5)) # 1st terrace
	for c2 in [Vector3(-24, 0, 0), Vector3(24, 0, 0), Vector3(0, 0, 70), Vector3(0, 0, -70)]:
		out.append(c2 + (Vector3(2.5, 1.0, 0) if abs(c2.x) > 0 else Vector3(0, 1.0, 2.5)))
	out.append(Vector3(28, 1.0, 34.5)) # by the oasis
	return out

# Crystals: on the sand and the pyramids' 2nd floors.
func _desert_crystal_spots() -> Array:
	var out: Array = []
	for i in range(8):
		var a = TAU * float(i) / 8.0 + 0.3
		out.append(Vector3(cos(a) * 42.0, 1.0, sin(a) * 42.0))
	for i in range(8):
		var a2 = TAU * (float(i) + 0.5) / 8.0
		out.append(Vector3(cos(a2) * 62.0, 1.0, sin(a2) * 62.0))
	for c in DESERT_PYRAMIDS:
		out.append(c + Vector3(-6.5, 5.0, -6.5))
	return out

# Treasure (3rd and 4th floors of each pyramid), then a Genie spot at the top
# of each pyramid's tower.
func _desert_special_spots() -> Array:
	var out: Array = []
	for c in DESERT_PYRAMIDS:
		out.append(c + Vector3(5.0, 9.0, -5.0))
		out.append(c + Vector3(-2.5, 13.0, 2.5))
	for c2 in DESERT_PYRAMIDS:
		out.append(c2 + Vector3(1.5, PYR_TIER_H * 7.0 + 1.0, 1.5))
	return out

func _desert_genie_spot(k: int) -> int:
	return _royale_special_start() + DESERT_PYRAMIDS.size() * 2 + k

func _genie_on_map() -> bool:
	for id in royale_items:
		if String(royale_items[id]["type"]) == "genie":
			return true
	return false

# Host, with every weapon wave: a little treasure inside the pyramids.
func _desert_treasure_wave() -> void:
	var have = 0
	for id in royale_items:
		if DESERT_TREASURE.has(String(royale_items[id]["type"])):
			have += 1
	var start = _royale_special_start()
	var free = _royale_free_spots(start, start + DESERT_PYRAMIDS.size() * 2)
	var n = min(2, DESERT_MAX_TREASURE - have, free.size())
	var batch: Array = []
	for i in range(n):
		batch.append(_royale_new_item(int(free[i]), String(DESERT_TREASURE[randi() % DESERT_TREASURE.size()])))
	if not batch.is_empty():
		_royale_send_items(batch, "treasure")

# Host, with every crystal wave: if there's no Genie out there, one appears
# at the top of a random pyramid (not one the storm has taken), which rises.
func _desert_genie_wave() -> void:
	if _genie_on_map():
		return
	var options: Array = []
	for k in range(DESERT_PYRAMIDS.size()):
		if not storm_outside(DESERT_PYRAMIDS[k], 6.0):
			options.append(k)
	if options.is_empty():
		options = [0]
	var pick = int(options[randi() % options.size()])
	send_p2p_packet({"action": "crown", "k": pick})
	desert_set_crown(pick)
	_royale_send_items([_royale_new_item(_desert_genie_spot(pick), "genie")], "genie")

# --- THE WASTELAND (Huss Royale) ---
# A dead, green-hazed surface (dead trees, knocked-over buildings) where the
# radiation hurts: 5 damage every 5s above ground unless you wear a gas mask.
# The safe place is the bunker: its entrance is in the middle of the map and
# it goes two floors down (a medical room heals you a little). Long tunnels
# lead out to exits on two of the four sides (picked at random each round) -
# exits only: the hatches can't be opened from outside.
const WASTE_B1: float = -6.0 # floor heights
const WASTE_B2: float = -12.0
const WASTE_ROOM_H: float = 4.0
const WASTE_WALL: float = 0.4
const WASTE_RAD_EVERY: float = 5.0
const WASTE_RAD_DMG: int = 5
const WASTE_MED_EVERY: float = 2.0
const WASTE_MED_HEAL: int = 5
const WASTE_MED_RECT: Rect2 = Rect2(-20, -16, 12, 10) # x, z, w, d (B1)
# [name, tunnel start (on the hub / room wall), direction, shaft center, where you come out]
const WASTE_EXITS: Array = [
	["NORTH", Vector3(0, 0, 8), Vector3(0, 0, 1), Vector3(0, 0, 67.5), Vector3(0, 0.1, 63.5)],
	["SOUTH", Vector3(0, 0, -18), Vector3(0, 0, -1), Vector3(0, 0, -67.5), Vector3(0, 0.1, -63.5)],
	["EAST", Vector3(22, 0, -3), Vector3(1, 0, 0), Vector3(67.5, 0, -3), Vector3(63.5, 0.1, -3)],
	["WEST", Vector3(-22, 0, -3), Vector3(-1, 0, 0), Vector3(-67.5, 0, -3), Vector3(-63.5, 0.1, -3)],
]
var waste_open_exits: Array = [] # indices into WASTE_EXITS (2 of them)
var waste_rad_t: float = 0.0
var waste_med_t: float = 0.0
var waste_bot_rad: Dictionary = {}
var waste_bot_med: Dictionary = {}
var hazard_label: Label = null
var waste_flash_t: float = 0.0

func _waste_mat() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	return m

# Which two exits are open this round (from the host's seed: the same for everyone).
func _waste_pick_exits() -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = royale_seed + 77
	var order = [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var two = [order[0], order[1]]
	two.sort()
	return two

# A floor / ceiling slab: rect x0..x1, z0..z1 with its top at y.
func _slab(g: GeoBuilder, x0: float, x1: float, z0: float, z1: float, y: float, col: Color, thick: float = 0.3) -> void:
	g.box(Vector3((x0 + x1) / 2.0, y - thick / 2.0, (z0 + z1) / 2.0), Vector3(x1 - x0, thick, z1 - z0), col)

# A slab with rectangular holes ([x0, x1, z0, z1] each).
func _slab_holes(g: GeoBuilder, x0: float, x1: float, z0: float, z1: float, y: float, holes: Array, col: Color, thick: float = 0.3) -> void:
	var rects: Array = [[x0, x1, z0, z1]]
	for h in holes:
		var out: Array = []
		for r in rects:
			if h[0] >= r[1] or h[1] <= r[0] or h[2] >= r[3] or h[3] <= r[2]:
				out.append(r)
				continue
			if h[0] > r[0]:
				out.append([r[0], h[0], r[2], r[3]])
			if h[1] < r[1]:
				out.append([h[1], r[1], r[2], r[3]])
			var mx0 = max(r[0], h[0])
			var mx1 = min(r[1], h[1])
			if h[2] > r[2]:
				out.append([mx0, mx1, r[2], h[2]])
			if h[3] < r[3]:
				out.append([mx0, mx1, h[3], r[3]])
		rects = out
	for r in rects:
		if r[1] - r[0] > 0.01 and r[3] - r[2] > 0.01:
			_slab(g, r[0], r[1], r[2], r[3], y, col, thick)

# A wall along z at x (from z0 to z1), from y0 up h, with openings [[a, b, height]].
func _wall_x(g: GeoBuilder, x: float, z0: float, z1: float, y0: float, h: float, openings: Array, col: Color) -> void:
	_wall_line(g, x, z0, z1, y0, h, openings, col, false)

# A wall along x at z (from x0 to x1).
func _wall_z(g: GeoBuilder, z: float, x0: float, x1: float, y0: float, h: float, openings: Array, col: Color) -> void:
	_wall_line(g, z, x0, x1, y0, h, openings, col, true)

func _wall_line(g: GeoBuilder, fixed: float, a0: float, a1: float, y0: float, h: float, openings: Array, col: Color, along_x: bool) -> void:
	var w = WASTE_WALL
	var ops = openings.duplicate()
	ops.sort_custom(func(p, q): return p[0] < q[0])
	var cur = a0
	var segs: Array = []
	for o in ops:
		if o[0] > cur:
			segs.append([cur, o[0], 0.0, h])
		if float(o[2]) < h:
			segs.append([o[0], o[1], float(o[2]), h]) # lintel above the opening
		cur = max(cur, o[1])
	if cur < a1:
		segs.append([cur, a1, 0.0, h])
	for s in segs:
		var mid = (s[0] + s[1]) / 2.0
		var length = s[1] - s[0]
		var hy = s[3] - s[2]
		if length < 0.01 or hy < 0.01:
			continue
		var ctr = Vector3(mid, y0 + (s[2] + s[3]) / 2.0, fixed) if along_x else Vector3(fixed, y0 + (s[2] + s[3]) / 2.0, mid)
		g.box(ctr, Vector3(length, hy, w) if along_x else Vector3(w, hy, length), col)

# An underground room: floor, ceiling and the four walls (each wall: openings list).
func _waste_room(g: GeoBuilder, x0: float, x1: float, z0: float, z1: float, y: float, walls: Dictionary, col: Color, floor_col: Color, ceiling_holes: Array = [], floor_holes: Array = []) -> void:
	if floor_holes.is_empty():
		_slab(g, x0, x1, z0, z1, y, floor_col)
	else:
		_slab_holes(g, x0, x1, z0, z1, y, floor_holes, floor_col)
	var top = y + WASTE_ROOM_H
	_slab_holes(g, x0 - 0.2, x1 + 0.2, z0 - 0.2, z1 + 0.2, top + 0.3, ceiling_holes, col.darkened(0.25))
	for side in ["n", "s", "e", "w"]:
		if not walls.has(side):
			continue
		var ops: Array = walls[side]
		match side:
			"n":
				_wall_z(g, z1, x0 - 0.2, x1 + 0.2, y, WASTE_ROOM_H, ops, col)
			"s":
				_wall_z(g, z0, x0 - 0.2, x1 + 0.2, y, WASTE_ROOM_H, ops, col)
			"e":
				_wall_x(g, x1, z0 - 0.2, z1 + 0.2, y, WASTE_ROOM_H, ops, col)
			"w":
				_wall_x(g, x0, z0 - 0.2, z1 + 0.2, y, WASTE_ROOM_H, ops, col)

func _waste_light(pos: Vector3, col: Color, energy: float = 1.0, rng: float = 9.0) -> void:
	var l = OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	world_root.add_child(l)

func _waste_label(text: String, pos: Vector3, col: Color, yaw: float, size: int = 64) -> void:
	var lb = Label3D.new()
	lb.text = text
	lb.font_size = size
	lb.outline_size = 10
	lb.modulate = col
	lb.position = pos
	lb.rotation.y = yaw
	world_root.add_child(lb)

func _build_wasteland_map(_wall_color: Color) -> void :
	royale_ladders.clear()
	waste_open_exits = _waste_pick_exits()
	var mat = _waste_mat()
	var half = float(selected_map_data.get("size", 150.0)) / 2.0
	var concrete = Color(0.46, 0.47, 0.44)
	var dark_con = Color(0.33, 0.34, 0.32)
	var floor_col = Color(0.3, 0.31, 0.29)
	var dirt = Color(0.33, 0.36, 0.24)
	# --- the ground: one slab with holes for the stairs down and the exits ---
	var ground = GeoBuilder.new()
	var holes: Array = [[-1.8, 1.8, -0.5, 6.8]]
	for ei in waste_open_exits:
		var sc: Vector3 = WASTE_EXITS[ei][3]
		holes.append([sc.x - 1.5, sc.x + 1.5, sc.z - 1.5, sc.z + 1.5])
	_slab_holes(ground, -half, half, -half, half, 0.0, holes, dirt, 1.0)
	ground.finish(world_root, mat)
	nav_floor_rid = RID()

	# --- the entrance: a concrete hut over a ramp going down to B1 ---
	var b1 = GeoBuilder.new()
	b1.ramp(Vector3(0, 0, 6.8), Vector3(0, WASTE_B1, -5.2), 3.0, 0.4, dark_con)
	_slab(b1, -1.5, 1.5, -6.2, -5.1, WASTE_B1, floor_col) # landing at the bottom
	_wall_x(b1, -1.7, -6.0, 6.8, WASTE_B1, -WASTE_B1, [], concrete)
	_wall_x(b1, 1.7, -6.0, 6.8, WASTE_B1, -WASTE_B1, [], concrete)
	_wall_x(b1, -3.2, -1.0, 8.5, 0.0, 3.5, [], concrete)
	_wall_x(b1, 3.2, -1.0, 8.5, 0.0, 3.5, [], concrete)
	_wall_z(b1, -1.0, -3.4, 3.4, 0.0, 3.5, [], concrete)
	_wall_z(b1, 8.5, -3.4, 3.4, 0.0, 3.5, [[-1.8, 1.8, 2.8]], concrete)
	_slab(b1, -3.4, 3.4, -1.2, 8.7, 3.8, concrete)
	for i in range(6): # hazard stripes over the door
		b1.box(Vector3(-2.75 + i * 1.1, 3.15, 8.75), Vector3(0.55, 0.6, 0.1), Color(0.95, 0.8, 0.1) if i % 2 == 0 else Color(0.1, 0.1, 0.1), Basis(), false)
	_waste_label("BUNKER", Vector3(0, 4.4, 8.8), Color(1.0, 0.85, 0.2), 0.0, 96)
	_waste_light(Vector3(0, 2.8, 7.0), Color(1.0, 0.85, 0.5), 1.0, 7.0)

	# --- B1: hall, medical room, armory, control room, storage ---
	var y1 = WASTE_B1
	var pit = [-6.0, 6.0, -14.2, -11.4] # the ramp down to B2 goes through here
	_waste_room(b1, -8, 8, -16, -6, y1, {"n": [[-1.5, 1.5, 9.0]], "s": [[6.2, 7.8, 2.6]], "e": [[-10, -8, 2.6]], "w": [[-10, -8, 2.6]]}, concrete, floor_col, [], [pit])
	_waste_room(b1, -20, -8, -16, -6, y1, {"n": [], "s": [], "w": []}, Color(0.75, 0.78, 0.76), Color(0.62, 0.66, 0.64))
	_waste_room(b1, 8, 20, -16, -6, y1, {"n": [], "s": [], "e": []}, concrete, floor_col)
	_waste_room(b1, -8, 8, -26, -16, y1, {"s": [], "e": [], "w": [[-22, -20, 2.6]]}, concrete, floor_col)
	_waste_room(b1, -20, -8, -26, -16, y1, {"s": [], "w": []}, concrete, floor_col)
	# railings round the pit (open at the top of the ramp)
	_wall_z(b1, -11.2, -6.0, 6.2, y1, 1.0, [], Color(0.85, 0.7, 0.1))
	_wall_z(b1, -14.4, -6.0, 6.2, y1, 1.0, [], Color(0.85, 0.7, 0.1))
	_wall_x(b1, 6.2, -14.4, -11.2, y1, 1.0, [], Color(0.85, 0.7, 0.1))
	# medical room: beds, a green cross
	for i in range(3):
		b1.box(Vector3(-17.5, y1 + 0.35, -14.0 + i * 3.2), Vector3(3.0, 0.7, 1.4), Color(0.9, 0.92, 0.95))
		b1.box(Vector3(-18.6, y1 + 0.85, -14.0 + i * 3.2), Vector3(0.7, 0.3, 1.2), Color(1, 1, 1), Basis(), false)
	b1.box(Vector3(-19.75, y1 + 2.6, -11.0), Vector3(0.1, 1.6, 0.5), Color(0.2, 1.0, 0.35), Basis(), false)
	b1.box(Vector3(-19.75, y1 + 2.6, -11.0), Vector3(0.1, 0.5, 1.6), Color(0.2, 1.0, 0.35), Basis(), false)
	_waste_label("MEDICAL", Vector3(-8.25, y1 + 3.3, -9.0), Color(0.3, 1.0, 0.45), PI / 2.0, 48)
	_waste_light(Vector3(-14, y1 + 3.4, -11), Color(0.85, 1.0, 0.9), 1.2, 10.0)
	# armory: racks
	for i in range(3):
		b1.box(Vector3(19.4, y1 + 1.2, -14.5 + i * 3.5), Vector3(0.5, 2.4, 2.4), Color(0.3, 0.32, 0.28))
	_waste_label("ARMORY", Vector3(7.75, y1 + 3.3, -9.0), Color(1.0, 0.75, 0.3), -PI / 2.0, 48)
	_waste_light(Vector3(14, y1 + 3.4, -11), Color(1.0, 0.9, 0.7), 0.9, 10.0)
	# control room: desks with screens
	for i in range(4):
		b1.box(Vector3(-5.5 + i * 3.6, y1 + 0.5, -24.8), Vector3(2.6, 1.0, 1.0), Color(0.25, 0.27, 0.3))
		b1.box(Vector3(-5.5 + i * 3.6, y1 + 1.5, -25.4), Vector3(1.8, 1.0, 0.1), Color(0.2, 0.9, 0.5), Basis(), false)
	_waste_light(Vector3(0, y1 + 3.4, -21), Color(0.7, 1.0, 0.8), 0.9, 10.0)
	# storage: crates
	for i in range(5):
		b1.box(Vector3(-18.5 + (i % 3) * 2.2, y1 + 0.6 + (1.2 if i >= 3 else 0.0), -24.5 + (i % 2) * 1.3), Vector3(1.2, 1.2, 1.2), Color(0.45, 0.35, 0.2))
	_waste_light(Vector3(0, y1 + 3.4, -10), Color(1.0, 0.92, 0.75), 1.0, 11.0)
	b1.finish(world_root, mat)

	# --- B2: hub, generator room, mess hall, tunnels to the exits ---
	var b2 = GeoBuilder.new()
	var y2 = WASTE_B2
	b2.ramp(Vector3(-6.0, y1, -12.8), Vector3(6.0, y2, -12.8), 2.4, 0.4, dark_con)
	# the walls of the pit between the floors
	_wall_z(b2, -14.4, -6.0, 6.4, y2 + WASTE_ROOM_H - 0.3, 2.6, [], concrete)
	_wall_z(b2, -11.2, -6.0, 6.4, y2 + WASTE_ROOM_H - 0.3, 2.6, [], concrete)
	_wall_x(b2, 6.4, -14.4, -11.2, y2 + WASTE_ROOM_H - 0.3, 2.6, [], concrete)
	var hub_walls = {"n": [], "s": [], "e": [[-5, -3, 2.6]], "w": [[-5, -3, 2.6]]}
	# tunnel openings (open exits only; closed ones are caved in)
	if waste_open_exits.has(0):
		hub_walls["n"] = [[-1.5, 1.5, 3.2]]
	if waste_open_exits.has(1):
		hub_walls["s"] = [[-1.5, 1.5, 3.2]]
	_waste_room(b2, -10, 10, -18, 8, y2, hub_walls, concrete, floor_col, [pit])
	var gen_walls = {"n": [], "s": [], "e": [[-4.5, -1.5, 3.2]] if waste_open_exits.has(2) else []}
	_waste_room(b2, 10, 22, -10, 2, y2, gen_walls, concrete, floor_col)
	var mess_walls = {"n": [], "s": [], "w": [[-4.5, -1.5, 3.2]] if waste_open_exits.has(3) else []}
	_waste_room(b2, -22, -10, -10, 2, y2, mess_walls, concrete, floor_col)
	# generator: humming machines
	for i in range(2):
		b2.box(Vector3(16.0, y2 + 1.3, -7.0 + i * 5.0), Vector3(4.0, 2.6, 2.4), Color(0.35, 0.4, 0.3))
		b2.box(Vector3(16.0, y2 + 2.75, -7.0 + i * 5.0), Vector3(3.0, 0.3, 1.6), Color(0.9, 0.6, 0.1), Basis(), false)
	_waste_light(Vector3(16, y2 + 3.4, -4), Color(1.0, 0.7, 0.35), 1.0, 10.0)
	# mess hall: tables
	for i in range(3):
		b2.box(Vector3(-16.0, y2 + 0.45, -7.5 + i * 3.6), Vector3(5.0, 0.9, 1.2), Color(0.5, 0.42, 0.3))
	_waste_light(Vector3(-16, y2 + 3.4, -4), Color(1.0, 0.92, 0.75), 0.9, 10.0)
	_waste_light(Vector3(0, y2 + 3.4, -2), Color(0.85, 1.0, 0.8), 1.1, 13.0)
	_waste_label("B2", Vector3(-9.75, y2 + 3.0, 3.0), Color(1.0, 1.0, 0.6), PI / 2.0, 64)
	# rubble where the closed tunnels caved in
	for ei in range(4):
		if waste_open_exits.has(ei):
			continue
		var st: Vector3 = WASTE_EXITS[ei][1]
		var dir: Vector3 = WASTE_EXITS[ei][2]
		var side = Vector3(dir.z, 0, -dir.x)
		for k in range(5):
			var rp = st + Vector3(0, y2, 0) - dir * 1.0 + side * (float(k) - 2.0) * 0.7
			b2.box(rp + Vector3(0, 0.6 + (k % 2) * 0.5, 0), Vector3(1.2, 1.2 + (k % 3) * 0.4, 1.0), Color(0.4, 0.38, 0.34), Basis(Vector3.UP, 0.3 * k), false)
		_waste_label("COLLAPSED", st + Vector3(0, y2 + 3.0, 0) - dir * 0.3, Color(1.0, 0.4, 0.3), atan2(-dir.x, -dir.z), 40)
	b2.finish(world_root, mat)
	for ei in waste_open_exits:
		_waste_tunnel(int(ei), mat, concrete, floor_col)

	_build_waste_surface(mat, half)
	_royale_environment()

# A tunnel from the bunker out to an exit shaft, a ladder up, and the hatch.
func _waste_tunnel(ei: int, mat: Material, col: Color, floor_col: Color) -> void:
	var e: Array = WASTE_EXITS[ei]
	var st: Vector3 = e[1]
	var dir: Vector3 = e[2]
	var sc: Vector3 = e[3]
	var out_pos: Vector3 = e[4]
	var g = GeoBuilder.new()
	var y2 = WASTE_B2
	var along_z = abs(dir.z) > 0.5
	var length = (sc - st).dot(dir) - 1.5
	# floor, ceiling, side walls
	if along_z:
		var z0 = min(st.z, st.z + dir.z * length)
		var z1 = max(st.z, st.z + dir.z * length)
		_slab(g, -1.7, 1.7, z0, z1, y2, floor_col)
		_slab(g, -1.9, 1.9, z0, z1, y2 + 3.5 + 0.3, col.darkened(0.25))
		_wall_x(g, -1.7, z0, z1, y2, 3.5, [], col)
		_wall_x(g, 1.7, z0, z1, y2, 3.5, [], col)
	else:
		var x0 = min(st.x, st.x + dir.x * length)
		var x1 = max(st.x, st.x + dir.x * length)
		_slab(g, x0, x1, st.z - 1.7, st.z + 1.7, y2, floor_col)
		_slab(g, x0, x1, st.z - 1.9, st.z + 1.9, y2 + 3.5 + 0.3, col.darkened(0.25))
		_wall_z(g, st.z - 1.7, x0, x1, y2, 3.5, [], col)
		_wall_z(g, st.z + 1.7, x0, x1, y2, 3.5, [], col)
	# lights along it
	var n_l = int(length / 16.0)
	for i in range(n_l + 1):
		var lp = st + dir * (2.0 + float(i) * 16.0) + Vector3(0, y2 + 3.2, 0)
		_waste_light(lp, Color(1.0, 0.85, 0.55), 0.8, 9.0)
	# the shaft: 3x3, from the tunnel floor up to the surface
	var s0 = sc - Vector3(1.5, 0, 1.5)
	var s1 = sc + Vector3(1.5, 0, 1.5)
	_slab(g, s0.x - 0.2, s1.x + 0.2, s0.z - 0.2, s1.z + 0.2, y2, floor_col)
	var shaft_h = -y2
	# three closed sides + the side facing the tunnel open at the bottom
	var back = sc + dir * 1.5
	var side = Vector3(dir.z, 0, -dir.x)
	for sd in [1.0, -1.0]:
		var wc = sc + side * 1.5 * sd
		if along_z:
			_wall_x(g, wc.x, s0.z - 0.2, s1.z + 0.2, y2, shaft_h, [], col)
		else:
			_wall_z(g, wc.z, s0.x - 0.2, s1.x + 0.2, y2, shaft_h, [], col)
	if along_z:
		_wall_z(g, back.z, s0.x - 0.2, s1.x + 0.2, y2, shaft_h, [], col)
		_wall_z(g, sc.z - dir.z * 1.5, s0.x - 0.2, s1.x + 0.2, y2 + 3.5, shaft_h - 3.5, [], col)
	else:
		_wall_x(g, back.x, s0.z - 0.2, s1.z + 0.2, y2, shaft_h, [], col)
		_wall_x(g, sc.x - dir.x * 1.5, s0.z - 0.2, s1.z + 0.2, y2 + 3.5, shaft_h - 3.5, [], col)
	# the hatch on top (closed from outside) and a concrete collar round it
	g.box(sc + Vector3(0, 0.18, 0), Vector3(3.6, 0.36, 3.6), Color(0.35, 0.37, 0.3))
	g.box(sc + Vector3(0, 0.4, 0), Vector3(1.2, 0.1, 1.2), Color(0.85, 0.7, 0.1), Basis(), false)
	g.finish(world_root, mat)
	_waste_label("EXIT", sc + Vector3(0, y2 + 2.8, 0) - dir * 1.2, Color(0.4, 1.0, 0.4), atan2(-dir.x, -dir.z), 64)
	_waste_label("BUNKER EXIT\n(opens from inside only)", sc + Vector3(0, 1.6, 0), Color(1.0, 0.85, 0.3), atan2(-dir.x, -dir.z) + PI, 36)
	# ladder up the back wall
	var foot = back + Vector3(0, y2, 0)
	var ladder = MapLadder.new(-dir, shaft_h)
	ladder.position = foot
	ladder.rotation.y = atan2(-dir.x, -dir.z)
	world_root.add_child(ladder)
	# near the top of the shaft you climb out through the hatch (one way)
	var hatch = MapExitHatch.new(out_pos, -dir)
	hatch.position = sc + Vector3(0, -2.2, 0)
	world_root.add_child(hatch)
	royale_ladders.append([foot, -dir, shaft_h, out_pos, true])

func _build_waste_surface(mat: Material, half: float) -> void:
	var g = GeoBuilder.new()
	var rng = RandomNumberGenerator.new()
	rng.seed = 9090 # (the same wasteland on every screen; only the exits change)
	var avoid: Array = [Vector3(0, 0, 3)]
	for ei in range(4):
		avoid.append(WASTE_EXITS[ei][3])
	var free_spot = func(p: Vector3, r: float) -> bool:
		for a in avoid:
			if Vector2(p.x - a.x, p.z - a.z).length() < r:
				return false
		return true
	# knocked-over buildings: big concrete blocks lying at an angle
	var bcol = Color(0.42, 0.42, 0.39)
	var placed = 0
	var tries = 0
	while placed < 7 and tries < 60:
		tries += 1
		var a = rng.randf() * TAU
		var r = rng.randf_range(20.0, half - 12.0)
		var p = Vector3(cos(a) * r, 0, sin(a) * r)
		if not free_spot.call(p, 14.0):
			continue
		placed += 1
		avoid.append(p)
		var size = Vector3(rng.randf_range(7, 11), rng.randf_range(5, 9), rng.randf_range(6, 9))
		var tilt = Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(0.25, 0.6))
		g.box(p + Vector3(0, size.y * 0.32, 0), size, bcol.darkened(rng.randf_range(0.0, 0.15)), tilt)
		# dark window rows on it
		for wy in range(2):
			for wx in range(3):
				var lp = Vector3(-size.x * 0.3 + wx * size.x * 0.3, -size.y * 0.15 + wy * size.y * 0.35, size.z * 0.5 + 0.05)
				g.box(p + Vector3(0, size.y * 0.32, 0) + tilt * lp, Vector3(1.2, 1.0, 0.1), Color(0.12, 0.13, 0.12), tilt, false)
		# broken pieces next to it
		for k in range(3):
			var off = Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
			g.box(p + off + Vector3(0, 0.6, 0), Vector3(rng.randf_range(1.0, 2.5), rng.randf_range(0.6, 1.4), rng.randf_range(1.0, 2.5)), bcol.lightened(0.05), Basis(Vector3.UP, rng.randf() * TAU))
	# ruined walls (jagged tops)
	for i in range(9):
		var p2 = Vector3(rng.randf_range(-half + 8, half - 8), 0, rng.randf_range(-half + 8, half - 8))
		if not free_spot.call(p2, 9.0):
			continue
		avoid.append(p2)
		var yaw = rng.randf() * TAU
		var rot = Basis(Vector3.UP, yaw)
		for k in range(5):
			var hgt = rng.randf_range(1.2, 4.0)
			g.box(p2 + rot * Vector3(-4.0 + k * 2.0, hgt / 2.0, 0), Vector3(2.0, hgt, 0.5), Color(0.5, 0.47, 0.42), rot)
	# a fallen radio tower
	var tp = Vector3(-38, 0, 30)
	var trot = Basis(Vector3.UP, 0.7) * Basis(Vector3(0, 0, 1), PI / 2.0 - 0.12)
	g.box(tp + Vector3(0, 1.4, 0), Vector3(2.2, 22.0, 2.2), Color(0.55, 0.22, 0.15), trot)
	# wrecked cars
	for i in range(7):
		var cp = Vector3(rng.randf_range(-half + 10, half - 10), 0, rng.randf_range(-half + 10, half - 10))
		if not free_spot.call(cp, 6.0):
			continue
		var crot = Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.2, 0.2))
		var rust = Color(0.45, 0.25, 0.12).lerp(Color(0.3, 0.32, 0.3), rng.randf())
		g.box(cp + Vector3(0, 0.6, 0), Vector3(4.2, 1.0, 1.9), rust, crot)
		g.box(cp + crot * Vector3(-0.3, 1.35, 0), Vector3(2.0, 0.7, 1.7), rust.darkened(0.2), crot)
	# dead trees
	var bark = Color(0.24, 0.21, 0.18)
	var nt = 0
	var tt = 0
	while nt < 34 and tt < 120:
		tt += 1
		var p3 = Vector3(rng.randf_range(-half + 4, half - 4), 0, rng.randf_range(-half + 4, half - 4))
		if not free_spot.call(p3, 4.0):
			continue
		nt += 1
		var h3 = rng.randf_range(3.5, 7.0)
		var lean = Basis(Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU), rng.randf_range(0.0, 0.18))
		g.box(p3 + lean * Vector3(0, h3 / 2.0, 0), Vector3(0.35, h3, 0.35), bark, lean)
		for b in range(rng.randi_range(3, 5)):
			var by = h3 * rng.randf_range(0.45, 0.95)
			var ba = rng.randf() * TAU
			var blen = rng.randf_range(1.0, 2.4)
			var brot = lean * Basis(Vector3.UP, ba) * Basis(Vector3(0, 0, 1), rng.randf_range(0.6, 1.1))
			g.box(p3 + lean * Vector3(0, by, 0) + brot * Vector3(0, blen / 2.0, 0), Vector3(0.14, blen, 0.14), bark.lightened(0.05), brot, false)
	g.finish(world_root, mat)
	# glowing toxic puddles and barrels (looks only)
	var pmat = StandardMaterial3D.new()
	pmat.albedo_color = Color(0.3, 1.0, 0.2, 0.75)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.emission_enabled = true
	pmat.emission = Color(0.25, 0.9, 0.15)
	pmat.emission_energy_multiplier = 0.8
	for i in range(10):
		var pp = Vector3(rng.randf_range(-half + 6, half - 6), 0.03, rng.randf_range(-half + 6, half - 6))
		if not free_spot.call(pp, 5.0):
			continue
		var puddle = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = rng.randf_range(1.2, 3.0)
		cm.bottom_radius = cm.top_radius
		cm.height = 0.04
		puddle.mesh = cm
		puddle.scale = Vector3(1.0, 1.0, rng.randf_range(0.5, 1.0))
		puddle.position = pp
		puddle.material_override = pmat
		world_root.add_child(puddle)
	var barrel_mat = StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.85, 0.75, 0.1)
	for i in range(12):
		var bp = Vector3(rng.randf_range(-half + 6, half - 6), 0.0, rng.randf_range(-half + 6, half - 6))
		if not free_spot.call(bp, 5.0):
			continue
		var barrel = MeshInstance3D.new()
		var bm = CylinderMesh.new()
		bm.top_radius = 0.42
		bm.bottom_radius = 0.42
		bm.height = 1.1
		barrel.mesh = bm
		barrel.material_override = barrel_mat
		barrel.position = bp + Vector3(0, 0.55, 0)
		if i % 3 == 0:
			barrel.rotation = Vector3(PI / 2.0, rng.randf() * TAU, 0)
			barrel.position.y = 0.42
		world_root.add_child(barrel)

# Above ground = in the radiation (the entrance stairs count once you're
# down under the hut floor).
func waste_on_surface(p: Vector3) -> bool:
	return p.y > -1.5

func waste_in_medical(p: Vector3) -> bool:
	return p.y > WASTE_B1 - 0.6 and p.y < WASTE_B1 + 3.0 and WASTE_MED_RECT.has_point(Vector2(p.x, p.z))

# Radiation on the surface and healing in the medical room. Everyone does it
# for themselves; the host does it for the bots.
func _waste_tick(delta: float) -> void:
	if royale_time < ROYALE_GLIDE_TIME:
		return # (nobody gets hurt while they're still dropping in)
	var me = get_local_player()
	var hint = ""
	if me and not me.is_dead:
		var masked = gear_slot(local_peer_id, "mask") != ""
		if waste_on_surface(me.global_position) and not masked:
			waste_rad_t += delta
			hint = "RADIATION! -" + str(WASTE_RAD_DMG) + " HP every " + str(int(WASTE_RAD_EVERY)) + "s - get into the bunker (middle of the map) or find a gas mask"
			if waste_rad_t >= WASTE_RAD_EVERY:
				waste_rad_t = 0.0
				send_p2p_packet({"action": "take_damage", "peer_id": str(local_peer_id), "amount": WASTE_RAD_DMG})
				waste_flash_t = 0.35
				me.apply_damage(WASTE_RAD_DMG)
		else:
			waste_rad_t = 0.0
		if me and not me.is_dead and waste_in_medical(me.global_position):
			waste_med_t += delta
			if me.health < me.max_health:
				hint = "MEDICAL ROOM: +" + str(WASTE_MED_HEAL) + " HP every " + str(int(WASTE_MED_EVERY)) + "s"
			if waste_med_t >= WASTE_MED_EVERY:
				waste_med_t = 0.0
				if me.health < me.max_health:
					var amt = min(WASTE_MED_HEAL, me.max_health - me.health)
					send_p2p_packet({"action": "med_heal", "peer_id": local_peer_id, "amount": amt})
					me.heal(amt)
		else:
			waste_med_t = 0.0
	if waste_flash_t > 0.0:
		waste_flash_t -= delta
		if storm_tint:
			storm_tint.color = Color(0.3, 1.0, 0.2, 0.35)
			storm_tint.visible = true
	if hazard_label:
		hazard_label.text = hint
		hazard_label.visible = hint != ""
		hazard_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.35) if hint.begins_with("RAD") else Color(0.6, 1.0, 0.8))
	if is_host_peer:
		for pid in royale_bots:
			var b = get_player(pid)
			if b == null or b.is_dead:
				continue
			if waste_on_surface(b.global_position) and gear_slot(pid, "mask") == "":
				waste_bot_rad[pid] = float(waste_bot_rad.get(pid, 0.0)) + delta
				if float(waste_bot_rad[pid]) >= WASTE_RAD_EVERY:
					waste_bot_rad[pid] = 0.0
					send_p2p_packet({"action": "take_damage", "peer_id": str(pid), "amount": WASTE_RAD_DMG})
					b.apply_damage(WASTE_RAD_DMG)
			else:
				waste_bot_rad[pid] = 0.0
			if waste_in_medical(b.global_position) and b.health < b.max_health:
				waste_bot_med[pid] = float(waste_bot_med.get(pid, 0.0)) + delta
				if float(waste_bot_med[pid]) >= WASTE_MED_EVERY:
					waste_bot_med[pid] = 0.0
					var amt2 = min(WASTE_MED_HEAL, b.max_health - b.health)
					send_p2p_packet({"action": "med_heal", "peer_id": pid, "amount": amt2})
					b.heal(amt2)
			else:
				waste_bot_med[pid] = 0.0

# Bots: get under ground (no mask), or patch up in the medical room.
func waste_bot_goal(bot: NetworkPlayer):
	if royale_time < ROYALE_GLIDE_TIME:
		return null
	var masked = gear_slot(bot.peer_id, "mask") != ""
	if waste_on_surface(bot.global_position) and not masked:
		# a gas mask close by? grab it, then there's no need to hide
		for id in royale_items:
			if String(royale_items[id]["type"]) == "gasmask":
				var mp: Vector3 = royale_items[id]["pos"]
				if mp.y > -1.0 and mp.distance_to(bot.global_position) < 25.0:
					return mp
		return Vector3(0, WASTE_B1, -10.0) # into the bunker
	if bot.health <= bot.max_health - 30 and not waste_on_surface(bot.global_position):
		return Vector3(-14.0, WASTE_B1, -11.0) # the medical room
	return null

func _waste_spawn_points() -> Array:
	var out: Array = []
	for i in range(ROYALE_MAX_PLAYERS):
		var a = TAU * float(i) / float(ROYALE_MAX_PLAYERS) + 0.3
		out.append(Vector3(cos(a) * 50.0, 1.0, sin(a) * 50.0))
	return out

# Machetes, ballistic shields, rifles and gas masks: up top and down in the bunker.
func _waste_weapon_spots() -> Array:
	var out: Array = []
	for i in range(10):
		var a = TAU * (float(i) + 0.5) / 10.0
		out.append(Vector3(cos(a) * 26.0, 1.0, sin(a) * 26.0))
	for i in range(12):
		var a2 = TAU * float(i) / 12.0 + 0.15
		out.append(Vector3(cos(a2) * 52.0, 1.0, sin(a2) * 52.0))
	var y1 = WASTE_B1 + 1.0
	var y2 = WASTE_B2 + 1.0
	for p in [Vector3(12, y1, -8), Vector3(16, y1, -8), Vector3(12, y1, -14), Vector3(16, y1, -14), # armory
			Vector3(-5, y1, -8), Vector3(5, y1, -8), Vector3(-6, y1, -21), Vector3(-14, y1, -20),
			Vector3(-6, y2, 4), Vector3(6, y2, 4), Vector3(-6, y2, -6), Vector3(16, y2, 0), Vector3(-16, y2, 0)]:
		out.append(p)
	return out

func _waste_crystal_spots() -> Array:
	var out: Array = []
	for i in range(8):
		var a = TAU * float(i) / 8.0 + 0.4
		out.append(Vector3(cos(a) * 38.0, 1.0, sin(a) * 38.0))
	for i in range(6):
		var a2 = TAU * (float(i) + 0.5) / 6.0
		out.append(Vector3(cos(a2) * 62.0, 1.0, sin(a2) * 62.0))
	for p in [Vector3(-14, WASTE_B1 + 1.0, -8), Vector3(3, WASTE_B1 + 1.0, -21), Vector3(0, WASTE_B2 + 1.0, -4), Vector3(7, WASTE_B2 + 1.0, -16)]:
		out.append(p)
	return out


func _moon_tick(delta: float) -> void:
	_black_hole_tick(delta)
	var me = get_local_player()
	if hazard_label:
		var hint = ""
		if me and not me.is_dead and me.void_t > 0.05:
			hint = "LOST IN SPACE! " + str(snappedf(max(MOON_VOID_TIME - me.void_t, 0.0), 0.1)) + "s - drift back to the moon or an asteroid!"
		hazard_label.text = hint
		hazard_label.visible = hint != ""
		hazard_label.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))

# Map hazards a bot should get away from (null = none).
func bot_hazard_goal(bot: NetworkPlayer):
	match String(selected_map_data.get("mechanic", "")):
		"wasteland":
			return waste_bot_goal(bot)
		"moon":
			return moon_bot_goal(bot)
	return null

# Somewhere for a bot to wander to (the Wasteland: under ground, unless it
# has a gas mask).
func bot_roam_point(bot: NetworkPlayer) -> Vector3:
	if is_moon():
		return moon_random_point()
	if String(selected_map_data.get("mechanic", "")) == "wasteland" and gear_slot(bot.peer_id, "mask") == "" and royale_time >= ROYALE_GLIDE_TIME - 3.0:
		for _i in range(16):
			var p = rnav_random_point()
			if p.y < -3.0:
				return p
		return Vector3(0, WASTE_B1, -10.0)
	return rnav_random_point()

# --- THE MOON (Huss Royale) ---
# A small moon you can walk all the way around: gravity pulls toward its
# middle, so "down" is always under your feet. Asteroids float further out,
# each with its own little gravity; launch pads throw you across the gap and
# back. Lose every pull (fall into the gap between them) for a few seconds
# and you're lost in space. Portals take you straight to the other side.
# Weapons: the Plasma Sword (hits from further away) and the Raygun (blue
# beams). Special: the Black Hole - everyone gets 30s to find one of the mini
# bunkers that appear; each holds 3. Everyone else is pulled in.
const MOON_R: float = 30.0
const MOON_FIELD: float = 24.0 # the moon's pull reaches this far above its surface
const MOON_G: float = 13.0
const AST_FIELD: float = 7.0
const MOON_VOID_TIME: float = 2.5 # seconds adrift with no pull at all = lost in space
const MOON_NORTH: Vector3 = Vector3(0, 1, 0) # the storm closes in on the north pole
const MOON_PORTALS: Array = [Vector3(1, 0.35, 0.2), Vector3(-0.3, 0.2, 1), Vector3(0.5, -0.9, -0.4)] # each pairs with its opposite
const BH_TIME: float = 30.0
const BH_CAPACITY: int = 3
var moon_asteroids: Array = [] # [center, radius, return pad direction]
var moon_pads: Array = []
var bh_active: bool = false
var bh_t: float = 0.0
var bh_by: int = -1
var bh_bunkers: Array = [] # [{"pos", "up", "fwd", "node", "label", "slots": [pids]}]
var bh_fx: Node3D = null
var bh_my_bunker: int = -1
var bh_full_ms: int = -100000
var bh_label: Label = null
var bh_suck: Dictionary = {} # pid -> time being pulled in
var moon_storm_shell: MeshInstance3D = null
var moon_storm_mat: ShaderMaterial = null
var use_held_last: bool = false

const MOON_STORM_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec3 north = vec3(0.0, 1.0, 0.0);
uniform float cos_t = -1.0;
uniform vec4 col : source_color = vec4(0.03, 0.0, 0.07, 0.82);
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float c = dot(normalize(lp), north);
	if (c > cos_t) { discard; }
	float edge = clamp((cos_t - c) * 6.0, 0.0, 1.0);
	ALBEDO = mix(vec3(0.35, 0.1, 0.6), col.rgb, edge);
	ALPHA = col.a * mix(0.6, 1.0, edge);
}
"""

func is_moon() -> bool:
	return is_royale and String(selected_map_data.get("mechanic", "")) == "moon"

# [up, pull strength, body]: body 0 = the moon, k + 1 = asteroid k, -1 = none.
func moon_gravity(p: Vector3) -> Array:
	var d = p.length()
	if d <= MOON_R + MOON_FIELD:
		return [p / max(d, 0.001), MOON_G, 0]
	for i in range(moon_asteroids.size()):
		var a = moon_asteroids[i]
		var v: Vector3 = p - a[0]
		var dl = v.length()
		if dl <= float(a[1]) + AST_FIELD:
			return [v / max(dl, 0.001), MOON_G, i + 1]
	return [Vector3.ZERO, 0.0, -1]

# A basis with this up, facing (roughly) fwd.
static func basis_up(up: Vector3, fwd: Vector3 = Vector3.FORWARD) -> Basis:
	var y = up.normalized()
	var f = fwd - y * fwd.dot(y)
	if f.length() < 0.01:
		f = Vector3.RIGHT.cross(y) if abs(y.x) < 0.9 else Vector3.FORWARD.cross(y)
	var z = -f.normalized()
	var x = y.cross(z).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()

# Points spread evenly over a sphere (golden spiral).
static func sphere_points(n: int, offset: float = 0.0) -> Array:
	var out: Array = []
	var golden = PI * (3.0 - sqrt(5.0))
	for i in range(n):
		var y = 1.0 - (float(i) + 0.5) / float(n) * 2.0
		var r = sqrt(max(0.0, 1.0 - y * y))
		var th = golden * float(i) + offset
		out.append(Vector3(cos(th) * r, y, sin(th) * r))
	return out

func _moon_layout() -> void:
	moon_asteroids.clear()
	var dirs = sphere_points(10, 0.7)
	var rng = RandomNumberGenerator.new()
	rng.seed = 5151
	for i in range(dirs.size()):
		var d: Vector3 = dirs[i]
		var r = rng.randf_range(5.5, 7.5)
		var dist = MOON_R + MOON_FIELD + 5.0 + AST_FIELD + r + rng.randf_range(0.0, 3.0)
		var side = d.cross(Vector3.UP if abs(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var pad_dir = (-d).rotated(side, deg_to_rad(55.0)).normalized()
		moon_asteroids.append([d * dist, r, pad_dir])

func _moon_mat(c: Color, rough: float = 0.95) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _build_moon_map(_wall_color: Color) -> void :
	royale_ladders.clear()
	_moon_layout()
	var rng = RandomNumberGenerator.new()
	rng.seed = 7171
	# the moon
	var moon = StaticBody3D.new()
	moon.name = "Moon"
	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = MOON_R
	sm.height = MOON_R * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	mi.mesh = sm
	mi.material_override = _moon_mat(Color(0.6, 0.6, 0.63))
	moon.add_child(mi)
	var cs = CollisionShape3D.new()
	var ss = SphereShape3D.new()
	ss.radius = MOON_R
	cs.shape = ss
	moon.add_child(cs)
	world_root.add_child(moon)
	# craters and dark "seas" (looks only)
	var crater_mat = _moon_mat(Color(0.47, 0.47, 0.5))
	var rim_mat = _moon_mat(Color(0.7, 0.7, 0.72))
	for i in range(46):
		var d = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var cr = rng.randf_range(1.2, 4.5)
		var b = basis_up(d)
		var disk = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = cr
		cm.bottom_radius = cr
		cm.height = 0.05
		cm.radial_segments = 20
		disk.mesh = cm
		disk.material_override = crater_mat
		disk.transform = Transform3D(b, d * (MOON_R + 0.02))
		world_root.add_child(disk)
		var rim = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = cr
		tm.outer_radius = cr + 0.35
		tm.rings = 20
		rim.mesh = tm
		rim.material_override = rim_mat
		rim.transform = Transform3D(b.scaled(Vector3(1, 0.35, 1)), d * (MOON_R + 0.03))
		world_root.add_child(rim)
	for i in range(5):
		var d2 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var sea = MeshInstance3D.new()
		var cm2 = CylinderMesh.new()
		cm2.top_radius = rng.randf_range(7.0, 11.0)
		cm2.bottom_radius = cm2.top_radius
		cm2.height = 0.04
		cm2.radial_segments = 28
		sea.mesh = cm2
		sea.material_override = _moon_mat(Color(0.4, 0.4, 0.44))
		sea.transform = Transform3D(basis_up(d2), d2 * (MOON_R + 0.01))
		world_root.add_child(sea)
	# boulders to hide behind
	var rock_mat = _moon_mat(Color(0.52, 0.5, 0.5))
	for i in range(18):
		var d3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var rr = rng.randf_range(0.9, 1.8)
		_moon_rock(d3 * (MOON_R + rr * 0.5), rr, rock_mat, rng)
	# asteroids (each with its own pull) and the pads between them and the moon
	var ast_mat = _moon_mat(Color(0.42, 0.38, 0.36))
	moon_pads.clear()
	for i in range(moon_asteroids.size()):
		var a = moon_asteroids[i]
		_moon_rock(a[0], float(a[1]), ast_mat, rng, true)
		var d4: Vector3 = (a[0] as Vector3).normalized()
		# moon -> asteroid: straight up from the point under it
		var launch = sqrt(36.0 + 2.0 * MOON_G * MOON_FIELD) + 1.0
		_moon_pad(d4 * MOON_R, d4, d4 * launch, Color(0.3, 0.8, 1.0))
		# asteroid -> moon: from its moon-facing side
		var pd: Vector3 = a[2]
		var pp = (a[0] as Vector3) + pd * float(a[1])
		var back = sqrt(36.0 + 2.0 * MOON_G * AST_FIELD) + 2.0
		_moon_pad(pp, pd, (-(pp.normalized())) * back, Color(1.0, 0.6, 0.2))
	# portals: each pair on opposite sides
	for pdir in MOON_PORTALS:
		var pa = (pdir as Vector3).normalized()
		_moon_portal(pa, -pa)
		_moon_portal(-pa, pa)
	# stars, the Earth, the sun
	var stars = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q = QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var smat = StandardMaterial3D.new()
	smat.albedo_color = Color(1, 1, 1)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = smat
	mm.mesh = q
	mm.instance_count = 700
	for i in range(mm.instance_count):
		var sd = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), sd * 420.0))
	stars.multimesh = mm
	stars.extra_cull_margin = 1000.0
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(stars)
	var earth = MeshInstance3D.new()
	var em = SphereMesh.new()
	em.radius = 26.0
	em.height = 52.0
	earth.mesh = em
	var emat = StandardMaterial3D.new()
	emat.albedo_color = Color(0.25, 0.45, 0.9)
	emat.emission_enabled = true
	emat.emission = Color(0.1, 0.25, 0.6)
	emat.emission_energy_multiplier = 0.5
	earth.material_override = emat
	earth.position = Vector3(160, 120, -260)
	world_root.add_child(earth)
	# the dark matter storm: a shell over everything outside the safe cap
	moon_storm_mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = MOON_STORM_SHADER
	moon_storm_mat.shader = sh
	moon_storm_mat.set_shader_parameter("north", MOON_NORTH)
	moon_storm_mat.set_shader_parameter("cos_t", -1.0)
	for shell_r in [MOON_R + 0.3, MOON_R + 9.0]:
		var shell = MeshInstance3D.new()
		var shm = SphereMesh.new()
		shm.radius = shell_r
		shm.height = shell_r * 2.0
		shm.radial_segments = 64
		shm.rings = 32
		shell.mesh = shm
		shell.material_override = moon_storm_mat
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(shell)
		moon_storm_shell = shell
	_royale_environment()
	for c in world_root.get_children():
		if c is DirectionalLight3D:
			c.rotation_degrees = Vector3(-35, 30, 0)

# A lumpy rock; collide: a ball you can stand on (asteroids: walk all round it).
func _moon_rock(center: Vector3, r: float, mat: Material, rng: RandomNumberGenerator, big: bool = false) -> void:
	var body = StaticBody3D.new()
	body.position = center
	var mesh_i = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 24 if big else 10
	sm.rings = 12 if big else 6
	var st = SurfaceTool.new()
	st.create_from(sm, 0)
	var arr = st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var noise = FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.6 / r
	for i in range(verts.size()):
		var v = verts[i]
		verts[i] = v * (1.0 + (0.14 if big else 0.1) * noise.get_noise_3dv(v))
	arr[Mesh.ARRAY_VERTEX] = verts
	var am = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st2 = SurfaceTool.new()
	st2.create_from(am, 0)
	st2.generate_normals()
	mesh_i.mesh = st2.commit()
	mesh_i.material_override = mat
	body.add_child(mesh_i)
	var cs = CollisionShape3D.new()
	if big:
		cs.shape = mesh_i.mesh.create_trimesh_shape() # (walk on the real lumpy surface)
	else:
		var ss = SphereShape3D.new()
		ss.radius = r * 0.9
		cs.shape = ss
	body.add_child(cs)
	world_root.add_child(body)

func _moon_pad(pos: Vector3, up: Vector3, launch: Vector3, col: Color) -> void:
	var pad = MoonPad.new()
	pad.launch = launch
	pad.col = col
	pad.transform = Transform3D(basis_up(up), pos)
	world_root.add_child(pad)
	moon_pads.append(pad)

func _moon_portal(at: Vector3, to: Vector3) -> void:
	var p = MoonPortal.new()
	p.dest = to * (MOON_R + 0.15)
	p.dest_up = to
	p.transform = Transform3D(basis_up(at), at * MOON_R)
	world_root.add_child(p)

# Sky drop: spread round the moon, high above it.
func _moon_spawn_points() -> Array:
	var out: Array = []
	for d in sphere_points(ROYALE_MAX_PLAYERS, 0.4):
		out.append((d as Vector3) * (MOON_R + 20.0))
	return out

# Weapons: all over the moon, plus one on each asteroid.
func _moon_weapon_spots() -> Array:
	var out: Array = []
	for d in sphere_points(30, 0.1):
		out.append((d as Vector3) * (MOON_R + 1.0))
	for a in moon_asteroids_layout():
		var away: Vector3 = (a[0] as Vector3).normalized()
		out.append((a[0] as Vector3) + away * (float(a[1]) + 1.0))
	return out

func _moon_crystal_spots() -> Array:
	var out: Array = []
	for d in sphere_points(16, 1.3):
		out.append((d as Vector3) * (MOON_R + 1.0))
	for a in moon_asteroids_layout():
		var side = (a[2] as Vector3).cross((a[0] as Vector3).normalized()).normalized()
		out.append((a[0] as Vector3) + side * (float(a[1]) + 1.0))
	return out

# Black Hole items: anywhere on the moon.
func _moon_special_spots() -> Array:
	var out: Array = []
	for d in sphere_points(8, 2.1):
		out.append((d as Vector3) * (MOON_R + 1.0))
	return out

func moon_asteroids_layout() -> Array:
	if moon_asteroids.is_empty():
		_moon_layout()
	return moon_asteroids

# Each item floats "up" from wherever it is (the moon: straight out from its middle).
func item_up(pos: Vector3) -> Vector3:
	if not is_moon():
		return Vector3.UP
	var gi = moon_gravity(pos)
	return gi[0] if int(gi[2]) >= 0 else pos.normalized()

# Is a player standing at an item? (measured along the item's own up)
func item_touching(item_pos: Vector3, up: Vector3, p: NetworkPlayer) -> bool:
	var d = p.global_position + p._up() * 0.9 - item_pos
	var along = d.dot(up)
	return (d - up * along).length() < 1.3 and abs(along) < 1.8

# A random spot on the moon for a bot to head to (outside the storm).
func moon_random_point() -> Vector3:
	for _i in range(20):
		var d = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var p = d * MOON_R
		if not storm_outside(p, -6.0):
			return p
	return MOON_NORTH * MOON_R

# Host, with every crystal wave: a Black Hole item if there isn't one around.
func _moon_special_wave() -> void:
	if bh_active:
		return
	for id in royale_items:
		if String(royale_items[id]["type"]) == "blackhole":
			return
	for pid in player_gear:
		if String(player_gear[pid].get("special", "")) == "blackhole":
			return
	var start = _royale_special_start()
	var free = _royale_free_spots(start, start + 8)
	if free.is_empty():
		return
	_royale_send_items([_royale_new_item(int(free[0]), "blackhole")], "blackhole")

# --- THE BLACK HOLE ---
# Whoever holds it presses F (USE): the host places the bunkers (enough for
# everyone, 3 to a bunker, spread round the moon) and starts the clock.
func use_special() -> void:
	if gear_slot(local_peer_id, "special") != "blackhole" or bh_active:
		return
	if is_host_peer:
		_host_start_black_hole(local_peer_id)
	else:
		send_p2p_packet({"action": "bh_use"})

func _host_start_black_hole(by: int) -> void:
	if bh_active or gear_slot(by, "special") != "blackhole":
		return
	var alive = 0
	for pid in all_player_ids():
		if not dead_peers.has(pid):
			alive += 1
	var n = max(1, int(ceil(float(alive) / float(BH_CAPACITY))))
	var dirs: Array = []
	var tries = 0
	while dirs.size() < n and tries < 400:
		tries += 1
		var d = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		if storm_outside(d * MOON_R, 3.0):
			continue
		var ok = true
		for o in dirs:
			if (o as Vector3).angle_to(d) < 0.55:
				ok = false
				break
		if ok:
			dirs.append(d)
	while dirs.size() < n:
		dirs.append(MOON_NORTH.rotated(Vector3.RIGHT, 0.3 * dirs.size()))
	var arr: Array = []
	for d in dirs:
		arr.append([snappedf(d.x, 0.001), snappedf(d.y, 0.001), snappedf(d.z, 0.001)])
	var pkt = {"action": "bh_start", "by": by, "b": arr}
	send_p2p_packet(pkt)
	_apply_black_hole(pkt)

func _apply_black_hole(data: Dictionary) -> void:
	if bh_active or not world_root:
		return
	bh_active = true
	bh_t = BH_TIME
	bh_by = int(data.get("by", -1))
	bh_my_bunker = -1
	bh_suck.clear()
	var g = gear_of(bh_by).duplicate()
	g.erase("special")
	player_gear[bh_by] = g
	var who = "You" if bh_by == local_peer_id else String(player_nicknames.get(bh_by, "Someone"))
	log_console("[Moon] " + who + " unleashed a BLACK HOLE! " + str(int(BH_TIME)) + "s to get into a bunker - 3 per bunker!")
	for e in bh_bunkers:
		if is_instance_valid(e["node"]):
			e["node"].queue_free()
	bh_bunkers.clear()
	for v in data.get("b", []):
		if v is Array and v.size() >= 3:
			var d = Vector3(float(v[0]), float(v[1]), float(v[2])).normalized()
			_build_mini_bunker(d)
	if bh_fx and is_instance_valid(bh_fx):
		bh_fx.queue_free()
	bh_fx = BlackHoleFx.new()
	bh_fx.position = -MOON_NORTH.rotated(Vector3.RIGHT, 0.5) * 140.0
	world_root.add_child(bh_fx)
	_update_team_hud()

func _build_mini_bunker(d: Vector3) -> void:
	var fwd = d.cross(Vector3.UP if abs(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var b = basis_up(d, fwd)
	var root = Node3D.new()
	root.transform = Transform3D(b, d * MOON_R)
	world_root.add_child(root)
	var g = GeoBuilder.new()
	var col = Color(0.55, 0.57, 0.6)
	var stripe = Color(0.95, 0.75, 0.1)
	# 3.4m inside, 2.6m tall, a doorway in front (-z)
	g.box(Vector3(0, 0.1, 0), Vector3(4.4, 0.4, 4.4), col.darkened(0.2)) # floor pad
	g.box(Vector3(-2.0, 1.4, 0), Vector3(0.4, 2.6, 4.4), col)
	g.box(Vector3(2.0, 1.4, 0), Vector3(0.4, 2.6, 4.4), col)
	g.box(Vector3(0, 1.4, 2.0), Vector3(3.6, 2.6, 0.4), col)
	g.box(Vector3(-1.3, 1.4, -2.0), Vector3(1.0, 2.6, 0.4), col)
	g.box(Vector3(1.3, 1.4, -2.0), Vector3(1.0, 2.6, 0.4), col)
	g.box(Vector3(0, 2.4, -2.0), Vector3(1.6, 0.6, 0.4), stripe)
	g.box(Vector3(0, 2.9, 0), Vector3(4.6, 0.4, 4.6), col.darkened(0.1)) # roof
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	g.finish(root, mat)
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.light_energy = 1.2
	light.omni_range = 5.0
	light.position = Vector3(0, 2.2, 0)
	root.add_child(light)
	var lbl = Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 44
	lbl.outline_size = 10
	lbl.position = Vector3(0, 4.2, 0)
	lbl.modulate = Color(1.0, 0.85, 0.3)
	lbl.no_depth_test = true
	root.add_child(lbl)
	bh_bunkers.append({"pos": d * MOON_R, "up": d, "basis": b, "node": root, "label": lbl, "slots": []})
	_refresh_bunker_labels()

func _refresh_bunker_labels() -> void:
	for e in bh_bunkers:
		var n = (e["slots"] as Array).size()
		(e["label"] as Label3D).text = "BUNKER  " + str(n) + "/" + str(BH_CAPACITY) + ("  FULL" if n >= BH_CAPACITY else "")
		(e["label"] as Label3D).modulate = Color(1.0, 0.35, 0.3) if n >= BH_CAPACITY else Color(1.0, 0.85, 0.3)

# Which bunker (if any) a point is inside.
func bunker_at(p: Vector3) -> int:
	for i in range(bh_bunkers.size()):
		var e = bh_bunkers[i]
		var local = (e["basis"] as Basis).inverse() * (p - (e["pos"] as Vector3))
		if abs(local.x) < 1.8 and abs(local.z) < 1.8 and local.y > -0.5 and local.y < 2.6:
			return i
	return -1

# Host: someone wants a place in a bunker (first come, first served).
func _host_bunker_claim(pid: int, idx: int) -> void:
	if not bh_active:
		return
	for e in bh_bunkers:
		(e["slots"] as Array).erase(pid)
	if idx >= 0 and idx < bh_bunkers.size():
		var slots: Array = bh_bunkers[idx]["slots"]
		if slots.size() < BH_CAPACITY:
			slots.append(pid)
		else:
			send_p2p_packet({"action": "bh_full", "pid": pid, "b": idx})
			if pid == local_peer_id:
				_bunker_turned_away(idx)
	var state: Array = []
	for e in bh_bunkers:
		state.append(e["slots"])
	send_p2p_packet({"action": "bh_slots", "s": state})
	_refresh_bunker_labels()

func _apply_bunker_slots(state) -> void:
	if not (state is Array):
		return
	for i in range(min(state.size(), bh_bunkers.size())):
		var s: Array = []
		for v in state[i]:
			s.append(int(v))
		bh_bunkers[i]["slots"] = s
	_refresh_bunker_labels()

# That bunker is full: back out of the door.
func _bunker_turned_away(idx: int) -> void:
	bh_full_ms = _now_ms()
	var me = get_local_player()
	if me and idx >= 0 and idx < bh_bunkers.size():
		var e = bh_bunkers[idx]
		me.global_position = (e["pos"] as Vector3) + (e["basis"] as Basis) * Vector3(0, 0.3, -3.6)
		me.velocity = Vector3.ZERO
	log_console("[Moon] That bunker is full (3 inside)! Find another one!")
	bh_my_bunker = -1

func _black_hole_tick(delta: float) -> void:
	if not bh_active:
		if bh_label:
			bh_label.visible = false
		return
	bh_t -= delta
	var me = get_local_player()
	# where am I?
	if me and not me.is_dead:
		var inside = bunker_at(me.global_position)
		if inside != bh_my_bunker:
			bh_my_bunker = inside
			if is_host_peer:
				_host_bunker_claim(local_peer_id, inside)
			else:
				send_p2p_packet({"action": "bh_enter", "b": inside})
	if is_host_peer:
		for pid in royale_bots:
			var bt = get_player(pid)
			if bt == null or bt.is_dead:
				continue
			var bi = bunker_at(bt.global_position)
			var cur = -1
			for i in range(bh_bunkers.size()):
				if (bh_bunkers[i]["slots"] as Array).has(pid):
					cur = i
			if bi != cur and (bi < 0 or (bh_bunkers[bi]["slots"] as Array).size() < BH_CAPACITY):
				_host_bunker_claim(pid, bi)
	if bh_label:
		var mine_ok = false
		for e in bh_bunkers:
			if (e["slots"] as Array).has(local_peer_id):
				mine_ok = true
		if bh_t > 0.0:
			bh_label.text = "BLACK HOLE in " + str(int(ceil(bh_t))) + "s!  " + ("You're safe in a bunker - stay inside." if mine_ok else ("That bunker is FULL - find another!" if _now_ms() - bh_full_ms < 2500 else "Get into a bunker (3 per bunker)!"))
		else:
			bh_label.text = "THE BLACK HOLE IS PULLING EVERYTHING IN!"
		bh_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if mine_ok else Color(0.85, 0.55, 1.0))
		bh_label.visible = me != null and not me.is_dead
	if bh_t <= 0.0 and is_host_peer and bh_t > -100.0:
		bh_t = -1000.0
		var safe: Array = []
		for e in bh_bunkers:
			safe.append_array(e["slots"])
		var pkt = {"action": "bh_collapse", "safe": safe}
		send_p2p_packet(pkt)
		_apply_bh_collapse(pkt)
	# pull the unlucky ones in
	for pid in bh_suck.keys():
		var p = get_player(int(pid))
		if p == null or p.is_dead:
			bh_suck.erase(pid)
			continue
		bh_suck[pid] = float(bh_suck[pid]) + delta
		if bh_fx and is_instance_valid(bh_fx):
			var to = (bh_fx.global_position - p.global_position)
			p.global_position += to.normalized() * min(to.length(), (12.0 + 40.0 * float(bh_suck[pid])) * delta)
		if float(bh_suck[pid]) >= 1.6:
			bh_suck.erase(pid)
			if int(pid) == local_peer_id:
				log_console("[Moon] You were pulled into the black hole!")
				kill_local_player_from_fall()
			elif p.is_bot and is_host_peer:
				kill_bot_from_fall(p)

func _apply_bh_collapse(data: Dictionary) -> void:
	if not bh_active:
		return
	bh_t = -1000.0
	var safe: Array = []
	for v in data.get("safe", []):
		safe.append(int(v))
	for pid in all_player_ids():
		if dead_peers.has(pid) or safe.has(pid):
			continue
		var p = get_player(pid)
		if p:
			bh_suck[pid] = 0.0
			p.set_physics_process(pid != local_peer_id and not (p.is_bot and is_host_peer))
	var me_safe = safe.has(local_peer_id)
	log_console("[Moon] The black hole collapses!" + (" You made it - the bunker held." if me_safe else ""))
	get_tree().create_timer(2.5).timeout.connect(_end_black_hole)

func _end_black_hole() -> void:
	bh_active = false
	bh_suck.clear()
	for e in bh_bunkers:
		if is_instance_valid(e["node"]):
			e["node"].queue_free()
	bh_bunkers.clear()
	bh_my_bunker = -1
	if bh_fx and is_instance_valid(bh_fx):
		bh_fx.queue_free()
	bh_fx = null
	if players_container and is_instance_valid(players_container):
		for p in players_container.get_children():
			if p is NetworkPlayer:
				p.set_physics_process(true)

# Bots: during a black hole, the nearest bunker with room.
func moon_bot_goal(bot: NetworkPlayer):
	if not bh_active or bh_t <= 0.0:
		return null
	var best = null
	var best_d = INF
	for i in range(bh_bunkers.size()):
		var e = bh_bunkers[i]
		var slots: Array = e["slots"]
		if slots.size() >= BH_CAPACITY and not slots.has(bot.peer_id):
			continue
		var dd = bot.global_position.distance_to(e["pos"])
		if dd < best_d:
			best_d = dd
			best = (e["pos"] as Vector3) + (e["basis"] as Basis) * Vector3(0, 0.2, 0.3)
	return best

# --- THE STORM (every Royale map) ---
# A ring around the middle of the map: before 1:00 it covers the whole map,
# then it closes in, reaching the middle at 6:00. Outside it for 10s = out.
# Distances are measured across the map (x/z), so being underground or up a
# tower doesn't help. (The Moon measures them along its surface instead.)
func _storm_r0() -> float:
	if is_moon():
		return MOON_R * PI # the whole moon
	return float(selected_map_data.get("storm_r0", float(selected_map_data.get("size", 130.0)) * 0.75))

func storm_radius() -> float:
	var r0 = _storm_r0()
	var r1 = float(selected_map_data.get("storm_end", 8.0))
	if royale_time < STORM_START:
		return r0
	return lerp(r0, r1, clamp((royale_time - STORM_START) / (STORM_FULL - STORM_START), 0.0, 1.0))

func storm_dist(pos: Vector3) -> float:
	if is_moon():
		return MOON_R * acos(clamp(pos.normalized().dot(MOON_NORTH), -1.0, 1.0))
	return Vector2(pos.x, pos.z).length()

# margin > 0: also counts spots within that many meters of the edge.
func storm_outside(pos: Vector3, margin: float = 0.0) -> bool:
	if not is_royale or royale_time < STORM_START or storm_root == null:
		return false
	return storm_dist(pos) > storm_radius() - margin

# Bots: where to run when the storm is (nearly) on them; null when they're fine.
func storm_safe_goal(pos: Vector3):
	if not is_royale or storm_root == null or royale_time < STORM_START - 5.0:
		return null
	var r = storm_radius()
	var d = storm_dist(pos)
	if d < r - 7.0:
		return null
	if is_moon():
		# toward the north pole along the surface
		var dpos = pos.normalized()
		var axis = MOON_NORTH.cross(dpos)
		if axis.length() < 0.01:
			axis = Vector3.RIGHT
		return MOON_NORTH.rotated(axis.normalized(), (r * 0.45) / MOON_R) * MOON_R
	var flat = Vector2(pos.x, pos.z)
	var dir = flat.normalized() if flat.length() > 0.1 else Vector2(1, 0)
	var to = dir * max(r * 0.45, 2.0)
	return Vector3(to.x, pos.y, to.y)

func _build_storm() -> void :
	storm_root = Node3D.new()
	storm_root.name = "Storm"
	world_root.add_child(storm_root)
	var col: Color = selected_map_data.get("storm_color", Color(0.6, 0.4, 1.0))
	storm_wall = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 90.0
	cm.radial_segments = 72
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	storm_wall.mesh = cm
	storm_wall.position.y = 25.0
	var wm = StandardMaterial3D.new()
	wm.albedo_color = Color(col.r, col.g, col.b, 0.3)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	storm_wall.material_override = wm
	storm_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	storm_root.add_child(storm_wall)
	storm_wall.visible = not is_moon() # (the Moon has its dark matter shell)
	# Particles swirling around the edge and drifting in toward the middle.
	var q = SphereMesh.new() # (little round puffs)
	q.radius = 0.6
	q.height = 1.2
	q.radial_segments = 6
	q.rings = 3
	var pm = StandardMaterial3D.new()
	pm.albedo_color = Color(col.r, col.g, col.b, 0.8)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = pm
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = 600
	storm_mm = MultiMeshInstance3D.new()
	storm_mm.multimesh = mm
	storm_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	storm_mm.extra_cull_margin = 500.0
	storm_root.add_child(storm_mm)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	storm_parts.clear()
	for i in range(mm.instance_count):
		# [angle, distance outside the edge, height, speed]
		storm_parts.append([rng.randf() * TAU, rng.randf_range(0.0, 26.0), rng.randf_range(-8.0, 32.0), rng.randf_range(0.5, 1.3)])
	storm_outside_t = 0.0
	bot_storm_t.clear()
	_update_storm_visuals(0.0)

func _update_storm_visuals(delta: float) -> void :
	if storm_root == null or not is_instance_valid(storm_root) or storm_mm == null:
		return
	var r = storm_radius()
	storm_wall.scale = Vector3(r, 1.0, r)
	var mm = storm_mm.multimesh
	if is_moon():
		# dark matter swirling round the edge of the safe cap
		var th = clamp(r / MOON_R, 0.0, PI)
		if moon_storm_mat:
			moon_storm_mat.set_shader_parameter("cos_t", cos(th) if royale_time >= STORM_START else -1.5)
		var e1 = Vector3.RIGHT
		var e2 = Vector3.FORWARD
		for i in range(storm_parts.size()):
			var pt = storm_parts[i]
			pt[0] = fmod(pt[0] + delta * float(pt[3]) * 0.25, TAU)
			var ring_dir = MOON_NORTH * cos(th) + (e1 * cos(pt[0]) + e2 * sin(pt[0])) * sin(th)
			var rr = MOON_R + 0.6 + abs(float(pt[2])) * 0.5
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 1.4), ring_dir * rr + ring_dir.cross(MOON_NORTH).normalized() * (float(pt[1]) - 13.0) * 0.15))
		return
	for i in range(storm_parts.size()):
		var pt = storm_parts[i]
		pt[0] = fmod(pt[0] + delta * float(pt[3]) * 14.0 / max(r, 12.0), TAU)
		pt[1] = float(pt[1]) - delta * 3.0 * float(pt[3]) # drifting in toward the middle
		if pt[1] < 0.0:
			pt[1] += 26.0
		var rr = r + float(pt[1])
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(cos(pt[0]) * rr, pt[2], sin(pt[0]) * rr)))

# Everyone checks themselves; the host checks the bots.
func _storm_tick(delta: float) -> void :
	if storm_root == null:
		return
	_update_storm_visuals(delta)
	var name_up = String(selected_map_data.get("storm", "STORM"))
	var me = get_local_player()
	var inside_now = false
	if me and not me.is_dead:
		if storm_outside(me.global_position):
			inside_now = true
			storm_outside_t += delta
			if storm_outside_t >= STORM_GRACE:
				storm_outside_t = 0.0
				log_console("[Royale] The " + name_up.to_lower() + " got you!")
				kill_local_player_from_fall()
		else:
			storm_outside_t = 0.0
	if storm_tint:
		var sc: Color = selected_map_data.get("storm_color", Color(0.6, 0.4, 1.0))
		storm_tint.color = Color(sc.r, sc.g, sc.b, 0.22 + 0.2 * clamp(storm_outside_t / STORM_GRACE, 0.0, 1.0))
		storm_tint.visible = inside_now
	if storm_label:
		var text = ""
		var col = Color(1.0, 0.85, 0.4)
		if me and not me.is_dead:
			if royale_time < STORM_START:
				if royale_time > ROYALE_GLIDE_TIME:
					text = name_up + " in " + str(int(ceil(STORM_START - royale_time))) + "s"
			elif inside_now:
				var to_safe = max(storm_dist(me.global_position) - storm_radius(), 0.0)
				text = "IN THE " + name_up + "! Get to the middle: " + str(int(ceil(STORM_GRACE - storm_outside_t))) + "s  (" + str(int(ceil(to_safe))) + "m)"
				col = Color(1.0, 0.3, 0.25)
			elif royale_time < STORM_FULL:
				text = name_up + " closing in - " + str(int(round(storm_dist(me.global_position)))) + "m from the middle, safe zone " + str(int(round(storm_radius()))) + "m"
			else:
				text = name_up + " - hold the middle!"
		storm_label.text = text
		storm_label.add_theme_color_override("font_color", col)
		storm_label.visible = text != ""
	if is_host_peer:
		for pid in royale_bots:
			var b = get_player(pid)
			if b == null or b.is_dead:
				continue
			if storm_outside(b.global_position):
				bot_storm_t[pid] = float(bot_storm_t.get(pid, 0.0)) + delta
				if float(bot_storm_t[pid]) >= STORM_GRACE:
					bot_storm_t[pid] = 0.0
					kill_bot_from_fall(b)
			else:
				bot_storm_t[pid] = 0.0

func _royale_hud_text() -> String:
	var g = gear_of(local_peer_id)
	var parts: Array = []
	for slot in ["melee", "shield", "ranged", "mask", "special", "genie"]:
		var it = String(g.get(slot, ""))
		if GEAR.has(it):
			parts.append("[color=#" + (GEAR[it]["color"] as Color).lerp(Color.WHITE, 0.35).to_html(false) + "]" + String(GEAR[it]["name"]) + "[/color]")
	var me = get_local_player()
	var hp = str(me.health if me else 100) + (("/" + str(me.max_health)) if me and me.max_health != 100 else "") + " HP"
	var t = "[b]HUSS ROYALE[/b] - " + str(_alive_count()) + " of " + str(all_player_ids().size()) + " left\n"
	t += "You: " + hp + ("   " + ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "   [color=#999999]no gear yet - follow the light beams[/color]")
	if dead_peers.has(local_peer_id):
		var place = int(ffa_places.get(local_peer_id, 0))
		t = "[b]HUSS ROYALE[/b] - " + str(_alive_count()) + " of " + str(all_player_ids().size()) + " left\n[color=#ff5555]You're out" + (" (" + _ordinal(place) + ")" if place > 0 else "") + "[/color]"
	return t

# --- 1ST / 3RD PERSON VIEW (F5, or the VIEW button on mobile) ---

func toggle_view() -> void :
	third_person = not third_person
	save_player_data()
	var me = get_local_player()
	if me:
		me.apply_view_mode()
	log_console("[View] " + ("Third person" if third_person else "First person") + " (F5 to switch)")

func _set_in_match_flag(on: bool) -> void :
	if OS.has_feature("web"):
		var window = JavaScriptBridge.get_interface("window")
		if window:
			window._hussleInMatch = on
			window._hussleRoyale = on and is_royale

# F5 is the view key, so stop it from reloading the page during a match
# (the game usually gets the key first, but not if the page has focus).
const VIEW_KEY_JS: String = """
(function () {
	if (window._hussleF5Guard) { return; }
	window._hussleF5Guard = true;
	window.addEventListener('keydown', function (e) {
		if ((e.key === 'F5' || e.keyCode === 116) && window._hussleInMatch) { e.preventDefault(); }
		// Huss Royale: Ctrl is the slide key - keep Ctrl+S / Ctrl+D etc. from
		// opening browser dialogs mid-match.
		if (e.ctrlKey && window._hussleInMatch && window._hussleRoyale) { e.preventDefault(); }
	}, true);
	// Ctrl+W can't be blocked by a page, so ask before the tab closes mid-Royale.
	window.addEventListener('beforeunload', function (e) {
		if (window._hussleInMatch && window._hussleRoyale) { e.preventDefault(); e.returnValue = ''; return ''; }
	});
})();
"""

func _init_view_key_guard() -> void :
	if OS.has_feature("web"):
		JavaScriptBridge.eval(VIEW_KEY_JS, true)


# --- CONTROLS ---

func _looks_like_mobile() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")

func _set_controls(mobile: bool) -> void :
	mobile_controls = mobile
	save_player_data()

func _mobile_reset_inputs() -> void :
	mobile_move = Vector2.ZERO
	mobile_jump_held = false
	mobile_e_held = false
	mobile_q_held = false
	mobile_slide_held = false
	mobile_shoot_held = false
	mobile_use_held = false

func mobile_look_active() -> bool:
	return mobile_ui != null and mobile_ui.has_method("is_looking") and mobile_ui.is_looking()

func mobile_look(rel: Vector2) -> void :
	var me = get_local_player()
	if me:
		me.apply_look(rel, MOBILE_LOOK_SENSITIVITY)

# --- CHARACTER COLOR SCREEN ---

func _color_name(hex: String) -> String:
	for preset in COLOR_PRESETS:
		if String(preset[1]) == hex:
			return String(preset[0])
	return "Custom"

func _swatch_style(c: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	return sb

func _show_color_picker_ui() -> void :
	_save_nickname_from_input()
	_clear_ui()
	color_edit_part = ""
	color_canvas = CanvasLayer.new()
	add_child(color_canvas)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_canvas.add_child(center)

	var vp = get_viewport().get_visible_rect().size
	var wide = vp.x >= 960.0 # preview | presets | color field side by side
	var need_h = 470.0 if wide else 720.0
	var panel = PanelContainer.new()
	if vp.y < need_h:
		# Short screen: let the page scroll.
		var page = ScrollContainer.new()
		page.custom_minimum_size = Vector2(min(vp.x - 8.0, 940.0 if wide else 680.0), vp.y - 8.0)
		page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		center.add_child(page)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_child(panel)
	else:
		center.add_child(panel)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	var title = Label.new()
	title.text = "CUSTOMIZE CHARACTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	outer.add_child(title)

	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	outer.add_child(columns)

	# --- Left: your character. Click a body part to color just that part. ---
	var left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	var model_row = HBoxContainer.new()
	model_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(model_row)
	for opt in [["mannequin", "Mannequin"], ["dummy", "Crash Dummy"]]:
		var mb = Button.new()
		mb.name = "Model_" + String(opt[0])
		mb.toggle_mode = true
		mb.custom_minimum_size = Vector2(125, 32)
		var key = String(opt[0])
		if key == "dummy" and not unlocked_dummy:
			mb.text = "Crash Dummy (locked)"
			mb.disabled = true
			mb.tooltip_text = "Reach " + get_rank_name(DUMMY_UNLOCK_ELO) + " (" + str(DUMMY_UNLOCK_ELO) + " ELO) to unlock"
		else:
			mb.text = String(opt[1])
			mb.button_pressed = _my_model() == key
			mb.pressed.connect( func(): _choose_model(key))
		model_row.add_child(mb)
	if not unlocked_dummy:
		var lock_lbl = Label.new()
		lock_lbl.text = "Crash Dummy unlocks at " + get_rank_name(DUMMY_UNLOCK_ELO) + " (" + str(DUMMY_UNLOCK_ELO) + " ELO) - you have " + str(local_elo) + "."
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lock_lbl.custom_minimum_size = Vector2(260, 0)
		lock_lbl.add_theme_font_size_override("font_size", 11)
		lock_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
		left.add_child(lock_lbl)
	_build_color_preview(left)

	color_part_label = Label.new()
	color_part_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_part_label.add_theme_font_size_override("font_size", 15)
	color_part_label.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	left.add_child(color_part_label)

	color_current_label = Label.new()
	color_current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_current_label.add_theme_font_size_override("font_size", 13)
	left.add_child(color_current_label)

	var part_row = HBoxContainer.new()
	part_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(part_row)
	var whole_btn = Button.new()
	whole_btn.text = "Whole Body"
	whole_btn.custom_minimum_size = Vector2(110, 32)
	whole_btn.pressed.connect( func(): _select_color_part(""))
	part_row.add_child(whole_btn)
	var reset_btn = Button.new()
	reset_btn.text = "Reset Parts"
	reset_btn.tooltip_text = "Make every part your main color again"
	reset_btn.custom_minimum_size = Vector2(110, 32)
	reset_btn.pressed.connect(_reset_part_colors)
	part_row.add_child(reset_btn)

	var hint = Label.new()
	hint.text = "Click a body part to color just that part.\nDrag to turn the model."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	left.add_child(hint)

	# --- Middle: presets + hex code ---
	var mid = VBoxContainer.new()
	mid.add_theme_constant_override("separation", 8)
	columns.add_child(mid)
	var pre_lbl = Label.new()
	pre_lbl.text = "Pick a color:"
	pre_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(pre_lbl)
	var grid_center = CenterContainer.new()
	mid.add_child(grid_center)
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid_center.add_child(grid)
	for preset in COLOR_PRESETS:
		var hex = String(preset[1])
		var c = Color.html(hex)
		var b = Button.new()
		b.text = String(preset[0])
		b.custom_minimum_size = Vector2(110, 38)
		b.add_theme_stylebox_override("normal", _swatch_style(c))
		b.add_theme_stylebox_override("hover", _swatch_style(c.lightened(0.15), Color.WHITE, 2))
		b.add_theme_stylebox_override("pressed", _swatch_style(c.darkened(0.15), Color.WHITE, 2))
		b.add_theme_stylebox_override("focus", _swatch_style(c, Color(1.0, 0.9, 0.2), 3))
		var text_col = Color.BLACK if c.get_luminance() > 0.55 else Color.WHITE
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(state, text_col)
		b.pressed.connect( func(): _set_character_color(hex))
		grid.add_child(b)

	var hex_lbl = Label.new()
	hex_lbl.text = "Or enter a hex code:"
	hex_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(hex_lbl)
	var hex_row = HBoxContainer.new()
	hex_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(hex_row)
	color_hex_input = LineEdit.new()
	color_hex_input.placeholder_text = "#FF8800"
	color_hex_input.custom_minimum_size = Vector2(150, 36)
	color_hex_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_hex_input.text_submitted.connect( func(t): _apply_hex_color(t))
	_osk_prep(color_hex_input)
	hex_row.add_child(color_hex_input)
	var apply_btn = Button.new()
	apply_btn.text = "Use This Color"
	apply_btn.custom_minimum_size = Vector2(130, 36)
	apply_btn.pressed.connect( func(): _apply_hex_color(color_hex_input.text))
	hex_row.add_child(apply_btn)

	# --- Right (or under the presets on narrow screens): any exact color ---
	var right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	if wide:
		columns.add_child(right)
	else:
		mid.add_child(right)
	var field_lbl = Label.new()
	field_lbl.text = "Or pick any color:"
	field_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(field_lbl)
	var field_center = CenterContainer.new()
	right.add_child(field_center)
	color_field = ColorField.new()
	color_field.set_color(_edit_part_color())
	color_field.picked.connect(_on_color_field_picked)
	field_center.add_child(color_field)

	color_status_label = Label.new()
	color_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_status_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(color_status_label)

	var back_row = CenterContainer.new()
	outer.add_child(back_row)
	var back_btn = Button.new()
	back_btn.text = "Back to Menu"
	back_btn.custom_minimum_size = Vector2(240, 38)
	back_btn.pressed.connect(_build_main_menu)
	back_row.add_child(back_btn)

	_select_color_part("")

# The 3D preview: your character model in its own little world.
func _build_color_preview(parent: Control) -> void :
	var box = SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(270, 280)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(box)
	color_preview = box
	color_preview_vp = SubViewport.new()
	color_preview_vp.size = Vector2i(270, 280)
	color_preview_vp.own_world_3d = true
	color_preview_vp.transparent_bg = true
	color_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	box.add_child(color_preview_vp)

	var world = Node3D.new()
	color_preview_vp.add_child(world)
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	light.light_energy = 1.1
	world.add_child(light)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 200, 0)
	fill.light_energy = 0.35
	world.add_child(fill)
	color_preview_cam = Camera3D.new()
	color_preview_cam.position = Vector3(0, 0.92, 3.6)
	color_preview_cam.fov = 38.0
	world.add_child(color_preview_cam)
	color_preview_cam.current = true

	color_preview_outline = StandardMaterial3D.new()
	color_preview_outline.cull_mode = BaseMaterial3D.CULL_FRONT
	color_preview_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	color_preview_outline.albedo_color = Color(1.0, 0.9, 0.1)
	color_preview_outline.grow = true
	color_preview_outline.grow_amount = 0.025

	color_preview_mats = {}
	for grp in MannequinBody.GROUPS:
		var m = StandardMaterial3D.new()
		m.roughness = 0.55
		color_preview_mats[grp] = m
	_rebuild_preview_body(world)
	box.gui_input.connect(_on_color_preview_input)

# (Re)builds the model in the preview - after picking Mannequin / Crash Dummy.
func _rebuild_preview_body(world: Node3D = null) -> void :
	var parent = world
	var yaw = PI # facing you
	if color_preview_body:
		parent = color_preview_body.get_parent()
		yaw = color_preview_body.rotation.y
		color_preview_body.queue_free()
		color_preview_body = null
	if not parent:
		return
	var body = MannequinBody.new()
	body.build(color_preview_mats, true, _my_model())
	body.rotation.y = yaw
	parent.add_child(body)
	color_preview_body = body

func _choose_model(m: String) -> void :
	if m == "dummy" and not unlocked_dummy:
		return
	local_model = _clean_model(m)
	save_player_data()
	_rebuild_preview_body()
	if color_canvas:
		for key in ["mannequin", "dummy"]:
			var b = color_canvas.find_child("Model_" + key, true, false)
			if b:
				b.button_pressed = _my_model() == key
	_select_color_part(color_edit_part)
	if color_status_label:
		color_status_label.text = ("You're the Crash Test Dummy now!" if local_model == "dummy" else "Back to the Mannequin.") + " Other players will see it in your next match."
		color_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))

# Click = pick the part under the cursor; drag sideways = turn the model.
func _on_color_preview_input(event: InputEvent) -> void :
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			color_preview_press = event.position
			color_preview_dragged = false
		else:
			if color_preview_press.x >= 0.0 and not color_preview_dragged:
				_select_color_part(_color_preview_pick(event.position))
			color_preview_press = Vector2(-1, -1)
	elif event is InputEventMouseMotion and color_preview_press.x >= 0.0:
		if event.position.distance_to(color_preview_press) > 6.0:
			color_preview_dragged = true
		if color_preview_dragged and color_preview_body:
			color_preview_body.rotation.y += event.relative.x * 0.012

# Which body part is under this point of the preview ("" = none).
func _color_preview_pick(pos: Vector2) -> String:
	if not color_preview_cam or not color_preview_cam.is_inside_tree():
		return ""
	var world = color_preview_cam.get_world_3d() # the preview's own little world
	if not world:
		return ""
	var from = color_preview_cam.project_ray_origin(pos)
	var to = from + color_preview_cam.project_ray_normal(pos) * 20.0
	var q = PhysicsRayQueryParameters3D.create(from, to)
	var hit = world.direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit.get("collider"):
		return ""
	return String(hit["collider"].get_meta("part", ""))

func _part_color_hex(part: String) -> String:
	if part != "" and local_part_colors.has(part):
		return String(local_part_colors[part])
	return local_color_hex

func _edit_part_color() -> Color:
	var hex = _part_color_hex(color_edit_part)
	return Color.html(hex) if Color.html_is_valid(hex) else Color(0.5, 0.5, 0.5)

func _select_color_part(part: String) -> void :
	color_edit_part = part if BODY_PART_NAMES.has(part) else ""
	if color_preview_body:
		for grp in color_preview_body.group_mats:
			var m: StandardMaterial3D = color_preview_body.group_mats[grp]
			m.next_pass = color_preview_outline if grp == color_edit_part else null
		for grp in color_preview_body.dark_of:
			color_preview_body.dark_of[grp].next_pass = color_preview_outline if grp == color_edit_part else null
	if color_field:
		color_field.set_color(_edit_part_color())
	_refresh_color_preview()

func _reset_part_colors() -> void :
	local_part_colors.clear()
	save_player_data()
	_select_color_part("")
	if color_status_label:
		color_status_label.text = "Every part is your main color again."
		color_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))

# Dragging updates the preview live; letting go saves the color.
func _on_color_field_picked(c: Color, done: bool) -> void :
	var hex = c.to_html(false).to_lower()
	if done:
		_set_character_color(hex, false)
	else:
		_refresh_color_preview(c)

func _local_color() -> Color:
	return Color.html(local_color_hex) if Color.html_is_valid(local_color_hex) else Color(0.5, 0.5, 0.5)

# live: a color being dragged on the color field, shown before it's saved.
func _refresh_color_preview(live = null) -> void :
	if color_preview_body:
		for grp in color_preview_body.group_mats:
			var col: Color = Color.html(_part_color_hex(grp)) if Color.html_is_valid(_part_color_hex(grp)) else Color(0.5, 0.5, 0.5)
			if live is Color and (color_edit_part == "" or color_edit_part == grp):
				col = live
			color_preview_body.group_mats[grp].albedo_color = col
		color_preview_body.refresh_dark()
	if color_part_label:
		var n = local_part_colors.size()
		color_part_label.text = "Editing: " + String(BODY_PART_NAMES[color_edit_part]) + ("" if color_edit_part != "" or n == 0 else "  (" + str(n) + " part" + ("s" if n > 1 else "") + " colored)")
	if color_current_label:
		var hx = _part_color_hex(color_edit_part)
		if live is Color:
			hx = (live as Color).to_html(false)
		color_current_label.text = ("Your color: " if color_edit_part == "" else String(BODY_PART_NAMES[color_edit_part]) + ": ") + _color_name(hx.to_lower()) + "  (#" + hx.to_upper() + ")"

# Applies to the part being edited, or (Whole Body) to everything.
func _set_character_color(hex: String, move_field: bool = true) -> void :
	var h = hex.trim_prefix("#").to_lower()
	if color_edit_part == "":
		local_color_hex = h
		local_part_colors.clear() # whole body = every part this color
	elif h == local_color_hex:
		local_part_colors.erase(color_edit_part)
	else:
		local_part_colors[color_edit_part] = h
	save_player_data()
	_refresh_color_preview()
	if move_field and color_field:
		color_field.set_color(_edit_part_color())
	if color_status_label:
		color_status_label.text = "Saved! Other players will see you in " + ("this color." if color_edit_part == "" else "these colors.")
		color_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))

# Accepts "#RRGGBB", "RRGGBB", "#RGB" or "RGB".
func _apply_hex_color(text: String) -> bool:
	var t = text.strip_edges().trim_prefix("#")
	var valid = (t.length() == 6 or t.length() == 3) and Color.html_is_valid(t)
	if not valid:
		if color_status_label:
			color_status_label.text = "That's not a valid hex color - try something like #FF8800."
			color_status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		return false
	if t.length() == 3:
		t = t[0] + t[0] + t[1] + t[1] + t[2] + t[2]
	_set_character_color(t)
	return true

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

	# Fits small (phone) screens too.
	var vp_size = get_viewport().get_visible_rect().size
	var lb_w = clamp(vp_size.x - 24.0, 360.0, 760.0)
	var lb_h = clamp(vp_size.y - 130.0, 180.0, 330.0)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(lb_w, 0)
	center_panel.add_child(panel)

	var container = VBoxContainer.new()
	panel.add_child(container)

	var title = Label.new()
	title.text = "--- ELO LEADERBOARD ---"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	lb_status_label = Label.new()
	lb_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_status_label.add_theme_font_size_override("font_size", 12)
	lb_status_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	container.add_child(lb_status_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(lb_w - 20.0, lb_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(scroll)

	leaderboard_list = VBoxContainer.new()
	leaderboard_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var list = leaderboard_list
	_lb_set(local_nickname, local_elo, float(leaderboard_data.get(local_nickname, {}).get("t", _wall_time())))
	var online = _lb_online_nicks()
	online[local_nickname] = true
	var names: Array = leaderboard_data.keys()
	names.sort_custom(func(a, b):
		var ea = int(leaderboard_data[a].get("elo", 0)) if leaderboard_data[a] is Dictionary else 0
		var eb = int(leaderboard_data[b].get("elo", 0)) if leaderboard_data[b] is Dictionary else 0
		return ea > eb if ea != eb else String(a) < String(b))
	# Skip the rebuild when nothing shown would change (keeps clicks reliable).
	var sig_rows: Array = []
	for n in names:
		var e = leaderboard_data[n]
		var sn = String(n)
		var seen_txt = ""
		if e is Dictionary and float(e.get("seen", 0.0)) > 0.0:
			seen_txt = _ago(_wall_time() - float(e.get("seen", 0.0)))
		sig_rows.append([sn, int(e.get("elo", 0)) if e is Dictionary else 0, online.has(sn), _lb_tid_for_nick(sn), seen_txt])
	var sig = str([sig_rows, local_nickname, challenge_out.get("to", ""), challenge_out.is_empty(), party_invites_out.keys(), _party_ids(), party_leader, mm_self_id])
	if lb_status_label:
		lb_status_label.text = social_status
	if sig == lb_list_sig and leaderboard_list.get_child_count() > 0:
		return
	lb_list_sig = sig
	for c in leaderboard_list.get_children():
		c.queue_free()

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
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = label.text
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)

		var nick = String(player_key)
		var st_lbl = Label.new()
		st_lbl.add_theme_font_size_override("font_size", 11)
		st_lbl.custom_minimum_size = Vector2(175, 0)
		if nick == local_nickname:
			st_lbl.text = "you"
			st_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
		elif online.has(nick):
			st_lbl.text = "online"
			st_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
		else:
			# Offline: their ELO is from the last time they were online.
			var seen = float(entry.get("seen", 0.0)) if entry is Dictionary else 0.0
			st_lbl.text = "offline" + ("  -  last online " + _ago(_wall_time() - seen) if seen > 0.0 else "")
			st_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(st_lbl)

		# Buttons only for other players who are online (on the main menu) now.
		var btn_box = HBoxContainer.new()
		btn_box.custom_minimum_size = Vector2(276, 0)
		row.add_child(btn_box)
		var tid = _lb_tid_for_nick(nick) if nick != local_nickname else ""
		if tid != "":
			var ch = Button.new()
			ch.custom_minimum_size = Vector2(140, 30)
			if not challenge_out.is_empty() and String(challenge_out["to"]) == tid:
				ch.text = "Challenged..."
				ch.disabled = true
			else:
				ch.text = "Challenge to 1v1"
				ch.disabled = not challenge_out.is_empty()
				ch.pressed.connect( func(): _challenge_player(tid, nick))
			btn_box.add_child(ch)
			var iv = Button.new()
			iv.custom_minimum_size = Vector2(130, 30)
			if _party_ids().has(tid):
				iv.text = "In your party"
				iv.disabled = true
			elif party_invites_out.has(tid):
				iv.text = "Invited..."
				iv.disabled = true
			else:
				iv.text = "Invite to party"
				iv.disabled = (_in_party() and not _is_party_leader()) or party_members.size() >= PARTY_MAX
				iv.pressed.connect( func(): _invite_to_party(tid, nick))
			btn_box.add_child(iv)
	if lb_status_label:
		lb_status_label.text = social_status


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
	if mm_custom_match and not CHALLENGE_IS_RANKED:
		_schedule_room_leave()
		_show_match_results_screen("You won the challenge!" if is_winner else "You lost the challenge", is_winner, 0, local_elo, local_elo, false, "Friendly challenge - no ELO change.")
		return
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
	if mm_custom_match:
		banner_text = "You won the challenge!" if is_winner else "You lost the challenge"
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

	if dummy_just_unlocked:
		var un = Label.new()
		un.text = "UNLOCKED: the Crash Test Dummy! (Customize Character)"
		un.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		un.add_theme_font_size_override("font_size", 15)
		un.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		container.add_child(un)

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
	if not is_instance_valid(anim_elo_label):
		# The results screen is gone (left with Esc while it was counting).
		is_animating_elo = false
		return
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
	_free_royale_vote_ui()
	_free_direct_panel()
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
	if ranks_canvas:
		ranks_canvas.queue_free()
		ranks_canvas = null
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
		royale_drop_label = null
		storm_label = null
		storm_tint = null
		hazard_label = null
		bh_label = null
		mobile_ui = null
		console_panel = null
		_mobile_reset_inputs()
	menu_online_label = null
	leaderboard_list = null
	party_panel_box = null
	rank_panel_box = null
	party_code_input = null
	lb_status_label = null
	if color_canvas:
		color_canvas.queue_free()
		color_canvas = null
		color_preview = null
		color_hex_input = null
		color_preview_vp = null
		color_preview_body = null
		color_preview_cam = null
		color_part_label = null
		color_status_label = null
		color_current_label = null
		color_field = null
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

	var arena = float(selected_map_data.get("size", 50.0))
	var wall_h = float(selected_map_data.get("wall_height", 4.0))
	var floor_body = StaticBody3D.new()
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(arena, arena)
	floor_mesh.mesh = plane

	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = floor_color
	floor_mesh.material_override = floor_mat

	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(arena, 0.1, arena)
	floor_shape.shape = box

	floor_body.add_child(floor_mesh)
	floor_body.add_child(floor_shape)
	if bool(selected_map_data.get("custom_ground", false)):
		floor_body.queue_free() # (the map builds its own ground)
	else:
		world_root.add_child(floor_body)

	# Nav grid is rebuilt for each map, once the physics bodies exist.
	nav_grid = null
	nav_floor_rid = floor_body.get_rid()

	var half = arena / 2.0
	if not bool(selected_map_data.get("no_walls", false)):
		_create_wall_block(Vector3(0, wall_h / 2.0, -half), Vector3(arena, wall_h, 1), wall_color)
		_create_wall_block(Vector3(0, wall_h / 2.0, half), Vector3(arena, wall_h, 1), wall_color)
		_create_wall_block(Vector3(-half, wall_h / 2.0, 0), Vector3(1, wall_h, arena), wall_color)
		_create_wall_block(Vector3(half, wall_h / 2.0, 0), Vector3(1, wall_h, arena), wall_color)

	_build_map_mechanics(mechanic, wall_color)

	players_container = Node3D.new()
	players_container.name = "Players"
	world_root.add_child(players_container)

func _build_map_mechanics(mechanic: String, wall_color: Color) -> void :
	match mechanic:
		"royale":
			_build_royale_map(wall_color)
		"desert":
			_build_desert_map(wall_color)
		"wasteland":
			_build_wasteland_map(wall_color)
		"moon":
			_build_moon_map(wall_color)
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
	if is_royale:
		royale_ladders.append([face_pos, outward_normal.normalized(), height])

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
	if is_royale:
		player.gliding = true # sky drop
		if is_bot(peer_id):
			player.is_bot = true
			player.bot_level = int(royale_bots[peer_id]["level"])
			player.bot_miss = float(royale_bots[peer_id]["miss"])
			var spots = _royale_item_spots()
			player.glide_target = spots[randi() % spots.size()] + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))

	if is_moon():
		var sup = player.position.normalized()
		player.transform = Transform3D(basis_up(sup, -sup.cross(Vector3.UP if abs(sup.y) < 0.9 else Vector3.RIGHT)), player.position)
		player.moon_up = sup
		if player.is_bot:
			var mspots = _royale_item_spots().filter(func(sp): return sp.length() < MOON_R + 5.0)
			if not mspots.is_empty():
				player.glide_target = mspots[randi() % mspots.size()]
	players_container.add_child(player)
	if is_royale and not gear_of(peer_id).is_empty():
		if has_genie(peer_id):
			player.apply_genie()
		player.refresh_gear()

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


class ColorField extends Control:
	# Pick any exact color: drag on the square for saturation (left-right) and
	# brightness (top-bottom), drag on the bar for the hue.
	signal picked(color: Color, done: bool)
	const BAR_W: float = 18.0
	const GAP: float = 8.0
	var hue: float = 0.0
	var sat: float = 1.0
	var val: float = 1.0
	var dragging: String = ""
	var sv_tex: ImageTexture = null
	var hue_tex: ImageTexture = null
	var tex_hue: float = -1.0

	func _init() -> void:
		custom_minimum_size = Vector2(250, 250)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var img = Image.create(1, 180, false, Image.FORMAT_RGB8)
		for y in range(180):
			img.set_pixel(0, y, Color.from_hsv(1.0 - float(y) / 179.0, 1.0, 1.0))
		hue_tex = ImageTexture.create_from_image(img)

	func set_color(c: Color) -> void:
		if c.s > 0.01 and c.v > 0.01:
			hue = c.h
		sat = c.s
		val = c.v
		queue_redraw()

	func get_color() -> Color:
		return Color.from_hsv(hue, sat, val)

	func _sv_rect() -> Rect2:
		return Rect2(Vector2.ZERO, Vector2(size.x - BAR_W - GAP, size.y))

	func _hue_rect() -> Rect2:
		return Rect2(Vector2(size.x - BAR_W, 0), Vector2(BAR_W, size.y))

	func _rebuild_sv() -> void:
		if sv_tex and is_equal_approx(tex_hue, hue):
			return
		tex_hue = hue
		var n = 64
		var img = Image.create(n, n, false, Image.FORMAT_RGB8)
		for y in range(n):
			for x in range(n):
				img.set_pixel(x, y, Color.from_hsv(hue, float(x) / float(n - 1), 1.0 - float(y) / float(n - 1)))
		sv_tex = ImageTexture.create_from_image(img)

	func _draw() -> void:
		_rebuild_sv()
		var r = _sv_rect()
		var hr = _hue_rect()
		draw_texture_rect(sv_tex, r, false)
		draw_texture_rect(hue_tex, hr, false)
		var p = r.position + Vector2(sat * r.size.x, (1.0 - val) * r.size.y)
		draw_circle(p, 8.0, Color(1, 1, 1, 0.25))
		draw_arc(p, 8.0, 0.0, TAU, 24, Color.WHITE, 2.0, true)
		draw_arc(p, 9.5, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 1.0, true)
		var hy = hr.position.y + (1.0 - hue) * hr.size.y
		draw_rect(Rect2(hr.position.x - 3, hy - 3, hr.size.x + 6, 6), Color.WHITE, false, 2.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = "hue" if event.position.x >= _hue_rect().position.x - GAP * 0.5 else "sv"
				_apply(event.position, false)
			elif dragging != "":
				_apply(event.position, true)
				dragging = ""
			accept_event()
		elif event is InputEventMouseMotion and dragging != "":
			_apply(event.position, false)
			accept_event()

	func _apply(pos: Vector2, done: bool) -> void:
		if dragging == "sv":
			var r = _sv_rect()
			sat = clamp((pos.x - r.position.x) / r.size.x, 0.0, 1.0)
			val = clamp(1.0 - (pos.y - r.position.y) / r.size.y, 0.0, 1.0)
		else:
			var hr = _hue_rect()
			hue = clamp(1.0 - (pos.y - hr.position.y) / hr.size.y, 0.0, 0.9999)
		queue_redraw()
		picked.emit(get_color(), done)


# Crash test dummy model: crash_dummy_all_6_pieces.stl, simplified to ~7,400
# triangles, cut at the elbows/knees, positions quantized to 16 bits, zlib
# compressed, base64. Decoded once by MannequinBody.dummy_meshes().
const DUMMY_MESH_DATA: String = """
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
ulQb7qg9Oe/RWc96UbNWJLWob9p1FmN3IrXhjlYZu7RCG+6obT+TsQpjtOGOVhkLj9GGO2qLzUDbRmnRtn9F21Zr0bZ/PD2NMf8wbbijVcZardOGO2qbRTPm
HqoNd7TKWM8N2nBH7cYpjPUepg13tMqYa5w23FH7fhJjF4dowx2tMnYvXhvuqB3fff7cPq9tzTeRsRGDteGOVhmrvFkb7qh1jmIsOEQb7miVsXpbtOGO2vrj
GNs4SBvuaJUx2qoNd9Q2iGTMeZA23NEqY0O3asMdtXXGMJZlkDbc0Sru0q1a3KX/6Div+Tj+9r/WCFdn1KozatUZteqMpjVHqh5pVY+0qkda1SPThiPUiGnV
iGnViGnViJn6DVdXRKuuiFZdEa26IqZZd92fMenWf508VN0bWnVvaNW9oVX3humFwere06p7T6vuPa2690wrhKh7W6vuba26t7Xq3jbdMlD97GjVz45W/exo
1c+OadsB6mdTq342tepnU6t+Nk3zNl02M3uj/8txTQaFnb3xXwv3VzOGVs0YWjVjaNWMYZp/ZZawVRX/q1e/0V6zs5k26zfMa3S2pv0GeU37x9z91DymVfOY
Vs1jWjWPmWbtV81rcDbT1OAiXsH/+Ce4kFfff/wcrOZJW50D054tftnWtcF5vAKyLg2+6tkim+nM4CTPJv/oEqzmZ62an7Vqftaq+dl0Ec6bJqtpyeApnuWy
maYPDvMs+Y9L+zbxzPaP0X3V54VWfV5o1eeFVn1emHb37dzCN/1/zdJXfU5p1eeUVn1OadXnlOmxPupzUKs+B7Xqc1CrPgdNN/RRn6da9XlquqBPT8+imU1/
9NiY9M7VdErQnEKMmY7sHu/ZMNPEnseTKjX4r6n+cUnVEmy9538xycvHarWE9P5Dzl31NPXyn3PWy2dvd4fUMfVsdfEre67G5FmdryW9a27rHf+8ZzsdN93u
VxbfBrd1PZ86+qyty/3Uc5NWPT0t91PPTVr13KRVz01a9dykVc9NWvXcpFXPTVr13KRVz01a9dykVc9NWvXcpFXPTVr13KRVz01a9dykVc9NWvXcpFXPTVr1
3KRVz01a9dykVc9NWvXcpFXPTVr13KRVz01a9dykVc9NWvXcpFXPTVr13KRVz01a9dykVc9NWvXcpFXPTVr13KRVz01a9dykVc9NWvXcpFXPTVr13KRVz01a
9dykVc9NWvXcpFXPTVr13KRVz01a9dykVc9NWvXcpFXPTVr13KRVz01a9dykVc9NWvXcpFXPTVr13KRVz01a9dykVc9N6mehWkJzv/aOtzKb/inTb/TNXv+X
GZvVj85+x9aP5dSbQ616c6hVbw616s2hVr051Ko3h1r15lCr3hxq1ZtDrXpzqFVvDrXqzaFWvTnUqjeHWvXmUKveHGrVm0OtenOoVW8OterNoVa9OdSqN4da
9eZQq94catWbQ616c6hVbw616s2hVr051Ko3h1r15lCr3hxq1ZtDrXpzqFVvDrXqzaFWvTnUqjeHWvXmUKveHGrVm0OtenOoVW8OterNoVa9OdSqN4da9eZQ
q94catWbQ616c6hVbw616s2hVr051Ko3h1r15lCr3hxq1ZtDrXpzqFVvDrXqzaFWvTnUqjeHWvXmUKveHJo+LT3oeJGS3mXUW33vMn1ODCnlXUa92/cuo97t
e5dR7/a9y6j3+Vr1Vt+7zKszM6t7l1Hv9r3LqHf73mXUu33vMupJWRl6W5V3eaDquD5W9TM/U0do+lqr3uqr4ye/V+e6/1Gd3emLakn/r01KP07M+61X6RU4
2t5SYUm/ktsVmzvlVoStY0teSNrmahpZ9MRp38q2pq3gMW7CXltjS1ydu3SCrZULHz1d8YWt4/xCfL/kMj1bTP0rj7LFibPF1L/ynC22m324qv1COe47Od7h
k5NNzxZT/7Kj7ZS29get+pcdrfqXnbPFvDMd/2b6ukR40dTU4DzOIVse/9cq+UewTedNJxZW/541sbDDjhUOpumyTDcGlrJ1W/ECJwt+vphp6RK7YrbmL5hn
2+ecNbOOT//una1ds79Z+vSPrTfSJab99eD/cpFdyM7gora+4/c3D3llOoYH7r8+F89OW04PLybVv5JvyL0uZEk5W4tJNdNq1UyrVTOtVs20WjXTatVMq1Uz
rVbNtFo102rVTKtVM61WzbRaNdNq1UyrVTOtVs20WjXTatVMq1UzrVbNtFo102rVTKtVM61WzbRaNdNq1UyrVTOtVs20WjXTatVMq1UzrVbNtFo102rVTKtV
M61WzbRaNdNq1UyrVTOtVs20WjXTatVMq1UzrVbNtFo102rVTKtVM61WzbRaNdNq1UyrVTOtVs20WjXTatVMq1UzrVbNtFo102rVTKtVM61WzbRaNdNq1Uyr
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
9WjdE2sa1O2X+nZ/jQhbl6Xm3fs81Nbg1OY7+kbaGphacM/1ibaGfVuxpHWErampmY9t/8epP+snLBxj66KfEbvLTLI1zbexMUs7mT761WdHZMR/vfSz4Z43
obaO+Fpjj7Hb1ldft1wJjLB17ddplybNN/329eCyiX1N533pe+bPBtP1KV8PHd9la1xK+vg5LU29fgw96R1hOv5j+eWjFto66kuJPWub2lrp0/4lfhG2jv44
5NLU3raW/8jOZPExnfm+5uGiLUzTfay6Z1szW+d/qLDHfc9/vfu+fJzvDluLvc20pHnEf/312mHVz1WmZ97+vTJljK0l31yIae5rOv/Vqi3Tdv/Xda+uH323
w/TX67bnD3U2zfOm94WhK0w3vlp/dJOHae9Xb7cNaWZ6+OGt20/br7rf4caB3bEP887z2bjmdtnE1pf33c8UN+Jshmeptz/MrXf90IipnuOvvhlxtf7Ne0FP
loR2Of007smTstdflXsfaprhftTRO1UCrz6rsmmQ6Z3Ld6s0mpPlfJHXTVY3PJ/i5BthGpH02altsOmqc4+cfWeZTjr9yenXYtPkI65D40tkPJV+UL/u7c4s
vr+u+prTRW5kul7jbLy3T+TFw2/KTW1luuJA7nFP9+9I8pyT8dyus/Pr1ppsGnv2cqsmE0xrnA1084nMdy5XQMbxtpY6+6BciVjTzoe+VZm2w7TT/j99AxrM
3l8mYHE70xdnCvVIGWDa68AO7zEbTCOP3gqsFmt6ItHPp/cM0/6JEf5tQ7Q1PLS/jscGhYwxLX8kLCV04ohjvj5FQkw3HX/tkmeQ6aWTS0ZPKvTh6Oy66wK0
d1pp2x0JcUsbazroUGzQ2kWmo0/+fPO2/e6ti+rG7zBdlFBwyI5xpvdOOri7jjKtfeqB8/rupmx7srPDLlNja9YDbb4GHPjg4jrif83uHjJRG+mvSqzaHR3s
FtHZtP7Rzd5X//HXnsetMmzSlg34X4ufcj82P9/DA8nOpcbaenV/TNCbYaa/Vlf1eNTc9GHcGP+oNqYHDlX3OLNEO8Zfu2Cnr0/I/3hvwxsn0cg0fs/D4AvB
pnv2xwZ97WJac1NO9wxbTedhrwtrq26NCQqIM22yIdn58Tpbcx+o6VFssunfPWjnXNP2cVuCPDxtPRPn8P2rX+LaDy5N29uauqOmx4Qephf3+/p0DrE1cW2k
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
uJSsqPH7ve3SET+VHr8/pyzeosuCgjGPPKJUvvm1JFXTUaXmd8uM/f11afdN/3rPnro8/avRm48LdOn5zTxj5MF/GXNn+Gld5scvuTqugsrX8SetlLoq38S/
KJnY+EP8rx9Vxqp8EW9yrW93Xb6OL30yrZfKF/HdXrbs/S/zL3RfqTIznqjm5koJnZ16/MMX8UbXXY78S/GmZrDKBnGZUdsWq3wRf+9xhdO6NE54bGx6T2Wx
hD3n9rxS+TI2elGC387DBXMtj/lHz6rdzE7lumil3LSaC2NnOHbtrsvI6NA6GedV+kTX1tt35VOUucWWRypXHIuM1nRQWStq3eNdeioHxinvX1RXuTxqz9nL
ZiqrRf3+mdBV5c9jOwtoo8p1MSF53a+p9I97+uZ3jspLUdMSGj9XaRdV935Bgcoze947Fu2kssyxx41WLtNlvWOZC6014WG1F/czbb+1SvXatXXZ5ciOqDnH
VD7Y/M1kYbWpm97HbbFVOW1Nnu3ihrpsFTzOdlJtlQk7hGPkUZXPFlesP8dWlx4rVhm6Vni/NqjKBRO/seHncyuo3O03x7Bd6vsJbiWTKljNazK3X4bK62PD
HWyrqtwzuMdMb7FslFel+/p7Bt9wuFlFl31mZ9ZcdvsPu9Rfcuh1mf7nHKyrqtzU77xD5X/o2PaHwT6DTf79FhKNaX6zBt3N6mM985PQH7fC3qjirpmbE1e+
Unm7XYzl+9JZrSbYnjE57R1bP6+2Lvs0eJoQWkNlTc8fpR7eftBg0LwLDy41KGrXt6Eu9bzS4gekq7xQbYJDZmuVC1sYLJ5fZL+jpqqb6US7jrUn2ehyn+1q
k8NVVOq7KHZul1VaV/BdsOrAXaPTL/XLqnxm3Pna6pIqlxvv+bbSQ2UT46uxznVVXjUqKBgUptLeeMHH1S9Utis9KDbntsp6xrOfbPqlcqtx15TV+SqPVUpe
tMi6hcmd6J7tVS4ztYouf1KXm8t72Zysq/J6+SyDSjXyjG81qj1ZZZUKvo2s1ulyTfmJdbecVfnV6KrFhscq00v+iCq5wKjU84WWY8eXOHJjUCWVpUr8Sn9g
pXKQ/nfjBNsWeg9yS3kP1c+u87t5Id/EBHupHKv/o4Rvr7H6LeNjOqgcpd/95+b5Y/Ub1um7/r/sp9/IaeC6m0VnnOq0WJdj9StXGX5al4f0OpV/8Iej9ceV
1btSq4TxJ9+Luhyuf7va16sqG+o1PfM6eaz+wjutMlX21G9/70Oeyhp6QVWPN2+td9L29SCVJ/Wivhz0+cOi9hZJ0/7lmjTfWf9yQoUuiwppcb/fcl32VYqa
xcSp3Fjk0wPL17rcLjY90LPS5cPiFU1feKokqlzOuSWRfcLCVoU8aNZ5yr8cZrHVv5DTtG1nFPKSRdbMQvY13zaXaI+59zwiB/MQ8KVF4px/6WnuB3+/h5UW
FtLR/AE8YeavwRrmnvOJFpkPAL+YuP+lp4UrSrYzXw/7pFkt2BXMD8wvpIu53gIiPfOqf1nSwgs0sui0gNucA/paxKNkntlW2PfMvdFCWQsbMMPM7i9bmC/G
0hfm8bBvmF0Fs8xv/GVJ8yfgYzPLRUQ29x2W/8vT5p0WFfKM+ZC/fGs2cxFv83L2mF0Cg8xf/OV68x/gVTO7xUTdzd0X8z7sC24ymwQOMp/5l5vN1oIjzDf8
pZ35m8W898oEEDUwtwDnm9kG8N5w+cuK5rPA/LSloP7DwX/Zy3wqeCytyxJ80jS9JbwH9sHzO60j7JOmPZYWck5aBjzz07LA9mnj4OmcNhWslPYZrJr2G3yv
9V9G1CZtDpirXfSXBmlf//KMtgD0SjsAntWWWV7IQ9oXfzlVe2/5sSIn6sTO+S+JwrUvlxeyv7bOikIO0fr+5UJtPbCGNhqspb0MWmsf/6WZNg8spa29skbR
sl8nL9AlUZxd+OpCVs8P3qByfImQvK27/kuiPl/K7f2X+p+vHC3k3Nof9/3LyEp7They2NtPNwo5+Vn4s385NT3/hUpTakdtqC11IDMypY5UDdIK7EAjoatj
qSlylaHbkRV1glUDVjUscwSdqDZYWy6vQfXBblQJpayoC+z61APtTENLjjSMXJCGUS/qTcNpDWrWRT0n+OqiZA/Us4J0Qa4HNQBdoHk6nh6weFoVV9Tju4SH
0WJbak8HwYNyKvNDdA+8R3fkEzRHsfww1tmZutJxeI6iVGdYR5HvDt2b4tFOd+pJJ6FjoXvLqaW7I38cuVjpj4eehnb4DshhigKjKBHyEDwCRmOtxygVNk/V
ewgWr59/o09E/hZ0Or2C9Qr2LfAz1n+cnqLOU5RNBX9CQsRP2kpn6TTI01xvhRVPyagRA/kMnqBT9B58j9Ix8HyBfo968ZSPLTxFcfQV/q+UAH6BPgV5D/kC
6lEVKg3qU00qQ0QlkNDHyCl6SyIpVAwsRuWoLFUlQaXIgGpBW1MRMqTy5IC6NdGGwFJreZe5FuqYoEZxqiAngC9GxlSU7Kki8g3lHVtr5CpQPeTKUyPUGESj
KJB8aKB8ZstNWj7Q/cmP3EF36Rskn2UKpIngIOiB1Bp6EDgKthu0G84Upjt0ILzTUX8mcn60SOph8LvLO2DukGE0G6XmIgXSKqRA2gF7FS2B7KBg5KdD7wA3
wZ6N9c6l+dBzUWI+yiyTJYOhF1EQzaJ9FADNEwUHYB0B8l5bEHQAbYO9gzbLSX/PUAS4A/oMXYJ9hm5DX6IDdBm8Db0D6+OlmygJ5CmLeSJinsL4FpbuQznm
AawnTN7rDIN9DmsJg30AZc6ROXmSJegBrYH2Qs6LLJDzoBGQwZJjoHnK+H5gP+RsZDkbsoW2I19qimW+WGJDjeGrQ81oADlTc2qBXGPyhrQEfeGfAFks2QL7
ogX50w3whrzjHir1DeyJIJDvsu+i87QFsgvcDr0HchFWitTn6QFdIC34gL6RoXgAeQxbi5yWvoPnUTIN9jPktPQS+hKohfcK9H6s5Rp4ja4il4ul10EulUtv
UOIa7Df0jnLAXOibkFx4b9AnmkJT5ROEU2GNoCHQU8FxNJTG0ngIT1DPT86thkwGZ6DcPHhWgzMgK5Hm0TrIavl85HrY68Cd4E4sm0xzsGQOLQBXg/wcwVJa
AXsZzo3VtIH4yclg7JmVKL8H9i7ojXLS+72wdtNduk9lxR0qJ4zFXTIRPMW3iXhNFsJACPhaiFfUUhQXmVRL3iEbDI4Qw8U4MRZ6HKyxwk+Ml7/yjYWeKCbA
mghrrvAXM8VssVwsQn6K/JVsipgkJosZYhosf9hTUMIfuRkotxTllosAnuhTrBSroAOgV8DPT+wFgquRWyUn2l0NXUvwXcpaYgO2qBYs1pvFKKStaG8I8iFi
k9gop+adLfaD+/FpWolSQg/LI8UeMVSEii0ov1nW2ArfJrFNhIO7oWejBNfYL0qL9xSJ1vKojDggPlAe7RUfaR9KHRB74S0n7qFvLSdSaY0ohy0pAusn8UQm
vygM+48nQvuM3phZWnxBSUu0Ww5iLCywl2sjXwu5Udhz47CHeT8OQW6EGCz372C5x0fIqcJGYV/6wTMee7MWNNeagX06GHvTH5wAPVUsEbOwb1diD87FHg5A
mVWoNwrlVqGMP2pNxNIpyE/D3pwm9/5ELFsJD09VPF0sE0FijuAJV+eitD+4Ano5Sq7G+vZAr4DVQhgJQ1FHVBDlxW98ryrCrims5S+wtqCtcBD1pa4v6glP
4YR8A9hOsJ1hucKuImzkpG9VJO2wxEU0Fo2QePI3V+EheBo3D9FENBfeoj2We8vJ7TrA2xz5jihvL9yRmgov0F7qpqI1pC3Iv+J2QrmuKNlB9EAtnjCuN2Qk
6CO6ie7QI4UvlvliqQ/y/UR/0UcMgN0PS+rDPxrWINj94R0EGQa2FV3QshvKd4PuInpC+oD9IX1QZyRq8RRwrEcKfcgwsVNUEwU0T1QX87HdLmI9ttdFzJN6
vYgQzylYLAC3i2DU0hdFUScCtUZC9EUWlRS7kLbDekHZtAP6LXzf0KIh0jy0/Q292DyxUPygDDIVJMyQfpOVsAJr8HSIOEbmorLgqRGrImcu7xhURa4yWBnH
j+8l1IPXBtocn6MyWA+6ErbdRdQVY0QxlKoMT02ItfwF3UE4Co1oiOPnjSNUCdtrA7rgKNpg39vBbgSfNcrzOcFTFDaAuMrJ/npDnHFUbHF8msDyxHG1wfHh
eu3RXh1s5Wgs7YHlTijXG2WaQ9ugxa7w85GrB68v1jdInjtuOCKNcVzc4HGHzx57sSn83XBEG+NIdofXC8fJC2dHT9FM9BXtsNQH7TVG6X7w81FsIzrL3/77
4Lja4ygMQy2e2K8prAGoNRD1ik8aMXKc7xgvpVUR/uHzR+WfCSYt+ybMq02a+5cUzxfnQjXnCo58uLu69k/KyN2n8lzB3Vc3kwoKTn0Lfez4afTn10tUlvq0
JmvLukLeyHyxoZBeryeEFjLzpVu4Sq9PjV/0TVCZmdvhLWl12Te3f0GLZ+3fRRfP8b3/qalB2aELH2x2unGwXbZRbMK5vpkOSW1vX87Sj62eyOydonlDsbNj
mQXXtr3Kj3l0grnt9pPU/m9K3lGZ9fx9TIdjTPsHJVP7FvtW3io9M2bDw6VvWjy/Fq0y72GtjKa7VP5K63rC71HGU8uSAU8jX6QaD858kz6w9DLjH6nXDTJM
N6deznDbrrJZakbM+SfWqa8zbkWovHy/wOC+SfO73ifSnq65c+fl0nCVpe/wZ1e5K3VlgxYJeWeWU0GGysxbC8pfMFGZf9FQL+XDmFvPY/a/cLtz+vu0AJW9
bn5pbL736o3uHq4nQ28U89gR1/1670arIjXXBzaaH+lx/dUrvzCVhtfHNhoW+eRsNQo3VBl39VijVbsWX9Notp2cdq2txvDkfNjJJ+tca645FG1/zU0zJebB
1W6a6Cira66aEzHXUwY0nnxl2FXPE28ySt6is5VeVrvKx1Gl6dU2mkNHT1110nyPdboyQFP7yK8r9ppD8ZlXPhrFmVjctXU9eXDGlSGvq4SqPHc+o1zTr8Mu
d9Y8PlT20hBNpQPeV5w1mQlmly01EYlmKUGNL+zwPu/q/CbC/9JM9/IXGl4yylwTonJLzBHnM7em3yxiEFxGZeNLNTRJZydcNNQsS4654GY8t3zauY6arnv9
z53KNNuo0vFcaY3zBQfQ5ULVc6U0zS/onSup6XnhfTKfmSpXJHufWJypJA/TlNwz52yY++Gdc86W1vS4yPb5lDVJfVyPRwQkdX7zMVild1J7jTZSez7ho95y
XZZJ/Ozx4lLemc8eHy+1uPy1hFMJlQGxMXnT5z0688Xj96UTCWtM5pavHN9Ds2SnMbhgZ5n4LS6dtqrMidvu0mJrXFytrKHrVY6Mi3Kx3Hr59HcXTXhQbD/N
jR1Oh66f+/RexBfRzLjcNDbS3TvCNfaDx4ArP2J6aQJ3tI3hb59Kr5j1WZv+MOt01xObssefaqEZut3j9BcPr6tbjmd4HLsWdLyXpkNE1eN9NTUjzI+HujbZ
oncgwG182NgobNu2FlFdNZO3KVFh7s3DJx7Lyg5co7J6VLbH8uuJh0edsHgXfLi9psvW4MNajyM3Tm3cl2f35A8PzH3bbtV/2eLQepOWpQ4cbKuJC7+zv5+m
eXi3Ld9LFxQs3DdQk7ul/r5ab++v0mXHA3Flw4XRvpnuV8Os97/2eHbTau99j6G3Zu7p8HbtKl0e291G02RL091bc3oHvjzpaJH3re2uZSeKfQgNCSw2kWru
2F0xpdy+7abuJqHWOx54RNzutP2+x+XbkRF9crYHqYzbZu1+btP0iG45m4NU+kX4aoptVjkMLLLZPmKg5kfYxE2mH2Lm3d3W1v3FpvlbzXPGBKkcs7Wf5nSY
/Y5P2euXqTwadja7TJDKulvve7S/0y7susfDO/dDO2pKh50PPXCiz8fmm9a6N9hUeZPGtJLBwpDZ2QmBuly0Yaf755AbGwdqYkIvbzTXDA3tuz3Szezeow0+
2ZGBKh02+GhWhxptfOrR826d9Tc8Nt81Wt9e0yt02obO2eGBuvRZfedEtdyYtQ406aPK6ateVkwpM3xVQZZzoMrcoO9Zjf7wQ9AD99CQ+KC+mqKh3kH33VeF
qJwelJfVIFBl/pqPWY+XhwY98fhx1z6wkyZnk17gXY/S91TeXt5D82STz5IM93EhhXyUZRio0jmgpmn3ss4BqVmlAgv5yn1UyLblcz0yQ5wDemgubnqwpKar
R6ounQN+nBiRq8u7M1eWtCs4O2cbHSmm0mgxr8tuDm/tlvm8DSpHzuWtUtl0Lm+tyhGzW2le/sNjs/lT67LF0AZ5SbPnzeZ9UnzOlyynQJUlZvN+U5k/i/dn
9hQ+akazeG/fm817xns6HxfNVD5SzRekZU1dWnQqHxGVuybzkd02mY9yziQ+7rr0mcJHttMkPkNsJ/HZsm8CnzndlrY4V+Zz6AQ+l7YtOGtx6Xf1CXx2nfHj
801l1Gg+q4uM5TPz/Rg+S1WGjeazt+lYPiebjuazWn80n+E0ms/2/FF8/qusPIq/KedH8nen7Uj+HlWfO9z4bdGWI/l7dGZIDSOTghrD+btmPWBO8rkPemN8
qPgfxg/hb2XfoeXfDlilMnVwn7fBf9h1MH+XfQbxt7vI8N7ul+94DeJv/eKBgzWlwod2rVEySlFZqvvBjwsfqdw3KDpHb4nK5P7ck7QcyD1Dv45Hyt/XH9x/
fs7O1Spj+jzWt/6e5sO9U5oP91SHfbjX+tWb+zGVil9wGaJxvbmXs+nNPV773ty/Kb25D+zek3vFDj25h3zWg3vL2z245xwxgPvJXV24Z94z6LdJQCnqxr2r
Ywdb0jxTGdCFe936XbgHVlmjC/fMKqd05h7bqSv3xg07cx9u35n789mtbjRudr1nu1MWA/KfdeI+v3gnvgqcGrjGee+9qI58XVC5sCNfLwZ15GtHz449NIt2
Ord0d34ZMa4jXx1Ot+drzbp2fN3xb8dXpUHt+Apl15avX5u7tHpvH6jyTRu+rql80oavd2Nb89XwY2u+Dn5szdfBl634Kjm/FV8xVY5sxVfSjq34qqppxVdY
j1Z8tV3Y4He5sR/yWvL1V+U+pwl6fq+DW/LVOaB5n9wVy1Qeb85X7d/efAUP8R6iebd/ZNMOmvcHXb35iq8yvxlHAs7efK3v0YwjhB5NOVqw6EgUWVZllCdH
NV+8OMZQadeE44rznhZua/cs9eJoZJIXRyYqe3px3NLBi2MYlfpeHOFs8uTIp4snRz4qm3lyXPRVw5FSE0+Ojt5pOF7K0nAEtdG1oHhQ6XXuaYbzDPtrONZy
1HDcVUiOx8w1HJtddB/kUel0RXeO3Iq6cUS3po7Z6w9XVS5x5XhvsAvHhLr8Xd2i2OsB6c4cN6q0c+Z48rirc1JCxhSXPt/XLm7l2tfdOU6XkQ058tzbuK1r
sSOtGnAsqrJOA45R7zhxvKqybsPxDYokzqhXssy28pOdOKa1crJ1sj4y0YHj3i72HBv71nBPenY7wIZj5rYNNEWHV5hjW/NF8f0qb9bkSJu57XZj6+nGI147
VOc4nFlwTZeRVTlWZ/ZOmVot+nnLUyqrV+V4vpipUZnJPbua1cjzXKJyiBl/fwvJ35dC8rkXXKZ0ZpFwXQ4x4z1WSP50tmauz1OPq3xpXlBw5tkn05XZl+7r
ckfp299mLD9W+su7M9v+y2d6c7MnRelyV+mJr/olqQzQP/O2V3KvkiPzO9w8XDrj09FUlb2L1/xR/4TKukVm/jp5y11/58+r64kWfx4Q8i+1WfFH/188/v1w
tMpOZEodaAgNpmrUhyqRDywf6K5kiXxX6gzdmTqSOaSDHDrUhSwg3cAhqGONUpYoPxhSDSXNkeuANs2pFpZVI35rQC2IJWgpvZtpAG1HGkW7KBIyCfSnvUjz
aR8doXV0GtyHHP8EHwOJA4PImVrRRkgvtNBLtjFAtjFKtjBJtuGPWkcg3MY62iLfV7kV6QDaGILtmUizII6gIy1EaiR/KG0lf5Dm1ieiTD2wHpZvlGtaCItL
NcL6u1FfsoL0A/vRUKoMGQYOo/FUHeIH+tEUqklTIVNoGtnCmkbToafTHHKALAGXUkNoHu7UELKJvCBhYBjtoB6QneBOOkQzIUfBo3SWIpDOUjL2vwX2Lt+Y
scA2VIYeJt/v6oc1Vsf+NcUeNiUzSQtoC5QwQ6oCjxXKmUGqgzWxTQ6wakq7p6SD1D1RdiqW1sQ2O0AvwVY6YDu9oMOwZV7YtpnQR7FFMyHJdFi+HdULqQdq
O0D3hDUT5OU9kSIoBMK3bnpCqkCOgfz2v3gwnlJxhC7iGB2A5yJyN+WbFW9SBtJD+a6/TPl+jEz6jPSeBP5+UglRQvyWA8vKChMkQ1FVHKBotHGcEug+2omn
c+A52dJNugPeke09pKfgU9lepmzvPX0BvxC3+pO41d9UFC0XlW2XlW0binqgg6gpHxq1FXZCI2oLa/lznbNoLTyQWosWSN0ED14fLDqLLpAR8sHVrkiTxAAk
fzESyV/4IfEPjNNEiJiNluvJVh2EK791QrbqKdtrLdqD7WWr3cRAcKBse7BsdYRsdZJsz1+sAFeg1cM4Ltexx6/TDaTndJn4bZiXIbnyh/pPIA/9/wrRB0uK
CsJMVJSPhtYQjURD+RNjQ0gT4Q1pBbYSnYQPpAfIb7GYDhkKDhUTxHLIVPAw1sZreQl+oq/Q+sIC7R9Gnm/cXabmIgRyDNZL6Jco0xzLLURzrLchyjbGmhpi
XT7QPdC6D9pfDm0Bb3NIP0lvaB94+0GWS18/MYbfPgEdL4op18V1UUK5LW6D98Q9UVq5L+6DWqEVBkqqSBVllAfiAXgH+z5SzEU6KOYjRYsFSNFiCVKCWCV/
BObjEyJLRcpSB+XyaLk8QVwUwZAb4A3xWOyAvIafvcGwNyOxd4fIFnuRssVJpK8iDvwi9VdRRImD8MCnYgpvL79RTYutNVB2iNeyRjbKxgt+aJUfXS0LlkXJ
EmBpZbvYJ/LFYXFE/IYcBfchly/miAM4JnPEQujVYo24Bd5Cbo0IFy8g28AI8RY6QmyHviv0lQ/ioyipXBXJPL+3kiKugcdErCgQSUIosWj9mLSTkVuI1g6g
tRfQqdirvC/LKKWUZNQRyjVRSimObctHy4exTfmoWwC9DfkXaFEonCuAPx98ByGFKRTWGTiapGTAPxXr4CkK3uHILof9DnJL5t6hzDvYL9DCC7Saj9wLwe+h
M0Aqi3YMIGWQCFtF8GRgywjbxrniSnPUP0ZlqBS5gPwe7DKwGkNKUWukUtSbBJWjImBt6DJUH5YAbUAb+MqgTn0sqSqH/NaGJipN/LayYqQH6snBsfrwlUWN
0lScmtAiKkEz5M3egVhDMdqGfEkaLXMDscYi8mZwMZQ7Af9kLClBC2SNGciVoHBaD27jN2DDWoCSB5ErhtL89vDy8m3ghrCM0Mcaw6pKUZQubgozJR2SKTKF
pZIjckQlJU/kgd/EG2GuWMFnqXCuEo+vhlUZqRwsS8UMuUpgFSQzpa7yUpTDspeislIN2h48QefpDA0WxgrfltkptbEyWUwGZ4gZ4Ep4T4nyynvIKdjlFWMl
SFRQNomVgq1NsHeL3cJUOSQOgcfFcfCMCMLSCtCmyiVxCbyJMvxGw5uwzRQTSEXFSKkJywRU3wFpqljArgXWUmzlWxnrItkq9ZQxorpSVRnLM9LDU0+pD9ZX
HJQa0A5KdcURS5vSCloM0eIILALTKYCe0EnIJfAkeAFyS/IJ3QXvIveEHkE/oWfQT+gN9BPKg35CxUUeZVE+fUBbLiId7bmI4ki/sLy4KKBfYDHo4qIctJbG
CV7uIvhNTS6iPKQ+qKW6YhwsF+GI5CJ/vB8PuoH87p3xog3SeNEB0h3sDj0IaZcYIuqK96g7CJ5d0O9xHMYLHkxckVzJl0bIG6h8U3Ut0jwKRpon304cSvvB
/fJN6aGIsXbLG8r75e3R/fLNvvtlxMZvUz8NJsmlMdD7kY+h9tSGmlFFeaO6BdhSvlO+DfzNsN6K8mb2cOR4G4ZL+mLNvjQbnA09C5yFCIyHtw8BfeS7zIfI
KM4X9EXs6QN2hfaVD5f4kjfiVF9IZ1gdoL0RMXUAu8hB782xzBf0RmoOX3NEc91AfsjFlbrLfHPEVf3AoZDu4Gx8dt4f86Bny/eZz8Y2BYFBiBpnQ9R3nG8G
NyMqDYXsAjm67Y7obCg4Hrq7nNKFp3bxgz1GTvHCt75HIkKcCk6H9oOeIqeYmQvOgW8krDmQpYjD5sqhwnMRLa6UPvaMIR5gOkY+njAGseMYRGccQY5B7DgG
MRrzLPQYegedhKMSB8YhykqSb0TmBx6ugWl/3r+cBl6UOhURWBqsB+AD5NLoLcqkwcv6Lb2ClQGdDestLH5T9FvwI/gRcdVbMhbZ4GepjbnjFMZCEZ+Jb50b
I4IrAZZAjKVAl4Y2kdpY8NvJjEVlSBVJE8RGxoizqoB887SaqCVvv1kLeyRr0QD5OoLfbeUO2xpxE2t30QyWh7z5yUNV3GG3AFsgfnIXHeFzh9WRpxSSQ1o5
VusI4Vuhw7C0LdhT3g5lPUwsgsW3Nvn21kh543IWOAv+kYi5ZkGmgXy7eBbSbMQKs8Q8LJ0lFkPz+0jnizFkKt7hSCTjWLxDbMYx2jsZob1DfPYOcdNz+YDE
C/CTfGBCT3wCTYUekikiNVPEZRyfmSJOagzy4B5TMRwcjpipFdgJ+Y3QE8Q6efWfCj0HshBLhiOi6gH2QRqOuGron3IToIej1jqxQewRoUh7RBjSHrEFW85D
mGZBFiPtQYkt4GXwsjiLxG+1vSyegxfAR+KXeAr9BPIUOdW6LD6Dn7HsF5gL5orvaHcBWuV3jq6FrALXgsFYy1qsYS2/9wS8DDsYMdRlyA7BA552yDjqJKyT
iJ7YE4fYKB4tXxYcQ32G3AY/g/fAe4j8PkOeQbSgFtHKM8gD8A625BmsO2AK7GvQuSi9DtuXK/gxhXBETetgrcYe5Nw6sR/x0n5ETBGIZfbDs19OLZCIyOgI
eBTRTiKsfeBhcD90IrgOUVMsrGS0mwI7F1YS8rmolyiXrIO9HSX3ibo0lpZRXbKXj93VIBNIWzAR3rGwlyNXF3YNsAE8Y0EPsD9NACfIKQSuoMxYWFwnEbkJ
FIhcIL7zp+Qb0k+hrglVACvIh8Vcwbrop+2R2qC9BuiTPWgcaWgN2lmNtvvjyjABaTdaMUHrbihfETUayD7dHlZLsKWs3V7WHi4ffRoha/N0CBPQj3Lt3diC
/shze8HwmaAtO7AOtsNEToDiCqsOLE+wDvpL7p1T0IvZoST7PGkQPHXgqwMrBd5v8HlSrMwNgr5CVoInMrES58QpukqvsRdOUW+RCJkJz2v6gfwP6ZkprvCb
CUVvJAPhhKX8QNNV9Gw8yJ4Ev4mxDJYYoD9yQtlRohI4U4ySt+cDBE+tEIDUVPTCklHiPPwBYiI4EeuaCY5GGX74oil6ol5IPWX5nugfrmJdt7Gu23Jtr9Cf
vobwOkkUAYsIXnMZ9IkGEF5/ZfR9ThBuzx49XVMIt9oMfVY7OieWyhvzPbEdadiSieIH1r5IbJVbFAB9Hn5FmQgrBp4Y8RByBRyFkmnwPIR+KF6JT+An6fuB
8p/ET+gfgt/9fA75LNSfh5ox6BG49hX0Fw8hr1DmJ777r9A3fEJ6JOv9Qr2t2AquMQ/f8BgI1wtFjSuwQlE+DH3KOZGF7X8Fi2ufRZ/yCcJtPEJP8hPyFK09
RXv8FuosfN6lwh3nRQr6SE+cA7FILUUKucP/Hb4U5L6RpYjFsv6Ctfp+xb4gvylxI1JLsV5MgccSuiX0d9T1Ff3hs8RW/0JPwG+5PgGeEMvwLdVTvoProfsj
fwItrEe+PyxuZYqIAqNkmyeg9ZT1oKGihxa+I8ct6SlRopHSWKmtWCvOiqtio7gpdkodxV1xgmhAW6WB0hCsjyjVFlZ9xVO+N/7PYLKJV/F/ofX3m/EDB19I
KBK+Of7hQTvN5vD3GvNnFTQFBYPOhrj8S/fSxj0KGWU1Y8a/zLCqPbOQ5So9+8OeP1ee3rdYZUGBX6W6c/5lYKWi81VGfe9S78IClQUFBlaT4S9hlQG6WW2G
J8cyGnxiabGwoKClld1Cth/Dc8tyEez6VrvAb5ZaMNny41/esZyB9daq5LOooOCVZVuwruWZhYWMthy66C+tFoMJVsHgbcuzYJlKWSgzwnIIWthpmQHPGisL
2KFW9tKzGp7+lr0WF/K01ThwraXfXwZZKQEFBe0sy/7lHEtDMNjK+C9XWA4Eh1oF/+Voq71/GWaZyH7Lm6CrVSTY0DLvL8dZll3Cfpu/9LLyAptbsj3D0g9U
rBYs4T0ZAbayPAWWs0r6y7aWqaCx1aO/rGBpu7SQWst6oIllw7/c8LDlUt7zXcFnlgNAB0u/pbxv5/7lWssPYFFbr4P/8rzlWfiHPrwOZljGgu0e1lpWUDD2
YTBY9WEIONtMu6SQ79JslxcUfExzAN9aNAYT0qLBpLR4cFWa6wqsK605OCDtDBiTdh4cnHblL4+l5YHz0zQrC+mQ1hxskNbtL6uk2QYW8ov2KzyGaXUDC5mn
nQre0k76ywfayL+8mvosCOeDtjy4WVvjL+dqx4OBWg+wVFb4A11++DXtfiOspaH967WFnPGl//5C1vlsFV3IFlV/xhbS5UOji4UcW3lyfCFXWPVMKKThy2VP
/2Vaeo9XKtv83K+tWFXl/Z81LE2b6nLVz/Zf1y/WZdMfNmYbA1b+XmrVzv+/HFjwPe3UnAtfh5vNSPwv3+QPeCKqqFyc73VzRSHzHpYK6bM4r2zCx07/MqbS
CU9dhuTdqNu7icrDX3/nerb4nj/o9MIQlf2+pdlp+6rUfL39JbO/yqV5A34+Wxict6nh/mCVi/OSrWcc0eWdr8UuVXykcnNe+bPLn6pcnHcrL3G3LlfkrTBy
uqXJP//k/ntd6n0vqjV/o8uVX5IW50wp/+VxdIdFlz/NNVJsVLZ+m2j3sp4u3d8mOurHqbz95bR136sqc7InV/r0ROXJzG/RuadEdua16NIqDXL0XtkbqEz7
pIkr01Bl7+zYbwmeKk1zCgoOblF55JXFqV9XdemdnZfy5ZvKp58a5Z5NVxmdnf4EfZ/k5qyo40Edddkiu69Lf39d6j/WOlm1U9nvyo4z52upbHyvq7VnXV1O
f5racOw+lQsT75RteO/l9QHz91Ss/swx4KjthJQ+dWMa63LVg6xKV6qHX39mUMxapWlM1cq+Bvuv5daZYqty06WqsxYad7lU1H5lI5WBF+fZ72+oUu/iBftK
f6iJP2DXoaJj4lK7njd16XlWaxhs9m1Nuwvmf1jp1EKn/ta6/HC2yLxuz1QmBDU33pt2PaxRgx/V/uXzWcOKaMIv1D9tarfBtkGX6ir7B181SSl7MrhOg9bV
dVlsXfQsk6JmQdRgdQ2V1gc+LCai5UtnlSref+UPp8gauvTxb+PoWleXm4Pu11hQdtW06FJxNddOXGN2zzjPT69OoJXKCL+h898YbPDjz67SwI/3icoaC2ZY
p9xV2XY877f/suh43rfX/CLrxdro0nNG8pJ2Jd6NPlfXutF/eXIEH1OVoxaOX/LojcpFo+wNntsdXdg7KSdTlzv7/6h0rLouTw49GX+5jsqLnboHLDw5r92S
45M7qaw24KnjmdMqTTvOcnYKVjmvrW9yroXKsu12FbTdpHJP21uJ19/ospV3Yur4XyrjOiyJvhmtcnebpQanbPzaaKquqqkyuc1+x+7NdPmsGdHQkGbtU51b
TdLlgTZlSha5btC2RGX9J7o819l3URWny02vRL9corJ4s7eLHKeM8H7zuHxZlSZNdqTcqWzQZIXR/foqjZvteX+glsp8r1d1izdRadpk58t5ff/lgWvre+qy
fBO3U35/WMx7wU+XfirLN9neMCRIpWmT5m/GbdSlt/fo/K9XVZo2cUsfFfsvP116v1OX5Zv0SdyZqtKs+Zp6y5NV/vCaYfLirsqopp2zF7xVubLY4ytrfXV5
nSpkWP1DovmXYvxV5pDD1We7dbm+WOlXn/bosj1VS9PG6NKPfqau6KzL0dT3TacluuSH7f3wX7/fHz1KTioyHLkgsRb/IaySXCs2Ia3F/xCbxXIs34L/n1cI
fo/qPni3w78W/6PvAqOQC8f/N7vk7x01Ufqg8IdMBieLgWIG6u0Th1ByF8ryEAZmFDzbwd3QUWIayvMAjUC0kU2B4i2tg50tf/k6Lge68JC1deIjbUWJmliy
VXyiSfj/gH8V2wo/5z5RpJgqpouv0N8pGla0+EmTkR8oIrGUfd/pJ02H9yvVFMXRTnHxnpi/6b38LS8X6/qAtb3D+s5Cf6AYKqB06A+UDPsD7GSsM0X+knQW
+ixdBFPAO/QFa/pKWZRHt8BbxL9L35LD3G6An1HqB+QOyJM+3sF/pzyU7Rv9kvkHPL0jeEP+LngT/gf8i7g4jv/jLuL/oVP4z+eSiIWcBmNBfgdtsmQKNP9u
E4b/AUPkbzcJYj/+B9whEvGfXihqxyEfhiUh8KXIe01n8H/hAfw3uAf/u54Te2Enip3IdZX3CVvJR9JbQfg98svEAshKeRdvpRiHtFIOZugo+mGpD5Z1lXcx
u0LagjwMohXECzZby8QI/L+8DLISaTTOCR5oMxKenljSE9oHrCUH+PDEN2PkwIcxkPawVsi7u4OQ4zu8g1DSXbiB6u+QzrDdhYu8X1wftrNwlAM4assybmjV
TehJmomyYFlRDn4vWdtD1nMRDcGGsp6jqAvWRe0OckBJBzmAwFcMBm3BfDITlfA/rJucBMkMlrkwQJvm8FSSQx/MkTMQRbEWAwivragQoBCPSYhSoBtyehCS
fIwz7DHOlAKqhjXwnXdbkUWlII/JTt7neAxJp9ViFv7/XS1mSj1LzIE1BHqmGAA9GzIHaQiOylzRRywU88UaEQwGi20ov0ByHnSEWCTGw8+/r20Th8EI5I+I
YyJALEZ+CTzjxVh4juDTL4UvQNSBPRa5AJFJdcAOUmdSGVhVofm35SfgMyohDEUJaENIMWEk+O5NMfGcFPGCnlIihId+PoUkIsXTeSxPwtJEWEbwGNFl7KVE
sLooLTKoqnhFmWCGHM5UBPoyyryG8K9PVyiDigi+L/6ajtJ9+fvSfdhvIPepuWgmWoihcvjOMDm11TBIL+yj5vD3Fd1FZ3n/nye8aiLagG2QayYcsLS5/P3H
AVJFTtZUAVIDbAapguUa+auvRjSF7YDzyFM0kkOHHORwEHvhBO0gnz6wluRf1mtgf1SQv7lXFDbCVFRGzgg5K1imoKmwQDIV5eWv0uVR3kQuN5JDZ4xESXES
AdJxOkGCdtApioXeCc8RikP/otA5Kg1PGVolfUOoN9IQGkYjaDSNkXqMnFR/vNTjYfnRBKkn0ByaQf40Sw4QnQD/ZMhEcJK8kzIZtj/oj1LTUGoqLUK5ubQA
9Xiy/gBaAZutRbQUS5bScjAAXCGHBy7H9vSmPXJI9Fo5+f56+CLQ0nKUYh1OK2GtoocosxYlh6PEWpRbSSFgCHJ3aS+tA9dRMBhMm1ArAvUCUCeCtHQPHq0c
6JpKQbQVvWe4nBr2EW3DXjqL/cYDEs+CR6Tegz57H2pdwr67gb1WBu2sgvUQ1hHswVXgKrTeG3tuONIY7CkeSjkaHC0HV46QL2cYI5eOx14bgn02DrUCYA3H
nuOhl/7Yc3x3zU9OdbsQ+3AB9tIcefd5OOqsAFeg7BDU8kd+MpZOwj6bhrQIn3AC8ryc9+N0WkaLaTZkHlrwR4352H98NGZhPyVQEXl/rCgd+POcEj+pZIlU
nyrDqi+fKatOVZGrT7XkBNp1kLeFpxY8/LuzFZmjjBWsSvBakR1Zk418fssGy+vLX6VdQAdqjLr15a/SPJC2DrlTE9Rwgacpct7Q7tQCPh4oXQ/tOFE1WM1g
O1EjcgVd4WlEHtCucpivB7UEm6BWW7TRhjrA4mmzvambHLjfmXypB7WndrD4DmUHeH3g6QMfPz/WBTbfvWyD8mPBsVjaE+xGI8Ge8n7mYJQcLO9FqtN+t6TW
2KZ2aKEldZTPJ3SUk3R3gfZBLV95d5QHz26Wdzk3wDZE33MAtIO2w2dYDRkA2kGMyJjW0EAaRfvpGNa7GTWHotYA1A2FjqJrtBH+aNke392MQj4Mco0Goe5A
ug5PGG2h3XSBzuBoHkCbkZDzsIqiZjEqQQfl0w0HIWXB4mRC+kgmVIrKUXk6RHp0mGrCbyF9JnJK8YpkAE99+A6glRqwa+A4Fcd+Yh/fIeBn4CrAUwe+Ujj+
XMMOn7MUvD4gP8FoAC8/D+cDHz8R54NzqjKOehWqTQ2x1ByfygDH3A6WFY6lAfLWKGeJkpVxrrjgTOO7K5VwDKsjtZBPzNXAFlliWVPk3HEWmaNmW9SvCu1I
zckZS5vieFdHLa7RAqXMUcIXdbvh/OCnI33kc5adsWYbHDNrHFN7WPVwZO2Q57PPFUeiGmQAlvaQy9vh2NugRB+UawbthCPfCKkjzkU38qKuaH8kzhxH6kXd
UYvPPxuUHowyfVFKQ52oFc6i1jhfnOS55SqfYXRDzf6kDtSb2ESpW6Tqrknxi8TPhLW+/RIMzEkT9FXx7H0pTFNQoH3nvlWXLb4ZZheJ1mVBwbfvPU6q3PXt
wPeYEyqn57V9ezW5S97L72dvR33UZE4PU9n20/x3YyJ02fVTw5cVDqhs++lcwfD17T91zLS41O3T0i8P01TueD/ny4hlKkNelckZsybkVaWsAetDXvXLjNgY
8mray7fhheyd8XK7ytuvLj8beEKl/mvTbIsHuqz4clEBPbfJNCgzo9/TtItFBw5NTT8WU+98j/TdMWGJzOSUy4/CY37HMgdej08PeP4pVpd2acExQ04yv98e
eWf3q27XVE65Hxgz70GdCwalH3+cdS/6+fb9KvfcCoh59nDp9dzjMY9uJtsU6WGocvHVfQaTzGtd5W1Wee3Kghj9p8euTM2YtV1lt8uPDEZXvHEx47jlM4uL
A1+6bFV5Jumn4ZryGy7wZ1eZcXNdKT0jXU48379834rmWj+j7Ncqv5ybF/PmhS6fJSc3Pr3X/sqWxmsSsvc1/nj1kUqnlJKNPx1U6ZBs77H9dHqSdSPH3Sov
JtVrVBOc/KrWZpWhSW6NSu5unjivUYPIskklNbVPUVIFzaaTJWG3OXU80VDjevxUYnFNfsyAxCqaptG7YTvHvj+Tfrzmy/1nrr+yDlMZccZE43msSWKBh3/c
6ngzTcChgDPfPewSJpy5atS5YpEzua+0oSrrXYkpFpd+LaGIZvCZ7fGZHmZJ2+N8Go/bmXiqpPPq7ckJt12r7hFxLd3nX0iIjXjddpPKAbH1NEsPJMZ+8GiY
/D3mscfP5GYxFYzNjHMOeVHNTJW3480+vVs66JS55uNecap55v2NKrvGHal4Jy/25AOP3RdiwD0X9p687xF9YRV44cK0k3xOqjQ6mXE8JvNZStmkNy+Wn3DU
7NtT/MQDj7MXi58Y7m5/WaXZ8dquA7eXPf4k88gGlVejTTWzdgdHJXq0T5kD9k15dao8na3gFtPUOf6qLodg6YgUXXocG21iZrztSDWN3a71R0a5FGydfGS8
S95W7yNRb2oHq/x4eJ7L1a0mh60103amHJro/iEi6VCcx4UrKhccqqFpuPP2Qf5+qbx4sEqWzx92OXjR5UP4hIO5xy9n5+031JTb4RlckNwj99yBJI+dV2vs
PeJhfN1kbw3N94g9e2prbkVs2zPc9fOWT5FVNfUjrkVW1lSLWBo53D0//Nuuqdld16rcG3nSI/t6ix0lT7R8Z7HDTCO2WezY6VHuZsPgNRbuv9ZG8PddpWNE
Bc3YrRv3tXg3IUhl4NaubjU3+4Xba+LDj285lrN1dcqOR3pVioZswRHffCg8ykNza/vmCI+kW1abX+b4rla5KTQ8x/YPG4dV0HzeErG6TvbqoP/yZoj1CfsP
ezfMrzjCsN6GDLdroQc37PD4cftecIRHjTtN1n9xmx36a/3T7OGrVH5eb6eJ2ZwFntrscfDnpw/zj62vqzmyeclq92yDZSp7r6/oHhaaG1LTvdrdj2ttNOM2
N1zVMVsbpMsDa7d77L5zMyjUw+nuvXW3SukX9A6y0JwNU9k6qN2J+R/3hI8xeVgqZWV/93ebSmzUUJa+yh0rK5rGGRZfqZ+9IkiXesv93A9v6rqirmZCWIcV
Lz2swjzCfZ1/33u3LD1rdJAuo5dZa1qGbVx+wOPQ3cNLwjxy7y5fYKQJD9Xlk4WTTrTKbTzCKc/vicqFE0Kpl57KHwsSKo4ul7x7scHJYlkLVmYVD1I5ccEO
926bvBbU0sSF6vLi/O3urTeFzWiSlRyoS6sF+z063zsyz1KzM1TlsnnbPAbdU9ltTlVNSKjK9BlH3G02nfb/XTGv3Gn/oVnawEIec68Jf1XNvNDT/qEnAnN1
2XroqqLnvgZPH5n1JLCQ3I7KAxN4q1RWmsJryZrI61WZPJG3x2xCSP7xWaMnds4KCfwvO09p67F9U48J/CmcJvAnpQm8B377LckqGqRymR/vGZXT/Xi/PR7X
03x1gX7/ogYFBaNH8lF7OiIkefWn9eN5nz8ebaYxCDs3mo9Lwkg+Uv4j+aipNBr5JmvSHzoPruK+7F7NEXysq4zg465y9ISZOeaLVI4ZzueGLh+N4ON+cxif
RfuG8dllO5TPN7OhfO6ZTc91CUzV5fYhfJY6+vJ3YdvQ2Kx5gbpcMIDP8HEDIrMbr1Jp7svnf9KA7R6RdxL787djaX/+vszpz98dlVP787dJZav+r7LH/mF4
P/7eNevH38RvEx+WIkrx4e/mq67cD1zw4e/m9j78nX0/1YSCPqk80Msup1aQWy/+pk/sqc3xWa3LWz24f0jrzj1GQnfuQ3Q5qntdzY7wWq37vbu9RJfm3Ww0
+eFeXbhHOt+N+5nJnkTTyvfqxH1Xz07cj9XtxH3ajPbcy6nMbse9X2Q77glT2nG/N7cd942323A/eaUN95n6tbMzh9xR2b8N96Ud23C/Or3TVJOHZWa35F73
QNttxR2KqVRacG9ctQX3zAeacy+tcltz7r1VfvTmXv1wC+6lj3lzPz+laakfO+bu8+b+v583XwsWNOPrwuSu+Tl1Vv+X9ZrxtUNlQVO+plR22l6yZ8n0pnyV
UfmgaTWNza5rTatq7HdFupZwXr89q+l1j+eXGzbhq1I5L75CffHkK1q6J1/d+vYYbDy8RIxn2eSL2ZEavuoN0fAVUGUfDV8Zx3oMd+++6407Xz3HevDVkz32
lwe487X1pxtfZ1VmuPH197IbX4tPu/F1+ZQbX6MnuPFVW6WBG1/NVXZsO9Z5x537Lq+p5wuV9V04BvB35njgg+M39wsHVB5vzDGDygmNOZaIasyRw61GHGnc
ashRx8KGlppJh1XWdeL450SDOpqYI34NOEpRuasBRyn7G0/JvbZc5alGKwxc85UGHNW8deII55YTRz6XnDgKUrnIiaMjIyeOl37YbdTv/s7RieOiq44cOyU4
ckyl8rvdB7edJ3QZ68ix1ghHjr6GOnI8pnK+/WwDa0OVqQ4csx1w4PitkBzXrXfgGM+qflWPpJNr6nF8ONueY0XyPmXxJV/Yc1Sp8kCtPMfQI9Pqf3RPjUuq
XVBwP+BxHY5FVS40TSt6c0Abm69FTCr0rMNRq8qddhzNfjO/n+SdWtmG49uk2hzrqtxVm2Pg9rU5Hlb5xW5Jo07n3tbiaDm7BkfRudWPv3i9S2VwtX4VnbOv
VOUY+1qVbqV3VPhtGRiTfux/nPegpRlH7Mzvt/dU4NieOfC6lQnH/P83k1P6V7j3rNdxlaHG/N9Bz4o/DVKelC7ZoNzFEfmlL+YmLlP5sDR/ywrJZ2Mh+QgW
kveGS5FyGQ33qHxRZM+L3mdU/i6tzemkVWlJy744BRK1z9/5KF98FXWVe6KK8li8EU9FdejqylPxFrmaylvIR5EraiufxGdhrXwT+cJWPuZvq3wQ94WFUlV5
g/I1UauqUh1layo2yldho9RV7LCMl9vBXx3kOdB57u3tYpN4BtkgHoh14io0Pwx5AcJDX3hOqoMgD4Thn2TDkRbLQTS/REllt8iC3o76WWiBH7fcgBa4nQvQ
a1DrgrwJk4C626AD5KCUcNRfia29ju09K4yU6+KsiIeOR6tllWgRhTb5dswvlKiAbb6OZTx4YDvWEo8SRihTUimLT1xLeS/egzzooYbyQrwAH4lHopqSJtLA
u+KuqKRcEZfFFegUaHPQXA41MFGSRTIYI06LGGGgnIacEqdEEeWEOAHuFDtFjhzWkyMfIjsvViOdF8uQNoslkFlgvuCBBx+w/3kraim8/hoKr7maUknObF5X
7ntD0BAlbUF+J46dsl6wroFkqHBZE8Uc2lAOxTBE7jK2mLfUXOFtNFF46wwU3q4iCm9RDrbFEK3EYXvOy0FIK7BFJijBpeKw3ATtFEEylLk4lDoPcsk4lI0T
TSXXi+JiuJgjZ9kaBr0SR2c6OB2eYWKgGAPpJef/by8GyYFqnSHeoLccFMc3OtzlbQpXSDVRG2IhKqOFEWKv2CdGirloxx8tD0Mr/mhnlGxtEHR7OaNQB9FF
+KK11mjTWbSUbbpD10eL7mjTUbZcWzih5crQFvIxSQtRUZSGlAMNhCK+UBFRQHnEc0C9hrzltyfRK3oEeUbX5PAOHrSRDs23wngOwIsUA+GbacmUQPsgp2g7
WaBFI7T7k0qDecTvMnuNlt/RbcpEm4/oDtq8IVvmme54xrxraDNJDhvh4RHJdEC2yfMKrhCTcFxWiHHQ48Rk+VD2ZOEjbzJ1Q+opmgu+OcCPezcT9qKeqC56
iz6ihrx9U0xUQCrG4yHFe+JH7PkmYTbdpyyk+5SGFE9apHh5w+EwXUE6TGew3slYnw/Ia+gp224mamJLmsIXh6POuimW9JQPrTYDeeBjU3GUzKF5ncXk2t7L
9dyXa4hH201R9yjVhBRDiaNy+VEsiQdXgvyms/fyFsgYGkX1IUPJDjJY/vw1kGwgA8ABNIisIUPIVt4asMXeP0lr5Q3WZZBoWiDfeLYAspem4+hsxx49hRLb
UWYZ9HF+by6WTofeS+Ohd9EI6F3kA72eWkLvRY49W2Fvhc8HEkjekPngfJpBHqAHecHin4BnYKsbYZvtsOWDsZV28kc6G9TyRnvzUc4bJeqjDP9MzbSDtpM/
SgeTJwXRUnKhJUgucgZLT+Tj+HiAKyiKjtFw2g1GQe+hjhRCm6gThdEG2kzNwGZoZRiNpjqQseAkcpDvaXZAbjE50yyaCWmAtp2RnwlrEtpaIVsdTp2xP22x
vcNQ0xZLGsh6/ON6MFrmbfGU2+WC2ptRuhnacpY/hnpCe+LYOSOthGcldSNHbPdhtM1vr1uBtBJrOAo/z8zYGbYn6ncGOyPPP83XhdiCPL9lXchKsC7oiC3g
FuvIgcZHqbjoRs5KKfmeDWOlHFgOuVLKb9EIkg26KG5KHfhdlIoQS8k60M6wjLHMQwkWbpA6iqviqPB7kR2V+rAbQLsqjaH5jR4uipPSULkoGsJ+LhyQ2wr7
uUjFGrLFc8HvmvBUHJR9IgP+VHFNOKH0GdjXxEXYh0QEGCG2gmfEIbSwVQSCgejX3BUvRYPt0BPBoh+VppHUj1pBt6LmZAlpQpUgGrAV8qXlWz0tkW8M3Ziq
gFWg7eWgbUOZM5TvHDUkJ9j15M/EVZCqwbdPzBMzxDX0L2boaczoHKyz0GcpFoylg9JXkeaBZtD7aQeZw7sfuR20DvY6Wk4WcoZMC4g/uB9eM/kOTws5LMkC
ZSzgG4lt5Rs25tAVoUvDsgAtsWWlqTyZUhmwLLShfIeqIbavCKQk2E0OUu8u5yg2plLyTar8sz8PcDCWg9ErkL6SIRaIl2K/WCgcREfxlHYh74DcTDFNLJLv
mFkIawA4QHSCNVPwW3dGI8fv2xmNsgtQbwCswSA/IjAA0gBWG6lb/Zlfzw3+hmihoTAGeeCQCbSxeE5825MHI5WBXUb8oufUUd4Sfk6/6C79pny6B3kD3qXH
dF4OVT+PpXfBm3Rd2vNk+fPQesoXOaDx6N/BIYfFHpAH1yRCgkSkfIwlCInf+rNWTJQ2Dz4JQly1BlwuH3oJgA7C0tngbMRZQfKG9xOhKD+FnnwDESkFyBWI
n+ATxFCKogfvffEQ9hNxXLB1HGu9j/L3xRfoRJGEdBZWEqKns9KXDj5GdHlW3BBc6imiyy+Qt+Bb8VEI5bP4Bn5FfCOUfMSXX0QJxRSfUyglFIGIk4cmf0Ds
VQI260xYmYi/2P8Ce4MHvvCnjpTrj0Q0l4ToLh6Mgk6Sj95EIqLbLecd3Q5ugI6UA5RM0cIj8BFiOFNEclrou4IHdnMkp4WkgCmI4e7Cw/5zKKdFPhl2ssyd
EzehObY7BznFQ0QQ1SXDcw7pBJaeQHx3E7IDvAlyjLda2qsRUd2ELMExmI8jMBux0HyQ53WdDekH9vvzmMMIcASWD0GUNAzkmUqHwBoO9hPtQB7M30/0kLod
4p4mIL9VqR2in3Zy2H87xD48aK2JaCRnYuTh+Dx3pIuwk7lGiIcaIRpi8gMhdsJGWo0Ev/2zKnRVYSXnDLUS5UF+M2gjWEXAIshZiqLyRn5Z5MqKr4iTTGEZ
Qr7Sd+S+I775Sh+J9Xc5g+ZHegi+lTYP/vuOfAbIDz68Ap9BnkimQ/MUDpchqSA/EpEO64LUlxEPXUaExTwNfRl+1qcRGyWDCUincUU/jes58wKdAE/QIfA4
fDflXK43IZPASaKtjKHayjdp8QC+oYhv2spZTG9C94Xwe8PaQhqDjeFpjKinL5K5jKMELIEYqi/kJTGz6SUinCzi3Ev6gdjpDIXiSh0KHYfraqh8f+hLOUMy
z4rMsyBflTMjh0JU/YN2UgStgWwDt9EU8DRF4hOcxieJhOyEh2dDZk6WjzD4ytmQfakLpL+8XdxFzrXeG7q/vOnLvqloIxIxUDR4BIkH5vKUKnvR5hpYkSjB
t9nXSD1VToXCjzNMRXTDUc5UxCvzwRmQMTKymYpWx0BGIfVATNZD3nzugYhsMNgLeqCcfGUAyLOB90Jk1oO6QvMs8vy4gWp1lbOHd0VsMRHSFfHMbuyJY/Im
8gbEGqvAVYgwQmgLrUa8sZimyUczpsmBrtNklMSchlLTUH8VIhl+mGMS2usKe5JkV/lu6VlgsByMuwqeUKqslFGOiO+ivBzCXl4xA+v98VUGyyihkKUiFPkj
IhYshlLfYd2BfUe8hjdM+IF+0hcrTkJC5LQNIfiWl1FKKzwjcAi+62XQcmm0rwddT7GXthl6YTO0+BNbUEx5KN/HWhztv0bv/xrt7YGcRC9fWrkllmKLCLXL
Kzy4yUzhSRDMULMAdR+ixy6G68ZD8Ch67dfyAag78qHHk1j/Wnj2wHdHDsish/7XHtugJ/UttG4PywrkKRLsYb0TVsor8U4OoreCFIXPSikKH0+nMEW8gscL
Vi3Y75CrBfECQ7GVJfBpY8UE2CWwV5aKXNJHvjs8sUID7SdKSStWVIKUBEOwjOdh7o7erDuWuEAqCVtISfRDfmgnhUqIT5RCsaj7AfxAJbHsA32mD/QAXCo2
Ui75oVwpwQ8xumL5ZyoLeYAe6AFKpUIugBPQg/K6esjZa5vINbpAa0QduV5b6EpypuVKWHdVrKU8dEn0duXR2lfZ5kfoB+ilPmK9c2ijHPL8EOvfiPWm8GQQ
2AZX6A+wWmCtHygcMluyBfRscByWtZaD3ZtSO7A1dFOQZ9SvRW1QdjZ6r9kotxNLt0G3QLltKNEbZTZSbayhHWpMhvBM/K1RqwdqncD6ZuM7zXV5YqBxqBMB
RiDXDn3GNtSdg9rtUHMK6vrKFvpDu6Ov4Bn91fc08IMlrijHrdbCd2WpuI3PehP9XVGlr/AUPPGDJ475bR44jB4vkTxx/L1EDnQOeaHcD0qkWrCnoHQi5aBv
WwTPFHjmQi+Cpza1l++zn0MTsIYO+D7WhtUeJUPl8oYomQOLdUM5nLQhloaiJPsWwe6K+u3luwyIDKgo/qlV5Hvn+XESPVilSB8syfHjFD+/oRMHThzrO+a2
cFGSv7eMnxd1MKHLtoD4jktraHLantNc3PTOI7/2up9rY1WaW0R/m+z//+Myi+25RRLSjY7kH/P7l675s4ap7BtZUDCljy7TjablTfcp5MgvZ7oU0vDzqNYq
++3d9yX/pi7Tqzb44d9Al7VqP3029rdKvf2nX2f46DLd6OMrl0oqt/0anO56UJdlzCMen33tuXdNZv/iukw3ssi4blbI2s+6VdClTUWbnGe1dPnm56HXvYbq
Mt3IMv22kcobpnPTdi/8L9ONpj6sMPNf9n0YMz3dqPnD4XP+x/Bp6UYVHvafirU/nDW3kL/S+sBf8eFVUDzsUP5/XDzvf5w3Jd1oa9q3yelGZ9P6gQlpgWjn
RFrZBYUclTZ2UrrRyrR4lByU1nLhv2yW9mJSIVumVfxLj7QtkwvZJa0k6lZLWzOpkOZpCf7pRiXTnsEukdZ7YrpRsbShf1k8bSK2+bs2E5/0ozYXzNZeh/+1
9in4RLsZW/hY2xb+B9pDsO9rq6Ode9qe8FzQ7pqQbpSsjfrLs9pjaC1O+xPbcFqbCDtaa4hah7WmaG2/tg4YqTWHP1xb5y/Xa4eh/EptFM7SedpBKL9BWx3b
PFgbIj21pjN/+anU23/tSkx7XaYbTdRG47P7afthG8ZqJ0umoPwYbRjaH629gaUjtGvgH67NQWsntDexJT21Y6czS6FMR60G26DRPsena63tPaWQLtrKM9KN
6mmj/JkrJjN5q+poj/2lnTZah7dRy0a7f3Iha2vj/QpZU9vcn/3+ftzOe9gW2vvTC2morTzlfxw8ndc+GttWWnsRW1VcmwMW077m45W6egrb9ijzJbXH5ELm
ps7A53qbugPMSb2GPZmRmgX7Wer/6etM4Gpewv//jOVK9l2WUF1tRKisSZTtomSLooN0spU2laVFSZFCiKxZskVElrRRlux0TiXZsgvXxXUtV//PzPBz7t//
9399X/OeZ555Zr5zzvlOfL/fmee5gtq7JfxqeVBS6oXftEQv4AeLSmb7/mBhyUT/H8wveQZNdgn/3k6V5IEZJS/AoyXT0dvhkvY+vZoeLzocpMm7TQ6UjMEZ
t5XcAhNLTNBDfMlynDGmZC8+dWTJHXBRSW3041viC/qUhPHfq2QA6FVSE616lrh51dr/8V7JQU0apHxWVVVp8o82S0tZNU1Sh5LTXhWSBs0/X7Apl+z6b9qF
eWs0WVWVct17qCZr7R9cuGyLJj33bs58VSSZ3fpT3rm2knYdPqS5Jmqy2t7V54gkzxpHpjtYa/J868XH+gcvUpiffttCk4E+pieeXdak4YTdGQevSObYKjO+
5Wvyw871aVPGaTJ0okFQ1vUyJ4OgQdftRxgElV/1mN406Oq1G/YGQcsvx9oYBI2+GN3bIKhvwZ75k+Znny/qYRDkmLuwi0HQtlOxJgZBPY4262gQ1C5VV88g
aN6udF2DIOvNt1sbBG1I2KQDLv/WwiDIKbwGeDfwcHP05sXlAneud3DhNtpO3F57GG87YwDvp1sv3meE+YotJwKU4yT5ubxM+HmrG/AxjNblo1LqTPQ4Gfim
tmToxCn+g65bKsb6n7/2xeMP/z+unpo7yP/ipUn+/fx7Xxi5JSUtPFmTiY36WZr4S25v1MvSNEAyppGV5VpfyW2NOluyeZK3GhlYPlggWb9xa0uDxZKXG7Ww
PDdLsknjdxbnlZKpjdUWrSIkOzc5alErSnKsVrhl3yDJlMbpFj2nSTZpEm5x1O07mzpYGK2QfN+0jsWpOMn6TZtZdJwkGa+lbbF2omS3pj9ZvfnaHu/XSE5t
0b6HSaLk/WYje9xykvRih8yXbJGM12rXo93o2c1/cn/z6j0mO0rOb7m3u2eSZHCrj90GbZOc23Jgd4M/JB113nerNkySaKr5i1FHYg9ZNBn/K5WtV3XzSZY0
111rfjdF0qV1i26D7CTjtWLNtfc8bBNn7mwreUV3nPm3PZK99Fp3nXdQMlv3Ytcn1pLxWpVdbA/d1PtJ/Q7vu/ToIxmnn9Klb5rkCj1FF51ekpc7RppNOirZ
36il2eNjkvFaLcxefKeXVlvzGf0lu3dsZxbVQzKzY2XnF90lR8drd3uTrEkn01qdm5yU/L3La1PH05KXTWI6FXaR1O9k3GmvmWS8VqNO7zIl06K+9Ji5UZPR
MT9qFWaSrWbW7NTwtGSR8pDpw+/UMnc2PZolmWrmYrquk2Tz6QtMbuRI9rboazIrV7KxZUOTktx4rXvGI/MkZ/b6w3jxmfaKJ8bWeZLRMVwv+berqXHamVF9
7hvZnR07YdHvD9poUnuCmdHOfLPxzY2K8smmmZE6P9eGGX3Lj9daZlhZIJlsF2H4V8EHxzWGxQXRMVwj+abGXZ3yJpIjHLnNZPuFht8KljosNKwqUAwfYjjq
nD/ocO5JNY8W7W9ExzT8Pf/iqvhUvR3tFsevaZFwzXAV0Z2NampOz5FugabsOTEk/jqqOekif0Gd2CfUPKFwMFz40QzHDUxz/CddF6yHPBwSpyH01dhb+hu3
Qm2oBdrewS1RMchLbfCf8xf0CaWWkOpD+ga5LZULP6Md8R/1tkhM7BbqiJpv9AqlWviv/Gv6QPegfw3WR1sd3HK9xFkaUCvxIqVUePoshc4ImlLhDU8H9S+F
18pKtK5GXcSj6K6o1af79JQMqIi6QX5KKvqdutMDHN2pAroiakcPaQk9Ax8h70Ht6TGO9rjVqMM+U2cRfmUzDl2mRDLFN+LJ2rGTSAaC1ZEbgB9pM9uBW9Vd
bD9uJHcgN4GUzoyRjoNGYlebKXqqg1oTsTfKGDRiWcxQ1HO5lqAh8v3QcYvjwnPVaWGVxc6CZxl/AV2IW69Cdhm8hHQZvMhqIJ1hNZFywByWLTzJZbMTaHVB
WNYAL6KuBjQdhdeojpBzGPcx9xvstESIp89UC9rPVAPar+BX+ky8/qvwSPcVN2v/EqGshZIWqy14gh1B+Qg7hPIhlgqmMu6xby1upHkoe22kpawujqUsApbc
rjbqub4u47f2ddFPXVZPMAJ5PdyAv6F6witMPbYQpXrCUxb3olUfh7/YkzZf5P5sLjhb7F9rwF4T37HGPWk1ZB+QGonAUXNFPX8h3RBpCo4xqGmIvBGk0eBo
3PBzDhN5Y7SqjXFVYQyvqYoasyGsCbTDhCctG8g2zBq0Zj1ZU/F4tSnkpsKmCdrynWQfiD96bYZkBlqK1wZmrDlyM9YNebfv+7F6sxZgC8jcn9kHagbpAzWH
5gP1ZYNYS/EyuwVSS5A/8G0pHvrqMAck/iBYB5oP1FJ4aeUSf2g5DrWtoJnEXFlrNg3JFXQX/m1ao4b7am0FWx32DnOHvzB+R61Qs4HtZfqgnnisrSdeN3Rg
K6A9JfT60OnBlj84lp5l26LPFbAJZ4uR2uPgr+zbgu1R845aQ35HbdCPnrDqAP07ai8ePXPpd/R5iv3O3hPvWx8ad/TaBr23FSG72ggvsdyOP5jnSynyGfcB
uQ0SXxLC/W8p2Q02k60WHoxOswx2FTOlAPkBWGxjO8Xikd3It0GzG/qjyAswp/jShrPCMxh/BXAVs+oCeBl5BmbfUZD7Yr3KcsUsu4z8EtJFHLnCw1ku5k8O
mI0jl/FFINzXF/f2dUh4XeUeK9PYHhxpbJ3w5sXzJJaAI4lFQU4TeRJbxvLYFXYYaQJ4GOTLLSaIlwnLhH+1ZcIH7TK2CMcCFiiCj/F8AQvAwV8x8DByc3D4
CP+OzsKjsDMbKwJ1OYngXcNhyX1OcT9Q3PvUBGHrI7xb8bBf19gsloncVgQAsxU+5GxZfxy2IuyWrVhqMIF5ILdl5jhsWRcctqy78HRlgcNW+J60Zf2YIxvB
RoITxf5bHtxruggQ5oI0mc0QnoH9hIfg6Ugz0MJWLGmwRSs7pME4RqIPR3AizushQpF5iH4mogX3VBfDNrLtbB+uz3O4ikJQXsISWRx0cSwWjEU5RoR644yB
BQ+Jtx2tEsG9SOfYcvSTjHQevEf5+FepI2iFf0/y8S8RD0HJgwHuEJ62DwovigfFA7aDtIdWCH+P3ONjCE0RPh1niGULM2gO8pW0F/o9sDyAfC9Fky8Fikdb
3KdjNDRxqMundJT5w+p0yCegTaVNFCx2LubTaWg2QbMbFqspXjzYT4W0Wfjm3EzrYBlDkbA8A9tjdAj1MbQKmmzIx4Snzs10A7X5IN/rzcOPHhIeOtdRhvDV
yT3DzRSBFeeRNdmL4JIjQb5H0BP5SBoNyU94puS7KPlOJf6iwYUmkpvwtemGFEsX0HM2+jyKXi+IRTJnIWfQETqMEV2F5oLYR34R+jzU5EJ/BMxBHiVedFyB
zVXhd5LvOL8O28uozRVe1/LEiwB/2krLca5QsQeU7yGcK16s5MD6JtryAJ3X8Vl5mM4rKN+kjbDfSstgGUqJYn9nIq1HvhVMFP7VLn33tLaVkqHbSseRL0YL
7kk+lmaTKylpHA7ujZS/6nAULzkUIkSlh9gJ6o+yl3gJwneiVqee1Ie0qC++zeqQalMdSAOgsRaBWweQLTUVgXGbQhoOHd9l1hByY9IWfoIbC4u61AhyB1qA
0ZggJYN8CctgjDYfLERugXIhNSNzqoEWI/A/IL63ryZSM2j4Yo7jdJuGUAEsO4m2FrDvALsFYtfkYuqM/y3xZSmlkAaDFmIJC9/paA6pI/2G/51ZgXxWfPju
Jf0D9aJz5ES9aQyNAvm+w95iH2JvsVykt9gLORZzJQGtdkAaJnywjsVccRDhSm2gPyhqEvB7jUVaAZsQ/BJjIS2C7CA4A7bDRLhXG7GL0QZXZV+Qv1IaBusZ
KE3HdbkWc/K0mJenxR7ZE5hNezDvDiI/gB6PCY/+qZhdfDZfg/aECILKd3LPwDXKfSXuxwxwx0w4ijQP1/Ba9HUGLTZhnvpiFgVi3i0UM3g+5s5K9JmKcUXj
mo0XL6HWCm8KfBfrMVpDQbQFdXGo9UXPm0Vg0fnCV3MMLC9iDCswH7Jx3gzUcw+I+1Abifm1CW34S7DdmEEzoT2KT5uLdtcx9msY7Vm0cIc2Dz35iT2aPrj+
V+Bqv0CZlEJp6OUwdHzJwQp8R2fR5jJa5OG7uoRf/wpGfR7980VsMWjP/1qsQgsb2FwWi0/sIF/GWQcIb7gDxMuHvjjPJbBQXMujMe8HiD2Iw8VLjUL8zbAG
R4odsxMxiwZgdo2j4SJgNN/5OgIch9kyHLPHEZYusPXD5zqCkR7G+C9DnoUzeEIuFIGIZ4PLMcuiMMO20SRKwnxcjvnsip6j0JM/ZusyzOoJyP1FuN+5uJ4L
ce5Y8DjyQvR3E602itFuRbvhaMFfVM5GT5NpPG2AxgPtF4h9lq7oVwl5hNi1ux6zbTjSMnKmMJoGvaN44RkmAhorcLbaM7x83MV7hj9ZE/Ge4Zn11eykXsqs
ZWtP9Zs8oNw6bHE162XVfL/mLSYy+/rE8smnqiqfflHfzn69HH4haftba61WDbzfXUx2es95VGv0UyLJNjX1HtdK1aTTe5u3f+yW/Pub3puz2pKtOtVWxSRI
Fn0b+njTfk0+IPOrZwf/yr77Z9wp2SFZVTX5+swFmhw6zE/dsbUmazZbe7WrQpNPvqxRGbTW5Fsd+2t1h0qe69k64+SuJ/YNMq4duOJQJ2NJmtak3zLc0r3d
KcP92EOvz8fWZyRGcPYLfnfsy38YEmGf/iUjZaV9etmxzYn26V/TzUfbp7sfHprM+XyIfXrrg6v2c7aysU833Od2lPO2lX366l3bTnP272qfrtzWJ5/T2dg+
/ejGDpc4++jbp0cl9L/B+a6tffrr2Cg1Z5yOffrnpS9vc+o0t0/PCklqYp8+OFCnsX36fm/JzGflVwPmaVKn8Ya0r0pJxUPO2w9Wp2V7b2u8Oq2Pgss/6H38
hmpGK8mB91ekxQdq0qrpijRPZy57OseXL01zCX3RfGnaZkcub3bMahWW9m5oVinnwXaL0qJtM34PTlvYx9Gk/+HVll8vlR7q0rNf8F+pum0KvUpS17RJi+Bs
5J6T+qitZxznkrI9qcyx58Q9qXrtbTdyWhYnpP45xHdUQuok/Vq7ONfciEzVGfB5UGTqGsPQQ5y3jBem7uuVUsjZoM/C1DOdZp38v/nGPDBV1W35Gc5PPkmu
d6//b3w3s0yx8qxkQvBPWk4rU2SecQzn3DqpTOGWJ/ksmnPAmDLFohz7VZxmI8oUOlnOiZyB9mWKXqckG2z9yS42ZYpHGZITdv3ktN5lCr10SYP9P6lnUab4
96Cke9pPBnUtU4Tsk6x/7Cd9O5Up0ndJNj3J2dq4TLFzm+Ts05yBHTHyJMkGOZyrDMoU79bO0i9TzIqXrA0WxWiyqf4eRfF36uqnKJp95/HMvYohyZJvc/Yr
biRKZjruU9zLllz++w7FioWSMfrJCo8IycX6OxVp37ntzHZF9eWabJS3TbFtrSbPG2xRpC6WVBgkK0aESqae2aLoGyO5D2z1Hw4+s1nxPE6Tfcw2K6znSA7N
S1TsCJHsl7sRI5S0PrNBMTtC8m7HDYpPgZJXwLZBkr2Ntyrc/SSvG29QuPhKbu28QfFmjuSz0xsUOv6SoZ0TFU3nSrK8dYojiyX7HV+jKJkt2eD0akW4r+S3
zFWK6d/5MnuV4lug5BewfZDkP2CL7+xzIk7x21xJ/W4rFS+Vkhss1isuukvGWMUqdKdL5vaLVRyYIlm9V4zin6mSH1KXKW5Nk7y8hv+CkuONXBTLU6yMYhTv
/ByyOAvTYhQ9Z0i2OxytCP3O9elRivtKybVDoxXjnSUH2sQq2k+WXDhoqUI1SXLGsKWKqgmSC0eHKf4eK1l/dKiixTjJhftCFL0VmpyyaZFiuLPk8ZUhipgx
kq+SFip0nCVfJ/gr3MdJXpy4QHHASdJzR7Disosmj42LVJwYI+mxIEBh6yi5Y02g4utYSb1p8xWtR0smKxYqxn6n26wAhaWjZPzMQMXA73Ra7q9Ic5I8Fuyv
sHKU/Bjup2gzWrLxgHZu+XmSNyIXKtaOlhzX4IOLVYRkYLt2CquoB7ieq6J/Zb5PsOKFg6RzutpNd1qCYbZb1hy/pGy3pmNfjDzqVsfJftoXt7mjXi3u6RY7
PKxw4ZS5fpIRRnecdTI0ue7kP5PvnNCk0dUNUzzX/srsToMnG0zS5N+Hek4ZNuFXag0a6HzeSTI6t7WzTqqk73mziedm/co//Xa6NB0o6eKgctKeL/lwhtm4
68c02WbFqjHD90nGDPYdc2aTJs3XZY4+Ei7pM2/JmPVKTU6ZvHro2NuSd5ekj7S5JNlrgP6wYW6Ss1KumGz/+CvnrFo+/M2T/42u/Trbjrw61ehG3w0xvtvG
D6NcTVp4BPYOq5Ds6hEA7nEL6O38MNFjfa+VFZLmCdGDLo+U3DnBtL/bAEntIxcHtghdNSus+78Vki+WVnSuqtLk/bmqLkMeSY70nm5m950vfYw6xb6SbOVr
abb1Tx2/NFOLR5Jv9wwwvVqsScP5t03uVWiSrU43ji/R5OFAtfHzx7/SddEm42MPJXvEHjX87bkmb600MX5yW3JpaC/jaw8khy2pbnznvmTOCjK2vCNZGH3H
qKJc8q9lt41c7kraRVw2unlf0ti6htbsPMn03l46M70lDwb76KQ5aTLfR1/7wOMdc/S1Zz5+NJ9zpVJfe9ejTwt/8n2YvvaUCqY495vDQ01eXKqvvfHBnOX6
2q73VHH62vvufFijrx1TKhm0uVrNbTc12SiMqN85ybiRFRSQqskJM3KrZ0VoclNCteotV2tytPDH4wiOoQMskkWzA0jxYvNZjIhTcBe8y/JZFEtlmZDzWTak
HMjL2Gm2Hcdpdgw8xlLAFLYXbcrRohx5KXhByKXsDCuGRoV0m/HoU7fZLbFI+Rb0KnYI6RbbBbuHwu4x44uYi4WXvEL0XchyWQZ6Oofz30Wf59DnJeTl6Jcv
aObLtUthzeMJ5LACsICdR6tMdhHpPOMb2c6iD5WIA6XCmfah1/1sD85xHO1KWJpY7pzLTkGbwQ6zZBbClgvf6g9F3IaDkI8gv4fPf4Q9ED4QecyrHFYhIj6t
EDEhKvDdbWY1WTxNYKvoNxaL+7GajG8EqcmiKZzFslDY+cMqjPkgj8a981LULcT98lIR2YXf91khRZMFUg/BpWLzyhLqThG0iLriTi+MzKHpDv0SsfGBx+Tj
EfrCyQxnTsQd7ibcN3Kv+ttwR86fDWQID1opYAruq48hHadH7JXwK89jRD2B/BQtJ7AE3K8nII9nwajzB/lnug6rN+wGe8FSaDBab8dd5UD0OBD3yZshb8f9
5FrqB/ZHeYPwCbWKelEfaPugtF1Y74R1Cuq5pygdaAbg6A+pDxL32tNL+L3iT1D24Y70OOUjcd9QeWI7wQSaxG6QC3OG3hX3tSnojY9lsLC5BCtH3OFforE0
mF3FFV1KQ1gp7qZVYmMCf3J3Ha1Gw+oSrng7MfY/0FpH+BIaDHLfUn8Im4nIV4nRr8Jv0guJR8Fajt/DSkTE0kGyAC3wG+ggdRHsjpz/DjpIZuBtphbXeBHb
gaRma5Fus3XQ8LdlRWyLiNyRwtYj7ReL/vnT+iKWiJoUSFtRy2OQpEBaD/1a1KjRfi0rYyuRJ6M+BGkNmAhtAtI68ZR9HTTrYBOCufSM8S2ez9hltLoMXTiu
Qh/UrOQb7ciGheO6sWGRFAnybVg27CTu/E9RDPnCZj6LoZNiA9MpsaT4pGgRic8XCavOwltcJ8g8NscysY0pBramdIU9Z1dZHKx5FCUbto5esZe4xp6zSugD
2RLmjd4vszjU2LCNtBHcglQL3EK1WDKtFLHmkiHvol3gHqRB4B4axPbTZd476uPQ035oDtAB8DCl0hE6iDFYiu1UK8kEaQ31RlpPfaE3RQ3ftGUKmiBfiToT
1BoLm77IzfAZ+HXYmRqKTVkNRdwNTkvkprDmvrV6IjeBdUOwN3LuCcwaaSvZQLZGT1tpB9ki7aZBYiG6vYhpaQ29LfId0NqKJ6XGOKzRjzW0DZFsQR5PaghS
Kg1FOkjD0IM9WuyF1h7lIzRKbIkbhZRDTkhZYBZdpEnCn+kktB0K21S0HEqHqAMNpzRyID30Pgj9D0IvDZGGgENgwZ/CDkXtUNjr0XXhLTYYaTO4EPkNEZfi
OU2hYhxTiL89m0UfcMwSb6cV4h2ygl5hdo3BLByD+VaKeecibKcIq1minj89+ii8Fr5BaS7Iyx9Rfkn12Uvk9Zk/8bem/mL58wKqzqqDbVhbNp+msjGYmbxX
BfpzgTyFprFAMmb12TziLbinvjawDyITFkS+sHPHGabAkj+l5s/k5kIzD/I4kbujlT+4AIc7WvHF/bytL7Vj7UB9ps+8iW/09CbumXQOdWAdwN7Q+xLXeRMv
8fcevdlMshV+JWeSNVMSj8akJO7ndAYNh34m8ZL0POhBlhjfOIzQF/TGMU48i/2x1UApnr1zS/7ssJLdZNdw3BTefyPYIvweC/GLLIKchJmwScyDOOSMVVEw
Wlmy4cySeRD3rOpBPEaaJ/VgPUBDZshmUyfWSURf6oZaruMxtpqzVswL9KGGrCWkVqwxa8oCUPKhppADqAoH3x7RHLU+aM39KjZFbQCuuUyajFQOllMZyDe8
uCE9pako34NcQbdoGn2iL+QH6RNkxoLpX/F23Q92FcLSDW0fQHLDte2EKzwLV7MT+p8s/LbxmIKjUDZEmgTy5dyGaD8dPXxCmgY5GKUKSHxDhqHYNjsNeQDp
ippg5Dy+rx90PI7adLG+YzLsDPFNj6N2oK5456Mr/Ebq4pPOBr3Qgw/yxiJuYWOqLjw0GtAIpPFga6pG9cH69Du1FbGBG2IuNaMmwjNjU6pN9SDriLw21YTU
CHlDWGgLP31E7akFGeFoQfo4Ty0Ru7YWRtSAaiDviJzHUGxODLpaYn2KFmRnpmQhpGR+4AT8Ra/JJjJX4YN3AjtGk5FOkCubCY0rc0I+lI1B3TnUnEC6SWdo
KMpnaBg7S5chX6ZrNAZWt0G+jTkA/S9gL1Dim6hLiG/CLqH3yN9TbfaO+JqBv4lvgPiLnhBf4/CEXiN/TX8S9xy8AO0DxOj82FgWSnxDAvcwPZbZsHH4ez8e
sh3ycfjrzt/zH6bDZM/4Jh57xv3M2jO+7cmeFVIQmwfLQvydv0AXwNN0GrxLfHs93z6lxe7QHfA+tFqMlx/SfZCvddGCzUiM7U8x/j/pH+T/UCVYSSPYbHwz
05FGgCOgaQA2YPXAeqwOyOPe1mC6kHSFhTuby+bgk81ii5kpaw/ddHAUkgFowDqCs2CzGHlHsW3TnOmBet9jqk1H0mN9wD5sIOuPfCBs57IZkLugNBrsB/YT
W+JGMy/hDmAeSlbMEakX2It1Bx2ZEesMyQKSBWSu6cwccHhBasEaQer8fdVEa7AFEs+noL4RaybWgkxBuQnYjFUDCTIh94CFm4gGx2P2eoGPaCQromfgIyqi
KewzyH0sV2PfUPqK9I0+C2keRmsnPPcq8Etwj8Mj8f1PYT83KPjcZ+Orjev0OKuDa3L2Sr3VWXcSDKyHPb5obffiWT+j4D41mp+wOG7QOLms4NvrhnfLJfcG
EfX1uf9vRe011pLb/23UPttUMsz/VcfxZV4fX3WsZibpdNTeyLKr/Ul/o4iuAStTzOr01aTeqUVGq7rWzKlnvMg8/mhz4yvFOwVDDg0xDi5OOTkUnHrK0XhO
8YmDnF4fxxh7fGeY/w/5rblk09xuxhnmV+f46F2o0GRV1bNuEZMbHpxiPLp4YE6hsa+6em658TB18Z67xkPU6fnvjft331uga5LQ/Wj+DpO0oq8pH4xbqDec
q2v66FbD5EqTFkX1CtuY7rLw+phkeuCmZJj/DznVUvLtxULT7jcvFn4wzb8h+XRLsmnSTcm3Sd06dbwhee5SvGmCpeT7a1s6Dekl+fmqducvVyXPfavfrdnx
X1l+Palz3BXJ7usndza4Kvlq7eHOI65Ien3M6tz1O8P8f5JrjPtKRtz6ybbe4e3SOkjev1XU2bev5KGiVDPrQklLVTezpH6Sg0uXd1ENkPT6eLQLO3+2OKPL
13OSlqXtuioLJK+VZnXxt5UMKP+7q8FgSd87vc275kl6fVxk3iW3S/lPXijfb+6cI3nvboT5H0MlBz5w6tZshKTFgzvd8k9Ken1s3L3whOT1B626b/7OdhVN
u292kNz1KLF7kpPkhkcNejRIl4x+7NPjRpom4z/u6pY4QjLtiVePgAmSa56e7rF7ouSXwBs9TqVLxjxtZ3F7v+S45/MtyE1y67M1FlF7JL0+rrY457b2+U/+
+7ympdVOyQ4vci0ip0ru/1hhVbxMst7L+ZYPt0p6fZxvOc9T8urLn/zrZZjlbzMlX73MtOy9SfJ15UvL416SRZVtrD6tk5z4qpXVcB/JMa/6WX1eI/n6lbPV
1/mSf70KtboXK9nj9UKr+gskO79eZrVyuaTb61VWnqGSAa+TrOovkZzyerPV0UhJ5evtVgciJN2W/RkwqDQ15qHf2dLJuQ/9NumPXPXMT1medfKZ38d2dRPf
+n25V3Xkrd/0tkkLvH2KTCWvb/nkF/qgz4FPfvdaR+6q5k8POadATg1c8ND0QGogPdyWtDkw6kHOkdTA+PvdT6YGdrk7Pyc1sOJ2cEFqYLq6y6XUwL03oq6n
BhZd8lelBtoUvCpNDazKqihPDeyQMepBamBmquGj1MD7O92fpAbuSar+LDXQaHUDry9W6X6a/Ap94DKH56mBaYu5/NSPW1rN4q1OKHgPIRN4bztH8Z6tB/Oz
uPXnZ2zXk599uTkfSYYpH1Vqx6gDquAYnf5q78ML/pCs+dAjbdIWTb5TjDw49KAm6z2ZndnmmWTO3h4nrxppMj72/bG4u5q8mxJ8dOI9Sbss66O+ak2enNQ6
zW+cJjvfj85+1VYy7LG6YsRXTbqMz8ypqtJkzbE7yif/8V8Wn520VpN1Hl/MOd/9UTWbss7ZmjRmYfmNkjR54OXiG/1WSLo+vlXUVvdX6lfqqrIX61c6qvaH
6leOU1WC41X3QIVqHuipGgjOVTUE/VQvYDlc5RmmX7lAtS1cv3KJajAYp8qHZo0qDlyverhEvzJRNQHyJpUZuE31L9ruVk2D/oCqPOIHj6kehf9gtmp/5A/m
qlZAc0Y1AjYFqslC7h2iX3lV1QzyLVUl+lSpbi35wauqiKX6lWWqZmj7ROUBTaVqAPin6lOUfuVb1faIH3yqegrNF5X3sh+sqX4I1lIbhP6gltok4ge11RMi
OVuF/mAdtc7/sL76WwindgSnYzRvdRealuq8aK6JAwcIm9bq6Uu4/gvGaai+E/GDg9TO6N9CvWEpZ3WMxE69VJB/Y0PUo2AzVN0JYx6m5r/IMHVXcIT6AjhK
3R21LurMKE73UMluTzuVDIj7lfqVSjFmb/ULtIopfrDqB4PVmUt/MFy9F1yo1sLIl6o34XuOUUeBcepEjDNB7YRzrVdHQN6kHgR5i7pd2A9uVzcCD6lfQZ+m
3oBf6oi6F3o7oX4AzUm1IeRc9RjoC9QDwEL1CnzSInU4uEo9CJq7anXYDz5QF4IV6kn43j6oJ2E8n9W1l/xgq2LX/+FDdRV6blbcJuIHdYv59SM5oJhfXb2K
O6z5L/2Kg2FpXLyc/wolWTH/paJ4ID7juuLb6H91cUv0f634BXireGT8T9aI5PRo918+K56Cz/tPsXXcDz4tfgbL5iX6K3+yC2xMS5zw2Utuv2//g1fKl+pL
EhXffTBOk8bO6wvMa2sypSRSTSSpX5l6v7mhZM2xJ0sPndOkfqVXxSZTyeJnYc8W9JB8M270y9tfNKlfaf5n2XjJEaVVVbM2aFK/MuTtTMUPLv3LbdYPDnqX
7C/59NGBD42i/zfqVx5/x6/Dnxz5wOFZo1aa1B1/7JPFoF95llVnp5FeEg+XWhvyWeHBqgbjGwZ4ENXaSL+h5iy0d3Dz9ZXKoTkGOYP9ixu3miwfNwE1kV5T
AbvAGNryEMwF4gE8D8H8D9Iz8CK7gRuADNxSfUMfx9kJdk/4HMnAzcAJVo5yKSwustuweAIbHuCjik6yKrrNnhNfAn8DdXmsLm4/uK4Z5G/UnJXh1itLLG8/
wrKRZzFt3JI1Yuli2X02a4xRHwX58v1IeoWb3BMiuHYkqYS/r/qUA+kLZBWkL9CfEA/PTlJP5Cch9aRM4TI+kzpRlvDBNER41TgpwnNkUR5uuTMhc09dJ+g8
yIOE90R9pqjnrTqiXR5u1zuCLZG3pLO4oW8G8nACTZA3pQLcqDenc7itbwEa4LhAvyMZg3zBZ0vYnBVWBajPEx7WzkM+C8tzxG91L8L2BD7beRzvUVNAf6Om
ADLP/xY2f9Mn3Ip/po+QP4mwRp+oEOSeti5Sd+SF4hE1X8bWA+mSCPp+SSzwvEyuSFPAi6jvLpaPWUN/SSwx/SQ8pX0Si1GvwOoKvRCLVd2FfJWUoBIlJeSZ
SNfIG/SGfE2EIrlG1ykYmhcisPcLlK6LEEvXxKLA67QQ+XWKQh4F7XLIN0TgjBtiqS9f2BqPtE4EZrqJsX0SC1c/odSYdIVPFP4ApwHVFUFU6oH1qBGdQWoM
5qKGa/hC4Fykx2LJ8GPUZYtFwYZisWM2NNmQ+GPM03QKV8xb+go+Rn6TbtEWcAvGsAVyMo5bwptIEe3DUSS8ltxCfhNjuiW2GnFdifBEUiL8sxSJvIRKwVI6
gqNUeCi5TQfAUuRFaFWC47nwTvccmj1URjtRz6U9IC+V0TYcd0T4iU0iPEoZ+BypDBbPwZW0mspRewdcSXcpmpYg3QXvURg0fAPSRnC1CLRzB6lc8C7y0/g2
jEAj4YesN76HMfSIHKgvpN6gA0pjaAJVIE0EJ5KCHkL/SFhWIOcB25/SfZpLARSIM94XCwcf0mx6gPwB8rnQPQC5Z0FueQ+cCIsKUc9bP0TONzE9wEg6o+fH
SI/AR+IR4VPkYWgVKM5wH5+L+9T5C/VPRaiU2iJESmsROIUHB2mPmd+eauCvQHukSEijkReTEzUUViZo0RoztyuseyEtpaHgUPFCaDA0XcULn9aw6wh2FEFY
GBFa8dleG6mZCODRBJYysApffNwOOr6EuRpsa4vHfk2RmkDWga4p5rqOCDPOvY8ZgAb4W6CDZAxyH3o6IuyKGZIFaEH9wf5kB5qKV0t2NJ6GIU0G7ZDMILkg
r06tyAapC9iFhoM80IqNeLzJl6vPAGeQJ+hJs4g/+vWAPIvmiYA2/uQjQt34IC0CF9EyGoC0AlxBq8BVtB6chzrezgM9e0C2ocVkS77i1UcCvtm6mHNOYkn3
euFDcCDVxMi2imXROygFTKH94H46JJYl66ElX7SfILwYJSClg+l0GOSvdBK+L2BOEv5xkmgNxVIc0hqKAGMgxyAPpyAKoflIQdCHIx+InmsKj4YJSImC25Fv
Ry+J6CcW5MGI9JDHghFow1/ahkCui/HzwELa+DviRLVEro2/Gnypuq7wTWeIo414YGsu5os59aGx5EgjqR9kR/FK0xxt+ULyOTQdvTqjbhKOkeLRdAh0XmLE
XqgPgWYkqIv+ea9t0HYsNM7oyRx5KI3CqPSoG7UFtfC59CBpIdUB9VDbjd5QE/ybyh/XjcIxUDxWHMBsRG4DqR/jPkvmsYlI08BotkSEhVsiNjHxoGQToR8r
QqvZQJoM2Z/NZ3ORvMHJYmPNXMgTWBPYdEFpCOvNZjE/FgBNF2aKsjU03AeptfDbZY80EpzFpjJX2Jiyjqi1ZlYoTWVjmAlKVqwPLHg4siao7YDEw6lZsc7Q
j2R9mbkIE7cAI5wvvN75s1S2le3GsZVtEa85F0HaBHkRZD8k/sB5CzSJ4tVIIlsmtscsYxHI9dF3Z/TZl3WH3JkZsN9R4o9QxzBL1gY6A4yBe2X9HVpDZoQa
S9CSGbMpzEds0WoDm7aoN4Ql31imi3pjaHhguSmwULBBOJcLm84CWTAYzJxQY8za4RN2EJ5K24AdxGa1tiIU3VC0cBHh4HgIvinoYTjSCGiHi8fO7YQlD1M3
CGUH0EH48HNAm2VsIc4Ww1awULEUIVT4yosCo1ikWHTgg+QLRkITiBQM3mQb2Aymxne5EXIxStfYAZTUyFPZFRFW8BzbzJJB/qr5GnQHkC5BLsH/6a5DOgf5
OuSrLEe8XDglAgmewsgc2A58Vh1Qh7VnB5F6sPPslghhn4der7IidhnHLWjTUHdKhEnbCcseKO8QbXLQYx5qnCAdRsuWwuNTc7YLeXOWKbajHUZ+Bi2rMQ8c
1ZgKcjPxP8vn1IwpWQJrKsISrgW3ieCEKcg9RThLT5aEvAl7Q9XYOvGguwny0WwO244Zsp3twQxZh9I8SPshN0Gd3AbZC/pWaLFO+Erbjl9mGuR5KG0XARe3
ozxP+GyMBjfiGt0vfBRuR11blPnr91GYC9yPrKnYcMYf+E/C/OuGNBazxxHX1Sicp5/YaNaJdUXLBbhOF+Dq74N+u4uQgX0xG/grBlOx3W2I2BZqj3k3F7Nu
PuaON3rjs3EartfJ4gVER5ylG2bAeDaYeUFngHb+aNMHLbzRYhbmpR8suVe8SbDTxxn74LzzcS5eG4BZOwRtDMDOmMeLMZK++GR+mAF8K6Wj8E75O0bIPRC7
Yu7w+WiMdpPQVxtmxnqy/ugjAPOpFXT8xW447HVhvwTfTHtc6W3R+zT0b4AzuGJWWsDeEvl+WC3BNbgV1+d+nFMX8iaUDoiFEhvRMgRMRR8HxMvQA9CuwLW7
HvXtod8N7sbfhQOYPXHgCsytZHA9uBkzJll42k4WHr3bwy4RY+cvVQKEB0FdnNEI5zDGWdqjLgKzzkVs1vXBfLVjw1g8ZuJQ6GJQHo6+RmDOuaEv/spIAXkm
ruRgtI3A+dsj9QB10OMyjGYoxjMcumTY8xntIrwg/8FioRmBvngg1zz0HIq+Z2KEfF46oCZZeP1czZYyd+ijxKbjICEHo/Q/GzV8ytkH1vefLlkv9XOzG/0z
I2ud+6l+UxddtrasWc26YAVRg9u/sl3eipp1Lmqy9ZF+vwUt0OTQOBftR48lZyW4aCc/phWBnUP/V4ZtcNG+86hZqIt2QoWk9QIX7WsPEgNctOPudfVx0b59
R7LBXBft46U2M120zdSXZ7hoD7l5epqLdv2rYdM+06SUX+kaVdnKzUmTTQ5u/MOnVJNhwSu7VFVp8nTMmU7dXko2DUo0XXlXcqv/atMndzTptmCZafY9TQ72
zzN1vyOZvTjftOEDyX+9/jG9U/orw8O+mVZ/KJkaMbPTi/+whnd4p8wSTa6LetZpbYXk/llxnZUqTX6Y6Wz2R5Fk65n3zBbe0mSoMrbr4RuSFaM7dmpb+Sv3
KYb0e31BcseUeDvD/L9WTjd/8Kdkzqr15gsfSXZe83v3kO884G5oMeyq5KJ1ulbdH0nO33i0X36F5O2NKdbH/8N7G3eByu27rFc+7Om2y/rwuSPFF4evW3U9
4/7gg8MktUZ+GjQtxG2x5eiuT3+lQeTDMaZXJPMnzRr1V6Em34ePH35rkCaNM10nDliryVsBcya9Pvz/Z6t5q5zd/DUZsfPIxF6zNOnw7MS0sQckF7zaPLWe
tyZDVoZ52Fz6lRXmd9zUkZq85+c0tYftr1x+u6Eyco5kjRMNlQVjVs7gTB5pqrwztcuQXh5TFJJLC7651xytyb0Pg5Utogq6/O3+KkKTr7Zsn/F8iOT8oOEe
o4ZrslGIWnnJUZOjfB8o+4yR3LG0RPnGQXJsVLHy8X+YHlCsdHPS5MF1JcpHDpLN5xQrW4yTfL2lVHnRUdJo2VXl2VGaVMy9rTw4VjLb5Ylyvavk+snlykgX
yZD1t5VvHSSHppQrXZwkk93vKclZstmMe8qrEyS1xrxUrp4mGT7+gfKjm2SttArlxbGSXtvuKmuMltxw6JFyz1jJTVnPlbGTJA8ff648OkHSfeQL5Q6l5OT9
z5TKMZLZwz4qt86WLHeoVA6YIdnN8bXyk7tk+IlKZV1nyWelr5Vn/PYO4mx58bUyY6rk6sK3yvJpks75b5UeUyTVeW+Vpa6Sn679pTyklFxy+asyxl3yi93f
SnNfyZyh75XX5kj+a/tB+S5Qkg38oHzxnfXBG9/5Aq0cfCXTbL4qF4RIfrT5ooxZLNnI7pvymZ9kSNE35fE5ki36V/d8EK3JkSXflCa+kk5l35RvAiW3FP2r
vDNH8mT/b8qhEZK2qL0cKJk5oEo5daFkxa1qnr/N0eTh/tU8b8Rpcmuf1cp3qzU5HGNoFyM5EvwarUnn8hqekYsn9K/l+TRG8qlNTc/YtZp8XFLDs7uf5ED7
Bp4DkjW57q6Wp12E5No7Wp6KhZINj5lMv3ZFky8GNPCcmSiZU67l2TFUsuaImdPX5P7K6vfqeX6MltxxV9szNkKy7r36nqdiJNust/PcfVaTAVH/b5ZtsfO8
dUbyeMhP+u628wzIk9QN5LyVaue5Kkcy25vz2VE7T9Msyb2enFsz7TyHnPpr6k++yLPz/DMjxeUnj5+HZfrtcT/5+bKdZ7VD6x1/ctcNO8/Qfa/++Mn9KjvP
Q7ueDOGsUWrnuWlbrB3nnjI7T6ek57acceV2ng/WHrsLOb7lPTvP4zGSZtebZ87oNqc/5x8lOpm2vUZZcdY9r5M5slPcEE63rgaZx210swwydQwXjebMMumR
uW5I8pEemeV6/7hwzu04NPOQw+2UoZnb2+V6cFZtmpqpaLvJ5//mwNWLMhu0mbCI80rUhsyNrSWf3nqW/bnbzDvjspv38X3onG1sq9e9VXZO7xlPJ2dvHGph
xKkwmJZtEdr75bTs4Y5cHu6Y2mFm9tRATb56NTNb15nLus4uJwZnhek1a++dHe0d+cY7+6Mbl3+w7p+B2bnKle04oxe55mkdl5zs65r35Ji7p2tezaMVh1zz
Zh8+PoXT7KRrXruDs8dxVuW55hnuSxrBOaDQNW/lLmc7zns3XPOmbDvdj/NciWve7o0qS84nd13zfBOOdeXs8sg1ryh2tilnwjPXvNtLaxly1ql0zVsXEvPa
Na9lYN0/XfMCvCWvRA3M1zquSdPVw/J3ZGzd5Jjvfex6M5OHGUslz9+a86R8tWSdlPH5nulDDrvkx6R1y1Tk3zww9uKc/GO7toU9ebNi9680e1XtXpj7r6yq
Ovo6do/km6b/lv8+RPLzZLcXwU1Uqs8PDxtpcta33Kf3dDRJVFVVmtqkRst/iZJw/3gTaTPoQGNoHDnSHDKkFmIRXwvqgXw0mVFPyDzgMo/xMJqMxTJBYyRT
sYivmXhmSCLEbyfQEiX+tIk/W6xDdak+OSNvirwaaqypAfowR6+jRdjd5mLReXMk3rYTdQO7iT4sqS/IFxZ3JQsRrLmzeMpphVYm1A+5iVgA3Eg8TzQhG+hM
ULbBp/DF5zDAGOdSa4yCu7RqC/JljkrIrURQ6lbiM5KIeDBUPL/UoQHQu6LshM9sD3ksSg74XvzAyfiGHGgk8tboZSysRtFwtOFPWHkg4KHUkmzFFoDB6MdB
eAB2QBpJQ2gYjRCOFYbA0hXteBDscRgT98jdRiyS9SJ/mgdprFguu1AEPV8EjSvuLK2RJoAThL9lHjA+lngeS46404qlSbgX5JskdgpnMdyz/Vgkvvhuu/A2
n8n4gvfTuA8dDf123P0mswvQ800lWSwbd2zWbAbuU2cg90TqCs7Eve9sSHMF+TMzHpXHm3Ev4ouJx1+wxh2tNfLZIkx3O6pFeqgLx9j5c7UM9MEd6cxmR5F7
oJSGu8cDuHvkvvIPggdRmsz2sT3QHRDxgmbDcjbOdBQW3PkOd7fD+8iFvA82uWCuiLBwABpvjGc1M0XqzZJwp23MOuEudC3ubtexDtCvR81c4SzIG1IGbIxx
374N6XfcEXdkdXDd12VNcVRnG1hNpOqwWY+ekoQddwV0VDgR4pt2VmOOZCDlQlqPPAlpPcavwJgmY0zc1/we8TvwrQ97RBQEHgOBR5PKFdGkclkhWIjvn28G
ymbVRFSNOjQJeV2aAZm7DamB5AHWEZ6d6yJNwUxTiAX7E8WCfe60pS60U0WEGh5efJqo57F16kLLe5oh+vDAHJhAv9N0aN3FEmx36Nyh9aCO5C2iy4Rw/9Vs
lNjiM4pZQXICndg4cBxzBp1xB2+FayRbLMbMEbGL8tl4yNmilCNKBWwiq05a1J6qC3/O/Nk1D+8exJ/R407fCmkq6ClcZPBg2zVoKu7urZCUIgaSki0Ty2yX
0Sw2B5zDvEDu/XsZ/QZ7Hl7ckzv24A6QyIfZC/oiH48R7ML5z4noSnuFg7D9ONt4aPm4ClgKmCLqz4n6vew8eB5W2fgtuBOoQhEf4gxs8zE3zoAFojV/yleA
xFufQYtzSHvRd6qI53QIo56KXlKRH8bYZ7F04cLpGMbuDi2vPyRqDqNmP9qmIp0BU0HuZIo/9/Nix/Ep57ET+GQ+7CQ+0xxY8z6OocaXbcVntAdtcWwSi4s3
CYdNiYwvyU9kRmh7XLQ+gdZ+7BS7jFZX0II/a0zHcUa43DojPN2fgdUZ1HJ3V1dg30HECAgXMQJqspYsAekLJTC+mD2M/UtVYBXVYqtYLcbAbZg/3K1eUzFr
EsAvsEiAzSoWBovFsPlE/Bn3R1qM8kf6hPwTPYCuHOkBlVMFBbIKegw+pmsUwK7RDfAGnaVgsWXjJvoLQz8bkN9k/J1yMNpyZ1mPYRcIy2AWwApoEQuG1WIW
B7tV3Oc5LOJEBLubwrlWHFIAGAcWIQWDcWIrUwFdQmv+/nURu0KnKJTx+F2hLI8O0hJ2kI6BV1BeBM0SFsqOUSRbwjJoDy1l+ymK7RXvO6NZGh0B0ymbYtgB
SJHsCC1n0Ww5O0HLcL5FONsitC9CWgIugUWR2KJYJKyKkJaBtXFl69MSmk9LaZaIlxAJjSd0syiQXpI/e4N+c8TqgPPo+TydBk+TiiKYii6CF+kehbN7VAye
RnkZNOEsgpVRCLtFZfSUFrJiuoXSWwpipSiXQvOW3qD0Bv0HwXIhC4FNCAtHfRBbiCtrjXAKtoY1xLGGNWdmLF648FvJGqMUj3JtFivcz81nH6gV5HcY7Sv0
9wGaV9QYlrVhuUa0i0fJVrzh6C7eaRghrUH5ClOBKuE0TQVdIrgGreezFegvlvGeVjB/9LQSZ1iJflSgCnIQtBthtfF7rkKaD/0KJN6HSjzL3IhvmL8z2YgU
LkobmRqfdSHycPGsNUhsRMnDdVPGzrLr7Cq7BJ4Vm97uYHw3WAkrZtdYKUpFYstnMeT+LJ74U+CeLJRs2CragX+Xd1B7NgDl1ZDb41/NbmKBvB7bSfXEeyA9
8U6oHasH6oEGyOsxQ+Q7qRmknVSDNUP7CPTAV7rsBHeSDtJXwRfId9Jm5F+Q/qVvII8P94K0kKoxzn+Q92LRIgpItNgSFE0xtIwGs2SkgeBAZsf4+//l0Nqx
HpB55KRk6ovfZDnxd0TLyZI1ArluOTViLdhzasG6gLz0nJ5TF9YAeQPG39UlQrtGvJfk7yi3YEybMYrN9FnwIfLNtAn5anyuBEh3IW8ScWQ2icgym+g68uvI
b+LYRPlIm8F88ByOzXRZvDHlKziS6CqOJMqEZi3tA/ehlCSiYiXRIeRJ0BwSm0MP4XxRtI5SUcoFucuyXDoKcvdQu8HdxDdn7BbrZXaLFSi7KQvpPhWKXI1j
N+TdtBW6Bfgeo+gObaRnKG0UKx02UhHkrWKtQhEYBZt1qN9Kt8GNyP+CtJUq6U8hb0W+DjbbKIXW03bSZq1ZIjVh2mBr9h7fZBu2gjbAfiu9FvEHt4LcbRrf
pLIc33wTWP4fJ/5LlA==
"""

class MannequinBody extends MeshInstance3D:
	# The dummy-style character from the sketch, made of simple shapes: dome
	# head, block torso, upper arm / elbow / forearm, thigh / knee / shin, with
	# small gaps between the pieces. Feet at y=0, top of the head at ~1.8.
	# Six colorable parts; every piece of a part uses that part's material.
	# (This node is the root and has no mesh of its own.)
	const GROUPS: Array = ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]
	const ARM_TILT: float = 0.95 # radians out from the sides (the A-pose in the sketch)
	var parts: Array = []
	var part_group: Dictionary = {} # piece -> part name
	var group_mats: Dictionary = {} # part name -> material
	var pickable: bool = false # add click shapes (color screen preview)
	var model: String = "mannequin" # or "dummy" (the crash test dummy, unlocked at 500 ELO)
	var arm_tilt: float = ARM_TILT # how far the arms hang out when standing
	var dark_of: Dictionary = {} # dummy: part -> darker shade (thighs / upper arms)
	var extra_mats: Array = []
	var hip_l: Node3D = null
	var hip_r: Node3D = null
	var knee_l: Node3D = null
	var knee_r: Node3D = null
	var shoulder_l: Node3D = null
	var shoulder_r: Node3D = null
	var elbow_l: Node3D = null
	var elbow_r: Node3D = null

	func build(mats: Dictionary, make_pickable: bool = false, model_name: String = "mannequin") -> void:
		group_mats = mats
		pickable = make_pickable
		if model_name == "dummy":
			_build_dummy()
			return
		var torso = BoxMesh.new()
		torso.size = Vector3(0.52, 0.52, 0.28)
		var torso_shape = BoxShape3D.new()
		torso_shape.size = torso.size
		_piece(torso, self, Vector3(0, 1.22, 0), "torso", torso_shape)
		var neck = CylinderMesh.new()
		neck.top_radius = 0.06
		neck.bottom_radius = 0.075
		neck.height = 0.08
		var neck_shape = CylinderShape3D.new()
		neck_shape.radius = 0.075
		neck_shape.height = 0.08
		_piece(neck, self, Vector3(0, 1.51, 0), "torso", neck_shape)
		_piece(_sphere(0.15, 0.27), self, Vector3(0, 1.665, 0), "head", _sphere_shape(0.15))

		for side in [-1, 1]:
			var grp = "arm_l" if side < 0 else "arm_r"
			var sh = Node3D.new()
			sh.position = Vector3(0.34 * side, 1.42, 0)
			sh.rotation = Vector3(0, 0, arm_tilt * side)
			add_child(sh)
			_piece(_capsule(0.068, 0.3), sh, Vector3(0, -0.17, 0), grp, _capsule_shape(0.068, 0.3))
			var el = Node3D.new() # the elbow bends the forearm
			el.position = Vector3(0, -0.365, 0)
			sh.add_child(el)
			_piece(_sphere(0.055, 0.11), el, Vector3.ZERO, grp, _sphere_shape(0.055))
			_piece(_capsule(0.072, 0.3), el, Vector3(0, -0.195, 0), grp, _capsule_shape(0.072, 0.3))
			if side < 0:
				shoulder_l = sh
				elbow_l = el
			else:
				shoulder_r = sh
				elbow_r = el

		for side in [-1, 1]:
			var grp2 = "leg_l" if side < 0 else "leg_r"
			var hip = Node3D.new()
			hip.position = Vector3(0.13 * side, 0.95, 0)
			add_child(hip)
			_piece(_capsule(0.095, 0.4), hip, Vector3(0, -0.2, 0), grp2, _capsule_shape(0.095, 0.4))
			var knee = Node3D.new()
			knee.position = Vector3(0, -0.47, 0)
			hip.add_child(knee)
			_piece(_sphere(0.07, 0.13), knee, Vector3.ZERO, grp2, _sphere_shape(0.07))
			_piece(_capsule(0.092, 0.42), knee, Vector3(0, -0.27, 0), grp2, _capsule_shape(0.092, 0.42))
			if side < 0:
				hip_l = hip
				knee_l = knee
			else:
				hip_r = hip
				knee_r = knee

	func _piece(mesh: Mesh, parent: Node3D, pos: Vector3, grp: String, shape: Shape3D) -> MeshInstance3D:
		var mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = pos
		mi.material_override = group_mats.get(grp, null)
		parent.add_child(mi)
		parts.append(mi)
		part_group[mi] = grp
		if pickable:
			var sb = StaticBody3D.new()
			sb.set_meta("part", grp)
			var cs = CollisionShape3D.new()
			cs.shape = shape
			sb.add_child(cs)
			mi.add_child(sb)
		return mi

	func _capsule(r: float, h: float) -> CapsuleMesh:
		var m = CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 16
		m.rings = 4
		return m

	func _sphere(r: float, h: float) -> SphereMesh:
		var m = SphereMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 16
		m.rings = 8
		return m

	func _capsule_shape(r: float, h: float) -> CapsuleShape3D:
		var c = CapsuleShape3D.new()
		c.radius = r
		c.height = h
		return c

	func _sphere_shape(r: float) -> SphereShape3D:
		var c = SphereShape3D.new()
		c.radius = r
		return c

	func materials() -> Array:
		var out: Array = []
		for g in group_mats:
			if group_mats[g] and not out.has(group_mats[g]):
				out.append(group_mats[g])
		for m in extra_mats:
			if not out.has(m):
				out.append(m)
		return out

	# ---- the crash test dummy (from crash_dummy_all_6_pieces.stl) ----
	# Head, torso, two arms and two legs; the arms and legs are cut at the
	# elbow / knee so they can bend. Thighs and upper arms are a darker shade
	# of their part's color, like a real crash test dummy.
	const DUMMY_SHOULDER: Vector3 = Vector3(0.255, 1.232, 0)
	const DUMMY_HIP: Vector3 = Vector3(0.11, 0.843, 0)
	const DUMMY_ELBOW_Y: Array = [-0.2926, -0.2882] # left, right
	const DUMMY_KNEE_Y: float = -0.3503

	func _build_dummy() -> void:
		model = "dummy"
		arm_tilt = 0.3
		var meshes = dummy_meshes()
		_mesh_piece(meshes["torso"], self, "torso", false)
		_mesh_piece(meshes["head"], self, "head", false)
		for side in [-1, 1]:
			var s = "l" if side < 0 else "r"
			var sh = Node3D.new()
			sh.position = Vector3(DUMMY_SHOULDER.x * side, DUMMY_SHOULDER.y, 0)
			sh.rotation = Vector3(0, 0, arm_tilt * side)
			add_child(sh)
			_mesh_piece(meshes["upperarm_" + s], sh, "arm_" + s, true)
			var el = Node3D.new()
			el.position = Vector3(0, DUMMY_ELBOW_Y[0 if side < 0 else 1], 0)
			sh.add_child(el)
			_mesh_piece(meshes["forearm_" + s], el, "arm_" + s, false)
			var hip = Node3D.new()
			hip.position = Vector3(DUMMY_HIP.x * side, DUMMY_HIP.y, 0)
			add_child(hip)
			_mesh_piece(meshes["thigh_" + s], hip, "leg_" + s, true)
			var knee = Node3D.new()
			knee.position = Vector3(0, DUMMY_KNEE_Y, 0)
			hip.add_child(knee)
			_mesh_piece(meshes["shin_" + s], knee, "leg_" + s, false)
			if side < 0:
				shoulder_l = sh
				elbow_l = el
				hip_l = hip
				knee_l = knee
			else:
				shoulder_r = sh
				elbow_r = el
				hip_r = hip
				knee_r = knee

	func _mesh_piece(mesh: Mesh, parent: Node3D, grp: String, dark: bool) -> MeshInstance3D:
		var mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _dark_mat(grp) if dark else group_mats.get(grp, null)
		parent.add_child(mi)
		parts.append(mi)
		part_group[mi] = grp
		if pickable:
			var sb = StaticBody3D.new()
			sb.set_meta("part", grp)
			var cs = CollisionShape3D.new()
			cs.shape = mesh.create_trimesh_shape()
			sb.add_child(cs)
			mi.add_child(sb)
		return mi

	func _dark_mat(grp: String) -> StandardMaterial3D:
		if not dark_of.has(grp):
			var m = StandardMaterial3D.new()
			var base: StandardMaterial3D = group_mats.get(grp, null)
			m.roughness = base.roughness if base else 0.55
			dark_of[grp] = m
			extra_mats.append(m)
		refresh_dark()
		return dark_of[grp]

	# Keeps the darker shades in step with their part's color.
	func refresh_dark() -> void:
		for grp in dark_of:
			var base: StandardMaterial3D = group_mats.get(grp, null)
			if base:
				var c = base.albedo_color.darkened(0.62)
				c.a = base.albedo_color.a
				dark_of[grp].albedo_color = c
				dark_of[grp].transparency = base.transparency

	static var _dummy_cache: Dictionary = {}

	# The dummy's ten pieces, decoded once from DUMMY_MESH_DATA.
	static func dummy_meshes() -> Dictionary:
		if not _dummy_cache.is_empty():
			return _dummy_cache
		var raw = Marshalls.base64_to_raw(DUMMY_MESH_DATA.replace("\n", "").replace("\t", "").replace(" ", ""))
		var size = raw.decode_u32(0)
		var data = raw.slice(4).decompress(size, FileAccess.COMPRESSION_DEFLATE)
		var off = 0
		var count = data.decode_u16(off)
		off += 2
		for _i in range(count):
			var nlen = data[off]
			off += 1
			var pname = data.slice(off, off + nlen).get_string_from_ascii()
			off += nlen
			var nv = data.decode_u16(off)
			var nt = data.decode_u16(off + 2)
			off += 4
			var mn = Vector3(data.decode_float(off), data.decode_float(off + 4), data.decode_float(off + 8))
			var sz = Vector3(data.decode_float(off + 12), data.decode_float(off + 16), data.decode_float(off + 20))
			off += 24
			var st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var k = sz / 65535.0
			for _v in range(nv):
				st.add_vertex(mn + Vector3(data.decode_u16(off) * k.x, data.decode_u16(off + 2) * k.y, data.decode_u16(off + 4) * k.z))
				off += 6
			for _t in range(nt * 3):
				st.add_index(data.decode_u16(off))
				off += 2
			st.generate_normals()
			_dummy_cache[pname] = st.commit()
		return _dummy_cache

	# --- Huss Royale gear: a sword in the right fist, a shield on the left forearm ---
	static func _gear_mat(c: Color, metal: float = 0.0, rough: float = 0.6) -> StandardMaterial3D:
		var m = StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metal
		m.roughness = rough
		return m

	static func _gear_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = pos
		mi.material_override = mat
		parent.add_child(mi)

	# Grip at the origin, blade running down -Y (in line with the forearm).
	static func make_sword() -> Node3D:
		var root = Node3D.new()
		root.name = "Sword"
		var grip = MeshInstance3D.new()
		var gm = CylinderMesh.new()
		gm.top_radius = 0.026
		gm.bottom_radius = 0.026
		gm.height = 0.15
		grip.mesh = gm
		grip.material_override = _gear_mat(Color(0.35, 0.2, 0.1))
		root.add_child(grip)
		var pommel = MeshInstance3D.new()
		var pm = SphereMesh.new()
		pm.radius = 0.038
		pm.height = 0.076
		pommel.mesh = pm
		pommel.position = Vector3(0, 0.085, 0)
		pommel.material_override = _gear_mat(Color(0.85, 0.65, 0.2), 0.7, 0.35)
		root.add_child(pommel)
		_gear_box(root, Vector3(0.22, 0.04, 0.06), Vector3(0, -0.09, 0), _gear_mat(Color(0.85, 0.65, 0.2), 0.7, 0.35))
		_gear_box(root, Vector3(0.065, 0.66, 0.016), Vector3(0, -0.44, 0), _gear_mat(Color(0.82, 0.85, 0.9), 0.9, 0.22))
		var tip = MeshInstance3D.new()
		var tm = PrismMesh.new()
		tm.size = Vector3(0.065, 0.1, 0.016)
		tip.mesh = tm
		tip.rotation_degrees = Vector3(0, 0, 180)
		tip.position = Vector3(0, -0.82, 0)
		tip.material_override = _gear_mat(Color(0.82, 0.85, 0.9), 0.9, 0.22)
		root.add_child(tip)
		return root

	# A round shield; its face points along +Y before it's placed.
	static func make_shield() -> Node3D:
		var root = Node3D.new()
		root.name = "Shield"
		var face = MeshInstance3D.new()
		var fm = CylinderMesh.new()
		fm.top_radius = 0.27
		fm.bottom_radius = 0.27
		fm.height = 0.045
		face.mesh = fm
		face.material_override = _gear_mat(Color(0.2, 0.38, 0.75))
		root.add_child(face)
		var rim = MeshInstance3D.new()
		var rm = TorusMesh.new()
		rm.inner_radius = 0.255
		rm.outer_radius = 0.3
		rim.mesh = rm
		rim.material_override = _gear_mat(Color(0.65, 0.65, 0.7), 0.8, 0.3)
		root.add_child(rim)
		var boss = MeshInstance3D.new()
		var bm2 = SphereMesh.new()
		bm2.radius = 0.07
		bm2.height = 0.07
		boss.mesh = bm2
		boss.position = Vector3(0, 0.03, 0)
		boss.material_override = _gear_mat(Color(0.85, 0.65, 0.2), 0.7, 0.35)
		root.add_child(boss)
		return root


	# --- More Royale gear. Same layout as the sword: the grip at the origin,
	# pointing down -Y (along the forearm); "up" on guns is -Z. ---
	static func _gear_cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
		var mi = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bot
		cm.height = h
		cm.radial_segments = 14
		cm.rings = 1
		mi.mesh = cm
		mi.position = pos
		mi.rotation_degrees = rot_deg
		mi.material_override = mat
		parent.add_child(mi)
		return mi

	static func _glow_mat(c: Color, energy: float = 2.0) -> StandardMaterial3D:
		var m = StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		return m

	static func make_gold_sword() -> Node3D:
		var root = make_sword()
		root.name = "GoldSword"
		var gold = _gear_mat(Color(1.0, 0.78, 0.25), 0.9, 0.25)
		for n in root.get_children():
			if n is MeshInstance3D and n.position.y < -0.2:
				n.material_override = gold # golden blade
		_gear_box(root, Vector3(0.05, 0.05, 0.065), Vector3(0, -0.09, 0), _glow_mat(Color(0.2, 0.9, 0.8), 1.2)) # a turquoise gem
		return root

	static func make_machete() -> Node3D:
		var root = Node3D.new()
		root.name = "Machete"
		_gear_box(root, Vector3(0.045, 0.17, 0.035), Vector3.ZERO, _gear_mat(Color(0.14, 0.12, 0.1)))
		_gear_box(root, Vector3(0.085, 0.02, 0.045), Vector3(0, -0.095, 0), _gear_mat(Color(0.3, 0.3, 0.3), 0.6, 0.5))
		var blade = _gear_mat(Color(0.62, 0.63, 0.6), 0.75, 0.45)
		_gear_box(root, Vector3(0.095, 0.56, 0.012), Vector3(0.015, -0.38, 0), blade)
		_gear_box(root, Vector3(0.014, 0.56, 0.016), Vector3(-0.034, -0.38, 0), _gear_mat(Color(0.35, 0.3, 0.26), 0.5, 0.6)) # dark spine
		var tip = MeshInstance3D.new()
		var tm = PrismMesh.new()
		tm.size = Vector3(0.095, 0.13, 0.012)
		tm.left_to_right = 1.0
		tip.mesh = tm
		tip.rotation_degrees = Vector3(0, 0, 180)
		tip.position = Vector3(0.015, -0.725, 0)
		tip.material_override = blade
		root.add_child(tip)
		return root

	static func make_plasma() -> Node3D:
		var root = Node3D.new()
		root.name = "PlasmaSword"
		var metal = _gear_mat(Color(0.25, 0.26, 0.3), 0.85, 0.3)
		_gear_cyl(root, 0.032, 0.032, 0.22, Vector3.ZERO, Vector3.ZERO, metal)
		_gear_cyl(root, 0.045, 0.04, 0.04, Vector3(0, -0.12, 0), Vector3.ZERO, _gear_mat(Color(0.7, 0.72, 0.78), 0.9, 0.2))
		var cyan = Color(0.3, 0.9, 1.0)
		var bm = _glow_mat(cyan, 1.5)
		bm.albedo_color = Color(cyan.r, cyan.g, cyan.b, 0.85)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_gear_cyl(root, 0.03, 0.04, 1.15, Vector3(0, -0.71, 0), Vector3.ZERO, bm)
		_gear_cyl(root, 0.012, 0.016, 1.13, Vector3(0, -0.71, 0), Vector3.ZERO, _glow_mat(Color(0.7, 0.97, 1.0), 1.2))
		var light = OmniLight3D.new()
		light.light_color = cyan
		light.light_energy = 0.9
		light.omni_range = 2.6
		light.position = Vector3(0, -0.7, 0)
		root.add_child(light)
		return root

	# Bow: limbs along +-Z (up and down when aimed), the string behind (+Y).
	static func make_bow(wood: Color = Color(0.55, 0.32, 0.15)) -> Node3D:
		var root = Node3D.new()
		root.name = "Bow"
		var wm = _gear_mat(wood, 0.1, 0.55)
		var pts: Array = []
		for i in range(11):
			var z = lerp(-0.62, 0.62, float(i) / 10.0)
			pts.append(Vector2(0.14 * pow(z / 0.62, 2.0), z)) # (y, z): the tips curve back
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg = MeshInstance3D.new()
			var bm = BoxMesh.new()
			var thick = 0.034 - 0.012 * abs((a.y + b.y) * 0.5) / 0.62
			bm.size = Vector3(0.03, thick, (b - a).length() + 0.01)
			seg.mesh = bm
			seg.position = Vector3(0, (a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
			seg.rotation = Vector3(-atan2(b.x - a.x, b.y - a.y), 0, 0)
			seg.material_override = wm
			root.add_child(seg)
		_gear_box(root, Vector3(0.042, 0.05, 0.15), Vector3.ZERO, _gear_mat(Color(0.25, 0.15, 0.08))) # leather grip
		_gear_cyl(root, 0.004, 0.004, 1.24, Vector3(0, 0.145, 0), Vector3(90, 0, 0), _gear_mat(Color(0.92, 0.9, 0.82)))
		# an arrow on the string, pointing forward
		var arrow = Node3D.new()
		arrow.name = "Arrow"
		root.add_child(arrow)
		_gear_cyl(arrow, 0.007, 0.007, 0.72, Vector3(0, -0.2, 0.025), Vector3.ZERO, _gear_mat(Color(0.6, 0.45, 0.25)))
		var head = MeshInstance3D.new()
		var hm = CylinderMesh.new()
		hm.top_radius = 0.0
		hm.bottom_radius = 0.022
		hm.height = 0.07
		head.mesh = hm
		head.rotation_degrees = Vector3(180, 0, 0)
		head.position = Vector3(0, -0.59, 0.025)
		head.material_override = _gear_mat(Color(0.7, 0.72, 0.75), 0.8, 0.3)
		arrow.add_child(head)
		return root

	static func make_sun_bow() -> Node3D:
		var root = make_bow(Color(1.0, 0.75, 0.22))
		root.name = "SunBow"
		for n in root.get_children():
			if n is MeshInstance3D and n.mesh is BoxMesh and n.position.y > 0.02:
				n.material_override = _glow_mat(Color(1.0, 0.7, 0.2), 0.8) # glowing tips
		return root

	static func make_rifle() -> Node3D:
		var root = Node3D.new()
		root.name = "Rifle"
		var wood = _gear_mat(Color(0.48, 0.28, 0.13), 0.05, 0.6)
		var metal = _gear_mat(Color(0.16, 0.16, 0.17), 0.85, 0.35)
		_gear_box(root, Vector3(0.05, 0.3, 0.1), Vector3(0, 0.24, 0.025), wood) # stock
		_gear_box(root, Vector3(0.04, 0.09, 0.07), Vector3(0, 0.03, 0.04), wood) # grip
		_gear_box(root, Vector3(0.055, 0.26, 0.065), Vector3(0, -0.07, -0.015), metal) # receiver
		_gear_box(root, Vector3(0.05, 0.32, 0.045), Vector3(0, -0.34, 0.005), wood) # forestock
		_gear_cyl(root, 0.016, 0.016, 0.62, Vector3(0, -0.5, -0.03), Vector3.ZERO, metal) # barrel
		_gear_cyl(root, 0.027, 0.027, 0.26, Vector3(0, -0.1, -0.085), Vector3.ZERO, _gear_mat(Color(0.08, 0.08, 0.09), 0.6, 0.3)) # scope
		_gear_cyl(root, 0.021, 0.021, 0.01, Vector3(0, -0.235, -0.085), Vector3.ZERO, _glow_mat(Color(0.3, 0.6, 0.9), 0.4))
		return root

	static func make_raygun() -> Node3D:
		var root = Node3D.new()
		root.name = "Raygun"
		var silver = _gear_mat(Color(0.8, 0.82, 0.86), 0.9, 0.2)
		var red = _gear_mat(Color(0.75, 0.12, 0.1), 0.3, 0.4)
		_gear_box(root, Vector3(0.04, 0.07, 0.12), Vector3(0, 0.02, 0.06), red) # grip
		_gear_cyl(root, 0.05, 0.045, 0.2, Vector3(0, -0.08, -0.02), Vector3.ZERO, silver)
		for i in range(3):
			var ring = MeshInstance3D.new()
			var rm = TorusMesh.new()
			rm.inner_radius = 0.045
			rm.outer_radius = 0.07 - 0.008 * i
			ring.mesh = rm
			ring.position = Vector3(0, -0.03 - 0.065 * i, -0.02)
			ring.material_override = _glow_mat(Color(0.35, 0.7, 1.0), 1.4) if i == 1 else red
			root.add_child(ring)
		_gear_cyl(root, 0.018, 0.026, 0.1, Vector3(0, -0.23, -0.02), Vector3.ZERO, silver)
		var tip = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.024
		sm.height = 0.048
		tip.mesh = sm
		tip.position = Vector3(0, -0.29, -0.02)
		tip.material_override = _glow_mat(Color(0.35, 0.75, 1.0), 3.0)
		root.add_child(tip)
		_gear_box(root, Vector3(0.012, 0.08, 0.06), Vector3(0, -0.02, -0.075), red) # fin
		return root

	# Ballistic shield: like the round shield, its face points along +Y.
	static func make_ballistic() -> Node3D:
		var root = Node3D.new()
		root.name = "Shield"
		_gear_box(root, Vector3(0.5, 0.045, 0.78), Vector3.ZERO, _gear_mat(Color(0.2, 0.22, 0.26), 0.4, 0.5))
		var glass = StandardMaterial3D.new()
		glass.albedo_color = Color(0.6, 0.8, 0.95, 0.55)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.metallic = 0.3
		glass.roughness = 0.1
		_gear_box(root, Vector3(0.3, 0.05, 0.1), Vector3(0, 0.002, 0.24), glass) # view port
		_gear_box(root, Vector3(0.5, 0.048, 0.05), Vector3(0, 0.002, -0.12), _gear_mat(Color(0.9, 0.9, 0.85)))
		return root

	# Gas mask: worn on the face (front = -Z), centered on the head.
	static func make_gasmask() -> Node3D:
		var root = Node3D.new()
		root.name = "GasMask"
		var rubber = _gear_mat(Color(0.14, 0.15, 0.14), 0.0, 0.8)
		var face = MeshInstance3D.new()
		var fm = SphereMesh.new()
		fm.radius = 0.12
		fm.height = 0.2
		face.mesh = fm
		face.scale = Vector3(1.05, 1.0, 0.75)
		face.position = Vector3(0, -0.035, -0.07)
		face.material_override = rubber
		root.add_child(face)
		var lens = _glow_mat(Color(0.45, 0.9, 0.4), 0.5)
		for sx in [-1.0, 1.0]:
			_gear_cyl(root, 0.035, 0.035, 0.03, Vector3(0.048 * sx, 0.02, -0.155), Vector3(90, 0, 0), lens)
		_gear_cyl(root, 0.045, 0.04, 0.08, Vector3(0, -0.095, -0.17), Vector3(70, 0, 0), _gear_mat(Color(0.35, 0.4, 0.25), 0.3, 0.6)) # filter
		var strap = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = 0.135
		tm.outer_radius = 0.155
		strap.mesh = tm
		strap.rotation_degrees = Vector3(90, 0, 0)
		strap.position = Vector3(0, 0.01, 0)
		strap.scale = Vector3(1.0, 1.0, 0.25)
		strap.material_override = rubber
		root.add_child(strap)
		return root

	# The Genie's lamp (golden, with a wisp of blue smoke).
	static func make_lamp() -> Node3D:
		var root = Node3D.new()
		root.name = "Lamp"
		var gold = _gear_mat(Color(1.0, 0.76, 0.22), 0.95, 0.2)
		var body = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.18
		sm.height = 0.36
		body.mesh = sm
		body.scale = Vector3(1.0, 0.55, 0.75)
		body.material_override = gold
		root.add_child(body)
		_gear_cyl(root, 0.018, 0.05, 0.26, Vector3(0.22, 0.05, 0), Vector3(0, 0, -62), gold) # spout
		var handle = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = 0.05
		tm.outer_radius = 0.075
		handle.mesh = tm
		handle.rotation_degrees = Vector3(90, 0, 0)
		handle.position = Vector3(-0.2, 0.04, 0)
		handle.material_override = gold
		root.add_child(handle)
		_gear_cyl(root, 0.0, 0.06, 0.08, Vector3(0, 0.12, 0), Vector3.ZERO, gold) # lid
		_gear_cyl(root, 0.08, 0.06, 0.05, Vector3(0, -0.11, 0), Vector3.ZERO, gold) # foot
		var smoke = _glow_mat(Color(0.4, 0.8, 1.0), 1.5)
		smoke.albedo_color.a = 0.6
		smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for i in range(4):
			var puff = MeshInstance3D.new()
			var pm = SphereMesh.new()
			pm.radius = 0.035 + 0.012 * i
			pm.height = pm.radius * 2.0
			puff.mesh = pm
			puff.position = Vector3(0.33 + 0.03 * i, 0.16 + 0.09 * i, 0.02 * sin(i))
			puff.material_override = smoke
			root.add_child(puff)
		return root

	static func make_blackhole_orb() -> Node3D:
		var root = Node3D.new()
		root.name = "BlackHoleOrb"
		var core = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		core.mesh = sm
		var black = StandardMaterial3D.new()
		black.albedo_color = Color(0, 0, 0)
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core.material_override = black
		root.add_child(core)
		var ring = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = 0.26
		tm.outer_radius = 0.4
		ring.mesh = tm
		ring.rotation_degrees = Vector3(70, 0, 15)
		ring.scale = Vector3(1, 0.15, 1)
		ring.material_override = _glow_mat(Color(0.85, 0.45, 1.0), 2.5)
		root.add_child(ring)
		return root

	static func make_gear(type: String) -> Node3D:
		match type:
			"sword":
				return make_sword()
			"gold_sword":
				return make_gold_sword()
			"machete":
				return make_machete()
			"plasma":
				return make_plasma()
			"shield":
				return make_shield()
			"ballistic":
				return make_ballistic()
			"bow":
				return make_bow()
			"sun_bow":
				return make_sun_bow()
			"rifle":
				return make_rifle()
			"raygun":
				return make_raygun()
			"gasmask":
				return make_gasmask()
			"genie":
				return make_lamp()
			"blackhole":
				return make_blackhole_orb()
		return make_sword()

	# What the body is carrying. The right hand holds the melee weapon, or the
	# gun / bow while you're shooting (mode "ranged"); the shield is on the
	# left forearm; the gas mask on the face.
	var held_right: String = ""
	var held_shield: String = ""
	var wearing_mask: bool = false
	var holding_ranged: bool = false

	func set_loadout(melee: String, shield: String, ranged: String, mask: bool, mode: String) -> void:
		var right = melee
		if ranged != "" and (mode == "ranged" or melee == ""):
			right = ranged
		held_right = right
		held_shield = shield
		wearing_mask = mask
		holding_ranged = right != "" and right == ranged
		holding_sword = right != "" and not holding_ranged
		holding_shield = shield != ""
		if not elbow_r:
			return
		_swap_item(elbow_r, "Held", right, Vector3(0, -0.39 if model == "dummy" else -0.37, 0), Vector3.ZERO)
		_swap_item(elbow_l, "Shield", shield, Vector3(0.07 if model == "dummy" else -0.1, -0.2, 0), Vector3(0, 0, 90))
		_swap_item(self, "GasMask", "gasmask" if mask else "", head_center(), Vector3.ZERO)
		set_first_person(first_person)

	func _swap_item(parent: Node3D, nname: String, type: String, pos: Vector3, rot_deg: Vector3) -> void:
		var old = parent.get_node_or_null(nname)
		if old and String(old.get_meta("type", "")) == type:
			return
		if old:
			parent.remove_child(old)
			old.queue_free()
		if type == "":
			return
		var n = make_gear(type)
		n.name = nname
		n.set_meta("type", type)
		n.position = pos
		n.rotation_degrees = rot_deg
		parent.add_child(n)

	# Middle of the head (in the body's own space) - where a mask goes.
	func head_center() -> Vector3:
		for p in parts:
			if String(part_group.get(p, "")) == "head":
				var mi: MeshInstance3D = p
				var c = mi.get_aabb().get_center()
				return mi.transform * c if mi.get_parent() == self else c
		return Vector3(0, 1.665, 0)

	var holding_sword: bool = false
	var holding_shield: bool = false

	func set_gear(sword: bool, shield: bool) -> void:
		set_loadout("sword" if sword else "", "shield" if shield else "", "", wearing_mask, "melee")

	# Your own body in first person: only its shadow (it would block the view).
	var first_person: bool = false
	func set_first_person(on: bool) -> void:
		first_person = on
		var mode = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for n in find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).cast_shadow = mode

	# Ghost look (seen by other ghosts): see-through.
	func set_alpha(a: float) -> void:
		for m in materials():
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
			m.albedo_color.a = a

	# Sets every joint for one frame.
	#  run 0..1: standing (the sketch's A-pose) -> full running stride
	#  phase: where in the stride we are (radians); sprint 0..1: longer strides
	#  air 0..1: jumping / falling / flying - knees tucked, arms out
	#  windup 0..1: fist pulled back (pressing E starts an attack)
	#  punch 0..1: the right arm thrown forward (the attack lands / ends)
	func apply_pose(run: float, phase: float, sprint: float, air: float, windup: float, punch: float) -> void:
		if not hip_l:
			return
		var s = sin(phase)
		var c = cos(phase)
		# Legs: thighs swing; a knee bends hard while its leg swings forward
		# through the air, and stays a little bent while the foot is down.
		var hip_amp = (0.6 + 0.25 * sprint) * run
		var knee_amp = (1.05 + 0.45 * sprint) * run
		var hl = s * hip_amp
		var hr = -s * hip_amp
		var kl = -(knee_amp * max(0.0, c) + 0.18 * run)
		var kr = -(knee_amp * max(0.0, -c) + 0.18 * run)
		hl = lerp(hl, 0.55, air)
		hr = lerp(hr, -0.15, air)
		kl = lerp(kl, -1.0, air)
		kr = lerp(kr, -0.45, air)
		hip_l.rotation = Vector3(hl, 0, 0)
		hip_r.rotation = Vector3(hr, 0, 0)
		knee_l.rotation = Vector3(kl, 0, 0)
		knee_r.rotation = Vector3(kr, 0, 0)

		# Arms: from the A-pose down to the sides, swinging opposite the legs
		# with the elbows bent, like a runner.
		var tilt = lerp(arm_tilt, 0.2, run)
		tilt = lerp(tilt, arm_tilt + 0.3, air)
		var arm_amp = (0.75 + 0.35 * sprint) * run
		var elbow = (1.25 + 0.25 * sprint) * run
		var sl = Vector3(-s * arm_amp, 0, -tilt)
		var sr = Vector3(s * arm_amp, 0, tilt)
		var el = elbow + 0.25 * run * max(0.0, -s) # more bend on the forward swing
		var er = elbow + 0.25 * run * max(0.0, s)
		el = lerp(el, 0.35, air)
		er = lerp(er, 0.35, air)

		# Holding a sword: the sword arm bent, blade pointing ahead. Holding a
		# shield: the shield arm raised in front (the run swing still shows).
		if holding_sword:
			sr = sr.lerp(Vector3(0.3 + 0.35 * s * run, 0, 0.22), 0.75)
			er = lerp(er, 1.2, 0.75)
		if holding_shield:
			sl = sl.lerp(Vector3(0.45 - 0.35 * s * run, 0, -0.3), 0.75)
			el = lerp(el, 1.45, 0.75)
		# Holding a bow / gun: the right arm up and pointing ahead, the left
		# hand helping if it's free.
		if holding_ranged:
			sr = sr.lerp(Vector3(1.35 + 0.08 * s * run, 0, 0.12), 0.85)
			er = lerp(er, 0.2, 0.85)
			if not holding_shield:
				sl = sl.lerp(Vector3(1.2, 0, -0.55), 0.6)
				el = lerp(el, 1.0, 0.6)

		# Attack: wind the right fist back, then throw a straight punch; the
		# left arm comes up as a guard.
		var atk = max(windup, punch)
		var twist = 0.0
		if atk > 0.001:
			var pull_back = Vector3(-0.55, 0, 0.4)
			var thrown = Vector3(1.55, 0, 0.1)
			sr = sr.lerp(pull_back.lerp(thrown, punch), atk)
			er = lerp(er, lerp(2.0, 0.05, punch), atk)
			sl = sl.lerp(Vector3(1.05, 0, -0.3), atk * 0.85)
			el = lerp(el, 1.95, atk * 0.85)
			twist = lerp(-0.3, 0.4, punch) * atk # right shoulder back, then into the punch
		shoulder_l.rotation = sl
		shoulder_r.rotation = sr
		elbow_l.rotation = Vector3(el, 0, 0)
		elbow_r.rotation = Vector3(er, 0, 0)

		# Whole body: lean into the run, a little bounce each stride, twist for punches.
		rotation = Vector3(-0.13 * run * (1.0 - air), twist, 0)
		position = Vector3(0, abs(c) * 0.05 * run * (1.0 - air), 0)

	func _blend_joint(n: Node3D, target: Vector3, a: float) -> void:
		n.rotation = n.rotation.lerp(target, a)

	# Huss Royale sky drop: belly down, arms and legs spread like a skydiver.
	# (Blended over the normal pose; a = 0..1.)
	func blend_glide(a: float) -> void:
		if not hip_l:
			return
		_blend_joint(shoulder_l, Vector3(0.35, 0.0, -1.35), a)
		_blend_joint(shoulder_r, Vector3(0.35, 0.0, 1.35), a)
		_blend_joint(elbow_l, Vector3(0.9, 0, 0), a)
		_blend_joint(elbow_r, Vector3(0.9, 0, 0), a)
		_blend_joint(hip_l, Vector3(-0.1, 0, -0.32), a)
		_blend_joint(hip_r, Vector3(-0.1, 0, 0.32), a)
		_blend_joint(knee_l, Vector3(-0.85, 0, 0), a)
		_blend_joint(knee_r, Vector3(-0.85, 0, 0), a)
		rotation = rotation.lerp(Vector3(-1.25, 0, 0), a)
		position = position.lerp(Vector3(0, 0.62, 0.85), a)

	# Huss Royale slide: leaning back low, front leg out straight, back leg
	# tucked, arms out for balance.
	func blend_slide(a: float) -> void:
		if not hip_l:
			return
		_blend_joint(hip_l, Vector3(1.2, 0, 0), a)
		_blend_joint(knee_l, Vector3(-0.1, 0, 0), a)
		_blend_joint(hip_r, Vector3(0.25, 0, 0.1), a)
		_blend_joint(knee_r, Vector3(-1.75, 0, 0), a)
		_blend_joint(shoulder_l, Vector3(-0.4, 0, -1.15), a)
		_blend_joint(shoulder_r, Vector3(0.6, 0, 0.8) if not holding_sword else Vector3(0.9, 0, 0.35), a)
		_blend_joint(elbow_l, Vector3(0.35, 0, 0), a)
		_blend_joint(elbow_r, Vector3(0.8, 0, 0), a)
		rotation = rotation.lerp(Vector3(0.62, 0, 0), a)
		position = position.lerp(Vector3(0, -0.42, 0), a)


class MobileControls extends Control:
	# On-screen touch controls, laid out like this:
	#   top-left: SPRINT (toggle)                 top-right: Q (only with lunge)
	#   bottom-left: movement joystick            right: HUSS (= E), JUMP below it
	#   top: LEAVE
	# Any finger that lands somewhere else drags the camera. Multi-touch:
	# e.g. one thumb on the joystick while the other looks around.
	const STICK_R: float = 70.0
	var mm: Node
	var touches: Dictionary = {} # touch index -> zone name
	# Look drags are worked out from each finger's own positions. (The
	# browser's per-event "relative" can jump when another finger touches
	# down or a button is pressed, which jolted the camera.)
	var touch_last: Dictionary = {} # touch index -> last position seen
	var touch_start: Dictionary = {} # touch index -> where it touched down
	var look_moving: Dictionary = {} # touch index -> past the dead zone yet
	const LOOK_DEADZONE: float = 10.0 # px (scaled) a finger must move before the view turns
	var stick_vec: Vector2 = Vector2.ZERO

	func _init(manager: Node) -> void:
		mm = manager
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func is_looking() -> bool:
		return touches.values().has("look")

	# Sizes are designed for a 620px-tall screen and scale with the screen
	# height, so the layout keeps its proportions on small phones and on
	# high-resolution screens alike.
	func _k() -> float:
		return clamp(get_viewport_rect().size.y / 620.0, 0.6, 3.0)

	func _layout() -> Dictionary:
		var s = get_viewport_rect().size
		var k = _k()
		var q_y = 125.0 * k
		if mm.team_hud_label and mm.team_hud_label.visible:
			q_y = max(q_y, mm.team_hud_label.get_global_rect().end.y + 10.0)
		return {
			"k": k,
			"stick_r": STICK_R * k,
			"stick_center": Vector2(150 * k, s.y - 200 * k),
			"sprint": Rect2(115 * k, max(105 * k, 100.0), 140 * k, 64 * k),
			"q": Rect2(s.x - 225 * k, q_y, 80 * k, 52 * k),
			"huss": Rect2(s.x - 250 * k, s.y - 250 * k, 120 * k, 76 * k),
			"jump": Rect2(s.x - 240 * k, s.y - 145 * k, 110 * k, 100 * k),
			"leave": Rect2(200, 10, 90 * min(k, 1.0), 40 * min(k, 1.0)), # beside the fixed-size HP box
			"view": Rect2(200 + 100 * min(k, 1.0), 10, 80 * min(k, 1.0), 40 * min(k, 1.0)), # 1st / 3rd person
			"slide": Rect2(s.x - 360 * k, s.y - 130 * k, 104 * k, 80 * k), # Royale: slide (while sprinting)
			"shoot": Rect2(s.x - 380 * k, s.y - 250 * k, 116 * k, 76 * k), # Royale: fire the bow / gun
			"use": Rect2(s.x - 320 * k, q_y, 80 * k, 52 * k), # Royale: the special item (Black Hole)
		}

	func _zone_visible(zone: String) -> bool:
		var me = mm.get_local_player()
		var alive = me != null and not me.is_dead
		match zone:
			"huss", "jump":
				return alive
			"q":
				return alive and mm.local_ability == "lunge"
			"slide":
				return alive and mm.is_royale
			"shoot":
				return alive and mm.is_royale and mm.gear_slot(mm.local_peer_id, "ranged") != ""
			"use":
				return alive and mm.is_royale and mm.gear_slot(mm.local_peer_id, "special") != ""
		return true

	func _zone_at(pos: Vector2) -> String:
		var L = _layout()
		for z in ["q", "use", "huss", "shoot", "jump", "slide", "sprint", "leave", "view"]:
			if _zone_visible(z) and (L[z] as Rect2).grow(6).has_point(pos):
				return z
		if pos.distance_to(L["stick_center"]) <= float(L["stick_r"]) * 1.8:
			return "stick"
		return "look"

	func _held(zone: String) -> bool:
		return touches.values().has(zone)

	func _sync_buttons() -> void:
		mm.mobile_jump_held = _held("jump")
		mm.mobile_e_held = _held("huss")
		mm.mobile_q_held = _held("q")
		mm.mobile_slide_held = _held("slide")
		mm.mobile_shoot_held = _held("shoot")
		mm.mobile_use_held = _held("use")

	func release_all() -> void:
		touches.clear()
		touch_last.clear()
		touch_start.clear()
		look_moving.clear()
		stick_vec = Vector2.ZERO
		mm._mobile_reset_inputs()

	func _update_stick(pos: Vector2) -> void:
		var L = _layout()
		var v = (pos - L["stick_center"]) / float(L["stick_r"])
		if v.length() > 1.0:
			v = v.normalized()
		stick_vec = v
		mm.mobile_move = v

	func _input(event: InputEvent) -> void:
		if not visible:
			return
		if event is InputEventScreenTouch:
			if event.pressed:
				var z = _zone_at(event.position)
				touches[event.index] = z
				touch_last[event.index] = event.position
				touch_start[event.index] = event.position
				look_moving[event.index] = false
				get_viewport().set_input_as_handled()
				match z:
					"stick":
						_update_stick(event.position)
					"sprint":
						mm.mobile_sprint_on = not mm.mobile_sprint_on
					"leave":
						touches.erase(event.index)
						mm._on_leave_requested() # may end the match and free this
						return
					"view":
						mm.toggle_view()
				_sync_buttons()
			else:
				var z2 = touches.get(event.index, "")
				touches.erase(event.index)
				touch_last.erase(event.index)
				touch_start.erase(event.index)
				look_moving.erase(event.index)
				if z2 == "stick":
					stick_vec = Vector2.ZERO
					mm.mobile_move = Vector2.ZERO
				_sync_buttons()
				if z2 != "":
					get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag:
			var z3 = touches.get(event.index, "")
			if z3 == "stick":
				_update_stick(event.position)
			elif z3 == "look":
				# Just touching never turns the view - only dragging does.
				var prev: Vector2 = touch_last.get(event.index, event.position)
				touch_last[event.index] = event.position
				if not look_moving.get(event.index, false):
					var start: Vector2 = touch_start.get(event.index, event.position)
					if event.position.distance_to(start) < LOOK_DEADZONE * _k():
						get_viewport().set_input_as_handled()
						return
					look_moving[event.index] = true
				var rel = event.position - prev
				if rel.length() < max(get_viewport_rect().size.y, 400.0) * 0.5: # ignore impossible jumps
					mm.mobile_look(rel)
			if z3 != "":
				get_viewport().set_input_as_handled()

	func _process(_delta: float) -> void:
		var show = mm.mobile_controls and mm.is_match_active and not mm.is_game_over and mm.get_local_player() != null
		if visible != show:
			visible = show
			if not show:
				release_all()
		if visible:
			queue_redraw()

	func _btn(r: Rect2, title: String, sub: String, lit: bool, held: bool, accent: Color = Color(1, 1, 1)) -> void:
		var sb = StyleBoxFlat.new()
		var a = 0.6 if held else (0.45 if lit else 0.28)
		sb.bg_color = Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35, a) if not lit else Color(accent.r, accent.g, accent.b, a)
		sb.set_corner_radius_all(14)
		sb.border_color = Color(1, 1, 1, 0.75 if lit or held else 0.45)
		sb.set_border_width_all(3 if held else 2)
		draw_style_box(sb, r)
		var font = ThemeDB.fallback_font
		var k = _k()
		var big = min(int((22 if r.size.y >= 60 * k else 18) * k), int(r.size.y * 0.45))
		var y = r.position.y + r.size.y * 0.5 + big * 0.35 - (8 * k if sub != "" else 0.0)
		draw_string(font, Vector2(r.position.x, y), title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, big, Color(1, 1, 1, 0.95))
		if sub != "":
			draw_string(font, Vector2(r.position.x, y + 20 * k), sub, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(13 * k), Color(1, 1, 1, 0.85))

	func _draw() -> void:
		var L = _layout()
		var me = mm.get_local_player()
		# joystick
		var c: Vector2 = L["stick_center"]
		var r: float = L["stick_r"]
		draw_circle(c, r, Color(1, 1, 1, 0.10))
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 3.0, true)
		draw_circle(c + stick_vec * r, r * 0.42, Color(1, 1, 1, 0.5 if _held("stick") else 0.32))
		# buttons
		_btn(L["sprint"], "SPRINT", "ON" if mm.mobile_sprint_on else "OFF", mm.mobile_sprint_on, false, Color(0.3, 0.9, 0.4))
		if _zone_visible("huss"):
			var can_huss = me != null and (me.targeted_opponent != null or me.qte_active)
			_btn(L["huss"], "HUSS", "", can_huss, mm.mobile_e_held, Color(1.0, 0.85, 0.2))
		if _zone_visible("jump"):
			_btn(L["jump"], "JUMP", "", false, mm.mobile_jump_held)
		if _zone_visible("q"):
			_btn(L["q"], "Q", "LUNGE", true, mm.mobile_q_held, Color(1.0, 0.75, 0.15))
		if _zone_visible("shoot"):
			var rt = mm.gear_slot(mm.local_peer_id, "ranged")
			_btn(L["shoot"], "SHOOT", String(mm.GEAR.get(rt, {}).get("name", "")).to_upper(), me != null and me.ranged_cd <= 0.0, mm.mobile_shoot_held, Color(1.0, 0.55, 0.3))
		if _zone_visible("use"):
			_btn(L["use"], "USE", "", true, mm.mobile_use_held, Color(0.75, 0.45, 1.0))
		if _zone_visible("slide"):
			_btn(L["slide"], "SLIDE", "sprint on" if not mm.mobile_sprint_on else "", mm.mobile_sprint_on, mm.mobile_slide_held, Color(0.4, 0.75, 1.0))
		_btn(L["leave"], "LEAVE", "", false, false, Color(1.0, 0.4, 0.4))
		_btn(L["view"], "3RD" if not mm.third_person else "1ST", "", mm.third_person, false, Color(0.5, 0.8, 1.0))


class Crosshair extends Control:
	# Plus-shaped crosshair drawn around this control's origin (screen center).
	const ARM: float = 9.0
	const GAP: float = 3.0
	const THICK: float = 2.0

	var flash_t: float = 0.0

	# A shot of yours hit someone: the crosshair goes red for a moment.
	func flash() -> void:
		flash_t = 0.25
		queue_redraw()

	func _process(delta: float) -> void:
		if flash_t > 0.0:
			flash_t -= delta
			queue_redraw()

	func _draw() -> void:
		var outline = Color(0, 0, 0, 0.75)
		var col = Color(1, 0.25, 0.2, 1.0) if flash_t > 0.0 else Color(1, 1, 1, 0.95)
		for pass_i in range(2):
			var c = outline if pass_i == 0 else col
			var w = THICK + 2.0 if pass_i == 0 else THICK
			var ext = 1.0 if pass_i == 0 else 0.0
			draw_line(Vector2(-ARM - ext, 0), Vector2(-GAP + ext, 0), c, w)
			draw_line(Vector2(GAP - ext, 0), Vector2(ARM + ext, 0), c, w)
			draw_line(Vector2(0, -ARM - ext), Vector2(0, -GAP + ext), c, w)
			draw_line(Vector2(0, GAP - ext), Vector2(0, ARM + ext), c, w)


class RoyaleMapPreview extends Control:
	# A little top-down picture of a Huss Royale map for the vote cards.
	var mechanic: String = "royale"
	var ground: Color = Color(0.36, 0.56, 0.32)

	func _draw() -> void:
		var r = Rect2(Vector2.ZERO, size)
		var c = size * 0.5
		var u = min(size.x, size.y) * 0.5
		var rng = RandomNumberGenerator.new()
		rng.seed = 11
		match mechanic:
			"desert":
				draw_rect(r, Color(0.94, 0.8, 0.55))
				for i in range(7):
					var dp = Vector2(rng.randf() * size.x, rng.randf() * size.y)
					draw_arc(dp, rng.randf_range(10, 26), PI * 1.1, PI * 1.9, 12, Color(0.85, 0.68, 0.42), 2.0)
				for p in [Vector2(0, 0), Vector2(-1.3, -0.55), Vector2(1.3, -0.55), Vector2(-1.3, 0.55), Vector2(1.3, 0.55)]:
					var pc = c + p * u * 0.62
					for k in range(4):
						var s = (0.3 - 0.065 * k) * u
						draw_rect(Rect2(pc - Vector2(s, s), Vector2(s, s) * 2.0), Color(0.82, 0.64, 0.36).darkened(0.07 * k))
					draw_circle(pc, 0.03 * u, Color(1.0, 0.82, 0.3))
			"wasteland":
				draw_rect(r, Color(0.3, 0.36, 0.22))
				draw_rect(r, Color(0.35, 0.9, 0.3, 0.12))
				for i in range(14):
					var tp = Vector2(rng.randf() * size.x, rng.randf() * size.y)
					draw_line(tp, tp + Vector2(rng.randf_range(-6, 6), -10), Color(0.25, 0.2, 0.15), 2.0)
				for i in range(5):
					var bp = Vector2(rng.randf() * size.x, rng.randf() * size.y)
					draw_set_transform(bp, rng.randf() * TAU, Vector2.ONE)
					draw_rect(Rect2(-10, -6, 20, 12), Color(0.45, 0.43, 0.4))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), Color(0.55, 0.55, 0.5))
				draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color(0.08, 0.08, 0.08))
				draw_arc(c, 0.75 * u, 0.0, TAU, 40, Color(0.4, 1.0, 0.3, 0.7), 2.0)
			"moon":
				draw_rect(r, Color(0.02, 0.02, 0.05))
				for i in range(40):
					draw_circle(Vector2(rng.randf() * size.x, rng.randf() * size.y), rng.randf_range(0.5, 1.3), Color(1, 1, 1, rng.randf_range(0.4, 1.0)))
				draw_circle(c, 0.55 * u, Color(0.62, 0.62, 0.66))
				for i in range(6):
					var cp = c + Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35)) * u
					draw_circle(cp, rng.randf_range(0.04, 0.1) * u, Color(0.5, 0.5, 0.54))
				for i in range(9):
					var a = TAU * float(i) / 9.0 + 0.3
					draw_circle(c + Vector2(cos(a) * 1.55, sin(a) * 0.85) * u, rng.randf_range(0.05, 0.1) * u, Color(0.45, 0.4, 0.38))
				draw_circle(c + Vector2(0.2, -0.15) * u, 0.07 * u, Color(0.6, 0.3, 1.0))
				draw_circle(c + Vector2(-0.25, 0.2) * u, 0.07 * u, Color(0.6, 0.3, 1.0))
			_:
				draw_rect(r, Color(0.25, 0.45, 0.75))
				var isl = Rect2(c - Vector2(0.92, 0.92) * u, Vector2(1.84, 1.84) * u)
				draw_rect(isl, ground)
				draw_rect(Rect2(c - Vector2(0.14, 0.14) * u, Vector2(0.28, 0.28) * u), Color(0.6, 0.58, 0.54))
				draw_rect(Rect2(c - Vector2(0.05, 0.05) * u, Vector2(0.1, 0.1) * u), Color(0.4, 0.38, 0.36))
				for d in [Vector2(0, -0.55), Vector2(0, 0.55), Vector2(-0.55, 0), Vector2(0.55, 0)]:
					draw_rect(Rect2(c + d * u - Vector2(0.09, 0.09) * u, Vector2(0.18, 0.18) * u), Color(0.55, 0.38, 0.22))
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						draw_rect(Rect2(c + Vector2(sx, sz) * 0.8 * u - Vector2(0.07, 0.07) * u, Vector2(0.14, 0.14) * u), Color(0.5, 0.48, 0.45))
		draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)


class GeoBuilder:
	# Big Royale maps are made of hundreds of boxes. Drawing each one as its
	# own mesh would be slow in a browser, so they're merged: one mesh (with
	# vertex colors) per builder, and one static body holding all the
	# collision boxes.
	var st: SurfaceTool
	var body: StaticBody3D
	var count: int = 0

	func _init() -> void:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		body = StaticBody3D.new()

	const FACES: Array = [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]

	# A box at center (rotated by rot), in one color. collide = false: looks only.
	func box(center: Vector3, size: Vector3, color: Color, rot: Basis = Basis(), collide: bool = true) -> void:
		var h = size * 0.5
		for f in FACES:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var hn = abs(n.dot(h))
			var hu = abs(u.dot(h))
			var hv = abs(v.dot(h))
			var c = n * hn
			# clockwise seen from outside (Godot's front faces)
			var corners = [c - u * hu - v * hv, c - u * hu + v * hv, c + u * hu + v * hv, c + u * hu - v * hv]
			var wn = (rot * n).normalized()
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(color)
				st.set_normal(wn)
				st.add_vertex(center + rot * corners[idx])
		if collide:
			var cs = CollisionShape3D.new()
			var bs = BoxShape3D.new()
			bs.size = size
			cs.shape = bs
			cs.transform = Transform3D(rot, center)
			body.add_child(cs)
		count += 1

	# A sloped slab whose top surface runs from a to b (a ramp you can walk up).
	func ramp(a: Vector3, b: Vector3, width: float, thick: float, color: Color) -> void:
		var d = b - a
		var x = d.normalized()
		var side = Vector3.UP.cross(x).normalized()
		if side.length() < 0.01:
			side = Vector3.FORWARD
		var y = x.cross(side).normalized()
		if y.y < 0.0:
			y = -y
			side = -side
		var rot = Basis(x, y, x.cross(y)).orthonormalized()
		box((a + b) * 0.5 - y * thick * 0.5, Vector3(d.length(), thick, width), color, rot)

	func finish(parent: Node, mat: Material) -> StaticBody3D:
		if count > 0:
			var mi = MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			body.add_child(mi)
		parent.add_child(body)
		return body


class ShotFx extends Node3D:
	# What a Royale shot looks like: an arrow flying (bows), a quick tracer
	# (hunting rifle) or a glowing blue beam (raygun). Visual only.
	var kind: String = "bow"
	var a: Vector3 = Vector3.ZERO
	var b: Vector3 = Vector3.ZERO
	var t: float = 0.0
	var life: float = 0.3
	var flight: float = 0.0
	var mat: StandardMaterial3D = null
	var outer_mat: StandardMaterial3D = null
	var arrow: Node3D = null

	static func basis_along(dir: Vector3) -> Basis:
		var y = dir.normalized()
		var helper = Vector3.UP if abs(y.y) < 0.98 else Vector3.RIGHT
		var x = helper.cross(y).normalized()
		var z = x.cross(y).normalized()
		return Basis(x, y, z)

	func _ready() -> void:
		var d = b - a
		var length = max(d.length(), 0.05)
		if kind == "dust":
			life = 2.5
			mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.92, 0.78, 0.52, 0.7)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var sm = SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 10
			sm.rings = 5
			for i in range(14):
				var puff = MeshInstance3D.new()
				puff.mesh = sm
				puff.material_override = mat
				var ang = TAU * float(i) / 14.0
				puff.position = a + Vector3(cos(ang) * 3.0, float(i % 4) * 2.5, sin(ang) * 3.0)
				puff.set_meta("dir", Vector3(cos(ang), 0.3, sin(ang)))
				puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(puff)
			return
		if kind == "bow" or kind == "sun_bow":
			arrow = Node3D.new()
			add_child(arrow)
			var shaft = MeshInstance3D.new()
			var cm = CylinderMesh.new()
			cm.top_radius = 0.018
			cm.bottom_radius = 0.018
			cm.height = 0.8
			shaft.mesh = cm
			var sm = StandardMaterial3D.new()
			sm.albedo_color = Color(1.0, 0.8, 0.3) if kind == "sun_bow" else Color(0.65, 0.45, 0.25)
			if kind == "sun_bow":
				sm.emission_enabled = true
				sm.emission = Color(1.0, 0.7, 0.2)
				sm.emission_energy_multiplier = 1.5
			shaft.material_override = sm
			arrow.add_child(shaft)
			var head = MeshInstance3D.new()
			var hm = CylinderMesh.new()
			hm.top_radius = 0.0
			hm.bottom_radius = 0.045
			hm.height = 0.12
			head.mesh = hm
			head.position = Vector3(0, 0.45, 0)
			var hmat = StandardMaterial3D.new()
			hmat.albedo_color = Color(0.75, 0.77, 0.8)
			hmat.metallic = 0.8
			head.material_override = hmat
			arrow.add_child(head)
			var fl = MeshInstance3D.new()
			var fm = BoxMesh.new()
			fm.size = Vector3(0.1, 0.14, 0.01)
			fl.mesh = fm
			fl.position = Vector3(0, -0.36, 0)
			var flm = StandardMaterial3D.new()
			flm.albedo_color = Color(0.9, 0.2, 0.15)
			fl.material_override = flm
			arrow.add_child(fl)
			arrow.global_transform = Transform3D(basis_along(d), a)
			flight = length / 75.0
			life = flight + 0.4
			return
		var beam = MeshInstance3D.new()
		var bm = CylinderMesh.new()
		var col = Color(1.0, 0.92, 0.6)
		var r = 0.02
		life = 0.12
		if kind == "raygun":
			col = Color(0.55, 0.85, 1.0)
			r = 0.06
			life = 0.35
		bm.top_radius = r
		bm.bottom_radius = r
		bm.height = length
		bm.radial_segments = 8
		bm.rings = 1
		beam.mesh = bm
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam.material_override = mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		beam.global_transform = Transform3D(basis_along(d), (a + b) * 0.5)
		if kind == "raygun":
			# a soft blue glow around the beam
			var outer = MeshInstance3D.new()
			var om = CylinderMesh.new()
			om.top_radius = 0.16
			om.bottom_radius = 0.16
			om.height = length
			om.radial_segments = 10
			om.rings = 1
			outer.mesh = om
			var omat = StandardMaterial3D.new()
			omat.albedo_color = Color(0.4, 0.7, 1.0, 0.3)
			omat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			omat.cull_mode = BaseMaterial3D.CULL_DISABLED
			outer.material_override = omat
			outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(outer)
			outer.global_transform = beam.global_transform
			outer_mat = omat
			var glow = OmniLight3D.new()
			glow.light_color = col
			glow.light_energy = 2.0
			glow.omni_range = 4.0
			add_child(glow)
			glow.global_position = b
		else:
			var flash = OmniLight3D.new()
			flash.light_color = Color(1.0, 0.8, 0.4)
			flash.light_energy = 2.5
			flash.omni_range = 3.0
			add_child(flash)
			flash.global_position = a

	func _process(delta: float) -> void:
		t += delta
		if kind == "dust":
			for p in get_children():
				if p is MeshInstance3D:
					p.position += (p.get_meta("dir") as Vector3) * delta * 3.0
					p.scale = Vector3.ONE * (1.0 + t * 1.2)
			mat.albedo_color.a = clamp(1.0 - t / life, 0.0, 1.0) * 0.7
			if t >= life:
				queue_free()
			return
		if arrow:
			var k = clamp(t / max(flight, 0.01), 0.0, 1.0)
			arrow.global_position = a.lerp(b, k)
		elif mat:
			mat.albedo_color.a = clamp(1.0 - t / life, 0.0, 1.0) * 0.9
			if outer_mat:
				outer_mat.albedo_color.a = clamp(1.0 - t / life, 0.0, 1.0) * 0.3
		if t >= life:
			queue_free()


class MapExitHatch extends Area3D:
	# The Wasteland's bunker exits: climbing up the shaft into this zone puts
	# you out on the surface next to the hatch. There's no way back in.
	var out_pos: Vector3
	var face: Vector3

	func _init(dest: Vector3, facing: Vector3) -> void:
		out_pos = dest
		face = facing

	func _ready() -> void:
		collision_mask = 1 | 2
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(2.6, 1.6, 2.6)
		col.shape = box
		add_child(col)
		body_entered.connect(_on_body_entered)

	func _on_body_entered(body: Node3D) -> void:
		if not (body is NetworkPlayer) or body.main_manager == null:
			return
		var mm = body.main_manager
		if not (body.is_local_player() or (body.is_bot and mm.is_host_peer)):
			return
		body.ladder_contacts.clear()
		body.velocity = Vector3.ZERO
		body.global_position = out_pos
		body.rotation.y = atan2(-face.x, -face.z)
		if body.is_local_player():
			mm.log_console("[Wasteland] You climbed out of the bunker. The hatch slams shut behind you.")
			body._send_p2p_position(true)


class MoonPad extends Area3D:
	# A launch pad on the Moon: throws you across the gap to an asteroid (or
	# back down to the moon).
	var launch: Vector3 = Vector3.UP * 20.0
	var col: Color = Color(0.3, 0.8, 1.0)
	var t: float = 0.0
	var ring: MeshInstance3D

	func _ready() -> void:
		collision_mask = 1 | 2
		var cs = CollisionShape3D.new()
		var cyl = CylinderShape3D.new()
		cyl.radius = 1.3
		cyl.height = 1.2
		cs.shape = cyl
		cs.position = Vector3(0, 0.6, 0)
		add_child(cs)
		var disc = MeshInstance3D.new()
		var dm = CylinderMesh.new()
		dm.top_radius = 1.4
		dm.bottom_radius = 1.5
		dm.height = 0.18
		disc.mesh = dm
		disc.position = Vector3(0, 0.05, 0)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.2
		disc.material_override = mat
		add_child(disc)
		ring = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = 0.9
		tm.outer_radius = 1.05
		ring.mesh = tm
		ring.material_override = mat
		add_child(ring)
		var light = OmniLight3D.new()
		light.light_color = col
		light.light_energy = 1.0
		light.omni_range = 4.0
		light.position = Vector3(0, 1.0, 0)
		add_child(light)
		body_entered.connect(_on_body_entered)

	func _process(delta: float) -> void:
		t += delta
		if ring:
			ring.position = Vector3(0, 0.2 + fmod(t * 1.5, 2.0), 0)

	func _on_body_entered(body: Node3D) -> void:
		if not (body is NetworkPlayer) or body.main_manager == null or body.is_dead:
			return
		if body.is_local_player() or (body.is_bot and body.main_manager.is_host_peer):
			body.moon_launch(launch)


class MoonPortal extends Area3D:
	# Step through it and you come out on the other side of the moon.
	var dest: Vector3
	var dest_up: Vector3
	var t: float = 0.0
	var swirl: MeshInstance3D

	func _ready() -> void:
		collision_mask = 1 | 2
		var cs = CollisionShape3D.new()
		var sph = SphereShape3D.new()
		sph.radius = 1.1
		cs.shape = sph
		cs.position = Vector3(0, 1.3, 0)
		add_child(cs)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.65, 0.3, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.25, 1.0)
		mat.emission_energy_multiplier = 1.6
		var frame = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = 1.15
		tm.outer_radius = 1.4
		frame.mesh = tm
		frame.rotation_degrees = Vector3(90, 0, 0)
		frame.position = Vector3(0, 1.4, 0)
		frame.material_override = mat
		add_child(frame)
		swirl = MeshInstance3D.new()
		var dm = CylinderMesh.new()
		dm.top_radius = 1.15
		dm.bottom_radius = 1.15
		dm.height = 0.05
		swirl.mesh = dm
		swirl.rotation_degrees = Vector3(90, 0, 0)
		swirl.position = Vector3(0, 1.4, 0)
		var smat = StandardMaterial3D.new()
		smat.albedo_color = Color(0.4, 0.1, 0.8, 0.55)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.emission_enabled = true
		smat.emission = Color(0.35, 0.1, 0.7)
		swirl.material_override = smat
		add_child(swirl)
		var lbl = Label3D.new()
		lbl.text = "PORTAL\nto the other side"
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 26
		lbl.outline_size = 6
		lbl.modulate = Color(0.85, 0.65, 1.0)
		lbl.position = Vector3(0, 3.3, 0)
		add_child(lbl)
		body_entered.connect(_on_body_entered)

	func _process(delta: float) -> void:
		t += delta
		if swirl:
			swirl.rotation.z = t * 2.0

	func _on_body_entered(body: Node3D) -> void:
		if not (body is NetworkPlayer) or body.main_manager == null:
			return
		if not (body.is_local_player() or (body.is_bot and body.main_manager.is_host_peer)):
			return
		var now = Time.get_ticks_msec()
		if now - body.portal_cd_ms < 1500:
			return
		body.portal_cd_ms = now
		# flip head-over-heels round our own forward: same heading, new side
		var fwd = -body.global_transform.basis.z
		var b = (Basis(fwd.normalized(), PI) * body.global_transform.basis).orthonormalized()
		var out = dest + dest_up * 0.3 + (fwd - dest_up * fwd.dot(dest_up)).normalized() * 2.2
		body.global_transform = Transform3D(b, out)
		body.velocity = Vector3.ZERO
		body.moon_up = b.y
		if body.is_local_player():
			body.main_manager.log_console("[Moon] Through the portal - you're on the other side of the moon!")
			body._send_p2p_position(true)


class BlackHoleFx extends Node3D:
	# The black hole hanging in space while it's out.
	var t: float = 0.0
	var disk: MeshInstance3D

	func _ready() -> void:
		var core = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 16.0
		sm.height = 32.0
		core.mesh = sm
		var black = StandardMaterial3D.new()
		black.albedo_color = Color(0, 0, 0)
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core.material_override = black
		add_child(core)
		disk = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = 19.0
		tm.outer_radius = 38.0
		tm.rings = 48
		disk.mesh = tm
		disk.scale = Vector3(1, 0.06, 1)
		disk.rotation_degrees = Vector3(70, 0, 20)
		var dmat = StandardMaterial3D.new()
		dmat.albedo_color = Color(1.0, 0.55, 0.2)
		dmat.emission_enabled = true
		dmat.emission = Color(0.9, 0.35, 0.9)
		dmat.emission_energy_multiplier = 2.5
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disk.material_override = dmat
		add_child(disk)
		var halo = MeshInstance3D.new()
		var hm = SphereMesh.new()
		hm.radius = 21.0
		hm.height = 42.0
		halo.mesh = hm
		var hmat = StandardMaterial3D.new()
		hmat.albedo_color = Color(0.5, 0.2, 0.9, 0.25)
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.cull_mode = BaseMaterial3D.CULL_FRONT
		halo.material_override = hmat
		add_child(halo)

	func _process(delta: float) -> void:
		t += delta
		if disk:
			disk.rotate_object_local(Vector3.UP, delta * 0.8)


class RoyaleItem extends Node3D:
	# A sword or shield floating above the ground in Huss Royale, with a tall
	# glowing beam so it can be spotted from far away. Walking into it (local
	# player) asks the manager for it; the host decides who gets it.
	var item_id: int
	var item_type: String
	var main_manager: Node
	var visual: Node3D
	var t: float = 0.0

	func _init(id: int, type: String, manager: Node) -> void:
		item_id = id
		item_type = type
		main_manager = manager

	func _ready() -> void:
		visual = Node3D.new()
		add_child(visual)
		if not main_manager.GEAR.has(item_type):
			_build_crystal()
			return
		var info: Dictionary = main_manager.GEAR[item_type]
		var slot = String(info["slot"])
		var gear = MannequinBody.make_gear(item_type)
		gear.scale = Vector3.ONE * 1.6
		match slot:
			"melee":
				gear.rotation_degrees = Vector3(0, 0, 180) # blade up
				gear.position = Vector3(0, -0.6, 0)
			"shield":
				gear.rotation_degrees = Vector3(0, 0, 90) # face out
			"ranged":
				gear.rotation_degrees = Vector3(0, 90, 180) # standing on its end
				gear.position = Vector3(0, -0.2, 0)
			"mask":
				gear.scale = Vector3.ONE * 2.6
				gear.position = Vector3(0, -0.1, 0)
			"genie":
				gear.scale = Vector3.ONE * 1.4
			"special":
				gear.scale = Vector3.ONE * 1.8
		visual.add_child(gear)
		var col: Color = info["color"]
		if slot == "genie":
			# No beam, no sign: you have to find it.
			var glow = OmniLight3D.new()
			glow.light_color = Color(0.5, 0.85, 1.0)
			glow.light_energy = 0.8
			glow.omni_range = 3.0
			add_child(glow)
			return
		var beam = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.12
		cm.height = 9.0
		beam.mesh = cm
		beam.position = Vector3(0, 4.0, 0)
		var bmat = StandardMaterial3D.new()
		bmat.albedo_color = Color(col.r, col.g, col.b, 0.25)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = bmat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		var label = Label3D.new()
		label.text = String(info["name"]).to_upper() + "\n" + main_manager.gear_effect_text(item_type)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 18
		label.outline_size = 5
		label.modulate = col
		label.position = Vector3(0, 1.3, 0)
		add_child(label)

	# Royale crystals (Regen or an ability): the floating crystal with a beam.
	func _build_crystal() -> void:
		var info = main_manager.crystal_info(item_type)
		var col: Color = info["color"]
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.3
		for half in [1.0, -1.0]:
			var cone = MeshInstance3D.new()
			var cm = CylinderMesh.new()
			cm.top_radius = 0.0 if half > 0.0 else 0.42
			cm.bottom_radius = 0.42 if half > 0.0 else 0.0
			cm.height = 0.6
			cm.radial_segments = 4
			cm.rings = 1
			cone.mesh = cm
			cone.position.y = 0.3 * half
			cone.material_override = mat
			visual.add_child(cone)
		var light = OmniLight3D.new()
		light.light_color = col
		light.light_energy = 1.2
		light.omni_range = 4.0
		add_child(light)
		var beam = MeshInstance3D.new()
		var bm = CylinderMesh.new()
		bm.top_radius = 0.12
		bm.bottom_radius = 0.12
		bm.height = 9.0
		beam.mesh = bm
		beam.position = Vector3(0, 4.0, 0)
		var bmat = StandardMaterial3D.new()
		bmat.albedo_color = Color(col.r, col.g, col.b, 0.3)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = bmat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		var label = Label3D.new()
		label.text = String(info["name"]).to_upper() if item_type == "regen" else String(info["name"])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 18
		label.outline_size = 5
		label.modulate = col
		label.position = Vector3(0, 1.1, 0)
		add_child(label)

	func _process(delta: float) -> void:
		t += delta
		if visual:
			visual.rotation.y = t * 1.6
			visual.position.y = sin(t * 2.0) * 0.15
		# Pick up: the local player walks into it.
		var me = main_manager.get_local_player() if main_manager else null
		if me and not me.is_dead and main_manager.item_touching(global_position, global_transform.basis.y, me):
			main_manager.on_item_touched(item_id)


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
	var hatch: bool = false # goes up through a hole in the floor above (hop off at the top)

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
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.8

		# Two rails plus rungs every 0.4m (visual only, no collision) - all
		# in one mesh (big maps have dozens of ladders).
		var wood = Color(0.45, 0.28, 0.12)
		var gb = GeoBuilder.new()
		for x in [-0.5, 0.5]:
			gb.box(Vector3(x, height / 2.0, 0.1), Vector3(0.1, height, 0.1), wood, Basis(), false)
		var y = 0.3
		while y < height:
			gb.box(Vector3(0, y, 0.1), Vector3(1.0, 0.07, 0.07), wood, Basis(), false)
			y += 0.4
		var mi = MeshInstance3D.new()
		mi.mesh = gb.st.commit()
		mi.material_override = mat
		add_child(mi)

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
	var team_ring: MeshInstance3D = null
	# Mannequin body (replaces the old capsule). mesh_inst is the root: hiding
	# it hides the whole body; every part shares base_material (color + outline).
	var body_parts: Array = []
	var body_materials: Array = []
	var hip_l: Node3D = null
	var hip_r: Node3D = null
	var knee_l: Node3D = null
	var knee_r: Node3D = null
	var shoulder_l: Node3D = null
	var shoulder_r: Node3D = null
	var anim_phase: float = 0.0
	var anim_amount: float = 0.0
	var anim_last_pos: Vector3 = Vector3.ZERO
	var anim_window: float = 0.0
	var anim_speed: float = 0.0
	var anim_vspeed: float = 0.0
	var anim_air: float = 0.0
	var anim_windup: float = 0.0
	var anim_punch_t: float = -1.0 # time since the punch started (-1 = none)
	var anim_was_attacking: bool = false
	var body: MannequinBody = null
	var view_camera: Camera3D = null # 3rd person (F5)
	var net_target: Vector3 = Vector3.ZERO # Huss Royale: smoothed remote movement
	var net_has_target: bool = false
	var net_vel: Vector3 = Vector3.ZERO # bots: the host's last known velocity (to run ahead between updates)
	var net_age: float = 0.0
	var last_pos_send_ms: int = -100000
	const ARM_TILT: float = 0.95 # radians out from the sides (the A-pose in the sketch)
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
	# How fast the QTE marker sweeps the bar (bar widths per second). Was 1.5.
	const QTE_SPEED: float = 1.0
	var lock_failsafe_timer: float = 0.0
	const MOVEMENT_LOCK_FAILSAFE: float = 6.0

	var is_launching: bool = false
	var launch_target_pos: Vector3 = Vector3.ZERO
	var launch_timer: float = 0.0

	var gravity_mult: float = 1.0
	var friction: float = 1.0

	const LADDER_CLIMB_SPEED: float = 5.0
	var ladder_contacts: Array = []
	var ladder_hop_t: float = 0.0 # hopping off the top of a hatch ladder (keeps its momentum)

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
	var bot_attack_started_ms: int = -100000
	var bot_clashes: int = 0
	var qte_started_ms: int = -100000
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

	# Huss Royale bots: the match host runs them (_process_royale_bot), everyone
	# else sees them through the host's "bots_move" packets.
	var is_bot: bool = false
	var bot_level: int = 3
	var bot_miss: float = 0.5
	var rb_target: NetworkPlayer = null
	var rb_goal: Vector3 = Vector3.ZERO
	var rb_roaming: bool = false
	var rb_think: float = 0.0
	var rb_path: PackedVector3Array = PackedVector3Array()
	var rb_path_i: int = 0
	var rb_repath: float = 0.0
	var rb_hop: float = 3.0
	var rb_stuck_t: float = 0.0
	var rb_last_pos: Vector3 = Vector3.ZERO
	var rb_pick_t: float = 0.0
	var rb_sprinting: bool = false
	# Sky drop (start of a Royale) and sliding (Ctrl while sprinting, Royale)
	var gliding: bool = false
	var glide_target: Vector3 = Vector3.ZERO
	var slide_t: float = 0.0
	var slide_cd: float = 0.0
	var slide_dir: Vector3 = Vector3.ZERO
	var slide_speed: float = 0.0
	var ctrl_held_last: bool = false
	var remote_slide_t: float = 0.0
	var slide_blend: float = 0.0
	var glide_blend: float = 0.0
	# First person in a Royale: your hands holding your sword / shield.
	var fp_rig: Node3D = null
	var fp_sword: Node3D = null # right hand (melee weapon, or the bow / gun while shooting)
	var fp_shield: Node3D = null # left hand (shield)
	# Royale gear: health up to max_health (150 with a Genie wish), shooting
	var max_health: int = 100
	var base_gravity: float = 1.0
	var ranged_cd: float = 0.0
	var weapon_mode: String = "melee" # "ranged" for a few seconds after shooting
	var ranged_mode_t: float = 0.0
	var fp_recoil: float = 0.0

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
		if is_dummy or is_bot:
			return false
		return peer_id == main_manager.local_peer_id

	# Eliminated: invisible to everyone, can't be hit or block anyone, but the
	# local player can still walk, jump and climb around the map.
	func set_dead_state() -> void :
		if is_dead:
			return
		if is_bot and bot_windup > 0.0 and main_manager and main_manager.is_host_peer:
			_rbot_end_attack(false, true) # let go of whoever it was holding
		is_dead = true
		health = 0
		gliding = false
		slide_t = 0.0
		_cancel_own_qte()
		lock_sources.clear()
		is_movement_locked = false
		is_launching = false
		set_highlight(false)
		if targeted_opponent:
			targeted_opponent.set_highlight(false)
			targeted_opponent = null
		if body:
			body.set_loadout("", "", "", false, "melee")
		if fp_rig:
			fp_rig.visible = false
		if mesh_inst:
			mesh_inst.visible = false
		if team_ring:
			team_ring.visible = false
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
		if main_manager:
			main_manager.refresh_ghost_visibility()

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
			if targeted_opponent.is_bot:
				targeted_opponent.remove_movement_lock(peer_id)
			else:
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
		if gliding and main_manager:
			gravity_mult = main_manager.ROYALE_GLIDE_GRAVITY

		base_material = StandardMaterial3D.new()
		base_material.roughness = 0.55
		if is_dummy:
			base_material.albedo_color = Color(0.6, 0.6, 0.6)
		else:
			base_material.albedo_color = main_manager.player_body_color(peer_id)
		_build_body()

		# Team modes: everyone wears their own color, so a glowing team-colored
		# ring around the waist shows which side they're on.
		if not is_dummy and main_manager.team_size > 1 and not main_manager.is_single_player:
			team_ring = MeshInstance3D.new()
			var torus = TorusMesh.new()
			torus.inner_radius = 0.31 # a glowing belt around the mannequin's waist
			torus.outer_radius = 0.4
			team_ring.mesh = torus
			team_ring.position.y = 1.03
			var ring_mat = StandardMaterial3D.new()
			ring_mat.albedo_color = main_manager.TEAM_COLORS[team]
			ring_mat.emission_enabled = true
			ring_mat.emission = main_manager.TEAM_COLORS[team]
			ring_mat.emission_energy_multiplier = 1.5
			team_ring.material_override = ring_mat
			# Other players see your ring; you don't see your own.
			team_ring.visible = not is_local_player()
			add_child(team_ring)

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
			if not main_manager.mobile_controls:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if main_manager.is_royale:
				_build_fp_rig()
			apply_view_mode()
		if main_manager and main_manager.mobile_controls and hussing_label:
			hussing_label.text = "You're in Hussing range, tap HUSS"

	# ---- mannequin body (see MannequinBody) ----
	# Parts the player colored differently get their own material; the rest
	# share base_material (the player's main color).
	func _build_body() -> void :
		var mats: Dictionary = {}
		body_materials = [base_material]
		for grp in MannequinBody.GROUPS:
			var hex = "" if is_dummy or not main_manager else main_manager.player_part_override(peer_id, grp)
			if hex == "" or Color.html(hex).is_equal_approx(base_material.albedo_color):
				mats[grp] = base_material
			else:
				var m = StandardMaterial3D.new()
				m.roughness = base_material.roughness
				m.albedo_color = Color.html(hex)
				mats[grp] = m
				body_materials.append(m)
		body = MannequinBody.new()
		body.name = "Body"
		body.build(mats, false, "mannequin" if is_dummy or not main_manager else main_manager.player_model(peer_id))
		add_child(body)
		mesh_inst = body
		for m in body.materials():
			if not body_materials.has(m):
				body_materials.append(m)
		body_parts = body.parts
		hip_l = body.hip_l
		hip_r = body.hip_r
		knee_l = body.knee_l
		knee_r = body.knee_r
		shoulder_l = body.shoulder_l
		shoulder_r = body.shoulder_r

		# Your own body: you only see its shadow (the camera sits inside the
		# chest, so the arms/legs would otherwise be in your face) - unless
		# you've switched to 3rd person.
		if is_local_player():
			body.set_first_person(not (main_manager and main_manager.third_person))
		anim_last_pos = global_position if is_inside_tree() else Vector3.ZERO

	# Running cycle (legs and arms bend), jumping, and a punch when attacking -
	# driven by how fast the body actually moves, so it looks the same for
	# remote players whose positions come over the network.
	func set_gear(_sword: bool, _shield: bool) -> void :
		refresh_gear()

	func heal(amount: int) -> void :
		if is_dead:
			return
		health = min(max_health, health + amount)
		_update_health_display()


	# ---- The Moon: "down" is toward the moon (or the asteroid you're on) ----
	var moon_up: Vector3 = Vector3.UP
	var void_t: float = 0.0 # seconds with no pull at all
	var moon_fly_t: float = 0.0 # thrown by a launch pad: keep the momentum
	var portal_cd_ms: int = -100000
	var f_held_last: bool = false

	func moon_launch(v: Vector3) -> void :
		velocity = v
		moon_fly_t = 1.6
		gliding = false
		if main_manager:
			gravity_mult = base_gravity

	# Turn the body so its feet point down the pull (quickly in the air,
	# straight away on the ground). Returns main_manager.moon_gravity().
	func _moon_align(delta: float) -> Array:
		var gi = main_manager.moon_gravity(global_position)
		var up: Vector3 = gi[0] if int(gi[2]) >= 0 else moon_up
		var cur = global_transform.basis.y
		var ang = cur.angle_to(up)
		if ang > 0.0005:
			var axis = cur.cross(up)
			if axis.length() < 0.0001:
				axis = global_transform.basis.x
			var step = ang if (is_on_floor() or ang < 0.05) else min(ang, 4.0 * delta)
			var b = (Basis(axis.normalized(), step) * global_transform.basis).orthonormalized()
			global_transform = Transform3D(b, global_position)
		moon_up = global_transform.basis.y
		up_direction = moon_up
		return gi

	# Pull + walking along the surface (players and bots). wish: the way to go.
	func _moon_step(delta: float, wish: Vector3, speed: float, jump: bool, gi: Array, hold: bool = false) -> void :
		if int(gi[2]) < 0:
			# Adrift between the moon and the asteroids: no pull, no grip.
			void_t += delta
			move_and_slide()
			return
		void_t = 0.0
		var up = moon_up
		var vu = velocity.dot(up)
		var vt = velocity - up * vu
		if not is_on_floor():
			vu -= float(gi[1]) * gravity_mult * delta
		if gliding:
			if is_on_floor() or main_manager.royale_time >= main_manager.ROYALE_GLIDE_TIME:
				gliding = false
				gravity_mult = base_gravity
				if is_local_player() and is_on_floor():
					main_manager.log_console("[Royale] Landed on the moon! Grab a Plasma Sword or a Raygun.")
			else:
				gravity_mult = main_manager.ROYALE_GLIDE_GRAVITY
				vu = max(vu, -main_manager.ROYALE_GLIDE_FALL)
		if hold:
			vt = Vector3.ZERO
		elif moon_fly_t > 0.0:
			moon_fly_t -= delta # (a launch pad threw us: keep going)
		else:
			var dir = wish - up * wish.dot(up)
			if dir.length() > 0.05:
				vt = vt.lerp(dir.normalized() * speed, friction)
			else:
				vt = vt.move_toward(Vector3.ZERO, max(speed, 8.0) * friction)
			if jump and is_on_floor():
				vu = jump_velocity
		velocity = vt + up * vu
		move_and_slide()

	# Turn (around our own up) to face dir.
	func _moon_face(dir: Vector3, delta: float) -> void :
		var f = dir - moon_up * dir.dot(moon_up)
		if f.length() < 0.05:
			return
		var target = main_manager.basis_up(moon_up, f)
		var b = global_transform.basis.orthonormalized().slerp(target, clamp(10.0 * delta, 0.0, 1.0)).orthonormalized()
		global_transform = Transform3D(b, global_position)

	# The local player on the Moon (instead of the flat-ground movement).
	func _moon_local(delta: float) -> void :
		var gi = _moon_align(delta)
		var mm = main_manager
		var is_sprinting: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT) or mm.mobile_sprint_on
		var speed: float = sprint_speed if is_sprinting else walk_speed
		var ability: String = mm.local_ability
		if ability == "speed_boost":
			speed *= mm.SPEED_BOOST_MULT
		var jump_pressed: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("ui_accept") or mm.mobile_jump_held
		var jump_just = jump_pressed and not jump_held_last
		jump_held_last = jump_pressed
		if jump_just and ability == "double_jump" and not is_on_floor() and int(gi[2]) >= 0:
			velocity += moon_up * (jump_velocity * 1.1 - velocity.dot(moon_up))
			mm.consume_local_ability("used")
		var q_pressed = Input.is_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_Q) or mm.mobile_q_held
		var q_just = q_pressed and not q_held_last
		q_held_last = q_pressed
		if q_just and ability == "lunge":
			_start_lunge()
			return
		# F / USE: the Black Hole
		var f_pressed = Input.is_key_pressed(KEY_F) or Input.is_physical_key_pressed(KEY_F) or mm.mobile_use_held
		if f_pressed and not f_held_last and not is_dead:
			mm.use_special()
		f_held_last = f_pressed
		var input_dir: Vector3 = Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
		input_dir += _mobile_move_dir()
		var wish = global_transform.basis * input_dir
		# Ctrl while sprinting: slide (here too)
		var ctrl = Input.is_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_CTRL) or mm.mobile_slide_held
		var ctrl_just = ctrl and not ctrl_held_last
		ctrl_held_last = ctrl
		slide_cd -= delta
		if slide_t <= 0.0 and ctrl_just and is_sprinting and is_on_floor() and not gliding and slide_cd <= 0.0:
			var hv = velocity - moon_up * velocity.dot(moon_up)
			if hv.length() > walk_speed * 0.5:
				_start_slide(hv)
		if slide_t > 0.0:
			slide_t -= delta
			var k = clamp(slide_t / mm.SLIDE_TIME, 0.0, 1.0)
			speed = lerp(walk_speed * 0.8, slide_speed, k)
			slide_dir = (slide_dir - moon_up * slide_dir.dot(moon_up)).normalized()
			var steer = wish - moon_up * wish.dot(moon_up)
			if steer.length() > 0.1:
				slide_dir = slide_dir.lerp(steer.normalized(), clamp(2.5 * delta, 0.0, 1.0)).normalized()
			wish = slide_dir
			if jump_pressed or slide_t <= 0.0:
				slide_t = 0.0
				slide_cd = mm.SLIDE_COOLDOWN
		_moon_step(delta, wish, speed, jump_pressed, gi)
		_send_p2p_position()
		if void_t >= mm.MOON_VOID_TIME and not is_dead:
			void_t = 0.0
			mm.log_console("[Moon] You drifted off into space!")
			mm.kill_local_player_from_fall()

	# Host: a bot on the moon (the moon is round, so no path grid - it just
	# walks straight at things, jumping over rocks).
	func _process_moon_bot(delta: float) -> void :
		net_has_target = false
		if is_dead:
			return
		var gi = _moon_align(delta)
		if void_t >= main_manager.MOON_VOID_TIME:
			void_t = 0.0
			main_manager.kill_bot_from_fall(self)
			return
		if is_launching:
			launch_timer -= delta
			var ld = (launch_target_pos - global_position).normalized()
			velocity = ld * 32.0 + moon_up * 3.0
			move_and_slide()
			if launch_timer <= 0.0:
				is_launching = false
			return
		if bot_windup > 0.0:
			_rbot_process_windup(delta)
			_moon_step(delta, Vector3.ZERO, 20.0, false, gi, true)
			return
		if is_movement_locked:
			lock_failsafe_timer -= delta
			if lock_failsafe_timer <= 0.0:
				lock_sources.clear()
				is_movement_locked = false
			_moon_step(delta, Vector3.ZERO, 20.0, false, gi, true)
			return
		if gliding:
			var to = glide_target - global_position
			_moon_face(to, delta)
			_moon_step(delta, to, walk_speed, false, gi)
			return
		bot_attack_cd -= delta
		ranged_cd -= delta
		rb_think -= delta
		if rb_think <= 0.0:
			rb_think = 0.25 if bot_level >= 4 else 0.45
			_rbot_think()
		var t = rb_target
		if t and (not is_instance_valid(t) or t.is_dead):
			rb_target = null
			t = null
		if t and bot_attack_cd <= 0.0 and not t.gliding and _bot_can_hit(t):
			_rbot_start_attack(t)
			_moon_step(delta, Vector3.ZERO, 20.0, false, gi, true)
			return
		if t:
			_rbot_try_shoot(t)
		var dest = t.global_position if t else rb_goal
		var wish = dest - global_position
		if t and global_position.distance_to(t.global_position) < 2.0:
			_moon_face(wish, delta)
			wish = Vector3.ZERO
		else:
			_moon_face(wish, delta)
		var jump = false
		rb_stuck_t += delta
		if rb_stuck_t >= 0.8:
			if wish.length() > 0.5 and global_position.distance_to(rb_last_pos) < 0.4:
				jump = true
				bot_jumps += 1
				if rb_roaming:
					rb_goal = main_manager.moon_random_point()
			rb_last_pos = global_position
			rb_stuck_t = 0.0
		if rb_sprinting and wish.length() > 1.0 and is_on_floor():
			rb_hop -= delta
			if rb_hop <= 0.0:
				rb_hop = randf_range(2.5, 6.0)
				jump = true
				bot_jumps += 1
		_moon_step(delta, wish, sprint_speed if rb_sprinting else walk_speed, jump, gi)
		rb_pick_t -= delta
		if rb_pick_t <= 0.0:
			rb_pick_t = 0.15
			main_manager.royale_bot_pickups(self)

	# Someone else's shot arrived: show them holding the bow / gun for a bit.
	func remote_shot() -> void :
		ranged_mode_t = 5.0
		set_weapon_mode("ranged")

	# ---- Huss Royale gear on this player ----
	# Rebuilds what the body (and your first-person hands) are holding from
	# the manager's gear table.
	func refresh_gear() -> void :
		if not main_manager:
			return
		var g = main_manager.gear_of(peer_id)
		if body:
			if is_dead:
				body.set_loadout("", "", "", false, "melee")
			else:
				body.set_loadout(String(g.get("melee", "")), String(g.get("shield", "")), String(g.get("ranged", "")), g.has("mask"), weapon_mode)
		_update_fp_rig_gear()

	func set_weapon_mode(mode: String) -> void :
		if weapon_mode == mode:
			return
		weapon_mode = mode
		refresh_gear()

	# A Genie wish: 150 HP, 40 damage hits, twice as fast, lower gravity.
	func apply_genie() -> void :
		if not main_manager:
			return
		max_health = main_manager.GENIE_HEALTH
		health = max_health
		walk_speed = 8.0 * main_manager.GENIE_SPEED
		sprint_speed = 14.0 * main_manager.GENIE_SPEED
		base_gravity = main_manager.GENIE_GRAVITY
		if not gliding:
			gravity_mult = base_gravity
		_update_health_display()
		if not get_node_or_null("GenieAura"):
			var aura = OmniLight3D.new()
			aura.name = "GenieAura"
			aura.light_color = Color(0.4, 0.85, 1.0)
			aura.light_energy = 1.4
			aura.omni_range = 3.0
			aura.position = Vector3(0, 1.2, 0)
			add_child(aura)

	func _fire_down() -> bool:
		if main_manager.mobile_controls:
			return main_manager.mobile_shoot_held
		return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	# Left click / SHOOT: a shot along the crosshair. Whoever fires decides
	# whether it hit (like the E attack); everyone sees the arrow / beam.
	func _fire_ranged() -> void :
		var type = main_manager.gear_slot(peer_id, "ranged")
		if not main_manager.GEAR.has(type) or not camera:
			return
		var g: Dictionary = main_manager.GEAR[type]
		ranged_cd = float(g.get("cd", 1.0))
		ranged_mode_t = 6.0
		set_weapon_mode("ranged")
		fp_recoil = 1.0
		var from = camera.global_position
		var dir = -camera.global_transform.basis.z
		var reach = float(g.get("range", 70.0))
		var q = PhysicsRayQueryParameters3D.create(from, from + dir * reach)
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var hit = get_world_3d().direct_space_state.intersect_ray(q)
		var end = from + dir * reach
		var victim = -1
		if not hit.is_empty():
			end = hit["position"]
			var c = hit["collider"]
			if c is NetworkPlayer and c != self and not c.is_dead and not c.gliding and not main_manager.is_teammate(c.peer_id, peer_id):
				victim = c.peer_id
		var muzzle = from + dir * 0.7 + camera.global_transform.basis.x * 0.22 - camera.global_transform.basis.y * 0.18
		main_manager.royale_shot(peer_id, type, muzzle, end, victim)

	# Host: a bot with a bow / rifle / raygun shoots at its target - and misses
	# as often as its difficulty says.
	func _rbot_try_shoot(t: NetworkPlayer) -> bool:
		if ranged_cd > 0.0 or t == null or t.is_dead or t.gliding:
			return false
		var type = main_manager.gear_slot(peer_id, "ranged")
		if not main_manager.GEAR.has(type):
			return false
		var g: Dictionary = main_manager.GEAR[type]
		var dist = global_position.distance_to(t.global_position)
		if dist < 4.5 or dist > float(g.get("range", 70.0)) * 0.7:
			return false
		var eye = global_position + _up() * 1.5
		var aim = t.global_position + t._up() * 1.0
		var q = PhysicsRayQueryParameters3D.create(eye, aim)
		q.exclude = [get_rid()]
		q.collision_mask = 1
		if get_world_3d().direct_space_state.intersect_ray(q).get("collider") != t:
			return false
		_bot_face(t.global_position, 0.08)
		ranged_cd = float(g.get("cd", 1.0)) * (1.25 if bot_level >= 4 else 1.7)
		ranged_mode_t = 5.0
		set_weapon_mode("ranged")
		var hit = randf() >= bot_miss
		var end = aim
		if not hit:
			# a near miss: past their shoulder
			var side = (aim - eye).cross(_up()).normalized()
			end = aim + side * randf_range(1.2, 2.5) * (1.0 if randf() < 0.5 else -1.0) + _up() * randf_range(-0.5, 1.0)
			end = eye + (end - eye).normalized() * float(g.get("range", 70.0)) * 0.8
			bot_misses += 1
		else:
			bot_hits += 1
		main_manager.royale_shot(peer_id, type, eye + (aim - eye).normalized() * 0.7, end, t.peer_id if hit else -1)
		return true

	# The way "up" is for this player (straight up, except on the Moon).
	func _up() -> Vector3:
		return global_transform.basis.y.normalized() if is_inside_tree() else Vector3.UP


	# The camera you see through: the eye camera (1st person) or one behind
	# your shoulder (3rd person). Aiming / targeting always uses the eye camera.
	func apply_view_mode() -> void :
		if not is_local_player() or not camera:
			return
		var tp = main_manager.third_person
		if tp:
			if not view_camera:
				view_camera = Camera3D.new()
				view_camera.top_level = true
				view_camera.fov = camera.fov
				add_child(view_camera)
			_update_view_camera()
			view_camera.make_current()
		elif camera.is_inside_tree():
			camera.make_current()
		if body:
			body.set_first_person(not tp)
		_update_fp_rig_gear()
		# Your own name tag / HP tag would float over your head in 3rd person.
		if name_label:
			name_label.visible = false
		var hp = get_node_or_null("HPLabel")
		if hp:
			hp.visible = false

	func _update_view_camera() -> void :
		if not view_camera or not camera or not is_inside_tree():
			return
		var b = (global_transform.basis * Basis(Vector3.RIGHT, camera.rotation.x)).orthonormalized()
		var upv = global_transform.basis.y.normalized()
		var pivot = global_position + upv * 1.55
		var desired = pivot + b.z * 3.6 + b.x * 0.55 + upv * 0.3
		# Don't go through walls: stop in front of anything behind you.
		var q = PhysicsRayQueryParameters3D.create(pivot, desired)
		var ex: Array = [get_rid()]
		var parent = get_parent()
		if parent:
			for p in parent.get_children():
				if p is CollisionObject3D:
					ex.append(p.get_rid())
		q.exclude = ex
		q.collision_mask = 1
		var hit = get_world_3d().direct_space_state.intersect_ray(q)
		var pos = desired
		if not hit.is_empty():
			pos = hit["position"] + (pivot - desired).normalized() * 0.3
		view_camera.global_transform = Transform3D(b, pos)

	func _process(delta: float) -> void :
		if not body or delta <= 0.0:
			return
		if ranged_mode_t > 0.0:
			ranged_mode_t -= delta
			if ranged_mode_t <= 0.0 and weapon_mode == "ranged":
				set_weapon_mode("melee")
		# Huss Royale sends positions 20x a second: glide between them.
		if net_has_target and not is_local_player():
			if is_bot and net_age < 0.3:
				# Keep moving the way the host's bot was going until the next update.
				net_target += net_vel * delta
				global_position += net_vel * delta
			net_age += delta
			global_position = global_position.lerp(net_target, clamp(delta * 14.0, 0.0, 1.0))
		if view_camera and main_manager.third_person and is_local_player():
			_update_view_camera()
		# Speed measured over ~0.15s, not per frame: positions only change on
		# physics ticks / when network updates arrive, which can be less often
		# than frames are drawn.
		anim_window += delta
		if anim_window >= 0.15:
			var moved = global_position - anim_last_pos
			anim_last_pos = global_position
			var aup = _up()
			anim_vspeed = abs(moved.dot(aup)) / anim_window
			moved -= aup * moved.dot(aup)
			anim_speed = moved.length() / anim_window
			if anim_speed > 40.0:
				anim_speed = 0.0 # a teleport / respawn, not running
			anim_window = 0.0
		var speed = anim_speed
		var flying = is_dead and main_manager and main_manager.ghosts_can_fly()
		var in_air = flying or anim_vspeed > 2.0 or is_launching
		# Full running stride from a jog up (the practice bot moves at 4.5-5.5).
		var target = 0.0 if flying else clamp(speed / 4.0, 0.0, 1.0)
		if in_air:
			target *= 0.3 # jumping / falling / climbing: legs mostly still
		var k = clamp(delta * 10.0, 0.0, 1.0)
		anim_amount = lerp(anim_amount, target, k)
		anim_air = lerp(anim_air, 1.0 if in_air and not is_launching else 0.0, clamp(delta * 8.0, 0.0, 1.0))
		anim_phase = fmod(anim_phase + delta * (2.5 + speed * 1.05), TAU)
		var sprint = clamp((speed - 8.0) / 6.0, 0.0, 1.0)

		# Attacks: pressing E (a QTE starting) winds the fist back; when it
		# ends (the hit lands, misses or clashes) the punch is thrown.
		var attacking = qte_active
		if anim_was_attacking and not attacking:
			anim_punch_t = 0.0
		anim_was_attacking = attacking
		anim_windup = move_toward(anim_windup, 1.0 if attacking else 0.0, delta * 7.0)
		var punch = 0.0
		if anim_punch_t >= 0.0:
			anim_punch_t += delta
			var t = anim_punch_t
			if t < 0.07:
				punch = t / 0.07
			elif t < 0.22:
				punch = 1.0
			elif t < 0.42:
				punch = 1.0 - (t - 0.22) / 0.2
			else:
				anim_punch_t = -1.0
		body.apply_pose(anim_amount, anim_phase, sprint, anim_air, anim_windup, punch)
		# Royale: skydiving during the sky drop, sliding (Ctrl while sprinting).
		var sliding = slide_t > 0.0 if (is_local_player() or is_bot) else remote_slide_t > 0.0
		remote_slide_t = max(remote_slide_t - delta, 0.0)
		slide_blend = move_toward(slide_blend, 1.0 if sliding else 0.0, delta * 9.0)
		glide_blend = move_toward(glide_blend, 1.0 if gliding and not is_dead else 0.0, delta * 2.5)
		if glide_blend > 0.001:
			body.blend_glide(glide_blend)
		if slide_blend > 0.001:
			body.blend_slide(slide_blend)
		if is_local_player() and camera:
			# Duck the view while sliding.
			camera.position.y = lerp(camera.position.y, 0.95 if sliding else 1.5, clamp(delta * 12.0, 0.0, 1.0))
			if fp_rig:
				_animate_fp_rig(delta, punch)

	# 2v2 / 3v3 / FFA: ghosts see each other, half see-through (living
	# players still can't see ghosts at all).
	func show_as_ghost(seen: bool) -> void :
		if not body:
			return
		body.visible = seen
		if seen:
			body.set_alpha(0.5)
		if team_ring:
			team_ring.visible = seen
			if seen and team_ring.material_override:
				var rm: StandardMaterial3D = team_ring.material_override
				rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				rm.albedo_color.a = 0.5
		if name_label:
			name_label.visible = seen
			name_label.modulate.a = 0.5 if seen else 1.0

	func update_nametag(nickname: String, elo: int) -> void :
		if name_label and main_manager and is_bot:
			name_label.modulate = main_manager.player_color(peer_id).lerp(Color.WHITE, 0.35)
			name_label.text = "[BOT Lv" + str(bot_level) + "] " + nickname
			return
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
		hp_label.text = "HP: " + str(health) + "/" + str(max_health)
		add_child(hp_label)

	func _update_health_display() -> void :
		var hp_label = get_node_or_null("HPLabel") as Label3D
		if hp_label:
			hp_label.text = "HP: " + str(health) + "/" + str(max_health)
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
			rotate_object_local(Vector3.UP, - event.relative.x * mouse_sensitivity)
			if camera:
				camera.rotate_x( - event.relative.y * mouse_sensitivity)
				camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	func _physics_process(delta: float) -> void :
		_update_health_display()

		if global_position.y < FALL_BOUNDARY_Y and not (main_manager and main_manager.is_moon()):
			if is_dummy:
				apply_damage(100)
			elif is_bot:
				if main_manager.is_host_peer and not is_dead:
					main_manager.kill_bot_from_fall(self)
			elif is_local_player():
				if is_dead:
					# Ghosts can't die twice - just send them home.
					global_position = spawn_position
					velocity = Vector3.ZERO
					main_manager.log_console("[Match] You fell off the map - back to your spawn.")
					_send_p2p_position(true)
				else:
					main_manager.log_console("[Match] You fell off the map!")
					main_manager.kill_local_player_from_fall()
					if is_dead and (main_manager.team_size > 1 or main_manager.is_ffa):
						# 2v2/3v3: you're out but your team plays on - roam
						# invisibly from your spawn.
						global_position = spawn_position
						velocity = Vector3.ZERO
						_send_p2p_position(true)
			return

		if is_dummy:
			_process_dummy_ai(delta)
			return

		if is_bot:
			if main_manager.is_host_peer and main_manager.is_match_active and not main_manager.is_game_over:
				_process_royale_bot(delta)
			return

		if not is_local_player():
			return

		# Your own QTE keeps running even if an enemy grabs you mid-attack.
		if qte_active:
			_process_qte(delta)
			return

		if is_movement_locked:
			slide_t = 0.0
			# The practice bot just started its attack and you pressed E at the
			# same moment: clash, both of you get flung back.
			if main_manager.is_single_player and _e_down() and not is_dead and not main_manager.combat_cooldown_active and not main_manager.is_qte_in_progress:
				for src in lock_sources.keys():
					var bot = main_manager.get_player(int(src))
					if bot and bot.is_dummy and bot.bot_windup > 0.0 and main_manager._now_ms() - bot.bot_attack_started_ms <= main_manager.CLASH_WINDOW_MS:
						bot._bot_clash(self)
						return
			# Failsafe: never stay frozen forever if the unlock packet is lost.
			lock_failsafe_timer -= delta
			if lock_failsafe_timer <= 0.0:
				lock_sources.clear()
				is_movement_locked = false
				main_manager.log_console("[Combat] Movement lock expired.")
			if main_manager.is_moon():
				_moon_step(delta, Vector3.ZERO, 20.0, false, _moon_align(delta), true)
				_send_p2p_position()
				return
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
			if main_manager.is_moon():
				_moon_align(delta)
			var launch_dir = (launch_target_pos - global_position).normalized()
			velocity = launch_dir * 32.0 + _up() * 3.0
			move_and_slide()
			_send_p2p_position()
			if launch_timer <= 0.0:
				is_launching = false
			return

		if is_dead and main_manager.ghosts_can_fly():
			_process_ghost_flight(delta)
			return

		_update_mouse_capture()

		if not is_dead:
			if main_manager.mobile_controls:
				_apply_aim_assist(delta)
			_detect_and_highlight_opponents()

			if _e_down() and targeted_opponent and not gliding and not main_manager.combat_cooldown_active and not main_manager.is_qte_in_progress:
				_start_qte()
			ranged_cd -= delta
			if main_manager.is_royale and not gliding and ranged_cd <= 0.0 and not main_manager.is_qte_in_progress and main_manager.gear_slot(peer_id, "ranged") != "" and _fire_down():
				_fire_ranged()

		if main_manager.is_moon():
			_moon_local(delta)
			return

		if not is_on_floor():
			velocity.y -= 20.0 * gravity_mult * delta
		if gliding:
			_update_glide()

		var is_sprinting: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT) or main_manager.mobile_sprint_on
		var current_speed: float = sprint_speed if is_sprinting else walk_speed
		var ability: String = main_manager.local_ability
		if ability == "speed_boost":
			current_speed *= main_manager.SPEED_BOOST_MULT

		var jump_pressed: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("ui_accept") or main_manager.mobile_jump_held
		var jump_just_pressed = jump_pressed and not jump_held_last
		jump_held_last = jump_pressed
		if jump_pressed and is_on_floor():
			velocity.y = jump_velocity * (1.2 if is_sprinting else 1.0)
		elif jump_just_pressed and ability == "double_jump" and get_active_ladder() == null:
			# Second jump in mid-air - uses up the crystal.
			velocity.y = jump_velocity * 1.1
			main_manager.consume_local_ability("used")

		var q_pressed = Input.is_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_Q) or main_manager.mobile_q_held
		var q_just_pressed = q_pressed and not q_held_last
		q_held_last = q_pressed
		if q_just_pressed and ability == "lunge":
			_start_lunge()
			return

		# Huss Royale: Ctrl while sprinting = slide.
		var ctrl = Input.is_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_CTRL) or main_manager.mobile_slide_held
		var ctrl_just = ctrl and not ctrl_held_last
		ctrl_held_last = ctrl
		slide_cd -= delta
		if slide_t > 0.0:
			_process_slide(delta)
			return
		if ctrl_just and main_manager.is_royale and is_sprinting and is_on_floor() and not gliding and not is_dead and slide_cd <= 0.0:
			var hv = Vector3(velocity.x, 0.0, velocity.z)
			if hv.length() > walk_speed * 0.5:
				_start_slide(hv)
				_process_slide(delta)
				return

		var input_dir: Vector3 = Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
		input_dir += _mobile_move_dir()

		var direction = (transform.basis * input_dir).normalized()
		if ladder_hop_t > 0.0:
			ladder_hop_t -= delta # (off the top of a hatch ladder: let the hop carry you)
		elif direction != Vector3.ZERO:
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

	# Ghosts fly where they look: look up and hold W to rise, look down to sink,
	# A/D strafe, Shift = faster. No gravity; let go of the keys to hover.
	func _process_ghost_flight(delta: float) -> void :
		_update_mouse_capture()

		var input_dir: Vector3 = Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
		input_dir += _mobile_move_dir()
		if input_dir.length() > 1.0:
			input_dir = input_dir.normalized()

		var look: Basis = camera.global_transform.basis if camera else global_transform.basis
		var dir: Vector3 = -look.z * -input_dir.z + look.x * input_dir.x
		if dir.length() > 0.001:
			dir = dir.normalized()
		var fast: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT) or main_manager.mobile_sprint_on
		var speed: float = sprint_speed * main_manager.GHOST_FAST_MULT if fast else walk_speed
		velocity = velocity.lerp(dir * speed, min(1.0, 10.0 * delta))
		move_and_slide()
		if main_manager.is_moon():
			if global_position.length() > 150.0:
				global_position = global_position.normalized() * 150.0
		elif global_position.y > main_manager.GHOST_FLY_MAX_HEIGHT:
			global_position.y = main_manager.GHOST_FLY_MAX_HEIGHT
			velocity.y = min(velocity.y, 0.0)
		_send_p2p_position()

	# --- INPUT HELPERS (keyboard/mouse on PC, touch on mobile) ---
	func _e_down() -> bool:
		return Input.is_key_pressed(KEY_E) or main_manager.mobile_e_held

	func _mobile_move_dir() -> Vector3:
		var v: Vector2 = main_manager.mobile_move
		if v.length() < 0.15:
			return Vector3.ZERO
		return Vector3(v.x, 0.0, v.y) # stick up = forward

	func _update_mouse_capture() -> void :
		if main_manager.mobile_controls:
			if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return
		if Input.is_key_pressed(KEY_TAB):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Turning the view from a touch drag (mobile).
	func apply_look(rel: Vector2, sens: float) -> void :
		if is_movement_locked:
			return
		rotate_object_local(Vector3.UP, -rel.x * sens)
		if camera:
			camera.rotate_x(-rel.y * sens)
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Mobile aim assist: if an opponent is close, roughly in front of you and in
	# plain sight, the camera is pulled toward them (gently while you're
	# dragging the view yourself, so you can still look away).
	func _apply_aim_assist(delta: float) -> void :
		if not camera or is_movement_locked:
			return
		var cam_pos = camera.global_position
		var fwd = -camera.global_transform.basis.z
		var best: NetworkPlayer = null
		var best_angle = deg_to_rad(main_manager.AIM_ASSIST_CONE_DEG)
		var space = get_world_3d().direct_space_state
		for child in get_parent().get_children():
			if not (child is NetworkPlayer) or child == self or child.is_dead or main_manager.is_teammate(child.peer_id, peer_id):
				continue
			var tp = child.global_position + child._up() * 0.9
			var to = tp - cam_pos
			var dist = to.length()
			if dist < 0.5 or dist > main_manager.AIM_ASSIST_RANGE:
				continue
			var ang = fwd.angle_to(to)
			if ang > best_angle:
				continue
			var q = PhysicsRayQueryParameters3D.create(cam_pos, tp)
			q.exclude = [get_rid()]
			q.collision_mask = 1
			if space.intersect_ray(q).get("collider") != child:
				continue
			best_angle = ang
			best = child
		if best == null:
			return
		var to_t = best.global_position + best._up() * 0.9 - cam_pos
		var desired_yaw = atan2(-to_t.x, -to_t.z)
		var desired_pitch = atan2(to_t.y, Vector2(to_t.x, to_t.z).length())
		# A gentle nudge, not a lock-on: it fades out toward the edge of the
		# cone and never turns you faster than AIM_ASSIST_MAX_TURN.
		var fall = clamp(1.0 - best_angle / deg_to_rad(main_manager.AIM_ASSIST_CONE_DEG), 0.0, 1.0)
		var k = main_manager.AIM_ASSIST_STRENGTH * fall * (0.5 if main_manager.mobile_look_active() else 1.0)
		var t = 1.0 - exp(-k * delta)
		var max_step = deg_to_rad(main_manager.AIM_ASSIST_MAX_TURN) * delta
		if main_manager.is_moon():
			# work it out in our own frame ("up" is wherever the moon puts it)
			var lt = global_transform.basis.orthonormalized().inverse() * to_t
			rotate_object_local(Vector3.UP, clamp(wrapf(atan2(-lt.x, -lt.z), -PI, PI) * t, -max_step, max_step))
			desired_pitch = atan2(lt.y, Vector2(lt.x, lt.z).length())
		else:
			rotation.y += clamp(wrapf(desired_yaw - rotation.y, -PI, PI) * t, -max_step, max_step)
		var pitch = camera.rotation.x + clamp((desired_pitch - camera.rotation.x) * t, -max_step, max_step)
		camera.rotation.x = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))

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
		# Up through a hatch: at the top, hop off backwards onto the floor.
		if ladder.hatch and push > 0.3 and global_position.y > ladder.global_position.y + ladder.height - 1.0:
			velocity = ladder.outward_normal * 5.0 + Vector3(0, 3.5, 0)
			ladder_contacts.clear()
			ladder_hop_t = 0.4
			return
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
		forward -= _up() * forward.dot(_up())
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

	# ---- Huss Royale: sky drop ----
	# Low gravity and a capped fall speed until you land (or 15s are up).
	func _update_glide() -> void :
		if is_on_floor() or is_dead or main_manager.royale_time >= main_manager.ROYALE_GLIDE_TIME:
			gliding = false
			gravity_mult = base_gravity
			if is_local_player() and is_on_floor():
				main_manager.log_console("[Royale] Landed! Grab a sword or shield.")
			return
		gravity_mult = main_manager.ROYALE_GLIDE_GRAVITY
		velocity.y = max(velocity.y, -main_manager.ROYALE_GLIDE_FALL)

	# ---- Huss Royale: sliding ----
	func _start_slide(hv: Vector3) -> void :
		slide_dir = hv.normalized()
		slide_speed = max(hv.length(), sprint_speed) * main_manager.SLIDE_BOOST
		slide_t = main_manager.SLIDE_TIME

	# A quick burst along the ground that slows down; you can steer a little,
	# and jumping out of it keeps your speed.
	func _process_slide(delta: float) -> void :
		slide_t -= delta
		if not is_on_floor():
			velocity.y -= 20.0 * gravity_mult * delta
		var k = clamp(slide_t / main_manager.SLIDE_TIME, 0.0, 1.0)
		var spd = lerp(walk_speed * 0.8, slide_speed, k)
		var input_dir = Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
		input_dir += _mobile_move_dir()
		var want = transform.basis * input_dir
		want.y = 0.0
		if want.length() > 0.1:
			slide_dir = slide_dir.lerp(want.normalized(), clamp(2.5 * delta, 0.0, 1.0)).normalized()
		velocity.x = slide_dir.x * spd
		velocity.z = slide_dir.z * spd
		if velocity.y > 1.0 or slide_t <= 0.0:
			slide_t = 0.0 # jumped out of it, or it's over
			slide_cd = main_manager.SLIDE_COOLDOWN
		move_and_slide()
		_send_p2p_position()

	# ---- Huss Royale: first-person hands holding your sword / shield ----
	func _fp_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> void :
		var mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = pos
		mi.rotation = rot
		mi.material_override = mat
		parent.add_child(mi)

	func _build_fp_rig() -> void :
		if fp_rig or not camera or not body:
			return
		fp_rig = Node3D.new()
		fp_rig.name = "FPRig"
		camera.add_child(fp_rig)
		var arm_r = body.group_mats.get("arm_r", base_material)
		var arm_l = body.group_mats.get("arm_l", base_material)
		var forearm = CapsuleMesh.new()
		forearm.radius = 0.045
		forearm.height = 0.42
		var fist = SphereMesh.new()
		fist.radius = 0.055
		fist.height = 0.11
		# Right hand: fist at the pivot, forearm running back toward the
		# bottom-right of the screen, the weapon up and forward.
		fp_sword = Node3D.new()
		fp_sword.name = "FPSword"
		fp_sword.position = Vector3(0.33, -0.36, -0.62)
		fp_rig.add_child(fp_sword)
		_fp_mesh(fp_sword, forearm, Vector3(0.07, -0.13, 0.13), Vector3(-0.85, 0.0, 0.45), arm_r)
		_fp_mesh(fp_sword, fist, Vector3.ZERO, Vector3.ZERO, arm_r)
		# Left hand: the shield held out in front, face forward.
		fp_shield = Node3D.new()
		fp_shield.name = "FPShield"
		fp_shield.position = Vector3(-0.4, -0.4, -0.62)
		fp_rig.add_child(fp_shield)
		_fp_mesh(fp_shield, forearm, Vector3(-0.06, -0.12, 0.16), Vector3(-0.85, 0.0, -0.4), arm_l)
		for n in fp_rig.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_update_fp_rig_gear()

	# How each item sits in your first-person hands: [position, rotation, scale].
	const FP_ITEM_POSE: Dictionary = {
		"melee": [Vector3.ZERO, Vector3(128, 0, -14), 0.85], # blade up and forward
		"plasma": [Vector3.ZERO, Vector3(124, 0, -12), 0.72],
		"bow": [Vector3(-0.04, 0.02, 0.0), Vector3(92, 10, 0), 0.75],
		"rifle": [Vector3(-0.08, 0.05, 0.04), Vector3(92, 7, 0), 0.95],
		"raygun": [Vector3(-0.03, 0.03, 0.0), Vector3(92, 7, 0), 1.0],
		"shield": [Vector3(0.02, 0.02, -0.04), Vector3(-72, 38, 0), 0.62], # face forward, turned in a bit
		"ballistic": [Vector3(0.06, 0.1, -0.05), Vector3(-82, 30, 0), 0.6],
	}

	func _update_fp_rig_gear() -> void :
		if not fp_rig or not main_manager:
			return
		var g = main_manager.gear_of(peer_id)
		var show = main_manager.is_royale and not main_manager.third_person and not is_dead
		fp_rig.visible = show
		var melee = String(g.get("melee", ""))
		var ranged = String(g.get("ranged", ""))
		var right = melee
		if ranged != "" and (weapon_mode == "ranged" or melee == ""):
			right = ranged
		var shield = String(g.get("shield", ""))
		_fp_set_item(fp_sword, right)
		_fp_set_item(fp_shield, shield)
		fp_sword.visible = right != ""
		fp_shield.visible = shield != ""

	func _fp_set_item(hand: Node3D, type: String) -> void :
		var old = hand.get_node_or_null("Item")
		if old and String(old.get_meta("type", "")) == type:
			return
		if old:
			hand.remove_child(old)
			old.queue_free()
		if type == "":
			return
		var it = MannequinBody.make_gear(type)
		it.name = "Item"
		it.set_meta("type", type)
		var key = type
		if type == "sun_bow":
			key = "bow"
		elif not FP_ITEM_POSE.has(type):
			key = "shield" if String(main_manager.GEAR.get(type, {}).get("slot", "")) == "shield" else "melee"
		var pose: Array = FP_ITEM_POSE[key]
		it.position = pose[0]
		it.rotation_degrees = pose[1]
		it.scale = Vector3.ONE * float(pose[2])
		hand.add_child(it)
		for n in it.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _animate_fp_rig(delta: float, punch: float) -> void :
		if not fp_rig.visible:
			return
		var bob = anim_amount * (1.0 - anim_air)
		fp_rig.position = Vector3(sin(anim_phase) * 0.012 * bob, -abs(cos(anim_phase)) * 0.018 * bob, 0.0)
		fp_rig.rotation.z = lerp(fp_rig.rotation.z, 0.18 * slide_blend, clamp(delta * 10.0, 0.0, 1.0))
		fp_recoil = move_toward(fp_recoil, 0.0, delta * 6.0)
		if weapon_mode == "ranged" and main_manager.gear_slot(peer_id, "ranged") != "":
			# Aiming: the bow / gun comes in toward the middle; a kick on each shot.
			fp_sword.position = Vector3(0.24, -0.3 + 0.03 * fp_recoil, -0.55 + 0.09 * fp_recoil)
			fp_sword.rotation = Vector3(0.14 * fp_recoil, 0.0, 0.0)
		else:
			# E: pull the weapon back, then thrust it forward.
			var wind = anim_windup * (1.0 - punch)
			fp_sword.position = Vector3(0.33 - 0.08 * punch, -0.36 + 0.05 * wind, -0.62 + 0.1 * wind - 0.28 * punch)
			fp_sword.rotation = Vector3(0.35 * wind - 0.95 * punch, 0.0, 0.0)
		fp_shield.position = Vector3(-0.4 + 0.06 * anim_windup, -0.4 + 0.04 * anim_windup, -0.62)

	# ---- Huss Royale bots ----
	# Run on the match host. They glide down like everyone else, grab swords,
	# shields and Regen crystals, chase the nearest player (or bot) and attack
	# like the practice bot: hold the target for a moment, then hit or miss -
	# how often they miss comes from the room's average ELO. They sprint and
	# jump (and climb ladders) from the start.
	func _rbot_sight() -> float:
		return (38.0 if bot_level >= 4 else 26.0) + (16.0 if main_manager.gear_slot(peer_id, "ranged") != "" else 0.0)

	func _rbot_windup_time() -> float:
		return 0.75 if bot_level >= 4 else 0.9

	func _rbot_cooldown() -> float:
		return 2.2 if bot_level >= 4 else 3.0

	func _process_royale_bot(delta: float) -> void :
		if main_manager.is_moon():
			_process_moon_bot(delta)
			return
		net_has_target = false
		if is_dead:
			return
		if not is_on_floor():
			velocity.y -= 20.0 * gravity_mult * delta
		if gliding:
			_update_glide()
		if is_launching:
			launch_timer -= delta
			var ld = (launch_target_pos - global_position).normalized()
			velocity = ld * 32.0 + _up() * 3.0
			move_and_slide()
			if launch_timer <= 0.0:
				is_launching = false
			return
		if bot_windup > 0.0:
			_rbot_process_windup(delta)
			move_and_slide()
			return
		if is_movement_locked:
			# Held by someone's attack (or failsafe after 6s).
			lock_failsafe_timer -= delta
			if lock_failsafe_timer <= 0.0:
				lock_sources.clear()
				is_movement_locked = false
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			return
		if gliding:
			# Steer toward the landing spot it picked.
			var to = glide_target - global_position
			to.y = 0.0
			var want = to.normalized() * walk_speed if to.length() > 1.5 else Vector3.ZERO
			velocity.x = lerp(velocity.x, want.x, 0.1)
			velocity.z = lerp(velocity.z, want.z, 0.1)
			if want.length() > 0.1:
				rotation.y = lerp_angle(rotation.y, atan2(-want.x, -want.z), 4.0 * delta)
			move_and_slide()
			return

		bot_attack_cd -= delta
		ranged_cd -= delta
		rb_think -= delta
		if rb_think <= 0.0:
			rb_think = 0.25 if bot_level >= 4 else 0.45
			_rbot_think()
		var t = rb_target
		if t and (not is_instance_valid(t) or t.is_dead):
			rb_target = null
			t = null
		if t and bot_attack_cd <= 0.0 and not t.gliding and _bot_can_hit(t):
			_rbot_start_attack(t)
			move_and_slide()
			return
		if t:
			_rbot_try_shoot(t)

		var desired = Vector3.ZERO
		var dest = t.global_position if t else rb_goal
		if t and global_position.distance_to(t.global_position) < 2.0:
			_bot_face(t.global_position, delta) # close enough: square up
		else:
			rb_repath -= delta
			if rb_repath <= 0.0 or rb_path_i >= rb_path.size():
				_rbot_plan(dest)
			var wp = dest
			if rb_path_i < rb_path.size():
				wp = rb_path[rb_path_i]
				var flat = Vector2(wp.x - global_position.x, wp.z - global_position.z)
				var dy = wp.y - global_position.y
				# Reached it (a drop down a ledge counts once we're over the edge).
				if flat.length() < (0.8 if rb_sprinting else 0.5) and (abs(dy) < 1.6 or (dy < 0.0 and get_active_ladder() == null)):
					rb_path_i += 1
					if rb_path_i < rb_path.size():
						wp = rb_path[rb_path_i]
			var to2 = Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
			if to2.length() > 0.3:
				desired = to2.normalized() * (sprint_speed if rb_sprinting else walk_speed)
		if ladder_hop_t > 0.0:
			ladder_hop_t -= delta
		else:
			velocity.x = lerp(velocity.x, desired.x, friction)
			velocity.z = lerp(velocity.z, desired.z, friction)
		if desired.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-desired.x, -desired.z), 10.0 * delta)
		var ladder = get_active_ladder()
		if ladder:
			# On a ladder: climb toward the next waypoint (up into the wall, or
			# down by leaning away from it).
			var climb = desired.normalized() if desired.length() > 0.1 else Vector3.ZERO
			if rb_path_i < rb_path.size():
				var ldy = rb_path[rb_path_i].y - global_position.y
				if ldy > 1.0:
					climb = -ladder.outward_normal
				elif ldy < -1.0:
					climb = ladder.outward_normal
			_apply_ladder_climb(ladder, climb, false)
		elif is_on_floor() and rb_sprinting and desired.length() > 0.1:
			# Sprint-hops now and then, like players do.
			rb_hop -= delta
			if rb_hop <= 0.0:
				rb_hop = randf_range(2.5, 6.0)
				velocity.y = jump_velocity * 1.2
				bot_jumps += 1
		move_and_slide()

		# Barely moved for a moment while trying to: jump and re-plan.
		rb_stuck_t += delta
		if rb_stuck_t >= 0.8:
			if desired.length() > 0.1 and global_position.distance_to(rb_last_pos) < 0.4:
				if is_on_floor():
					velocity.y = jump_velocity * 1.2
					bot_jumps += 1
				rb_repath = 0.0
				if rb_roaming:
					rb_goal = main_manager.bot_roam_point(self)
			rb_last_pos = global_position
			rb_stuck_t = 0.0
		rb_pick_t -= delta
		if rb_pick_t <= 0.0:
			rb_pick_t = 0.15
			main_manager.royale_bot_pickups(self)

	# Pick who to fight (the nearest living player or bot, sticking with the
	# current one), else go for gear, else roam. The storm comes first.
	func _rbot_think() -> void :
		var safe = main_manager.storm_safe_goal(global_position)
		if not (safe is Vector3):
			safe = main_manager.bot_hazard_goal(self)
		if safe is Vector3:
			if rb_roaming or not rb_goal.is_equal_approx(safe):
				rb_repath = 0.0
			rb_goal = safe
			rb_target = null
			rb_roaming = false
			rb_sprinting = true
			return
		var best: NetworkPlayer = null
		var best_d = _rbot_sight()
		for c in get_parent().get_children():
			if c is NetworkPlayer and c != self and not c.is_dead and not c.gliding:
				if main_manager.is_moon() and c.global_position.length() > main_manager.MOON_R + 6.0:
					continue
				var d = global_position.distance_to(c.global_position)
				if c == rb_target:
					d -= 4.0
				if d < best_d:
					best_d = d
					best = c
		if best and main_manager.storm_outside(best.global_position, -4.0):
			best = null # don't chase anyone into the storm
		var item = main_manager.royale_bot_wanted_item(self)
		if best and item is Vector3:
			# grab a weapon lying close by first, unless the fight is right here
			var item_d = global_position.distance_to(item)
			if item_d < 12.0 and best_d > item_d + 4.0:
				best = null
		if best != rb_target:
			rb_repath = 0.0
		rb_target = best
		if best:
			rb_sprinting = true
			rb_roaming = false
			return
		if item is Vector3:
			if not rb_goal.is_equal_approx(item):
				rb_repath = 0.0
			rb_goal = item
			rb_sprinting = true
			rb_roaming = false
			return
		if not rb_roaming or global_position.distance_to(rb_goal) < 3.0 or main_manager.storm_outside(rb_goal, -6.0):
			rb_goal = main_manager.bot_roam_point(self)
			rb_roaming = true
			rb_repath = 0.0
		rb_sprinting = bot_level >= 4

	func _rbot_plan(dest: Vector3) -> void :
		rb_path = main_manager.rnav_path(global_position, dest)
		if rb_path.is_empty():
			rb_path = PackedVector3Array([dest]) # no grid yet / no way: head straight there
			rb_path_i = 0
		else:
			rb_path_i = 1 if rb_path.size() > 1 else 0
		rb_repath = 0.4 if rb_target else 1.5

	# Like a player's QTE: the target is held while the bot "times" its hit.
	func _rbot_start_attack(t: NetworkPlayer) -> void :
		bot_target = t
		bot_windup = _rbot_windup_time()
		bot_attack_started_ms = main_manager._now_ms()
		qte_active = true
		qte_target_peer = t.peer_id
		velocity.x = 0.0
		velocity.z = 0.0
		if t.is_bot or t.is_local_player():
			t.add_movement_lock(peer_id)
		main_manager.send_p2p_packet({"action": "qte_start", "attacker": str(peer_id), "target": str(t.peer_id)})

	func _rbot_process_windup(delta: float) -> void :
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		var t = bot_target
		if t == null or not is_instance_valid(t) or t.is_dead or not qte_active:
			_rbot_end_attack(false, true)
			return
		_bot_face(t.global_position, delta)
		bot_windup -= delta
		if bot_windup <= 0.0:
			_rbot_end_attack(randf() >= bot_miss, false)

	func _rbot_end_attack(hit: bool, cancelled: bool) -> void :
		var t = bot_target
		bot_windup = 0.0
		bot_target = null
		qte_active = false
		qte_target_peer = -1
		bot_attack_cd = _rbot_cooldown()
		var mm = main_manager
		if t and is_instance_valid(t):
			if t.is_bot or t.is_local_player():
				t.remove_movement_lock(peer_id)
			mm.send_p2p_packet({"action": "qte_end", "attacker": str(peer_id), "target": str(t.peer_id)})
		if cancelled or t == null or not is_instance_valid(t) or t.is_dead or is_dead:
			return
		if not hit:
			bot_misses += 1
			if t.is_local_player():
				mm.log_console("[Royale] " + String(mm.player_nicknames.get(peer_id, "A bot")) + " (bot) missed you!")
			return
		bot_hits += 1
		var dmg = mm.gear_damage(peer_id, t.peer_id, mm.melee_base(peer_id))
		is_launching = true
		launch_timer = 0.45
		launch_target_pos = t.global_position
		mm.send_p2p_packet({"action": "take_damage", "peer_id": str(t.peer_id), "amount": dmg})
		mm.send_p2p_packet({"action": "trigger_cooldown", "peer_id": str(t.peer_id)})
		if t.is_local_player():
			mm.start_combat_cooldown()
			mm.log_console("[Royale] " + String(mm.player_nicknames.get(peer_id, "A bot")) + " (bot) hit you for " + str(dmg) + "!")
		elif t.is_bot:
			t.bot_attack_cd = max(t.bot_attack_cd, 1.5)
		t.apply_damage(dmg) # may end the match - nothing after this

	# Someone and this bot attacked each other at the same moment.
	func _rbot_clashed(opp: NetworkPlayer) -> void :
		if main_manager.is_host_peer and (bot_windup > 0.0 or bot_target != null):
			_rbot_end_attack(false, true)
		qte_active = false
		qte_target_peer = -1
		lock_sources.clear()
		is_movement_locked = false
		bot_attack_cd = max(bot_attack_cd, _rbot_cooldown())
		if opp:
			var away = global_position - opp.global_position
			away.y = 0.0
			if away.length() < 0.01:
				away = global_transform.basis.z
				away.y = 0.0
			is_launching = true
			launch_timer = 0.45
			launch_target_pos = global_position + away.normalized() * 20.0

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
		if main_manager and main_manager.is_moon():
			_moon_face(target - global_position, delta)
			return
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
		var reach = BOT_ATTACK_RANGE
		if is_bot and main_manager:
			reach = max(BOT_ATTACK_RANGE, main_manager.melee_reach(peer_id) - 1.5) # Plasma Sword reaches further
		if global_position.distance_to(target.global_position) > reach:
			return false
		if abs((target.global_position - global_position).dot(_up())) > 2.5:
			return false
		var q = PhysicsRayQueryParameters3D.create(global_position + _up() * 1.5, target.global_position + target._up() * 0.9) # (own "up": the Moon is round)
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var hit = get_world_3d().direct_space_state.intersect_ray(q)
		return hit.get("collider") == target

	# You and the bot "pressed E" at the same moment (within CLASH_WINDOW_MS):
	# same as two players clashing - both attacks are cancelled and you're
	# both flung apart.
	func _bot_clash(player: NetworkPlayer) -> void :
		if bot_windup > 0.0 or (qte_active and bot_target != null):
			_bot_end_attack(false, true)
		player.trigger_repulse_clash(self, true)
		trigger_repulse_clash(player, true)
		main_manager.log_console("[Practice] You and the dummy pressed E at the same time - clash! You're both flung back.")
		bot_attack_cd = BOT_ATTACK_COOLDOWN
		bot_clashes += 1
		_set_bot_status("")

	# Like a player's QTE: the target is held while the bot "times" its hit.
	func _bot_start_attack(target: NetworkPlayer) -> void :
		bot_target = target
		bot_windup = BOT_WINDUP
		bot_attack_started_ms = main_manager._now_ms()
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

		# You started a QTE on the bot just as its own attack was ready: the bot
		# "pressed E" at the same time -> clash.
		if is_movement_locked and health > 0 and level >= 3 and bot_attack_cd <= 0.0 and not main_manager.is_game_over:
			var you = main_manager.get_local_player()
			if you and you.qte_active and you.qte_target_peer == peer_id and main_manager._now_ms() - you.qte_started_ms <= main_manager.CLASH_WINDOW_MS and _bot_can_hit(you):
				_bot_clash(you)
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

	func _send_p2p_position(force: bool = false) -> void :
		if main_manager.is_royale and not force:
			# up to 15 players: 20 updates a second each is plenty
			var now = main_manager._now_ms()
			if now - last_pos_send_ms < main_manager.ROYALE_POS_SEND_MS:
				return
			last_pos_send_ms = now
		var pkt = {
			"action": "move",
			"peer_id": str(peer_id),
			"pos_x": global_position.x,
			"pos_y": global_position.y,
			"pos_z": global_position.z,
			"rot_y": rotation_degrees.y
		}
		if main_manager.is_royale:
			if main_manager.is_moon():
				var q = global_transform.basis.get_rotation_quaternion()
				pkt["q"] = [snappedf(q.x, 0.001), snappedf(q.y, 0.001), snappedf(q.z, 0.001), snappedf(q.w, 0.001)]
			if gliding:
				pkt["gl"] = 1
			if slide_t > 0.0:
				pkt["sl"] = 1
		main_manager.send_p2p_packet(pkt)

	func is_in_camera_vision(target: NetworkPlayer) -> bool:
		if not camera:
			return false

		var target_pos = target.global_position + target._up() * 0.9 # (its own "up": the Moon is round)
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
		var min_distance: float = main_manager.melee_reach(peer_id) # 6m (Plasma Sword: 9m)

		for child in players_container.get_children():
			if child is NetworkPlayer and child != self and not child.is_dead and not child.gliding and not main_manager.is_teammate(child.peer_id, peer_id):
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
		for m in body_materials:
			if m:
				m.next_pass = outline_material if active else null
		if hussing_label:
			hussing_label.visible = active

	func trigger_repulse_clash(opp: NetworkPlayer, quiet: bool = false) -> void:
		if is_bot:
			_rbot_clashed(opp)
			return
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
			repulse_dir -= _up() * repulse_dir.dot(_up())
			if repulse_dir.length() < 0.01:
				# Standing on top of each other: push along our own back direction.
				repulse_dir = global_transform.basis.z
				repulse_dir -= _up() * repulse_dir.dot(_up())
			repulse_dir = repulse_dir.normalized()
			is_launching = true
			launch_timer = 0.45
			# Target is farther than the launch can travel (32 u/s * 0.45s), so the
			# fling direction never flips mid-flight.
			launch_target_pos = global_position + repulse_dir * 20.0

		if not quiet:
			main_manager.log_console("[Combat] Simultaneous attack clash! Both players repelled!")

	func _start_qte() -> void :
		if main_manager.is_royale:
			ranged_mode_t = 0.0
			set_weapon_mode("melee")
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
		qte_started_ms = main_manager._now_ms()
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
			if targeted_opponent.is_bot:
				targeted_opponent.add_movement_lock(peer_id) # (only matters on the host)
			else:
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
		if not _e_down():
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

		qte_progress += delta * QTE_SPEED * qte_direction
		if qte_progress >= 1.0:
			qte_progress = 1.0
			qte_direction = -1.0
		elif qte_progress <= 0.0:
			qte_progress = 0.0
			qte_direction = 1.0

		if qte_indicator:
			qte_indicator.position.x = qte_progress * (400 - 8)

		if qte_e_released and _e_down():
			_evaluate_qte()

	func _evaluate_qte() -> void :
		qte_active = false
		qte_target_peer = -1
		main_manager.is_qte_in_progress = false

		if qte_canvas:
			qte_canvas.queue_free()
			qte_canvas = null

		if targeted_opponent:
			if targeted_opponent.is_bot:
				targeted_opponent.remove_movement_lock(peer_id)
			else:
				targeted_opponent.is_movement_locked = false
			if not main_manager.is_single_player:
				main_manager.send_p2p_packet({
					"action": "qte_end",
					"attacker": str(peer_id),
					"target": str(targeted_opponent.peer_id)
				})

		main_manager.start_combat_cooldown()

		var base_hit = main_manager.melee_base(peer_id) # 25 (40 with a Genie wish)
		var damage = base_hit * 2 if qte_double_damage else base_hit
		if targeted_opponent:
			damage = main_manager.gear_damage(peer_id, targeted_opponent.peer_id, damage) # Royale sword / shield
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
				main_manager.log_console("[Combat] " + ("DOUBLE DAMAGE strike" if damage >= 50 else "Precision strike") + " landed on " + targeted_opponent.name_label.text + "!" + (" (" + str(damage) + " damage)" if damage != 25 and damage != 50 else ""))
		else:
			main_manager.log_console("[Combat] Timing missed! Cooldown triggered.")
