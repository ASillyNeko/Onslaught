global function CLOnslaughtGameMode_Init
global function ServerCallback_OnSlaughtGameMode_JuggernautCrateIcon
global function ServerCallback_OnSlaughtGameMode_JuggernautIcon
global function ServerCallback_OnSlaughtGameMode_BaseIcon

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

void function ServerCallback_OnSlaughtGameMode_JuggernautCrateIcon( int crate )
{
	thread OnSlaughtGameMode_MakeJuggernautCrateIcon( GetEntityFromEncodedEHandle( crate ) )
}

void function OnSlaughtGameMode_MakeJuggernautCrateIcon( entity crate )
{
	crate.EndSignal( "OnDestroy" )
	crate.EndSignal( "OnDeath" )

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

	RuiSetInt( rui, "viewerTeam", crate.GetTeam() )
	RuiSetInt( rui, "cappingTeam", crate.GetTeam() )

	RuiTrackInt( rui, "hardpointTeamRelation", crate, RUI_TRACK_TEAM_RELATION_VIEWPLAYER )

	RuiSetInt( rui, "hardpointState", 4 )
	RuiSetFloat( rui, "progressFrac", 1.0 )

	RuiSetBool( rui, "isVisible", true )

	WaitForever()
}

void function ServerCallback_OnSlaughtGameMode_JuggernautIcon( int player )
{
	thread OnSlaughtGameMode_MakeJuggernautIcon( GetEntityFromEncodedEHandle( player ) )
}

void function OnSlaughtGameMode_MakeJuggernautIcon( entity player )
{
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )

	GetLocalClientPlayer().EndSignal( "GameStateChanged" )

	var rui = CreateCockpitRui( $"ui/cp_hardpoint_marker.rpak", 200 )
	// var rui = CreateCockpitRui( $"ui/overhead_icon_generic.rpak", MINIMAP_Z_BASE + 200 )

	OnThreadEnd
	(
		function() : ( rui )
		{
			RuiDestroy( rui )
		}
	)

		// RuiSetImage( rui, "icon", $"resource/juggernauticon.png" )
		// RuiSetBool( rui, "isVisible", true )
		// RuiSetBool( rui, "showClampArrow", true )
		// RuiSetBool( rui, "pinToEdge", true )
		// RuiSetFloat2( rui, "iconSize", <64,64,0> )
		// RuiTrackFloat3( rui, "pos", player, RUI_TRACK_OVERHEAD_FOLLOW )
		// WaitForever()

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
		float frac = clamp( hp / 1200, 0.0, 1.0 )
		RuiSetFloat( rui, "progressFrac", frac )
		WaitFrame()
	}
}

void function ServerCallback_OnSlaughtGameMode_BaseIcon( int player, int base )
{
	thread OnSlaughtGameMode_MakeBaseIcon( GetEntityFromEncodedEHandle( player ), GetEntityFromEncodedEHandle( base ) )
}

void function OnSlaughtGameMode_MakeBaseIcon( entity player, entity base )
{
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