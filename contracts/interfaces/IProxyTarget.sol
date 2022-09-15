pragma solidity >=0.5.0;

interface IProxyTarget {
    function deposit(address token, uint256 amount, address to) external;
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address to) external;
    function stake(uint256 amount, address onBehalf) external;
}
