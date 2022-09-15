pragma solidity =0.5.17;

import './interfaces/ISyncSwapPair.sol';
import './SyncSwapERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/ISyncSwapFactory.sol';
import './interfaces/IUniswapV2Callee.sol';

contract SyncSwapPair is ISyncSwapPair, SyncSwapERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint private constant MINIMUM_LIQUIDITY = 1000;
    bytes4 private constant SELECTOR = 0xa9059cbb; //bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint32 public pairSwapFee = uint32(-1); // use defaultSwapFee from factory

    uint8 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1);
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function getReservesSimple() external view returns (uint112 _reserve0, uint112 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'T');
    }

    constructor() public {
        factory = msg.sender;
    }

    function _getSymbol(address token) private view returns (bool, string memory) {
        // bytes4(keccak256(bytes("symbol()")))
        (bool success, bytes memory returndata) = token.staticcall(abi.encodeWithSelector(0x95d89b41));
        if (success) {
            return (true, abi.decode(returndata, (string)));
        } else {
            return (false, "");
        }
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory); // sufficient check
        token0 = _token0;
        token1 = _token1;

        // try to set symbols for the pair token
        (bool success0, string memory symbol0) = _getSymbol(_token0);
        (bool success1, string memory symbol1) = _getSymbol(_token1);
        if (success0 && success1) {
            bytes memory _symbol = abi.encodePacked(symbol0, "/", symbol1, " SLP");
            name = string(abi.encodePacked("SyncSwap ", _symbol));
            symbol = string(_symbol);
        } else {
            name = "SyncSwap SLP Token";
            symbol = "SLP";
        }
    }

    // called by the factory to set the swapFee
    function setPairSwapFee(uint32 _pairSwapFee) external {
        require(msg.sender == factory); // sufficient check
        pairSwapFee = _pairSwapFee;
    }

    function getSwapFee() public view returns (uint32 swapFee) {
        uint32 _pairSwapFee = pairSwapFee; // gas savings
        swapFee = _pairSwapFee == uint32(-1) ? ISyncSwapFactory(factory).defaultSwapFee() : _pairSwapFee;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1));

        uint32 blockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed != 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/(protocolFeeFactor) of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address _factory = factory; // gas savings
        address feeTo = ISyncSwapFactory(_factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint8 protocolFeeFactor = ISyncSwapFactory(_factory).protocolFeeFactor();
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(protocolFeeFactor - 1).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity != 0) {
                        _mint(feeTo, liquidity);
                    }
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity != 0, 'M');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) {
            kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        }
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 != 0 && amount1 != 0, 'U');

        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) {
            kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        }
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out != 0 || amount1Out != 0, 'O');
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'L');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        //require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');

        if (amount0Out != 0) {
            _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        }
        if (amount1Out != 0) {
            _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        }
        if (data.length != 0) {
            IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        }
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }

        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In != 0 || amount1In != 0, 'I');

        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint32 _swapFee = getSwapFee();
        uint balance0Adjusted = balance0.mul(1e6).sub(amount0In.mul(_swapFee));
        uint balance1Adjusted = balance1.mul(1e6).sub(amount1In.mul(_swapFee));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1e12), 'K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swapFor0(uint amount0Out, address to) external lock {
        require(amount0Out != 0, 'O');
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1); // gas savings
        require(amount0Out < _reserve0, 'L');

        address _token0 = token0;
        _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));

        uint amount1In = balance1 > _reserve1 ? balance1 - _reserve1 : 0;
        require(amount1In != 0, 'I');

        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance1Adjusted = balance1.mul(1e6).sub(amount1In.mul(getSwapFee()));
        require(balance0.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1e6), 'K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, 0, amount1In, amount0Out, 0, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swapFor1(uint amount1Out, address to) external lock {
        require(amount1Out != 0, 'O');
        (uint112 _reserve0, uint112 _reserve1) = (reserve0, reserve1); // gas savings
        require(amount1Out < _reserve1, 'L');

        address _token1 = token1;
        _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));

        uint amount0In = balance0 > _reserve0 ? balance0 - _reserve0 : 0;
        require(amount0In != 0, 'I');

        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0.mul(1e6).sub(amount0In.mul(getSwapFee()));
        require(balance0Adjusted.mul(balance1) >= uint(_reserve0).mul(_reserve1).mul(1e6), 'K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, 0, 0, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
