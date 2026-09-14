"""Rebuild rogue forest geometry and one-metre navigation source meshes.

Encounter maps retain their authored building, defender and entrance markers.
Balance resources, battle.tscn and HUD scenes remain editor-owned; rebuilding
terrain must never overwrite unrelated gameplay or interface changes.

Usage: python tools/build_rogue_battles.py [--maps-only] [--godot PATH]
"""
from build_rogue_forest import main


if __name__ == "__main__":
    main()
