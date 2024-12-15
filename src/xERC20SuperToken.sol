// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {CustomSuperTokenBase} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/CustomSuperTokenBase.sol";
import {UUPSProxy} from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxy.sol";
import {UUPSUtils} from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSUtils.sol";
import {ISuperToken, ISuperTokenFactory, IERC20} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperToken} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

contract xERC20SuperTokenProxy is CustomSuperTokenBase, UUPSProxy {
    function initialize(
        ISuperTokenFactory factory,
        string memory name,
        string memory symbol
    ) external {
        ISuperTokenFactory(factory).initializeCustomSuperToken(address(this));

        ISuperToken(address(this)).initializeWithAdmin(
            IERC20(address(0)),
            18,
            name,
            symbol,
            address(this)
        );

        UUPSUtils.setImplementation(address(this));
    }
}

contract xERC20SuperToken is SuperToken {}
