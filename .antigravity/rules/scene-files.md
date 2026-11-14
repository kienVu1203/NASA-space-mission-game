---
trigger: glob
globs: "**/*.tscn, **/*.tres"
---

# Scene and Resource File Rules (Godot)

Prefer editing in the Godot editor. If you must edit the text by hand:

- Never change the `format=` value in the header.
- Every `[ext_resource]` and `[sub_resource]` id must be unique in its file.
- Never invent a `uid://` value; leave `uid=` off new references.
- Never edit or delete a `.uid` file; commit it with its script.
- Never hand-edit TileMapLayer cell data.
- Only edit scenes your role owns (`docs/roles.md`); `.tscn` merge conflicts are painful.
