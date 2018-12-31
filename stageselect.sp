#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
	name = "Stage selector",
	author = "Besath",
	description = "Teleport to various stages on the map",
	version = SOURCEMOD_VERSION,
	url = "https://bitbucket.org/besath/stage-select/"
};

char currentMap[32];
Database g_hDatabase;

#define db_CreateStagesTable "CREATE table IF NOT EXISTS stages (mapname VARCHAR(128) NOT NULL, stagename VARCHAR(32) NOT NULL, origin_x FLOAT NOT NULL, origin_y FLOAT NOT NULL, origin_z FLOAT NOT NULL, angles_x FLOAT NOT NULL, angles_y FLOAT NOT NULL, angles_z FLOAT NOT NULL, PRIMARY KEY (mapname, stagename));"
#define db_InsertStage "INSERT OR REPLACE INTO stages (mapname, stagename, origin_x, origin_y, origin_z, angles_x, angles_y, angles_z) VALUES ('%s', '%s', %f, %f, %f, %f, %f, %f);"
#define db_DeleteStage "DELETE FROM stages WHERE mapname = '%s' AND stagename = '%s';"
#define db_GetStageNames "SELECT stagename FROM stages WHERE mapname = '%s';"
#define db_GetTeleportLocation "SELECT origin_x, origin_y, origin_z, angles_x, angles_y, angles_z FROM stages WHERE mapname = '%s' AND stagename = '%s';"

public OnPluginStart()
{
	RegAdminCmd("sm_regstage", Command_RegStage, ADMFLAG_GENERIC, "Register stage coordinates");
	RegAdminCmd("sm_delstage", Command_DelStage, ADMFLAG_GENERIC, "Delete stage from database");
	RegConsoleCmd("sm_stages", Command_Stages, "Opens a menu that lets you teleport to the selected point on the map");
	RegConsoleCmd("sm_courses", Command_Stages, "Opens a menu that lets you teleport to the selected point on the map");

	Database.Connect(OnConnect, "stageselect");
}

public OnMapStart()
{
	GetCurrentMap(currentMap, sizeof(currentMap));
}

public void OnConnect(Database db, const char[] error, any data)
{
	if(db == null)
	{
		SetFailState("Could not connect to db: %s", error);
	}

	g_hDatabase = db;
	char sQuery[304];
	g_hDatabase.Format(sQuery, sizeof(sQuery), db_CreateStagesTable);
	g_hDatabase.Query(SQLCallback, sQuery);
}

public void SQLCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("Query failure: %s", error);
	}

}

public Action Command_RegStage(client, args)
{
	if (args < 1)
	{
		PrintToChat(client, "Please specify a name");
		return Plugin_Continue;
	}
	if (args > 1)
	{
		PrintToChat(client, "Too many arguments");
		return Plugin_Continue;
	}

	float pos[3];
	float angs[3];
	char arg1[32];
	char stageQuery[PLATFORM_MAX_PATH];
	GetClientAbsOrigin(client, pos);
	GetClientAbsAngles(client, angs);
	GetCmdArgString(arg1, sizeof(arg1));
	g_hDatabase.Format(stageQuery, sizeof(stageQuery), db_InsertStage, currentMap, arg1, pos[0], pos[1], pos[2], angs[0], angs[1], angs[2]);
	g_hDatabase.Query(SQLCallback, stageQuery);
	PrintToChat(client, "Stage %s has been added", arg1);
	return Plugin_Continue;
}

public Action Command_DelStage(client, args)
{
	if (args < 1)
	{
		PrintToChat(client, "Please specify a name of the stage you want to delete");
		return Plugin_Continue;
	}
	if (args > 1)
	{
		PrintToChat(client, "Too many arguments");
		return Plugin_Continue;
	}

	char arg1[32];
	char delQuery[PLATFORM_MAX_PATH];
	GetCmdArgString(arg1, sizeof(arg1));
	g_hDatabase.Format(delQuery, sizeof(delQuery), db_DeleteStage, currentMap, arg1);
	g_hDatabase.Query(SQLCallback, delQuery);
	PrintToChat(client, "Stage %s has been deleted", arg1);
	return Plugin_Continue;
}

public Action Command_Stages(client, args)
{
	char sQuery[256];
	g_hDatabase.Format(sQuery, sizeof(sQuery), db_GetStageNames, currentMap);
	g_hDatabase.Query(SQLMenuCallback, sQuery, GetClientUserId(client));
}

public SQLMenuCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("Query failed: %s", error);
	}
	char stage[32];
	new client = GetClientOfUserId(data);
	Menu menu = new Menu(MenuHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End);
	if (results.HasResults)
	{
		while(results.FetchRow())
		{
			results.FetchString(0, stage, sizeof(stage));
			menu.AddItem(stage, stage);
		}
	}
	menu.SetTitle("Teleport locations");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char info[32];
			menu.GetItem(param2, info, sizeof(info));
			char tpQuery[256];
			g_hDatabase.Format(tpQuery, sizeof(tpQuery), db_GetTeleportLocation, currentMap, info);
			g_hDatabase.Query(SQL_TP_Callback, tpQuery, param1);
		}
		case MenuAction_Cancel:
		{
			if(param2 != MenuCancel_Exit)
			{
				PrintToChat(param1, "[SM] Nothing to display");
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

public SQL_TP_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	float position[3];
	float angles[3];
	new client = data;
	if (results.HasResults)
	{
		position[0] = results.FetchFloat(0);
		position[1] = results.FetchFloat(1);
		position[2] = results.FetchFloat(2);
		angles[0] = results.FetchFloat(3);
		angles[1] = results.FetchFloat(4);
		angles[2] = results.FetchFloat(5);
		TeleportEntity(client, position, angles, NULL_VECTOR);
		FakeClientCommandEx(client, "stoptimer");
	}
	else
	{
		PrintToChat(client, "[SM] Something went wrong.");
	}
}