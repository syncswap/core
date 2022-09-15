pragma solidity =0.5.17;

import '../SyncSwapERC20.sol';

contract PairERC20 is SyncSwapERC20 {
    constructor(uint _totalSupply) public {
        _mint(msg.sender, _totalSupply);
    }
}
