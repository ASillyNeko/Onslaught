global function Sh_OnslaughtGameMode_Init

global const string GAMEMODE_ONSLAUGHT = "onslaught"

void function Sh_OnslaughtGameMode_Init()
{
	AddCallback_OnRegisteringCustomNetworkVars( OnslaughtGameMode_NetworkVars )
	AddCallback_OnCustomGamemodesInit( CreateGamemodeOnslaught )
}

void function CreateGamemodeOnslaught()
{
	GameMode_Create( GAMEMODE_ONSLAUGHT )
	GameMode_SetName( GAMEMODE_ONSLAUGHT, "#GAMEMODE_ONSLAUGHT" )
	GameMode_SetDesc( GAMEMODE_ONSLAUGHT, "#GAMEMODE_ONSLAUGHT_DESC" )
	GameMode_SetGameModeAnnouncement( GAMEMODE_ONSLAUGHT, "grnc_modeDesc" )
	GameMode_SetDefaultScoreLimits( GAMEMODE_ONSLAUGHT, 0, 3 )
	GameMode_SetDefaultTimeLimits( GAMEMODE_ONSLAUGHT, 0, 4 )
	GameMode_SetColor( GAMEMODE_ONSLAUGHT, [128, 255, 255, 255] )

	AddPrivateMatchMode( GAMEMODE_ONSLAUGHT )
	
	#if SERVER
		GameMode_AddServerInit( GAMEMODE_ONSLAUGHT, OnslaughtGameMode_Init )
		GameMode_SetPilotSpawnpointsRatingFunc( GAMEMODE_ONSLAUGHT, RateSpawnpoints_Generic )
		GameMode_SetTitanSpawnpointsRatingFunc( GAMEMODE_ONSLAUGHT, RateSpawnpoints_Generic )
	#elseif CLIENT
		GameMode_AddClientInit( GAMEMODE_ONSLAUGHT, CLOnslaughtGameMode_Init )
	#endif
}

void function OnslaughtGameMode_NetworkVars()
{
	if ( GAMETYPE != GAMEMODE_ONSLAUGHT )
		return

	string start = "ServerCallback_OnslaughtGameMode_"
	Remote_RegisterFunction( start + "JuggernautCrateIcon" )
	Remote_RegisterFunction( start + "JuggernautIcon" )
	Remote_RegisterFunction( start + "BaseIcon" )
}