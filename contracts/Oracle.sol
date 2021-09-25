pragma solidity =0.6.6;

import "./libs/SafeMath.sol";
import "./libs/FixedPoint.sol";
import "./libs/OracleLibrary.sol";

contract Oracle {
    using FixedPoint for *;
    using SafeMath for uint256;

    struct Observation {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    address public immutable factory;
    address public priceUpdater;
    uint256 public constant CYCLE = 15 minutes;

    bytes32 INIT_CODE_HASH;

    // mapping from pair address to a list of price observations of that pair
    mapping(address => Observation) public pairObservations;

    constructor(
        address factory_,
        bytes32 INIT_CODE_HASH_,
        address priceUpdater_
    ) public {
        factory = factory_;
        INIT_CODE_HASH = INIT_CODE_HASH_;
        priceUpdater = priceUpdater_;
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

    function update(address tokenA, address tokenB) external {
        require(
            msg.sender == priceUpdater,
            "BecoSwapOracle: Price can update only price updater address"
        );
        address pair = pairFor(tokenA, tokenB);

        Observation storage observation = pairObservations[pair];
        uint256 timeElapsed = block.timestamp - observation.timestamp;
        require(timeElapsed >= CYCLE, "BecoSwapOracle: PERIOD_NOT_ELAPSED");
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,

        ) = BecoSwapOracleLibrary.currentCumulativePrices(pair);
        observation.timestamp = block.timestamp;
        observation.price0Cumulative = price0Cumulative;
        observation.price1Cumulative = price1Cumulative;
    }

    function computeAmountOut(
        uint256 priceCumulativeStart,
        uint256 priceCumulativeEnd,
        uint256 timeElapsed,
        uint256 amountIn
    ) private pure returns (uint256 amountOut) {
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
        );
        amountOut = priceAverage.mul(amountIn).decode144();
    }

    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external view returns (uint256 amountOut) {
        address pair = pairFor(tokenIn, tokenOut);
        Observation storage observation = pairObservations[pair];

        if (
            pairObservations[pair].price0Cumulative == 0 ||
            pairObservations[pair].price1Cumulative == 0
        ) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - observation.timestamp;
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,

        ) = BecoSwapOracleLibrary.currentCumulativePrices(pair);
        (address token0, ) = sortTokens(tokenIn, tokenOut);

        if (token0 == tokenIn) {
            return
                computeAmountOut(
                    observation.price0Cumulative,
                    price0Cumulative,
                    timeElapsed,
                    amountIn
                );
        } else {
            return
                computeAmountOut(
                    observation.price1Cumulative,
                    price1Cumulative,
                    timeElapsed,
                    amountIn
                );
        }
    }
}
