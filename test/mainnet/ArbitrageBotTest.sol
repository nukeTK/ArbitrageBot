// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "../../src/ArbitrageBot.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// contract ArbitrageTest is Test {
//     // Test user
//     address user = address(1);
//     address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
//     address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
//     ArbitrageBot bot;

//     // Exchange pairs
//     address constant UNISWAP_V2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
//     address constant SUSHISWAP = 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f;
//     address constant SHEBASWAP = 0x8faf958E36c6970497386118030e6297fFf8d275;
//     address constant SAKESWAP = 0x2ad95483ac838E2884563aD278e933fba96Bc242;
//     address constant CROSWAP = 0x60A26d69263eF43e9a68964bA141263F19D71D51;

//     function setUp() public {
//         // Fork mainnet at a specific block
//         vm.createSelectFork("mainnet");
//         vm.startPrank(user);

//         // Deploy ArbitrageBot implementation and proxy
//         ArbitrageBot implementation = new ArbitrageBot();
//         ERC1967Proxy proxy =
//             new ERC1967Proxy(address(implementation), abi.encodeWithSelector(ArbitrageBot.initialize.selector));
//         bot = ArbitrageBot(payable(address(proxy)));

//         // Give user some initial WETH and DAI
//         vm.deal(user, 100 ether);

//         // Wrap ETH to WETH
//         (bool success,) = WETH.call{value: 50 ether}("");
//         require(success, "WETH wrap failed");

//         // Give user some DAI
//         deal(DAI, user, 100000 * 1e18);

//         vm.stopPrank();
//     }

//     // function test_verifyExchanges() public {
//     //     vm.startPrank(user);
//     //     // Loop through and verify each exchange
//     //     for (uint256 i = 0; i < 5; i++) {
//     //         address exchange = bot.exchanges(i);
//     //         assertNotEq(exchange, address(0), "Exchange should not be zero address");

//     //         // Verify it matches expected exchange addresses
//     //         bool isValidExchange =
//     //             exchange == UNISWAP_V2 ||
//     //             exchange == SUSHISWAP ||
//     //             exchange == SHEBASWAP ||
//     //             exchange == SAKESWAP ||
//     //             exchange == CROSWAP;

//     //     console.log("isValidExchange", isValidExchange);

//     //     vm.stopPrank();
//     //     }
//     // }

//     // function test_findArbitrage() public {
//     //     vm.startPrank(user);
//     //     (address exchangeBuy, address exchangeSell, uint256 priceBuy, uint256 priceSell) = bot.findArbitrage();
//     //     console.log("exchangeBuy", exchangeBuy);
//     //     console.log("exchangeSell", exchangeSell);
//     //     console.log("priceBuy", priceBuy);
//     //     console.log("priceSell", priceSell);
//     //     vm.stopPrank();
//     // }

//     function test_executeArbitrage() public {
//         vm.startPrank(user);
//         // Approve and deposit WETH
//         IERC20(WETH).approve(address(bot), 10 ether);
//         bot.depositTokens(WETH, 10 ether);

//         // Approve and deposit DAI
//         // IERC20(DAI).approve(address(bot), 20000 * 1e18);
//         // bot.depositTokens(DAI, 20000 * 1e18);
//         // console.log("WETH balance", IERC20(WETH).balanceOf(address(bot)));
//         // console.log("DAI balance", IERC20(DAI).balanceOf(address(bot)));
//         // bot.executeArbitrageDAI(20 ether);
//         // console.log("WETH balance", IERC20(WETH).balanceOf(address(bot)));
//         // console.log("DAI balance", IERC20(DAI).balanceOf(address(bot)));
//         // bot.executeArbitrageWETH(0.001 ether);
//         // console.log("WETH balance", IERC20(WETH).balanceOf(address(bot)));
//         // console.log("DAI balance", IERC20(DAI).balanceOf(address(bot)));

//         vm.stopPrank();
//     }
// }
