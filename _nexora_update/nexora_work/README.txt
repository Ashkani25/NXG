NEXORA Disc Football - v2 (floating 3D menu, 5 new pitches, 3 new balls)

Quick browser test: serve this folder (npx serve .) and open index.html.
Android build: unchanged (npm install -> npm run android:add -> npm run android:sync -> npm run android:open).
The Capacitor web folder is www/ (already contains the same files as the root).

New pitches : arena, street (neon), dragon, dragon2, persia  -> assets/fields/*.jpg
New balls   : b4 (classic), b5 (multicolour), b6 (neon carbon) -> assets/balls/*.png
UI assets   : assets/ui/*.webp + bg_menu.jpg / bg_sub.jpg
Pitch geometry (touchlines, goal lines, kick-off spot, goal width/depth) is stored per pitch in the FIELDS array inside index.html.

v3 changes: 8 new pitches (forest, ice, ocean, street, streetarena, lava, stadium, checker) each with its own goal image (assets/goals/*.webp),
6 new balls (b7-b12), pieces heavier vs the ball (HV) and more friction (PF1/PF2) - constants at the top of the script in index.html.
Pitch geometry + goal image per pitch: FIELDS array (gs = goal image). Goal image sizes/post positions: GS table.

v4 changes: 14 pitches total (futsal, arena, grand arena, desert, grove, pool added), fields now .webp with small t_*.webp thumbnails,
sounds in assets/sfx (select, hit_ball, hit_piece, goal commentator, menu music), no text under the HUD, pieces heavier (HV=6, EPP, PF1/PF2 at top of script),
pieces can enter the goal without sticking (goal walls act like normal walls), 3D team-select (spinning coins), lighter rendering (static bg canvas, cached halo, lazy ball loading).
