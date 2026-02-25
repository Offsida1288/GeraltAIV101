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

    // -------------------------------------------------------------------------
    // ERRORS
    // -------------------------------------------------------------------------

    error GAV_ZeroRequestId();
    error GAV_NotOperator();
    error GAV_NotSessionKeeper();
    error GAV_ResponseAlreadySet();
    error GAV_RequestAlreadySubmitted();
    error GAV_MaxRequestsReached();
    error GAV_InvalidIndex();
    error GAV_ZeroAddress();
    error GAV_InvalidBatchLength();
    error GAV_ZeroSessionId();
    error GAV_SessionExists();
    error GAV_WhenPaused();
    error GAV_ReentrantCall();

    // -------------------------------------------------------------------------
    // CONSTANTS
    // -------------------------------------------------------------------------

    uint256 public constant GAV_MAX_REQUESTS = 100_000;
    uint256 public constant GAV_MAX_BATCH = 80;
    uint256 public constant GAV_MAX_SESSION_REQUESTS = 500;
    bytes32 public constant GAV_DOMAIN = keccak256("GeraltAIV101.GAV_DOMAIN");

    // -------------------------------------------------------------------------
    // IMMUTABLES
    // -------------------------------------------------------------------------

    address public immutable operator;
    address public immutable sessionKeeper;
    uint256 public immutable deployBlock;

    // -------------------------------------------------------------------------
    // STATE
    // -------------------------------------------------------------------------

    mapping(bytes32 => bytes32) private _responseOf;
    mapping(bytes32 => address) private _promptSenderOf;
    mapping(bytes32 => uint256) private _promptBlockOf;
    bytes32[] private _requestIds;
    uint256 public requestCount;

    mapping(bytes32 => bytes32[]) private _sessionRequestIds;
    mapping(bytes32 => bool) private _sessionExists;
    bytes32[] private _sessionIds;
    uint256 public sessionCount;

    bool private _paused;
    uint256 private _reentrancyLock;

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------

    constructor() {
        operator = address(0x91f2A4b6C8d0E2f4A6b8C0d2E4f6A8b0C2d4E6f8);
        sessionKeeper = address(0xC3d5E7f9A1b3C5d7E9f1A3b5C7d9E1f3A5b7C9d1);
        deployBlock = block.number;
        if (operator == address(0) || sessionKeeper == address(0)) revert GAV_ZeroAddress();
    }

    // -------------------------------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------------------------------

    modifier onlyOperator() {
        if (msg.sender != operator) revert GAV_NotOperator();
        _;
    }

    modifier onlySessionKeeper() {
        if (msg.sender != sessionKeeper) revert GAV_NotSessionKeeper();
        _;
    }

    modifier whenNotPaused() {
        if (_paused) revert GAV_WhenPaused();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyLock != 0) revert GAV_ReentrantCall();
        _reentrancyLock = 1;
        _;
        _reentrancyLock = 0;
    }

    // -------------------------------------------------------------------------
    // PUBLIC: SUBMIT PROMPT
    // -------------------------------------------------------------------------

    function submitPrompt(bytes32 requestId, bytes32 promptHash) external whenNotPaused nonReentrant {
        if (requestId == bytes32(0)) revert GAV_ZeroRequestId();
        if (_promptBlockOf[requestId] != 0) revert GAV_RequestAlreadySubmitted();
        if (requestCount >= GAV_MAX_REQUESTS) revert GAV_MaxRequestsReached();

        _promptSenderOf[requestId] = msg.sender;
        _promptBlockOf[requestId] = block.number;
        _requestIds.push(requestId);
        requestCount++;

        emit PromptSubmitted(msg.sender, requestId, promptHash, block.number);
    }

    // -------------------------------------------------------------------------
    // OPERATOR: SET RESPONSE (SINGLE + BATCH)
    // -------------------------------------------------------------------------

    function setResponse(bytes32 requestId, bytes32 responseHash) external onlyOperator {
        if (requestId == bytes32(0)) revert GAV_ZeroRequestId();
        if (_responseOf[requestId] != bytes32(0)) revert GAV_ResponseAlreadySet();

        _responseOf[requestId] = responseHash;
        emit ResponseSet(requestId, responseHash, block.number);
    }

    function setResponseBatch(bytes32[] calldata requestIds, bytes32[] calldata responseHashes) external onlyOperator {
        if (requestIds.length != responseHashes.length) revert GAV_InvalidBatchLength();
        if (requestIds.length == 0 || requestIds.length > GAV_MAX_BATCH) revert GAV_InvalidBatchLength();

        for (uint256 i; i < requestIds.length; ) {
            bytes32 rid = requestIds[i];
            if (rid != bytes32(0) && _responseOf[rid] == bytes32(0)) {
                _responseOf[rid] = responseHashes[i];
            }
            unchecked { ++i; }
        }
        emit ResponseBatchSet(requestIds.length, block.number);
    }

    // -------------------------------------------------------------------------
    // SESSION KEEPER: SESSIONS
    // -------------------------------------------------------------------------

    function createSession(bytes32 sessionId) external onlySessionKeeper {
        if (sessionId == bytes32(0)) revert GAV_ZeroSessionId();
        if (_sessionExists[sessionId]) revert GAV_SessionExists();

        _sessionExists[sessionId] = true;
        _sessionIds.push(sessionId);
        sessionCount++;

        emit SessionCreated(sessionId, msg.sender, 0, block.number);
    }

    function appendSessionRequest(bytes32 sessionId, bytes32 requestId) external onlySessionKeeper {
        if (sessionId == bytes32(0)) revert GAV_ZeroSessionId();
        if (!_sessionExists[sessionId]) revert GAV_InvalidIndex();
        if (_sessionRequestIds[sessionId].length >= GAV_MAX_SESSION_REQUESTS) revert GAV_MaxRequestsReached();

        _sessionRequestIds[sessionId].push(requestId);
        emit SessionRequestAppended(sessionId, requestId, block.number);
    }

    // -------------------------------------------------------------------------
    // OPERATOR: PAUSE
    // -------------------------------------------------------------------------

    function setPaused(bool paused) external onlyOperator {
        _paused = paused;
        emit PauseToggled(paused, msg.sender, block.number);
    }

    function isPaused() external view returns (bool) {
        return _paused;
    }

    // -------------------------------------------------------------------------
    // VIEWS: PROMPT / RESPONSE
    // -------------------------------------------------------------------------

    function getResponse(bytes32 requestId) external view returns (bytes32) {
        return _responseOf[requestId];
    }

    function getPromptSender(bytes32 requestId) external view returns (address) {
        return _promptSenderOf[requestId];
    }

    function getPromptBlock(bytes32 requestId) external view returns (uint256) {
        return _promptBlockOf[requestId];
    }

    function getRequestAt(uint256 index) external view returns (bytes32) {
        if (index >= _requestIds.length) revert GAV_InvalidIndex();
        return _requestIds[index];
    }

    function totalRequests() external view returns (uint256) {
        return _requestIds.length;
    }

    // -------------------------------------------------------------------------
    // VIEWS: SESSIONS
    // -------------------------------------------------------------------------

    function getSessionRequestCount(bytes32 sessionId) external view returns (uint256) {
        return _sessionRequestIds[sessionId].length;
    }

    function getSessionRequestAt(bytes32 sessionId, uint256 index) external view returns (bytes32) {
        bytes32[] storage arr = _sessionRequestIds[sessionId];
        if (index >= arr.length) revert GAV_InvalidIndex();
        return arr[index];
    }
