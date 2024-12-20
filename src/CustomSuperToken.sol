// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CustomSuperTokenBase} from
    "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/CustomSuperTokenBase.sol";
import {UUPSProxy} from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxy.sol";
import {UUPSUtils} from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSUtils.sol";
import {
    ISuperfluid,
    ISuperToken,
    IERC20,
    IPoolAdminNFT,
    IPoolMemberNFT,
    ISuperTokenFactory
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {
    SuperToken,
    IConstantOutflowNFT,
    IConstantInflowNFT
} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import {SuperTokenFactoryBase} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";
import {IERC7802, IERC165} from "@contracts-bedrock/L2/interfaces/IERC7802.sol";
import {Predeploys} from "@contracts-bedrock/libraries/Predeploys.sol";
import {Unauthorized} from "@contracts-bedrock/libraries/errors/CommonErrors.sol";

contract CustomSuperTokenProxy is CustomSuperTokenBase, UUPSProxy {
    function initialize(ISuperTokenFactory factory, string memory name, string memory symbol, address admin) external {
        CustomSuperToken tokenImpl = new CustomSuperToken(
            ISuperfluid(ISuperTokenFactory(factory).getHost()),
            SuperTokenFactoryBase(address(factory)).CONSTANT_OUTFLOW_NFT_LOGIC(),
            SuperTokenFactoryBase(address(factory)).CONSTANT_INFLOW_NFT_LOGIC(),
            SuperTokenFactoryBase(address(factory)).POOL_ADMIN_NFT_LOGIC(),
            SuperTokenFactoryBase(address(factory)).POOL_MEMBER_NFT_LOGIC()
        );

        ISuperTokenFactory(factory).initializeCustomSuperToken(address(this));

        UUPSUtils.setImplementation(address(tokenImpl));

        ISuperToken(address(this)).initializeWithAdmin(IERC20(address(0)), 18, name, symbol, admin);
    }
}

contract CustomSuperToken is SuperToken {
    constructor(
        ISuperfluid host,
        IConstantOutflowNFT constantOutflowNFT,
        IConstantInflowNFT constantInflowNFT,
        IPoolAdminNFT poolAdminNFT,
        IPoolMemberNFT poolMemberNFT
    ) SuperToken(host, constantOutflowNFT, constantInflowNFT, poolAdminNFT, poolMemberNFT) {}

    /// @notice Allows the admin to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function adminMint(address _to, uint256 _amount) external onlyAdmin {
        _mint(_to, _amount);
    }
}
