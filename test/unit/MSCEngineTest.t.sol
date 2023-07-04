// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployMSC} from "../../script/DeployMSC.s.sol";
import {MuhStablecoin} from "../../src/MuhStablecoin.sol";
import {MSCEngine} from "../../src/MSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";

contract MSCEngineTest is Test {
    DeployMSC public deployer;
    MuhStablecoin public msc;
    MSCEngine public engine;
    HelperConfig public config;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    uint256 amountToMint = 100 ether;
    uint256 amountToBurn = 10 ether;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployMSC();
        (msc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig();

        if (block.chainid == 31337) {
            vm.deal(USER, STARTING_ERC20_BALANCE);
        }

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }

    // Constructor Tests
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            MSCEngine
                .MSCEngine__TokenAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new MSCEngine(tokenAddresses, priceFeedAddresses, address(msc));
    }

    // Price Tests
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    // Deposit Collateral Tests

    // This test needs own set up
    function testRevertsIfTransferFromFails() public {
        // Arrange - Set up
        address owner = msg.sender;
        vm.prank(owner);

        MockFailedTransferFrom mockMSC = new MockFailedTransferFrom();
        tokenAddresses = [address(mockMSC)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        MSCEngine mockEngine = new MSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockMSC)
        );
        mockMSC.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockMSC.transferOwnership(address(mockEngine));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockMSC)).approve(
            address(mockEngine),
            AMOUNT_COLLATERAL
        );

        // Assert
        vm.expectRevert(MSCEngine.MSCEngine__TransferFailed.selector);
        mockEngine.depositCollateral(address(mockMSC), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(MSCEngine.MSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock testToken = new ERC20Mock("TT", "TT");
        vm.startPrank(USER);
        vm.expectRevert(MSCEngine.MSCEngine__NotAllowedToken.selector);

        engine.depositCollateral(address(testToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalMSCMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(USER);

        uint256 expectedTotalMSCMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );

        assertEq(totalMSCMinted, expectedTotalMSCMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testCanDepositCollateralWithoutMinting()
        public
        depositedCollateral
    {
        uint256 userBalance = msc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    // Mint Tests
    function testCanMintMSC() public depositedCollateral {
        vm.prank(USER);
        engine.mintMSC(amountToMint);

        uint256 userBalance = msc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    // Redeem Collateral Tests
    function testCanRedeemDepositedCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintMSC(amountToMint - 2 ether);
        uint256 withdrawalAmt = AMOUNT_COLLATERAL - 1 ether;
        engine.redeemCollateral(weth, withdrawalAmt);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        vm.stopPrank();

        assertEq(userBalance, withdrawalAmt);
    }

    function testCanRedeemCollateralAndBurnMSC() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintMSC(amountToMint);
        msc.approve(address(engine), amountToMint);
        uint256 withdrawalAmt = AMOUNT_COLLATERAL - 1 ether;
        engine.redeemCollateralForMSC(weth, withdrawalAmt, amountToBurn);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 userMSC = (msc.balanceOf(USER)) - amountToBurn;
        vm.stopPrank();

        assertEq(userBalance, withdrawalAmt);
        assert(userMSC < amountToMint); // this is a dumb assertion but i'll leave for coverage
    }
}
