# Turn by Turn

**An asynchronous Connect Four where the chain is the referee — no server, no accounts, no way to wipe a game.**

Built for **Road to Devcon VIII — Onchain Gaming**, problem **Turn by Turn: A Board Game That Waits for You**.

## What it is

Connect Four, played by two wallets over hours or days. You make a move, close the
tab, go live your life — the game sits onchain waiting. When your opponent moves,
it's your turn. If they stall for **3 days**, you claim the win by timeout.

- **Base Sepolia** — cheap enough that a move costs a fraction of a cent.
- **One immutable contract, zero admin functions.** No owner, no upgradeability,
  no pause switch. Once deployed, nobody — including us — can alter or erase a game.
- **The rules alone decide the winner.** Horizontal, vertical, both diagonals —
  win detection is enforced by the EVM, not by a server you have to trust.
- **Draws are real.** A full 42-disc board with no connect-four ends as a draw
  (test-covered with a hand-computed full-board sequence).
- **Meera never buys ETH.** An ERC-4337 verifying paymaster
  (`src/TurnByTurnPaymaster.sol`, deployed & funded on Base Sepolia) sponsors
  game moves: a backend signer approves UserOps that call only the game's
  selectors (`createGame / joinGame / play / claimTimeout`), rate-limited to
  8 sponsored moves per player per day. Players with a smart account play
  gasless; everyone else pays a fraction of a cent per move.

## Why it answers the brief

The problem asks for *a board game that waits for you*: asynchronous rivalry that
doesn't demand both players be online, with rules enforced by the chain rather
than a server. Turn by Turn is exactly that loop: `createGame → joinGame → play
(one tx per move, whenever you show up) → GameWon / GameDrawn / claimTimeout`.
The timeout mechanic is what makes asynchrony fair — a stalled game is a lost game.

## Contracts

- `src/TurnByTurn.sol` — the whole game. ~190 lines, Solidity 0.8.24.
  - Board packed into 2 bits per cell (`uint256[3]` covers all 42 cells).
  - `createGame`, `joinGame`, `play`, `claimTimeout` (3 days), `cancelGame` (while open).
  - Views: `boardOf` (42 bytes), `openGames` (lobby), `gamesOf` (per-player history).
- `src/TurnByTurnPaymaster.sol` — ERC-4337 verifying paymaster for gasless play
  (whitelisted game selectors, per-player daily rate limit, backend-signed approvals).
- **33 Foundry tests, all passing** — lifecycle, turn enforcement, all four win
  directions, no-false-positive check, full-board draw, timeout claims, paymaster
  signature/selector/rate-limit checks, fuzz run (256 random games never brick
  the state machine).

```
forge test
# Ran 4 test suites: 33 tests passed, 0 failed
```

## Live demo

- Contract (Base Sepolia): see `DEPLOYED.md` and the footer of the web app.
- Web app: static frontend (`web/`) — connect wallet, create/join, play. No build
  step, plain ethers v6. Hosted on Vercel.

## How a move works

1. `createGame()` — you become player 1 (gold discs), game opens in the lobby.
2. Anyone calls `joinGame(id)` — player 2 (red discs), game activates.
3. `play(id, col)` — gravity drops your disc, win is checked, turn flips.
4. If it's your opponent's turn and `lastMoveAt + 3 days` has passed,
   `claimTimeout(id)` ends the game in your favor.

## Run locally

```sh
forge build
forge test -vv
# frontend: serve web/ statically, set CONTRACT in web/app.js to your deploy
```

## Stack

Solidity 0.8.24 · Foundry (forge/cast) · ethers v6 · static HTML/CSS/JS · Base Sepolia.
