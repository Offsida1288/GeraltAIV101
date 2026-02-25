// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title GeraltAIV101
/// @notice Extended chatbot response ledger: sessions, batch responses, pause, and session keeper. Builds on GeraltAI-style prompt/response commitments with extra safety and structure.
/// @dev Operator and sessionKeeper are immutable. Remix: compile 0.8.20+, deploy with no args.

contract GeraltAIV101 {

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------

    event PromptSubmitted(address indexed user, bytes32 requestId, bytes32 promptHash, uint256 atBlock);
    event ResponseSet(bytes32 indexed requestId, bytes32 responseHash, uint256 atBlock);
    event ResponseBatchSet(uint256 count, uint256 atBlock);
    event SessionCreated(bytes32 indexed sessionId, address indexed creator, uint256 requestCount, uint256 atBlock);
    event SessionRequestAppended(bytes32 indexed sessionId, bytes32 requestId, uint256 atBlock);
    event PauseToggled(bool paused, address indexed by, uint256 atBlock);
