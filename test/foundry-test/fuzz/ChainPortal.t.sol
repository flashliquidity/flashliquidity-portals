// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BaseChainPortal} from "../../../contracts/BaseChainPortal.sol";
import {ChainPortal} from "../../../contracts/ChainPortal.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {CcipRouterMock} from "../../mocks/CcipRouterMock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract ChainPortalTest is Test {
    BaseChainPortal public portal;
    CcipRouterMock public ccipRouter;
    ERC20Mock public linkToken;
    address public governor = makeAddr("governor");
    address public guardian = makeAddr("guardian");
    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");
    address public rob = makeAddr("rob");
    address public cc_portal = makeAddr("cc_portal");

    uint64 public baseChainSelector = uint64(block.chainid);
    uint64 public crossChainSelector = uint64(4444);
    uint32 public executionDelay = 6 hours;

    function isNotAuthorizedLane(address sender, uint64 chainSelector, address[] memory targets)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < targets.length; i++) {
            if (!portal.isAuthorizedLane(sender, chainSelector, targets[i])) {
                return true;
            }
        }
        return false;
    }

    function buildMessage(
        bytes32 messageId,
        address chainPortal,
        uint64 sourceChainSelector,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        address[] memory tokens,
        uint256[] memory amounts
    ) public view returns (Client.Any2EVMMessage memory) {
        ChainPortal.CrossChainAction memory action = ChainPortal.CrossChainAction({
            sender: msg.sender,
            targets: targets,
            values: values,
            signatures: signatures,
            calldatas: calldatas
        });
        Client.EVMTokenAmount[] memory tokensData = new Client.EVMTokenAmount[](tokens.length);
        for (uint256 i; i < tokens.length;) {
            tokensData[i].token = tokens[i];
            tokensData[i].amount = amounts[i];
            unchecked {
                ++i;
            }
        }
        return Client.Any2EVMMessage({
            messageId: messageId,
            sender: abi.encode(chainPortal),
            sourceChainSelector: sourceChainSelector,
            data: abi.encode(action),
            destTokenAmounts: tokensData
        });
    }

    function setUp() public {
        vm.prank(governor);
        linkToken = new ERC20Mock("LINK","LINK", 1000000);
        ccipRouter = new CcipRouterMock(
            address(linkToken),
            uint64(block.chainid)
        );
        portal = new BaseChainPortal(
            governor,
            guardian,
            address(ccipRouter),
            address(linkToken),
            executionDelay
        );
    }

    function testFuzzTeleport(
        address sender,
        uint64 chainSelector,
        uint64 gasLimit,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        address[] memory tokens,
        uint256[] memory amounts,
        bool authorizeAllLanes,
        bool isPortalSet
    ) public {
        gasLimit = uint64(bound(gasLimit, 1, 2e6));
        if (authorizeAllLanes && targets.length > 0) {
            address[] memory senders = new address[](targets.length);
            bool[] memory enableds = new bool[](targets.length);
            uint64[] memory chainSelectors = new uint64[](targets.length);
            for (uint256 i = 0; i < senders.length; i++) {
                senders[i] = sender;
                chainSelectors[i] = chainSelector;
                enableds[i] = true;
            }
            vm.prank(governor);
            bool zeroAddressTarget;
            for (uint256 i; i < targets.length; i++) {
                if (targets[i] == address(0)) {
                    zeroAddressTarget = true;
                    break;
                }
            }
            if (!zeroAddressTarget) {
                portal.setLanes(senders, chainSelectors, targets, enableds);
            }
        }
        if (isPortalSet && targets.length > 0) {
            address[] memory portals = new address[](1);
            uint64[] memory chainSelectors = new uint64[](1);
            portals[0] = address(portal);
            chainSelectors[0] = chainSelector;
            vm.prank(governor);
            portal.setChainPortals(chainSelectors, portals);
        }
        if (isNotAuthorizedLane(sender, chainSelector, targets) && targets.length > 0) {
            vm.expectRevert(ChainPortal.ChainPortal__LaneNotAvailable.selector);
        } else if (
            (
                targets.length != values.length || values.length != signatures.length
                    || signatures.length != calldatas.length || tokens.length != amounts.length
            )
        ) {
            vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        } else if (targets.length == 0) {
            vm.expectRevert(ChainPortal.ChainPortal__ZeroTargets.selector);
        } else if (portal.getPortal(chainSelector) == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, chainSelector));
        }
        vm.prank(sender);
        portal.teleport(chainSelector, gasLimit, targets, values, signatures, calldatas, tokens, amounts);
    }

    function testFuzzCcipReceive(
        bytes32 messageId,
        uint64 sourceChainSelector,
        address sourcePortal,
        ChainPortal.CrossChainAction memory action,
        bool isChainPortalSet,
        bool isAuthorizedSourcePortal
    ) public {
        vm.assume(sourceChainSelector != 0);
        vm.assume(sourcePortal != address(0));
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage(
            messageId, sourceChainSelector, abi.encode(sourcePortal), abi.encode(action), new Client.EVMTokenAmount[](0)
        );
        if (isChainPortalSet) {
            uint64[] memory chainSelectors = new uint64[](1);
            address[] memory portals = new address[](1);
            chainSelectors[0] = sourceChainSelector;
            portals[0] = isAuthorizedSourcePortal ? sourcePortal : rob;
            vm.prank(address(governor));
            portal.setChainPortals(chainSelectors, portals);
            if (!isAuthorizedSourcePortal) {
                vm.expectRevert(ChainPortal.ChainPortal__InvalidPortal.selector);
            }
        } else {
            vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, sourceChainSelector));
        }
        vm.prank(address(ccipRouter));
        portal.ccipReceive(message);
    }
}
