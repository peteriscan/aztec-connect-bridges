// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

//import "forge-std/console2.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {IRocketStorage} from "../../interfaces/rocketpool/IRocketStorage.sol";
import {IRocketTokenRETH} from "../../interfaces/rocketpool/IRocketTokenRETH.sol";
import {IRocketDepositPool} from "../../interfaces/rocketpool/IRocketDepositPool.sol";

contract RocketPoolBridge is BridgeBase {
    error UnexpectedAfterDepositState();
    error UnexpectedAfterBurnState();

    IRocketStorage public constant rocketStorage = IRocketStorage(0x4169D71D56563eA9FDE76D92185bEB7aa1Da6fB8);
    IRocketTokenRETH public immutable reth;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        reth = IRocketTokenRETH(getRETHContractAddress());
        reth.approve(ROLLUP_PROCESSOR, type(uint256).max);
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
            uint256 outputValueB,
            bool isAsync
        )
    {
        if (isETH(_inputAssetA)) {
            if (isRETH(_outputAssetA)) {
                outputValueA = deposit(_inputValue);
            } else {
                revert ErrorLib.InvalidOutputA();   
            }
        } else if (isRETH(_inputAssetA)) {
            if (isETH(_outputAssetA)) {
                outputValueA = burn(_inputValue, _interactionNonce);
            } else {
                revert ErrorLib.InvalidOutputA();
            }
        } else {
            revert ErrorLib.InvalidInputA();
        }

        outputValueB = 0;
        isAsync = false;
    }

    // ETH -> rETH
    function deposit(uint256 _inputValue) private returns (uint256 outputValue)
    {
        //console2.log("[convert] [deposit] [before] input", _inputValue);
        //console2.log("[convert] [deposit] [before] ETH balance", address(this).balance);
        //console2.log("[convert] [deposit] [before] rETH balance", reth.balanceOf(address(this)));

        uint256 beforeBalance = reth.balanceOf(address(this));
        IRocketDepositPool depositPool = IRocketDepositPool(getDepositPoolContractAddress());
        depositPool.deposit{value: _inputValue}();
        uint256 afterBalance = reth.balanceOf(address(this));

        if (afterBalance < beforeBalance) {
            revert UnexpectedAfterDepositState();
        }

        outputValue = afterBalance - beforeBalance;

        //console2.log("[convert] [deposit] [after] ETH balance", address(this).balance);
        //console2.log("[convert] [deposit] [after] rETH balance", reth.balanceOf(address(this)));
    }

    // rETH -> ETH
    function burn(uint256 _inputValue, uint256 _interactionNonce) private returns (uint256 outputValue) {
        //console2.log("[convert] [burn] [before] input", _inputValue);
        //console2.log("[convert] [burn] [before] ETH balance", address(this).balance);
        //console2.log("[convert] [burn] [before] rETH balance", reth.balanceOf(address(this)));

        uint256 beforeBalance = address(this).balance;
        reth.burn(_inputValue);
        uint256 afterBalance = address(this).balance;

        if (afterBalance < beforeBalance) {
            revert UnexpectedAfterBurnState();
        }

        //console2.log("[convert] [burn] [after] ETH balance", address(this).balance);
        //console2.log("[convert] [burn] [after] rETH balance", reth.balanceOf(address(this)));

        outputValue = afterBalance - beforeBalance;
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(_interactionNonce);
    }

    function isETH(AztecTypes.AztecAsset calldata asset) private pure returns (bool) {
        return asset.assetType == AztecTypes.AztecAssetType.ETH;
    }

    function isRETH(AztecTypes.AztecAsset calldata asset) private view returns (bool) {
        return asset.assetType == AztecTypes.AztecAssetType.ERC20 && asset.erc20Address == address(reth);
    }

    function getRETHContractAddress() private view returns (address) {
        return getContractAddress("rocketTokenRETH");
    }

    function getDepositPoolContractAddress() private view returns (address) {
        return getContractAddress("rocketDepositPool");
    }

    function getContractAddress(string memory contractName) private view returns (address) {
        return rocketStorage.getAddress(keccak256(abi.encodePacked("contract.address", contractName)));
    }
}
