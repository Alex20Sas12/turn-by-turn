// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TurnByTurn.sol";

/// Full-board draw: 42 moves, strict a/b alternation, no connect-4.
/// Sequence verified by exhaustive simulation (no win on any placement,
/// gravity-respecting). A moves first (even indices), B on odd.
contract TurnByTurnDrawTest is Test {
    TurnByTurn game;
    address a = address(0xA11CE);
    address b = address(0xB0B);

    function testFullBoardDraw() public {
        game = new TurnByTurn();
        vm.prank(a);
        uint256 id = game.createGame();
        vm.prank(b);
        game.joinGame(id);

        uint8[42] memory cols = [
            5, 4, 5, 0, 6, 2, 4, 5, 5, 0, 4, 1, 1, 0, 4, 5, 6, 5, 3, 1, 1,
            2, 2, 6, 2, 6, 6, 3, 6, 2, 0, 3, 0, 3, 3, 4, 3, 1, 4, 2, 1, 0
        ];
        for (uint8 i = 0; i < 42; i++) {
            address who = i % 2 == 0 ? a : b;
            vm.prank(who);
            game.play(id, cols[i]);
        }

        (,,, address w, TurnByTurn.Status st,, uint8 moves) = game.games(id);
        assertEq(moves, 42);
        assertEq(uint256(st), uint256(TurnByTurn.Status.Finished));
        assertEq(w, address(0)); // draw: no winner
    }
}
