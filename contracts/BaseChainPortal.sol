//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {ChainPortal} from "./ChainPortal.sol";

/**
 * @title BaseChainPortal
 * @author Oddcod3 (@oddcod3)
 *
 * @dev Main portal deployed on the base chain where the FlashLiquidity governor is deployed.
 *
 * @notice This contract is used to communicate with other CrossChainPortals.
 * @notice The FlashLiquidity governor can use this contract to govern CrossChainPortals.
 * @notice The FlashLiquidity governor can use this contract to govern cross-chain contracts indirectly (cross-chain contracts must be governed by CrossChainPortal).
 * @notice During action execution, the function will revert if this portal is included in the targets array of the action.
 */
contract BaseChainPortal is Governable, Guardable, ChainPortal {
    error BaseChainPortal__SelfCallNotAuthorized();

    constructor(address governor, address guardian, address ccipRouter, address linkToken, uint64 executionDelay)
        Governable(governor)
        Guardable(guardian)
        ChainPortal(ccipRouter, linkToken, executionDelay)
    {
        s_isGuardian[governor] = true;
    }

    /// @inheritdoc Guardable
    function setGuardians(address[] calldata guardians, bool[] calldata enableds) external override onlyGovernor {
        _setGuardians(guardians, enableds);
    }

    /// @inheritdoc ChainPortal
    function abortAction(uint64 actionId) external override onlyGuardian {
        _abortAction(actionId);
    }

    /// @inheritdoc ChainPortal
    function setExecutionDelay(uint64 executionDelay) external override onlyGovernor {
        _setExecutionDelay(executionDelay);
    }

    /// @inheritdoc ChainPortal
    function setChainPortals(uint64[] calldata destChainSelectors, address[] calldata portals)
        external
        override
        onlyGovernor
    {
        _setChainPortals(destChainSelectors, portals);
    }

    /// @inheritdoc ChainPortal
    function setLanes(
        address[] calldata senders,
        uint64[] calldata destChainSelectors,
        address[] calldata receivers,
        bool[] calldata enableds
    ) external override onlyGovernor {
        _setLanes(senders, destChainSelectors, receivers, enableds);
    }

    /**
     * @notice Revert if this portal is included in the targets array.
     */
    function _verifyActionRestrictions(address, address[] memory targets, uint64) internal view override {
        for (uint256 i; i < targets.length;) {
            if (targets[i] == address(this)) {
                revert BaseChainPortal__SelfCallNotAuthorized();
            }
            unchecked {
                ++i;
            }
        }
    }
}
