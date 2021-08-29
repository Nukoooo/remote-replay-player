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
    g_cvReplayStartDelay = CreateConVar("rrp_replay_start_delay", "5.0", "same as shavit_replay_delay", 0, true, -1.0);
    g_cvServerUrl = CreateConVar("rrp_server_url", "http://127.0.0.1:5000/replays/", "url to download replays");
    g_cvIgnoreFileCheck = CreateConVar("rrp_ignore_file_check", "0", "Ignore the existence of files if enabled", 0, true, 0.0, true, 1.0);
    g_cvCheckRepalyTime = CreateConVar("rrp_check_replay_time", "0", "Check if the time of downloaded replay is longer than the server record (Callback server should handle this)", 0, true, 0.0, true, 1.0);

    RegConsoleCmd("sm_dr", Command_DownloadReplay);

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
        if (!CreateDirectory(sFolder, 511))
        {
        }
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

// I don't have any plan on supporting other replay formats
// Make a pr if you want to
bool IsBTimesReplay(int client, const char[] path)
{
    if (!FileExists(path))
    {
        return false;
    }

    File f = OpenFile(path, "rb");
    if (!f)
    {
        return false;
    }

    any header[2];
    f.Read(header, 2, 4);

    // Ghetto way but works
    char info[16];
    FormatEx(info, 16, "%s%s", header[0], header[1]);

    // OK we just read a bad/empty file, don't play it
    if (strlen(info) == 0)
    {
        g_bShouldPlayReplay[client] = false;
        return false;
    }

    if (StrContains(info, ":{SHAVI") != -1)
    {
        return false;
    }

    return true;
}

bool PlayBTimesReplay(const char[] path, frame_cache_t cache)
{
    File f = OpenFile(path, "rb");
    if (!f)
    {
        return false;
    }

    any header[2];
    f.Read(header, 2, 4);
    cache.fTime = header[1]; // The time yo

    any data[sizeof(frame_t)];
    delete cache.aFrames;

    // Only 6 cells are used: Pos[3] Ang[2] Buttons
    cache.aFrames = new ArrayList(6);

    int iTimerStartTick = -1, iTimerEndTick = -1;
    while (!f.EndOfFile())
    {
        f.Read(data, 6, 4);
        cache.aFrames.PushArray(data, 6);

        // I actually love how "smart" blacky was 
        // What if some hackers hop in a csgo bhop server and use "No duck cooldown"?
        if (data[5] & IN_BULLRUSH && iTimerEndTick == -1)
        {
            if (iTimerStartTick == -1)
            {
                iTimerStartTick = cache.aFrames.Length - 1;
            }
            else
            {
                iTimerEndTick = cache.aFrames.Length - 1;
            }
        }

    }

    cache.iReplayVersion = 0x01;
    // TODO: (Maybe?)
    // Get WR Holder name from the server?
    cache.sReplayName = "Invalid";
    cache.fTickrate = 1.0 / GetTickInterval();
    cache.bNewFormat = true;
    cache.iPreFrames = iTimerStartTick;
    cache.iPostFrames = cache.aFrames.Length - iTimerEndTick;
    cache.iFrameCount = cache.aFrames.Length - cache.iPreFrames - cache.iPostFrames;
    
    return true;
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

    g_bShouldPlayReplay[client] = true;

    if (IsBTimesReplay(client, path))
    {

        // bTimes replay only !!!!!11
        if (g_bShouldPlayReplay[client])
        {
            frame_cache_t cache;
            if (PlayBTimesReplay(path, cache))
            {
                int result = Shavit_StartReplayFromFrameCache(g_iCreatedReplayStyle[client], g_iCreatedReplayTrack[client], g_cvReplayStartDelay.FloatValue, client, -1, Replay_Dynamic, true, cache);
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
            else
            {
                Shavit_PrintToChat(client, "Failed to load the replay. R: %sBad replay file", g_sChatStrings.sVariable);
            }
        }
        else
        {
            Shavit_PrintToChat(client, "Failed to load the replay. R: %sBad replay file", g_sChatStrings.sVariable);
        }

    }
    else
    {
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
}

void LoadConfig()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/remote-replay-player.cfg");

    KeyValues kv = new KeyValues("RemoteReplayPlyaer");

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