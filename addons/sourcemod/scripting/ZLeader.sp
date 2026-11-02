#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <regex>
#include <clientprefs>
#include <multicolors>
#include <zombiereloaded>
#include <zleader>
#include "utilshelper.inc"

#undef REQUIRE_PLUGIN
#tryinclude <vip_core>
#tryinclude <ccc>
#tryinclude <basecomm>
#tryinclude <sourcecomms>
#tryinclude <mapchooser_extended>
#define REQUIRE_PLUGIN

#pragma newdecls required

ConVar g_cvGlowLeader,
	g_cvNeonLeader,
	g_cvTrailPosition,
	g_cvEnableVIP,
	g_cvCooldown,
	g_cvMarkerNumber,
	g_cvTracers,
	g_cvMarkerTime,
	g_cvRemoveNomOnMute;

int g_Serial_Beacon = 0,
	g_Serial_Ping = 0,
	g_BeamSprite = -1,
	g_HaloSprite = -1,
	g_iSpriteLaser = -1,
	g_iMaximumMarker,
	g_iPingColor[MAXPLAYERS + 1][4],
	g_iMarkerPos[MAXPLAYERS + 1] = { MK_TYPE_CROSSHAIR, ... },
	// Entity references (EntIndexToEntRef), never raw indexes
	g_iSpriteFollow[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... },
	g_iSpriteLeader[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... },
	g_iPlayerNeon[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... },
	g_iNeonEntities[MK_TOTAL][MAXPLAYERS + 1],
	g_iMarkerEntities[MK_TOTAL][MAXPLAYERS + 1],
	g_iClientMarker[MK_TOTAL][MAXPLAYERS + 1],
	g_iMarkerInUse[MAXPLAYERS + 1],
	g_iMarkerGen[MAXPLAYERS + 1],
	g_iClientGetVoted[MAXPLAYERS + 1],
	g_iClientVoteWhom[MAXPLAYERS + 1] = { -1, ... },
	g_iClientLeaderSlot[MAXPLAYERS + 1] = { -1, ... },
	g_TrailModel[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... },
	g_BeaconSerial[MAXPLAYERS + 1] = {0, ... },
	g_PingSerial[MAXPLAYERS + 1] = {0, ... },
	g_iClientSprite[MAXPLAYERS + 1] = {-1, ...},
	g_iClientNextVote[MAXPLAYERS + 1] = { -1, ... },
	g_iButtonMarkerCount[MAXPLAYERS + 1] = {0, ... },
	g_iButtonPingCount[MAXPLAYERS + 1] = {0, ... },
	g_iCurrentLeader[MAXLEADER] = { -1, ... };

bool g_bLate,
	g_bPlugin_ccc,
	g_bPlugin_vipcore,
	g_Plugin_BaseComm,
	g_bPlugin_SourceCommsPP,
	g_bPlugin_MCE,
	g_bNeonLeader,
	g_bGlowLeader,
	g_bTracers,
	g_bVIPGroups,
	g_bBlockLeaderChat,
	g_bShorcut[MAXPLAYERS + 1] = { true, ... },
	g_bPingSound[MAXPLAYERS + 1] = { true, ... },
	g_bClientLeader[MAXPLAYERS + 1],
	g_bTrailActive[MAXPLAYERS + 1] = { false, ... },
	g_bBeaconActive[MAXPLAYERS + 1] = { false, ... },
	g_bTracersActive[MAXPLAYERS + 1] = { false, ... },
	g_bAttack3Held[MAXPLAYERS + 1] = { false, ... },
	g_bSuicideSpectate[MAXPLAYERS + 1] = { false, ... },
	g_bResignedByAdmin[MAXPLAYERS + 1] = { false, ... };

char g_sTrailPosition[64],
	g_sColorName[MAXPLAYERS + 1][64],
	g_sColorChat[MAXPLAYERS + 1][64],
	g_sSteamIDs2[MAXPLAYERS+1][MAX_AUTHID_LENGTH];

char g_sMarkerTypes[MK_TOTAL][32] = { "MK_NORMAL", "MK_DEFEND", "MK_ZMTP", "MK_NOHUG", "MK_PING" };
char g_sEntityTypes[ENTITIES_PER_MK][32] = { "prop_dynamic", "light_dynamic", "env_sprite" };

// Radio commands relayed to the CTs; each message is the phrase "Radio <command>"
char g_sRadioCommands[][] = {
	"compliment", "coverme", "cheer", "takepoint", "holdpos", "regroup", "followme", "takingfire",
	"thanks", "go", "fallback", "sticktog", "getinpos", "stormfront", "report", "roger",
	"enemyspot", "needbackup", "sectorclear", "inposition", "reportingin", "getout", "negative", "enemydown"
};

float g_fPingPos[MAXPLAYERS + 1][3],
	g_fPingNextTime[MAXPLAYERS + 1],
	g_fTracerTime[MAXPLAYERS + 1],
	g_fTracerWidth[MAXPLAYERS + 1],
	g_fPingCooldown,
	g_fMarkerTime;

Cookie g_hZLeaderSettings;

StringMap g_smLeaderAuth;

GlobalForward g_hSetClientLeaderForward,
	g_hRemoveClientLeaderForward;

// Slots are the order of the leaders in configs.txt
enum struct LeaderData {
	char L_Codename[48];

	char L_TrailVMT[PLATFORM_MAX_PATH];
	char L_CodeNameVMT[PLATFORM_MAX_PATH];
	char L_FollowVMT[PLATFORM_MAX_PATH];
	char L_MarkerMDL[PLATFORM_MAX_PATH];
	char L_MarkerVMT[PLATFORM_MAX_PATH];

	char L_MarkerArrowVMT[PLATFORM_MAX_PATH];
	int L_iColorArrow[4];

	char L_MarkerZMTP_VMT[PLATFORM_MAX_PATH];
	int L_iColorZMTP[4];

	char L_MarkerNOHUG_VMT[PLATFORM_MAX_PATH];
	int L_iColorNOHUG[4];

	char L_MarkerDefend_VMT[PLATFORM_MAX_PATH];
	int L_iColorDefend[4];

	char L_MarkerPing_VMT[PLATFORM_MAX_PATH];
	int L_iColorPing[4];
	char L_MarkerPing_Sound[PLATFORM_MAX_PATH];

	float L_TracerTime;
	float L_TracerWidth;
}

LeaderData g_LeaderData[MAXLEADER];

int g_iTotalLeader;

public Plugin myinfo = {
	name = "ZLeader Remake",
	author = "Original by AntiTeal, nuclear silo, CNTT, colia || Remake by Oylsister, .Rushaway",
	description = "Allows for a human to be a leader, and give them special functions with it.",
	version = ZLeader_VERSION,
	url = "https://github.com/oylsister/ZLeader-Remake"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLate = late;
	CreateNative("ZL_SetLeader", Native_SetLeader);
	CreateNative("ZL_IsClientLeader", Native_IsClientLeader);
	CreateNative("ZL_RemoveLeader", Native_RemoveLeader);
	CreateNative("ZL_GetClientLeaderSlot", Native_GetClientLeaderSlot);
	CreateNative("ZL_IsLeaderSlotFree", Native_IsLeaderSlotFree);
	CreateNative("ZL_IsPossibleLeader", Native_IsPossibleLeader);

	g_hSetClientLeaderForward = new GlobalForward("Leader_SetClientLeader", ET_Ignore, Param_Cell, Param_String);
	g_hRemoveClientLeaderForward = new GlobalForward("Leader_RemoveClientLeader", ET_Ignore, Param_Cell, Param_Cell);

	MarkNativeAsOptional("CCC_GetColorKey");
	RegPluginLibrary("zleader");

	return APLRes_Success;
}

public void OnPluginStart() {
	/* TRANSLATIONS */
	LoadTranslations("zleader.phrases.txt");
	LoadTranslations("common.phrases.txt");

	/* PUBLIC COMMANDS */
	RegConsoleCmd("sm_mark", Command_Marker, "Open Marker menu");
	RegConsoleCmd("sm_marker", Command_Marker, "Open Marker menu");
	RegConsoleCmd("sm_leader", Command_Leader, "Take the Leader role");
	RegConsoleCmd("sm_vl", Command_VoteLeader, "Vote for set a leader");
	RegConsoleCmd("sm_voteleader", Command_VoteLeader, "Vote for set a leader");
	RegConsoleCmd("sm_leaders", Command_PossibleLeaders, "Print all possible leaders");
	RegConsoleCmd("sm_currentleader", Command_CurrentLeader, "Print all active leaders");

	/* MARKER COMMANDS TO CREATE BINDS */
	RegConsoleCmd("sm_arrow", Command_Arrow, "Arrow a location");
	RegConsoleCmd("sm_defend", Command_Defend, "Defend a location");
	RegConsoleCmd("sm_zmtp", Command_ZMTP, "ZM Teleport a location");
	RegConsoleCmd("sm_nodoorhug", Command_NoDoorHug, "No Doorhug a location");
	RegConsoleCmd("sm_ping", Command_Ping, "Ping a location");
	RegConsoleCmd("sm_removemarker", Command_RemoveMarkers, "Remove all markers");

	/* ADMINS COMMANDS */
	RegAdminCmd("sm_removeleader", Command_RemoveLeader, ADMFLAG_KICK, "Revome a current leader");
	RegAdminCmd("sm_reloadleaders", Command_ReloadLeaders, ADMFLAG_BAN, "Reload access for leader.ini");

	/* CONVARS */
	g_cvNeonLeader = CreateConVar("sm_zleader_neon", "1", "Put a neon light parented to the leader", _, true, 0.0, true, 1.0);
	g_cvGlowLeader = CreateConVar("sm_zleader_glow", "1", "Put a glow colors effect on the leader", _, true, 0.0, true, 1.0);
	g_cvTrailPosition = CreateConVar("sm_zleader_trail_position", "0.0 0.0 10.0", "The trail position (X Y Z)");
	g_cvEnableVIP = CreateConVar("sm_zleader_vip", "0", "VIP groups can be leader?", _, true, 0.0, true, 1.0);
	g_cvCooldown = CreateConVar("sm_zleader_cooldown", "4", "Cooldown in seconds for ping beam");
	g_cvMarkerNumber = CreateConVar("sm_zleader_marker_number", "0", "Max markers per player [0 or lower: One marker of each type max | 1 or higher: Max markers in total]", _, true, 0.0, true, view_as<float>(MAX_MARKERS));
	g_cvTracers = CreateConVar("sm_zleader_tracers", "1", "Allow leaders to use tracers ? (bullet impact)", _, true, 0.0, true, 1.0);
	g_cvMarkerTime = CreateConVar("sm_zleader_marker_time", "15", "Time to remove marker in seconds", _, true, 1.0);
	g_cvRemoveNomOnMute = CreateConVar("sm_zleader_remove_nominate_onmute", "1", "Remove a player's nomination when they are muted", 0, true, 0.0, true, 1.0);

	AutoExecConfig(true);

	/* HOOK CVARS */
	g_cvNeonLeader.AddChangeHook(OnConVarChanged);
	g_cvGlowLeader.AddChangeHook(OnConVarChanged);
	g_cvTrailPosition.AddChangeHook(OnConVarChanged);
	g_cvEnableVIP.AddChangeHook(OnConVarChanged);
	g_cvCooldown.AddChangeHook(OnConVarChanged);
	g_cvMarkerNumber.AddChangeHook(OnConVarChanged);
	g_cvMarkerTime.AddChangeHook(OnConVarChanged);
	g_cvTracers.AddChangeHook(OnConVarChanged);

	/* INITIALIZE VALUES */
	g_bNeonLeader = g_cvNeonLeader.BoolValue;
	g_bGlowLeader = g_cvGlowLeader.BoolValue;
	g_cvTrailPosition.GetString(g_sTrailPosition, sizeof(g_sTrailPosition));
	g_bVIPGroups = g_cvEnableVIP.BoolValue;
	g_fPingCooldown = g_cvCooldown.FloatValue;
	g_iMaximumMarker = g_cvMarkerNumber.IntValue;
	g_fMarkerTime = g_cvMarkerTime.FloatValue;
	g_bTracers = g_cvTracers.BoolValue;

	if (g_iMaximumMarker > MAX_MARKERS)
		g_iMaximumMarker = MAX_MARKERS;

	g_smLeaderAuth = new StringMap();

	AddCommandListener(HookPlayerChat, "say");
	AddCommandListener(HookPlayerChatTeam, "say_team");
	AddCommandListener(QuickLeaderMenuCommand, "+lookatweapon");
	AddCommandListener(QuickMarkerMenuCommand, "-lookatweapon");

	/* HOOK EVENTS & RADIO */
	AddTempEntHook("Player Decal", HookDecal);
	HookEvent("player_team", OnPlayerTeam, EventHookMode_Post);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	HookEvent("round_end", OnRoundEnd);
	HookEvent("round_start", OnRoundStart);
	HookEvent("bullet_impact", OnBulletImpact, EventHookMode_Post);
	HookRadio();

	/* COOKIES */
	SetCookieMenuItem(ZLeaderCookieHandler, 0, "ZLeader Settings");
	g_hZLeaderSettings = new Cookie("zleader_settings", "ZLeader Settings", CookieAccess_Protected);

	/* ADD FILTERS */
	AddMultiTargetFilter("@leaders", Filter_Leaders, "Possible Leaders", false);
	AddMultiTargetFilter("@!leaders", Filter_NotLeaders, "Everyone but Possible Leaders", false);
	AddMultiTargetFilter("@leader", Filter_Leader, "Current Leader", false);
	AddMultiTargetFilter("@!leader", Filter_NotLeader, "Every one but the Current Leader", false);

	if (!g_bLate)
		return;

	/* Late load */
	char sSteam32ID[32];
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && IsClientAuthorized(i) && GetClientAuthId(i, AuthId_Steam2, sSteam32ID, sizeof(sSteam32ID)))
			OnClientAuthorized(i, sSteam32ID);
	}

	g_bLate = false;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvNeonLeader)
		g_bNeonLeader = g_cvNeonLeader.BoolValue;
	else if (convar == g_cvGlowLeader)
		g_bGlowLeader = g_cvGlowLeader.BoolValue;
	else if (convar == g_cvTrailPosition)
		g_cvTrailPosition.GetString(g_sTrailPosition, sizeof(g_sTrailPosition));
	else if (convar == g_cvEnableVIP)
		g_bVIPGroups = g_cvEnableVIP.BoolValue;
	else if (convar == g_cvCooldown)
		g_fPingCooldown = g_cvCooldown.FloatValue;
	else if (convar == g_cvMarkerNumber)
		g_iMaximumMarker = g_cvMarkerNumber.IntValue;
	else if (convar == g_cvMarkerTime)
		g_fMarkerTime = g_cvMarkerTime.FloatValue;
	else if (convar == g_cvTracers)
		g_bTracers = g_cvTracers.BoolValue;

	if (g_iMaximumMarker > MAX_MARKERS)
		g_iMaximumMarker = MAX_MARKERS;
}

void LoadConfig() {
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/zleader/configs.txt");

	if (!FileExists(sPath)) {
		SetFailState("Couldn't find config file: %s", sPath);
		return;
	}

	KeyValues kv = new KeyValues("zleader");

	if (!kv.ImportFromFile(sPath))
	{
		SetFailState("Couldn't read config file: %s", sPath);
		delete kv;
		return;
	}

	g_iTotalLeader = 0;

	if (kv.GotoFirstSubKey()) {
		do {
			if (g_iTotalLeader >= MAXLEADER) {
				LogError("configs.txt defines more than %d leaders; ignoring the rest.", MAXLEADER);
				break;
			}

			kv.GetString("codename", g_LeaderData[g_iTotalLeader].L_Codename, 48);

			// The whole plugin (and the natives) use the position in this file as the slot
			if (kv.GetNum("leader_slot", g_iTotalLeader) != g_iTotalLeader)
				LogError("configs.txt: \"leader_slot\" of \"%s\" does not match its position (%d), the position is used.", g_LeaderData[g_iTotalLeader].L_Codename, g_iTotalLeader);

			kv.GetString("codename_vmt", g_LeaderData[g_iTotalLeader].L_CodeNameVMT, PLATFORM_MAX_PATH);
			kv.GetString("trail_vmt", g_LeaderData[g_iTotalLeader].L_TrailVMT, PLATFORM_MAX_PATH);
			kv.GetString("follow_vmt", g_LeaderData[g_iTotalLeader].L_FollowVMT, PLATFORM_MAX_PATH);

			kv.GetString("marker_mdl", g_LeaderData[g_iTotalLeader].L_MarkerMDL, PLATFORM_MAX_PATH);
			kv.GetString("marker_vmt", g_LeaderData[g_iTotalLeader].L_MarkerVMT, PLATFORM_MAX_PATH);

			kv.GetString("arrow_vmt", g_LeaderData[g_iTotalLeader].L_MarkerArrowVMT, PLATFORM_MAX_PATH);
			kv.GetColor("arrow_color", g_LeaderData[g_iTotalLeader].L_iColorArrow[0], g_LeaderData[g_iTotalLeader].L_iColorArrow[1], g_LeaderData[g_iTotalLeader].L_iColorArrow[2], g_LeaderData[g_iTotalLeader].L_iColorArrow[3]);

			kv.GetString("defend_vmt", g_LeaderData[g_iTotalLeader].L_MarkerDefend_VMT, PLATFORM_MAX_PATH);
			kv.GetColor("defend_color", g_LeaderData[g_iTotalLeader].L_iColorDefend[0], g_LeaderData[g_iTotalLeader].L_iColorDefend[1], g_LeaderData[g_iTotalLeader].L_iColorDefend[2], g_LeaderData[g_iTotalLeader].L_iColorDefend[3]);

			kv.GetString("zmtp_vmt", g_LeaderData[g_iTotalLeader].L_MarkerZMTP_VMT, PLATFORM_MAX_PATH);
			kv.GetColor("zmtp_color", g_LeaderData[g_iTotalLeader].L_iColorZMTP[0], g_LeaderData[g_iTotalLeader].L_iColorZMTP[1], g_LeaderData[g_iTotalLeader].L_iColorZMTP[2], g_LeaderData[g_iTotalLeader].L_iColorZMTP[3]);

			kv.GetString("nodoorhug_vmt", g_LeaderData[g_iTotalLeader].L_MarkerNOHUG_VMT, PLATFORM_MAX_PATH);
			kv.GetColor("nodoorhug_color", g_LeaderData[g_iTotalLeader].L_iColorNOHUG[0], g_LeaderData[g_iTotalLeader].L_iColorNOHUG[1], g_LeaderData[g_iTotalLeader].L_iColorNOHUG[2], g_LeaderData[g_iTotalLeader].L_iColorNOHUG[3]);

			kv.GetString("ping_vmt", g_LeaderData[g_iTotalLeader].L_MarkerPing_VMT, PLATFORM_MAX_PATH);
			kv.GetColor("ping_color", g_LeaderData[g_iTotalLeader].L_iColorPing[0], g_LeaderData[g_iTotalLeader].L_iColorPing[1], g_LeaderData[g_iTotalLeader].L_iColorPing[2], g_LeaderData[g_iTotalLeader].L_iColorPing[3]);
			kv.GetString("ping_sound", g_LeaderData[g_iTotalLeader].L_MarkerPing_Sound, PLATFORM_MAX_PATH);

			g_LeaderData[g_iTotalLeader].L_TracerTime = kv.GetFloat("tracer_time", 0.7);
			g_LeaderData[g_iTotalLeader].L_TracerWidth = kv.GetFloat("tracer_width", 0.8);

			g_iTotalLeader++;
		}
		while(kv.GotoNextKey());
	}

	delete kv;
}

void LoadDownloadTable() {
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/zleader/downloads.txt");

	if (!FileExists(sPath)) {
		SetFailState("Couldn't find config file: %s", sPath);
		return;
	}

	File file = OpenFile(sPath, "r");
	if (!file) {
		LogError("Couldn't open download list: %s", sPath);
		return;
	}

	char buffer[PLATFORM_MAX_PATH];
	while (!file.EndOfFile()) {
		file.ReadLine(buffer, sizeof(buffer));

		int pos;
		pos = StrContains(buffer, "//");
		if (pos != -1) buffer[pos] = '\0';

		pos = StrContains(buffer, "#");
		if (pos != -1) buffer[pos] = '\0';

		pos = StrContains(buffer, ";");
		if (pos != -1) buffer[pos] = '\0';

		pos = StrContains(buffer, "*");
		if (pos != -1) buffer[pos] = '\0';

		TrimString(buffer);
		if (buffer[0] == '\0') continue;

		AddFileToDownloadsTable(buffer);
	}

	delete file;
}

void PrecacheConfig() {
	for(int i = 0; i < g_iTotalLeader; i++) {
		if (g_LeaderData[i].L_CodeNameVMT[0] != '\0')
			PrecacheGeneric(g_LeaderData[i].L_CodeNameVMT, true);

		if (g_LeaderData[i].L_TrailVMT[0] != '\0')
			PrecacheGeneric(g_LeaderData[i].L_TrailVMT, true);

		if (g_LeaderData[i].L_FollowVMT[0] != '\0')
			PrecacheGeneric(g_LeaderData[i].L_FollowVMT, true);

		if (g_LeaderData[i].L_MarkerMDL[0] != '\0')
			PrecacheModel(g_LeaderData[i].L_MarkerMDL, true);

		if (g_LeaderData[i].L_MarkerVMT[0] != '\0')
			PrecacheGeneric(g_LeaderData[i].L_MarkerVMT, true);

		if (g_LeaderData[i].L_MarkerArrowVMT[0] != '\0')
			PrecacheGeneric(g_LeaderData[i].L_MarkerArrowVMT, true);

		if (g_LeaderData[i].L_MarkerZMTP_VMT[0] != '\0')
			PrecacheGeneric(g_LeaderData[i].L_MarkerZMTP_VMT, true);

		if (g_LeaderData[i].L_MarkerNOHUG_VMT[0] != '\0')
			PrecacheGeneric(g_LeaderData[i].L_MarkerNOHUG_VMT, true);

		if (g_LeaderData[i].L_MarkerDefend_VMT[0] != '\0')
			PrecacheGeneric(g_LeaderData[i].L_MarkerDefend_VMT, true);

		if (g_LeaderData[i].L_MarkerPing_VMT[0] != '\0')
			PrecacheGeneric(g_LeaderData[i].L_MarkerPing_VMT, true);

		if (g_LeaderData[i].L_MarkerPing_Sound[0] != '\0')
			PrecacheSound(g_LeaderData[i].L_MarkerPing_Sound, true);
	}

	// Always precache it so tracers keep working when the cvar gets enabled mid-map
	if ((g_iSpriteLaser = PrecacheModel("materials/sprites/laser.vmt")) == 0)
	{
		LogError("Sprite for laser not precached, tracers disabled");
		g_cvTracers.BoolValue = false;
		g_bTracers = false;
	}
}

/* =========================================================================
||  REMOVE ALL FILTERS / COMMAND LISTENER / CLOSE ALL HANDLES
============================================================================ */
public void OnPluginEnd() {
	// Don't leave trails, sprites, neons and markers attached to players on unload/reload
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && IsClientLeader(i))
			RemoveLeader(i, R_SELFRESIGN, false);
	}

	RemoveMultiTargetFilter("@leaders", Filter_Leaders);
	RemoveMultiTargetFilter("@!leaders", Filter_NotLeaders);
	RemoveMultiTargetFilter("@leader", Filter_Leader);
	RemoveMultiTargetFilter("@!leader", Filter_NotLeader);

	RemoveCommandListener(HookPlayerChat, "say");
	RemoveCommandListener(HookPlayerChatTeam, "say_team");
	RemoveCommandListener(QuickLeaderMenuCommand, "+lookatweapon");
	RemoveCommandListener(QuickMarkerMenuCommand, "-lookatweapon");

	delete g_hSetClientLeaderForward;
	delete g_hRemoveClientLeaderForward;
}

/* =========================================================================
||  EXTERNAL PLUGINS
============================================================================ */
public void OnAllPluginsLoaded() {
	g_bPlugin_vipcore = LibraryExists("vip_core");
	g_bPlugin_ccc = LibraryExists("ccc");
	g_Plugin_BaseComm = LibraryExists("basecomm");
	g_bPlugin_SourceCommsPP = LibraryExists("sourcecomms++");
	g_bPlugin_MCE = LibraryExists("mapchooser");
}

public void OnLibraryRemoved(const char[] name) {
	if (strcmp(name, "vip_core", false) == 0)
		g_bPlugin_vipcore = false;

	else if (strcmp(name, "ccc", false) == 0)
		g_bPlugin_ccc = false;

	else if (strcmp(name, "basecomm", false) == 0)
		g_Plugin_BaseComm = false;

	else if (strcmp(name, "sourcecomms++", false) == 0)
		g_bPlugin_SourceCommsPP = false;

	else if (strcmp(name, "mapchooser", false) == 0)
		g_bPlugin_MCE = false;
}

public void OnLibraryAdded(const char[] name) {
	if (strcmp(name, "vip_core", false) == 0)
		g_bPlugin_vipcore = true;

	else if (strcmp(name, "ccc", false) == 0)
		g_bPlugin_ccc = true;

	else if (strcmp(name, "basecomm", false) == 0)
		g_Plugin_BaseComm = true;

	else if (strcmp(name, "sourcecomms++", false) == 0)
		g_bPlugin_SourceCommsPP = true;

	else if (strcmp(name, "mapchooser", false) == 0)
		g_bPlugin_MCE = true;
}

/* =========================================================================
||  INITIAL SETUP (Cache, dl table, load cfg..)
============================================================================ */
public void OnMapStart() {
	Reset_AllLeaders();
	LoadConfig();
	LoadDownloadTable();
	PrecacheConfig();
	UpdateLeaders();

	GameData GameConf = new GameData("funcommands.games");
	if (!GameConf) {
		SetFailState("Unable to load game config funcommands.games");
		return;
	}

	char buffer[PLATFORM_MAX_PATH];
	if (GameConf.GetKeyValue("SpriteBeam", buffer, sizeof(buffer)) && buffer[0])
		g_BeamSprite = PrecacheModel(buffer);

	if (GameConf.GetKeyValue("SpriteHalo", buffer, sizeof(buffer)) && buffer[0])
		g_HaloSprite = PrecacheModel(buffer);

	delete GameConf;

	char sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	g_bBlockLeaderChat = StrContains(sMap, "ze_collective_css") != -1;
}

/* =========================================================================
||  CLIENT CONNECTING (Index, Cookie, ..)
============================================================================ */
public void OnClientAuthorized(int client, const char[] auth) {

	if (IsFakeClient(client))
		return;

	// No state reset here: the client may already have been voted leader before being authorized,
	// and OnClientDisconnect already cleans everything up for the next player on this index.
	if (AreClientCookiesCached(client))
		ReadClientCookies(client);

	strcopy(g_sSteamIDs2[client], sizeof(g_sSteamIDs2[]), auth);
}

public void OnClientCookiesCached(int client) {
	ReadClientCookies(client);
}

void ParseClientCookie(int client, bool &shortcut, bool &pingSound, int &markerPos) {
	// Default values, also used for the parts missing from a partial cookie
	shortcut = true;
	pingSound = true;
	markerPos = MK_TYPE_CROSSHAIR;

	char buffer[64];
	g_hZLeaderSettings.Get(client, buffer, sizeof(buffer));

	if (buffer[0] == '\0')
		return;

	// Parse chain format: shortcut|pingsound|markerpos
	char parts[3][16];
	int count = ExplodeString(buffer, "|", parts, 3, sizeof(parts[]));

	if (count >= 1) {
		shortcut = view_as<bool>(StringToInt(parts[0]));
	}
	if (count >= 2) {
		pingSound = view_as<bool>(StringToInt(parts[1]));
	}
	if (count >= 3) {
		markerPos = StringToInt(parts[2]);
	}
}

public void ReadClientCookies(int client) {
	bool shortcut, pingSound;
	int markerPos;

	ParseClientCookie(client, shortcut, pingSound, markerPos);

	g_bShorcut[client] = shortcut;
	g_bPingSound[client] = pingSound;
	g_iMarkerPos[client] = markerPos;
}

public void SetClientCookies(int client) {
	if (!client || !IsClientInGame(client) || IsFakeClient(client))
		return;

	// Read current cookie values
	bool currentShortcut, currentPingSound;
	int currentMarkerPos;
	ParseClientCookie(client, currentShortcut, currentPingSound, currentMarkerPos);

	// Check if values have changed
	bool shortcutChanged = g_bShorcut[client] != currentShortcut;
	bool pingSoundChanged = g_bPingSound[client] != currentPingSound;
	bool markerPosChanged = g_iMarkerPos[client] != currentMarkerPos;

	// If no values have changed, no need to save
	if (!shortcutChanged && !pingSoundChanged && !markerPosChanged) {
		return;
	}

	// Otherwise, save the chain format
	char sValue[64];
	FormatEx(sValue, sizeof(sValue), "%d|%d|%d",
		g_bShorcut[client] ? 1 : 0,
		g_bPingSound[client] ? 1 : 0,
		g_iMarkerPos[client]);

	g_hZLeaderSettings.Set(client, sValue);
}

public void ZLeaderCookieHandler(int client, CookieMenuAction action, any info, char[] buffer, int maxlen) {
	switch (action) {
		case CookieMenuAction_SelectOption: {
			ZLeaderSetting(client);
		}
	}
}

public void ZLeaderSetting(int client) {
	Menu menu = new Menu(ZLeaderSettingHandler, MENU_ACTIONS_ALL);

	menu.SetTitle("%T %T", "Menu Prefix", client, "Client Setting", client);

	char shortcut[64], markerpos[64], pingsound[64];
	FormatEx(shortcut, 64, "%T", "Shortcut", client);
	FormatEx(markerpos, 64, "%T", "Marker Pos", client);
	FormatEx(pingsound, 64, "%T", "Ping Sound", client);

	menu.AddItem("shortcut", shortcut);
	menu.AddItem("markerpos", markerpos);
	menu.AddItem("pingsound", pingsound);

	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ZLeaderSettingHandler(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_DisplayItem: {
			char info[64], display[64];
			menu.GetItem(param2, info, sizeof(info));
			if (strcmp(info, "shortcut", false) == 0) {
				FormatEx(display, sizeof(display), "%T : %T", "Shortcut", param1, g_bShorcut[param1] ? "Enabled" : "Disabled", param1);
				return RedrawMenuItem(display);
			} else if (strcmp(info, "markerpos", false) == 0) {

				char thepos[64];
				FormatEx(thepos, sizeof(thepos), "%T", g_iMarkerPos[param1] == MK_TYPE_CLIENT ? "Client Position" : "Client Crosshair", param1);
				FormatEx(display, sizeof(display), "%T : %s", "Marker Pos", param1, thepos);
				return RedrawMenuItem(display);
			} else if (strcmp(info, "pingsound", false) == 0) {
				FormatEx(display, sizeof(display), "%T : %T", "Ping Sound", param1, g_bPingSound[param1] ? "Enabled" : "Disabled", param1);
				return RedrawMenuItem(display);
			}
		}
		case MenuAction_Select: {
			char info[64];
			menu.GetItem(param2, info, sizeof(info));
			if (strcmp(info, "shortcut", false) == 0) {
				char status[32];
				g_bShorcut[param1] = !g_bShorcut[param1];
				FormatEx(status, sizeof(status), "%T", g_bShorcut[param1] ? "Enabled Chat" : "Disabled Chat", param1);
				CPrintToChat(param1, "%T %T", "Prefix", param1, "You set shortcut", param1, status);
				SetClientCookies(param1);
			} else if (strcmp(info, "markerpos", false) == 0) {
				g_iMarkerPos[param1] = (g_iMarkerPos[param1] == MK_TYPE_CLIENT) ? MK_TYPE_CROSSHAIR : MK_TYPE_CLIENT;
				CPrintToChat(param1, "%T %T", "Prefix", param1, (g_iMarkerPos[param1] == MK_TYPE_CLIENT) ? "Marker Pos Player Position" : "Marker Pos Crosshair", param1);
				SetClientCookies(param1);
			} else if (strcmp(info, "pingsound", false) == 0) {
				char status[32];
				g_bPingSound[param1] = !g_bPingSound[param1];
				FormatEx(status, sizeof(status), "%T", g_bPingSound[param1] ? "Enabled Chat" : "Disabled Chat", param1);
				CPrintToChat(param1, "%T %T", "Prefix", param1, "You set pingsound", param1, status);
				SetClientCookies(param1);
			}

			ZLeaderSetting(param1);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack)
				ShowCookieMenu(param1);
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

/* =========================================================================
||  Hook Event Stuff
============================================================================ */
public void OnClientDisconnect(int client) {
	if (IsClientLeader(client))
		RemoveLeader(client, R_DISCONNECTED, true);

	// Withdraw the vote this client gave
	int votedFor = GetClientFromSerial(g_iClientVoteWhom[client]);
	if (votedFor != 0 && g_iClientGetVoted[votedFor] > 0)
		g_iClientGetVoted[votedFor]--;

	Reset_PlayerState(client);
	Reset_ClientSettings(client);

	g_sSteamIDs2[client][0] = '\0';
}

public void OnPlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	int iUserID = event.GetInt("userid");
	int client = GetClientOfUserId(iUserID);
	// We need to perform OnPlayerTeam after OnPlayerDeath, to check if leader moved to spec
	if (IsClientLeader(client))
		CreateTimer(0.2, Timer_OnTeamChange, iUserID, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int iUserID = event.GetInt("userid");
	int client = GetClientOfUserId(iUserID);
	if (IsClientLeader(client))
		CreateTimer(0.1, Timer_OnDeath, iUserID, TIMER_FLAG_NO_MAPCHANGE);
}

public void ZR_OnClientInfected(int client, int attacker, bool motherinfect, bool override, bool respawn) {
	if (IsClientLeader(client))
		RemoveLeader(client, R_INFECTED, true);
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast) {
	// We create timer for don't insta remove leader (usefull for API)
	CreateTimer(0.3, Timer_RoundEndClean, _, TIMER_FLAG_NO_MAPCHANGE);
	KillAllBeacons();
	KillAllPingsBeam();
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast) {
	Reset_AllLeaders();
	EnsureLeaderConsistency();

	// Clear resigned-by-admin flags so players can take leader in the new round
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i))
			Reset_ClientResigned(i);
	}
}

public void OnBulletImpact(Event event, const char[] name, bool dontBroadcast) {
	if (!g_bTracers)
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!g_bTracersActive[client])
		return;

	float origin[3], destination[3], adjustedOrigin[3];
	GetClientEyePosition(client, origin);

	destination[0] = event.GetFloat("x");
	destination[1] = event.GetFloat("y");
	destination[2] = event.GetFloat("z");

	float distance = GetVectorDistance(origin, destination);
	float percent = 0.4 / (distance / 100.0);

	adjustedOrigin[0] = origin[0] + (destination[0] - origin[0]) * percent;
	adjustedOrigin[1] = origin[1] + (destination[1] - origin[1]) * percent - 0.08;
	adjustedOrigin[2] = origin[2] + (destination[2] - origin[2]) * percent;

	TE_SetupBeamPoints(adjustedOrigin, destination, g_iSpriteLaser, 0, 0, 0, g_fTracerTime[client], g_fTracerWidth[client], g_fTracerWidth[client] / 2, 1, 0.0, g_iPingColor[client], 0);
	TE_SendToAll();
}

public Action Timer_RoundEndClean(Handle timer) {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i))
			continue;

		Reset_ClientNextVote(i);

		if (IsClientLeader(i))
			RemoveLeader(i, R_SELFRESIGN, false);
	}

	return Plugin_Handled;
}

public Action Timer_OnDeath(Handle timer, int iUserID) {
	int client = GetClientOfUserId(iUserID);
	if (!client || !IsClientInGame(client))
		return Plugin_Stop;

	if (GetClientTeam(client) <= CS_TEAM_SPECTATOR)
		g_bSuicideSpectate[client] = true;

	if (IsClientLeader(client) && !g_bSuicideSpectate[client])
		RemoveLeader(client, R_DIED, true);

	return Plugin_Continue;
}

public Action Timer_OnTeamChange(Handle timer, int iUserID) {
	int client = GetClientOfUserId(iUserID);
	if (!client || !IsClientInGame(client))
		return Plugin_Stop;

	if (IsClientLeader(client) && g_bSuicideSpectate[client]) {
		RemoveLeader(client, R_SPECTATOR, true);
		g_bSuicideSpectate[client] = false;
	}

	return Plugin_Continue;
}

/* =========================================================================
||  Leader Command
============================================================================ */
public Action Command_Leader(int client, int args) {
	SetGlobalTransTarget(client);

	if (args == 0) {
		if (client <= 0 || !IsClientInGame(client)) {
			CReplyToCommand(client, "%T %T", "Prefix", client, "Command is in-game only", client);
			return Plugin_Handled;
		}

		if (IsPlayerAlive(client) && ZR_IsClientHuman(client) && IsClientLeader(client)) {
			LeaderMenu(client);
			return Plugin_Stop;
		}

		if (g_bResignedByAdmin[client]) {
			CReplyToCommand(client, "%t %t", "Prefix", "Leader was resigned by Admin", client);
			return Plugin_Stop;
		}

		if (IsPossibleLeader(client)) {
			if (!IsClientLeader(client)) {
				if (!IsPlayerAlive(client)) {
					CReplyToCommand(client, "%t %t", "Prefix", "Target must be alive");
					return Plugin_Stop;
				}
				if (ZR_IsClientZombie(client)) {
					CReplyToCommand(client, "%t %t", "Prefix", "It's Zombie");
					return Plugin_Stop;
				}
				if (IsTargetMuted(client) || IsTargetGagged(client)) {
					CReplyToCommand(client, "%T %T", "Prefix", client, "Leader should not be muted", client);
					return Plugin_Stop;
				}

				for (int i = 0; i < g_iTotalLeader; i++) {
					if (IsLeaderSlotFree(i)) {
						SetClientLeader(client, _, i);
						LeaderMenu(client);
						return Plugin_Stop;
					}
				}

				CReplyToCommand(client, "%t %t", "Prefix", "Slot is full");
				return Plugin_Stop;
			}
		} else {
			CReplyToCommand(client, "%t {red}%t", "Prefix", "Request Access");
			return Plugin_Handled;
		}
	}

	if (args == 1) {
		char sArgs[64];
		GetCmdArg(1, sArgs, sizeof(sArgs));
		char sTargetName[MAX_TARGET_LENGTH];
		int iTargets[MAXPLAYERS];
		int TargetCount;
		bool TnIsMl;

		if ((TargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS,
			COMMAND_FILTER_CONNECTED | COMMAND_FILTER_ALIVE | COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY, sTargetName, sizeof(sTargetName), TnIsMl)) <= 0)
		{
			/* IF MORE THAN ONE TARGET IN GAME FOUND */
			ReplyToTargetError(client, TargetCount);
			return Plugin_Handled;
		}

		/* IF NO TARGET FOUND */
		if (TargetCount == -1)
			return Plugin_Handled;

		int target = iTargets[0];

		if (target != -1) {
			if (!IsClientAdmin(client)) {
				CReplyToCommand(client, "%t %t", "Prefix", "Unable to target");
				return Plugin_Handled;
			}
			if (!IsClientInGame(target)) {
				CReplyToCommand(client, "%t %t", "Prefix", "Target is not in game");
				return Plugin_Handled;
			}
			if (!IsPlayerAlive(target)) {
				CReplyToCommand(client, "%t %t", "Prefix", "Target must be alive");
				return Plugin_Handled;
			}
			if (ZR_IsClientZombie(target)) {
				CReplyToCommand(client, "%t %t", "Prefix", "It's Zombie");
				return Plugin_Handled;
			}
			if (IsClientLeader(target)) {
				CReplyToCommand(client, "%t %t", "Prefix", "Already Leader", target);
				return Plugin_Handled;
			}
			if (IsTargetMuted(target) || IsTargetGagged(target)) {
				CReplyToCommand(client, "%T %T", "Prefix", client, "Leader should not be muted", client);
				return Plugin_Handled;
			}

			for (int i = 0; i < g_iTotalLeader; i++) {
				if (IsLeaderSlotFree(i)) {
					LogAction(client, target, "[ZLeader] \"%L\" have set leader on \"%L\"", client, target);
					CReplyToCommand(client, "%t %t", "Prefix", "You set client leader", target);
					SetClientLeader(target, client, i);
					LeaderMenu(target);
					return Plugin_Handled;
				}
			}

			CReplyToCommand(client, "%t %t", "Prefix", "Slot is full");
			return Plugin_Stop;
		} else {
			CReplyToCommand(client, "%t %t", "Prefix", "Leader usage");
			return Plugin_Handled;
		}
	}

	if (args > 1) {
		CReplyToCommand(client, "%t %t", "Prefix", "Leader usage");
		return Plugin_Handled;
	}

	return Plugin_Handled;
}

public void LeaderMenu(int client) {
	SetGlobalTransTarget(client);
	Menu menu = new Menu(LeaderMenuHandler, MENU_ACTIONS_ALL);

	if (g_iMaximumMarker < 1) {
		char sActive[256];
		int iActive;

		for (int type = 0; type < MK_TOTAL; type++) {
			if (type == MK_PING || !IsMarkerPlaced(client, type))
				continue;

			char sName[64];
			switch (type) {
				case MK_NORMAL: FormatEx(sName, sizeof(sName), "%T", "Arrow Marker", client);
				case MK_DEFEND: FormatEx(sName, sizeof(sName), "%T", "Defend Here", client);
				case MK_ZMTP:   FormatEx(sName, sizeof(sName), "%T", "ZM Teleport", client);
				case MK_NOHUG:  FormatEx(sName, sizeof(sName), "%T", "No Doorhug", client);
			}

			if (iActive++)
				StrCat(sActive, sizeof(sActive), "\n→ ");

			StrCat(sActive, sizeof(sActive), sName);
		}

		if (iActive)
			menu.SetTitle("%T \n%T\n→ %s", "Menu Leader title", client, "Active Marker", client, sActive);
		else
			menu.SetTitle("%T", "Menu Leader title", client);
	} else
		menu.SetTitle("%T", "Menu Leader title", client);

	char follow[64], trail[64], beacon[64], tracers[64], marker[64], removemarker[64], resign[64];

	FormatEx(follow, 64, "%T", "Follow Me", client);
	FormatEx(trail, 64, "%T", "Toggle Trail", client);
	FormatEx(beacon, 64, "%T", "Toggle Beacon", client);
	if (g_bTracers)
		FormatEx(tracers, 64, "%T", "Toggle Tracers", client);
	FormatEx(marker, 64, "%T", "Place Marker", client);
	FormatEx(removemarker, 64, "%T", "Remove Marker", client);
	FormatEx(resign, 64, "%T", "Resign from Leader", client);

	menu.AddItem("follow", follow);
	menu.AddItem("trail", trail);
	menu.AddItem("beacon", beacon);
	if (g_bTracers)
		menu.AddItem("tracers", tracers);
	menu.AddItem("marker", marker);
	menu.AddItem("removemarker", removemarker);
	menu.AddItem("resign", resign);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int LeaderMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_DisplayItem: {
			char info[64], display[128];
			menu.GetItem(param2, info, sizeof(info));
			if (strcmp(info, "follow", false) == 0 && g_iClientSprite[param1] == SP_FOLLOW) {
				FormatEx(display, sizeof(display), "%T (✘)", "Follow Me", param1);
				return RedrawMenuItem(display);
			} else if (strcmp(info, "trail", false) == 0 && g_bTrailActive[param1]) {
				FormatEx(display, sizeof(display), "%T (✘)", "Toggle Trail", param1);
				return RedrawMenuItem(display);
			} else if (strcmp(info, "beacon", false) == 0 && g_bBeaconActive[param1]) {
				FormatEx(display, sizeof(display), "%T (✘)", "Toggle Beacon", param1);
				return RedrawMenuItem(display);
			} else if (strcmp(info, "tracers", false) == 0 && g_bTracersActive[param1]) {
				FormatEx(display, sizeof(display), "%T (✘)", "Toggle Tracers", param1);
				return RedrawMenuItem(display);
			}
		}

		case MenuAction_Select: {
			if (!IsClientLeader(param1))
				return 0;

			char info[64];
			menu.GetItem(param2, info, sizeof(info));

			if (!ZR_IsClientZombie(param1)) {
				if (strcmp(info, "follow", false) == 0) {
					if (g_iClientSprite[param1] != SP_FOLLOW) {
						RemoveSpriteFollow(param1);
						g_iClientSprite[param1] = SP_FOLLOW;
						int slot = g_iClientLeaderSlot[param1];
						if (IsValidLeaderSlot(slot) && g_LeaderData[slot].L_FollowVMT[0] != '\0')
							g_iSpriteFollow[param1] = AttachSprite(param1, g_LeaderData[slot].L_FollowVMT, 1);
					} else {
						RemoveSpriteFollow(param1);
						Reset_ClientSprite(param1);
					}

					LeaderMenu(param1);
				} else if (strcmp(info, "trail", false) == 0) {
					ToggleTrail(param1);
					LeaderMenu(param1);
				} else if (strcmp(info, "beacon", false) == 0) {
					ToggleBeacon(param1);
					LeaderMenu(param1);
				} else if (strcmp(info, "tracers", false) == 0) {
					ToggleTracers(param1);
					LeaderMenu(param1);
				} else if (strcmp(info, "marker", false) == 0) {
					MarkerMenu(param1);
				} else if (strcmp(info, "removemarker", false) == 0) {
					RemoveAllMarkers(param1);
					LeaderMenu(param1);
				} else if (strcmp(info, "resign", false) == 0) {
					ResignConfirmMenu(param1);
				}
			}
		}

		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}
/* =========================================================================
||  Reload Leader Access Command
============================================================================ */
public Action Command_ReloadLeaders(int client, int args) {
	UpdateLeaders();
	CReplyToCommand(client, "%T %T", "Prefix", client, "Leader cache refreshed", client);
	LogAction(client, -1, "[ZLeader] \"%L\" has refreshed Leaders cache.", client);
	return Plugin_Handled;
}

/* =========================================================================
||  Possible Leader Command
============================================================================ */
public Action Command_PossibleLeaders(int client, int args) {
	char aBuf[1024], aBuf2[MAX_NAME_LENGTH];
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i) && IsPossibleLeader(i)) {
			GetClientName(i, aBuf2, sizeof(aBuf2));
			StrCat(aBuf, sizeof(aBuf), aBuf2);
			StrCat(aBuf, sizeof(aBuf), ", ");
		}
	}

	if (strlen(aBuf)) {
		aBuf[strlen(aBuf) - 2] = 0;
		CReplyToCommand(client, "%T %T", "Prefix", client, "Possible Leaders", client, aBuf);
	} else {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Possible Leaders None", client);
	}

	return Plugin_Handled;
}

/* =========================================================================
||  Current Leader Command
============================================================================ */
public Action Command_CurrentLeader(int client, int args) {
	CReplyToCommand(client, "%T %T", "Prefix", client, "Current Leaders", client);

	// The server console only gets the chat lines
	Menu menu = client ? new Menu(CurrentLeaderMenuHandler) : null;
	if (menu)
		menu.SetTitle("%T %T", "Menu Prefix", client, "Menu Leader list title", client);

	char codename[32], sLine[128];
	for (int i = 0; i < g_iTotalLeader; i++) {
		GetLeaderCodename(i, codename, sizeof(codename));

		if (!IsLeaderSlotFree(i)) {
			CReplyToCommand(client, "{darkred}[{orange}%s{darkred}] {lightblue}%N", codename, g_iCurrentLeader[i]);
			FormatEx(sLine, 128, "%s: %N", codename, g_iCurrentLeader[i]);
		} else {
			FormatEx(sLine, 128, "%s: %T", codename, "None", client);
		}

		if (menu)
			menu.AddItem(codename, sLine, ITEMDRAW_DISABLED);
	}

	if (menu) {
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int CurrentLeaderMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

/* =========================================================================
||  Vote Leader Command
============================================================================ */
public Action Command_VoteLeader(int client, int args) {
	if (client <= 0) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Command is in-game only", client);
		return Plugin_Handled;
	}
	if (GetLeaderFreeSlot() == -1) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Slot is full", client);
		return Plugin_Handled;
	}

	if (args < 1) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Vote leader usage", client);
		return Plugin_Handled;
	}

	bool TnIsMl;
	int iTargets[MAXPLAYERS], TargetCount;
	char sArgs[64], sTargetName[MAX_TARGET_LENGTH];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	if ((TargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS,
		COMMAND_FILTER_CONNECTED | COMMAND_FILTER_ALIVE | COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY, sTargetName, sizeof(sTargetName), TnIsMl)) <= 0)
	{
		/* IF MORE THAN ONE TARGET IN GAME FOUND */
		ReplyToTargetError(client, TargetCount);
		return Plugin_Handled;
	}

	/* IF NO TARGET FOUND */
	if (TargetCount == -1)
		return Plugin_Handled;

	int target = iTargets[0];

	if (g_iClientNextVote[client] > GetTime())
	{
		CReplyToCommand(client, "%T %T", "Prefix", client, "VoteLeader Cooldown", client, g_iClientNextVote[client] - GetTime());
		return Plugin_Handled;
	}

	if (!IsClientInGame(target)) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Target is not in game", client);
		return Plugin_Handled;
	}

	if (!IsPlayerAlive(target)) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Target must be alive", client);
		return Plugin_Handled;
	}

	if (GetClientFromSerial(g_iClientVoteWhom[client]) == target) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Already vote client", client);
		return Plugin_Handled;
	}

	if (ZR_IsClientZombie(target)) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Has to be human", client);
		return Plugin_Handled;
	}

	if (IsClientLeader(target)) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Already Leader", client, target);
		return Plugin_Handled;
	}

	if (g_bResignedByAdmin[target]) {
		CReplyToCommand(client, "%t %t", "Prefix", "Leader was resigned by Admin", target);
		return Plugin_Handled;
	}

	if (IsTargetMuted(target) || IsTargetGagged(target)) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Leader should not be muted", client);
		return Plugin_Handled;
	}

	int clientVoteWhom = GetClientFromSerial(g_iClientVoteWhom[client]);
	if (clientVoteWhom != 0) {
		g_iClientGetVoted[clientVoteWhom]--;
	}

	g_iClientGetVoted[target]++;
	g_iClientVoteWhom[client] = GetClientSerial(target);
	g_iClientNextVote[client] = GetTime() + 10;

	int number = GetClientCount(true)/8;

	if (number == 0)
		number = 1;

	for (int i = 1; i <= MaxClients; i++) {
		SetGlobalTransTarget(i);

		if (IsClientInGame(i))
			CPrintToChat(i, "%t %t", "Prefix", "Vote for client", client, target, g_iClientGetVoted[target], number);
	}

	if (g_iClientGetVoted[target] >= number) {
		int slot = GetLeaderFreeSlot();

		if (slot == -1) {
			CReplyToCommand(client, "%T %T", "Prefix", client, "Slot is full", client);
			return Plugin_Handled;
		}

		SetClientLeader(target, -1, slot);
		LeaderMenu(target);
	}

	return Plugin_Handled;
}

/* =========================================================================
||  Remove Leader Command
============================================================================ */
public Action Command_RemoveLeader(int client, int args) {
	if (args < 1) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Remove leader usage", client);
		RemoveLeaderList(client);
		return Plugin_Handled;
	}

	bool TnIsMl;
	int iTargets[MAXPLAYERS], TargetCount;
	char sArgs[64], sTargetName[MAX_TARGET_LENGTH];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	if ((TargetCount = ProcessTargetString(sArgs, client, iTargets, MAXPLAYERS,
		COMMAND_FILTER_CONNECTED | COMMAND_FILTER_ALIVE | COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY, sTargetName, sizeof(sTargetName), TnIsMl)) <= 0)
	{
		/* IF MORE THAN ONE TARGET IN GAME FOUND */
		ReplyToTargetError(client, TargetCount);
		return Plugin_Handled;
	}

	/* IF NO TARGET FOUND */
	if (TargetCount == -1)
		return Plugin_Handled;

	int target = iTargets[0];

	if (target == -1) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Invalid client", client);
		return Plugin_Handled;
	}

	if (!IsClientLeader(target)) {
		CReplyToCommand(client, "%T %T", "Prefix", client, "Client is not leader", client, target);
		return Plugin_Handled;
	}

	RemoveLeader(target, R_ADMINFORCED, true);
	LogAction(client, target, "[ZLeader] Leader \"%L\" has been resigned by \"%L\"", target, client);
	return Plugin_Handled;
}

public void RemoveLeaderList(int client) {
	if (!client)
		return;

	SetGlobalTransTarget(client);
	Menu menu = new Menu(RemoveLeaderListMenuHandler);

	char title[128];
	FormatEx(title, sizeof(title), "%t %t \n%t", "Menu Prefix", "Menu Leader list title", "Menu Remove Leader title");
	menu.SetTitle("%s", title);

	char codename[32], sLine[128], sUserId[12];
	for (int i = 0; i < g_iTotalLeader; i++) {
		GetLeaderCodename(i, codename, sizeof(codename));

		if (!IsLeaderSlotFree(i)) {
			// Keep the userid, the slot may have changed hands when the admin selects it
			IntToString(GetClientUserId(g_iCurrentLeader[i]), sUserId, sizeof(sUserId));
			FormatEx(sLine, 128, "%s: %N", codename, g_iCurrentLeader[i]);
			menu.AddItem(sUserId, sLine);
		} else {
			FormatEx(sLine, 128, "%s: %t", codename, "None");
			menu.AddItem("", sLine, ITEMDRAW_DISABLED);
		}
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return;
}

public int RemoveLeaderListMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char sUserId[12];
			menu.GetItem(param2, sUserId, sizeof(sUserId));

			int target = GetClientOfUserId(StringToInt(sUserId));
			if (!target || !IsClientLeader(target)) {
				CPrintToChat(param1, "%T %T", "Prefix", param1, "Invalid client", param1);
				return 0;
			}

			LogAction(param1, target, "[ZLeader] Leader %N (%s) has been resigned by %N (%s)", target, g_sSteamIDs2[target], param1 , g_sSteamIDs2[param1]);
			RemoveLeader(target, R_ADMINFORCED, true);
		}

		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

/* =========================================================================
||  Trails
============================================================================ */
stock void ToggleTrail(int client) {
	if (IsValidEntRef(g_TrailModel[client]))
		KillTrail(client);
	else
		CreateTrail(client);

	// CreateTrail can fail (dead, wrong team, edicts limit), keep the menu state in sync
	g_bTrailActive[client] = IsValidEntRef(g_TrailModel[client]);
}

stock void CreateTrail(int client) {
	if (!client)
		return;

	KillTrail(client);

	int team = GetClientTeam(client);
	if (!IsPlayerAlive(client) || (team != CS_TEAM_T && team != CS_TEAM_CT))
		return;

	if (GetEdictsCount() > MAXEDICTS) {
		CPrintToChat(client, "%T %T", "Prefix", client, "Edicts Limit", client);
		return;
	}

	int slot = g_iClientLeaderSlot[client];
	if (!IsValidLeaderSlot(slot))
		return;

	int trail = CreateEntityByName("env_spritetrail");
	if (trail == -1)
		return;

	DispatchKeyValueFloat(trail, "lifetime", 2.0);
	DispatchKeyValue(trail, "startwidth", "25");
	DispatchKeyValue(trail, "endwidth", "15");
	DispatchKeyValue(trail, "spritename", g_LeaderData[slot].L_TrailVMT);
	DispatchKeyValue(trail, "rendercolor", "255 255 255");
	DispatchKeyValue(trail, "renderamt", "255");
	DispatchKeyValue(trail, "rendermode", "0");
	DispatchKeyValue(trail, "targetname", "trail");
	DispatchSpawn(trail);

	float angles[3], origin[3];
	char angle[3][16];

	ExplodeString(g_sTrailPosition, " ", angle, sizeof(angle), sizeof(angle[]), false);
	angles[0] = StringToFloat(angle[0]);
	angles[1] = StringToFloat(angle[1]);
	angles[2] = StringToFloat(angle[2]);

	GetClientAbsOrigin(client, origin);
	origin[0] += angles[0];
	origin[1] += angles[1];
	origin[2] += angles[2];

	TeleportEntity(trail, origin, NULL_VECTOR, NULL_VECTOR);

	SetVariantString("!activator");
	AcceptEntityInput(trail, "SetParent", client);
	SetEntPropFloat(trail, Prop_Send, "m_flTextureRes", 0.05);
	SetEntPropEnt(trail, Prop_Send, "m_hOwnerEntity", client);

	g_TrailModel[client] = EntIndexToEntRef(trail);
}

stock void KillTrail(int client) {
	KillEntityRef(g_TrailModel[client]);
}

/* =========================================================================
||  Beacon
============================================================================ */
public void ToggleBeacon(int client) {
	if (g_BeaconSerial[client] == 0)
		CreateBeacon(client);
	else
		KillBeacon(client);
}

public void CreateBeacon(int client) {
	g_BeaconSerial[client] = ++g_Serial_Beacon;
	g_bBeaconActive[client] = true;
	CreateTimer(1.0, Timer_Beacon, client | (g_Serial_Beacon << 7), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

// The beacon never touches the render color: resetting it here used to wipe the leader glow
// (and every player's color on round end)
public void KillBeacon(int client) {
	g_BeaconSerial[client] = 0;
	Reset_ClientBeaconActive(client);
}

public void KillAllBeacons() {
	for (int i = 1; i <= MaxClients; i++)
		KillBeacon(i);
}

public Action Timer_Beacon(Handle timer, any value) {
	int client = value & 0x7f;
	int serial = value >> 7;

	// Outdated timer: a newer beacon (or none) owns this client now, leave it alone
	if (g_BeaconSerial[client] != serial)
		return Plugin_Stop;

	if (!IsClientInGame(client) || !IsPlayerAlive(client) || !IsValidLeaderSlot(g_iClientLeaderSlot[client])) {
		KillBeacon(client);
		return Plugin_Stop;
	}

	float vec[3];
	GetClientAbsOrigin(client, vec);
	vec[2] += 10;

	// First beacon beam (grey)
	TE_SetupBeamRingPoint(vec, 10.0, 375.0, g_BeamSprite, g_HaloSprite, 0, 20, 0.5, 12.0, 0.0, {128, 128, 128, 255}, 10, 0);
	TE_SendToAll();

	// Second beacon beam
	TE_SetupBeamRingPoint(vec, 10.0, 375.0, g_BeamSprite, g_HaloSprite, 0, 15, 0.6, 25.0, 0.5, g_iPingColor[client], 10, 0);
	TE_SendToAll();

	return Plugin_Continue;
}

/* =========================================================================
||  Bullets impact tracers
============================================================================ */
public void ToggleTracers(int client) {
	g_bTracersActive[client] = !g_bTracersActive[client];
}

/* =========================================================================
||  Ping Marker
============================================================================ */
public void CreatePing(int client) {
	// Engine time: unlike GetGameTime() it does not restart on map change
	float fRemaining = g_fPingNextTime[client] - GetEngineTime();
	if (fRemaining > 0.0) {
		CPrintToChat(client, "%t %t", "Prefix", "Cooldown Ping", RoundToCeil(fRemaining));
		return;
	}

	CreatePingBeam(client);
}

public void KillPingBeam(int client) {
	g_PingSerial[client] = 0;
}

public void KillAllPingsBeam() {
	for (int i = 1; i <= MaxClients; i++)
		KillPingBeam(i);
}

public void CreatePingBeam(int client) {
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return;

	int slot = g_iClientLeaderSlot[client];
	if (!IsValidLeaderSlot(slot))
		return;

	// A new ping replaces the previous one. It is removed with its ring by the marker timer,
	// after the ping cooldown (or sm_zleader_marker_time when there is no cooldown).
	RemoveMarker(client, MK_PING);

	if (!SpawnMarker(client, MK_PING))
		return;

	// At least 1s between pings, even with no cooldown (the ping sound goes to every CT)
	g_fPingNextTime[client] = GetEngineTime() + (g_fPingCooldown > 1.0 ? g_fPingCooldown : 1.0);
	g_PingSerial[client] = ++g_Serial_Ping;

	CreateTimer(0.3, Timer_PingBeamRing, client | (g_Serial_Ping << 7), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	if (g_LeaderData[slot].L_MarkerPing_Sound[0] == '\0')
		return;

	for (int x = 1; x <= MaxClients; x++) {
		if (!IsClientInGame(x) || GetClientTeam(x) != CS_TEAM_CT || !g_bPingSound[x])
			continue;
		EmitSoundToClient(x, g_LeaderData[slot].L_MarkerPing_Sound, client, SNDCHAN_AUTO, _, _, 1.0);
	}
}

public Action Timer_PingBeamRing(Handle timer, any value) {
	int client = value & 0x7f;
	int serial = value >> 7;

	// Outdated timer: a newer ping (or none) owns this client now, leave it alone
	if (g_PingSerial[client] != serial)
		return Plugin_Stop;

	if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
		KillPingBeam(client);
		return Plugin_Stop;
	}

	// Each leader has its own ping position (it used to follow the last marker placed by anyone)
	float vec[3];
	vec[0] = g_fPingPos[client][0];
	vec[1] = g_fPingPos[client][1];
	vec[2] = g_fPingPos[client][2];

	// First ping beam ring (grey)
	TE_SetupBeamRingPoint(vec, 10.0, 70.0, g_BeamSprite, g_HaloSprite, 0, 20, 0.5, 12.0, 0.0, {128, 128, 128, 255}, 10, 0);
	TE_SendToAll();

	// Second ping beam ring
	TE_SetupBeamRingPoint(vec, 10.0, 130.0, g_BeamSprite, g_HaloSprite, 0, 15, 0.6, 25.0, 0.5, g_iPingColor[client], 10, 0);
	TE_SendToAll();

	return Plugin_Continue;
}

/* =========================================================================
||  Sprite
============================================================================ */
public void RemoveSpriteFollow(int client) {
	KillEntityRef(g_iSpriteFollow[client]);
}

public void RemoveSpriteCodeName(int client) {
	KillEntityRef(g_iSpriteLeader[client]);
}

// Returns an entity reference
public int AttachSprite(int client, char[] sprite, int position) {
	if (!IsPlayerAlive(client))
		return INVALID_ENT_REFERENCE;

	if (GetEdictsCount() > MAXEDICTS) {
		CPrintToChat(client, "%T %T", "Prefix", client, "Edicts Limit", client);
		return INVALID_ENT_REFERENCE;
	}

	float Origin[3];
	GetClientEyePosition(client, Origin);
	// Position 0 = Close to top of head, Position 1 = Higher pos
	Origin[2] += position == 1 ? 82.0 : 68.0;

	int Ent = CreateEntityByName("env_sprite");

	if (Ent == -1)
		return INVALID_ENT_REFERENCE;

	DispatchKeyValue(Ent, "model", sprite);
	DispatchKeyValue(Ent, "classname", "env_sprite");
	DispatchKeyValue(Ent, "spawnflags", "1");
	DispatchKeyValue(Ent, "scale", "0.1");
	DispatchKeyValue(Ent, "rendermode", "1");
	DispatchKeyValue(Ent, "rendercolor", "255 255 255");
	DispatchKeyValue(Ent, "renderamt", "255");
	DispatchSpawn(Ent);
	TeleportEntity(Ent, Origin, NULL_VECTOR, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(Ent, "SetParent", client, Ent, 0);

	return EntIndexToEntRef(Ent);
}

/* =========================================================================
||  Marker
============================================================================ */
public Action Command_Marker(int client, int args) {
	if (IsClientLeader(client)) {
		MarkerMenu(client);
	}

	return Plugin_Handled;
}

public Action Command_Arrow(int client, int args) {
	if (IsClientLeader(client))
		ToggleMarkerState(client, MK_NORMAL);

	return Plugin_Handled;
}

public Action Command_Defend(int client, int args) {
	if (IsClientLeader(client))
		ToggleMarkerState(client, MK_DEFEND);

	return Plugin_Handled;
}

public Action Command_ZMTP(int client, int args) {
	if (IsClientLeader(client))
		ToggleMarkerState(client, MK_ZMTP);

	return Plugin_Handled;
}

public Action Command_NoDoorHug(int client, int args) {
	if (IsClientLeader(client))
		ToggleMarkerState(client, MK_NOHUG);

	return Plugin_Handled;
}

public Action Command_Ping(int client, int args) {
	if (IsClientLeader(client))
		CreatePing(client);

	return Plugin_Handled;
}

public Action Command_RemoveMarkers(int client, int args) {
	if (IsClientLeader(client))
		RemoveAllMarkers(client);

	return Plugin_Handled;
}

public void MarkerMenu(int client) {
	Menu menu = new Menu(MarkerMenuHandler, MENU_ACTIONS_ALL);

	menu.SetTitle("%T %T", "Menu Prefix", client, "Marker menu title", client);

	char normal[64], defend[64], zmtp[64], nohug[64], ping[64], removemarker[64];

	FormatEx(normal, 64, "%T", "Arrow Marker", client);
	FormatEx(defend, 64, "%T", "Defend Here", client);
	FormatEx(zmtp, 64, "%T", "ZM Teleport", client);
	FormatEx(nohug, 64, "%T", "No Doorhug", client);
	FormatEx(ping, 64, "%T", "Ping Marker", client);
	FormatEx(removemarker, 64, "%T", "Remove Marker", client);

	menu.AddItem("normal", normal);
	menu.AddItem("defend", defend);
	menu.AddItem("zmtp", zmtp);
	menu.AddItem("nohug", nohug);
	menu.AddItem("ping", ping);
	menu.AddItem("removemarker", removemarker);

	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MarkerMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_DisplayItem: {
			if (g_iMaximumMarker < 1) {
				char info[64], display[64];
				menu.GetItem(param2, info, sizeof(info));

				if (strcmp(info, "normal", false) == 0 && IsMarkerPlaced(param1, MK_NORMAL)) {
					FormatEx(display, sizeof(display), "%T (✘)", "Arrow Marker", param1);
					return RedrawMenuItem(display);
				} else if (strcmp(info, "defend", false) == 0 && IsMarkerPlaced(param1, MK_DEFEND)) {
					FormatEx(display, sizeof(display), "%T (✘)", "Defend Here", param1);
					return RedrawMenuItem(display);
				} else if (strcmp(info, "zmtp", false) == 0 && IsMarkerPlaced(param1, MK_ZMTP)) {
					FormatEx(display, sizeof(display), "%T (✘)", "ZM Teleport", param1);
					return RedrawMenuItem(display);
				} else if (strcmp(info, "nohug", false) == 0 && IsMarkerPlaced(param1, MK_NOHUG)) {
					FormatEx(display, sizeof(display), "%T (✘)", "No Doorhug", param1);
					return RedrawMenuItem(display);
				}
			}
		}

		case MenuAction_Select: {
			if (!IsClientLeader(param1))
				return 0;

			char info[64];
			menu.GetItem(param2, info, sizeof(info));

			if (strcmp(info, "normal", false) == 0)
				ToggleMarkerState(param1, MK_NORMAL);
			else if (strcmp(info, "defend", false) == 0)
				ToggleMarkerState(param1, MK_DEFEND);
			else if (strcmp(info, "zmtp", false) == 0)
				ToggleMarkerState(param1, MK_ZMTP);
			else if (strcmp(info, "nohug", false) == 0)
				ToggleMarkerState(param1, MK_NOHUG);
			else if (strcmp(info, "ping", false) == 0)
				CreatePing(param1);
			else if (strcmp(info, "removemarker", false) == 0)
				RemoveAllMarkers(param1);

			MarkerMenu(param1);
		}

		case MenuAction_Cancel: {
			// Only on "Back": reopening on every cancel covered other plugins' menus (map votes...)
			if (param2 == MenuCancel_ExitBack && IsClientLeader(param1))
				LeaderMenu(param1);
		}

		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

stock void ToggleMarkerState(int client, int type) {
	if (g_iMaximumMarker < 1 && IsMarkerPlaced(client, type))
		RemoveMarker(client, type);
	else
		SpawnMarker(client, type);
}

stock void RemoveAllMarkers(int client) {
	// Older markers (several markers of the same type) are only reachable by their targetname
	char sTargetNames[MK_TOTAL][32], sName[32];
	for (int type = 0; type < MK_TOTAL; type++)
		GenerateTargetName(client, sTargetNames[type], sizeof(sTargetNames[]), type);

	// One pass per entity class, instead of a full rescan after every kill for every marker type
	for (int i = 0; i < ENTITIES_PER_MK; i++) {
		int entity = INVALID_ENT_REFERENCE;
		while ((entity = FindEntityByClassname(entity, g_sEntityTypes[i])) != INVALID_ENT_REFERENCE) {
			if (GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName)) <= 0 || strncmp(sName, "MK_", 3) != 0)
				continue;

			for (int type = 0; type < MK_TOTAL; type++) {
				if (strcmp(sName, sTargetNames[type]) == 0) {
					AcceptEntityInput(entity, "Kill");
					break;
				}
			}
		}
	}

	KillPingBeam(client);
	Reset_ClientMarkers(client);
}

public void RemoveMarker(int client, int type) {
	KillEntityRef(g_iClientMarker[type][client]);
	KillEntityRef(g_iMarkerEntities[type][client]);
	KillEntityRef(g_iNeonEntities[type][client]);

	if (type == MK_PING)
		KillPingBeam(client);
}

// Returns true when the marker has been placed
public bool SpawnMarker(int client, int type) {
	if (type != MK_PING && g_iMaximumMarker > 0 && g_iMarkerInUse[client] >= g_iMaximumMarker) {
		CPrintToChat(client, "%T %T", "Prefix", client, "Marker Max Limit", client, g_iMaximumMarker);
		return false;
	}

	if (GetEdictsCount() + ENTITIES_PER_MK > MAXEDICTS) {
		CPrintToChat(client, "%T %T", "Prefix", client, "Edicts Limit", client);
		return false;
	}

	int slot = g_iClientLeaderSlot[client];
	if (!IsPlayerAlive(client) || !IsValidLeaderSlot(slot))
		return false;

	// One trace gives both the position and the entity the marker sticks to
	float pos[3];
	int parent;
	if (g_iMarkerPos[client] == MK_TYPE_CROSSHAIR || type == MK_PING) {
		parent = GetPlayerEye(client, pos);
	} else {
		GetClientAbsOrigin(client, pos);
		// At the player's position, follow what the player stands on rather than what they aim at
		parent = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	}

	if (!IsParentableSurface(parent))
		parent = -1;

	char sTargetName[32], sSprite[PLATFORM_MAX_PATH];
	int color[4];
	GenerateTargetName(client, sTargetName, sizeof(sTargetName), type);
	GetMarkerStyle(slot, type, sSprite, sizeof(sSprite), color);

	int prop = SpawnAimMarker(g_LeaderData[slot].L_MarkerMDL, sTargetName, pos, color, parent);
	if (prop == -1)
		return false;

	int sprite = SpawnSpecialMarker(sSprite, sTargetName, pos, type == MK_PING ? 40.0 : 160.0, parent);
	int neon = type == MK_PING ? -1 : SetupSpecialNeon(sTargetName, pos, color, parent);

	g_iClientMarker[type][client] = EntIndexToEntRef(prop);
	g_iMarkerEntities[type][client] = sprite == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(sprite);
	g_iNeonEntities[type][client] = neon == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(neon);

	bool counted = type != MK_PING;
	if (counted)
		g_iMarkerInUse[client]++;

	if (type == MK_PING) {
		g_fPingPos[client][0] = pos[0];
		g_fPingPos[client][1] = pos[1];
		g_fPingPos[client][2] = pos[2];
	}

	// One timer per marker, holding the references of its own entities
	DataPack pack;
	CreateDataTimer(type == MK_PING && g_fPingCooldown > 0.0 ? g_fPingCooldown : g_fMarkerTime, Timer_RemoveMarker, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(type);
	pack.WriteCell(g_iMarkerGen[client]);
	pack.WriteCell(counted);
	pack.WriteCell(g_iClientMarker[type][client]);
	pack.WriteCell(g_iMarkerEntities[type][client]);
	pack.WriteCell(g_iNeonEntities[type][client]);
	return true;
}

public Action Timer_RemoveMarker(Handle timer, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int type = pack.ReadCell();
	int gen = pack.ReadCell();
	bool counted = pack.ReadCell();
	int prop = pack.ReadCell();
	int sprite = pack.ReadCell();
	int neon = pack.ReadCell();

	int propRef = prop;
	KillEntityRef(prop);
	KillEntityRef(sprite);
	KillEntityRef(neon);

	if (!client)
		return Plugin_Stop;

	// Only clear the client's slot if it still holds this marker, not a newer one of the same type
	if (g_iClientMarker[type][client] == propRef) {
		Reset_ClientMarker(client, type);

		if (type == MK_PING)
			KillPingBeam(client);
	}

	// Markers placed before the last "remove all" are not counted any more
	if (counted && gen == g_iMarkerGen[client] && g_iMarkerInUse[client] > 0)
		g_iMarkerInUse[client]--;

	return Plugin_Stop;
}

stock void GetMarkerStyle(int slot, int type, char[] sprite, int maxlen, int color[4]) {
	switch (type) {
		case MK_NORMAL: {
			strcopy(sprite, maxlen, g_LeaderData[slot].L_MarkerArrowVMT);
			CopyColor(g_LeaderData[slot].L_iColorArrow, color);
		}
		case MK_DEFEND: {
			strcopy(sprite, maxlen, g_LeaderData[slot].L_MarkerDefend_VMT);
			CopyColor(g_LeaderData[slot].L_iColorDefend, color);
		}
		case MK_ZMTP: {
			strcopy(sprite, maxlen, g_LeaderData[slot].L_MarkerZMTP_VMT);
			CopyColor(g_LeaderData[slot].L_iColorZMTP, color);
		}
		case MK_NOHUG: {
			strcopy(sprite, maxlen, g_LeaderData[slot].L_MarkerNOHUG_VMT);
			CopyColor(g_LeaderData[slot].L_iColorNOHUG, color);
		}
		default: {
			strcopy(sprite, maxlen, g_LeaderData[slot].L_MarkerPing_VMT);
			CopyColor(g_LeaderData[slot].L_iColorPing, color);
		}
	}
}

stock void CopyColor(const int source[4], int dest[4]) {
	for (int i = 0; i < 4; i++)
		dest[i] = source[i];
}

stock int SpawnAimMarker(const char[] model, const char[] sTargetName, const float pos[3], const int color[4], int parent) {
	int Ent = CreateEntityByName("prop_dynamic");
	if (Ent == -1)
		return -1;

	DispatchKeyValue(Ent, "targetname", sTargetName);
	DispatchKeyValue(Ent, "model", model);
	DispatchKeyValue(Ent, "DefaultAnim", "default");
	DispatchKeyValue(Ent, "solid", "0");
	DispatchKeyValue(Ent, "spawnflags", "256");
	DispatchKeyValue(Ent, "rendermode", "1");
	DispatchKeyValue(Ent, "rendercolor", "255 255 255");
	DispatchKeyValue(Ent, "renderamt", "200");
	DispatchKeyValue(Ent, "modelscale", "0.9");
	DispatchKeyValue(Ent, "disablereceiveshadows", "1");
	DispatchKeyValue(Ent, "disableshadows", "1");
	DispatchSpawn(Ent);

	SetEntityRenderColor(Ent, color[0], color[1], color[2], color[3]);

	TeleportEntity(Ent, pos, NULL_VECTOR, NULL_VECTOR);
	SetMarkerParent(Ent, parent);

	return Ent;
}

stock int SpawnSpecialMarker(const char[] sprite, const char[] sTargetName, const float pos[3], float height, int parent) {
	int Ent = CreateEntityByName("env_sprite");
	if (Ent == -1)
		return -1;

	float vec[3];
	vec[0] = pos[0];
	vec[1] = pos[1];
	vec[2] = pos[2] + height;

	DispatchKeyValue(Ent, "targetname", sTargetName);
	DispatchKeyValue(Ent, "model", sprite);
	DispatchKeyValue(Ent, "classname", "env_sprite");
	DispatchKeyValue(Ent, "spawnflags", "1");
	DispatchKeyValue(Ent, "scale", "0.1");
	DispatchKeyValue(Ent, "rendermode", "1");
	DispatchKeyValue(Ent, "rendercolor", "255 255 255");
	DispatchKeyValue(Ent, "renderamt", "128");
	DispatchKeyValue(Ent, "disablereceiveshadows", "1");
	DispatchKeyValue(Ent, "disableshadows", "1");
	DispatchSpawn(Ent);

	TeleportEntity(Ent, vec, NULL_VECTOR, NULL_VECTOR);
	SetMarkerParent(Ent, parent);

	return Ent;
}

stock void SetupPlayerNeon(int client) {
	if (GetEdictsCount() > MAXEDICTS) {
		CPrintToChat(client, "%T %T", "Prefix", client, "Edicts Limit", client);
		return;
	}

	int slot = g_iClientLeaderSlot[client];
	if (!IsValidLeaderSlot(slot))
		return;

	int Neon = CreateEntityByName("light_dynamic");
	if (Neon == -1)
		return;

	float fOrigin[3];
	GetClientAbsOrigin(client, fOrigin);

	char sTargetName[32];
	FormatEx(sTargetName, sizeof(sTargetName), "MK_light_player_%d", GetClientUserId(client));

	char sColor[64];
	FormatEx(sColor, sizeof(sColor), "%i %i %i %i", g_LeaderData[slot].L_iColorPing[0], g_LeaderData[slot].L_iColorPing[1], g_LeaderData[slot].L_iColorPing[2], g_LeaderData[slot].L_iColorPing[3]);

	DispatchKeyValue(Neon, "targetname", sTargetName);
	DispatchKeyValue(Neon, "_light", sColor);
	DispatchKeyValue(Neon, "brightness", "2");
	DispatchKeyValue(Neon, "distance", "150");
	DispatchKeyValue(Neon, "spotlight_radius", "50");
	DispatchKeyValue(Neon, "style", "0");
	DispatchSpawn(Neon);
	AcceptEntityInput(Neon, "TurnOn");

	TeleportEntity(Neon, fOrigin, NULL_VECTOR, NULL_VECTOR);

	SetVariantString("!activator");
	AcceptEntityInput(Neon, "SetParent", client, Neon, 0);

	g_iPlayerNeon[client] = EntIndexToEntRef(Neon);
}

stock void RemovePlayerNeon(int client) {
	KillEntityRef(g_iPlayerNeon[client]);
}

stock int SetupSpecialNeon(const char[] sTargetName, const float pos[3], const int color[4], int parent) {
	int Neon = CreateEntityByName("light_dynamic");
	if (Neon == -1)
		return -1;

	char sColor[64];
	FormatEx(sColor, sizeof(sColor), "%i %i %i %i", color[0], color[1], color[2], color[3]);

	DispatchKeyValue(Neon, "targetname", sTargetName);
	DispatchKeyValue(Neon, "_light", sColor);
	DispatchKeyValue(Neon, "brightness", "5");
	DispatchKeyValue(Neon, "distance", "150");
	DispatchKeyValue(Neon, "spotlight_radius", "50");
	DispatchKeyValue(Neon, "style", "0");
	DispatchSpawn(Neon);
	AcceptEntityInput(Neon, "TurnOn");

	TeleportEntity(Neon, pos, NULL_VECTOR, NULL_VECTOR);
	SetMarkerParent(Neon, parent);

	return Neon;
}

// Returns the entity hit by the trace
stock int GetPlayerEye(int client, float pos[3]) {
	float vAngles[3], vOrigin[3];

	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	TR_TraceRayFilter(vOrigin, vAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer);
	TR_GetEndPosition(pos);
	return TR_GetEntityIndex();
}

stock bool TraceEntityFilterPlayer(int entity, int contentsMask) {
	return entity > MaxClients || !entity;
}

// Thanks to Koen for this feature: markers follow moving / breakable entities
stock bool IsParentableSurface(int entity) {
	if (entity <= MaxClients || !IsValidEntity(entity))
		return false;

	char class[64];
	GetEntityClassname(entity, class, sizeof(class));
	return strcmp(class, "func_breakable", false) == 0 || strcmp(class, "func_tracktrain", false) == 0 || strcmp(class, "func_movelinear", false) == 0 || strcmp(class, "func_door", false) == 0 ||
		StrContains(class, "prop_dynamic") != -1 || StrContains(class, "func_physbox") != -1 || StrContains(class, "prop_physics") != -1;
}

stock void SetMarkerParent(int entity, int parent) {
	if (parent == -1)
		return;

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", parent, entity);
}

/* =========================================================================
||  Leader Chat
============================================================================ */
public Action HookPlayerChat(int client, char[] command, int args) {
	return HandleLeaderChat(client, false);
}

public Action HookPlayerChatTeam(int client, char[] command, int args) {
	return HandleLeaderChat(client, true);
}

static Action HandleLeaderChat(int client, bool isSayTeam) {
	if (g_bBlockLeaderChat)
		return Plugin_Continue;

	// A gagged leader must go through the normal chat, so the comms plugin can block it
	if (!IsClientLeader(client) || IsTargetGagged(client))
		return Plugin_Continue;

	char LeaderText[256];
	GetCmdArgString(LeaderText, sizeof(LeaderText));
	StripQuotes(LeaderText);

	if (LeaderText[0] == '\0' || LeaderText[0] == '/' || LeaderText[0] == '@' || IsChatTrigger())
		return Plugin_Handled;

	char codename[32], szMessage[512];
	GetLeaderCodename(g_iClientLeaderSlot[client], codename, sizeof(codename));

	if (g_bPlugin_ccc) {
		FormatEx(szMessage, sizeof(szMessage), "{%s}%N {default}: {%s}%s",
			g_sColorName[client], client, g_sColorChat[client], LeaderText);
	} else {
		FormatEx(szMessage, sizeof(szMessage), "{teamcolor}%N {default}: {default}%s",
			client, LeaderText);
	}

	if (isSayTeam) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && GetClientTeam(i) == CS_TEAM_CT)
				CPrintToChat(i, "%t {darkred}[{orange}%t{darkred}] %s", "Human Chat Prefix", "Leader Codename", codename, szMessage);
		}
	} else {
		CPrintToChatAll("{darkred}[{orange}%t{darkred}] %s", "Leader Codename", codename, szMessage);
	}

	return Plugin_Handled;
}

void GetClientChat(int client) {
	CCC_GetColorKey(client, CCC_NameColor, g_sColorName[client], 64);
	CCC_GetColorKey(client, CCC_ChatColor, g_sColorChat[client], 64);

	// Check HEX to prevent issue
	char g_sColorNameSanitized[64], g_sColorChatSanitized[64];

	if (g_sColorName[client][0] != '\0' && IsValidHex(g_sColorName[client])) {
		FormatEx(g_sColorNameSanitized, sizeof(g_sColorNameSanitized), "#%s", g_sColorName[client]);
		g_sColorName[client] = g_sColorNameSanitized;
	} else {
		g_sColorName[client] = "lightblue";
	}

	if (g_sColorChat[client][0] != '\0' && IsValidHex(g_sColorChat[client])) {
		FormatEx(g_sColorChatSanitized, sizeof(g_sColorChatSanitized), "#%s", g_sColorChat[client]);
		g_sColorChat[client] = g_sColorChatSanitized;
	} else {
		g_sColorChat[client] = "default";
	}
}

/* =========================================================================
||  Radio
============================================================================ */
void HookRadio() {
	for (int i = 0; i < sizeof(g_sRadioCommands); i++)
		AddCommandListener(Radio, g_sRadioCommands[i]);
}

public Action Radio(int client, const char[] command, int argc) {
	if (!IsClientLeader(client))
		return Plugin_Continue;

	for (int i = 0; i < sizeof(g_sRadioCommands); i++) {
		if (strcmp(command, g_sRadioCommands[i], false) == 0) {
			char sPhrase[32];
			FormatEx(sPhrase, sizeof(sPhrase), "Radio %s", g_sRadioCommands[i]);
			PrintRadio(client, sPhrase);
			break;
		}
	}

	return Plugin_Stop;
}

// text is the phrase key of the radio message
public void PrintRadio(int client, const char[] text) {
	char codename[32];

	if (IsClientLeader(client)) {
		GetLeaderCodename(g_iClientLeaderSlot[client], codename, sizeof(codename));
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_CT)
				CPrintToChat(i, "{darkred}[{orange}%t{darkred}] {blue}%N {default}(%t): %t", "Leader Codename", codename, client, "Radio", text);
		}
	}
}

/* =========================================================================
||  Function
============================================================================ */
void SetClientLeader(int client, int adminset = -1, int slot) {
	if (!IsClientInGame(client)) {
		if (adminset != -1)
			CReplyToCommand(adminset, "%T %T", "Prefix", adminset, "Invalid client", adminset);

		return;
	}

	g_bClientLeader[client] = true;
	g_iClientLeaderSlot[client] = slot;
	g_iCurrentLeader[slot] = client;

	g_iPingColor[client][0] = g_LeaderData[slot].L_iColorPing[0];
	g_iPingColor[client][1] = g_LeaderData[slot].L_iColorPing[1];
	g_iPingColor[client][2] = g_LeaderData[slot].L_iColorPing[2];
	g_iPingColor[client][3] = g_LeaderData[slot].L_iColorPing[3];

	g_fTracerTime[client] = g_LeaderData[slot].L_TracerTime;
	g_fTracerWidth[client] = g_LeaderData[slot].L_TracerWidth;

	Reset_ClientSprite(client);
	Reset_ClientResigned(client);

	char codename[32];
	GetLeaderCodename(slot, codename, sizeof(codename));

	if (g_bPlugin_ccc)
		GetClientChat(client);

	if (g_LeaderData[slot].L_CodeNameVMT[0] != '\0')
		g_iSpriteLeader[client] = AttachSprite(client, g_LeaderData[slot].L_CodeNameVMT, 0);

	if (g_bNeonLeader)
		SetupPlayerNeon(client);

	if (g_bGlowLeader)
		ToolsSetEntityColor(client, g_iPingColor[client][0], g_iPingColor[client][1], g_iPingColor[client][2]);

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i))
			CPrintToChat(i, "%T %T", "Prefix", i, "Become New Leader", i, client, codename);
	}

	Reset_ClientMarkers(client);

	Call_StartForward(g_hSetClientLeaderForward);
	Call_PushCell(client);
	Call_PushString(codename);
	Call_Finish();
}

void RemoveLeader(int client, ResignReason reason, bool announce = true) {
	char codename[32];
	bool wasLeader = g_bClientLeader[client];
	int slot = GetClientLeaderSlot(client);

	GetLeaderCodename(slot, codename, sizeof(codename));

	// Unconditional: these may exist even if the matching cvar/flag changed meanwhile
	RemoveAllMarkers(client);
	RemoveSpriteFollow(client);
	RemoveSpriteCodeName(client);
	RemovePlayerNeon(client);
	KillTrail(client);
	KillBeacon(client);

	if (g_bGlowLeader)
		ToolsSetEntityColor(client, 255, 255, 255);

	Reset_VotesForClient(client);
	Reset_ClientFromLeaderSlots(client);

	Reset_CurrentLeader(client);
	Reset_CurrentLeaderSlot(client);
	Reset_ClientGetVoted(client);
	Reset_ClientSprite(client);
	Reset_ClientTrailActive(client);
	Reset_ClientTracersActive(client);
	Reset_ClientTracerSettings(client);
	if (!wasLeader)
		return;

	Call_StartForward(g_hRemoveClientLeaderForward);
	Call_PushCell(client);
	Call_PushCell(reason);
	Call_Finish();

	if (reason == R_ADMINFORCED)
		g_bResignedByAdmin[client] = true;

	if (announce) {
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i))
				continue;

			SetGlobalTransTarget(i);

			switch (reason) {
				case R_DISCONNECTED: {
					CPrintToChat(i, "%t %t", "Prefix", "Remove Disconnected", codename, client);
				}
				case R_ADMINFORCED: {
					CPrintToChat(i, "%t %t", "Prefix", "Remove Admin Force", codename, client);
				}
				case R_SELFRESIGN: {
					CPrintToChat(i, "%t %t", "Prefix", "Remove Self Resign", codename, client);
				}
				case R_SPECTATOR: {
					CPrintToChat(i, "%t %t", "Prefix", "Remove Spectator", codename, client);
				}
				case R_DIED: {
					CPrintToChat(i, "%t %t", "Prefix", "Remove Died", codename, client);
				}
				case R_INFECTED: {
					CPrintToChat(i, "%t %t", "Prefix", "Remove Infected", codename, client);
				}
			}
		}
	}
}

void EnsureLeaderConsistency() {
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client))
			continue;

		int slot = g_iClientLeaderSlot[client];
		bool isLeader = g_bClientLeader[client];

		if (isLeader) {
			if (slot < 0 || slot >= g_iTotalLeader || g_iCurrentLeader[slot] != client) {
				LogMessage("Inconsistent state: Client %d marked as leader but slot %d is invalid", client, slot);
				RemoveLeader(client, R_ADMINFORCED, false);
			}
		} else if (slot >= 0 && slot < g_iTotalLeader && g_iCurrentLeader[slot] == client) {
			LogMessage("Inconsistent state: Client %d in slot %d but not marked as leader", client, slot);
			Reset_LeaderSlotByIndex(slot);
			Reset_ClientLeaderSlot(client);
		}
	}
}

/* =========================================================================
||  QuickCommand
============================================================================ */
// +lookatweapon exist only on CS:GO
public Action QuickLeaderMenuCommand(int client, const char[] command, int argc) {
	if (IsClientLeader(client))
		QuickPingCommand(client);

	return Plugin_Continue;
}

// -lookatweapon exist only on CS:GO
public Action QuickMarkerMenuCommand(int client, const char[] command, int argc) {
	if (IsClientLeader(client))
		QuickMarkerCommand(client);

	return Plugin_Continue;
}

// Flashlight x2 : Marker Menu
// Spray x2 : Ping Shortcut
// +Attack3 : Leader Menu
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse) {
	// Runs every tick for every player: plain array lookup before any native call
	if (!g_bClientLeader[client] || !IsPlayerAlive(client))
		return Plugin_Continue;

	if (impulse == 0x64)
		QuickMarkerCommand(client);
	else if (impulse == 0xC9)
		QuickPingCommand(client);

	// IN_ATTACK3 stays set on every tick while the key is held: only react to the press itself
	// (it used to create a timer and redraw the menu on each tick)
	bool bAttack3 = (buttons & IN_ATTACK3) != 0;
	if (bAttack3 && !g_bAttack3Held[client])
		QuickLeaderCommand(client);
	g_bAttack3Held[client] = bAttack3;

	return Plugin_Continue;
}

// Spray : Ping shortcut
public Action HookDecal(const char[] sTEName, const int[] iClients, int iNumClients, float fSendDelay) {
	int client = TE_ReadNum("m_nPlayer");
	if (client > 0 && client <= MaxClients && g_bClientLeader[client])
		RequestFrame(QuickPingCommand, client);
	return Plugin_Continue;
}

stock void QuickMarkerCommand(int client) {
	if (!IsClientLeader(client) || !g_bShorcut[client])
		return;

	g_iButtonMarkerCount[client]++;
	CreateTimer(1.0, ResetMarkerButtonPressed, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

	if (g_iButtonMarkerCount[client] >= 2)
		MarkerMenu(client);
}

stock void QuickPingCommand(int client) {
	if (!client || !IsClientInGame(client) || !IsClientLeader(client) || !g_bShorcut[client])
		return;

	g_iButtonPingCount[client]++;
	CreateTimer(1.0, ResetPingButtonPressed, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

	if (g_iButtonPingCount[client] >= 2)
		CreatePing(client);
}

stock void QuickLeaderCommand(int client) {
	if (IsClientLeader(client) && g_bShorcut[client])
		LeaderMenu(client);
}

public Action ResetMarkerButtonPressed(Handle timer, any iUserID) {
	int client = GetClientOfUserId(iUserID);
	if (!client)
		return Plugin_Handled;

	g_iButtonMarkerCount[client] = 0;
	return Plugin_Handled;
}

public Action ResetPingButtonPressed(Handle timer, any iUserID) {
	int client = GetClientOfUserId(iUserID);
	if (!client)
		return Plugin_Handled;

	g_iButtonPingCount[client] = 0;
	return Plugin_Handled;
}

/* =========================================================================
||  VIP
============================================================================ */
stock bool IsClientVIP(int client) {
	if (!g_bVIPGroups || !g_bPlugin_vipcore)
		return false;

	char group[64];
	bool vip = VIP_GetClientVIPGroup(client, group, 64);

	if (!vip)
		return false;

	if (strcmp(group, "Retired Staff", false) == 0)
		return true;
	else
		return false;
}

/* =========================================================================
||  API
============================================================================ */
public int Native_SetLeader(Handle hPlugins, int numParams) {
	int client = GetNativeCell(1);
	int slot = GetNativeCell(2);

	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);

	if (slot < 0 || slot >= g_iTotalLeader)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid leader slot (%d)", slot);

	if (!IsLeaderSlotFree(slot))
		return ThrowNativeError(SP_ERROR_NATIVE, "Leader slot %d is already taken", slot);

	// Would leave the old slot taken and its codename sprite attached forever
	if (IsClientLeader(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "The client (index %d) is already leader", client);

	SetClientLeader(client, -1, slot);
	return 0;
}

public int Native_IsClientLeader(Handle hPlugins, int numParams) {
	int client = GetNativeCell(1);

	if (client < 1 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);

	return IsClientLeader(client);
}

public int Native_RemoveLeader(Handle hPlugins, int numParams) {
	int client = GetNativeCell(1);
	ResignReason reason = view_as<ResignReason>(GetNativeCell(2));
	bool announce = view_as<bool>(GetNativeCell(3));

	if (client < 1 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);

	if (!IsClientLeader(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "The client (index %d) is not the leader", client);

	RemoveLeader(client, reason, announce);
	return 0;
}

public int Native_GetClientLeaderSlot(Handle hPlugins, int numParams) {
	int client = GetNativeCell(1);

	if (client < 1 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);

	if (!IsClientLeader(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "The client (index %d) is not the leader", client);

	return GetClientLeaderSlot(client);
}

public int Native_IsLeaderSlotFree(Handle hPlugins, int numParams) {
	return IsLeaderSlotFree(GetNativeCell(1));
}

public int Native_IsPossibleLeader(Handle hPlugins, int numParams) {
	int client = GetNativeCell(1);

	if (client < 1 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);

	return IsPossibleLeader(client);
}

stock bool IsValidLeaderSlot(int slot) {
	return slot >= 0 && slot < g_iTotalLeader;
}

stock int GetLeaderCodename(int slot, char[] buffer, int maxlen) {
	if (!IsValidLeaderSlot(slot)) {
		buffer[0] = '\0';
		return -1;
	}

	strcopy(buffer, maxlen, g_LeaderData[slot].L_Codename);
	return 1;
}

stock int GetLeaderFreeSlot() {
	for (int i = 0; i < g_iTotalLeader; i++) {
		if (IsLeaderSlotFree(i))
			return i;
	}
	return -1;
}

stock int GetClientLeaderSlot(int client) {
	return g_iClientLeaderSlot[client];
}

stock bool IsClientLeader(int client) {
	return g_bClientLeader[client];
}

stock bool IsLeaderSlotFree(int slot) {
	// Slots past the configured leaders don't exist
	if (!IsValidLeaderSlot(slot))
		return false;

	return g_iCurrentLeader[slot] == -1;
}

stock bool IsClientAdmin(int client) {
	return CheckCommandAccess(client, "sm_ban", ADMFLAG_BAN, true);
}

stock bool IsPossibleLeader(int client) {
	if (g_bResignedByAdmin[client])
		return false;

	if (IsClientAdmin(client) || IsClientVIP(client))
		return true;

	if (g_sSteamIDs2[client][0] == '\0')
		return false;

	// Keys are stored upper case (case-insensitive match), like the SteamID2 the engine gives
	int dummy;
	return g_smLeaderAuth.GetValue(g_sSteamIDs2[client], dummy);
}

stock bool IsValidHex(const char[] arg) {
	if (SimpleRegexMatch(arg, "^(#?)([A-Fa-f0-9]{6})$") == 0)
		return false;
	return true;
}

/* =========================================================================
||  Filters
============================================================================ */
public bool Filter_Leaders(const char[] sPattern, ArrayList hClients) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && (IsPossibleLeader(i) || IsClientLeader(i)))
			hClients.Push(i);
	}
	return true;
}

public bool Filter_NotLeaders(const char[] sPattern, ArrayList hClients) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsPossibleLeader(i) && !IsClientLeader(i))
			hClients.Push(i);
	}
	return true;
}

public bool Filter_Leader(const char[] sPattern, ArrayList hClients) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && IsClientLeader(i))
			hClients.Push(i);
	}
	return true;
}

public bool Filter_NotLeader(const char[] sPattern, ArrayList hClients) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientLeader(i))
			hClients.Push(i);
	}
	return true;
}

/* =========================================================================
||  Leaders.ini Access
============================================================================ */
stock void UpdateLeaders() {
	char g_sDataFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, g_sDataFile, sizeof(g_sDataFile), "configs/zleader/leaders.ini");
	g_smLeaderAuth.Clear();

	File fFile = OpenFile(g_sDataFile, "rt");
	if (!fFile) {
		LogError("Access via Leader.ini will not work. Could not read from: %s", g_sDataFile);
		return;
	}

	char sAuth[MAX_AUTHID_LENGTH];

	while (!fFile.EndOfFile()) {
		char line[512];
		if (!fFile.ReadLine(line, sizeof(line)))
			break;

		/* Trim comments */
		int len = strlen(line);
		bool ignoring = false;
		for (int i=0; i<len; i++) {
			if (ignoring) {
				if (line[i] == '"')
					ignoring = false;
			} else {
				if (line[i] == '"') {
					ignoring = true;
				} else if (line[i] == ';') {
					line[i] = '\0';
					break;
				} else if (line[i] == '/' && i != len - 1 && line[i+1] == '/') {
					line[i] = '\0';
					break;
				}
			}
		}

		TrimString(line);

		if ((line[0] == '/' && line[1] == '/') || (line[0] == ';' || line[0] == '\0'))
			continue;

		sAuth = "";
		BreakString(line, sAuth, sizeof(sAuth));
		if (sAuth[0] == '\0')
			continue;

		// Case-insensitive match, see IsPossibleLeader()
		for (int i = 0; sAuth[i] != '\0'; i++)
			sAuth[i] = CharToUpper(sAuth[i]);

		g_smLeaderAuth.SetValue(sAuth, true);
	}

	delete fFile;
}

/* =========================================================================
||  Entity references
============================================================================ */
// Kills the entity if it still exists and clears the reference.
// References can't match a recycled entity index, unlike the raw indexes used before.
stock void KillEntityRef(int &ref) {
	int entity = EntRefToEntIndex(ref);
	if (entity > MaxClients)
		AcceptEntityInput(entity, "Kill");

	ref = INVALID_ENT_REFERENCE;
}

stock bool IsValidEntRef(int ref) {
	return EntRefToEntIndex(ref) > MaxClients;
}

stock bool IsMarkerPlaced(int client, int type) {
	return IsValidEntRef(g_iClientMarker[type][client]);
}

/* =========================================================================
||  Glow Leader
============================================================================ */
stock void ToolsGetEntityColor(int entity, int aColor[4]) {
	static bool bGotConfig = false;
	static char sProp[32];

	if (!bGotConfig) {
		GameData GameConf = new GameData("core.games");
		bool Exists = GameConf.GetKeyValue("m_clrRender", sProp, sizeof(sProp));
		delete GameConf;

		if (!Exists)
			strcopy(sProp, sizeof(sProp), "m_clrRender");

		bGotConfig = true;
	}

	int Offset = GetEntSendPropOffs(entity, sProp);

	for (int i = 0; i < 4; i++)
		aColor[i] = GetEntData(entity, Offset + i, 1);
}

stock void ToolsSetEntityColor(int client, int Red, int Green, int Blue) {
	int aColor[4];
	ToolsGetEntityColor(client, aColor);

	SetEntityRenderColor(client, Red, Green, Blue, aColor[3]);
}

public void ResignConfirmMenu(int client) {
	Menu menu = new Menu(ResignConfirmMenuHandler, MENU_ACTIONS_ALL);

	menu.SetTitle("%T ?", "Resign from Leader", client);

	char no[64], yes[64];
	FormatEx(no, 64, "%T", "No", client);
	FormatEx(yes, 64, "%T", "Yes", client);

	menu.AddItem("canceled", no);
	menu.AddItem("confirmed", yes);

	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ResignConfirmMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_DisplayItem: {
			char info[64], display[64];
			menu.GetItem(param2, info, sizeof(info));

			if (strcmp(info, "canceled", false) == 0) {
				FormatEx(display, sizeof(display), "%T", "No", param1);
				return RedrawMenuItem(display);
			} else if (strcmp(info, "confirmed", false) == 0) {
				FormatEx(display, sizeof(display), "%T", "Yes", param1);
				return RedrawMenuItem(display);
			}
		}
		case MenuAction_Select: {
			if (!IsClientLeader(param1))
				return 0;

			char info[64];
			menu.GetItem(param2, info, sizeof(info));

			if (strcmp(info, "confirmed", false) == 0) {
				RemoveLeader(param1, R_SELFRESIGN, true);
			} else if (strcmp(info, "canceled", false) == 0) {
				LeaderMenu(param1);
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack && IsClientLeader(param1))
				LeaderMenu(param1);
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

/* =========================================================================
||  DRY
============================================================================ */
stock void GenerateTargetName(int client, char[] sTargetName, int size, int type) {
	FormatEx(sTargetName, size, "%s_%d", g_sMarkerTypes[type], GetClientUserId(client));
}

stock bool IsTargetMuted(int target) {
	bool bIsMuted = false;
	bool bBaseCommsPP = g_Plugin_BaseComm && GetFeatureStatus(FeatureType_Native, "BaseComm_IsClientMuted") == FeatureStatus_Available;
	bool bSourceCommsPP = g_bPlugin_SourceCommsPP && GetFeatureStatus(FeatureType_Native, "SourceComms_GetClientMuteType") == FeatureStatus_Available;
	if (bBaseCommsPP)
		bIsMuted = BaseComm_IsClientMuted(target);
	else if (bSourceCommsPP) {
		int iComms = SourceComms_GetClientMuteType(target);
		bIsMuted = iComms != 0 ? true : false;
	}

	return bIsMuted;
}

stock bool IsTargetGagged(int target) {
	bool bIsGagged = false;
	bool bBaseCommsPP = g_Plugin_BaseComm && GetFeatureStatus(FeatureType_Native, "BaseComm_IsClientGagged") == FeatureStatus_Available;
	bool bSourceCommsPP = g_bPlugin_SourceCommsPP && GetFeatureStatus(FeatureType_Native, "SourceComms_GetClientGagType") == FeatureStatus_Available;
	if (bBaseCommsPP)
		bIsGagged = BaseComm_IsClientGagged(target);
	else if (bSourceCommsPP) {
		int iComms = SourceComms_GetClientGagType(target);
		bIsGagged = iComms != 0 ? true : false;
	}

	return bIsGagged;
}

/* =========================================================================
|| 3RD Party Integration
============================================================================ */
#if defined _sourcecomms_included
public void SourceComms_OnBlockAdded(int client, int target, int time, int type, char[] reason) {
	// Check for mute/silence type (1 = Mute, 2 = Gag, 3 = Silence)
	if (type == 1 || type == 2 || type == 3) {
		if (IsPossibleLeader(target)) {
			MCE_RemoveNomination(target);
		}

		if (IsClientLeader(target)) {
			RemoveLeader(target, R_ADMINFORCED, true);
		}
	}
}

public void SourceComms_OnBlockRemoved(int client, int target, int type, char[] reason) {
	// Check for (4) unmute - (5) ungag - (6) unsilence - (14) temp mute removed - (15) temp gag removed - (16) temp silence removed
	// Gags resign the leader too (see OnBlockAdded), so their removal has to clear the flag as well
	if (type == 4 || type == 5 || type == 6 || type == 14 || type == 15 || type == 16) {
		Reset_ClientResigned(target);
	}
}
#endif

#if defined _basecomm_included
public void BaseComm_OnClientMute(int client, bool muteState) {
	OnBaseCommBlock(client, muteState);
}

// A gagged leader could keep talking through the leader chat
public void BaseComm_OnClientGag(int client, bool gagState) {
	OnBaseCommBlock(client, gagState);
}

void OnBaseCommBlock(int client, bool blocked) {
	if (!blocked) {
		Reset_ClientResigned(client);
	} else if (IsClientLeader(client)) {
		// Muting/gagging a non-leader used to clear their "resigned by admin" flag
		RemoveLeader(client, R_ADMINFORCED, true);
	}
}
#endif

stock void MCE_RemoveNomination(int client) {
	if (!g_cvRemoveNomOnMute.BoolValue)
		return;

	bool bNatives = g_bPlugin_MCE && GetFeatureStatus(FeatureType_Native, "GetNominationByOwner") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "RemoveNominationByOwner") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "IsMapLeaderRestricted") == FeatureStatus_Available;

	if (!bNatives)
		return;

#if defined _mapchooser_extended_included_
	// Client has a nomination and the map is leader nom only ? Remove it
	char map[PLATFORM_MAX_PATH];
	if (GetNominationByOwner(client, map) && IsMapLeaderRestricted(map)) {
		RemoveNominationByOwner(client);
	}
#else
	#pragma unused client
#endif
}

/* =========================================================================
||  Reset Values functions
============================================================================ */
stock void Reset_PlayerState(int client) {
	Reset_CurrentLeader(client);
	Reset_LeaderSlot(client);
	Reset_ClientGetVoted(client);
	Reset_ClientNextVote(client);
	Reset_ClientVoteWho(client);
	Reset_ClientResigned(client);
	g_fPingNextTime[client] = 0.0;
	g_bAttack3Held[client] = false;
}

// Defaults until the cookies of the next player on this index are cached
stock void Reset_ClientSettings(int client) {
	g_bShorcut[client] = true;
	g_bPingSound[client] = true;
	g_iMarkerPos[client] = MK_TYPE_CROSSHAIR;
}

stock void Reset_CurrentLeaderSlot(int client) {
	int slot = g_iClientLeaderSlot[client];
	Reset_ClientLeaderSlot(client);
	Reset_LeaderSlotByIndex(slot);
}

stock void Reset_ClientLeaderSlot(int client) {
	g_iClientLeaderSlot[client] = -1;
}

stock void Reset_LeaderSlotByIndex(int slot) {
	if (slot >= 0 && slot < g_iTotalLeader)
		g_iCurrentLeader[slot] = -1;
}

stock void Reset_LeaderSlot(int client) {
	g_iClientLeaderSlot[client] = -1;
}

stock void Reset_CurrentLeader(int client) {
	g_bClientLeader[client] = false;
}

stock void Reset_ClientVoteWho(int client) {
	g_iClientVoteWhom[client] = -1;
}

stock void Reset_ClientGetVoted(int client) {
	g_iClientGetVoted[client] = 0;
}

stock void Reset_ClientNextVote(int client) {
	g_iClientNextVote[client] = 0;
}

stock void Reset_ClientSprite(int client) {
	g_iClientSprite[client] = -1;
}

stock void Reset_ClientBeaconActive(int client) {
	g_bBeaconActive[client] = false;
}

stock void Reset_ClientTrailActive(int client) {
	g_bTrailActive[client] = false;
}

stock void Reset_ClientTracersActive(int client) {
	g_bTracersActive[client] = false;
}

stock void Reset_ClientMarker(int client, int type) {
	g_iClientMarker[type][client] = INVALID_ENT_REFERENCE;
	g_iMarkerEntities[type][client] = INVALID_ENT_REFERENCE;
	g_iNeonEntities[type][client] = INVALID_ENT_REFERENCE;
}

// Forget every marker slot and the counter. Pending marker timers still kill their own entities,
// the generation change only stops them from decrementing the new counter.
stock void Reset_ClientMarkers(int client) {
	for (int type = 0; type < MK_TOTAL; type++)
		Reset_ClientMarker(client, type);

	g_iMarkerInUse[client] = 0;
	g_iMarkerGen[client]++;
}

stock void Reset_ClientTracerSettings(int client) {
	g_fTracerTime[client] = 0.0;
	g_fTracerWidth[client] = 0.0;
}

stock void Reset_ClientResigned(int client) {
	g_bResignedByAdmin[client] = false;
}

void Reset_AllLeaders() {
	for (int i = 0; i < g_iTotalLeader; i++) {
		int client = g_iCurrentLeader[i];
		if (client != -1) {
			if (IsClientInGame(client) && !IsFakeClient(client)) {
				RemoveLeader(client, R_SELFRESIGN, false);
			} else {
				Reset_LeaderSlotByIndex(i);
			}
		}
	}

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			if (g_bClientLeader[i]) {
				RemoveLeader(i, R_SELFRESIGN, false);
			}
			// Voters can vote again, so the counts they gave must go too (they used to add up across rounds)
			Reset_ClientVoteWho(i);
			Reset_ClientGetVoted(i);
			Reset_ClientNextVote(i);
		}
	}
}

void Reset_VotesForClient(int client) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientFromSerial(g_iClientVoteWhom[i]) == client) {
			Reset_ClientVoteWho(i);
		}
	}
}

void Reset_ClientFromLeaderSlots(int client) {
	for (int i = 0; i < g_iTotalLeader; i++) {
		if (g_iCurrentLeader[i] == client) {
			g_iCurrentLeader[i] = -1;
		}
	}
}
