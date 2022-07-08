// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {RocketPoolBridge} from "../../../bridges/rocketpool/RocketPoolBridge.sol";

import {IRocketTokenRETH} from "../../../interfaces/rocketpool/IRocketTokenRETH.sol";
import {IRocketDepositPool} from "../../../interfaces/rocketpool/IRocketDepositPool.sol";

contract RocketPoolBridgeTest is BridgeTestBase {
    IRocketTokenRETH public constant RETH = IRocketTokenRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);
    IRocketDepositPool public constant DP = IRocketDepositPool(0x4D05E3d48a938db4b7a9A59A802D5b45011BDe58);

    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private rethAsset;

    RocketPoolBridge private bridge;
    uint256 private id;

    function setUp() public {
        bridge = new RocketPoolBridge(address(ROLLUP_PROCESSOR));
        vm.label(address(bridge), "Rocket Pool Bridge");

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 500000);
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedAsset(address(RETH), 1337);

        ethAsset = getRealAztecAsset(address(0));
        rethAsset = getRealAztecAsset(address(RETH));
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

    function testRocketPoolBridge() public {
        validateRocketPoolBridge(200 ether, 50 ether);
    }
    
    function validateRocketPoolBridge(uint256 _balance, uint256 _depositAmount) public {
        // Send ETH to bridge
        vm.deal(address(ROLLUP_PROCESSOR), _balance);

        // Convert ETH to rETH
        validateStake(_depositAmount);

        // convert rETH back to ETH
        validateUnstake(RETH.balanceOf(address(ROLLUP_PROCESSOR)));

        //deal(address(RETH), address(ROLLUP_PROCESSOR), 1 ether);
        //validateUnstake(1 ether);
    }

    function validateStake(uint256 depositAmount) public {
        uint256 beforeETHBalance = address(ROLLUP_PROCESSOR).balance;
        uint256 beforeRETHBalance = RETH.balanceOf(address(ROLLUP_PROCESSOR));

        uint256 rethMintAmount = RETH.getRethValue(depositAmount);
        
        uint256 bridgeId = encodeBridgeId(id, ethAsset, emptyAsset, rethAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), depositAmount, rethMintAmount, 0, true, "");
        sendDefiRollup(bridgeId, depositAmount);

        assertEq(address(ROLLUP_PROCESSOR).balance, beforeETHBalance - depositAmount, "ETH balance not matching");
        assertEq(RETH.balanceOf(address(ROLLUP_PROCESSOR)), beforeRETHBalance + rethMintAmount, "rETH balance not matching");
    }

    function validateUnstake(uint256 depositAmount) public {
        uint256 beforeETHBalance = address(ROLLUP_PROCESSOR).balance;
        uint256 beforeRETHBalance = RETH.balanceOf(address(ROLLUP_PROCESSOR));

        uint256 expectedETH = RETH.getEthValue(depositAmount);

        uint256 bridgeId = encodeBridgeId(id, rethAsset, emptyAsset, ethAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), depositAmount, expectedETH, 0, true, "");
        sendDefiRollup(bridgeId, depositAmount);

        assertEq(address(ROLLUP_PROCESSOR).balance, beforeETHBalance + expectedETH, "ETH balance not maching");
        assertEq(RETH.balanceOf(address(ROLLUP_PROCESSOR)), beforeRETHBalance - depositAmount, "rETH balance not matching");
    }
}
