// TurnByTurnPaymaster — ERC-4337 paymaster that sponsors game moves for
// players who hold no ETH. Verifying-paymaster pattern: our backend signer
// approves UserOps that call ONLY createGame/joinGame/play/claimTimeout on the
// game contract, per-sender rate-limited. EntryPoint pulls ETH from this
// contract's deposit; fund it with deposit() / receive.
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEntryPoint {
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;
    function balanceOf(address account) external view returns (uint256);
    function depositTo(address account) external payable;
    function getNonce(address sender, uint192 key) external view returns (uint256);
}

struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

contract TurnByTurnPaymaster {
    IEntryPoint public immutable entryPoint;
    address public immutable game;
    address public signer;          // backend key that approves sponsorship
    address public owner;           // only to rotate signer / withdraw surplus

    uint256 public constant MAX_SPONSOR_PER_SENDER_PER_DAY = 8;
    mapping(address => uint256) public dailyCount;   // dayIndex<<8 ... packed below
    mapping(address => uint256) public lastDay;

    event Sponsored(address indexed sender, bytes4 selector);
    event SignerRotated(address oldSigner, address newSigner);

    error OnlyEntryPoint();
    error OnlyOwner();
    error BadSelector();
    error RateLimited();
    error BadSignature();

    constructor(IEntryPoint _ep, address _game, address _signer) {
        entryPoint = _ep;
        game = _game;
        signer = _signer;
        owner = msg.sender;
    }

    receive() external payable {}

    function deposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    // --- ERC-4337 paymaster interface ---

    /// paymasterAndData layout after the standard 52-byte header
    /// (20 paymaster + 16 gasLimits + 16 gasFees):
    /// [48 bytes: validUntil(6) | validAfter(6) | signature(65)] — classic verifying layout
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 /*userOpHash*/,
        uint256 /*maxCost*/
    ) external returns (bytes memory context, uint256 validationData) {
        if (msg.sender != address(entryPoint)) revert OnlyEntryPoint();

        // 1. The op must call ONLY our game contract, only a game selector.
        (address target, bytes memory cd) = _decodeCall(userOp.callData);
        if (target != game) revert BadSelector();
        bytes4 sel;
        assembly { sel := mload(add(cd, 32)) }
        if (!_isGameSelector(sel)) revert BadSelector();

        // 2. Per-sender daily rate limit.
        uint256 day = block.timestamp / 1 days;
        if (lastDay[userOp.sender] != day) {
            lastDay[userOp.sender] = day;
            dailyCount[userOp.sender] = 0;
        }
        if (dailyCount[userOp.sender] >= MAX_SPONSOR_PER_SENDER_PER_DAY) revert RateLimited();
        dailyCount[userOp.sender] += 1;

        // 3. Backend signature over (sender, nonce, callData-hash, chain, expiry).
        (uint48 validUntil, bytes memory sig) = _parsePmData(userOp.paymasterAndData);
        if (block.timestamp > validUntil) revert BadSignature();
        bytes32 h = keccak256(abi.encode(userOp.sender, userOp.nonce, keccak256(cd), block.chainid, validUntil));
        if (_recover(_toEthSigned(h), sig) != signer) revert BadSignature();

        emit Sponsored(userOp.sender, sel);
        // validationData: sigFailure=0, validUntil, validAfter=0
        return ("", (uint256(validUntil) << 160));
    }

    function postOp(uint8, bytes calldata, uint256, uint256) external {
        if (msg.sender != address(entryPoint)) revert OnlyEntryPoint();
        // no post-op accounting needed — rate limit was applied at validate time
    }

    // --- helpers ---

    function _decodeCall(bytes memory callData) internal pure returns (address target, bytes memory cd) {
        // ERC-4337 v0.7 account callData: execute(address,uint256,bytes) —
        // abi-encoded (target, value, data). SimpleAccount-style.
        bytes4 sel;
        assembly { sel := mload(add(callData, 32)) }
        require(sel == bytes4(keccak256("execute(address,uint256,bytes)")), "unsupported account");
        assembly { target := mload(add(callData, 36)) }
        uint256 dataOff;
        assembly { dataOff := mload(add(callData, 100)) }  // offset of bytes arg
        uint256 len;
        assembly { len := mload(add(add(callData, 36), dataOff)) }
        cd = new bytes(len);
        assembly {
            let src := add(add(callData, 68), dataOff)   // 36 + 32 length word
            let dst := add(cd, 32)
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }
    }

    function _isGameSelector(bytes4 sel) internal pure returns (bool) {
        return sel == bytes4(keccak256("createGame()"))
            || sel == bytes4(keccak256("joinGame(uint256)"))
            || sel == bytes4(keccak256("play(uint256,uint8)"))
            || sel == bytes4(keccak256("claimTimeout(uint256)"));
    }

    function _parsePmData(bytes memory pmd) internal pure returns (uint48 validUntil, bytes memory sig) {
        // header: 20 addr + 16 + 16 = 52; then validUntil(6) + validAfter(6) + sig(65)
        require(pmd.length >= 52 + 12 + 65, "pm data short");
        assembly { validUntil := shr(208, mload(add(pmd, 84))) } // bytes 52..57
        sig = new bytes(65);
        assembly {
            let src := add(pmd, 96)   // 32 len + 52 header + 12 times
            let dst := add(sig, 32)
            mstore(dst, mload(src))
            mstore(add(dst, 32), mload(add(src, 32)))
            mstore(add(dst, 64), mload(add(src, 64))) // copies 96B, sig uses first 65
        }
    }

    function _toEthSigned(bytes32 h) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }

    function _recover(bytes32 h, bytes memory sig) internal pure returns (address) {
        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;
        address rec = ecrecover(h, v, r, s);
        if (rec == address(0)) revert BadSignature();
        return rec;
    }

    // --- owner ops ---

    function rotateSigner(address newSigner) external {
        if (msg.sender != owner) revert OnlyOwner();
        emit SignerRotated(signer, newSigner);
        signer = newSigner;
    }

    function withdrawSurplus(address payable to, uint256 amount) external {
        if (msg.sender != owner) revert OnlyOwner();
        require(address(this).balance >= amount, "insufficient");
        to.transfer(amount);
    }
}
