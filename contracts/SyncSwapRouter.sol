pragma solidity =0.5.17;

import './interfaces/ISyncSwapFactory.sol';
import './libraries/TransferHelper.sol';
import './interfaces/ISyncSwapRouter.sol';
import './libraries/SyncSwapLibrary.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';
import './interfaces/IProxyTarget.sol';

contract SyncSwapRouter is ISyncSwapRouter {
    using SafeMath for uint;

    address public factory;
    address public WETH;
    address public owner;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'X');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
        owner = msg.sender;
    }

    function() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function _getReservesWithPair(address pair, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (uint reserve0, uint reserve1) = ISyncSwapPair(pair).getReservesSimple();
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // **** RESCUE ****
    function rescueERC20(address token, uint value, address to) external {
        require(msg.sender == owner);
        require(to != address(0));
        TransferHelper.safeTransfer(token, to, value);
    }

    function rescueETH(uint value, address to) external {
        require(msg.sender == owner);
        require(to != address(0));
        TransferHelper.safeTransferETH(to, value);
    }

    // **** PROXY ****
    function stakeProxy(
        address target,
        address token,
        uint256 amount,
        address onBehalf,
        uint deadline
    ) external ensure(deadline) {
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);
        TransferHelper.safeApprove(token, target, amount);
        IProxyTarget(target).stake(amount, onBehalf);
    }

    function depositProxy(
        address target,
        address token,
        uint256 amount,
        address to,
        uint deadline
    ) external ensure(deadline) {
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);
        TransferHelper.safeApprove(token, target, amount);
        IProxyTarget(target).deposit(token, amount, to);
    }

    function swapProxy(
        address target,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address to,
        uint deadline
    ) external ensure(deadline) {
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, target, amountIn);
        IProxyTarget(target).swap(tokenIn, tokenOut, amountIn, to);
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address _factory,
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal returns (address pair, uint amountA, uint amountB) {
        pair = ISyncSwapFactory(_factory).getPair(tokenA, tokenB);
        // create the pair if it doesn't exist yet
        if (pair == address(0)) {
            pair = ISyncSwapFactory(_factory).createPair(tokenA, tokenB);
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            (uint reserveA, uint reserveB) = _getReservesWithPair(pair, tokenA, tokenB);
            if (reserveA == 0 && reserveB == 0) {
                (amountA, amountB) = (amountADesired, amountBDesired);
            } else {
                uint amountBOptimal = _quote(amountADesired, reserveA, reserveB);

                if (amountBOptimal <= amountBDesired) {
                    require(amountBOptimal >= amountBMin, 'B');
                    (amountA, amountB) = (amountADesired, amountBOptimal);
                } else {
                    uint amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                    //assert(amountAOptimal <= amountADesired);
                    require(amountAOptimal >= amountAMin, 'A');
                    (amountA, amountB) = (amountAOptimal, amountBDesired);
                }
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        address pair;
        (pair, amountA, amountB) = _addLiquidity(factory, tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);

        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);

        liquidity = ISyncSwapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        address _WETH = WETH;
        address pair;
        (pair, amountToken, amountETH) = _addLiquidity(
            factory,
            token,
            _WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );

        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);

        IWETH(_WETH).deposit.value(amountETH)();
        assert(IWETH(_WETH).transfer(pair, amountETH));

        liquidity = ISyncSwapPair(pair).mint(to);

        // refund dust eth, if any
        if (msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    // **** REMOVE LIQUIDITY ****
    function _removeLiquidity(
        address pair,
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to
    ) internal returns (uint amountA, uint amountB) {
        ISyncSwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = ISyncSwapPair(pair).burn(to);

        (amountA, amountB) = tokenA < tokenB ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'A');
        require(amountB >= amountBMin, 'B');
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = SyncSwapLibrary.pairFor(factory, tokenA, tokenB);
        (amountA, amountB) = _removeLiquidity(pair, tokenA, tokenB, liquidity, amountAMin, amountBMin, to);
    }

    function _removeLiquidityETH(
        address _WETH,
        address pair,
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to
    ) internal returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = _removeLiquidity(
            pair,
            token,
            _WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this)
        );

        TransferHelper.safeTransfer(token, to, amountToken);

        IWETH(_WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountToken, uint amountETH) {
        address _WETH = WETH;
        address pair = SyncSwapLibrary.pairFor(factory, token, _WETH);
        (amountToken, amountETH) = _removeLiquidityETH(_WETH, pair, token, liquidity, amountTokenMin, amountETHMin, to);
    }

    function removeLiquidityWithPermit2(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, bytes calldata signature
    ) external returns (uint amountA, uint amountB) {
        address pair = SyncSwapLibrary.pairFor(factory, tokenA, tokenB);

        { // scope to avoid stack too deep errors
        uint value = approveMax ? uint(-1) : liquidity;
        ISyncSwapPair(pair).permit2(msg.sender, address(this), value, deadline, signature);
        }

        (amountA, amountB) = _removeLiquidity(pair, tokenA, tokenB, liquidity, amountAMin, amountBMin, to);
    }

    function removeLiquidityETHWithPermit2(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, bytes calldata signature
    ) external returns (uint amountToken, uint amountETH) {
        address pair = SyncSwapLibrary.pairFor(factory, token, WETH);

        { // scope to avoid stack too deep errors
        uint value = approveMax ? uint(-1) : liquidity;
        ISyncSwapPair(pair).permit2(msg.sender, address(this), value, deadline, signature);
        }

        (amountToken, amountETH) = _removeLiquidityETH(WETH, pair, token, liquidity, amountTokenMin, amountETHMin, to);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function _removeLiquidityETHSupportingFeeOnTransferTokens(
        address _WETH,
        address pair,
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to
    ) internal returns (uint amountETH) {
        (, amountETH) = _removeLiquidity(
            pair,
            token,
            _WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this)
        );

        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));

        IWETH(_WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountETH) {
        address _WETH = WETH;
        address pair = SyncSwapLibrary.pairFor(factory, token, _WETH);
        amountETH = _removeLiquidityETHSupportingFeeOnTransferTokens(_WETH, pair, token, liquidity, amountTokenMin, amountETHMin, to);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH) {
        address _WETH = WETH;
        address pair = SyncSwapLibrary.pairFor(factory, token, _WETH);

        { // scope to avoid stack too deep errors
        uint value = approveMax ? uint(-1) : liquidity;
        ISyncSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        }

        amountETH = _removeLiquidityETHSupportingFeeOnTransferTokens(
            _WETH, pair, token, liquidity, amountTokenMin, amountETHMin, to
        );
    }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens2(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, bytes calldata signature
    ) external returns (uint amountETH) {
        address _WETH = WETH;
        address pair = SyncSwapLibrary.pairFor(factory, token, _WETH);

        { // scope to avoid stack too deep errors
        uint value = approveMax ? uint(-1) : liquidity;
        ISyncSwapPair(pair).permit2(msg.sender, address(this), value, deadline, signature);
        }

        amountETH = _removeLiquidityETHSupportingFeeOnTransferTokens(
            _WETH, pair, token, liquidity, amountTokenMin, amountETHMin, to
        );
    }

    // **** SWAP ****
    function _swapSimple(address pair, address tokenIn, address tokenOut, uint amountOut, address to) internal {
        if (tokenIn < tokenOut) { // whether input token is `token0`
            ISyncSwapPair(pair).swapFor1(amountOut, to);
        } else {
            ISyncSwapPair(pair).swapFor0(amountOut, to);
        }
    }

    // requires the initial amount to have already been sent to the first pair
    function _swap(
        address _factory,
        address pair,
        uint[] memory amounts,
        address[] memory path,
        address _to
    ) internal {
        uint end = path.length - 1;
        for (uint i; i < end; ++i) {
            (address input, address output) = (path[i], path[i + 1]);
            uint _amountOut = amounts[i + 1];

            if (i < end - 1) {
                address _pair = pair;
                pair = SyncSwapLibrary.pairFor(_factory, output, path[i + 2]);
                _swapSimple(_pair, input, output, _amountOut, pair);
            } else {
                _swapSimple(pair, input, output, _amountOut, _to);
            }
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        address _factory = factory;
        amounts = SyncSwapLibrary.getAmountsOut(_factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'O');

        address tokenIn = path[0];
        address initialPair = SyncSwapLibrary.pairFor(_factory, tokenIn, path[1]);
        TransferHelper.safeTransferFrom(
            tokenIn, msg.sender, initialPair, amounts[0]
        );

        _swap(_factory, initialPair, amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        address _factory = factory;
        amounts = SyncSwapLibrary.getAmountsIn(_factory, amountOut, path);
        uint _amountIn = amounts[0];
        require(_amountIn <= amountInMax, 'E');

        address tokenIn = path[0];
        address initialPair = SyncSwapLibrary.pairFor(_factory, tokenIn, path[1]);
        TransferHelper.safeTransferFrom(
            tokenIn, msg.sender, initialPair, _amountIn
        );

        _swap(_factory, initialPair, amounts, path, to);
    }

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        address tokenIn = path[0];
        address _WETH = WETH;
        require(tokenIn == _WETH, 'P');

        address _factory = factory;
        amounts = SyncSwapLibrary.getAmountsOut(_factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'O');

        uint _amountIn = amounts[0];
        IWETH(_WETH).deposit.value(_amountIn)();
        address initialPair = SyncSwapLibrary.pairFor(_factory, tokenIn, path[1]);
        assert(IWETH(_WETH).transfer(initialPair, _amountIn));

        _swap(_factory, initialPair, amounts, path, to);
    }

    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        address _WETH = WETH;
        require(path[path.length - 1] == _WETH, 'P');

        address _factory = factory;
        amounts = SyncSwapLibrary.getAmountsIn(_factory, amountOut, path);
        uint _amountIn = amounts[0];
        require(_amountIn <= amountInMax, 'E');

        address tokenIn = path[0];
        address initialPair = SyncSwapLibrary.pairFor(_factory, tokenIn, path[1]);
        TransferHelper.safeTransferFrom(
            tokenIn, msg.sender, initialPair, _amountIn
        );
        _swap(_factory, initialPair, amounts, path, address(this));

        uint _amountOut = amounts[amounts.length - 1];
        IWETH(_WETH).withdraw(_amountOut);
        TransferHelper.safeTransferETH(to, _amountOut);
    }

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        address _WETH = WETH;
        require(path[path.length - 1] == _WETH, 'P');

        address _factory = factory;
        amounts = SyncSwapLibrary.getAmountsOut(_factory, amountIn, path);
        uint _amountOut = amounts[amounts.length - 1];
        require(_amountOut >= amountOutMin, 'O');

        address tokenIn = path[0];
        address initialPair = SyncSwapLibrary.pairFor(_factory, tokenIn, path[1]);
        TransferHelper.safeTransferFrom(
            tokenIn, msg.sender, initialPair, amounts[0]
        );
        _swap(_factory, initialPair, amounts, path, address(this));

        IWETH(_WETH).withdraw(_amountOut);
        TransferHelper.safeTransferETH(to, _amountOut);
    }

    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        address tokenIn = path[0];
        address _WETH = WETH;
        require(tokenIn == _WETH, 'P');

        address _factory = factory;
        amounts = SyncSwapLibrary.getAmountsIn(_factory, amountOut, path);
        uint _amountIn = amounts[0];
        require(_amountIn <= msg.value, 'E');

        IWETH(_WETH).deposit.value(_amountIn)();
        address initialPair = SyncSwapLibrary.pairFor(_factory, tokenIn, path[1]);
        assert(IWETH(_WETH).transfer(initialPair, _amountIn));

        _swap(_factory, initialPair, amounts, path, to);

        // refund dust eth, if any
        if (msg.value > _amountIn) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - _amountIn);
        }
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(
        address _factory,
        address pair,
        address[] memory path,
        address _to
    ) internal {
        for (uint i; i < path.length - 1; ++i) {
            (address input, address output) = (path[i], path[i + 1]);

            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1) = ISyncSwapPair(pair).getReservesSimple();
            (uint reserveInput, uint reserveOutput) = input < output ? (reserve0, reserve1) : (reserve1, reserve0);
            uint amountInput = IERC20(input).balanceOf(pair).sub(reserveInput);
            amountOutput = SyncSwapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput, ISyncSwapPair(pair).getSwapFee());
            }

            if (i < path.length - 2) {
                address _pair = pair;
                pair = SyncSwapLibrary.pairFor(_factory, output, path[i + 2]);
                _swapSimple(_pair, input, output, amountOutput, pair);
            } else {
                _swapSimple(pair, input, output, amountOutput, _to);
            }
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) {
        address tokenIn = path[0];
        address _factory = factory;
        address initialPair = SyncSwapLibrary.pairFor(_factory, tokenIn, path[1]);
        TransferHelper.safeTransferFrom(
            tokenIn, msg.sender, initialPair, amountIn
        );

        address tokenOut = path[path.length - 1];
        uint balanceBefore = IERC20(tokenOut).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(_factory, initialPair, path, to);

        require(
            IERC20(tokenOut).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'O'
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        payable
        ensure(deadline)
    {
        address tokenIn = path[0];
        address _WETH = WETH;
        require(tokenIn == _WETH, 'P');

        uint amountIn = msg.value;
        IWETH(_WETH).deposit.value(amountIn)();
        address _factory = factory;
        address initialPair = SyncSwapLibrary.pairFor(_factory, tokenIn, path[1]);
        assert(IWETH(_WETH).transfer(initialPair, amountIn));

        address tokenOut = path[path.length - 1];
        uint balanceBefore = IERC20(tokenOut).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(_factory, initialPair, path, to);

        require(
            IERC20(tokenOut).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'O'
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        ensure(deadline)
    {
        address _WETH = WETH;
        require(path[path.length - 1] == _WETH, 'P');

        address tokenIn = path[0];
        address _factory = factory;
        address initialPair = SyncSwapLibrary.pairFor(_factory, tokenIn, path[1]);
        TransferHelper.safeTransferFrom(
            tokenIn, msg.sender, initialPair, amountIn
        );

        _swapSupportingFeeOnTransferTokens(_factory, initialPair, path, address(this));
        uint _amountOut = IERC20(_WETH).balanceOf(address(this));
        require(_amountOut >= amountOutMin, 'O');

        IWETH(_WETH).withdraw(_amountOut);
        TransferHelper.safeTransferETH(to, _amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure returns (uint amountB) {
        return SyncSwapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint swapFee)
        public
        pure
        returns (uint amountOut)
    {
        return SyncSwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut, swapFee);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint swapFee)
        public
        pure
        returns (uint amountIn)
    {
        return SyncSwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut, swapFee);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        returns (uint[] memory amounts)
    {
        return SyncSwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        returns (uint[] memory amounts)
    {
        return SyncSwapLibrary.getAmountsIn(factory, amountOut, path);
    }
}
