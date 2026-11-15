# MutTSVoice: TeamSpeak voice for Rising Storm 2

MutTSVoice moves the game's voice chat onto **TeamSpeak 3**. Players keep their normal voice keys. While their TeamSpeak plugin is running (and they haven't turned it off with `mutate tsvoice off`), those keys talk through TeamSpeak instead of the game's own voice chat:

- **Squad voice** is your **TeamSpeak channel**, like TeamSpeak's own push-to-talk: everyone sitting in the same TeamSpeak channel as you hears you.
- **The main Voice Chat key** talks on the channel picked with the game's **Change Voice Channel** key (O by default), as in the game: Team to begin with, then Squad (your TeamSpeak channel), Vehicle, Proximity, Command and All as you press it.
- **All, Team, Vehicle and Command** voice reach exactly the players the game would pick, wherever they sit on the TeamSpeak server.
- **Proximity** voice comes from the speaker's direction and fades out with distance.

There are two parts:

1. **The mutator** (`MutTSVoice`) goes on the game server.
2. **The RS2 Voice TeamSpeak plugin** goes into each player's TeamSpeak. Players without it keep the game's own voice chat as normal.

## Contents

1. For players: setting up
2. The voice channels
3. Commands
4. Server settings
5. Player settings
6. Building the plugin
7. How it works

## 1. For players: setting up

1. **Install the plugin:** quit TeamSpeak completely (also from the system tray), then double-click `RS2Voice.ts3_plugin` and TeamSpeak installs it. If TeamSpeak says the plugin is a "Bad Image" or fails to load it (LoadLibrary error 193), the plugin file is empty: quit TeamSpeak and install it again. Then check it is ticked under TeamSpeak's *Tools > Options > Addons*.
2. **TeamSpeak's microphone setting:** while the game is running, the plugin keeps your microphone off and only turns it on while you hold a voice key in the game. Voice Activation or Continuous Transmission work best. Push-to-Talk works too, but then your TeamSpeak key still talks into your channel as well.
3. **Join the TeamSpeak server** the game server names (type `mutate tsvoice` in the game to see it). Sit in your squad's channel: that channel is your Squad voice.
4. **Play.** When the game finds the plugin you see *"[TS Voice] Linked to TeamSpeak"*. From then on your voice keys talk on TeamSpeak.

While the game is linked, the plugin keeps your microphone off until you hold a voice key. When you leave the game, your microphone goes back to how it was.

## 2. The voice channels

These are the game's normal voice keys. Nothing new to learn.

| Game voice key | On TeamSpeak, who hears you |
| :--- | :--- |
| Squad voice | Everyone in **your TeamSpeak channel**, whether they are in the game or not, and whatever team they are on |
| Team voice | Your team |
| All voice | Everyone in the game |
| Vehicle voice | The crew of your vehicle or helicopter |
| Command voice | Squad leaders and the commander of your team (you must be one) |
| Proximity voice | Anyone within 75 meters, **including enemies**. Their voice comes from your direction and gets quieter with distance |
| The main Voice Chat key (CapsLock by default) | The channel picked with the game's Change Voice Channel key (O by default), shown by the game when you press it. The game starts on Team; Squad is your TeamSpeak channel. Pressing O while holding the key moves you to the new channel straight away |

- If you can't talk on a channel right now, the key talks to your team instead, the same as the game does (Vehicle with no vehicle, Command when you aren't a leader).
- **The dead** are heard only by other dead players, the same as the game, unless the server changes that. Squad voice is not affected: it is plain talk in your TeamSpeak channel.
- **Spectators** reach only other spectators, except in Squad voice.
- Who is talking on TeamSpeak that you can hear (and you, while you talk) shows on the left of the screen in the game's own voice pop-up, exactly like the game's voice chat: the name in the game's HUD font with the channel (TEAM, SQUAD, LOCAL, ...) under it, in team colours. It uses the pop-up's free rows, after anyone on the game's own voice chat, up to its 4 rows. An enemy talking on local (proximity) voice is heard but not shown.
- Only players who have the plugin running can hear TeamSpeak voice. Everyone else uses the game's voice chat.

## 3. Commands

| Command | What it does |
| :--- | :--- |
| `mutate tsvoice` | Shows the server's TeamSpeak address, whether your plugin is linked, and your TeamSpeak channel |
| `mutate tsvoice off` | Turns TeamSpeak voice off for you: all your voice keys use the game's voice chat, and the plugin gives your microphone back. Saved on your computer |
| `mutate tsvoice on` | Turns TeamSpeak voice back on (it is on to begin with) |
| `mutate tsvoice who` | Lists every player: plugin linked or not, and which TeamSpeak channel they sit in |
| `mutate tsvoice help` | Lists the commands |

## 4. Server settings

On the WebAdmin **Mutators** page, **MutTSVoice Settings** (two tabs: **Voice** and **TeamSpeak server**), or in `ROMutTSVoice_Server.ini` on the server under `[MutTSVoice.MutTSVoice]`. Changes from the WebAdmin page apply to everyone straight away. The page needs the server's `MutatorSettings` package and `MutTSVoice.int` (its labels).

| Setting | What it does | Default |
| :--- | :--- | :--- |
| `ProximityRangeMeters` | How far proximity voice carries, in meters (5 to 500) | 75 (like the game) |
| `bProximitySameTeamOnly` | Proximity voice only reaches your own team. Off: enemies close by hear you too | Off |
| `bLetDeadTalkToLiving` | Living players can hear the dead (not counting Squad voice) | Off |
| `bEnemiesOverhear` | Enemies within the proximity range overhear Squad, Team, Vehicle and Command talk, from the talker's direction, as if they heard them speak. Teammates still hear it on the channel as usual. Overheard enemies aren't named in the voice pop-up | Off |
| `TeamSpeakAddress` | The TeamSpeak server players should join. Shown by `mutate tsvoice` | Empty |
| `TeamSpeakChannel` | Where players should sit while playing. Shown by `mutate tsvoice` | Empty |

The mutator is workshop item **3839741457** (unlisted). A server downloads it when `ServerSubscribedWorkshopItems=3839741457` is in its `ROEngine.ini` (added to the 29th's Company, Platoon, Euro and Bat servers on 2026-11-14), and runs it when `MutTSVoice.MutTSVoice` is added to its mutator list (the start-up command line in the hosting control panel).

**The TeamSpeak server** must let players whisper (the default server groups do). If whispering is blocked, every channel except Squad stays silent.

## 5. Player settings

| Where | Setting | What it does | Default |
| :--- | :--- | :--- | :--- |
| `ROMutTSVoice_Client.ini`, `[MutTSVoice.TSVInteraction]` | `bDisableTeamSpeak` | TeamSpeak voice off (set by `mutate tsvoice off` / `on`) | Off |
| `ROMutTSVoice_Client.ini`, `[MutTSVoice.TSVInteraction]` | `bDisableTalkerList` | Hides the list of who is talking | Off |
| `ROMutTSVoice_Client.ini`, `[MutTSVoice.TSVInteraction]` | `PluginPort` | The plugin's port. Only change it together with the plugin's | 25700 |
| `rs2voice.ini` in TeamSpeak's settings folder (`%APPDATA%\TS3Client`), `[RS2Voice]` | `Port` | The port the plugin listens on, on your own computer only | 25700 |

## 6. Building the plugin

The plugin is in the `Plugin` folder. It needs the Visual Studio C++ build tools (`winget install Microsoft.VisualStudio.2022.BuildTools`, with "Desktop development with C++").

| Command | What it does |
| :--- | :--- |
| `Plugin\Build-Plugin.ps1` | Downloads TeamSpeak's plugin headers if they are missing, builds `build\rs2voice_win64.dll`, and packs `build\RS2Voice.ts3_plugin` (the installer players double-click) |
| `Plugin\Build-Plugin.ps1 -Install` | The same, then copies the plugin straight into your own TeamSpeak (close TeamSpeak first) |
| `Plugin\Test-Plugin.ps1 -SteamId <your Steam ID>` | Checks the plugin without the game: links to it the way the game does and prints what it answers. TeamSpeak must be running with the plugin on |

The TeamSpeak headers belong to TeamSpeak, so they are not kept in git.

## 7. How it works

- **Finding each other:** every player's plugin writes their Steam ID into their TeamSpeak client's details, so each plugin can tell which TeamSpeak user is which player in the game.
- **The game and the plugin** talk over a connection on your own computer only (127.0.0.1, port 25700). Nothing goes from the game server to TeamSpeak.
- **Choosing who hears you:** when you hold a voice key, your game works out who should hear you, using the same rules as the game's voice chat. It sends their Steam IDs to your plugin, a few times a second, so proximity voice follows people as they move. The plugin *whispers* to exactly those TeamSpeak users. If nobody should hear, the microphone stays off.
- **Squad voice** is different: the plugin simply talks into your own TeamSpeak channel. The plugin also tells the game which channel you are in, so everyone's talker list and `mutate tsvoice who` show it.
- **Proximity voice:** ten times a second, your game tells the plugin where your camera is and where each proximity talker you can hear is standing. TeamSpeak then plays their voice from that direction, at full volume up to 7.5 meters, fading to silence at 75 meters.
- **The server** only keeps, for every player, their Steam ID, their TeamSpeak channel, which voice channel they are talking on, and whether their plugin is linked. It sends these to everyone so the talker lists match.
