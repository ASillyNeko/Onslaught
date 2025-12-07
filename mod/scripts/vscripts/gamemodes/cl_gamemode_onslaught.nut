global function CLOnslaughtGameMode_Init
global function ServerCallback_OnslaughtGameMode_JuggernautCrateIcon
global function ServerCallback_OnslaughtGameMode_JuggernautIcon
global function ServerCallback_OnslaughtGameMode_BaseIcon

void function CLOnslaughtGameMode_Init()
{
	foreach ( int team in [ TEAM_IMC, TEAM_MILITIA ] )
	{
		RegisterLevelMusicForTeam( eMusicPieceID.LEVEL_INTRO, "music_mp_ctf_flag_4", team )
	
		RegisterLevelMusicForTeam( eMusicPieceID.ROUND_BASED_GAME_WON, "music_mp_freeagents_outro_win", team )
		RegisterLevelMusicForTeam( eMusicPieceID.ROUND_BASED_GAME_LOST, "music_mp_fd_defeat", team )

		RegisterLevelMusicForTeam( eMusicPieceID.LEVEL_WIN, "music_mp_pilothunt_epilogue_win", team )
		RegisterLevelMusicForTeam( eMusicPieceID.LEVEL_DRAW, "music_mp_pilothunt_epilogue_win", team )
		RegisterLevelMusicForTeam( eMusicPieceID.LEVEL_LOSS, "music_mp_pilothunt_epilogue_lose", team )
	}
}

void function ServerCallback_OnslaughtGameMode_JuggernautCrateIcon( int crate )
{
	thread OnslaughtGameMode_MakeJuggernautCrateIcon( GetEntityFromEncodedEHandle( crate ) )
}

void function OnslaughtGameMode_MakeJuggernautCrateIcon( entity crate )
{
	if ( !IsValid( crate ) )
		return

	crate.EndSignal( "OnDestroy" )

	GetLocalClientPlayer().EndSignal( "GameStateChanged" )

	var rui = CreateCockpitRui( $"ui/cp_hardpoint_marker.rpak", 200 )

	OnThreadEnd
	(
		function() : ( rui )
		{
			RuiDestroy( rui )
		}
	)

	RuiTrackFloat3( rui, "pos", crate, RUI_TRACK_ABSORIGIN_FOLLOW )

	RuiSetInt( rui, "hardpointId", 0 )

	RuiSetInt( rui, "viewerTeam", GetLocalClientPlayer().GetTeam() )
	RuiSetInt( rui, "cappingTeam", crate.GetTeam() )

	RuiTrackInt( rui, "hardpointTeamRelation", crate, RUI_TRACK_TEAM_RELATION_VIEWPLAYER )

	RuiSetInt( rui, "hardpointState", 4 )
	RuiSetFloat( rui, "progressFrac", 0.0 )

	RuiSetBool( rui, "isVisible", true )

	while ( true )
	{
		RuiSetInt( rui, "cappingTeam", crate.GetTeam() )
		RuiSetFloat( rui, "progressFrac", GetGlobalNetInt( "JuggernautCrateProgress" ) / 100.0 )

		WaitFrame()
	}

	WaitForever()
}

void function ServerCallback_OnslaughtGameMode_JuggernautIcon( int player, int health )
{
	thread OnslaughtGameMode_MakeJuggernautIcon( GetEntityFromEncodedEHandle( player ), health )
}

void function OnslaughtGameMode_MakeJuggernautIcon( entity player, int health )
{
	if ( !IsValid( player ) || !IsAlive( player ) )
		return

	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )

	GetLocalClientPlayer().EndSignal( "GameStateChanged" )

	var rui = CreateCockpitRui( $"ui/cp_hardpoint_marker.rpak", 200 )

	OnThreadEnd
	(
		function() : ( rui )
		{
			RuiDestroy( rui )
		}
	)

	RuiTrackFloat3( rui, "pos", player, RUI_TRACK_ABSORIGIN_FOLLOW )

	RuiSetInt( rui, "hardpointId", 1 )

	RuiSetInt( rui, "viewerTeam", GetLocalClientPlayer().GetTeam() )
	RuiSetInt( rui, "cappingTeam", player.GetTeam() )

	RuiTrackInt( rui, "hardpointTeamRelation", player, RUI_TRACK_TEAM_RELATION_VIEWPLAYER )

	RuiSetInt( rui, "hardpointState", 4 )

	RuiSetBool( rui, "isVisible", true )

	while ( true )
	{
		float hp = float( player.GetHealth() )
		float frac = clamp( hp / health, 0.0, 1.0 )

		RuiSetFloat( rui, "progressFrac", frac )

		WaitFrame()
	}
}

void function ServerCallback_OnslaughtGameMode_BaseIcon( int player, int base )
{
	thread OnslaughtGameMode_MakeBaseIcon( GetEntityFromEncodedEHandle( player ), GetEntityFromEncodedEHandle( base ) )
}

void function OnslaughtGameMode_MakeBaseIcon( entity player, entity base )
{
	if ( !IsValid( player ) || !IsAlive( player ) || !IsValid( base ) )
		return

	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )

	base.EndSignal( "OnDestroy" )

	GetLocalClientPlayer().EndSignal( "GameStateChanged" )

	var rui = CreateCockpitRui( $"ui/cp_hardpoint_marker.rpak", 200 )

	OnThreadEnd
	(
		function() : ( rui )
		{
			RuiDestroy( rui )
		}
	)

	RuiSetFloat3( rui, "pos", base.GetOrigin() + < 0, 0, 64 > )

	RuiSetInt( rui, "hardpointId", 2 )

	RuiSetInt( rui, "viewerTeam", GetLocalClientPlayer().GetTeam() )
	RuiSetInt( rui, "cappingTeam", base.GetTeam() )

	RuiTrackInt( rui, "hardpointTeamRelation", base, RUI_TRACK_TEAM_RELATION_VIEWPLAYER )

	RuiSetInt( rui, "hardpointState", 4 )
	RuiSetFloat( rui, "progressFrac", 1.0 )

	RuiSetBool( rui, "isVisible", true )

	WaitForever()
}