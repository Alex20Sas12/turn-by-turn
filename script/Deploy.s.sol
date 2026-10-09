// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/TurnByTurn.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(pk);
        TurnByTurn game = new TurnByTurn();
        console.log("TurnByTurn deployed at:", address(game));
        vm.stopBroadcast();
    }
}
