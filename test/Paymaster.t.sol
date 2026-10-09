// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TurnByTurn.sol";
import "../src/TurnByTurnPaymaster.sol";

contract PaymasterTest is Test {
    TurnByTurn game;
    TurnByTurnPaymaster pm;
    uint256 signerKey = 0x5A1;
    address signer;
    address player = address(0xBEEF);

    function setUp() public {
        game = new TurnByTurn();
        signer = vm.addr(signerKey);
        pm = new TurnByTurnPaymaster(IEntryPoint(address(0xE7)), address(game), signer);
    }

    function _userOp(bytes memory cd) internal view returns (PackedUserOperation memory op) {
        op.sender = player;
        op.nonce = 0;
        // SimpleAccount-style: execute(game, 0, cd)
        op.callData = abi.encodeWithSelector(
            bytes4(keccak256("execute(address,uint256,bytes)")),
            address(game), uint256(0), cd
        );
        // paymasterAndData: header(52) + validUntil(6) + validAfter(6) + sig(65)
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        bytes32 h = keccak256(abi.encode(player, uint256(0), keccak256(cd), block.chainid, validUntil));
        bytes32 ethH = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethH);
        bytes memory sig = abi.encodePacked(r, s, v);
        op.paymasterAndData = abi.encodePacked(
            address(pm), uint128(0), uint128(0), validUntil, uint48(0), sig
        );
    }

    function _validate(PackedUserOperation memory op) internal returns (bytes memory, uint256) {
        vm.prank(address(0xE7));
        return pm.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    function testSponsorsGameMove() public {
        (PackedUserOperation memory op) = _userOp(abi.encodeWithSelector(TurnByTurn.createGame.selector));
        (, uint256 vd) = _validate(op);
        assertEq(vd & 1, 0, "signature accepted");
        assertGt(vd >> 160, 0, "validUntil set");
    }

    function testRejectsForeignContract() public {
        PackedUserOperation memory op = _userOp(abi.encodeWithSelector(TurnByTurn.createGame.selector));
        // retarget callData at another contract
        op.callData = abi.encodeWithSelector(
            bytes4(keccak256("execute(address,uint256,bytes)")),
            address(0xDEAD), uint256(0), abi.encodeWithSelector(TurnByTurn.createGame.selector)
        );
        vm.prank(address(0xE7));
        vm.expectRevert(TurnByTurnPaymaster.BadSelector.selector);
        pm.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    function testRejectsNonGameSelector() public {
        PackedUserOperation memory op = _userOp(abi.encodeWithSelector(TurnByTurn.cancelGame.selector, uint256(1)));
        vm.prank(address(0xE7));
        vm.expectRevert(TurnByTurnPaymaster.BadSelector.selector);
        pm.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    function testRejectsBadSignature() public {
        PackedUserOperation memory op = _userOp(abi.encodeWithSelector(TurnByTurn.createGame.selector));
        // corrupt the signature's `r` component — ecrecover yields wrong address
        op.paymasterAndData[64] = bytes1(uint8(uint8(op.paymasterAndData[64]) ^ 0xFF));
        vm.prank(address(0xE7));
        vm.expectRevert(TurnByTurnPaymaster.BadSignature.selector);
        pm.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    function testRateLimit() public {
        bytes memory cd = abi.encodeWithSelector(TurnByTurn.createGame.selector);
        for (uint256 i = 0; i < 8; i++) {
            PackedUserOperation memory op = _userOp(cd);
            op.nonce = i;
            // re-sign with matching nonce
            uint48 validUntil = uint48(block.timestamp + 1 hours);
            bytes32 h = keccak256(abi.encode(player, i, keccak256(cd), block.chainid, validUntil));
            bytes32 ethH = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethH);
            op.paymasterAndData = abi.encodePacked(address(pm), uint128(0), uint128(0), validUntil, uint48(0), abi.encodePacked(r, s, v));
            _validate(op);
        }
        PackedUserOperation memory op9 = _userOp(cd);
        vm.prank(address(0xE7));
        vm.expectRevert(TurnByTurnPaymaster.RateLimited.selector);
        pm.validatePaymasterUserOp(op9, bytes32(0), 0);
    }

    function testRateLimitResetsNextDay() public {
        bytes memory cd = abi.encodeWithSelector(TurnByTurn.createGame.selector);
        vm.warp(block.timestamp + 2 days);
        PackedUserOperation memory op = _userOp(cd);
        _validate(op); // should not revert
    }

    function testOnlyEntryPoint() public {
        PackedUserOperation memory op = _userOp(abi.encodeWithSelector(TurnByTurn.createGame.selector));
        vm.expectRevert(TurnByTurnPaymaster.OnlyEntryPoint.selector);
        pm.validatePaymasterUserOp(op, bytes32(0), 0);
    }
}
