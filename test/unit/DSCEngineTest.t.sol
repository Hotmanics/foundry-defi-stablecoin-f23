// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzepplein/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 public constant AMOUNT_TO_MINT = 0.01 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 1 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    // function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
    //     tokenAddresses.push(weth);
    //     tokenAddresses.push(wbtc);
    //     priceFeedAddresses.push(btcUsdPriceFeed);

    //     vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
    //     new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    // }

    // function testGetUsdValue() external {
    //     uint256 ethAmount = 15e18;
    //     uint256 expectedUsd = 30000e18;
    //     uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
    //     assertEq(expectedUsd, actualUsd);
    // }

    // function testGetTokenAmountFromUsd() external {
    //     uint256 usdAmount = 100 ether;
    //     uint256 expectedWeth = 0.05 ether;
    //     uint256 actualWeth = engine.getTokenAmountFromUSD(weth, usdAmount);
    //     assertEq(expectedWeth, actualWeth);
    // }

    // function testRevertsWithUnapprovedCollateral() external {
    //     ERC20Mock token = new ERC20Mock();
    //     token.mint(USER, AMOUNT_COLLATERAL);
    //     vm.startPrank(USER);

    //     vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
    //     engine.depositCollateral(address(token), AMOUNT_COLLATERAL);
    //     vm.stopPrank();
    // }

    modifier mintCollateralApproveDscEngineAndDepositCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    modifier mintAndDepositCollateral(uint256 mintAmount, uint256 depositAmount) {
        ERC20Mock(weth).mint(USER, mintAmount);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), depositAmount);
        engine.depositCollateral(weth, depositAmount);
        vm.stopPrank();
        _;
    }

    /////////////////
    // Depositing
    /////////////////

    function testDepositCollateral() public mintAndDepositCollateral(AMOUNT_COLLATERAL, AMOUNT_COLLATERAL) {
        assertEq(AMOUNT_COLLATERAL, engine.getCollateralDeposited(USER, weth));
    }

    function testRevertOnDepositOfZeroTokens() public {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertOnDepositOnUndocumentedToken() public {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(0xDD13e55209FD76AfE204DBdA4007C227904f0A82, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /////////////////
    // Minting
    /////////////////

    function testMintDsc() public mintAndDepositCollateral(AMOUNT_COLLATERAL, AMOUNT_COLLATERAL) {
        vm.startPrank(USER);

        engine.mintDsc(AMOUNT_TO_MINT);

        vm.stopPrank();

        assertEq(AMOUNT_TO_MINT, engine.getDscMinted(USER));
    }

    function testRevertOnMintDscWithBrokenHealth() public {
        vm.startPrank(USER);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        engine.mintDsc(AMOUNT_TO_MINT);

        vm.stopPrank();
    }

    function testRevertOnMintDscWithZeroAmount() public {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);

        vm.stopPrank();
    }

    /////////////////
    // Deposit & Mint
    /////////////////
    function testDepositCollateralAndMintDsc() public {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    /////////////////
    // Redeeming
    /////////////////
    function testRedeemCollateral() public mintAndDepositCollateral(AMOUNT_COLLATERAL, AMOUNT_COLLATERAL) {
        vm.startPrank(USER);

        engine.mintDsc(AMOUNT_TO_MINT);
        DecentralizedStableCoin(dsc).approve(address(engine), DecentralizedStableCoin(dsc).balanceOf(USER));
        engine.burnDsc(AMOUNT_TO_MINT);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    function testRevertOnRedeemCollateralFromBreakingHealthFactor()
        public
        mintAndDepositCollateral(AMOUNT_COLLATERAL, AMOUNT_COLLATERAL)
    {
        vm.startPrank(USER);

        engine.mintDsc(AMOUNT_TO_MINT);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /////////////////
    // Burning
    /////////////////

    function testBurn() public mintAndDepositCollateral(AMOUNT_COLLATERAL, AMOUNT_COLLATERAL) {
        vm.startPrank(USER);

        engine.mintDsc(AMOUNT_TO_MINT);
        DecentralizedStableCoin(dsc).approve(address(engine), DecentralizedStableCoin(dsc).balanceOf(USER));
        engine.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRevertBurnIfZeroTokens() public mintAndDepositCollateral(AMOUNT_COLLATERAL, AMOUNT_COLLATERAL) {
        vm.startPrank(USER);

        engine.mintDsc(AMOUNT_TO_MINT);
        DecentralizedStableCoin(dsc).approve(address(engine), DecentralizedStableCoin(dsc).balanceOf(USER));
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }
}
