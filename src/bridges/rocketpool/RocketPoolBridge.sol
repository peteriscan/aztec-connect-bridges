// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {IRocketTokenRETH} from "../../interfaces/rocketpool/IRocketTokenRETH.sol";
import {IRocketDepositPool} from "../../interfaces/rocketpool/IRocketDepositPool.sol";

contract RocketPoolBridge is BridgeBase {
    IRocketTokenRETH public constant RETH = IRocketTokenRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);
    IRocketDepositPool public constant DP = IRocketDepositPool(0x4D05E3d48a938db4b7a9A59A802D5b45011BDe58);

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        RETH.approve(ROLLUP_PROCESSOR, type(uint256).max);
    }

    receive() external payable {}

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool isAsync
        )
    {
        isAsync = false;

        if (isETH(_inputAssetA)) {
            if (isRETH(_outputAssetA)) {
                outputValueA = stake(_inputValue);
            } else {
                revert ErrorLib.InvalidOutputA();   
            }
        } else if (isRETH(_inputAssetA)) {
            if (isETH(_outputAssetA)) {
                outputValueA = unstake(_inputValue, _interactionNonce);
            } else {
                revert ErrorLib.InvalidOutputA();
            }
        } else {
            revert ErrorLib.InvalidInputA();
        }
    }

    // ETH -> rETH
    function stake(uint256 _inputValue) private returns (uint256 outputValue)
    {
        DP.deposit{value: _inputValue}();
        outputValue = RETH.balanceOf(address(this));
    }

    // rETH -> ETH
    function unstake(uint256 _inputValue, uint256 _interactionNonce) private returns (uint256 outputValue) {
        RETH.burn(_inputValue);
        outputValue = address(this).balance;
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(_interactionNonce);
    }

    function isETH(AztecTypes.AztecAsset calldata asset) private pure returns (bool) {
        return asset.assetType == AztecTypes.AztecAssetType.ETH;
    }

    function isRETH(AztecTypes.AztecAsset calldata asset) private pure returns (bool) {
        return asset.assetType == AztecTypes.AztecAssetType.ERC20 && asset.erc20Address == address(RETH);
    }
}
