---
paths:
  - "scenes/design/**"
  - "scenes/result/**"
  - "scenes/main/**"
---

# UI Rules

- UI only displays state and requests changes; it never owns game state. Read and write through `GameState` and signals.
- Use `Container` nodes (VBox, HBox, Grid, Margin) instead of hand-placed positions, so layouts survive the web canvas size.
- Style through the shared `Theme` resource in `assets/ui/`, not per-node overrides.
