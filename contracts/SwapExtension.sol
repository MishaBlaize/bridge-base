// SPDX-License-Identifier: MIT

import "./BridgeCore.sol";
import "./interfaces/IUniswapV2Router.sol";
pragma solidity 0.8.17;

error InvalidInitializerUsed();
contract BridgeWithSwap is BridgeCore {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    struct SwapInfo {
        address tokenToSend;
        address tokenToReceive;
        uint256 amountToSend;
        uint256 minAmountToReceive;
        uint256 deadline;
    }

    IUniswapV2Router public swapRouter;
    /// @notice Mapping of nonce to swap info
    mapping(uint256 => SwapInfo) public swapInfo;
    mapping(address => mapping(address => address[])) public getPathForTokenToToken;

    event SendWithSwap(
        address indexed tokenToSend,
        address indexed tokenToReceive,
        address indexed to,
        uint256 amountToSend,
        uint256 minAmountToReceive,
        uint256 deadline,
        uint256 nonce
    );
    event WithdrawWithSwap(
        address indexed tokenSent,
        address indexed tokenToReceive,
        address indexed to,
        uint256 amountSent,
        uint256 minAmountToReceive,
        uint8 fromChainId,
        uint256 nonceOnOtherChain,
        uint256 deadline
    );

    modifier onlySupportedTokens(address token, address tokenToReceive) {
        if (!tokenIsSupported[token]) {
            revert TokenIsNotSupported(token);
        }
        else if (!tokenIsSupported[tokenToReceive]) {
            revert TokenIsNotSupported(tokenToReceive);
        }
        _;
    }

    function initialize(
        uint8[] calldata,
        address,
        uint256,
        address[] calldata,
        address,
        uint256
    ) public override initializer {
        revert InvalidInitializerUsed();
    }

    function initialize(
        uint8[] calldata _supportedChains,
        address _wrappedNative,
        uint256 _minAmountForNative,
        address[] calldata _otherChainsTokenForNative,
        address _relayer,
        uint256 _minTimeToWaitBeforeRefund,
        address _swapRouter
    ) public {
        super.initialize(
            _supportedChains,
            _wrappedNative,
            _minAmountForNative,
            _otherChainsTokenForNative,
            _relayer,
            _minTimeToWaitBeforeRefund
        );
        swapRouter = IUniswapV2Router(_swapRouter);
    }

    function sendWithSwap(
        address tokenToSend,
        address tokenToReceive,
        address to,
        uint8 dstChainId,
        uint256 amountToSend,
        uint256 minAmountToReceive,
        uint256 deadline
    ) external payable whenNotPaused onlySupportedTokens(tokenToSend, tokenToReceive) {
        if(amountToSend < minAmountForToken[tokenToSend]) 
            revert AmountIsLessThanMinimum(amountToSend, minAmountForToken[tokenToSend]);
        if (tokenToSend == wrappedNative) 
            if(msg.value != amountToSend) 
                revert AmountIsNotEqualToMsgValue(amountToSend, msg.value);
        else{
            if(msg.value != 0) 
                revert MsgValueShouldBeZero();
            IERC20Upgradeable(tokenToSend).safeTransferFrom(msg.sender, address(this), amountToSend);
        }
        nonceInfo[nonce] = NonceInfo(
            tokenToSend,
            msg.sender,
            to,
            dstChainId,
            tokenToReceive,
            amountToSend,
            block.timestamp
        );
        swapInfo[nonce] = SwapInfo(
            tokenToSend,
            tokenToReceive,
            amountToSend,
            minAmountToReceive,
            deadline
        );
        emit SendWithSwap(
            tokenToSend,
            tokenToReceive,
            to,
            amountToSend,
            minAmountToReceive,
            deadline,
            nonce++
        );
    }

    function withdrawWithSwap(
        address tokenSent,
        address tokenToReceive,
        address to,
        uint256 amountSent,
        uint256 minAmountToReceive,
        uint8 fromChainId,
        uint256 nonceOnOtherChain,
        uint256 deadline
    ) external whenNotPaused onlyRole(RELAYER_ROLE) onlySupportedTokens(tokenSent, tokenToReceive){
        if(nonceIsUsed[nonceOnOtherChain])
            revert NonceIsUsed(nonceOnOtherChain);
        nonceIsUsed[nonceOnOtherChain] = true;
        emit WithdrawWithSwap(
            tokenSent,
            tokenToReceive,
            to,
            amountSent,
            minAmountToReceive,
            fromChainId,
            nonceOnOtherChain,
            deadline
        );
        if(tokenSent == wrappedNative) {
            swapRouter.swapExactETHForTokens{value: amountSent}(
                minAmountToReceive,
                getPathForTokenToToken[wrappedNative][tokenToReceive],
                to,
                deadline
            );
        } else{
            IERC20Upgradeable(tokenSent).safeApprove(address(swapRouter), amountSent);
            swapRouter.swapExactTokensForTokens(
                amountSent,
                minAmountToReceive,
                getPathForTokenToToken[tokenSent][tokenToReceive],
                to,
                deadline
            );
        }
    }


    function setPathForTokenToToken(
        address tokenSent,
        address tokenToReceive,
        address[] calldata path
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        getPathForTokenToToken[tokenSent][tokenToReceive] = path;
    }
}