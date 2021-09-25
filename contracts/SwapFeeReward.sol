pragma solidity 0.6.6;

import "./Ownable.sol";
import "./libs/SafeMath.sol";
import "./libs/EnumerableSet.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";

interface IMasterChef {
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _referrer
    ) external;
}

interface IBecoSwapFactory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function INIT_CODE_HASH() external pure returns (bytes32);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;

    function setDevFee(address pair, uint8 _devFee) external;

    function setSwapFee(address pair, uint32 swapFee) external;
}

interface IBecoSwapPair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function swapFee() external view returns (uint32);

    function devFee() external view returns (uint32);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to)
        external
        returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;

    function setSwapFee(uint32) external;

    function setDevFee(uint32) external;
}

contract SwapFeeReward is Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _whitelist;

    address public factory;
    address public router;
    bytes32 public INIT_CODE_HASH;
    IOracle public oracle;
    address public targetToken;
    IERC20 public beco;
    uint256 public poolId;

    mapping(address => uint256) public nonces;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public pairOfPid;

    IMasterChef public masterChef;

    struct PairsList {
        address pair;
        uint256 percentReward;
        bool enabled;
    }
    PairsList[] public pairsList;

    event Withdraw(address userAddress, uint256 amount);
    event Rewarded(
        address account,
        address input,
        address output,
        uint256 amount,
        uint256 quantity
    );

    modifier onlyRouter() {
        require(
            msg.sender == router,
            "SwapFeeReward: caller is not the router"
        );
        _;
    }

    constructor(
        address _factory,
        address _router,
        bytes32 _INIT_CODE_HASH,
        address _beco,
        IOracle _Oracle,
        address _targetToken,
        address _masterChef
    ) public {
        factory = _factory;
        router = _router;
        INIT_CODE_HASH = _INIT_CODE_HASH;
        beco = IERC20(_beco);
        oracle = _Oracle;
        targetToken = _targetToken;
        masterChef = IMasterChef(_masterChef);

    }

    function deposit(uint256 _poolId) public onlyOwner {
        poolId = _poolId;
        masterChef.deposit(_poolId, 1 ether, address(0x0));
    }

    function sortTokens(address tokenA, address tokenB)
        public
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "BecoSwapFactory: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "BecoSwapFactory: ZERO_ADDRESS");
    }

    function pairFor(address tokenA, address tokenB)
        public
        view
        returns (address pair)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                        INIT_CODE_HASH
                    )
                )
            )
        );
    }

    function getSwapFee(address tokenA, address tokenB)
        internal
        view
        returns (uint256 swapFee)
    {
        swapFee = uint256(1000).sub(
            IBecoSwapPair(pairFor(tokenA, tokenB)).swapFee()
        );
    }


    function checkPairExist(address tokenA, address tokenB)
        public
        view
        returns (bool)
    {
        address pair = pairFor(tokenA, tokenB);
        PairsList storage pool = pairsList[pairOfPid[pair]];
        if (pool.pair != pair) {
            return false;
        }
        return true;
    }

    function swap(
        address account,
        address input,
        address output,
        uint256 amount
    ) public onlyRouter returns (bool) {
        if (!isWhitelist(input) || !isWhitelist(output)) {
            return false;
        }
        address pair = pairFor(input, output);
        PairsList storage pool = pairsList[pairOfPid[pair]];
        if (pool.pair != pair || pool.enabled == false) {
            return false;
        }
        uint256 pairFee = getSwapFee(input, output);
        uint256 fee = amount.div(pairFee);
        uint256 quantity = getQuantity(output, fee, targetToken);
        quantity = quantity.mul(pool.percentReward).div(100);
        _balances[account] = _balances[account].add(quantity);
        emit Rewarded(account, input, output, amount, quantity);
        return true;
    }

    function rewardBalance(address account) public view returns (uint256) {
        return _balances[account];
    }

    function withdraw() public returns (bool) {
        uint256 balance = _balances[msg.sender];
        if (balance > 0) {
            if (beco.balanceOf(address(this)) < balance) {
                masterChef.deposit(poolId, 0, address(0x0));
            }
            safeBecoTransfer(msg.sender, balance);
            _balances[msg.sender] = _balances[msg.sender].sub(balance);
            emit Withdraw(msg.sender, balance);
            return true;
        }
        return false;
    }
    
     // Safe beco transfer function, just in case if rounding error causes pool to not have enough BECO.
    function safeBecoTransfer(address _to, uint256 _amount) internal {
        uint256 becoBal = beco.balanceOf(address(this));
        if (_amount > becoBal) {
            beco.transfer(_to, becoBal);
        } else {
            beco.transfer(_to, _amount);
        }
    }

    function getQuantity(
        address outputToken,
        uint256 outputAmount,
        address anchorToken
    ) public view returns (uint256) {
        uint256 quantity = 0;
        if (outputToken == anchorToken) {
            quantity = outputAmount;
        } else if (
            IBecoSwapFactory(factory).getPair(outputToken, anchorToken) !=
            address(0) &&
            checkPairExist(outputToken, anchorToken)
        ) {
            quantity = IOracle(oracle).consult(
                outputToken,
                outputAmount,
                anchorToken
            );
        } else {
            uint256 length = getWhitelistLength();
            for (uint256 index = 0; index < length; index++) {
                address intermediate = getWhitelist(index);
                if (
                    IBecoSwapFactory(factory).getPair(outputToken, intermediate) !=
                    address(0) &&
                    IBecoSwapFactory(factory).getPair(intermediate, anchorToken) !=
                    address(0) &&
                    checkPairExist(intermediate, anchorToken)
                ) {
                    uint256 interQuantity = IOracle(oracle).consult(
                        outputToken,
                        outputAmount,
                        intermediate
                    );
                    quantity = IOracle(oracle).consult(
                        intermediate,
                        interQuantity,
                        anchorToken
                    );
                    break;
                }
            }
        }
        return quantity;
    }

    function addWhitelist(address _addToken) public onlyOwner returns (bool) {
        require(
            _addToken != address(0),
            "SwapMining: token is the zero address"
        );
        return EnumerableSet.add(_whitelist, _addToken);
    }

    function delWhitelist(address _delToken) public onlyOwner returns (bool) {
        require(
            _delToken != address(0),
            "SwapMining: token is the zero address"
        );
        return EnumerableSet.remove(_whitelist, _delToken);
    }

    function getWhitelistLength() public view returns (uint256) {
        return EnumerableSet.length(_whitelist);
    }

    function isWhitelist(address _token) public view returns (bool) {
        return EnumerableSet.contains(_whitelist, _token);
    }

    function getWhitelist(uint256 _index) public view returns (address) {
        require(
            _index <= getWhitelistLength() - 1,
            "SwapMining: index out of bounds"
        );
        return EnumerableSet.at(_whitelist, _index);
    }

    function setRouter(address newRouter) public onlyOwner {
        require(
            newRouter != address(0),
            "SwapMining: new router is the zero address"
        );
        router = newRouter;
    }

    function setOracle(IOracle _oracle) public onlyOwner {
        require(
            address(_oracle) != address(0),
            "SwapMining: new oracle is the zero address"
        );
        oracle = _oracle;
    }

    function setFactory(address _factory) public onlyOwner {
        require(
            _factory != address(0),
            "SwapMining: new factory is the zero address"
        );
        factory = _factory;
    }

    function setInitCodeHash(bytes32 _INIT_CODE_HASH) public onlyOwner {
        INIT_CODE_HASH = _INIT_CODE_HASH;
    }

    function pairsListLength() public view returns (uint256) {
        return pairsList.length;
    }

    function addPair(uint256 _percentReward, address _pair) public onlyOwner {
        require(_pair != address(0), "_pair is the zero address");
        pairsList.push(
            PairsList({
                pair: _pair,
                percentReward: _percentReward,
                enabled: true
            })
        );
        pairOfPid[_pair] = pairsListLength() - 1;
    }

    function setPair(uint256 _pid, uint256 _percentReward) public onlyOwner {
        pairsList[_pid].percentReward = _percentReward;
    }

    function setPairEnabled(uint256 _pid, bool _enabled) public onlyOwner {
        pairsList[_pid].enabled = _enabled;
    }
}
