---
paths:
  - "autoload/**"
  - "core/**"
---

# GDScript Rules

- Game values (costs, mass, delta-v, power) come from `data/*.json`, never hardcoded.
- Use static typing: `var x: int`, `func f(a: float) -> void`.
- Logic in `core/` must not touch UI nodes; communicate through signals or `GameState`.
- Use `delta` for anything time-dependent.
- Keep one script per scene; do not edit another role's scripts (see `docs/roles.md`).
