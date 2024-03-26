//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {CrossChainGovernable} from "flashliquidity-acs/contracts/CrossChainGovernable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {Portal, ChainPortal} from "./ChainPortal.sol";

/**
 * @title CrossChainGovernorPortal
 * @author Oddcod3 (@oddcod3)
 *
 * @dev Cross-chain governor portals are not deployed on the same chain where governor is deployed.
 * @notice This contract is used to communicate with other CrossChainGovernorPortals and with GovernorPortal.
 * @notice Governor can extend governance to cross-chain contracts indirectly by interacting with cross-chain portals from governor portal.
 * @notice The role of owner/governor for the contracts that require cross-chain governance should be granted to this portal.
 */
contract CrossChainGovernorPortal is CrossChainGovernable, Guardable, ChainPortal {
    error CrossChainGovernorPortal__CommunicationNotLost();

    uint32 private s_intervalCommunicationLost = 28 days;

    event IntervalCommunicationLostChanged(uint32 indexed newInterval);

    constructor(
        address governor,
        address guardian,
        address ccipRouter,
        address linkToken,
        uint64 chainSelector,
        uint64 governorChainSelector,
        uint64 route2GovChainSelector,
        address route2GovPortal,
        uint32 executionDelay
    )
        CrossChainGovernable(governor, governorChainSelector)
        Guardable(guardian)
        ChainPortal(ccipRouter, linkToken, chainSelector, executionDelay)
    {
        Portal.Route memory route;
        route.portal = route2GovPortal;
        if (route2GovChainSelector == 0) {
            route.chainSelector = governorChainSelector;
        } else {
            route.chainSelector = route2GovChainSelector;
            s_routes[route2GovChainSelector] = route;
        }
        s_routes[governorChainSelector] = route;
    }

    /**
     * @dev When this interval is exceeded the communication with the base portal is considered lost.
     * @param intervalCommunicationLost The time interval between the last timestamp an action has been received and the timestamp of the current block.
     */
    function setIntervalCommunicationLost(uint32 intervalCommunicationLost) external onlyPortalController {
        s_intervalCommunicationLost = intervalCommunicationLost;
        emit CommunicationLostIntervalChanged(intervalCommunicationLost);
    }

    /// @inheritdoc CrossChainGovernable
    function setPendingGovernor(address pendingGovernor, uint64 pendingGovernorChainSelector)
        external
        override
        onlyPortalController
    {
        _setPendingGovernor(pendingGovernor, pendingGovernorChainSelector);
    }

    /// @inheritdoc CrossChainGovernable
    function transferGovernance() external override onlyGuardian onlyNotCursed {
        _transferGovernance();
    }

    /// @inheritdoc Guardable
    function setGuardians(address[] calldata guardians, bool[] calldata enableds)
        external
        override
        onlyPortalController
    {
        _setGuardians(guardians, enableds);
    }

    /**
     * @dev This function can be executed only by guardians and only if communication with the base portal has been lost.
     * @param actionSet The action set struct containing the emergency instructions to be executed.
     */
    function emergencyCommunicationLost(Portal.ActionSet memory actionSet) external onlyGuardian onlyNotCursed {
        if (!_isCommunicationLost()) revert CrossChainGovernorPortal__CommunicationNotLost();
        Portal.State storage portalState = s_portalState;
        uint64 lastActionId = s_portalState.lastActionId;
        ++s_portalState.lastActionId;
        s_actionSets[lastActionId] = actionSet;
        s_actionInfos[lastActionId] =
            Portal.ActionSetInfo(uint48(block.timestamp) + portalState.executionDelay, Portal.ActionState.PENDING);
    }

    /// @inheritdoc ChainPortal
    /// @dev The portal controller is the portal itself.
    function _isPortalController() internal view virtual override returns (bool) {
        return msg.sender == address(this);
    }

    /// @inheritdoc ChainPortal
    /// @dev only not cursed guardians are authorized to abort action sets.
    function _isAuthorizedToAbort() internal view override returns (bool) {
        return _isGuardian(msg.sender) && !_isGuardianCursed(msg.sender);
    }

    /// @dev Action sets are authorized if the origin is either the governor or another cross-chain portals if set.
    function _isAuthorizedActionOrigin(address origin, uint64 srcChainSelector) internal view override returns (bool) {
        return _getGovernor() == origin && _getGovernorChainSelector() == srcChainSelector
            || super._isAuthorizedActionOrigin(origin, srcChainSelector);
    }

    /// @return True if communication with the governor portal has been lost lost; otherwise, false.
    function _isCommunicationLost() internal view returns (bool) {
        Portal.State memory portalState = s_portalState;
        return portalState.lastActionId != 0
            && block.timestamp - portalState.lastMessageTimestamp > s_intervalCommunicationLost;
    }

    /// @return Return the inteval after which, if no message has been received, communication with base portal is considered lost.
    function getIntervalCommunicationLost() external view returns (uint32) {
        return s_intervalCommunicationLost;
    }
}
