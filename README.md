# Chess 3D

A 3D chess game for Godot 4 (GDScript). Play hot-seat on one machine or
against a built-in engine, on a 3D board with procedurally generated pieces -
a sculpted medieval set (king with sword, queen, bishop with crosier, horse,
brick tower, foot soldier) or classic turned pieces - that you can also swap
for your own `.glb` models. Captures are animated: pieces are knocked flying
or crushed, with debris, dust, camera shake and sound.

Built and tested with **Godot 4.7.2 stable** (anything from 4.4 up should
work). No third-party addons.

## Running

- **Editor:** open the folder in Godot and press F5.
- **Command line:** `godot --path .`

The main menu lets you pick the mode (two players / vs computer), your color,
the difficulty, the look (antique metal, carved stone, classic wood, marble,
stylized flat), the piece set (medieval or classic, plus any you add) and
whether sound effects play. Choices are remembered in `user://settings.cfg`.

### Controls

| Input | Action |
| --- | --- |
| Left click | Select a piece, then click a highlighted square to move |
| Right drag | Orbit the camera a little |
| Mouse wheel | Zoom (clamped) |
| `U` or Backspace | Undo |
| `F` | Flip the board |
| `Esc` | Clear the selection |

Legal moves show as dots (rings on pieces that can be captured); the last
move and a king in check are highlighted. In hot-seat the camera swings to
the other side after each move - turn that off with "Rotate board each turn".
Against the computer, Undo takes back your move and the reply.

## Project layout

```
chess/    Pure rules, no Node dependencies (RefCounted): Piece, Move, Board (0x88),
          MoveGenerator, San, GameState
ai/       ChessAI (search + evaluation), AiPlayer (runs it on a Thread),
          StockfishAdapter (optional external UCI engine)
pieces/   PieceProfiles (the shape data), MeshBuilder, ProceduralPieceFactory
          (classic set), MedievalPieceFactory (sculpted set), PieceSet (Resource),
          MaterialPresets
scenes/   Board3D, Piece3D (move / capture animations), Effects (debris, dust,
          flashes), Sfx (synthesized sounds), CameraRig, Stage, game scene
ui/       Main menu, HUD (move list, captured pieces, promotion picker, game over)
tools/    Blender export script, glTF exporter, screenshot helper
tests/    Headless test runner and suites
```

The rules never touch rendering: `GameState` is the only thing the scenes
talk to, and the AI searches on its own `Board.clone()`.

## Tests

```powershell
.\tests\run_tests.ps1                 # everything, ~12 s
.\tests\run_tests.ps1 -Full           # plus the deep perft counts (~90 s)
.\tests\run_tests.ps1 -Filter perft   # only suites whose file name matches
```

The script uses `godot` from PATH, `$env:GODOT`, or `-Godot <path>`. Without
it:

```
godot --headless --path . --import                      # once, and after adding class_name scripts
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . -s tests/run_tests.gd -- --full
```

What is covered:

- **Perft** on the start position (20 / 400 / 8,902 / 197,281; 4,865,609 with
  `--full`), Kiwipete and positions 3-6 from the Chess Programming Wiki.
- FEN round trips, castling edge cases, en passant (including pins),
  stalemate, the 50-move rule, threefold repetition, insufficient material,
  SAN generation and parsing, Zobrist hashing.
- The AI finds mate-in-1 and mate-in-2 positions, takes hanging pieces,
  stays inside its time budget, and runs on a thread without blocking.
- The 3D side, headless: piece meshes of both built-in sets, picking math,
  click-to-move, the promotion picker, undo, the game-over dialog, the menu,
  presets and `.glb` piece sets.
- The polish: capture animations (knock / crush) and their debris, the
  selection lift, the drop-in at the start of a game, the mated king
  toppling, camera shake and the generated sounds.

## The medieval set

[`pieces/medieval_piece_factory.gd`](pieces/medieval_piece_factory.gd) builds
six figures on carved pedestals out of `MeshBuilder` primitives - lathes,
ellipsoids, cones, tori and `add_loft` (a tube with elliptical sections along
a path: the horse's neck, arms, the crosier's crook). Each piece is one
function (`_build_king`, `_build_knight`, ...) made of readable parts, so
changing a crown, a beard or the height of a tower is a matter of editing a
few numbers. The figures face the enemy.

It is selected with **Pieces -> Medieval (built-in)** (the default), and pairs
best with the **Antique metal** (aged gold vs. pewter) and **Carved stone**
(ivory vs. charcoal) looks, which add a cast / carved grain through a
triplanar noise texture - no UVs or image files needed. From code:
`PieceSet.medieval(MaterialPresets.Preset.CARVED_STONE)`.

## Animations and sound

- **Moves** lift, arc and set down with a small squash; knights jump.
- **Captures**: the attacker rears back and lunges; the victim is knocked
  away along the line of attack, tumbling and fading. A knight instead lands
  on its victim and flattens it. Either way chips of the victim's own
  material fly off, dust puffs up, a ring spreads over the square and the
  camera jolts (`Piece3D.capture_out`, `Effects.shatter`, `CameraRig.shake`).
- The selected piece rises off its square, a king in check trembles, a mated
  king falls over, a promotion flashes, and the pieces drop onto the board at
  the start of a game.
- **Sounds** (move, capture, check, promotion, game over) are synthesized in
  [`scenes/sfx.gd`](scenes/sfx.gd), so there are no audio files; turn them
  off with "Sound effects" in the menu.

`GameSettings.animations = false` makes everything instant.

## Tweaking the classic pieces

All shape data lives in [`pieces/piece_profiles.gd`](pieces/piece_profiles.gd),
one function per piece. A profile is a list of `(radius, height)` points from
the bottom of the piece to the top, in board units (one square = 1.0):

```gdscript
static func pawn() -> PackedVector2Array:
	var p := _pts([
		0.270, 0.020,  # top of the felt
		0.270, 0.065,  # base rim
		...
	])
	p.append_array(arc(0.615, 0.125, -50.0, 90.0, 9))  # ball head
	return p
```

`ProceduralPieceFactory` turns these into meshes with `SurfaceTool`: lathes
with smooth normals (corners sharper than ~40 degrees stay crisp), plus

- **Rook** - crenellations as extra geometry on the rim,
- **Bishop** - a mitre slit cut into the head geometry, with a dark core
  showing through,
- **Queen** - a crown with a ring of spheres, **King** - a cross,
- **Knight** - a beveled, extruded horse-head outline on a lathe pedestal.

The merlon count, slit angle, pearl sizes, cross dimensions and the knight
outline are constants in the same file. If you change `PieceProfiles.height()`
values, keep them equal to the real mesh height (a test checks this).

## Custom piece sets (`.glb` -> `PieceSet`)

A `PieceSet` ([`pieces/piece_set.gd`](pieces/piece_set.gd)) is a Resource that
maps each piece type to a `Mesh` or `PackedScene`, plus materials for White
and Black. Empty slots fall back to a built-in mesh (classic or medieval,
see `procedural_style`), so you can replace just the knight if you like.

Model conventions: stand on y = 0, centered on the origin, front toward +Z,
sized for a 1 x 1 square. `model_scale` and `model_rotation_degrees` on the
PieceSet adapt models that don't follow them.

**Easiest: drop a `.glb` in `piece_sets/`.** Name the objects `Pawn`,
`Knight`, `Bishop`, `Rook`, `Queen` and `King` (case-insensitive; `Pawn.001`
is fine). The file appears in the menu under **Pieces**. `user://piece_sets/`
is scanned too, so this also works in an exported game.

**In the editor, for full control:**

1. Copy the `.glb` into the project and let Godot import it.
2. In the FileSystem dock: right-click -> New Resource -> `PieceSet`, save it
   as `piece_sets/my_set.tres`.
3. Drag the meshes (expand the `.glb` in the FileSystem dock) or scenes into
   the Pawn ... King slots.
4. Leave **Apply Materials** on to have the menu's look applied to your
   models, or turn it off to keep the materials baked into the `.glb` (then
   use separate scenes if White and Black should differ).

**From code:**

```gdscript
var piece_set := PieceSet.from_glb("res://piece_sets/pieces.glb")  # or user:// or an absolute path
piece_set.use_preset(MaterialPresets.Preset.MARBLE)
var knight := piece_set.instantiate(Piece.WHITE | Piece.KNIGHT)    # a Node3D
```

Materials are assigned by surface/material name: `felt` gets the felt
material, `accent` the dark detail material, anything else the piece color.

### Refining the pieces in Blender

[`tools/blender_export_pieces.py`](tools/blender_export_pieces.py) rebuilds
the same profiles in Blender (the bishop's slit is a real boolean cut there)
and exports `pieces.glb` with one object per piece:

```
blender --background --python tools/blender_export_pieces.py -- piece_sets/pieces.glb
```

or open it in Blender's Text Editor and press Run Script; the pieces land in
a `ChessPieces` collection. Edit them, keep the object names, export as glTF
binary into `piece_sets/`, and pick the set in the menu.

The script's numbers are generated from `piece_profiles.gd`. After changing a
profile, refresh them (a test fails if they drift apart):

```
godot --headless --path . -s tools/sync_blender_profiles.gd
```

No Blender at hand? Export the exact in-game meshes straight from Godot:

```
godot --headless --path . -s tools/export_pieces_glb.gd -- piece_sets/procedural_export.glb
```

## The computer opponent

`ChessAI` ([`ai/chess_ai.gd`](ai/chess_ai.gd)) is a negamax alpha-beta search
with iterative deepening, a transposition table, move ordering (hash move,
MVV-LVA, killer moves, history), check extensions, late-move reductions and
quiescence search. Evaluation is material plus piece-square tables, tapered
between middlegame and endgame. It runs on a `Thread` through `AiPlayer`, so
the UI keeps rendering while it thinks.

| Level | Depth | Time limit | Notes |
| --- | --- | --- | --- |
| Easy | 2 | 0.6 s | Picks randomly among moves within ~0.9 pawns of the best |
| Medium | 5 | 3 s | |
| Hard | up to 9 | 5 s | Usually reaches depth 6-7 in the middlegame |

Tune them in `ChessAI.LEVELS`. GDScript searches roughly 60-70k nodes per
second, so this is a solid club-level opponent, not a master.

### Optional: Stockfish

Paste the path to a Stockfish executable (or any UCI engine) into
"Stockfish executable" in the menu. The game then talks UCI to it through
`OS.execute_with_pipe` (`ai/stockfish_adapter.gd`); the three levels map to
Stockfish's Skill Level 1 / 8 / 20. If the program can't be started, the
built-in engine plays instead.

## Tools

- `tools/screenshot.gd` - renders a scene and saves a PNG, e.g.
  `godot --path . -s tools/screenshot.gd -- res://scenes/game.tscn out.png moves=e2e4,e7e5 preset=1`
- `tools/export_pieces_glb.gd`, `tools/sync_blender_profiles.gd`,
  `tools/blender_export_pieces.py` - see above.

## Notes and limits

- Threefold repetition, the 50-move rule and insufficient material end the
  game automatically (no claim step). Insufficient material covers K v K,
  K + minor v K, and kings with same-colored bishops only.
- FEN loading rejects malformed strings but does not check that the position
  is reachable (for example, the side not to move may be in check).
- The Blender script's geometry code is tested with plain Python and its
  data is checked against the game, but it has not been run inside Blender
  itself yet.
- The Stockfish adapter is tested against a small fake UCI engine
  (`tests/mock_uci_engine.py`), not against a real Stockfish binary.
