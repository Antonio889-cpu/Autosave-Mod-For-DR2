DANGANRONPA 2: GOODBYE DESPAIR - AUTOSAVE MOD 1.0
LINUX AND STEAM DECK (PROTON) - EXPERIMENTAL
==================================================

The mod works with the Windows version of the game, so Steam must run the game
through Proton. On Steam Deck, do these steps in Desktop Mode.

INSTALL
1. In Steam, right-click the game and open Properties > Compatibility.
2. Enable "Force the use of a specific Steam Play compatibility tool" and pick
   a Proton version. Wait for Steam to finish downloading the game.
3. Start the game once, then close it.
4. Extract this archive, open a terminal in the extracted folder and run:

     bash install.sh

5. In Steam, open Properties > General and set Launch Options to:

     WINEDLLOVERRIDES="d3dx9_43=n,b" %command%

6. Start the game. Autosaves appear in the Load menu with an [AUTO] tag.

OPTIONS
  bash install.sh --interval 10     Save every 2, 5, 10, 15 or 30 minutes
  bash install.sh --notify          Show the on-screen notification
  bash install.sh --no-backups      Do not keep backup copies
  bash install.sh --game-dir PATH   Use a specific game folder

The notification is off by default because it may not display correctly in
Steam Deck Gaming Mode.

UNINSTALL
  bash install.sh --uninstall

Then clear the Launch Options in Steam. Your saves are kept.

TROUBLESHOOTING
If no autosaves appear, check that the Launch Options are set, then open
dr2_autosave.log in the game folder. If that file does not exist, Proton did
not load the mod.

Saves made with the native Linux version may not appear in the Proton version.

Unofficial fan-made mod, not affiliated with or endorsed by Spike Chunsoft.
Characters and sprites belong to their respective owners.
