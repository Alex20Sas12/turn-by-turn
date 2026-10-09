// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title TurnByTurn — asynchronous Connect Four, the chain is the referee.
/// @notice No owner, no upgradeability, no admin functions. Once deployed,
///         nobody can wipe or alter a game — the rules alone decide the winner.
contract TurnByTurn {
    uint8 public constant ROWS = 6;
    uint8 public constant COLS = 7;
    /// @notice If a player stalls longer than this, the opponent may claim the win.
    uint256 public constant TIMEOUT = 3 days;

    enum Status { Open, Active, Finished, Cancelled }

    struct Game {
        address player1;          // creator, moves first (disc 1)
        address player2;          // joiner (disc 2)
        address turn;             // whose move is due
        address winner;           // zero while undecided; set on win/timeout
        Status status;
        uint64 lastMoveAt;        // timestamp of last move (game start for player1's first move window)
        uint8 moves;              // total discs placed
        uint8[7] heights;         // discs per column
        // packed board: 2 bits per cell, row-major from bottom. 0 empty, 1 = player1, 2 = player2
        uint256[3] cells;         // 42 cells * 2 bits = 84 bits; 3 words, plenty of room
    }

    Game[] public games;
    mapping(address => uint256[]) private _gamesOf;

    event GameCreated(uint256 indexed gameId, address indexed player1);
    event GameJoined(uint256 indexed gameId, address indexed player2);
    event MovePlayed(uint256 indexed gameId, address indexed player, uint8 col, uint8 row);
    event GameWon(uint256 indexed gameId, address indexed winner, string reason);
    event GameDrawn(uint256 indexed gameId);
    event GameCancelled(uint256 indexed gameId);

    error NotPlayer();
    error NotYourTurn();
    error GameNotActive();
    error GameNotOpen();
    error CannotJoinOwnGame();
    error ColumnFull();
    error ColumnOutOfRange();
    error TimeoutNotReached();
    error OnlyOpenCanCancel();

    function createGame() external returns (uint256 gameId) {
        gameId = games.length;
        games.push();
        Game storage g = games[gameId];
        g.player1 = msg.sender;
        g.turn = msg.sender;
        g.status = Status.Open;
        g.lastMoveAt = uint64(block.timestamp);
        _gamesOf[msg.sender].push(gameId);
        emit GameCreated(gameId, msg.sender);
    }

    function joinGame(uint256 gameId) external {
        Game storage g = games[gameId];
        if (g.status != Status.Open) revert GameNotOpen();
        if (g.player1 == msg.sender) revert CannotJoinOwnGame();
        g.player2 = msg.sender;
        g.status = Status.Active;
        g.lastMoveAt = uint64(block.timestamp);
        _gamesOf[msg.sender].push(gameId);
        emit GameJoined(gameId, msg.sender);
    }

    function cancelGame(uint256 gameId) external {
        Game storage g = games[gameId];
        if (msg.sender != g.player1) revert NotPlayer();
        if (g.status != Status.Open) revert OnlyOpenCanCancel();
        g.status = Status.Cancelled;
        emit GameCancelled(gameId);
    }

    function _cell(Game storage g, uint8 row, uint8 col) internal view returns (uint8) {
        uint256 idx = uint256(row) * COLS + col;      // 0..41
        uint256 word = idx >> 4;                       // 16 cells per word
        uint256 shift = (idx & 15) * 2;
        return uint8((g.cells[word] >> shift) & 3);
    }

    function _setCell(Game storage g, uint8 row, uint8 col, uint8 v) internal {
        uint256 idx = uint256(row) * COLS + col;
        uint256 word = idx >> 4;
        uint256 shift = (idx & 15) * 2;
        g.cells[word] = (g.cells[word] & ~(uint256(3) << shift)) | (uint256(v) << shift);
    }

    function play(uint256 gameId, uint8 col) external {
        Game storage g = games[gameId];
        if (g.status != Status.Active) revert GameNotActive();
        if (msg.sender != g.turn) revert NotYourTurn();
        if (col >= COLS) revert ColumnOutOfRange();
        uint8 row = g.heights[col];
        if (row >= ROWS) revert ColumnFull();

        uint8 disc = msg.sender == g.player1 ? 1 : 2;
        _setCell(g, row, col, disc);
        g.heights[col] = row + 1;
        g.moves += 1;
        g.lastMoveAt = uint64(block.timestamp);
        emit MovePlayed(gameId, msg.sender, col, row);

        if (_isWin(g, row, col, disc)) {
            g.status = Status.Finished;
            g.winner = msg.sender;
            emit GameWon(gameId, msg.sender, "connect-four");
            return;
        }
        if (g.moves == ROWS * COLS) {
            g.status = Status.Finished;
            emit GameDrawn(gameId);
            return;
        }
        g.turn = msg.sender == g.player1 ? g.player2 : g.player1;
    }

    /// @notice Claim the win when the opponent has stalled past TIMEOUT.
    function claimTimeout(uint256 gameId) external {
        Game storage g = games[gameId];
        if (g.status != Status.Active) revert GameNotActive();
        if (msg.sender != g.player1 && msg.sender != g.player2) revert NotPlayer();
        if (msg.sender == g.turn) revert NotYourTurn(); // you can't claim on your own turn
        if (block.timestamp < uint256(g.lastMoveAt) + TIMEOUT) revert TimeoutNotReached();
        g.status = Status.Finished;
        g.winner = msg.sender;
        emit GameWon(gameId, msg.sender, "timeout");
    }

    function _isWin(Game storage g, uint8 row, uint8 col, uint8 disc) internal view returns (bool) {
        // directions: horizontal, vertical, diag /, diag \
        int8[4] memory dr = [int8(0), int8(1), int8(1), int8(1)];
        int8[4] memory dc = [int8(1), int8(0), int8(1), int8(-1)];
        for (uint256 d = 0; d < 4; d++) {
            uint256 count = 1;
            count += _countDir(g, row, col, dr[d], dc[d], disc);
            count += _countDir(g, row, col, -dr[d], -dc[d], disc);
            if (count >= 4) return true;
        }
        return false;
    }

    function _countDir(Game storage g, uint8 row, uint8 col, int8 dr, int8 dc, uint8 disc)
        internal view returns (uint256 n)
    {
        int256 r = int256(uint256(row)) + dr;
        int256 c = int256(uint256(col)) + dc;
        while (r >= 0 && r < int256(uint256(ROWS)) && c >= 0 && c < int256(uint256(COLS))) {
            if (_cell(g, uint8(uint256(r)), uint8(uint256(c))) != disc) break;
            n++;
            r += dr;
            c += dc;
        }
    }

    // ---------- views ----------

    function gamesCount() external view returns (uint256) { return games.length; }

    function gamesOf(address player) external view returns (uint256[] memory) {
        return _gamesOf[player];
    }

    /// @notice Whole board as 42 bytes, row-major from the bottom row.
    function boardOf(uint256 gameId) external view returns (uint8[] memory out) {
        Game storage g = games[gameId];
        out = new uint8[](ROWS * COLS);
        for (uint8 r = 0; r < ROWS; r++) {
            for (uint8 c = 0; c < COLS; c++) {
                out[uint256(r) * COLS + c] = _cell(g, r, c);
            }
        }
    }

    /// @notice Open games waiting for a second player, newest first, capped.
    function openGames(uint256 maxResults) external view returns (uint256[] memory ids) {
        uint256 total = games.length;
        uint256 found;
        uint256[] memory tmp = new uint256[](total > maxResults ? maxResults : total);
        for (uint256 i = total; i > 0 && found < maxResults; i--) {
            if (games[i - 1].status == Status.Open) {
                tmp[found++] = i - 1;
            }
        }
        ids = new uint256[](found);
        for (uint256 i = 0; i < found; i++) ids[i] = tmp[i];
    }
}
