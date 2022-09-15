pragma solidity =0.5.17;

import './interfaces/ISyncSwapFactory.sol';
import './SyncSwapPair.sol';

contract SyncSwapFactory is ISyncSwapFactory {
    address public feeTo;
    address public feeToSetter;

    uint32 public defaultSwapFee = 3000; // 0.3%, in 1e6 precision
    uint8 public protocolFeeFactor = 5; // 1/5, 20%
    //bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(SyncSwapPair).creationCode));

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'D');

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Z');
        require(getPair[token0][token1] == address(0), 'R'); // single check is sufficient

        bytes memory bytecode = type(SyncSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ISyncSwapPair(pair).initialize(token0, token1);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'F');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'F');
        feeToSetter = _feeToSetter;
    }

    function setProtocolFeeFactor(uint8 _protocolFeeFactor) external {
        require(_protocolFeeFactor > 1, 'V');
        protocolFeeFactor = _protocolFeeFactor;
    }

    function setDefaultSwapFee(uint32 _defaultSwapFee) external {
        require(_defaultSwapFee <= 1e5, 'V'); // maximum 10%
        defaultSwapFee = _defaultSwapFee;
    }

    function setPairSwapFee(address _pair, uint32 _pairSwapFee) external {
        require(_pairSwapFee <= 1e5 || _pairSwapFee == uint32(-1), 'V'); // maximum 10%
        ISyncSwapPair(_pair).setPairSwapFee(_pairSwapFee);
    }
}