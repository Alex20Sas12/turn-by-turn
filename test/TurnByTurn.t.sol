// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TurnByTurn.sol";

contract TurnByTurnTest is Test {
    TurnByTurn game;
    address a = address(0xA11CE);
    address b = address(0xB0B);
    address stranger = address(0xBEEF);

    function setUp() public {
        game = new TurnByTurn();
    }

    function _open() internal returns (uint256 id) {
        vm.prank(a);
        id = game.createGame();
    }

    function _active() internal returns (uint256 id) {
        id = _open();
        vm.prank(b);
        game.joinGame(id);
    }

    function _play(address p, uint256 id, uint8 col) internal {
        vm.prank(p);
        game.play(id, col);
    }

    // --- lifecycle ---

    function testCreateAndJoin() public {
        uint256 id = _active();
        (address p1, address p2, address turn,, TurnByTurn.Status st,,) = game.games(id);
        assertEq(p1, a);
        assertEq(p2, b);
        assertEq(turn, a);
        assertEq(uint256(st), uint256(TurnByTurn.Status.Active));
    }

    function testJoinOpenTwiceReverts() public {
        uint256 id = _active();
        vm.prank(stranger);
        vm.expectRevert(TurnByTurn.GameNotOpen.selector);
        game.joinGame(id);
    }

    function testCannotJoinOwnGame() public {
        uint256 id = _open();
        vm.prank(a);
        vm.expectRevert(TurnByTurn.CannotJoinOwnGame.selector);
        game.joinGame(id);
    }

    function testCancelOpenGame() public {
        uint256 id = _open();
        vm.prank(a);
        game.cancelGame(id);
        (,,,, TurnByTurn.Status st,,) = game.games(id);
        assertEq(uint256(st), uint256(TurnByTurn.Status.Cancelled));
    }

    function testStrangerCannotCancel() public {
        uint256 id = _open();
        vm.prank(stranger);
        vm.expectRevert(TurnByTurn.NotPlayer.selector);
        game.cancelGame(id);
    }

    function testPlayBeforeJoinReverts() public {
        uint256 id = _open();
        vm.prank(a);
        vm.expectRevert(TurnByTurn.GameNotActive.selector);
        game.play(id, 3);
    }

    // --- move rules ---

    function testNotYourTurn() public {
        uint256 id = _active();
        vm.prank(b);
        vm.expectRevert(TurnByTurn.NotYourTurn.selector);
        game.play(id, 0);
    }

    function testStrangerCannotMove() public {
        uint256 id = _active();
        vm.prank(stranger);
        vm.expectRevert(TurnByTurn.NotYourTurn.selector);
        game.play(id, 0);
    }

    function testColumnOutOfRange() public {
        uint256 id = _active();
        vm.prank(a);
        vm.expectRevert(TurnByTurn.ColumnOutOfRange.selector);
        game.play(id, 7);
    }

    function testColumnFull() public {
        uint256 id = _active();
        // Fill column 0 to the top with a/b alternation, using cols 1..4 as
        // fillers for the other player. Sequence (verified by simulation):
        // a0 b1 | a0 b1 | a0 b1  (col0: A,A,A rows 0,2,4... no—gravity: col0 rows 0,1,2 etc.)
        // Use the same simulated prefix as the draw sequence but stop when col0 is full:
        // draw-seq prefix: 5,4,5,0,6,2,4,5,5,0,4,1,1,0,4,5,6,5,3,1,1,2,2,6,2,6,6,3,6,2,0,3,0,3,3,4,3,1,4,2,1,0
        // col0 gets hits at moves 4(b? idx3=0? ) — simpler: play the full draw prefix until col0 is full (6 discs).
        uint8[16] memory seq = [5, 4, 5, 0, 6, 2, 4, 5, 5, 0, 4, 1, 1, 0, 4, 5];
        // col0 occupied at seq idx 3 (row0), 9 (row1), 13 (row2) — not enough.
        // Direct approach: fill col0 by having the turn player play 0, fillers in col 2/3.
        // a:0 b:2 a:0 b:2 a:0 b:2 -> col0 rows0,1,2 (a,a,a)... wait col0 gets a at 0, a at 1? No:
        // each a-move into col0 stacks. Sequence: a0 (r0), b2, a0 (r1), b2, a0 (r2), b3,
        // a0 (r3), b3, a0 (r4), b4, a0 (r5) -> col0 full, all a-discs (vertical 6 — but that
        // WINS at 4! So interleave: col0 must mix discs: a0(r0) b0? b can't play 0 unless turn.
        // Order: a0 b0 a0 b0 a0 b0 — but a0 three in a col? a at r0,r2,r4; b at r1,r3,r5: no 4-in-row.
        _play(a, id, 0); _play(b, id, 0);
        _play(a, id, 0); _play(b, id, 0);
        _play(a, id, 0); _play(b, id, 0);
        // column 0 now full (6 discs, alternating). Next move to col 0 must revert.
        vm.prank(a);
        vm.expectRevert(TurnByTurn.ColumnFull.selector);
        game.play(id, 0);
    }

    // --- win detection: all four directions ---

    function testWinHorizontal() public {
        uint256 id = _active();
        // a: cols 0,1,2,3 (bottom row); b: cols 4,5,6
        _play(a, id, 0); _play(b, id, 4);
        _play(a, id, 1); _play(b, id, 5);
        _play(a, id, 2); _play(b, id, 6);
        _play(a, id, 3);
        (,,, address w, TurnByTurn.Status st,,) = game.games(id);
        assertEq(w, a);
        assertEq(uint256(st), uint256(TurnByTurn.Status.Finished));
    }

    function testWinVertical() public {
        uint256 id = _active();
        // a stacks col 0 four times; b plays col 1
        _play(a, id, 0); _play(b, id, 1);
        _play(a, id, 0); _play(b, id, 1);
        _play(a, id, 0); _play(b, id, 1);
        _play(a, id, 0);
        (,,, address w,,,) = game.games(id);
        assertEq(w, a);
    }

    function testWinDiagonalUp() public {
        uint256 id = _active();
        // a wins on / diagonal: (0,0),(1,1),(2,2),(3,3)
        _play(a, id, 0); _play(b, id, 1);
        _play(a, id, 1); _play(b, id, 2);
        _play(a, id, 3); _play(b, id, 2);
        _play(a, id, 2); _play(b, id, 3);
        _play(a, id, 4); _play(b, id, 3);
        _play(a, id, 3);
        (,,, address w,,,) = game.games(id);
        assertEq(w, a);
    }

    function testWinDiagonalDown() public {
        uint256 id = _active();
        // a wins on \ diagonal: (3,0),(2,1),(1,2),(0,3)
        _play(a, id, 3); _play(b, id, 2);
        _play(a, id, 2); _play(b, id, 1);
        _play(a, id, 0); _play(b, id, 1);
        _play(a, id, 1); _play(b, id, 0);
        _play(a, id, 4); _play(b, id, 0);
        _play(a, id, 0);
        (,,, address w,,,) = game.games(id);
        assertEq(w, a);
    }

    function testNoFalseWinThreeInRow() public {
        uint256 id = _active();
        _play(a, id, 0); _play(b, id, 4);
        _play(a, id, 1); _play(b, id, 5);
        _play(a, id, 2);
        (,,, address w, TurnByTurn.Status st,,) = game.games(id);
        assertEq(w, address(0));
        assertEq(uint256(st), uint256(TurnByTurn.Status.Active));
    }

    // --- draw: full board, no winner (hand-computed sequence in TurnByTurnDraw.t.sol) ---

    // --- timeout ---

    function testTimeoutClaim() public {
        uint256 id = _active();
        _play(a, id, 0);
        // b stalls; warp past TIMEOUT
        vm.warp(block.timestamp + 3 days + 1);
        vm.prank(a);
        game.claimTimeout(id);
        (,,, address w, TurnByTurn.Status st,,) = game.games(id);
        assertEq(w, a);
        assertEq(uint256(st), uint256(TurnByTurn.Status.Finished));
    }

    function testTimeoutTooEarly() public {
        uint256 id = _active();
        _play(a, id, 0);
        vm.warp(block.timestamp + 3 days - 1);
        vm.prank(a);
        vm.expectRevert(TurnByTurn.TimeoutNotReached.selector);
        game.claimTimeout(id);
    }

    function testCannotClaimOnOwnTurn() public {
        uint256 id = _active();
        vm.warp(block.timestamp + 10 days);
        vm.prank(a); // it's a's turn
        vm.expectRevert(TurnByTurn.NotYourTurn.selector);
        game.claimTimeout(id);
    }

    function testStrangerCannotClaimTimeout() public {
        uint256 id = _active();
        _play(a, id, 0);
        vm.warp(block.timestamp + 10 days);
        vm.prank(stranger);
        vm.expectRevert(TurnByTurn.NotPlayer.selector);
        game.claimTimeout(id);
    }

    // --- board view ---

    function testBoardView() public {
        uint256 id = _active();
        _play(a, id, 3); _play(b, id, 3); _play(a, id, 3);
        uint8[] memory board = game.boardOf(id);
        assertEq(board.length, 42);
        assertEq(board[3], 1);      // row0 col3 = player1
        assertEq(board[7 + 3], 2);  // row1 col3 = player2
        assertEq(board[14 + 3], 1); // row2 col3 = player1
        assertEq(board[0], 0);
    }

    function testGamesOfTracksBothPlayers() public {
        uint256 id = _active();
        uint256[] memory ga = game.gamesOf(a);
        uint256[] memory gb = game.gamesOf(b);
        assertEq(ga.length, 1);
        assertEq(gb.length, 1);
        assertEq(ga[0], id);
        assertEq(gb[0], id);
    }

    function testOpenGamesListsOnlyOpen() public {
        uint256 open1 = _open();
        _active(); // joined, not open
        uint256 open2 = _open();
        uint256[] memory ids = game.openGames(10);
        assertEq(ids.length, 2);
        assertEq(ids[0], open2); // newest first
        assertEq(ids[1], open1);
    }

    // --- fuzz: illegal moves always revert, game never bricks ---

    function testFuzzRandomColumnsNeverBrick(uint256 seed) public {
        uint256 id = _active();
        address cur = a;
        for (uint256 i = 0; i < 30; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint8 col = uint8(seed % 7);
            (,, address t,, TurnByTurn.Status st,,) = game.games(id);
            if (uint256(st) != uint256(TurnByTurn.Status.Active)) break;
            address who = t;
            (,,,,,, uint8 movesPlayed) = game.games(id);
            movesPlayed;
            // column full check via boardOf: column full iff top row (row 5) cell occupied
            bool colFull = game.boardOf(id)[5 * 7 + col] != 0;
            if (colFull) {
                vm.prank(who);
                vm.expectRevert(TurnByTurn.ColumnFull.selector);
                game.play(id, col);
                continue;
            }
            vm.prank(who);
            game.play(id, col);
            cur = who;
        }
        cur;
        // game is always in a valid status
        (,,,, TurnByTurn.Status st2,,) = game.games(id);
        assertTrue(uint256(st2) <= uint256(TurnByTurn.Status.Cancelled));
    }
}
