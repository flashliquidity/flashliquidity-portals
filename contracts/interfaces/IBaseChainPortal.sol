//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IGovernable} from "./IGovernable.sol";
import {IGuardable} from "./IGuardable.sol";
import {IChainPortal} from "./IChainPortal.sol";

interface IBaseChainPortal is IGovernable, IGuardable, IChainPortal {}
