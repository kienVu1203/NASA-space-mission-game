# Data schema (draft, update in the first 3 hours of the event)

Each file in `data/` is a JSON array of objects. Every object has `id` (string) and `name` (string).

- `launch_vehicles.json`: `cost`, `payload_kg`, `isp_s`
- `instruments.json`: `cost`, `mass_kg`, `power_w`, `science_value`
- `destinations.json`: `delta_v_required`, `travel_days`
- `mission_events.json`: `description`, `probability`, `effect`
