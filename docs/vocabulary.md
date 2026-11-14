# STAR FALL vocabulary library

The Phase 3 boss (the Sky Remnant at the Dawn Tower) is a typing encounter
built on an English environmental vocabulary library. This page documents the
content, its schema, how a fight selects words from it, and its review status.

## Size and coverage

`data/star_fall/vocabulary.json` holds **203 entries**.

| Band | Entries | Meaning |
|---|---|---|
| `foundation` | 52 | Short, very familiar words with regular spelling (air, sun, tree, soil, seed) |
| `developing` | 56 | Common environmental words, a little longer or less regular (reuse, litter, recycle, protect) |
| `intermediate` | 56 | Longer or more conceptual words (habitat, compost, conserve, aquifer, runoff) |
| `advanced` | 39 | Long, multi-part or abstract terms (pollution, ecosystem, biodiversity, sustainability) |

| Category | Entries |
|---|---|
| nature | 31 |
| water | 30 |
| habitat | 24 |
| energy | 20 |
| recycling | 21 |
| forest | 19 |
| pollution | 18 |
| conservation | 17 |
| responsibility | 12 |
| waste | 11 |

The library covers nature and living things, water and oceans, trees and
forests, waste and litter, reuse and recycling, energy and resources,
pollution, habitats and wildlife, conservation and restoration, and
environmental responsibility.

## Schema

```jsonc
{
  "schema_version": 1,
  "bands": ["foundation", "developing", "intermediate", "advanced"],
  "categories": ["nature", "water", "forest", "waste", "recycling", "energy",
                 "pollution", "habitat", "conservation", "responsibility"],
  "entries": [{
    "id": "v_habitat",            // stable id, "v_" + text; saved in the journal
    "text": "habitat",            // typing target: lowercase a-z only
    "definition": "The natural home of a plant or animal.",
    "example": "The wetland is a habitat for many birds.",
    "category": "habitat",        // one of `categories`
    "band": "intermediate",       // one of `bands`
    "note": "..."                 // optional: why it matters, when not obvious
  }]
}
```

`core/star_fall/sf_vocabulary.gd` validates the file on load and reports every
problem (the game logs it; `test_phase3.gd` fails on it):

- unique ids and unique typing text;
- every required field present and non-empty;
- band and category from the declared lists;
- typing text is lowercase `a-z` only, at least two letters: no spaces,
  hyphens, apostrophes, digits or accented characters.

Display capitalisation is independent of matching: the screen may show
`HABITAT`, and the player may type with Shift held; both match `habitat`.

## Content rules

- One spelling convention throughout: **American English** (fertilizer,
  aluminum, colorful).
- Single words only. No plurals used to inflate the count, no duplicate
  spellings, no invented words.
- Definitions and examples are **short original sentences** written for this
  game, not copied from a dictionary.
- A `note` is added where the environmental link is not obvious (bee, fungus,
  battery, smog, nectar, estuary, upcycle, carbon, fertilizer and others).
- Bands are a judgement call combining word length, spelling regularity,
  everyday familiarity and conceptual difficulty, not character count alone.
  For example `toxic`, `smog` and `prey` are short but sit in `developing`
  because the idea is less familiar, while `garden` stays in `developing`
  despite being six letters.
- No band claims alignment with a school grade or a formal reading standard.

## Library versus encounter deck

The fight never uses the whole library.

| Term | Meaning |
|---|---|
| Library | All 203 entries |
| Deck | The finite selection one attempt must complete: **30 entries** |
| Pending queue | Deck entries not yet completed and not falling |
| Active words | Words currently falling (at most one instance per entry) |
| Completed | Entries typed successfully; each pays out exactly once |
| Missed | Entries that reached the danger line; they return to the pending queue |

`select_deck()` reads the stages in `data/star_fall/typing.json`:

| Stage | Band | Count |
|---|---|---|
| 1 | foundation | 8 |
| 2 | developing | 8 |
| 3 | intermediate | 8 |
| 4 | advanced | 6 |

Each stage draws distinct entries from its band with a **seeded** shuffle,
first preferring an unused first letter and an unused category (for variety),
then filling from the rest of the band. Inside a stage, words are ordered from
shorter to longer. The same seed always selects the same deck.

The deck seed is the boss seed plus the current journal size. A **retry**
inside the fight keeps the same words for consistent practice; leaving the
tower and coming back after learning new words draws a fresh deck.

**Play order changes on every attempt.** Each attempt (first entry, retry,
re-entry, reload) reshuffles the deck *inside each stage*
(`order_for_attempt()`), so foundation words still come first and advanced
words still come last. An order identical to the previous attempt's (saved in
the campaign) is replaced by rotating one stage by one place, so consecutive
attempts always differ when any other order exists.

### Added in the Phase 3 fix

Four entries absent from the library were added (the suggested `refill`,
`repair`, `wetland` and `upcycle` were already present):

| id | Text | Band | Category |
|---|---|---|---|
| `v_mulch` | mulch | developing | forest |
| `v_rainwater` | rainwater | intermediate | water |
| `v_peatland` | peatland | advanced | habitat |
| `v_refurbish` | refurbish | advanced | recycling |

All four pass validation and are reachable by real deck selection
(`test_phase3.gd`).

## Journal

Every completed word is recorded once in the campaign's
`vocabulary_journal` (saved since save version 3) with its definition, example and
note available for review:

- in the fight: `Esc` → **Vocabulary journal** (the arena is frozen);
- in exploration: `Esc` → **Vocabulary journal** (appears once the journal has
  an entry).

Journal progress never counts as boss damage: a retry starts the boss at full
health with zero completed entries.

## Sources and review status

Stated plainly, so nobody overestimates the review this content has had:

- The entries, definitions, examples and notes were drafted by an AI coding
  assistant (Claude) for this project and checked by a script for structure
  only (`test_phase3.gd`).
- **No external dictionary or reference was consulted while writing them.**
  Two definitions follow widely used formulations recalled from general
  knowledge rather than looked up: microplastic as plastic under five
  millimeters (a size threshold used by NOAA), and sustainability as meeting
  present needs without compromising future generations (the 1987 Brundtland
  report's wording, paraphrased).
- **No educator, linguist or subject-matter expert has reviewed the library.**
  Before use with children, have an educator review spelling, meaning,
  suitability and band placement, and replace any entry that does not fit the
  intended audience.
