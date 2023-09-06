//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {DataTypes} from "./libraries/DataTypes.sol";

/**
 * @title CrossChainGovernorExecutor
 * @author Oddcod3 (@oddcod3)
 *
 * @dev Governor proxy used from cross-chain portals to execute actions received sent by cross-chain governor
 *
 * @notice The address of this contract should be the owner/governor of ownable/governable contracts deployed on the same chain
 */
contract CrossChainGovernorExecutor {
    error CrossChainGovernorExecutor__ActionExecutionFailed();
    error CrossChainGovernorExecutor__NotCrossChainPortal();

    address private immutable s_crossChainPortal;

    modifier onlyCrossChainPortal() {
        _revertIfNotCrossChainPortal();
        _;
    }

    constructor() {
        s_crossChainPortal = msg.sender;
    }

    /**
     * @param action The action to be executed
     */
    function executeAction(DataTypes.CrossChainAction memory action) external onlyCrossChainPortal {
        bool success;
        bytes memory callData;
        bytes memory resultData;
        uint256 targetsLength = action.targets.length;
        for (uint256 i; i < targetsLength;) {
            if (bytes(action.signatures[i]).length == 0) {
                callData = action.calldatas[i];
            } else {
                callData = abi.encodePacked(bytes4(keccak256(bytes(action.signatures[i]))), action.calldatas[i]);
            }
            (success, resultData) = action.targets[i].call{value: action.values[i]}(callData);
            if (!success) {
                if (resultData.length == 0) {
                    revert CrossChainGovernorExecutor__ActionExecutionFailed();
                }
                assembly {
                    let size := mload(resultData)
                    revert(add(32, resultData), size)
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function _revertIfNotCrossChainPortal() internal view {
        if (msg.sender != s_crossChainPortal) {
            revert CrossChainGovernorExecutor__NotCrossChainPortal();
        }
    }
}
