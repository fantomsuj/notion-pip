# Mafia role framework

## Purpose and design principles

This document is the product and implementation contract for assigning roles,
resolving role actions, and deciding wins. The first release should be easy to
teach, produce useful information without making any player indispensable, and
work when one device is passed around. More complex roles are opt-in modules,
not part of the default rules.

The framework uses three alignments:

- **Town** wins by eliminating every living Mafia player.
- **Mafia** wins as soon as living Mafia players equal or outnumber all other
  living players, unless an unresolved action in the current resolution can
  remove that parity.
- **Independent** roles have their own objective. They are excluded from the
  MVP because they make balance and end-game messaging less predictable.

Roles grant abilities; alignment determines victory. A role changing or losing
an ability does not implicitly change its alignment.

## Baseline MVP

The default game contains only these four roles:

| Role | Alignment | Ability | Information | Mode support |
| --- | --- | --- | --- | --- |
| Civilian | Town | None | Public discussion and voting only | Single and multi-device |
| Mafia | Mafia | Chooses one living non-Mafia target with the Mafia team each night | Knows the other Mafia players | Single and multi-device |
| Detective | Town | Investigates one living player each night | Learns `Mafia` or `Not Mafia` after resolution | Single and multi-device |
| Doctor | Town | Protects one living player from the Mafia kill each night | Learns only that protection was submitted, not whether it prevented a kill | Single and multi-device |

MVP rules are deliberately conservative:

- One day elimination and at most one Mafia kill occur per round.
- Roles and alignment are revealed when a player dies.
- Eliminated players cannot speak, vote, act, or receive private updates.
- A tie in the day vote eliminates nobody. Do not add a random tie-breaker.
- The Doctor may protect themself, but may not protect the same target on two
  consecutive nights. This is easier to enforce privately than a limited-use
  self-protection rule and prevents permanent self-shielding.
- The Detective may investigate themself, although the UI should discourage a
  choice that provides no new information.
- Mafia members may not target a Mafia member in the baseline rules.

### Recommended role sets

The supported MVP range is **5–16 players**. Games below five are too volatile;
games above sixteen should be split or use a separately tested large-game
variant.

| Players | Mafia | Detective | Doctor | Civilians | Notes |
| ---: | ---: | ---: | ---: | ---: | --- |
| 5 | 1 | 1 | 0 | 3 | Intro game; omit Doctor to avoid frequent no-kill nights |
| 6 | 1 | 1 | 1 | 3 | Town-favored teaching setup; see six-player alternative below |
| 7 | 2 | 1 | 0 | 4 | Fast baseline |
| 8 | 2 | 1 | 1 | 4 | Recommended first full game |
| 9 | 2 | 1 | 1 | 5 | Recommended |
| 10 | 2 | 1 | 1 | 6 | Recommended |
| 11 | 3 | 1 | 1 | 6 | Stronger informed minority for a larger table |
| 12 | 3 | 1 | 1 | 7 | Recommended |
| 13 | 3 | 1 | 1 | 8 | Recommended |
| 14 | 3 | 1 | 1 | 9 | Recommended |
| 15 | 4 | 1 | 1 | 9 | Large, faster game |
| 16 | 4 | 1 | 1 | 10 | Maximum supported baseline |

At six players, experienced groups may use `2 Mafia / 1 Detective / 3
Civilian` for a shorter, harsher game. Label it **Fast**, not **Balanced**. Do
not allow arbitrary role counts under the Balanced preset.

## Mode viability

**Single-device mode** means one unlocked device is passed between players.
Every private step must have a handoff screen, explicit player confirmation,
content concealed before and after the step, and no notification or history
that exposes the result. Team decisions that require private conversation are
not viable without a moderator, so Mafia members submit individual choices; a
strict majority selects the target, with a tie producing no kill.

**Multi-device mode** gives each player an authenticated private screen and can
support simultaneous actions, persistent private information, and private team
chat. The server remains authoritative; clients never receive unrevealed roles
or actions that their player is not entitled to see.

| Capability or role | Single device | Multi-device | Constraint |
| --- | :---: | :---: | --- |
| MVP roles | Yes | Yes | Pass-and-play privacy gates are required |
| Roleblocker | Yes | Yes | Submission acknowledgement must not reveal priority or outcome |
| Vigilante | Yes | Yes | Private target selection; limited shots shown only to owner |
| Bulletproof | Yes | Yes | Passive; owner is not told when armor triggers by default |
| Godfather | Yes | Yes | Passive Detective result |
| Miller | Yes | Yes | Setup must warn that misleading results are enabled |
| Tracker / Watcher | Limited | Yes | Single-device result text must be concealed during handoff |
| Lovers | Limited | Yes | Single-device pairing reveal requires two separate private views |
| Mafia team chat | No | Yes | Replace with independent ballots on one device |
| Secret Mayor vote weight | No | Yes | Device handoff and public tally can leak the modifier |
| Real-time discussion powers | No | Yes | Requires private, concurrent communication |

“Limited” roles are allowed only in a custom single-device game with an explicit
privacy warning. They are never automatically selected there.

## Optional advanced roles

Advanced roles are grouped by a **balance weight** used to validate custom
setups. Weight is a guardrail, not a mathematical promise.

| Role | Alignment | Ability | Weight | Default availability |
| --- | --- | --- | ---: | --- |
| Roleblocker | Town | Prevents one target's active night ability | +1 Town | 9+ players |
| Vigilante | Town | Attempts a night kill; two shots per game | +1 Town | 10+ players |
| Bulletproof | Town | Survives the first otherwise-successful Mafia kill | +1 Town | 8+ players |
| Tracker | Town | Learns whom the target visited, if anyone | +1 Town | 9+, multi-device preferred |
| Watcher | Town | Learns which players visited the target | +2 Town | 11+, multi-device preferred |
| Godfather | Mafia | Appears `Not Mafia` to the Detective | +1 Mafia | 9+ players with a Detective |
| Mafia Roleblocker | Mafia | Blocks one non-Mafia active ability | +1 Mafia | 11+ players |
| Miller | Town | Appears `Mafia` to the Detective | +1 Mafia | 9+ experienced groups only |
| Jester | Independent | Wins personally if eliminated by day vote | Unscored | Custom, 9+, multi-device preferred |

Expansion constraints:

- Replace a Civilian or plain Mafia slot; never increase the total player
  count implicitly.
- Add at most one new role in teaching games and at most one information role
  per four non-Mafia players.
- Use no more than one source of protection and one Town killing role before 12
  players.
- Godfather and Miller require a Detective and must not both appear below 12
  players. Their presence is announced as a possible rule, never secretly
  enabled by configuration.
- Roleblocker and Mafia Roleblocker should not coexist below 13 players.
- Independent roles are excluded from matchmaking and balance ratings until
  their win rates have been measured separately.

## Setup validation and balancing constraints

A setup is valid only when all of the following hold:

1. Player count is within the selected preset's supported range and every
   player receives exactly one role.
2. There is at least one Mafia and at least two Town players.
3. Mafia count is normally 20–30% of players, and is always less than half at
   game start.
4. The Balanced preset exactly matches the table above. Custom presets are
   clearly marked **Unrated** when they diverge.
5. The absolute difference between total Town and Mafia balance weights is no
   more than one. Unscored roles always make the setup Unrated.
6. Role minimum-player, dependency, incompatibility, duplicate, and mode rules
   pass. All listed advanced roles have a maximum count of one unless a future
   ruleset explicitly overrides it.
7. A setup cannot combine more than two disruptive effects (kill, protection,
   or block) outside the shared Mafia kill before 12 players.

The validator should return stable error codes plus display text, for example
`player_count_out_of_range`, `mafia_ratio_invalid`, `role_requires_detective`,
`role_not_supported_in_mode`, and `balance_weight_exceeded`. This lets product
copy evolve without changing game logic.

Role assignment uses a server-generated cryptographically secure shuffle in
multi-device games and the platform secure random generator on the host device
in single-device games. Persist the resulting assignment, not the random seed,
and make assignment idempotent so reconnects never reroll roles.

## Round and action resolution

Use a deterministic phase machine:

`lobby -> roleReveal -> dayDiscussion -> dayVote -> nightActions -> nightResolution -> dayDiscussion`

After every elimination and night resolution, evaluate victory before opening
the next interactive phase. Resolve a night from an immutable snapshot so
submission order and network timing cannot affect the outcome.

Recommended resolution order:

1. Lock all submitted actions at the deadline (missing actions become `pass`).
2. Apply roleblocks.
3. Establish protection and passive defenses.
4. Resolve investigations and movement-derived information from the locked
   action graph.
5. Resolve Mafia and Vigilante kills simultaneously.
6. Commit deaths together, discard information belonging to players killed
   that night, publish the allowed public outcome, then evaluate wins.

Simultaneous lethal actions may kill each other's actors. Protection prevents
one or all kills according to the role definition; MVP Doctor protection
prevents all Mafia-kill attempts against that target for that night, but does
not prevent a day elimination. A blocked Doctor supplies no protection. A
blocked Mafia member casts no ballot; if no Mafia ballot has a strict majority,
there is no Mafia kill.

## Win-condition interactions

- Town wins immediately when no living Mafia remain, even if a Town lethal
  action would otherwise be available next night.
- Mafia parity is checked after simultaneous deaths. A protected or failed kill
  cannot create parity.
- If the last Mafia and last Town players die in the same resolution, the game
  is a draw; neither main alignment wins.
- Dead players retain a final outcome but cannot satisfy future action-based
  conditions.
- A Jester day elimination records the Jester's personal win but does not end
  the game. Other alignments continue toward their own outcomes. A Jester
  killed at night does not win.
- If multiple win conditions become true in one atomic resolution, record all
  compatible winners. The result model therefore stores a set of winning
  player IDs and alignment outcomes rather than one winner enum.

## Implementation contract

Keep definitions data-driven while behavior remains typed and testable. A role
definition needs a stable ID, alignment, mode support, minimum players,
dependencies and exclusions, maximum count, balance weight, public rules text,
private instructions, and an ability kind. A versioned `Ruleset` owns the role
catalog, setup table, phase sequence, action priorities, reveal policy, tie
policy, and win evaluators.

The engine should separate:

- **commands** (`submitVote`, `submitNightAction`) from validated, immutable
  **events** (`voteLocked`, `playerProtected`, `playerKilled`);
- private player projections from the public game projection;
- action validation from deterministic resolution; and
- role identity from alignment, alive state, and temporary effects.

Every command includes game, round, phase, actor, and idempotency identifiers.
Reject actions from dead players, wrong phases, invalid targets, or stale
rounds. Store private investigation results as audience-scoped events rather
than public game state.

Minimum regression coverage should include every recommended player count,
invalid ratio and dependency cases, mode exclusions, tied votes and Mafia
ballots, consecutive Doctor targeting, block/protect/kill priority, simultaneous
last-player deaths, parity after protection, misleading investigation roles,
idempotent action submission, reconnect projections, and prevention of private
data leakage.

## Product defaults and future tuning

The lobby defaults to the Balanced preset and explains only roles selected for
that game. Advanced roles require the host to enable **Custom roles**, after
which the lobby displays balance and mode warnings to every player before
starting.

Track anonymized results by ruleset version, player count, mode, role set,
winner, round count, no-elimination days, prevented kills, and incomplete
games. Review balance only after a meaningful sample; a practical initial
target is a Mafia win rate of 40–55% with a median game length of three to six
rounds. Change presets by introducing a new ruleset version so existing games
and historical telemetry remain reproducible.
