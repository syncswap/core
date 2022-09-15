pragma solidity =0.5.17;

import './interfaces/ISyncSwapERC20.sol';
import './libraries/SafeMath.sol';
import './libraries/SignatureChecker.sol';

contract SyncSwapERC20 is ISyncSwapERC20 {
    using SafeMath for uint;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    bytes32 private DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    constructor() public {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,

                // keccak256(bytes('SyncSwap SLP Token')),
                0xf217daa25f50651e072a913278858c2bfea9576ad0ab9d0a2cd31744cea22cbe,

                // keccak256(bytes('1')),
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6,

                280, // SyncSwap - hardcode chain id
                address(this)
            )
        );
    }

    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external returns (bool) {
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (from != msg.sender) {
            uint _allowance = allowance[from][msg.sender];
            if (_allowance != uint(-1)) {
                allowance[from][msg.sender] = _allowance.sub(value);
            }
        }
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'X');
        bytes32 hash = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(hash, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'S');
        _approve(owner, spender, value);
    }

    function permit2(address owner, address spender, uint value, uint deadline, bytes calldata signature) external {
        require(deadline >= block.timestamp, 'X');
        bytes32 hash = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        require(SignatureChecker.checkSignature(owner, hash, signature), 'S');
        _approve(owner, spender, value);
    }
}
