// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IFlypeRouter {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function addLiquidity(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );
    function removeLiquidity(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);
    function removeLiquidityWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    )external returns (uint256 amountToken, uint256 amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint256[] memory amounts, uint256[] memory fees);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )external returns (uint256[] memory amounts, uint256[] memory fees);
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )external
        payable
        returns (uint[] memory amounts, uint256[] memory fees);
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )external
        returns (uint[] memory amounts, uint256[] memory fees);
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )external
        returns (uint[] memory amounts, uint256[] memory fees);
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    )  external
        payable
        returns (uint[] memory amounts, uint256[] memory fees);

    function quote(uint amountA, uint reserveA, uint reserveB) external view returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external view returns (uint amountOut, uint256 fee);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external view returns (uint amountIn, uint256 fee);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts, uint256[] memory fees);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts, uint256[] memory fees);
}
