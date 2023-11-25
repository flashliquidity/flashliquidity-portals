//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IChainPortal} from "./IChainPortal.sol";
import {Portal} from "../libraries/Portal.sol";

interface ICrossChainPortal is IChainPortal {
    function setIntervalCommunicationLost(uint32 intervalCommunicationLost) external;

    /**
     * @param actionSet The action set struct containing the emergency instructions to be executed.
     * @dev This function can be executed only by guardians and only if communication with the base portal has been lost.
     */
    function emergencyCommunicationLost(Portal.ActionSet memory actionSet) external;
}
