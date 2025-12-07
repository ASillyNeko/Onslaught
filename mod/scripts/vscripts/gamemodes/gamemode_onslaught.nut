global function OnslaughtGameMode_Init

const int ONSLAUGHT_DEV = 1

const int JUGGERNAUT_HEALTH = 1000

struct
{
	int Onslaught_CrateLocationIndex = 0
	array<vector> Onslaught_Origins = []
	array<vector> Onslaught_Angles = []

	entity Juggernaut = null
	int health = JUGGERNAUT_HEALTH
	entity lastdamagedjuggernaut = null

	entity JuggernautCrate = null
	bool JuggernautCrateUsable = true
	float JuggernautCrateUseTime = 7.5
	vector JuggernautCrateRespawnPos = < 0, 0, 0 >
	vector JuggernautCrateRespawnAngle = < 0, 0, 0 >

	table<int, entity > base
	bool SwitchedSides = false

	// BP_ORT Thing
	table<int, entity> custombotspawnpoint
} file

void function OnslaughtGameMode_Init()
{
	PrecacheModel( $"models/containers/pelican_case_large.mdl" )

	RegisterSignal( "EnableJump" )
	RegisterSignal( "EquipedJuggernaut" )

	SetServerVar( "replayDisabled", false )

	SetRoundBased( true )
	SetSwitchSidesBased( true )
	SetGamemodeAllowsTeamSwitch( false )

	Riff_ForceTitanAvailability( eTitanAvailability.Never )
	Riff_ForceBoostAvailability( eBoostAvailability.Disabled )

	SetSpawnpointGamemodeOverride( TEAM_DEATHMATCH )

	GameMode_SetDefaultScoreLimits( GAMEMODE_ONSLAUGHT, 3, 3 )

	ClassicMP_SetCustomIntro( OnslaughtGameMode_NoIntro, 5.0 )
	ClassicMP_ForceDisableEpilogue( true )
	ClassicMP_SetShouldTryIntroAndEpilogueWithoutClassicMP( true )

	AddCallback_GameStateEnter( eGameState.Prematch, OnslaughtGameMode_Prematch )
	AddCallback_GameStateEnter( eGameState.Playing, OnslaughtGameMode_Playing )
	AddCallback_GameStateEnter( eGameState.SwitchingSides, OnslaughtGameMode_SwitchingSides )

	AddCallback_OnPlayerKilled( OnslaughtGameMode_JuggernautDeath )
	AddCallback_OnClientDisconnected( OnslaughtGameMode_JuggernautDisconnected )
	AddCallback_IsValidMeleeExecutionTarget( OnslaughtGameMode_IsValidExecutionTarget )
	AddCallback_OnPlayerRespawned( OnslaughtGameMode_OnPlayerRespawned )

	file.health = GetCurrentPlaylistVarInt( "juggernaut_health", JUGGERNAUT_HEALTH )
	file.JuggernautCrateUseTime = GetCurrentPlaylistVarFloat( "juggernautcrate_usetime", 7.5 )

	#if BP_ORT
		AddCallback_OnClientConnected( OnslaughtGameMode_BotThink )
		AddCallback_OnPlayerKilled( OnslaughtGameMode_RespawnBot )
	#endif
}

void function OnslaughtGameMode_Prematch()
{
	if ( !IsNewThread() )
	{
		thread OnslaughtGameMode_Prematch()
		return
	}

	OnslaughtGameMode_SetupJuggernautBases( GetMapName() )

	foreach ( entity player in GetPlayerArray() )
		if ( IsValid( player ) )
			OnslaughtGameMode_OnPlayerRespawned( player )
}

void function OnslaughtGameMode_Playing()
{
	if ( !IsNewThread() )
	{
		thread OnslaughtGameMode_Playing()
		return
	}

	OnslaughtGameMode_GameStateEnter_Playing()

	file.Juggernaut = null

	if ( !file.Onslaught_Origins.len() && !file.Onslaught_Angles.len() )
		OnslaughtGameMode_SetupJuggernautSpawnpoints( GetMapName() )

	if ( file.Onslaught_Origins.len() && file.Onslaught_Angles.len() )
	{
		int random = RandomIntRange( 0, file.Onslaught_CrateLocationIndex + 1 )

		OnslaughtGameMode_SpawnJuggernautCrate( file.Onslaught_Origins[ random ], file.Onslaught_Angles[ random ] )
	}

	wait 8.0

	if ( IsValid( file.Juggernaut ) )
		return

	foreach ( entity playerfromarray in GetPlayerArray() )
		if ( IsValid( playerfromarray ) )
			OnslaughtGameMode_SendInfoMessageToPlayer( playerfromarray, "#GAMEMODE_ONSLAUGHT_CAPTURE_JUGGERNAUT" )
}

void function OnslaughtGameMode_SwitchingSides()
{
	file.SwitchedSides = !file.SwitchedSides
}

void function OnslaughtGameMode_SpawnJuggernautCrate( vector origin, vector angles )
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
	JuggernautCrate.EnableRenderAlways()
	JuggernautCrate.SetUsable()
	JuggernautCrate.SetUsableByGroup( "pilot" )
	JuggernautCrate.SetUsePrompts( "#GAMEMODE_ONSLAUGHT_JUGGERNAUT_CRATE_USE_PROMPT", "#GAMEMODE_ONSLAUGHT_JUGGERNAUT_CRATE_USE_PROMPT" )

	file.JuggernautCrate = JuggernautCrate

	foreach ( entity player in GetPlayerArray() )
		Remote_CallFunction_NonReplay( player, "ServerCallback_OnslaughtGameMode_JuggernautCrateIcon", JuggernautCrate.GetEncodedEHandle() )

	thread OnslaughtGameMode_JuggernautCrate_Think( JuggernautCrate )
}

void function OnslaughtGameMode_JuggernautCrate_Think( entity JuggernautCrate )
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
			thread OnslaughtGameMode_Juggernaut_EquipThink( player, JuggernautCrate, player.IsBot() )

		WaitFrame()
	}
}

void function OnslaughtGameMode_Juggernaut_EquipThink( entity player, entity JuggernautCrate, bool isbot = false )
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

			if ( IsValid( player ) && file.Juggernaut != player )
				OnslaughtGameMode_EnableOrDisableWeapons( player, true )
		}
	)

	OnslaughtGameMode_EnableOrDisableWeapons( player )
	float startTime = Time()
	float waitTime = file.JuggernautCrateUseTime

	JuggernautCrate.UnsetUsable()
	file.JuggernautCrateUsable = false

	#if ONSLAUGHT_DEV
		waitTime = 1.0
	#endif

	SetTeam( JuggernautCrate, player.GetTeam() )

	while ( ( player.UseButtonPressed() || isbot ) && startTime > Time() - waitTime )
	{
		float progress = clamp( ( Time() - startTime ) / waitTime, 0.0, 1.0 )

		SetGlobalNetInt( "JuggernautCrateProgress", int( progress * 100 ) )

		WaitFrame()
	}

	SetGlobalNetInt( "JuggernautCrateProgress", 0 )

	SetTeam( JuggernautCrate, TEAM_UNASSIGNED )

	if ( !player.UseButtonPressed() && !isbot )
		return

	array<string> Mods = [ "disable_wallrun", "disable_doublejump" ]

	if ( isbot )
		Mods = []

	player.SetPlayerSettingsWithMods( "pilot_stalker_male", Mods )

	StatusEffect_AddEndless( player, eStatusEffect.move_slow, 0.1 ) // Disable Sprinting So They Can't Just Run Into The Base
	player.SetMaxHealth( file.health )
	player.SetHealth( player.GetMaxHealth() )
	player.EnableRenderAlways()

	TakeWeaponsForArray( player, player.GetMainWeapons() )
	player.TakeOffhandWeapon( OFFHAND_ORDNANCE )
	player.TakeOffhandWeapon( OFFHAND_SPECIAL )

	player.GiveWeapon( "mp_weapon_lmg" )

	entity weapon = player.GetMainWeapons()[0]

	weapon.SetMods( [ "extended_ammo", "pas_fast_reload", "pas_run_and_gun", "threat_scope" ] )
	weapon.SetWeaponPrimaryClipCount( weapon.GetWeaponPrimaryClipCountMax() )

	thread OnslaughtGameMode_JuggernautWeaponThink( player, weapon )

	AddEntityCallback_OnDamaged( player, OnslaughtGameMode_HandleJuggernautDamage )
	file.Juggernaut = player
	thread OnslaughtGameMode_JuggernautThink( player )
	player.Signal( "EquipedJuggernaut" )

	foreach ( entity playerfromarray in GetPlayerArray() )
	{
		if ( IsValid( playerfromarray ) )
		{
			entity base

			if ( IsIMCOrMilitiaTeam( player.GetTeam() ) )
			{
				base = file.base[ GetOtherTeam( player.GetTeam() ) ]
				Remote_CallFunction_NonReplay( playerfromarray, "ServerCallback_OnslaughtGameMode_BaseIcon", player.GetEncodedEHandle(), base.GetEncodedEHandle() )
			}
			else
			{
				foreach ( int team in [ TEAM_IMC, TEAM_MILITIA ] )
				{
					base = file.base[ team ]
					Remote_CallFunction_NonReplay( playerfromarray, "ServerCallback_OnslaughtGameMode_BaseIcon", player.GetEncodedEHandle(), base.GetEncodedEHandle() )
				}
			}

			if ( playerfromarray != player )
			{
				Remote_CallFunction_NonReplay( playerfromarray, "ServerCallback_OnslaughtGameMode_JuggernautIcon", player.GetEncodedEHandle(), file.health )
				
				if ( playerfromarray.GetTeam() == player.GetTeam() )
					OnslaughtGameMode_SendInfoMessageToPlayer( playerfromarray, "#GAMEMODE_ONSLAUGHT_FRIENDLY_GOT_JUGGERNAUT" )
				else
					OnslaughtGameMode_SendInfoMessageToPlayer( playerfromarray, "#GAMEMODE_ONSLAUGHT_ENEMY_GOT_JUGGERNAUT" )
			}
		}
	}

	OnslaughtGameMode_SendInfoMessageToPlayer( player, "#GAMEMODE_ONSLAUGHT_GET_TO_ENEMY_BASE" )

	OnslaughtGameMode_EnableOrDisableWeapons( player, true, false )
}

void function OnslaughtGameMode_DisableJump( entity player )
{
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )
	player.EndSignal( "EnableJump" )

	if ( player.IsBot() )
		return

	while ( true )
	{
		if ( !player.IsNoclipping() )
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

void function OnslaughtGameMode_JuggernautWeaponThink( entity player, entity weapon )
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

		thread OnslaughtGameMode_DisableJump( player )
		HolsterAndDisableWeapons( player )
	}
}

int function OnslaughtGameMode_DecideTimeoutWinner()
{
	file.Juggernaut = null

	OnslaughtGameMode_SetTeamScore( TEAM_IMC )
	OnslaughtGameMode_SetTeamScore( TEAM_MILITIA )

	CreateLevelWinnerDeterminedMusicEvent()

	int winningteam = TEAM_UNASSIGNED

	if ( TEAM_IMC >= GameMode_GetRoundScoreLimit( GAMEMODE_ONSLAUGHT ) )
		winningteam = TEAM_IMC
	else if ( TEAM_MILITIA >= GameMode_GetRoundScoreLimit( GAMEMODE_ONSLAUGHT ) )
		winningteam = TEAM_MILITIA

	if (
		GameRules_GetTeamScore2( TEAM_IMC ) + GameRules_GetTeamScore2( TEAM_MILITIA ) == ( GameMode_GetRoundScoreLimit( GAMEMODE_ONSLAUGHT ) / 1.5 ).tointeger() ||
		GameRules_GetTeamScore2( TEAM_IMC ) + GameRules_GetTeamScore2( TEAM_MILITIA ) - 1 == ( GameMode_GetRoundScoreLimit( GAMEMODE_ONSLAUGHT ) / 1.5 ).tointeger()
	)
		SetGameState( eGameState.SwitchingSides )

	return winningteam
}

void function OnslaughtGameMode_GameStateEnter_Playing()
{
	if ( !IsNewThread() )
	{
		thread OnslaughtGameMode_GameStateEnter_Playing()
		return
	}

	SetServerVar( "roundEndTime", expect float( GetServerVar( "roundEndTime" ) ) + 0.1 )

	WaitFrame()

	while ( GetGameState() == eGameState.Playing )
	{
		if ( Time() >= expect float( GetServerVar( "roundEndTime" ) ) - 0.1 )
		{
			int winningTeam = OnslaughtGameMode_DecideTimeoutWinner()
			
			if ( GetGameState() != eGameState.SwitchingSides || ( IsIMCOrMilitiaTeam( winningTeam ) && GameRules_GetTeamScore2( winningTeam ) >= GameMode_GetRoundScoreLimit( GAMEMODE_ONSLAUGHT ) ) )
				OnslaughtGameMode_SetWinner( winningTeam, "#GAMEMODE_TIME_LIMIT_REACHED", "#GAMEMODE_TIME_LIMIT_REACHED" )

			foreach ( entity player in GetPlayerArray() )
				if ( IsValid( player ) && file.Juggernaut == player )
					player.Die( player, player, { damageSourceId = eDamageSourceId.damagedef_suicide } )
		}
		
		WaitFrame()
	}
}

void function OnslaughtGameMode_JuggernautDeath( entity victim, entity attacker, var damageInfo )
{
	TakeWeaponsForArray( victim, victim.GetMainWeapons() )

	if ( file.Juggernaut != victim || GetGameState() != eGameState.Playing )
		return

	if ( IsValid( attacker ) && attacker.IsPlayer() && attacker != victim && GetGameState() == eGameState.Playing && attacker.GetTeam() != victim.GetTeam() )
		attacker.AddToPlayerGameStat( PGS_DEFENSE_SCORE, 1 )

	foreach ( entity playerfromarray in GetPlayerArray() )
	{
		if ( IsValid( playerfromarray ) && playerfromarray != victim )
		{
			if ( playerfromarray.GetTeam() == victim.GetTeam() )
				OnslaughtGameMode_SendInfoMessageToPlayer( playerfromarray, "#GAMEMODE_ONSLAUGHT_FRIENDLY_ARMOR_DOWN" )
			else
				OnslaughtGameMode_SendInfoMessageToPlayer( playerfromarray, "#GAMEMODE_ONSLAUGHT_ENEMY_ARMOR_DOWN" )
		}
	}

	file.Juggernaut = null
	file.lastdamagedjuggernaut = null

	OnslaughtGameMode_SpawnJuggernautCrate( file.JuggernautCrateRespawnPos, file.JuggernautCrateRespawnAngle )

	victim.DisableRenderAlways()

	RemoveEntityCallback_OnDamaged( victim, OnslaughtGameMode_HandleJuggernautDamage )
}

void function OnslaughtGameMode_JuggernautDisconnected( entity player )
{
	if ( file.Juggernaut != player || GetGameState() != eGameState.Playing )
		return

	entity attacker = file.lastdamagedjuggernaut

	if ( IsValid( attacker ) && attacker.IsPlayer() && attacker != player && GetGameState() == eGameState.Playing && attacker.GetTeam() != player.GetTeam() )
		attacker.AddToPlayerGameStat( PGS_DEFENSE_SCORE, 1 )

	foreach ( entity playerfromarray in GetPlayerArray() )
	{
		if ( IsValid( playerfromarray ) && playerfromarray != player )
		{
			if ( playerfromarray.GetTeam() == player.GetTeam() )
				OnslaughtGameMode_SendInfoMessageToPlayer( playerfromarray, "#GAMEMODE_ONSLAUGHT_FRIENDLY_ARMOR_DOWN" )
			else
				OnslaughtGameMode_SendInfoMessageToPlayer( playerfromarray, "#GAMEMODE_ONSLAUGHT_ENEMY_ARMOR_DOWN" )
		}
	}

	file.Juggernaut = null
	file.lastdamagedjuggernaut = null

	OnslaughtGameMode_SpawnJuggernautCrate( file.JuggernautCrateRespawnPos, file.JuggernautCrateRespawnAngle )

	player.DisableRenderAlways()

	RemoveEntityCallback_OnDamaged( player, OnslaughtGameMode_HandleJuggernautDamage )
}

void function OnslaughtGameMode_HandleJuggernautDamage( entity juggernaut, var damageInfo )
{
	if ( !IsNewThread() )
	{
		thread OnslaughtGameMode_HandleJuggernautDamage( juggernaut, damageInfo )
		return
	}

	entity attacker = DamageInfo_GetAttacker( damageInfo )

	if ( IsValid( attacker ) && attacker.IsPlayer() && attacker != juggernaut && GetGameState() == eGameState.Playing && attacker.GetTeam() != juggernaut.GetTeam() )
		file.lastdamagedjuggernaut = attacker

	WaitEndFrame()

	if ( file.Juggernaut != juggernaut )
		return

	if ( juggernaut.GetMaxHealth() > 100 )
		juggernaut.SetMaxHealth( max( 100, juggernaut.GetHealth() ) )
}

bool function OnslaughtGameMode_IsValidExecutionTarget( entity attacker, entity target )
{
	if ( file.Juggernaut == target )
		return false
	
	return true
}

void function OnslaughtGameMode_OnPlayerRespawned( entity player )
{
	if ( !IsNewThread() )
	{
		thread OnslaughtGameMode_OnPlayerRespawned( player )
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

				Remote_CallFunction_NonReplay( player, "ServerCallback_OnslaughtGameMode_BaseIcon", playerfromarray.GetEncodedEHandle(), base.GetEncodedEHandle() )
			}
			else
			{
				foreach ( int team in [ TEAM_IMC, TEAM_MILITIA ] )
				{
					base = file.base[ team ]

					Remote_CallFunction_NonReplay( player, "ServerCallback_OnslaughtGameMode_BaseIcon", playerfromarray.GetEncodedEHandle(), base.GetEncodedEHandle() )
				}
			}

			if ( playerfromarray != player )
				Remote_CallFunction_NonReplay( player, "ServerCallback_OnslaughtGameMode_JuggernautIcon", playerfromarray.GetEncodedEHandle(), file.health )
		}
	}

	if ( IsValid( file.JuggernautCrate ) )
		Remote_CallFunction_NonReplay( player, "ServerCallback_OnslaughtGameMode_JuggernautCrateIcon", file.JuggernautCrate.GetEncodedEHandle() )

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

void function OnslaughtGameMode_JuggernautThink( entity player )
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

void function OnslaughtGameMode_SendInfoMessageToPlayer( entity player, string message )
{
	if ( !IsNewThread() )
	{
		thread OnslaughtGameMode_SendInfoMessageToPlayer( player, message )
		return
	}

	player.EndSignal( "OnDestroy" )

	while ( !IsAlive( player ) )
		WaitFrame()

	NSSendInfoMessageToPlayer( player, message )
}

#if BP_ORT
	void function OnslaughtGameMode_BotThink( entity bot )
	{
		if ( !IsNewThread() )
		{
			thread OnslaughtGameMode_BotThink( bot )
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

			WaitFrame()
		}
	}

	array<vector> function SortPositionsByClosestToPos( array<vector> neighborPos, vector pos )
	{
		array<vector> returnOrigins = []
		int n = neighborPos.len()

		if ( !n )
			return [ pos ]

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

	void function OnslaughtGameMode_RespawnBot( entity bot, entity attacker, var damageInfo )
	{
		if ( !IsNewThread() )
		{
			thread OnslaughtGameMode_RespawnBot( bot, attacker, damageInfo )
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

void function OnslaughtGameMode_SetTeamScore( int team, int amount = 1 )
{
	int scoreLimit = GameMode_GetScoreLimit( GAMETYPE )
	int score = GameRules_GetTeamScore( team )
	
	if ( IsRoundBased() )
	{
		scoreLimit = GameMode_GetRoundScoreLimit( GAMETYPE )
		score = GameRules_GetTeamScore2( team )
	}

	int newScore = score + amount

	if ( newScore > scoreLimit && !GameScore_AllowPointsOverLimit() )
		newScore = scoreLimit

	GameRules_SetTeamScore( team, newScore )
	GameRules_SetTeamScore2( team, newScore )
}

void function OnslaughtGameMode_SetWinner( int ornull team, string winningReason = "", string losingReason = "", bool addedTeamScore = true )
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

		if ( team && player.GetTeam() == team )
			announcementSubstr = announceRoundWinnerWinningSubstr
	
		if ( Flag( "AnnounceWinnerEnabled" ) )
		{
			if ( IsRoundBased() && !HasRoundScoreLimitBeenReached() )
				Remote_CallFunction_NonReplay( player, "ServerCallback_AnnounceRoundWinner", 0, announcementSubstr, ROUND_WINNING_KILL_REPLAY_SCREEN_FADE_TIME, GameRules_GetTeamScore2( TEAM_MILITIA ), GameRules_GetTeamScore2( TEAM_IMC ) )
			else
				Remote_CallFunction_NonReplay( player, "ServerCallback_AnnounceWinner", 0, announcementSubstr, ROUND_WINNING_KILL_REPLAY_SCREEN_FADE_TIME )
		}

		if ( team && player.GetTeam() == team )
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

void function OnslaughtGameMode_NoIntro()
{
	AddCallback_OnClientConnected( OnslaughtGameMode_NoIntro_SpawnPlayer )
	AddCallback_GameStateEnter( eGameState.Prematch, OnslaughtGameMode_NoIntro_Start )
}

void function OnslaughtGameMode_NoIntro_Start()
{
	ClassicMP_OnIntroStarted()

	foreach ( entity player in GetPlayerArray() )
		OnslaughtGameMode_NoIntro_SpawnPlayer( player )
		
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

void function OnslaughtGameMode_NoIntro_SpawnPlayer( entity player )
{
	if ( GetGameState() != eGameState.Prematch )
		return

	if ( ShouldIntroSpawnAsTitan() )
		thread OnslaughtGameMode_NoIntro_TitanSpawnPlayer( player )
	else
		thread OnslaughtGameMode_NoIntro_PilotSpawnPlayer( player )
}

void function OnslaughtGameMode_NoIntro_PilotSpawnPlayer( entity player )
{
	player.EndSignal( "OnDestroy" )

	if ( PlayerCanSpawn( player ) )
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

void function OnslaughtGameMode_NoIntro_TitanSpawnPlayer( entity player )
{
	player.EndSignal( "OnDestroy" )

	WaitFrame()

	ScreenFadeFromBlack( player, 1, 1 )

	entity intermissionCam = GetEntArrayByClass_Expensive( "info_intermission" )[0]
	player.SetObserverModeStaticPosition( intermissionCam.GetOrigin() )
	player.SetObserverModeStaticAngles( intermissionCam.GetAngles() )
	player.StartObserverMode( OBS_MODE_STATIC_LOCKED )

	while ( Time() < expect float( level.nv.gameStartTime ) )
		WaitFrame()
	
	if ( PlayerCanSpawn( player ) )
	{
		player.StopObserverMode()
		RespawnAsTitan( player )
	}
	
	TryGameModeAnnouncement( player )
}

// Map Juggernaut Spawn Points
void function OnslaughtGameMode_SetupJuggernautSpawnpoints( string mapName )
{
	if ( mapName == "mp_forwardbase_kodai" )
	{
		file.Onslaught_CrateLocationIndex = 0
		file.Onslaught_Origins = [ < -40.3034, 870.326, 1096.03 > ] 
		file.Onslaught_Angles = [ < 0, 90, 0 > ]
	}
	else if ( mapName == "mp_eden" )
	{
		file.Onslaught_CrateLocationIndex = 0
		file.Onslaught_Origins = [ < 1012.47, 447.898, 67.8343 > ] 
		file.Onslaught_Angles = [ < 0, 90, 0 > ]
	}
	else if ( mapName == "mp_drydock" )
	{
		file.Onslaught_CrateLocationIndex = 0
		file.Onslaught_Origins = [ < -312.031, -1.25381, 408.031 > ]
		file.Onslaught_Angles = [ < 0, 90, 0 > ]
	}
}

void function OnslaughtGameMode_SetupJuggernautBases( string mapName )
{
	entity base
	int IMCTeam = file.SwitchedSides ? TEAM_MILITIA : TEAM_IMC
	int MilitiaTeam = file.SwitchedSides ? TEAM_IMC : TEAM_MILITIA

	#if BP_ORT
		entity botspawnpoint
	#endif

	if ( IMCTeam in file.base && file.base[ IMCTeam ] && IsValid( file.base[ IMCTeam ] ) )
		file.base[ IMCTeam ].Destroy()

	if ( MilitiaTeam in file.base && file.base[ MilitiaTeam ] && IsValid( file.base[ MilitiaTeam ] ) )
		file.base[ MilitiaTeam ].Destroy()

	if ( mapName == "mp_forwardbase_kodai" )
	{
		// Base 1 IMC
		base = CreateEntity( "prop_script" )
		base.SetValueForModelKey( $"models/containers/pelican_case_large.mdl" )
		base.SetOrigin( < -924.794, 2370.93, 960.031 > )
		DispatchSpawn( base )
		SetTeam( base, IMCTeam )
		base.SetModel( $"models/dev/empty_model.mdl" )
		base.EnableRenderAlways()
		file.base[ IMCTeam ] <- base

		#if BP_ORT
			botspawnpoint = CreateEntity( "prop_script" )
			botspawnpoint.SetOrigin( < -611.425, 1777.85, 878.241 > )
			DispatchSpawn( botspawnpoint )
			SetTeam( botspawnpoint, IMCTeam )
			file.custombotspawnpoint[ IMCTeam ] <- botspawnpoint
		#endif

		// Downstairs

			// Doors
			OnslaughtGameMode_CreateBaseTrigger( < -1000, 2085, 1000 >, < -880, 2085, 1000 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < -1000, 2430, 1000 >, < -760, 2430, 1000 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < -155, 2545, 1000 >, < -155, 2720, 1000 >, IMCTeam )

			// Window
			OnslaughtGameMode_CreateBaseTrigger( < -315, 2070, 1030 >, < -465, 2070, 1030 >, IMCTeam )

		// Upstairs

			// Door
			OnslaughtGameMode_CreateBaseTrigger( < -495, 3420, 1135 >, < -495, 3495, 1135 >, IMCTeam )

			// Windows
			OnslaughtGameMode_CreateBaseTrigger( < -90, 3395, 1150 >, < -90, 3265, 1150 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < -150, 3120, 1150 >, < -150, 3000, 1150 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < -605, 2625, 1150 >, < -605, 2785, 1150 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < -805, 2540, 1150 >, < -925, 2540, 1150 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < -965, 2070, 1150 >, < -875, 2070, 1150 >, IMCTeam )

		// Base 2 Militia
		base = CreateEntity( "prop_script" )
		base.SetValueForModelKey( $"models/containers/pelican_case_large.mdl" )
		base.SetOrigin( < 724.76, -1960.62, 952.031 > )
		DispatchSpawn( base )
		SetTeam( base, MilitiaTeam )
		base.SetModel( $"models/dev/empty_model.mdl" )
		base.EnableRenderAlways()
		file.base[ MilitiaTeam ] <- base
		
		#if BP_ORT
			botspawnpoint = CreateEntity( "prop_script" )
			botspawnpoint.SetOrigin( < 336.194, -1266.42, 807.079 > )
			DispatchSpawn( botspawnpoint )
			SetTeam( botspawnpoint, MilitiaTeam )
			file.custombotspawnpoint[ MilitiaTeam ] <- botspawnpoint
		#endif

		// Doors
		OnslaughtGameMode_CreateBaseTrigger( < 850, -1610, 990 >, < 990, -1610, 990 >, MilitiaTeam )
		OnslaughtGameMode_CreateBaseTrigger( < 1000, -2095, 990 >, < 1000, -1940, 990 >, MilitiaTeam )
		OnslaughtGameMode_CreateBaseTrigger( < 485, -2285, 990 >, < 485, -2130, 990 >, MilitiaTeam )
		OnslaughtGameMode_CreateBaseTrigger( < 675, -1750, 990 >, < 815, -1750, 990 >, MilitiaTeam )

		// Window
		OnslaughtGameMode_CreateBaseTrigger( < 485, -1940, 1030 >, < 485, -1820, 1030 >, MilitiaTeam )
	}
	else if ( mapName == "mp_eden" )
	{
		// Base 1 IMC
		base = CreateEntity( "prop_script" )
		base.SetValueForModelKey( $"models/containers/pelican_case_large.mdl" )
		base.SetOrigin( < 3142.13, 228.306, 72.0313 > )
		DispatchSpawn( base )
		SetTeam( base, IMCTeam )
		base.SetModel( $"models/dev/empty_model.mdl" )
		base.EnableRenderAlways()
		file.base[ IMCTeam ] <- base

		#if BP_ORT
			botspawnpoint = CreateEntity( "prop_script" )
			botspawnpoint.SetOrigin( < 3052.62, 802.836, 72.0313 > )
			DispatchSpawn( botspawnpoint )
			SetTeam( botspawnpoint, IMCTeam )
			file.custombotspawnpoint[ IMCTeam ] <- botspawnpoint
		#endif

		// Downstairs
			// Doors
			OnslaughtGameMode_CreateBaseTrigger( < 3285, 240, 110 >, < 3285, 105, 110 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 2945, 410, 110 >, < 2805, 410, 110 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 3055, 600, 110 >, < 3055, 525, 110 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 3205, 445, 110 >, < 3205, 300, 110 >, IMCTeam )

		// Upstairs
			// Doors
			OnslaughtGameMode_CreateBaseTrigger( < 3050, -115, 240 >, < 3050, -20, 240 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 3145, 245, 240 >, < 3070, 245, 240 >, IMCTeam )

			// Window
			OnslaughtGameMode_CreateBaseTrigger( < 3325, 210, 270 >, < 3325, 115, 270 >, IMCTeam )

		// Base 2 Militia
		base = CreateEntity( "prop_script" )
		base.SetValueForModelKey( $"models/containers/pelican_case_large.mdl" )
		base.SetOrigin( < -929.291, -790.651, 208.031 > )
		DispatchSpawn( base )
		SetTeam( base, MilitiaTeam )
		base.SetModel( $"models/dev/empty_model.mdl" )
		base.EnableRenderAlways()
		file.base[ MilitiaTeam ] <- base

		#if BP_ORT
			botspawnpoint = CreateEntity( "prop_script" )
			botspawnpoint.SetOrigin( < -1408.32, -511.992, 208.031 > )
			DispatchSpawn( botspawnpoint )
			SetTeam( botspawnpoint, MilitiaTeam )
			file.custombotspawnpoint[ MilitiaTeam ] <- botspawnpoint
		#endif

		// Doors
		OnslaughtGameMode_CreateBaseTrigger( < -1425, -610, 250 >, < -1330, -610, 250 >, MilitiaTeam )
		OnslaughtGameMode_CreateBaseTrigger( < -620, -875, 250 >, < -710, -875, 250 >, MilitiaTeam )

		// Windows
		OnslaughtGameMode_CreateBaseTrigger( < -1445, -870, 270 >, < -1445, -800, 270 >, MilitiaTeam )
		OnslaughtGameMode_CreateBaseTrigger( < -600, -500, 270 >, < -600, -585, 270 >, MilitiaTeam )
	}
	else if ( mapName == "mp_drydock" )
	{
		// Base 1 IMC
		base = CreateEntity( "prop_script" )
		base.SetValueForModelKey( $"models/containers/pelican_case_large.mdl" )
		base.SetOrigin( < 350.869, 2087.41, 264.031 > )
		DispatchSpawn( base )
		SetTeam( base, IMCTeam )
		base.SetModel( $"models/dev/empty_model.mdl" )
		base.EnableRenderAlways()
		file.base[ IMCTeam ] <- base

		// Downstairs
			// Doors
			OnslaughtGameMode_CreateBaseTrigger( < 795, 1820, 305 >, < 915, 1820, 305 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 930, 1840, 305 >, < 925, 1965, 305 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 800, 2165, 305 >, < 910, 2170, 305 >, IMCTeam )
			OnslaughtGameMode_CreateBaseTrigger( < -105, 1980, 305 >, < -105, 2140, 305 >, IMCTeam )

			// Window
			OnslaughtGameMode_CreateBaseTrigger( < 170, 2345, 325 >, < 305, 2345, 325 >, IMCTeam )

		// Upstairs
			// Window
			OnslaughtGameMode_CreateBaseTrigger( < 785, 2015, 450 >, < 785, 2165, 450 >, IMCTeam )

		// Base 2 Militia
		base = CreateEntity( "prop_script" )
		base.SetValueForModelKey( $"models/containers/pelican_case_large.mdl" )
		base.SetOrigin( < 280.589, -1954.31, 280.031 > )
		DispatchSpawn( base )
		SetTeam( base, MilitiaTeam )
		base.SetModel( $"models/dev/empty_model.mdl" )
		base.EnableRenderAlways()
		file.base[ MilitiaTeam ] <- base

		// Downstairs
			// Doors
			// Doors
			OnslaughtGameMode_CreateBaseTrigger( < 40, -1520, 315 >, < 205, -1520, 315 >, MilitiaTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 225, -2210, 315 >, < 780, -2210, 315 >, MilitiaTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 865, -1485, 315 >, < 865, -1365, 315 >, MilitiaTeam )
			OnslaughtGameMode_CreateBaseTrigger( < -100, -2125, 315 >, < -100, -1980, 315 >, MilitiaTeam )

			// Window
			OnslaughtGameMode_CreateBaseTrigger( < 870, -2175, 350 >, < 870, -2050, 350 >, MilitiaTeam )
		
		// Upstairs
			// Window
			OnslaughtGameMode_CreateBaseTrigger( < 640, -1535, 475 >, < 765, -1535, 475 >, MilitiaTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 870, -1690, 475 >, < 870, -1815, 475 >, MilitiaTeam )
			OnslaughtGameMode_CreateBaseTrigger( < 175, -1535, 475 >, < 50, -1535, 475 >, MilitiaTeam )
			OnslaughtGameMode_CreateBaseTrigger( < -105, -1620, 475 >, < -105, -1760, 475 >, MilitiaTeam )
	}
}

void function OnslaughtGameMode_CreateBaseTrigger( vector origin1, vector origin2, int baseteam )
{
	if ( !IsNewThread() )
	{
		thread OnslaughtGameMode_CreateBaseTrigger( origin1, origin2, baseteam )
		return
	}

	#if ONSLAUGHT_DEV
		DebugDrawLine( origin1, origin2, 0, 140, 255, true, 10000.0 )
	#endif

	float PADDING = 64.0

	vector mins = < min( origin1.x, origin2.x ), min( origin1.y, origin2.y ), min( origin1.z, origin2.z ) >
	vector maxs = < max( origin1.x, origin2.x ), max( origin1.y, origin2.y ), max( origin1.z, origin2.z ) >

	mins -= < PADDING, PADDING, PADDING >
	maxs += < PADDING, PADDING, PADDING >

	array<entity> playersInTrigger

	while ( GetGameState() <= eGameState.Playing )
	{
		array<entity> playersCurrentlyInTrigger

		foreach ( entity player in GetPlayerArray() )
		{
			if ( !IsValid( player ) || !IsAlive( player ) )
				continue

			vector playerOrigin = player.GetOrigin()

			if (
				playerOrigin.x >= mins.x && playerOrigin.x <= maxs.x &&
				playerOrigin.y >= mins.y && playerOrigin.y <= maxs.y &&
				playerOrigin.z >= mins.z && playerOrigin.z <= maxs.z
			)
			{
				playersCurrentlyInTrigger.append( player )
				if ( playersInTrigger.find( player ) == -1 )
					OnslaughtGameMode_JuggernautEnteredBase( player, baseteam )
			}
		}

		playersInTrigger = playersCurrentlyInTrigger

		WaitFrame()
	}
}

void function OnslaughtGameMode_JuggernautEnteredBase( entity player, int team )
{
	if ( team == player.GetTeam() )
		return

	if ( file.Juggernaut != player )
		return

	OnslaughtGameMode_SetTeamScore( GetOtherTeam( team ) )

	if ( GameRules_GetTeamScore2( TEAM_IMC ) + GameRules_GetTeamScore2( TEAM_MILITIA ) == ( GameMode_GetRoundScoreLimit( GAMEMODE_ONSLAUGHT ) / 1.5 ).tointeger() )
		SetGameState( eGameState.SwitchingSides )
	else
		OnslaughtGameMode_SetWinner( GetOtherTeam( team ) )

	player.Die( player, player, { damageSourceId = eDamageSourceId.damagedef_suicide } )
}