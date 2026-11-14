"""A tiny fake UCI engine used by tests/test_stockfish_adapter.gd.

It speaks just enough of the protocol to exercise StockfishAdapter: it
answers the handshake, remembers the last "position" command and replies to
"go" with a fixed move that depends on how many moves have been played.
"""
import sys

REPLIES = ["e2e4", "e7e5", "g1f3", "b8c6"]
moves_played = 0


def say(text):
    sys.stdout.write(text + "\n")
    sys.stdout.flush()


for raw in sys.stdin:
    line = raw.strip()
    if line == "uci":
        say("id name MockFish 1.0")
        say("id author Chess 3D tests")
        say("option name Skill Level type spin default 20 min 0 max 20")
        say("uciok")
    elif line == "isready":
        say("readyok")
    elif line.startswith("position"):
        moves_played = len(line.split(" moves ", 1)[1].split()) if " moves " in line else 0
    elif line.startswith("go"):
        say("info depth 1 score cp 20")
        say("bestmove " + REPLIES[moves_played % len(REPLIES)])
    elif line == "quit":
        break
