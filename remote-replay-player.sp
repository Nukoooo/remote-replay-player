#include <sourcemod>
#include <ripext>
#include <shavit>

// Straight from shavit-replay. YES! :spaghetti:
enum struct sqlstring_t
{
    char user_table_name[64];
    char playertime_table_name[64];

    char map_column_name[64];
    char style_column_name[64];
    char track_column_name[64];
    char username_column_name[64];
    char steamid_column_name[64];

    char query[768];
}

char g_sCreatedReplayName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
int g_iCreatedReplayIndex[MAXPLAYERS + 1];
int g_iCreatedReplayStyle[MAXPLAYERS + 1];
int g_iCreatedReplayTrack[MAXPLAYERS + 1];
bool g_bShouldPlayReplay[MAXPLAYERS + 1];

char g_sCurrentMap[256];
chatstrings_t g_sChatStrings;

bool g_bUseMysql;
sqlstring_t g_sMysqlStrings;
Database g_hDatabase;

ConVar g_cvReplayStartDelay;
ConVar g_cvServerUrl;
ConVar g_cvIgnoreFileCheck;
ConVar g_cvCheckRepalyTime;

public Plugin myinfo =
{
	name = "Remote replays player",
	author = "Nuko chan",
	description = "Download replays from the remote server and play",
	version = "1.0",
	url = "https://github.com/NukoOoOoOoO/remote-replay-player"
}

public void OnPluginStart()
{
    g_cvReplayStartDelay = CreateConVar("rrp_replay_start_delay", "5.0", "same as shavit_replay_delay", 0, true, 0.0);
    g_cvServerUrl = CreateConVar("rrp_server_url", "http://127.0.0.1:5000/replays/", "url to download replays");
    g_cvIgnoreFileCheck = CreateConVar("rrp_ignore_file_check", "0", "Ignore the existence of files if enabled", 0, true, 0.0, true, 1.0);
    g_cvCheckRepalyTime = CreateConVar("rrp_check_replay_time", "0", "Check if the time of downloaded replay is longer than the server record (Callback server should handle this)", 0, true, 0.0, true, 1.0);

    RegConsoleCmd("sm_dr", Command_DownloadReplay);
    RegConsoleCmd("sm_stopreplay", Command_StopReplay);

    LoadConfig();

    if (g_bUseMysql)
    {
        if (!g_hDatabase)
        {
            g_hDatabase = GetDatabase();
        }
    }
}

public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client) || IsClientSourceTV(client) || IsClientReplay(client) || !IsClientAuthorized(client))
        return;

    g_iCreatedReplayTrack[client] = 0;
    g_iCreatedReplayStyle[client] = 0;
    g_sCreatedReplayName[client] = "I don't have a replay name!";
    g_bShouldPlayReplay[client] = true; // Theoretically we will not have ANY problem with it...
}

public void OnMapStart()
{
    GetCurrentMap(g_sCurrentMap, 256);

    char sFolder[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sFolder, PLATFORM_MAX_PATH, "data/downloaded_replay");

    if (!DirExists(sFolder))
    {
        CreateDirectory(sFolder, 511);
    }
}

public void OnMapEnd()
{
    char sPath[256];
    for (int i = 0; i < STYLE_LIMIT; i++)
    {
        for(int j = 0; j < TRACKS_SIZE; j++)
        {
            BuildPath(Path_SM, sPath, 256, "data/downloaded_replay/%s_%d_%d.replay", g_sCurrentMap, i, j);
            if (FileExists(sPath))
            {
                DeleteFile(sPath);
            }
        }
    }
}

bool CreateReplayFile(int client, int style, int track, char[] path, int size)
{
    char sFolder[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sFolder, PLATFORM_MAX_PATH, "data/downloaded_replay");

    if (!DirExists(sFolder))
    {
        if (!CreateDirectory(sFolder, 511))
        {
            return false;
        }
    }

    BuildPath(Path_SM, path, size, "data/downloaded_replay/%s_%d_%d.replay", g_sCurrentMap, style, track);

    g_iCreatedReplayStyle[client] = style;
    g_iCreatedReplayTrack[client] = track;

    if (!g_cvIgnoreFileCheck.BoolValue)
    {
        if (FileExists(path))
        {
            StartReplay(client, path);
            return false;
        }
    }

    return true;
}

public Action Command_DownloadReplay(int client, int args)
{
    if (!client)
    {
        ReplyToCommand(client, "Not usable in server console");
        return Plugin_Handled;
    }

    Reset(client);

    char style_[8];
    GetCmdArg(1, style_, 8);
    char track_[8];
    GetCmdArg(2, track_, 8);

    int style = StringToInt(style_);
    int track = StringToInt(track_);

    char server_url[128];
    g_cvServerUrl.GetString(server_url, 128);

    char url[512];
    FormatEx(url, 512, "%s?map=%s&style=%d&track=%d", server_url, g_sCurrentMap, style, track);

    if (g_cvCheckRepalyTime.BoolValue)
    {
        FormatEx(url, 512, "%s&time=%.3f", url, Shavit_GetWorldRecord(style, track));
    }

    HTTPRequest request = new HTTPRequest(url);
    char path[PLATFORM_MAX_PATH];

    if (CreateReplayFile(client, style, track, path, PLATFORM_MAX_PATH))
    {
        request.DownloadFile(path, OnRepalyDownloaded, GetClientUserId(client));
    }

    return Plugin_Handled;
}

public Action Command_StopReplay(int client, int args)
{
    if (!client)
    {
        ReplyToCommand(client, "Not usable in server console");
        return Plugin_Handled;
    }

    if (g_iCreatedReplayIndex[client] == 0)
    {
        Shavit_PrintToChat(client, "You didn't start a replay");
        return Plugin_Handled;
    }

    KickClient(g_iCreatedReplayIndex[client]);
    Reset(client);
    Shavit_PrintToChat(client, "Replay is stopped");

    return Plugin_Handled;
}

void OnRepalyDownloaded(HTTPStatus status, any value)
{
    int client = GetClientOfUserId(value);
    if (!client)
    {
        return;
    }

    // Note: Server should handle this if the target file doesnt exist
    // otherwise it will fail to load and print errors to servre console
    // which you dont really want to see :)
    if (status != HTTPStatus_OK) 
    {
        Shavit_PrintToChat(client, "Failed to start a replay. Error code: %s%d", g_sChatStrings.sWarning, status);
        return;
    }

    char path[512];
    BuildPath(Path_SM, path, 512, "data/downloaded_replay/%s_%d_%d.replay", g_sCurrentMap, g_iCreatedReplayStyle[client], g_iCreatedReplayTrack[client]);

    StartReplay(client, path);
} 

void StartReplay(int client, const char[] path)
{
    if (!FileExists(path))
    {
        Shavit_PrintToChat(client, "Failed to start a replay. R: %sFile doesnt exist", g_sChatStrings.sWarning);
        return;
    }

    int result = Shavit_StartReplayFromFile(g_iCreatedReplayStyle[client], g_iCreatedReplayTrack[client], g_cvReplayStartDelay.FloatValue, client, -1, Replay_Dynamic, true, path);
    if (result == 0)
    {
        Shavit_PrintToChat(client, "%sFailed to create replay bot.", g_sChatStrings.sWarning);
    }
    else
    {
        g_iCreatedReplayIndex[client] = result;
        QueryReplayName(client);
        Shavit_PrintToChat(client, "Replay is started.");
    }
}

void LoadConfig()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/remote-replay-player.cfg");

    KeyValues kv = new KeyValues("RemoteReplayPlayer");

    if (!kv.ImportFromFile(sPath))
    {
        delete kv;
        SetFailState("Failed to load config, make sure \"configs/remote-replay-player.cfg\" exist ");
        return;
    }

    char temp[4];
    g_bUseMysql = false;

    kv.GetString("use_mysql", temp, 4);
    int num = StringToInt(temp);

    if (num > 0)
    {
        g_bUseMysql = true;
    }

    kv.GetString("user_table", g_sMysqlStrings.user_table_name, 64, "users");
    kv.GetString("playertime_table", g_sMysqlStrings.playertime_table_name, 64, "playertimes");

    kv.GetString("map_column_name", g_sMysqlStrings.map_column_name, 64, "map");
    kv.GetString("style_column_name", g_sMysqlStrings.style_column_name, 64, "style");
    kv.GetString("track_column_name", g_sMysqlStrings.track_column_name, 64, "track");
    kv.GetString("username_column_name", g_sMysqlStrings.username_column_name, 64, "name");
    kv.GetString("steamid_column_name", g_sMysqlStrings.steamid_column_name, 64, "auth");

    kv.GetString("query", g_sMysqlStrings.query, 768, "EmptyQueryBoi");

    delete kv;

}

Database GetDatabase()
{
    Database db = null;
    char error[256];

    if (SQL_CheckConfig("rrp"))
    {
        if (!(db = SQL_Connect("rrp", true, error, 256)))
        {
            g_bUseMysql = false;
            LogError("[!] Failed to connect to database. R:%s", error);
            return null;
        }
    }

    return db;
}

void QueryReplayName(int client)
{
    if (!g_bUseMysql) return;

    char query[768];
    strcopy(query, 768, g_sMysqlStrings.query);

    ReplaceString(query, 768, "{username_column_name}", g_sMysqlStrings.username_column_name);
    ReplaceString(query, 768, "{playertime_table}", g_sMysqlStrings.playertime_table_name);
    ReplaceString(query, 768, "{user_table}", g_sMysqlStrings.user_table_name);
    ReplaceString(query, 768, "{steamid_column_name}", g_sMysqlStrings.steamid_column_name);
    ReplaceString(query, 768, "{map_column_name}", g_sMysqlStrings.map_column_name);
    ReplaceString(query, 768, "{style_column_name}", g_sMysqlStrings.style_column_name);
    ReplaceString(query, 768, "{track_column_name}", g_sMysqlStrings.track_column_name);

    char style_track[4];
    Format(style_track, 4, "%d", g_iCreatedReplayStyle[client]);
    ReplaceString(query, 768, "{style}", style_track);

    Format(style_track, 4, "%d", g_iCreatedReplayTrack[client]);
    ReplaceString(query, 768, "{track}", style_track);

    ReplaceString(query, 768, "{map}", g_sCurrentMap);

    DataPack pack = new DataPack();
    pack.WriteCell(client);
    g_hDatabase.Query(SQL_QueryReplayName_Callback, query, pack, DBPrio_High);
}

public void SQL_QueryReplayName_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
    data.Reset();
    int client = data.ReadCell();
    delete data;

    if (!results)
    {
        g_sCreatedReplayName[client] = "I don't have a replay name!";
        Shavit_SetReplayCacheName(g_iCreatedReplayIndex[client], g_sCreatedReplayName[client]);

        LogError("[RRP] Failed to get replay name. Reason: %s", error);
        return;
    }

    if (results.FetchRow())
    {
        results.FetchString(0, g_sCreatedReplayName[client], MAX_NAME_LENGTH);
    }

    Shavit_SetReplayCacheName(g_iCreatedReplayIndex[client], g_sCreatedReplayName[client]);
}

void Reset(int client)
{
    g_iCreatedReplayIndex[client] = 0;
    g_iCreatedReplayStyle[client] = 0;
    g_iCreatedReplayTrack[client] = 0;
    g_sCreatedReplayName[client] = "I don't have a replay name!";
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(g_sChatStrings);
}