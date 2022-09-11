// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import "forge-std/console2.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {RocketPoolBridge} from "../../../bridges/rocketpool/RocketPoolBridge.sol";

import {IRocketStorage} from "../../../interfaces/rocketpool/IRocketStorage.sol";
import {IRocketTokenRETH} from "../../../interfaces/rocketpool/IRocketTokenRETH.sol";
import {IRocketDepositPool} from "../../../interfaces/rocketpool/IRocketDepositPool.sol";
import {IRocketDAOProtocolSettingsDeposit} from "../../../interfaces/rocketpool/IRocketDAOProtocolSettingsDeposit.sol";

contract RocketPoolBridgeTest is BridgeTestBase {
    IRocketStorage private constant rocketStorage = IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);
    IRocketTokenRETH private rocketTokenRETH;
    IRocketDepositPool private rocketDepositPool;
    IRocketDAOProtocolSettingsDeposit private rocketDepositPoolSettings;

    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private rethAsset;

    RocketPoolBridge private bridge;
    uint256 private id;

    constructor() {
        rocketTokenRETH = IRocketTokenRETH(getRETHContractAddress());
        rocketDepositPool = IRocketDepositPool(getDepositPoolContractAddress());
        rocketDepositPoolSettings = IRocketDAOProtocolSettingsDeposit(getDepositPoolSettingsContractAddress());
    }

    function setUp() public {
        bridge = new RocketPoolBridge(address(ROLLUP_PROCESSOR));
        vm.label(address(bridge), "Rocket Pool Bridge");

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 500000);
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedAsset(address(rocketTokenRETH), 1337);

        ethAsset = getRealAztecAsset(address(0));
        rethAsset = getRealAztecAsset(address(rocketTokenRETH));
    }
    
    function testErrorCodes() public {
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.startPrank(address(ROLLUP_PROCESSOR));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(ethAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(rethAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.AsyncDisabled.selector);
        bridge.finalise(rethAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0);

        vm.stopPrank();
    }

    function testDepositThenBurnAll() public {
        vm.deal(address(ROLLUP_PROCESSOR), 200 ether);
        deposit(50 ether);
        burn(rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)));
    }

    function testMultipleDepositsThenBurnAll() public {
        vm.deal(address(ROLLUP_PROCESSOR), 100 ether);

        uint256 reth1 = deposit(60 ether);
        uint256 reth2 = deposit(30 ether);

        assertEq(address(ROLLUP_PROCESSOR).balance, 10 ether, "10 ETH should be left");
        assertEq(rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)), reth1 + reth2, "sum of output values do not match the rETH balance");
        assertGt(rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)), 89 ether, "rETH balance is below the sanity check value");

        uint256 eth = burn(reth1 + reth2);

        assertLe(address(ROLLUP_PROCESSOR).balance, 100 ether, "there should not be more than the original 100 ETH");
        assertGt(address(ROLLUP_PROCESSOR).balance, 99.9 ether, "ETH balance is below the sanity check value");
        assertEq(address(ROLLUP_PROCESSOR).balance, 10 ether + eth, "output value does not match the ETH balance");
        assertEq(rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)), 0, "all rETH should have been burned");
    }

    function testDepositThenMultipleBurns() public {
        vm.deal(address(ROLLUP_PROCESSOR), 100 ether);

        uint256 reth = deposit(100 ether);

        assertEq(address(ROLLUP_PROCESSOR).balance, 0 ether, "0 ETH should be left undeposited");
        assertEq(rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)), reth, "rETH balance does not match the output value");
        assertGt(rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)), 99 ether, "rETH balance is below the sanity check value");

        uint256 eth1 = burn(50 ether);
        uint256 eth2 = burn(reth - 50 ether);

        assertLe(address(ROLLUP_PROCESSOR).balance, 100 ether, "there should not be more than the original 100 ETH");
        assertGt(address(ROLLUP_PROCESSOR).balance, 99.9 ether, "ETH balance is below the sanity check value");
        assertEq(address(ROLLUP_PROCESSOR).balance, eth1 + eth2, "output value does not match the ETH balance");
        assertEq(rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)), 0, "all rETH should have been burned");
    }

    function deposit(uint256 depositAmount) public returns (uint256) {
        uint256 beforeETHBalance = address(ROLLUP_PROCESSOR).balance;
        uint256 beforeRETHBalance = rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR));

        uint256 rethMintAmount = getRETHMintAmount(depositAmount);

        console2.log("=== [stake] Before ===");
        console2.log("ETH balance", beforeETHBalance);
        console2.log("rETH balance", beforeRETHBalance);
        console2.log("Deposit amount", depositAmount);
        console2.log("Expected rETH amount", rethMintAmount);
        console2.log("Deposit Pool balance", rocketDepositPool.getBalance());
        console2.log("");

        uint256 bridgeCallData = encodeBridgeCallData(id, ethAsset, emptyAsset, rethAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), depositAmount, rethMintAmount, 0, true, "");
        sendDefiRollup(bridgeCallData, depositAmount);

        console2.log("=== [stake] After ===");
        console2.log("ETH balance", address(ROLLUP_PROCESSOR).balance);
        console2.log("rETH balance", rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)));
        console2.log("Deposit Pool balance", rocketDepositPool.getBalance());
        console2.log("");

        assertEq(address(ROLLUP_PROCESSOR).balance, beforeETHBalance - depositAmount, "[stake] ETH balance not matching");
        assertEq(rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)), beforeRETHBalance + rethMintAmount, "[stake] rETH balance not matching");

        return rethMintAmount;
    }

    function burn(uint256 rethAmount) public returns (uint256) {
        uint256 beforeETHBalance = address(ROLLUP_PROCESSOR).balance;
        uint256 beforeRETHBalance = rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR));

        uint256 expectedETH = rocketTokenRETH.getEthValue(rethAmount);

        console2.log("=== [unstake] Before ===");
        console2.log("ETH balance", beforeETHBalance);
        console2.log("rETH balance", beforeRETHBalance);
        console2.log("Unstake amount", rethAmount);
        console2.log("Expected ETH amount", expectedETH);
        console2.log("Deposit Pool balance", rocketDepositPool.getBalance());
        console2.log("");

        uint256 bridgeCallData = encodeBridgeCallData(id, rethAsset, emptyAsset, ethAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), rethAmount, expectedETH, 0, true, "");
        sendDefiRollup(bridgeCallData, rethAmount);

        console2.log("=== [unstake] After ===");
        console2.log("ETH balance", address(ROLLUP_PROCESSOR).balance);
        console2.log("rETH balance", rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)));
        console2.log("Deposit Pool balance", rocketDepositPool.getBalance());
        console2.log("");

        assertEq(address(ROLLUP_PROCESSOR).balance, beforeETHBalance + expectedETH, "[unstake] ETH balance not maching");
        assertEq(rocketTokenRETH.balanceOf(address(ROLLUP_PROCESSOR)), beforeRETHBalance - rethAmount, "[unstake] rETH balance not matching");

        return expectedETH;
    }

    function getRETHMintAmount(uint256 depositAmount) private view returns (uint256) {
        uint256 calcBase = 1 ether;
        uint256 depositFee = (depositAmount * rocketDepositPoolSettings.getDepositFee()) / calcBase;
        uint256 depositNet = depositAmount - depositFee;
        return rocketTokenRETH.getRethValue(depositNet);
    }

    function getRETHContractAddress() private view returns (address) {
        return getContractAddress("rocketTokenRETH");
    }

    function getDepositPoolContractAddress() private view returns (address) {
        return getContractAddress("rocketDepositPool");
    }

    function getDepositPoolSettingsContractAddress() private view returns (address) {
        return getContractAddress("rocketDAOProtocolSettingsDeposit");
    }

    function getContractAddress(string memory contractName) private view returns (address) {
        return rocketStorage.getAddress(keccak256(abi.encodePacked("contract.address", contractName)));
    }
}
