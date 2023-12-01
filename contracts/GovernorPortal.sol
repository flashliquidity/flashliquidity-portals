//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {ChainPortal} from "./ChainPortal.sol";

/**
 * @title GovernorPortal
 * @author Oddcod3 (@oddcod3)
 *
 * @dev GovernorPortal is deployed on the same chain as the governor.
 * @notice This contract send/receive actions sets to/from CrossChainGovernorPortals.
 * @notice This contract is used to extend governance to cross-chain contracts.
 */

contract GovernorPortal is Governable, Guardable, ChainPortal {

    constructor(
        address governor,
        address guardian,
        address ccipRouter,
        address linkToken,
        uint64 chainSelector,
        uint32 executionDelay
    ) Governable(governor) Guardable(guardian) ChainPortal(ccipRouter, linkToken, chainSelector, executionDelay) {}

    /// @inheritdoc Guardable
    function setGuardians(address[] calldata guardians, bool[] calldata enableds)
        external
        override
        onlyPortalController
    {
        _setGuardians(guardians, enableds);
    }

    /// @dev Revert if msg.sender is not an authorized address.
    function _isPortalController() internal view virtual override returns (bool) {
        return msg.sender == _getGovernor();
    }

    /// @dev Revert if msg.sender is not an authorized address.
    function _isAuthorizedToAbort() internal view virtual override returns (bool) {
        return _isGuardian(msg.sender) || msg.sender == _getGovernor();
    }
}
