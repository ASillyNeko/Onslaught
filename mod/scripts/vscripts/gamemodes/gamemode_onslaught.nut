global function OnslaughtGameMode_Init

const int ONSLAUGHT_DEV = 0
const int JUGGERNAUT_HEALTH = 1000

struct
{
	int Onslaught_CrateLocationIndex = 0
	array<vector> Onslaught_Origins = []
	array<vector> Onslaught_Angles = []

	entity Juggernaut = null

	entity JuggernautCrate = null
	bool JuggernautCrateUsable = true
	vector JuggernautCrateRespawnPos = < 0, 0, 0 >
	vector JuggernautCrateRespawnAngle = < 0, 0, 0 >

	table<int, entity > base

	// BP_ORT Stuff
	table<int, entity> custombotspawnpoint
} file

void function OnslaughtGameMode_Init()
{
	PrecacheModel( $"models/containers/pelican_case_large.mdl" )

	RegisterSignal( "EnableJump" )
	RegisterSignal( "EquipedJuggernaut" )

	SetServerVar( "replayDisabled", false )
	SetShouldUseRoundWinningKillReplay( true )
	SetRoundBased( true )
	SetSwitchSidesBased( true )
	Riff_ForceTitanAvailability( eTitanAvailability.Never )
	Riff_ForceBoostAvailability( eBoostAvailability.Disabled )
	SetSpawnpointGamemodeOverride( TEAM_DEATHMATCH )
	ClassicMP_SetCustomIntro( OnSlaughtGameMode_NoIntro, 5.0 )
	ClassicMP_ForceDisableEpilogue( true )
	ClassicMP_SetShouldTryIntroAndEpilogueWithoutClassicMP( true )

	AddCallback_GameStateEnter( eGameState.Playing, OnslaughtGameMode_Setup )
	SetTimeoutWinnerDecisionFunc( OnslaughtGameMode_DecideTimeoutWinner )

	AddCallback_OnPlayerKilled( OnSlaughtGameMode_JuggernautDeath )
	AddCallback_OnClientDisconnected( OnSlaughtGameMode_JuggernautDisconnected )
	AddCallback_IsValidMeleeExecutionTarget( OnSluaghtGameMode_IsValidExecutionTarget )
	AddCallback_OnPlayerRespawned( OnSlaughtGameMode_OnPlayerRespawned )

	// BP_ORT Stuff
	#if BP_ORT
		AddCallback_OnClientConnected( OnSlaughtGameMode_BotThink )
		AddCallback_OnPlayerKilled( OnSlaughtGameMode_RespawnBot )
	#endif
}

void function OnslaughtGameMode_Setup()
{
	if ( !IsNewThread() )
	{
		thread OnslaughtGameMode_Setup()
		return
	}

	file.Juggernaut = null

	if ( !file.Onslaught_Origins.len() && !file.Onslaught_Angles.len() )
		OnSlaughtGameMode_SetupJuggernautSpawnpoints( GetMapName() )

	if ( file.Onslaught_Origins.len() && file.Onslaught_Angles.len() )
	{
		int random = RandomIntRange( 0, file.Onslaught_CrateLocationIndex + 1 )
		OnSlaughtGameMode_SpawnJuggernautCrate( file.Onslaught_Origins[random], file.Onslaught_Angles[random] )
	}

	OnSlaughtGameMode_SetupJuggernautBases( GetMapName() )

	foreach ( entity player in GetPlayerArray() )
		if ( IsValid( player ) )
			OnSlaughtGameMode_OnPlayerRespawned( player )

	wait 8.0
	foreach ( entity playerfromarray in GetPlayerArray() )
		if ( IsValid( playerfromarray ) )
			NSSendInfoMessageToPlayer( playerfromarray, "#ONSLAUGHT_CAPTUREJUGGERNAUT" )
}

void function OnSlaughtGameMode_SpawnJuggernautCrate( vector origin, vector angles )
{
	entity JuggernautCrate = CreateEntity( "prop_script" )
	JuggernautCrate.SetValueForModelKey( $"models/containers/pelican_case_large.mdl" )
	JuggernautCrate.SetOrigin( origin )
	JuggernautCrate.SetAngles( angles )
	JuggernautCrate.kv.solid = SOLID_VPHYSICS
	DispatchSpawn( JuggernautCrate )

	Highlight_SetNeutralHighlight( JuggernautCrate, "sp_friendly_hero" )

	SetTargetName( JuggernautCrate, "JuggernautCrate" )

	JuggernautCrate.SetAIObstacle( true )
	JuggernautCrate.SetModel( $"models/containers/pelican_case_large.mdl" )
	JuggernautCrate.SetForceVisibleInPhaseShift( true )
	JuggernautCrate.SetUsable()
	JuggernautCrate.SetUsableByGroup( "pilot" )
	JuggernautCrate.SetUsePrompts( "#ONSLAUGHT_JUGGERNAUTCRATEUSEPROMPT", "#ONSLAUGHT_JUGGERNAUTCRATEUSEPROMPT" )
	file.JuggernautCrate = JuggernautCrate
	foreach ( entity player in GetPlayerArray() )
		Remote_CallFunction_NonReplay( player, "ServerCallback_OnSlaughtGameMode_JuggernautCrateIcon", JuggernautCrate.GetEncodedEHandle() )

	thread OnSlaughtGameMode_JuggernautCrate_Think( JuggernautCrate )
}

void function OnSlaughtGameMode_JuggernautCrate_Think( entity JuggernautCrate )
{
	JuggernautCrate.EndSignal( "OnDestroy" )
	svGlobal.levelEnt.EndSignal( "GameStateChanged" )

	OnThreadEnd
	(
		function() : ( JuggernautCrate )
		{
			if ( IsValid( JuggernautCrate ) )
				JuggernautCrate.Destroy()
		}
	)

	while ( true )
	{
		entity player = expect entity ( JuggernautCrate.WaitSignal( "OnPlayerUse" ).player )
		if ( IsValid( player ) && player.IsPlayer() )
			thread OnSlaughtGameMode_Juggernaut_EquipThink( player, JuggernautCrate, player.IsBot() )

		WaitFrame()
	}
}

void function OnSlaughtGameMode_Juggernaut_EquipThink( entity player, entity JuggernautCrate, bool isbot = false )
{
	JuggernautCrate.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )

	OnThreadEnd
	(
		function() : ( JuggernautCrate, player )
		{
			if ( IsValid( JuggernautCrate ) )
			{
				if ( IsValid( player ) && file.Juggernaut == player )
					JuggernautCrate.Destroy()
				else
					JuggernautCrate.SetUsable()

				file.JuggernautCrateUsable = true
			}
		}
	)

	OnslaughtGameMode_EnableOrDisableWeapons( player )
	float startTime = Time()
	JuggernautCrate.UnsetUsable()
	file.JuggernautCrateUsable = false
	float waitTime = 7.5
	#if ONSLAUGHT_DEV
		waitTime = 1.0
	#endif

	while ( ( player.UseButtonPressed() || isbot ) && startTime > Time() - waitTime )
		WaitFrame()

	if ( !player.UseButtonPressed() && !isbot )
	{
		OnslaughtGameMode_EnableOrDisableWeapons( player, true )
		return
	}

	array<string> Mods = [ "disable_wallrun", "disable_doublejump" ]
	if ( player.IsBot() )
		Mods = []

	player.SetPlayerSettingsWithMods( "pilot_stalker_male", Mods )
	StatusEffect_AddEndless( player, eStatusEffect.move_slow, 0.1 ) // Disable Sprinting So They Can't Just Run Into The Base
	player.SetMaxHealth( JUGGERNAUT_HEALTH )
	player.SetHealth( player.GetMaxHealth() )

	TakeWeaponsForArray( player, player.GetMainWeapons() )
	player.TakeOffhandWeapon( OFFHAND_ORDNANCE )
	player.TakeOffhandWeapon( OFFHAND_SPECIAL )
	player.GiveWeapon( "mp_weapon_lmg" )
	entity weapon = player.GetMainWeapons()[0]
	weapon.SetMods( [ "extended_ammo", "pas_fast_reload", "pas_run_and_gun", "threat_scope" ] )
	weapon.SetWeaponPrimaryClipCount( weapon.GetWeaponPrimaryClipCountMax() )
	thread OnSlaughtGameMode_JuggernautWeaponThink( player, weapon )

	AddEntityCallback_OnDamaged( player, OnSlaughtGameMode_HandleJuggernautDamage )
	file.Juggernaut = player
	thread OnSlaughtGameMode_JuggernautThink( player )
	player.Signal( "EquipedJuggernaut" )
	foreach ( entity playerfromarray in GetPlayerArray() )
	{
		if ( IsValid( playerfromarray ) )
		{
			entity base
			if ( IsIMCOrMilitiaTeam( player.GetTeam() ) )
			{
				base = file.base[ GetOtherTeam( player.GetTeam() ) ]
				Remote_CallFunction_NonReplay( playerfromarray, "ServerCallback_OnSlaughtGameMode_BaseIcon", player.GetEncodedEHandle(), base.GetEncodedEHandle() )
			}
			else
			{
				foreach ( int team in [ TEAM_IMC, TEAM_MILITIA ] )
				{
					base = file.base[ team ]
					Remote_CallFunction_NonReplay( playerfromarray, "ServerCallback_OnSlaughtGameMode_BaseIcon", player.GetEncodedEHandle(), base.GetEncodedEHandle() )
				}
			}

			if ( playerfromarray != player )
			{
				Remote_CallFunction_NonReplay( playerfromarray, "ServerCallback_OnSlaughtGameMode_JuggernautIcon", player.GetEncodedEHandle(), JUGGERNAUT_HEALTH )
				
				if ( playerfromarray.GetTeam() == player.GetTeam() )
					NSSendInfoMessageToPlayer( playerfromarray, "#ONSLAUGHT_FRIENDLYGOTJUGGERNAUT" )
				else
					NSSendInfoMessageToPlayer( playerfromarray, "#ONSLAUGHT_ENEMYGOTJUGGERNAUT" )
			}
		}
	}

	OnslaughtGameMode_EnableOrDisableWeapons( player, true, false )
}

void function OnSlaughtGameMode_DisableJump( entity player )
{
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )
	player.EndSignal( "EnableJump" )

	while ( true )
	{
		if ( !player.IsNoclipping() && !player.IsBot() )
		{
			vector velocity = player.GetVelocity()
			if ( velocity.z > 0.0 )
				velocity.z = 0.0

			if ( file.Juggernaut == player )
				player.SetVelocity( velocity )
			else
				player.SetVelocity( < 0, 0, velocity.z > )
		}

		WaitFrame()
	}
}

void function OnSlaughtGameMode_JuggernautWeaponThink( entity player, entity weapon )
{
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )
	weapon.EndSignal( "OnDestroy" )

	while ( true )
	{
		weapon.SetWeaponPrimaryClipCount( weapon.GetWeaponPrimaryClipCountMax() )

		WaitFrame()
	}
}

void function OnslaughtGameMode_EnableOrDisableWeapons( entity player, bool enableordisable = false, bool enablejump = true )
{
	if ( enableordisable )
	{
		if ( enablejump )
			player.Signal( "EnableJump" )

		player.MovementEnable()
		DeployAndEnableWeapons( player )
	}
	else
	{
		player.MovementDisable()
		player.ConsumeDoubleJump()
		thread OnSlaughtGameMode_DisableJump( player )
		HolsterAndDisableWeapons( player )
	}
}

int function OnslaughtGameMode_DecideTimeoutWinner()
{
	file.Juggernaut = null

	OnSlaughtGameMode_SetTeamScore( TEAM_IMC )
	OnSlaughtGameMode_SetTeamScore( TEAM_MILITIA )

	CreateLevelWinnerDeterminedMusicEvent()

	if ( TEAM_IMC >= GetCurrentPlaylistVarInt( "roundscorelimit", 3 ) )
		return TEAM_IMC
	else if ( TEAM_MILITIA >= GetCurrentPlaylistVarInt( "roundscorelimit", 3 ) )
		return TEAM_MILITIA

	return TEAM_UNASSIGNED
}

void function OnSlaughtGameMode_JuggernautDeath( entity victim, entity attacker, var damageInfo )
{
	TakeWeaponsForArray( victim, victim.GetMainWeapons() )

	if ( file.Juggernaut != victim )
		return

	foreach ( entity playerfromarray in GetPlayerArray() )
		if ( IsValid( playerfromarray ) && playerfromarray != victim )
		{
			if ( playerfromarray.GetTeam() == victim.GetTeam() )
				NSSendInfoMessageToPlayer( playerfromarray, "#ONSLAUGHT_FRIENDLYARMORDOWN" )
			else
				NSSendInfoMessageToPlayer( playerfromarray, "#ONSLAUGHT_ENEMYARMORDOWN" )
		}

	file.Juggernaut = null
	OnSlaughtGameMode_SpawnJuggernautCrate( file.JuggernautCrateRespawnPos, file.JuggernautCrateRespawnAngle )

	RemoveEntityCallback_OnDamaged( victim, OnSlaughtGameMode_HandleJuggernautDamage )
}

void function OnSlaughtGameMode_JuggernautDisconnected( entity player )
{
	if ( file.Juggernaut != player )
		return

	foreach ( entity playerfromarray in GetPlayerArray() )
		if ( IsValid( playerfromarray ) && playerfromarray != player )
		{
			if ( playerfromarray.GetTeam() == player.GetTeam() )
				NSSendInfoMessageToPlayer( playerfromarray, "#ONSLAUGHT_FRIENDLYARMORDOWN" )
			else
				NSSendInfoMessageToPlayer( playerfromarray, "#ONSLAUGHT_ENEMYARMORDOWN" )
		}

	file.Juggernaut = null
	OnSlaughtGameMode_SpawnJuggernautCrate( file.JuggernautCrateRespawnPos, file.JuggernautCrateRespawnAngle )
}

void function OnSlaughtGameMode_HandleJuggernautDamage( entity juggernaut, var damageInfo )
{
	if ( !IsNewThread() )
	{
		thread OnSlaughtGameMode_HandleJuggernautDamage( juggernaut, damageInfo )
		return
	}

	WaitFrame()

	if ( file.Juggernaut != juggernaut )
		return

	if ( juggernaut.GetMaxHealth() > 100 )
		juggernaut.SetMaxHealth( max( 100, juggernaut.GetHealth() ) )
}

bool function OnSluaghtGameMode_IsValidExecutionTarget( entity attacker, entity target )
{
	if ( file.Juggernaut == target )
		return false
	
	return true
}

void function OnSlaughtGameMode_OnPlayerRespawned( entity player )
{
	if ( !IsNewThread() )
	{
		thread OnSlaughtGameMode_OnPlayerRespawned( player )
		return
	}

	player.EndSignal( "OnDestroy" )

	foreach ( entity playerfromarray in GetPlayerArray() )
	{
		if ( IsValid( playerfromarray ) && playerfromarray != player && playerfromarray == file.Juggernaut )
		{
			entity base
			if ( IsIMCOrMilitiaTeam( playerfromarray.GetTeam() ) )
			{
				base = file.base[ GetOtherTeam( playerfromarray.GetTeam() ) ]
				Remote_CallFunction_NonReplay( player, "ServerCallback_OnSlaughtGameMode_BaseIcon", playerfromarray.GetEncodedEHandle(), base.GetEncodedEHandle() )
			}
			else
			{
				foreach ( int team in [ TEAM_IMC, TEAM_MILITIA ] )
				{
					base = file.base[ team ]
					Remote_CallFunction_NonReplay( player, "ServerCallback_OnSlaughtGameMode_BaseIcon", playerfromarray.GetEncodedEHandle(), base.GetEncodedEHandle() )
				}
			}

			if ( playerfromarray != player )
				Remote_CallFunction_NonReplay( player, "ServerCallback_OnSlaughtGameMode_JuggernautIcon", playerfromarray.GetEncodedEHandle(), JUGGERNAUT_HEALTH )
		}
	}

	if ( IsValid( file.JuggernautCrate ) )
		Remote_CallFunction_NonReplay( player, "ServerCallback_OnSlaughtGameMode_JuggernautCrateIcon", file.JuggernautCrate.GetEncodedEHandle() )

	if ( !( player.GetTeam() in file.base ) )
		return

	entity spawnpoint = file.base[ player.GetTeam() ]
	#if BP_ORT
		if ( player.IsBot() && player.GetTeam() in file.custombotspawnpoint )
			spawnpoint = file.custombotspawnpoint[ player.GetTeam() ]
	#endif

	player.SetOrigin( spawnpoint.GetOrigin() )
	player.SetAngles( spawnpoint.GetAngles() )

	player.EndSignal( "OnDeath" )

	player.SetInvulnerable()
	wait 1.0
	player.ClearInvulnerable()
}

void function OnSlaughtGameMode_JuggernautThink( entity player )
{
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )
	while ( true )
	{	
		if ( player.IsOnGround() && !player.IsWallRunning() && !player.IsNoclipping() && !EntityIsOutOfBounds( player ) )
		{
			file.JuggernautCrateRespawnPos = player.GetOrigin()
			file.JuggernautCrateRespawnAngle = player.GetAngles()
		}

		WaitFrame()
	}
}

// BP_ORT Stuff
#if BP_ORT
	void function OnSlaughtGameMode_BotThink( entity bot )
	{
		if ( !IsNewThread() )
		{
			thread OnSlaughtGameMode_BotThink( bot )
			return
		}

		if ( !bot.IsBot() )
			return

		bot.EndSignal( "OnDestroy" )

		while ( GetGameState() != eGameState.Playing )
			WaitFrame()

		if ( !file.Onslaught_Origins.len() || !file.Onslaught_Angles.len() )
			return

		while ( true )
		{
			while ( GetGameState() != eGameState.Playing || !IsAlive( bot ) )
				WaitFrame()

			BotSetSimulationType( bot, 7 )

			if ( IsValid( file.JuggernautCrate ) )
			{
				array<vector> points = NavMesh_GetNeighborPositions( file.JuggernautCrate.GetOrigin(), HULL_HUMAN, 5 )
				if ( !points.len() )
					points = NavMesh_RandomPositions( file.JuggernautCrate.GetOrigin(), HULL_HUMAN, 5, 0, 200.0 )

				BotSetTargetPos( bot, points.len() ? SortPositionsByClosestToPos( points, file.JuggernautCrate.GetOrigin() )[0] : file.JuggernautCrate.GetOrigin() )
				if ( Distance( bot.GetOrigin(), file.JuggernautCrate.GetOrigin() ) < 150.0 && PlayerCanSee( bot, file.JuggernautCrate, true, 135 ) && file.JuggernautCrateUsable )
				{
					file.JuggernautCrate.Signal( "OnPlayerUse", { player = bot } )
					bot.WaitSignal( "OnDeath", "EquipedJuggernaut" )
				}
			}
			else if ( IsValid( file.Juggernaut ) && file.Juggernaut != bot )
			{
				array<vector> points = NavMesh_GetNeighborPositions( file.Juggernaut.GetOrigin(), HULL_HUMAN, 5 )
				if ( !points.len() )
					points = NavMesh_RandomPositions( file.Juggernaut.GetOrigin(), HULL_HUMAN, 5, 0, 200.0 )

				BotSetTargetPos( bot, points.len() ? SortPositionsByClosestToPos( points, file.Juggernaut.GetOrigin() )[0] : file.Juggernaut.GetOrigin() )
			}
			else if ( file.Juggernaut == bot )
			{
				int otherteam = RandomIntRange( TEAM_IMC, TEAM_MILITIA )
				if ( IsIMCOrMilitiaTeam( bot.GetTeam() ) )
					otherteam = GetOtherTeam( bot.GetTeam() )

				entity base = file.base[ otherteam ]
				array<vector> points = NavMesh_GetNeighborPositions( base.GetOrigin(), HULL_HUMAN, 5 )
				if ( !points.len() )
					points = NavMesh_RandomPositions( base.GetOrigin(), HULL_HUMAN, 5, 0, 200.0 )

				BotSetTargetPos( bot, points.len() ? SortPositionsByClosestToPos( points, base.GetOrigin() )[0] : base.GetOrigin() )
			}
			else
			{
				print( "All entities invalid" )
			}

			WaitFrame()
		}
	}

	array<vector> function SortPositionsByClosestToPos( array<vector> neighborPos, vector pos )
	{
		array<vector> returnOrigins = []
		int n = neighborPos.len()
		if ( !n )
			return returnOrigins

		array<bool> used = []
		for ( int i = 0; i < n; i++ )
			used.append( false )

		while ( returnOrigins.len() < n )
		{
			int bestIdx = -1
			float bestDist = -1
			for ( int i = 0; i < n; i++ )
			{
				if ( used[i] )
					continue

				float d = Distance( neighborPos[i], pos )
				if ( d < bestDist || bestDist == -1 )
				{
					bestDist = d
					bestIdx = i
				}
			}

			if ( bestIdx == -1 )
				break

			used[ bestIdx ] = true
			returnOrigins.append( neighborPos[ bestIdx ] )
		}

		return returnOrigins
	}

	void function OnSlaughtGameMode_RespawnBot( entity bot, entity attacker, var damageInfo )
	{
		if ( !IsNewThread() )
		{
			thread OnSlaughtGameMode_RespawnBot( bot, attacker, damageInfo )
			return
		}

		if ( !bot.IsBot() )
			return

		bot.EndSignal( "OnDestroy" )

		if ( GetGameState() != eGameState.Playing || !file.Onslaught_Origins.len() || !file.Onslaught_Angles.len() )
			return

		WaitEndFrame()
		bot.EndSignal( "OnDeath" )
		bot.EndSignal( "RespawnMe" )

		wait GetDeathCamLength( bot ) + GetCurrentPlaylistVarFloat( "respawn_delay", 0.0 ) + 1.0

		if ( GetGameState() != eGameState.Playing )
			return

		if ( !IsAlive( bot ) )
			bot.Signal( "RespawnMe" )
	}
#endif

void function OnSlaughtGameMode_SetTeamScore( int team, int amount = 1 )
{
	int scoreLimit = GameMode_GetScoreLimit( GAMETYPE )
	int score = GameRules_GetTeamScore( team )
	
	if ( IsRoundBased() )
	{
		scoreLimit = GameMode_GetRoundScoreLimit( GAMETYPE )
		score = GameRules_GetTeamScore2( team )
	}

	int newScore = score + amount
	if( newScore > scoreLimit && !GameScore_AllowPointsOverLimit() )
		newScore = scoreLimit

	GameRules_SetTeamScore( team, newScore )
	GameRules_SetTeamScore2( team, newScore )
}

void function OnSlaughtGameMode_SetWinner( int ornull team, string winningReason = "", string losingReason = "", bool addedTeamScore = true )
{
	if ( !GamePlayingOrSuddenDeath() )
		return
	
	if ( team )
		SetServerVar( "winningTeam", team )
	
	int announceRoundWinnerWinningSubstr
	int announceRoundWinnerLosingSubstr
	if ( winningReason == "" )
		announceRoundWinnerWinningSubstr = 0
	else
		announceRoundWinnerWinningSubstr = GetStringID( winningReason )
	
	if ( losingReason == "" )
		announceRoundWinnerLosingSubstr = 0
	else
		announceRoundWinnerLosingSubstr = GetStringID( losingReason )
	
	float endTime
	if ( IsRoundBased() )
		endTime = expect float( GetServerVar( "roundEndTime" ) )
	else
		endTime = expect float( GetServerVar( "gameEndTime" ) )
	
	foreach ( entity player in GetPlayerArray() )
	{
		int announcementSubstr = announceRoundWinnerLosingSubstr

		if( team && player.GetTeam() == team )
			announcementSubstr = announceRoundWinnerWinningSubstr
	
		if( Flag( "AnnounceWinnerEnabled" ) )
		{
			if ( IsRoundBased() && !HasRoundScoreLimitBeenReached() )
				Remote_CallFunction_NonReplay( player, "ServerCallback_AnnounceRoundWinner", 0, announcementSubstr, ROUND_WINNING_KILL_REPLAY_SCREEN_FADE_TIME, GameRules_GetTeamScore2( TEAM_MILITIA ), GameRules_GetTeamScore2( TEAM_IMC ) )
			else
				Remote_CallFunction_NonReplay( player, "ServerCallback_AnnounceWinner", 0, announcementSubstr, ROUND_WINNING_KILL_REPLAY_SCREEN_FADE_TIME )
		}

		if( team && player.GetTeam() == team )
			UnlockAchievement( player, achievements.MP_WIN )
	}

	if ( !team )
		SetServerVar( "winningTeam", GetWinningTeam() )
	
	SetGameState( eGameState.WinnerDetermined )
	if ( IsRoundBased() && !HasRoundScoreLimitBeenReached() )
	{
		if ( team != null && team != TEAM_UNASSIGNED )
			ScoreEvent_RoundComplete( expect int( team ) )
	}
	else
	{
		if ( team != null && team != TEAM_UNASSIGNED )
			ScoreEvent_MatchComplete( expect int( team ) )
		
		RegisterMatchStats_OnMatchComplete()
	}
}

void function OnSlaughtGameMode_NoIntro()
{
	AddCallback_OnClientConnected( OnSlaughtGameMode_NoIntro_SpawnPlayer )
	AddCallback_GameStateEnter( eGameState.Prematch, OnSlaughtGameMode_NoIntro_Start )
}

void function OnSlaughtGameMode_NoIntro_Start()
{
	ClassicMP_OnIntroStarted()

	foreach ( entity player in GetPlayerArray() )
		OnSlaughtGameMode_NoIntro_SpawnPlayer( player )
		
	while ( Time() < expect float( level.nv.gameStartTime ) )
		WaitFrame()
		
	foreach ( entity player in GetPlayerArray() )
	{
		if ( !IsPrivateMatchSpectator( player ) )
		{
			player.UnfreezeControlsOnServer()
			RemoveCinematicFlag( player, CE_FLAG_CLASSIC_MP_SPAWNING )
		}
	}
	
	ClassicMP_OnIntroFinished()
}

void function OnSlaughtGameMode_NoIntro_SpawnPlayer( entity player )
{
	if ( GetGameState() != eGameState.Prematch )
		return

	if ( ShouldIntroSpawnAsTitan() )
		thread OnSlaughtGameMode_NoIntro_TitanSpawnPlayer( player )
	else
		thread OnSlaughtGameMode_NoIntro_PilotSpawnPlayer( player )
}

void function OnSlaughtGameMode_NoIntro_PilotSpawnPlayer( entity player )
{
	player.EndSignal( "OnDestroy" )
	if( PlayerCanSpawn( player ) )
		RespawnAsPilot( player )
	
	player.FreezeControlsOnServer()
	HolsterAndDisableWeapons( player )
	ResetPlayerCooldowns( player )
	WaitFrame()
	AddCinematicFlag( player, CE_FLAG_CLASSIC_MP_SPAWNING )
	ScreenFadeFromBlack( player, 1, 1 )

	while ( Time() < expect float( level.nv.gameStartTime ) )
		WaitFrame()
	
	TryGameModeAnnouncement( player )
	DeployAndEnableWeapons( player )
}

void function OnSlaughtGameMode_NoIntro_TitanSpawnPlayer( entity player )
{
	player.EndSignal( "OnDestroy" )
	WaitFrame()
	ScreenFadeFromBlack( player, 1, 1 )

	entity intermissionCam = GetEntArrayByClass_Expensive( "info_intermission" )[ 0 ]
	player.SetObserverModeStaticPosition( intermissionCam.GetOrigin() )
	player.SetObserverModeStaticAngles( intermissionCam.GetAngles() )
	player.StartObserverMode( OBS_MODE_STATIC_LOCKED )

	while ( Time() < expect float( level.nv.gameStartTime ) )
		WaitFrame()
	
	if( PlayerCanSpawn( player ) )
	{
		player.StopObserverMode()
		RespawnAsTitan( player )
	}
	
	TryGameModeAnnouncement( player )
}

// Map Juggernaut Spawn Points
void function OnSlaughtGameMode_SetupJuggernautSpawnpoints( string mapName )
{
	if ( mapName == "mp_forwardbase_kodai" )
	{
		file.Onslaught_CrateLocationIndex = 0
		file.Onslaught_Origins = [ < -85.4952, 846.927, 1096.03 > ] 
		file.Onslaught_Angles = [ < 0, 0, 0 >, < 0, 0, 0 > ]
	}
}

void function OnSlaughtGameMode_SetupJuggernautBases( string mapName )
{
	entity base
	#if BP_ORT
		entity botspawnpoint
	#endif
	if ( mapName == "mp_forwardbase_kodai" )
	{
		// Base 1 IMC
		entity base
		base = CreateEntity( "prop_script" )
		base.SetOrigin( < -924.794, 2370.93, 960.031 > )
		DispatchSpawn( base )
		SetTeam( base, TEAM_IMC )
		file.base[ TEAM_IMC ] <- base
		#if BP_ORT
			botspawnpoint = CreateEntity( "prop_script" )
			botspawnpoint.SetOrigin( < -611.425, 1777.85, 878.241 > )
			DispatchSpawn( botspawnpoint )
			SetTeam( botspawnpoint, TEAM_IMC )
			file.custombotspawnpoint[ TEAM_IMC ] <- botspawnpoint
		#endif

		// Downstairs

			// Doors
			OnSlaughtGameMode_CreateBaseTrigger( < -1000, 2085, 1000 >, < -880, 2085, 1000 >, TEAM_IMC )
			OnSlaughtGameMode_CreateBaseTrigger( < -1000, 2430, 1000 >, < -760, 2430, 1000 >, TEAM_IMC )
			OnSlaughtGameMode_CreateBaseTrigger( < -155, 2545, 1000 >, < -155, 2720, 1000 >, TEAM_IMC )

			// Window
			OnSlaughtGameMode_CreateBaseTrigger( < -315, 2070, 1030 >, < -465, 2070, 1030 >, TEAM_IMC )

		// Upstairs

			// Door
			OnSlaughtGameMode_CreateBaseTrigger( < -495, 3420, 1135 >, < -495, 3495, 1135 >, TEAM_IMC )

			// Windows
			OnSlaughtGameMode_CreateBaseTrigger( < -90, 3395, 1150 >, < -90, 3265, 1150 >, TEAM_IMC )
			OnSlaughtGameMode_CreateBaseTrigger( < -150, 3120, 1150 >, < -150, 3000, 1150 >, TEAM_IMC )
			OnSlaughtGameMode_CreateBaseTrigger( < -605, 2625, 1150 >, < -605, 2785, 1150 >, TEAM_IMC )
			OnSlaughtGameMode_CreateBaseTrigger( < -805, 2540, 1150 >, < -925, 2540, 1150 >, TEAM_IMC )
			OnSlaughtGameMode_CreateBaseTrigger( < -965, 2070, 1150 >, < -875, 2070, 1150 >, TEAM_IMC )

		// Base 2 Militia
		base = CreateEntity( "prop_script" )
		base.SetOrigin( < 724.76, -1960.62, 952.031 > )
		DispatchSpawn( base )
		SetTeam( base, TEAM_MILITIA )
		file.base[ TEAM_MILITIA ] <- base
		
		#if BP_ORT
			botspawnpoint = CreateEntity( "prop_script" )
			botspawnpoint.SetOrigin( < 336.194, -1266.42, 807.079 > )
			DispatchSpawn( botspawnpoint )
			SetTeam( botspawnpoint, TEAM_MILITIA )
			file.custombotspawnpoint[ TEAM_MILITIA ] <- botspawnpoint
		#endif

		// Doors
		OnSlaughtGameMode_CreateBaseTrigger( < 850, -1610, 990 >, < 990, -1610, 990 >, TEAM_MILITIA )
		OnSlaughtGameMode_CreateBaseTrigger( < 1000, -2095, 990 >, < 1000, -1940, 990 >, TEAM_MILITIA )
		OnSlaughtGameMode_CreateBaseTrigger( < 485, -2285, 990 >, < 485, -2130, 990 >, TEAM_MILITIA )
		OnSlaughtGameMode_CreateBaseTrigger( < 675, -1750, 990 >, < 815, -1750, 990 >, TEAM_MILITIA )

		// Window
		OnSlaughtGameMode_CreateBaseTrigger( < 485, -1940, 1030 >, < 485, -1820, 1030 >, TEAM_MILITIA )
	}
}

void function OnSlaughtGameMode_CreateBaseTrigger( vector origin1, vector origin2, int baseteam )
{
	if ( !IsNewThread() )
	{
		thread OnSlaughtGameMode_CreateBaseTrigger( origin1, origin2, baseteam )
		return
	}

	svGlobal.levelEnt.EndSignal( "GameStateChanged" )

	#if ONSLAUGHT_DEV
		DebugDrawLine( origin1, origin2, 0, 140, 255, true, 10000.0 )
	#endif

	const float PADDING = 64.0

	vector mins = < min( origin1.x, origin2.x ), min( origin1.y, origin2.y ), min( origin1.z, origin2.z ) >
	vector maxs = < max( origin1.x, origin2.x ), max( origin1.y, origin2.y ), max( origin1.z, origin2.z ) >

	mins -= < PADDING, PADDING, PADDING >
	maxs += < PADDING, PADDING, PADDING >

	array<entity> playersInTrigger

	while ( true )
	{
		array<entity> playersCurrentlyInTrigger

		foreach ( entity player in GetPlayerArray() )
		{
			if ( !IsValid( player ) || !IsAlive( player ) )
				continue

			vector playerOrigin = player.GetOrigin()

			if ( playerOrigin.x >= mins.x && playerOrigin.x <= maxs.x &&
				 playerOrigin.y >= mins.y && playerOrigin.y <= maxs.y &&
				 playerOrigin.z >= mins.z && playerOrigin.z <= maxs.z )
			{
				playersCurrentlyInTrigger.append( player )
				if ( playersInTrigger.find( player ) == -1 )
					OnSlaughtGameMode_JuggernautEnteredBase( player, baseteam )
			}
		}

		playersInTrigger = playersCurrentlyInTrigger

		WaitFrame()
	}
}

void function OnSlaughtGameMode_JuggernautEnteredBase( entity player, int team )
{
	if ( team == player.GetTeam() )
		return

	if ( file.Juggernaut != player )
		return

	OnSlaughtGameMode_SetTeamScore( GetOtherTeam( team ) )
	thread OnSlaughtGameMode_SetWinner( GetOtherTeam( team ) )
}