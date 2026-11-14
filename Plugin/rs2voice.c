/*
 * RS2 Voice: TeamSpeak 3 client plugin for the MutTSVoice Rising Storm 2 mutator.
 *
 * The game (TSVInteraction, through TSVLink) connects to this plugin on 127.0.0.1 (port 25700 unless rs2voice.ini in
 * the TeamSpeak config folder says otherwise) and sends one text line per message:
 *
 *   HELLO <version> <steamid64>           the player's Steam ID
 *   CFG <proximity range in meters>
 *   TGT_BEGIN <channel> / TGT <id> ... / TGT_END
 *                                         the Steam IDs of everyone who should hear this player now
 *   PTT 1 <channel> / PTT 0               voice key held / let go
 *   LIS x y z fx fy fz ux uy uz           the camera: position (unreal units), forward and up
 *   POS <steamid> x y z                   a proximity talker this player can hear, and where they stand
 *   END                                   end of one frame of LIS and POS lines
 *   BYE                                   the game is closing the link
 *
 * and gets back:
 *
 *   TS <1|0>                              TeamSpeak is connected to a server or not
 *   CHAN <channel id> <channel name>      the TeamSpeak channel the player sits in (sent when it changes)
 *   MSG <text>                            a message to show the player
 *
 * How the voice gets to the right people:
 *  - Every plugin puts "rs2v=<steamid64>" in its TeamSpeak client's metadata, so each plugin can find the TeamSpeak
 *    client of any player in the game.
 *  - While the game is linked the microphone is off. Holding a voice key sets a whisper list with exactly the players
 *    the game says should hear, then turns the microphone on. With nobody to hear, it stays off (an empty whisper list
 *    would talk to the whole channel).
 *  - Squad voice is different: it is plain talk in the player's own TeamSpeak channel, so everyone sitting in that
 *    channel hears it, in the game or not.
 *  - Proximity talkers get a 3D position, so TeamSpeak plays them from their direction, and they fade to silence at
 *    the proximity range. Everyone else plays from the middle.

 */

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "teamspeak/public_definitions.h"
#include "teamspeak/public_errors.h"
#include "teamspeak/public_rare_definitions.h"
#include "ts3_functions.h"
#include "plugin_definitions.h"

#pragma comment(lib, "ws2_32.lib")

#define EXPORT __declspec(dllexport)
#define PLUGIN_API_VERSION 26
#define PLUGIN_VERSION "1.0"
#define DEFAULT_PORT 25700
#define MAX_PLAYERS 256
#define MAX_LINE 2048
#define META_PREFIX "rs2v="
#define CH_SQUAD 3   /* TSVRules.CH_SQUAD: plain talk in our own channel */

static struct TS3Functions ts3;
static char* g_pluginID = NULL;
static CRITICAL_SECTION g_lock;

/* ---- The link to the game */
static SOCKET g_listen = INVALID_SOCKET;
static SOCKET g_game = INVALID_SOCKET;
static HANDLE g_netThread = NULL;
static volatile LONG g_quit = 0;
static int g_port = DEFAULT_PORT;

/* ---- TeamSpeak */
static uint64 g_sch = 0;          /* the server connection in use */
static int g_tsConnected = 0;
static int g_savedInput = -1;     /* the microphone state before the game took it over, -1 while not taken */

/* ---- The game's state */
static char g_mySteam[32] = "";
static float g_rangeM = 75.0f;
static int g_talking = 0;
static int g_talkChannel = 0;
static uint64 g_lastChannel = 0; /* the channel last told to the game */
static void reportChannel(void);

typedef struct { char steam[32]; } SteamId;
static SteamId g_targets[MAX_PLAYERS];  static int g_numTargets = 0;
static SteamId g_newTargets[MAX_PLAYERS]; static int g_numNewTargets = 0;

/* Steam ID to TeamSpeak client, rebuilt from the clients' metadata */
typedef struct { anyID client; char steam[32]; int spatial; } ClientMap;
static ClientMap g_map[MAX_PLAYERS];  static int g_numMap = 0;
static DWORD g_mapBuilt = 0;
static int g_mapDirty = 1;

/* This frame's proximity talkers */
typedef struct { char steam[32]; TS3_VECTOR pos; } Spatial;
static Spatial g_frame[MAX_PLAYERS]; static int g_numFrame = 0;
static TS3_VECTOR g_lisPos, g_lisFwd, g_lisUp;
static int g_haveListener = 0;

/* ================================================================
 * Small helpers
 * ================================================================ */

static void logmsg(const char* fmt, ...)
{
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (ts3.logMessage)
        ts3.logMessage(buf, LogLevel_INFO, "RS2Voice", 0);
}

static void sendGame(const char* fmt, ...)
{
    char buf[MAX_LINE];
    int n;
    va_list ap;
    va_start(ap, fmt);
    n = vsnprintf(buf, sizeof(buf) - 2, fmt, ap);
    va_end(ap);
    if (n < 0)
        return;
    if (n > (int)sizeof(buf) - 3)
        n = (int)sizeof(buf) - 3;
    buf[n++] = '\r';
    buf[n++] = '\n';
    EnterCriticalSection(&g_lock);
    if (g_game != INVALID_SOCKET)
        send(g_game, buf, n, 0);
    LeaveCriticalSection(&g_lock);
}

static int isDigits(const char* s)
{
    if (!*s)
        return 0;
    for (; *s; s++)
        if (*s < '0' || *s > '9')
            return 0;
    return 1;
}

/* Unreal units (X north, Y east, Z up; 50 to the meter) to TeamSpeak's space in meters (x right, y up, z forward) */
static TS3_VECTOR toTS(float x, float y, float z, int isDirection)
{
    TS3_VECTOR v;
    float s = isDirection ? 1.0f : (1.0f / 50.0f);
    v.x = y * s;
    v.y = z * s;
    v.z = x * s;
    return v;
}

/* ================================================================
 * TeamSpeak clients by Steam ID
 * ================================================================ */

static void rebuildMap(void)
{
    anyID* clients = NULL;
    int i, n = 0;
    char* meta;
    char* p;

    if (!g_tsConnected || ts3.getClientList(g_sch, &clients) != ERROR_ok || !clients)
        return;

    /* Keep which clients were spatialized, so they can be put back in the middle */
    for (i = 0; clients[i] && n < MAX_PLAYERS; i++)
    {
        meta = NULL;
        if (ts3.getClientVariableAsString(g_sch, clients[i], CLIENT_META_DATA, &meta) != ERROR_ok || !meta)
            continue;
        p = strstr(meta, META_PREFIX);
        if (p)
        {
            char id[32];
            int k = 0;
            p += strlen(META_PREFIX);
            while (*p >= '0' && *p <= '9' && k < 31)
                id[k++] = *p++;
            id[k] = 0;
            if (k > 0)
            {
                int j, wasSpatial = 0;
                for (j = 0; j < g_numMap; j++)
                    if (g_map[j].client == clients[i])
                        wasSpatial = g_map[j].spatial;
                g_map[n].client = clients[i];
                strcpy_s(g_map[n].steam, sizeof(g_map[n].steam), id);
                g_map[n].spatial = wasSpatial;
                n++;
            }
        }
        ts3.freeMemory(meta);
    }
    ts3.freeMemory(clients);
    g_numMap = n;
    g_mapBuilt = GetTickCount();
    g_mapDirty = 0;
}

static void ensureMap(void)
{
    if (g_mapDirty || GetTickCount() - g_mapBuilt > 2000)
        rebuildMap();
}

static ClientMap* findClient(const char* steam)
{
    int i;
    for (i = 0; i < g_numMap; i++)
        if (strcmp(g_map[i].steam, steam) == 0)
            return &g_map[i];
    return NULL;
}

static ClientMap* findClientById(anyID id)
{
    int i;
    for (i = 0; i < g_numMap; i++)
        if (g_map[i].client == id)
            return &g_map[i];
    return NULL;
}

/* ================================================================
 * Our identity and the microphone
 * ================================================================ */

static void publishIdentity(int on)
{
    char meta[64];
    if (!g_tsConnected)
        return;
    if (on && g_mySteam[0])
        snprintf(meta, sizeof(meta), META_PREFIX "%s", g_mySteam);
    else
        meta[0] = 0;
    ts3.setClientSelfVariableAsString(g_sch, CLIENT_META_DATA, meta);
    ts3.flushClientSelfUpdates(g_sch, NULL);
}

static void setMic(int on)
{
    if (!g_tsConnected)
        return;
    ts3.setClientSelfVariableAsInt(g_sch, CLIENT_INPUT_DEACTIVATED, on ? INPUT_ACTIVE : INPUT_DEACTIVATED);
    ts3.flushClientSelfUpdates(g_sch, NULL);
}

/* The game is linked and TeamSpeak connected: the microphone is the game's now */
static void takeOver(void)
{
    int cur = 0;
    if (!g_tsConnected || g_game == INVALID_SOCKET || g_savedInput >= 0)
        return;
    if (ts3.getClientSelfVariableAsInt(g_sch, CLIENT_INPUT_DEACTIVATED, &cur) == ERROR_ok)
        g_savedInput = cur;
    else
        g_savedInput = INPUT_ACTIVE;
    publishIdentity(1);
    setMic(0);
    g_lastChannel = 0;
    reportChannel();
    logmsg("Game linked: microphone taken over (was %s)", g_savedInput == INPUT_ACTIVE ? "on" : "off");
}

static void resetSpatial(void)
{
    int i;
    for (i = 0; i < g_numMap; i++)
    {
        if (g_map[i].spatial && g_haveListener)
            ts3.channelset3DAttributes(g_sch, g_map[i].client, &g_lisPos);
        g_map[i].spatial = 0;
    }
}

/* Give everything back as it was */
static void giveBack(void)
{
    if (g_savedInput < 0)
        return;
    if (g_tsConnected)
    {
        ts3.requestClientSetWhisperList(g_sch, 0, NULL, NULL, NULL);
        resetSpatial();
        ts3.setClientSelfVariableAsInt(g_sch, CLIENT_INPUT_DEACTIVATED, g_savedInput);
        publishIdentity(0);
    }
    g_savedInput = -1;
    g_talking = 0;
    logmsg("Game unlinked: microphone given back");
}

/* Tells the game which channel we sit in, when it changes (Squad voice is that channel) */
static void reportChannel(void)
{
    anyID me = 0;
    uint64 ch = 0;
    char* name = NULL;

    if (!g_tsConnected || g_savedInput < 0 || g_game == INVALID_SOCKET)
        return;
    if (ts3.getClientID(g_sch, &me) != ERROR_ok || ts3.getChannelOfClient(g_sch, me, &ch) != ERROR_ok || ch == g_lastChannel)
        return;
    g_lastChannel = ch;
    if (ts3.getChannelVariableAsString(g_sch, ch, CHANNEL_NAME, &name) == ERROR_ok && name)
    {
        char clean[96];
        int i, k = 0;
        for (i = 0; name[i] && k < 95; i++)
            clean[k++] = (name[i] == '\r' || name[i] == '\n') ? ' ' : name[i];
        clean[k] = 0;
        sendGame("CHAN %llu %s", (unsigned long long)ch, clean);
        ts3.freeMemory(name);
    }
    else
        sendGame("CHAN %llu", (unsigned long long)ch);
}
/* ================================================================
 * Talking
 * ================================================================ */

/* Whisper to the current targets and switch the microphone to match */
static void applyTalk(void)
{
    anyID ids[MAX_PLAYERS + 1];
    int i, n = 0;
    ClientMap* c;

    if (!g_tsConnected || g_savedInput < 0)
        return;
    if (!g_talking)
    {
        setMic(0);
        ts3.requestClientSetWhisperList(g_sch, 0, NULL, NULL, NULL);
        return;
    }

    if (g_talkChannel == CH_SQUAD)
    {
        /* Squad: plain talk to our own channel */
        ts3.requestClientSetWhisperList(g_sch, 0, NULL, NULL, NULL);
        setMic(1);
        return;
    }

    ensureMap();
    for (i = 0; i < g_numTargets && n < MAX_PLAYERS; i++)
    {
        c = findClient(g_targets[i].steam);
        if (c)
            ids[n++] = c->client;
    }
    ids[n] = 0;

    if (n == 0)
    {
        /* Nobody to hear. An empty whisper list would talk to the whole channel, so stay quiet. */
        setMic(0);
        return;
    }
    ts3.requestClientSetWhisperList(g_sch, 0, NULL, ids, NULL);
    setMic(1);
}

/* ================================================================
 * 3D positions
 * ================================================================ */

static void applyFrame(void)
{
    int i, j, found;

    if (!g_tsConnected || g_savedInput < 0 || !g_haveListener)
        return;
    reportChannel();
    ensureMap();
    ts3.systemset3DListenerAttributes(g_sch, &g_lisPos, &g_lisFwd, &g_lisUp);

    for (i = 0; i < g_numMap; i++)
    {
        found = 0;
        for (j = 0; j < g_numFrame; j++)
        {
            if (strcmp(g_frame[j].steam, g_map[i].steam) == 0)
            {
                ts3.channelset3DAttributes(g_sch, g_map[i].client, &g_frame[j].pos);
                g_map[i].spatial = 1;
                found = 1;
                break;
            }
        }
        if (!found && g_map[i].spatial)
        {
            /* Not a proximity talker any more: back in the middle */
            ts3.channelset3DAttributes(g_sch, g_map[i].client, &g_lisPos);
            g_map[i].spatial = 0;
        }
    }
}

/* ================================================================
 * Messages from the game
 * ================================================================ */

static void handleLine(char* line)
{
    char* tok[16];
    int n = 0;
    char* ctx = NULL;
    char* t;

    for (t = strtok_s(line, " \t", &ctx); t && n < 16; t = strtok_s(NULL, " \t", &ctx))
        tok[n++] = t;
    if (n == 0)
        return;

    EnterCriticalSection(&g_lock);
    if (strcmp(tok[0], "HELLO") == 0 && n >= 3 && isDigits(tok[2]))
    {
        strcpy_s(g_mySteam, sizeof(g_mySteam), tok[2]);
        logmsg("Game linked, Steam ID %s", g_mySteam);
        sendGame("TS %d", g_tsConnected ? 1 : 0);
        takeOver();
        LeaveCriticalSection(&g_lock);
        return;
    }
    else if (strcmp(tok[0], "CFG") == 0 && n >= 2)
    {
        g_rangeM = (float)atof(tok[1]);
        if (g_rangeM < 1.0f)
            g_rangeM = 75.0f;
    }
    else if (strcmp(tok[0], "TGT_BEGIN") == 0)
    {
        g_numNewTargets = 0;
    }
    else if (strcmp(tok[0], "TGT") == 0)
    {
        int i;
        for (i = 1; i < n && g_numNewTargets < MAX_PLAYERS; i++)
            if (isDigits(tok[i]))
                strcpy_s(g_newTargets[g_numNewTargets++].steam, sizeof(SteamId), tok[i]);
    }
    else if (strcmp(tok[0], "TGT_END") == 0)
    {
        memcpy(g_targets, g_newTargets, sizeof(SteamId) * g_numNewTargets);
        g_numTargets = g_numNewTargets;
        if (g_talking)
            applyTalk();
    }
    else if (strcmp(tok[0], "PTT") == 0 && n >= 2)
    {
        g_talking = (tok[1][0] == '1');
        g_talkChannel = (n >= 3) ? atoi(tok[2]) : 0;
        applyTalk();
    }
    else if (strcmp(tok[0], "LIS") == 0 && n >= 10)
    {
        g_lisPos = toTS((float)atof(tok[1]), (float)atof(tok[2]), (float)atof(tok[3]), 0);
        g_lisFwd = toTS((float)atof(tok[4]), (float)atof(tok[5]), (float)atof(tok[6]), 1);
        g_lisUp = toTS((float)atof(tok[7]), (float)atof(tok[8]), (float)atof(tok[9]), 1);
        g_haveListener = 1;
        g_numFrame = 0;
    }
    else if (strcmp(tok[0], "POS") == 0 && n >= 5 && g_numFrame < MAX_PLAYERS && isDigits(tok[1]))
    {
        strcpy_s(g_frame[g_numFrame].steam, sizeof(g_frame[0].steam), tok[1]);
        g_frame[g_numFrame].pos = toTS((float)atof(tok[2]), (float)atof(tok[3]), (float)atof(tok[4]), 0);
        g_numFrame++;
    }
    else if (strcmp(tok[0], "END") == 0)
    {
        applyFrame();
    }
    else if (strcmp(tok[0], "BYE") == 0)
    {
        giveBack();
    }
    else if (strcmp(tok[0], "STATE") == 0)
    {
        /* For checking and fault finding: the plugin's own view */
        int deact = -1, i, spatial = 0;
        anyID me = 0;
        uint64 ch = 0;
        unsigned int e1 = 0, e2 = 0, e3 = 0;
        if (g_tsConnected)
        {
            e1 = ts3.getClientSelfVariableAsInt(g_sch, CLIENT_INPUT_DEACTIVATED, &deact);
            e2 = ts3.getClientID(g_sch, &me);
            e3 = ts3.getChannelOfClient(g_sch, me, &ch);
        }
        ensureMap();
        for (i = 0; i < g_numMap; i++)
            spatial += g_map[i].spatial;
        sendGame("STATE ts=%d linked=%d mic=%s talking=%d channel=%d targets=%d mapped=%d spatial=%d me=%u tschan=%llu errs=%u,%u,%u",
            g_tsConnected, g_savedInput >= 0, deact == INPUT_ACTIVE ? "on" : (deact == INPUT_DEACTIVATED ? "off" : "?"),
            g_talking, g_talkChannel, g_numTargets, g_numMap, spatial, (unsigned)me, (unsigned long long)ch, e1, e2, e3);
    }
    LeaveCriticalSection(&g_lock);
}

static void gameGone(void)
{
    EnterCriticalSection(&g_lock);
    if (g_game != INVALID_SOCKET)
    {
        closesocket(g_game);
        g_game = INVALID_SOCKET;
    }
    giveBack();
    g_mySteam[0] = 0;
    g_numTargets = 0;
    g_haveListener = 0;
    LeaveCriticalSection(&g_lock);
}

static DWORD WINAPI netThread(LPVOID unused)
{
    char buf[8192];
    char line[MAX_LINE];
    int lineLen = 0;

    (void)unused;
    while (!g_quit)
    {
        SOCKET s = accept(g_listen, NULL, NULL);
        if (s == INVALID_SOCKET)
        {
            if (g_quit)
                break;
            Sleep(200);
            continue;
        }
        EnterCriticalSection(&g_lock);
        if (g_game != INVALID_SOCKET)
        {
            /* A new game replaces an old link (a crashed game, a map change) */
            closesocket(g_game);
            giveBack();
        }
        g_game = s;
        LeaveCriticalSection(&g_lock);
        lineLen = 0;

        for (;;)
        {
            int got = recv(s, buf, sizeof(buf), 0), i;
            if (got <= 0)
                break;
            for (i = 0; i < got; i++)
            {
                char ch = buf[i];
                if (ch == '\n' || ch == '\r')
                {
                    if (lineLen > 0)
                    {
                        line[lineLen] = 0;
                        handleLine(line);
                    }
                    lineLen = 0;
                }
                else if (lineLen < MAX_LINE - 1)
                {
                    line[lineLen++] = ch;
                }
            }
        }
        EnterCriticalSection(&g_lock);
        if (g_game == s)
        {
            LeaveCriticalSection(&g_lock);
            gameGone();
        }
        else
        {
            closesocket(s);
            LeaveCriticalSection(&g_lock);
        }
    }
    return 0;
}

static int startListening(void)
{
    struct sockaddr_in a;
    WSADATA wsa;
    BOOL excl = TRUE;

    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
        return 0;
    g_listen = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (g_listen == INVALID_SOCKET)
        return 0;
    setsockopt(g_listen, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (const char*)&excl, sizeof(excl));
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons((unsigned short)g_port);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    if (bind(g_listen, (struct sockaddr*)&a, sizeof(a)) != 0 || listen(g_listen, 2) != 0)
    {
        logmsg("Could not listen on 127.0.0.1:%d (error %d)", g_port, WSAGetLastError());
        closesocket(g_listen);
        g_listen = INVALID_SOCKET;
        return 0;
    }
    g_netThread = CreateThread(NULL, 0, netThread, NULL, 0, NULL);
    return g_netThread != NULL;
}

/* ================================================================
 * TeamSpeak's plugin functions
 * ================================================================ */

EXPORT const char* ts3plugin_name(void) { return "RS2 Voice"; }
EXPORT const char* ts3plugin_version(void) { return PLUGIN_VERSION; }
EXPORT int ts3plugin_apiVersion(void) { return PLUGIN_API_VERSION; }
EXPORT const char* ts3plugin_author(void) { return "29th Infantry Division Engineer Corps"; }
EXPORT const char* ts3plugin_description(void)
{
    return "Rising Storm 2 voice through TeamSpeak: all, team, squad (your TeamSpeak channel), vehicle, command and proximity voice. "
           "Needs the MutTSVoice mutator on the game server.";
}
EXPORT void ts3plugin_setFunctionPointers(const struct TS3Functions funcs) { ts3 = funcs; }
EXPORT int ts3plugin_offersConfigure(void) { return PLUGIN_OFFERS_NO_CONFIGURE; }
EXPORT int ts3plugin_requestAutoload(void) { return 1; }

EXPORT void ts3plugin_registerPluginID(const char* id)
{
    size_t n = strlen(id) + 1;
    g_pluginID = (char*)malloc(n);
    if (g_pluginID)
        memcpy(g_pluginID, id, n);
}

EXPORT void ts3plugin_freeMemory(void* data) { free(data); }

static void checkConnection(uint64 sch)
{
    int status = 0;
    if (ts3.getConnectionStatus(sch, &status) == ERROR_ok && status == STATUS_CONNECTION_ESTABLISHED)
    {
        g_sch = sch;
        g_tsConnected = 1;
        g_mapDirty = 1;
    }
}

EXPORT int ts3plugin_init(void)
{
    char cfg[MAX_PATH] = "", ini[MAX_PATH];
    uint64* list = NULL;
    int i;

    InitializeCriticalSection(&g_lock);
    ts3.getConfigPath(cfg, sizeof(cfg));
    snprintf(ini, sizeof(ini), "%srs2voice.ini", cfg);
    g_port = GetPrivateProfileIntA("RS2Voice", "Port", DEFAULT_PORT, ini);

    /* Already connected when the plugin is turned on */
    if (ts3.getServerConnectionHandlerList(&list) == ERROR_ok && list)
    {
        uint64 cur = ts3.getCurrentServerConnectionHandlerID();
        for (i = 0; list[i]; i++)
            if (list[i] == cur)
                checkConnection(cur);
        for (i = 0; list[i] && !g_tsConnected; i++)
            checkConnection(list[i]);
        ts3.freeMemory(list);
    }

    if (!startListening())
    {
        if (ts3.printMessageToCurrentTab)
            ts3.printMessageToCurrentTab("RS2 Voice: could not open the local port for the game; is another copy running?");
        return 1;
    }
    logmsg("RS2 Voice %s listening on 127.0.0.1:%d", PLUGIN_VERSION, g_port);
    return 0;
}

EXPORT void ts3plugin_shutdown(void)
{
    InterlockedExchange(&g_quit, 1);
    gameGone();
    if (g_listen != INVALID_SOCKET)
    {
        closesocket(g_listen);
        g_listen = INVALID_SOCKET;
    }
    if (g_netThread)
    {
        WaitForSingleObject(g_netThread, 3000);
        CloseHandle(g_netThread);
        g_netThread = NULL;
    }
    WSACleanup();
    DeleteCriticalSection(&g_lock);
    free(g_pluginID);
    g_pluginID = NULL;
}

EXPORT void ts3plugin_onConnectStatusChangeEvent(uint64 sch, int newStatus, unsigned int errorNumber)
{
    (void)errorNumber;
    EnterCriticalSection(&g_lock);
    if (newStatus == STATUS_CONNECTION_ESTABLISHED)
    {
        if (!g_tsConnected)
        {
            g_sch = sch;
            g_tsConnected = 1;
            g_mapDirty = 1;
            g_savedInput = -1;
            sendGame("TS 1");
            takeOver();
        }
    }
    else if (newStatus == STATUS_DISCONNECTED && sch == g_sch && g_tsConnected)
    {
        g_tsConnected = 0;
        g_savedInput = -1;
        g_talking = 0;
        g_numMap = 0;
        sendGame("TS 0");
    }
    LeaveCriticalSection(&g_lock);
}

EXPORT void ts3plugin_onUpdateClientEvent(uint64 sch, anyID clientID, anyID invokerID, const char* invokerName, const char* invokerUniqueIdentifier)
{
    (void)clientID; (void)invokerID; (void)invokerName; (void)invokerUniqueIdentifier;
    if (sch == g_sch)
        g_mapDirty = 1;
}

EXPORT void ts3plugin_onClientMoveEvent(uint64 sch, anyID clientID, uint64 oldChannelID, uint64 newChannelID, int visibility, const char* moveMessage)
{
    (void)clientID; (void)oldChannelID; (void)newChannelID; (void)visibility; (void)moveMessage;
    if (sch == g_sch)
        g_mapDirty = 1;
}

/* Proximity talkers fade from full volume at 10% of the range to silence at the range */
EXPORT void ts3plugin_onCustom3dRolloffCalculationClientEvent(uint64 sch, anyID clientID, float distance, float* volume)
{
    ClientMap* c;
    float fullR, f;

    if (sch != g_sch || !volume)
        return;
    EnterCriticalSection(&g_lock);
    c = findClientById(clientID);
    if (c && c->spatial && g_rangeM > 0.0f)
    {
        fullR = g_rangeM * 0.1f;
        if (distance <= fullR)
            f = 1.0f;
        else if (distance >= g_rangeM)
            f = 0.0f;
        else
            f = 1.0f - (distance - fullR) / (g_rangeM - fullR);
        *volume = f * f;
    }
    else if (g_savedInput >= 0)
    {
        *volume = 1.0f;
    }
    LeaveCriticalSection(&g_lock);
}
