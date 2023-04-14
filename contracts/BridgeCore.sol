// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

error ArrayLengthMissmatch(uint256 expectedLength, uint256 actualLength);
error AmountIsLessThanMinimum(uint256 amount, uint256 minAmount);
error AmountIsNotEqualToMsgValue(uint256 amount, uint256 msgValue);
error NonceIsUsed(uint256 nonce);
error TokenIsNotSupported(address token);
error RefundIsBlocked(uint256 nonce);
error MinTimeToRefundIsNotReached(uint256 minTimeToRefund, uint256 creationTime); 
error OnlyRelayerOrCreatorCanRefund(uint256 nonce);
error MsgValueShouldBeZero();
error FailedToSendEther();
error ChainIsNotSupported(uint8 chainId);
error TokenIsNotSupportedOnChain(address token, uint8 chainId);
error MinTimeToWaitBeforeRefundIsTooBig(uint256 minTimeToWaitBeforeRefund);

contract BridgeCore is UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    struct NonceInfo{
        address token;
        address creator;
        address to;
        uint8 dstChainId;
        address dstToken;
        uint256 amount;
        uint256 creationTime;
    }
    /// @notice Role required to withdraw and refund tokens from the bridge
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    /// @notice Mapping for supported chains (chainId => isSupported)
    mapping(uint8 => bool) public chainIsSupported;
    /// @notice Minimum time to wait before refunding a transaction
    uint256 public minTimeToWaitBeforeRefund;
    /// @notice Address of the wrapped native token
    address public wrappedNative;

    /// @notice Mapping of supported tokens (token => isSupported)
    mapping(address => bool) public tokenIsSupported;
    /// @notice Mapping of minimum amount for tokens (token => minAmount)
    mapping(address => uint256) public minAmountForToken;
    /// @notice Mapping of other chains tokens (token => chainId => otherChainToken)
    mapping(address => mapping(uint8 => address)) public otherChainToken;
    /// @notice Unique nonce for each send transaction
    uint256 public nonce;
    /// @notice Mapping of used nonces (nonce => isUsed)
    mapping(uint256 => bool) public nonceIsUsed;
    /// @notice Mapping of nonce info (nonce => NonceInfo)
    mapping (uint256 => NonceInfo) public nonceInfo;
    /// @notice Mapping of blocked nonces for refund (nonce => isBlocked)
    mapping (uint256 => bool) public nonceIsBlockedForRefund;

    event Refund(address indexed token, address indexed to, uint256 amount, uint256 nonce);
    event BlockRefund(uint256 nonce);
    event Send(address indexed token, address indexed tokenOnSecondChain, address indexed to, uint256 amount, uint256 nonce);
    event Withdraw(address indexed token, address indexed tokenOnSecondChain, address indexed to, uint256 amount, uint256 nonce);
    event AddToken(address indexed token, address indexed tokenOnSecondChain, uint256 minAmount);

    /// @notice Modifier to check if the token is supported
    /// @param token Address of the token
    modifier onlySupportedToken(address token) {
        if (!tokenIsSupported[token]) {
            revert TokenIsNotSupported(token);
        }
        _;
    }

    /// @notice Modifier to check if chain is supported
    /// @param chainId Chain id
    modifier onlySupportedChain(uint8 chainId) {
        if (!chainIsSupported[chainId]) {
            revert ChainIsNotSupported(chainId);
        }
        _;
    }

    /// @notice function to initialize the contract
    function initialize(
        uint8[] calldata _supportedChains,
        address _wrappedNative,
        uint256 _minAmountForNative,
        address[] calldata _otherChainsTokenForNative,
        address _relayer,
        uint256 _minTimeToWaitBeforeRefund
    ) public initializer virtual {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(RELAYER_ROLE, _relayer);
        wrappedNative = _wrappedNative;
        if(_supportedChains.length != _otherChainsTokenForNative.length)
            revert ArrayLengthMissmatch(_supportedChains.length, _otherChainsTokenForNative.length);
        // add native tokens for supported chains
        for(uint8 i = 0; i < _otherChainsTokenForNative.length; i++){
            chainIsSupported[_supportedChains[i]] = true;
            if(_otherChainsTokenForNative[i] != address(0))
            addToken(_wrappedNative, _otherChainsTokenForNative[i], _supportedChains[i], _minAmountForNative);
        }
        minTimeToWaitBeforeRefund = _minTimeToWaitBeforeRefund;
    }

    /// @notice function to send tokens to the second chain
    /// @dev the function can be called only by a supported token and only emits a specific event for the backend to listen to
    /// @param token Address of the token
    /// @param to Address of the receiver on the second chain
    /// @param amount Amount of tokens to send 
    function send(
        address token,
        address to,
        uint8 dstChainId,
        uint256 amount
    ) external payable whenNotPaused onlySupportedToken(token) onlySupportedChain(dstChainId) {
        if(amount < minAmountForToken[token]) 
            revert AmountIsLessThanMinimum(amount, minAmountForToken[token]);
        if (token == wrappedNative){
            if(msg.value != amount) 
                revert AmountIsNotEqualToMsgValue(amount, msg.value);
        }
        else{
            if(msg.value != 0) 
                revert MsgValueShouldBeZero();
            IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        if(otherChainToken[token][dstChainId] == address(0))
            revert TokenIsNotSupportedOnChain(token, dstChainId);
        nonceInfo[nonce] = NonceInfo(
            token,
            msg.sender,
            to,
            dstChainId,
            otherChainToken[token][dstChainId],
            amount,
            block.timestamp
        );
        emit Send(token, otherChainToken[token][dstChainId], to, amount, nonce++);
    }

    /// @notice function to block a nonce for refund
    /// @dev the function can be called only by a relayer and should be called before withdrawing on the second chain
    /// @param nonceToBlock Nonce to block
    function blockRefund(uint256 nonceToBlock) external onlyRole(RELAYER_ROLE) {
        if(nonceIsBlockedForRefund[nonceToBlock])
            revert RefundIsBlocked(nonceToBlock);
        nonceIsBlockedForRefund[nonceToBlock] = true;
        emit BlockRefund(nonceToBlock);
    }

    /// @notice function to refund a transaction
    /// @dev the function can be called only by a relayer or the creator of the transaction
    /// @param nonceToRefund Nonce of the transaction to refund
    function refund(uint256 nonceToRefund) external {
        NonceInfo memory nonceInfoToRefund = nonceInfo[nonceToRefund];
        emit Refund(nonceInfoToRefund.token, nonceInfoToRefund.to, nonceInfoToRefund.amount, nonceToRefund);
        if(!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)){
            if(nonceIsBlockedForRefund[nonceToRefund])
                revert RefundIsBlocked(nonceToRefund);
            nonceIsBlockedForRefund[nonceToRefund] = true;
            if(block.timestamp <= nonceInfoToRefund.creationTime + minTimeToWaitBeforeRefund)
                revert MinTimeToRefundIsNotReached(
                    nonceInfoToRefund.creationTime + minTimeToWaitBeforeRefund,
                    block.timestamp
                );
            if(msg.sender != nonceInfoToRefund.creator && !hasRole(RELAYER_ROLE, msg.sender))
                revert OnlyRelayerOrCreatorCanRefund(nonceToRefund);
        }
        else{
            nonceIsBlockedForRefund[nonceToRefund] = true;
        }
        if(nonceInfoToRefund.token == wrappedNative){
            (bool sent,) = payable(nonceInfoToRefund.creator).call{value: nonceInfoToRefund.amount}("");
            if(!sent)
                revert FailedToSendEther();
        }
        else
            IERC20Upgradeable(nonceInfoToRefund.token).safeTransfer(nonceInfoToRefund.creator, nonceInfoToRefund.amount);
    }

    /// @notice function to withdraw tokens from the second chain
    /// @dev the function can be called only by a relayer and should be called after blocking the nonce for refund
    /// @param token Address of the token
    /// @param to Address of the receiver on the second chain
    /// @param amount Amount of tokens to withdraw
    /// @param nonceOnOtherChain Nonce of the transaction on the first chain
    function withdraw(
        address token,
        address to,
        uint256 amount,
        uint8 fromChainId,
        uint256 nonceOnOtherChain
    ) external whenNotPaused onlyRole(RELAYER_ROLE) onlySupportedToken(token) onlySupportedChain(fromChainId) {
        if(nonceIsUsed[nonceOnOtherChain]) 
            revert NonceIsUsed(nonceOnOtherChain);
        nonceIsUsed[nonceOnOtherChain] = true;
        emit Withdraw(token, otherChainToken[token][fromChainId], to, amount, nonceOnOtherChain);
        if(token == wrappedNative) {
            (bool sent,) = payable(to).call{value: amount}("");
            if(!sent)
                revert FailedToSendEther();
        } else {
            IERC20Upgradeable(token).safeTransfer(to, amount);
        }
    }

    /// @notice function to withdraw tokens from the bridge contract
    /// @dev can be called only in the paused state by the admin
    /// @param token Address of the token
    /// @param to Address of the receiver
    /// @param amount Amount of tokens to withdraw
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if(token == wrappedNative){
            (bool sent,) = payable(to).call{value: amount}("");
            if(!sent)
                revert FailedToSendEther();
        }
        else
            IERC20Upgradeable(token).safeTransfer(to, amount);
    }

    /// @notice function to add a new token to the bridge
    /// @param token Address of the token
    /// @param tokenOnSecondChain Address of the token on the second chain
    /// @param minAmount Minimum amount of tokens to send
    function addToken(
        address token,
        address tokenOnSecondChain,
        uint8 otherChainId,
        uint256 minAmount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenIsSupported[token] = true;
        if(!chainIsSupported[otherChainId])
            chainIsSupported[otherChainId] = true;
        minAmountForToken[token] = minAmount;
        otherChainToken[token][otherChainId] = tokenOnSecondChain;
        emit AddToken(token, tokenOnSecondChain, minAmount);
    }

    /// @notice function to set the minimum amount of tokens to send
    /// @param token Address of the token
    /// @param minAmount Minimum amount of tokens to send
    function setMinAmountForToken(address token, uint256 minAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minAmountForToken[token] = minAmount;
    }

    /// @notice function to set the address of the token on the second chain
    /// @param token Address of the token
    /// @param tokenOnSecondChain Address of the token on the second chain
    function setOtherChainToken(address token, address tokenOnSecondChain, uint8 otherChainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        otherChainToken[token][otherChainId] = tokenOnSecondChain;
    }

    /// @notice function to set the minimum time to wait before refunding a transaction
    /// @param _minTimeToWaitBeforeRefund Minimum time to wait before refunding a transaction
    function setTimeToWaitBeforeRefund(uint256 _minTimeToWaitBeforeRefund) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minTimeToWaitBeforeRefund > 1 hours) {
            revert MinTimeToWaitBeforeRefundIsTooBig(_minTimeToWaitBeforeRefund);
        }
        minTimeToWaitBeforeRefund = _minTimeToWaitBeforeRefund;
    } 

    /// @notice function to pause the bridge
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice function to unpause the bridge
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice function to ensure that only admin can upgrade the contract
    /// @param newImplementation Address of the new implementation 
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}

