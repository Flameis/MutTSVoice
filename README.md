# MutTSVoice - TeamSpeak voice for Rising Storm 2

*In development: it builds, but it has not been tried in a real game with TeamSpeak yet. See section 8.*

MutTSVoice moves the game's voice chat onto **TeamSpeak 3**. Players keep their normal voice keys. While their TeamSpeak plugin is running, those keys talk through TeamSpeak instead of the game's own voice chat:

- **Squad** voice is your **TeamSpeak channel**: everyone sitting in the same TeamSpeak channel as you hears you.
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
8. What has been checked

## 1. For players: setting up

1. **Install the plugin:** double-click `RS2Voice.ts3_plugin` and TeamSpeak installs it. Then check it is ticked under TeamSpeak's *Tools > Options > Addons*.
2. **Set TeamSpeak's microphone to Voice Activation or Continuous Transmission, not Push-to-Talk.** While the game is running, the plugin keeps your microphone off and only turns it on while you hold a voice key in the game. With TeamSpeak's own push-to-talk on, you would have to press both.
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
| The main voice key | Whatever channel the game's "change voice channel" key is set to |

- If you can't talk on a channel right now, the key talks to your team instead, the same as the game does (Vehicle with no vehicle, Command when you aren't a leader).
- **The dead** are heard only by other dead players, the same as the game, unless the server changes that. Squad voice is not affected: it is plain talk in your TeamSpeak channel.
- **Spectators** reach only other spectators, except in Squad voice.
- On the right of the screen, a short list shows who is talking on TeamSpeak that you can hear, and on which channel.
- Only players who have the plugin running can hear TeamSpeak voice. Everyone else uses the game's voice chat.

## 3. Commands

| Command | What it does |
| :--- | :--- |
| `mutate tsvoice` | Shows the server's TeamSpeak address, whether your plugin is linked, and your TeamSpeak channel |
| `mutate tsvoice who` | Lists every player: plugin linked or not, and which TeamSpeak channel they sit in |
| `mutate tsvoice help` | Lists the commands |

## 4. Server settings

In `MutTSVoice_Server.ini` on the server, under `[MutTSVoice.MutTSVoice]`:

| Setting | What it does | Default |
| :--- | :--- | :--- |
| `ProximityRangeMeters` | How far proximity voice carries, in meters | 75 (like the game) |
| `bProximitySameTeamOnly` | Proximity voice only reaches your own team. Off: enemies close by hear you too | Off |
| `bLetDeadTalkToLiving` | Living players can hear the dead (not counting Squad voice) | Off |
| `TeamSpeakAddress` | The TeamSpeak server players should join. Shown by `mutate tsvoice` | Empty |
| `TeamSpeakChannel` | Where players should sit while playing. Shown by `mutate tsvoice` | Empty |

Add the mutator to the server's mutator list as `MutTSVoice.MutTSVoice`.

**The TeamSpeak server** must let players whisper (the default server groups do). If whispering is blocked, every channel except Squad stays silent.

## 5. Player settings

| Where | Setting | What it does | Default |
| :--- | :--- | :--- | :--- |
| `MutTSVoice_Client.ini`, `[MutTSVoice.TSVInteraction]` | `bDisableTalkerList` | Hides the list of who is talking | Off |
| `MutTSVoice_Client.ini`, `[MutTSVoice.TSVInteraction]` | `PluginPort` | The plugin's port. Only change it together with the plugin's | 25700 |
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

## 8. What has been checked

- **Builds:** the mutator compiles with no errors or warnings. The plugin builds and has every function TeamSpeak looks for.
- **Test harness** (`THSuiteTSVoice`, *compiled, not yet run*): who hears whom on every channel, including the dead, spectators, enemies and the settings; Squad following the TeamSpeak channel; which game key talks on which channel; every player getting their info; `mutate tsvoice` and `who`; the voice tool being put in front of the game's input; keys being left to the game when no plugin is linked; and the plugin's messages.
- **Not checked yet (needs TeamSpeak and a real game):**
  - the plugin loading in TeamSpeak;
  - the game linking to it;
  - whispering reaching the right people;
  - Squad channel talk;
  - the microphone being taken over and given back;
  - proximity voice direction (left and right could come out swapped) and fading;
  - the talker list on screen. The harness can't check on-screen drawing or sound.
