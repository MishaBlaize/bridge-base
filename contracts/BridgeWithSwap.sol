// SPDX-License-Identifier: MIT

import "./BridgeCore.sol";
import "./interfaces/IUniswapV2Router.sol";
pragma solidity 0.8.17;

error AlreadyInitialized();
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
    mapping(address => mapping(address => address[])) internal _pathForTokenToToken;

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

    function initializeSwapRouter(
        address _swapRouter
    ) external onlyRole(DEFAULT_ADMIN_ROLE){
        if(address(swapRouter) != address(0)) revert AlreadyInitialized();
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
    ) external payable whenNotPaused onlySupportedToken(tokenToSend) onlySupportedChain(dstChainId) {
        if(amountToSend < minAmountForToken[tokenToSend]) 
            revert AmountIsLessThanMinimum(amountToSend, minAmountForToken[tokenToSend]);
        if (tokenToSend == wrappedNative){
            if(msg.value != amountToSend) 
                revert AmountIsNotEqualToMsgValue(amountToSend, msg.value);
        }
        else{
            if(msg.value != 0) 
                revert MsgValueShouldBeZero();
            IERC20Upgradeable(tokenToSend).safeTransferFrom(msg.sender, address(this), amountToSend);
        }
        nonceInfo[nonce] = NonceInfo(
            tokenToSend,
            msg.sender,
            to,
            _chainId(),
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
    ) external whenNotPaused onlyRole(RELAYER_ROLE) onlySupportedToken(tokenToReceive) onlySupportedChain(fromChainId){
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
                getPathForTokenToToken(wrappedNative, tokenToReceive),
                to,
                deadline
            );
        } 
        else if(tokenToReceive == wrappedNative){
            IERC20Upgradeable(tokenSent).safeApprove(address(swapRouter), amountSent);
            swapRouter.swapExactTokensForETH(
                amountSent,
                minAmountToReceive,
                getPathForTokenToToken(tokenSent, wrappedNative),
                to,
                deadline
            );
        }
        else{
            IERC20Upgradeable(tokenSent).safeApprove(address(swapRouter), amountSent);
            swapRouter.swapExactTokensForTokens(
                amountSent,
                minAmountToReceive,
                getPathForTokenToToken(tokenSent, tokenToReceive),
                to,
                deadline
            );
        }
    }

    function getPathForTokenToToken(
        address tokenSent,
        address tokenToReceive
    ) public view returns (address[] memory path) {
        path = _pathForTokenToToken[tokenSent][tokenToReceive];
        if(path.length == 0){
            if(tokenSent == wrappedNative){
                path = new address[](2);
                path[0] = wrappedNative;
                path[1] = tokenToReceive;
            }
            else if(tokenToReceive == wrappedNative){
                path = new address[](2);
                path[0] = tokenSent;
                path[1] = wrappedNative;
            }
            else{
                path = new address[](3);
                path[0] = tokenSent;
                path[1] = wrappedNative;
                path[2] = tokenToReceive;
            }
        }
    }


    function setPathForTokenToToken(
        address tokenSent,
        address tokenToReceive,
        address[] calldata path
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pathForTokenToToken[tokenSent][tokenToReceive] = path;
    }
}