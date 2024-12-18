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

contract SuperchainERC20SuperTokenProxy is CustomSuperTokenBase, UUPSProxy {
    function initialize(ISuperTokenFactory factory, string memory name, string memory symbol, address admin) external {
        SuperchainERC20SuperToken tokenImpl = new SuperchainERC20SuperToken(
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

contract SuperchainERC20SuperToken is SuperToken, IERC7802 {
    constructor(
        ISuperfluid host,
        IConstantOutflowNFT constantOutflowNFT,
        IConstantInflowNFT constantInflowNFT,
        IPoolAdminNFT poolAdminNFT,
        IPoolMemberNFT poolMemberNFT
    ) SuperToken(host, constantOutflowNFT, constantInflowNFT, poolAdminNFT, poolMemberNFT) {}

    /// @notice Allows the SuperchainTokenBridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function crosschainMint(address _to, uint256 _amount) external {
        if (msg.sender != Predeploys.SUPERCHAIN_TOKEN_BRIDGE) revert Unauthorized();

        _mint(_to, _amount);

        emit CrosschainMint(_to, _amount);
    }

    /// @notice Allows the SuperchainTokenBridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function crosschainBurn(address _from, uint256 _amount) external {
        if (msg.sender != Predeploys.SUPERCHAIN_TOKEN_BRIDGE) revert Unauthorized();

        _burn(_from, _amount);

        emit CrosschainBurn(_from, _amount);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) public view virtual returns (bool) {
        return _interfaceId == type(IERC7802).interfaceId || _interfaceId == type(IERC20).interfaceId
            || _interfaceId == type(IERC165).interfaceId;
    }
}
