// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Interface for UniswapV2 Router
interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        bool ifmint
    ) external returns (uint256[] memory amounts);

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountOut);

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountIn);
}

// Interface for UniswapV2 Pair (for price fetching)
interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract ArbitrageBot is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    struct SwapParams {
        uint256 maxTokenIn;
        uint256 minTokenOut;
        uint256 reserveTokenIn;
        uint256 reserveTokenOut;
        uint256 reserveTokenInSell;
        uint256 reserveTokenOutSell;
    }

    address public immutable WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public immutable DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address[] public exchanges; // List of WETH/DAI pair addresses
    address[] public routers; // List of router addresses for each exchange

    // Router addresses (mainnet)
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant SHEBASWAP_ROUTER = 0x03f7724180AA6b939894B5Ca4314783B0b36b329;
    address public constant SAKESWAP_ROUTER = 0x9C578b573EdE001b95d51a55A3FAfb45f5608b1f;
    address public constant CROSWAP_ROUTER = 0xCeB90E4C17d626BE0fACd78b79c9c87d7ca181b3;

    // Constants for slippage protection
    uint256 public constant SLIPPAGE_TOLERANCE = 20; // 0.2% slippage tolerance

    // Events
    event ArbitrageExecuted(address indexed exchangeBuy, address indexed exchangeSell, uint256 amountIn);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // Initialize exchanges (WETH/DAI pair addresses)
        exchanges = [
            0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11, // UniswapV2
            0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f, // SushiSwap
            0x8faf958E36c6970497386118030e6297fFf8d275, // ShebaSwap
            0x2ad95483ac838E2884563aD278e933fba96Bc242, // SakeSwap
            0x60A26d69263eF43e9a68964bA141263F19D71D51 // CroSwap
        ];

        // Initialize routers (corresponding to each exchange)
        routers = [
            UNISWAP_ROUTER, // UniswapV2
            SUSHISWAP_ROUTER, // SushiSwap
            SHEBASWAP_ROUTER, // ShebaSwap
            SAKESWAP_ROUTER, // SakeSwap
            CROSWAP_ROUTER // CroSwap
        ];
    }

    // Custom errors
    error ZeroWETHReserve();
    error NoProfitableArbitrage();
    error InsufficientBalance();
    error ApprovalFailed();
    error InvalidToken();
    error TransferFailed();
    error ExchangeNotFound();

    // ============ View Functions ============

    /// @notice Get price of 1 WETH in DAI from a given exchange pair
    function getPrice(address pair) public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();

        (uint256 reserveWETH, uint256 reserveDAI) = token0 == WETH ? (reserve0, reserve1) : (reserve1, reserve0);

        if (reserveWETH == 0) revert ZeroWETHReserve();
        return (reserveDAI * 1e18) / reserveWETH;
    }

    /// @notice Find arbitrage opportunity for DAI profit (DAI -> WETH -> DAI)
    function findArbitrageDAI()
        public
        view
        returns (address exchangeBuy, address exchangeSell, uint256 priceBuy, uint256 priceSell)
    {
        uint256[] memory prices = new uint256[](exchanges.length);
        for (uint256 i = 0; i < exchanges.length; i++) {
            prices[i] = getPrice(exchanges[i]);
        }

        uint256 bestBuyPrice = type(uint256).max;
        uint256 bestSellPrice = 0;

        for (uint256 i = 0; i < prices.length; i++) {
            uint256 price = prices[i];
            if (price < bestBuyPrice) {
                bestBuyPrice = price;
                exchangeBuy = exchanges[i];
            }
            if (price > bestSellPrice) {
                bestSellPrice = price;
                exchangeSell = exchanges[i];
            }
        }
        uint256 slippageAmount = (bestBuyPrice * SLIPPAGE_TOLERANCE) / 10000;
        uint256 minSellPrice = bestBuyPrice + slippageAmount;
        if (bestSellPrice <= minSellPrice) revert NoProfitableArbitrage();

        return (exchangeBuy, exchangeSell, bestBuyPrice, bestSellPrice);
    }

    /// @notice Find arbitrage opportunity for WETH profit (WETH -> DAI -> WETH)
    function findArbitrageWETH()
        public
        view
        returns (address exchangeBuy, address exchangeSell, uint256 priceBuy, uint256 priceSell)
    {
        uint256[] memory prices = new uint256[](exchanges.length);
        for (uint256 i = 0; i < exchanges.length; i++) {
            prices[i] = getPrice(exchanges[i]);
        }

        uint256 bestBuyPrice = 0;
        uint256 bestSellPrice = type(uint256).max;

        for (uint256 i = 0; i < prices.length; i++) {
            uint256 price = prices[i];
            if (price > bestBuyPrice) {
                bestBuyPrice = price;
                exchangeBuy = exchanges[i];
            }
            if (price < bestSellPrice) {
                bestSellPrice = price;
                exchangeSell = exchanges[i];
            }
        }
        uint256 slippageAmount = (bestSellPrice * SLIPPAGE_TOLERANCE) / 10000;
        uint256 maxBuyPrice = bestSellPrice + slippageAmount;
        if (bestBuyPrice <= maxBuyPrice) revert NoProfitableArbitrage();

        return (exchangeBuy, exchangeSell, bestBuyPrice, bestSellPrice);
    }

    // ============ External Functions ============

    /// @notice Execute arbitrage trade to profit in DAI (DAI -> WETH -> DAI)
    /// @param amountDAI Amount of DAI to use as input
    function executeArbitrageDAI(uint256 amountDAI) external onlyOwner nonReentrant whenNotPaused {
        // Find arbitrage opportunity
        (address exchangeBuy, address exchangeSell, uint256 priceBuy, uint256 priceSell) = findArbitrageDAI();
        address routerBuy = routers[_getExchangeIndex(exchangeBuy)];
        address routerSell = routers[_getExchangeIndex(exchangeSell)];

        // Log initial balances
        uint256 initialBalance = IERC20(DAI).balanceOf(address(this));

        // Execute the arbitrage swaps
        _executeSwapsDAI(exchangeBuy, exchangeSell, routerBuy, routerSell, amountDAI, initialBalance);

        emit ArbitrageExecuted(exchangeBuy, exchangeSell, amountDAI);
    }

    /// @notice Execute arbitrage trade to profit in WETH (WETH -> DAI -> WETH)
    /// @param amountWETH Amount of WETH to use as input
    function executeArbitrageWETH(uint256 amountWETH) external onlyOwner nonReentrant whenNotPaused {
        // Find arbitrage opportunity
        (address exchangeBuy, address exchangeSell, uint256 priceBuy, uint256 priceSell) = findArbitrageWETH();
        address routerBuy = routers[_getExchangeIndex(exchangeBuy)];
        address routerSell = routers[_getExchangeIndex(exchangeSell)];

        // Log initial balances
        uint256 initialBalance = IERC20(WETH).balanceOf(address(this));
        // Execute the arbitrage swaps
        _executeSwapsWETH(exchangeBuy, exchangeSell, routerBuy, routerSell, amountWETH, initialBalance);

        emit ArbitrageExecuted(exchangeBuy, exchangeSell, amountWETH);
    }

    /// @notice Deposit tokens to the contract
    function depositTokens(address token, uint256 amount) external whenNotPaused {
        if (token != WETH && token != DAI) revert InvalidToken();
        if (!IERC20(token).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
    }

    /// @notice Withdraw tokens from the contract
    function withdrawTokens(address token, uint256 amount) external onlyOwner nonReentrant {
        if (token != WETH && token != DAI) revert InvalidToken();
        if (!IERC20(token).transfer(msg.sender, amount)) revert TransferFailed();
    }

    /// @notice Emergency stop to withdraw all tokens
    function emergencyWithdraw() external onlyOwner nonReentrant {
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        uint256 daiBalance = IERC20(DAI).balanceOf(address(this));

        if (wethBalance > 0) {
            IERC20(WETH).transfer(msg.sender, wethBalance);
        }
        if (daiBalance > 0) {
            IERC20(DAI).transfer(msg.sender, daiBalance);
        }
    }

    /// @notice Pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ Internal Functions ============

    /// @notice Get exchange index for a given exchange address
    function _getExchangeIndex(address exchange) internal view returns (uint256) {
        for (uint256 i = 0; i < exchanges.length; i++) {
            if (exchanges[i] == exchange) return i;
        }
        revert ExchangeNotFound();
    }

    /// @notice Internal function to execute swaps for DAI profit (DAI -> WETH -> DAI)
    function _executeSwapsDAI(
        address exchangeBuy,
        address exchangeSell,
        address routerBuy,
        address routerSell,
        uint256 amountDAI,
        uint256 initialBalance
    ) internal {
        SwapParams memory params;

        // Buy: DAI -> WETH
        (uint112 reserve0Buy, uint112 reserve1Buy,) = IUniswapV2Pair(exchangeBuy).getReserves();
        (params.reserveTokenIn, params.reserveTokenOut) =
            IUniswapV2Pair(exchangeBuy).token0() == DAI ? (reserve0Buy, reserve1Buy) : (reserve1Buy, reserve0Buy);

        // Sell: WETH -> DAI
        (uint112 reserve0Sell, uint112 reserve1Sell,) = IUniswapV2Pair(exchangeSell).getReserves();
        (params.reserveTokenInSell, params.reserveTokenOutSell) =
            IUniswapV2Pair(exchangeSell).token0() == WETH ? (reserve0Sell, reserve1Sell) : (reserve1Sell, reserve0Sell);

        // Calculate swap amounts
        uint256 amountWETHOut =
            IUniswapV2Router02(routerBuy).getAmountOut(amountDAI, params.reserveTokenIn, params.reserveTokenOut);
        params.maxTokenIn = amountDAI;
        params.minTokenOut = IUniswapV2Router02(routerSell).getAmountOut(
            amountWETHOut, params.reserveTokenInSell, params.reserveTokenOutSell
        );
        params.minTokenOut = params.minTokenOut * (10000 - SLIPPAGE_TOLERANCE) / 10000;

        // Validate and approve
        if (IERC20(DAI).balanceOf(address(this)) < params.maxTokenIn) revert InsufficientBalance();
        if (!IERC20(DAI).approve(routerBuy, params.maxTokenIn)) revert ApprovalFailed();
        if (!IERC20(WETH).approve(routerSell, amountWETHOut)) revert ApprovalFailed();

        // Execute swaps
        _executeBuySwap(routerBuy, params.maxTokenIn, amountWETHOut, DAI, WETH);
        _executeSellSwap(routerSell, amountWETHOut, params.minTokenOut, WETH, DAI);
    }

    /// @notice Internal function to execute swaps for WETH profit (WETH -> DAI -> WETH)
    function _executeSwapsWETH(
        address exchangeBuy,
        address exchangeSell,
        address routerBuy,
        address routerSell,
        uint256 amountWETH,
        uint256 initialBalance
    ) internal {
        SwapParams memory params;

        // Buy: WETH -> DAI
        (uint112 reserve0Buy, uint112 reserve1Buy,) = IUniswapV2Pair(exchangeBuy).getReserves();
        (params.reserveTokenIn, params.reserveTokenOut) =
            IUniswapV2Pair(exchangeBuy).token0() == WETH ? (reserve0Buy, reserve1Buy) : (reserve1Buy, reserve0Buy);

        // Sell: DAI -> WETH
        (uint112 reserve0Sell, uint112 reserve1Sell,) = IUniswapV2Pair(exchangeSell).getReserves();
        (params.reserveTokenInSell, params.reserveTokenOutSell) =
            IUniswapV2Pair(exchangeSell).token0() == DAI ? (reserve0Sell, reserve1Sell) : (reserve1Sell, reserve0Sell);

        // Calculate swap amounts
        uint256 amountDAIOut =
            IUniswapV2Router02(routerBuy).getAmountOut(amountWETH, params.reserveTokenIn, params.reserveTokenOut);
        params.maxTokenIn = amountWETH;
        params.minTokenOut = IUniswapV2Router02(routerSell).getAmountOut(
            amountDAIOut, params.reserveTokenInSell, params.reserveTokenOutSell
        );
        params.minTokenOut = params.minTokenOut * (10000 - SLIPPAGE_TOLERANCE) / 10000;

        // Validate and approve
        if (IERC20(WETH).balanceOf(address(this)) < params.maxTokenIn) revert InsufficientBalance();
        if (!IERC20(WETH).approve(routerBuy, params.maxTokenIn)) revert ApprovalFailed();
        if (!IERC20(DAI).approve(routerSell, amountDAIOut)) revert ApprovalFailed();

        // Execute swaps
        _executeBuySwap(routerBuy, params.maxTokenIn, amountDAIOut, WETH, DAI);
        _executeSellSwap(routerSell, amountDAIOut, params.minTokenOut, DAI, WETH);
    }

    // ============ Private Functions ============

    function _executeBuySwap(address router, uint256 amountIn, uint256 amountOutMin, address tokenIn, address tokenOut)
        private
    {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        if (router == SAKESWAP_ROUTER) {
            IUniswapV2Router02(router).swapExactTokensForTokens(
                amountIn, amountOutMin, path, address(this), block.timestamp + 300, false
            );
        } else {
            IUniswapV2Router02(router).swapExactTokensForTokens(
                amountIn, amountOutMin, path, address(this), block.timestamp + 300
            );
        }
    }

    function _executeSellSwap(address router, uint256 amountIn, uint256 amountOutMin, address tokenIn, address tokenOut)
        private
    {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        if (router == SAKESWAP_ROUTER) {
            IUniswapV2Router02(router).swapExactTokensForTokens(
                amountIn, amountOutMin, path, address(this), block.timestamp + 300, false
            );
        } else {
            IUniswapV2Router02(router).swapExactTokensForTokens(
                amountIn, amountOutMin, path, address(this), block.timestamp + 300
            );
        }
    }

    /// @notice Authorize contract upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Receive ETH (for WETH unwrapping if needed)
    receive() external payable {}
}
