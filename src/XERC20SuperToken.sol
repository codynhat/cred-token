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
import {IXERC20} from "./interfaces/IXERC20.sol";

contract XERC20SuperTokenProxy is CustomSuperTokenBase, UUPSProxy {
    function initialize(ISuperTokenFactory factory, string memory name, string memory symbol, address admin) external {
        XERC20SuperToken tokenImpl = new XERC20SuperToken(
            ISuperfluid(ISuperTokenFactory(factory).getHost()),
            SuperTokenFactoryBase(address(factory)).CONSTANT_OUTFLOW_NFT_LOGIC(),
            SuperTokenFactoryBase(address(factory)).CONSTANT_INFLOW_NFT_LOGIC(),
            SuperTokenFactoryBase(address(factory)).POOL_ADMIN_NFT_LOGIC(),
            SuperTokenFactoryBase(address(factory)).POOL_MEMBER_NFT_LOGIC()
        );

        ISuperTokenFactory(factory).initializeCustomSuperToken(address(this));

        UUPSUtils.setImplementation(address(tokenImpl));

        ISuperToken(address(this)).initializeWithAdmin(IERC20(address(this)), 18, name, symbol, admin);
    }
}

contract XERC20SuperToken is SuperToken, IXERC20 {
    /// The duration it takes for the limits to fully replenish
    uint256 internal constant _DURATION = 1 days;
    uint256 internal constant _MAX_LIMIT = type(uint256).max / 2;

    /// Maps bridge address to xERC20 bridge configurations
    mapping(address => Bridge) public bridges;

    error IXERC20_NoLockBox();
    error IXERC20_LimitsTooHigh();

    constructor(
        ISuperfluid host,
        IConstantOutflowNFT constantOutflowNFT,
        IConstantInflowNFT constantInflowNFT,
        IPoolAdminNFT poolAdminNFT,
        IPoolMemberNFT poolMemberNFT
    ) SuperToken(host, constantOutflowNFT, constantInflowNFT, poolAdminNFT, poolMemberNFT) {}

    // ===== IXERC20 =====

    /// @inheritdoc IXERC20
    function setLockbox(address /*lockbox*/ ) external pure {
        // no lockbox support needed
        revert IXERC20_NoLockBox();
    }

    /// @inheritdoc IXERC20
    function setLimits(address bridge, uint256 mintingLimit, uint256 burningLimit) public onlyAdmin {
        if (mintingLimit > _MAX_LIMIT || burningLimit > _MAX_LIMIT) {
            revert IXERC20_LimitsTooHigh();
        }
        _changeMinterLimit(bridge, mintingLimit);
        _changeBurnerLimit(bridge, burningLimit);
        emit BridgeLimitsSet(mintingLimit, burningLimit, bridge);
    }

    /// @inheritdoc IXERC20
    function mint(address user, uint256 amount) public virtual {
        address bridge = msg.sender;
        uint256 currentLimit = mintingCurrentLimitOf(bridge);
        if (currentLimit < amount) revert IXERC20_NotHighEnoughLimits();
        bridges[bridge].minterParams.timestamp = block.timestamp;
        bridges[bridge].minterParams.currentLimit = currentLimit - amount;
        ISuperToken(address(this)).selfMint(user, amount, "");
    }

    /// @inheritdoc IXERC20
    function burn(address user, uint256 amount) public virtual {
        address bridge = msg.sender;
        uint256 currentLimit = burningCurrentLimitOf(bridge);
        if (currentLimit < amount) revert IXERC20_NotHighEnoughLimits();
        bridges[bridge].burnerParams.timestamp = block.timestamp;
        bridges[bridge].burnerParams.currentLimit = currentLimit - amount;
        // in order to enforce user allowance limitations, we first transfer to the bridge
        // (fails if not enough allowance) and then let the bridge burn it.
        ISuperToken(address(this)).selfTransferFrom(user, bridge, bridge, amount);
        ISuperToken(address(this)).selfBurn(bridge, amount, "");
    }

    /// @inheritdoc IXERC20
    function mintingMaxLimitOf(address bridge) external view returns (uint256 limit) {
        limit = bridges[bridge].minterParams.maxLimit;
    }

    /// @inheritdoc IXERC20
    function burningMaxLimitOf(address bridge) external view returns (uint256 limit) {
        limit = bridges[bridge].burnerParams.maxLimit;
    }

    /// @inheritdoc IXERC20
    function mintingCurrentLimitOf(address bridge) public view returns (uint256 limit) {
        limit = _getCurrentLimit(
            bridges[bridge].minterParams.currentLimit,
            bridges[bridge].minterParams.maxLimit,
            bridges[bridge].minterParams.timestamp,
            bridges[bridge].minterParams.ratePerSecond
        );
    }

    /// @inheritdoc IXERC20
    function burningCurrentLimitOf(address bridge) public view returns (uint256 limit) {
        limit = _getCurrentLimit(
            bridges[bridge].burnerParams.currentLimit,
            bridges[bridge].burnerParams.maxLimit,
            bridges[bridge].burnerParams.timestamp,
            bridges[bridge].burnerParams.ratePerSecond
        );
    }

    // ===== INTERNAL FUNCTIONS =====

    function _changeMinterLimit(address bridge, uint256 limit) internal {
        uint256 oldLimit = bridges[bridge].minterParams.maxLimit;
        uint256 currentLimit = mintingCurrentLimitOf(bridge);
        bridges[bridge].minterParams.maxLimit = limit;
        bridges[bridge].minterParams.currentLimit = _calculateNewCurrentLimit(limit, oldLimit, currentLimit);
        bridges[bridge].minterParams.ratePerSecond = limit / _DURATION;
        bridges[bridge].minterParams.timestamp = block.timestamp;
    }

    function _changeBurnerLimit(address bridge, uint256 limit) internal {
        uint256 _oldLimit = bridges[bridge].burnerParams.maxLimit;
        uint256 _currentLimit = burningCurrentLimitOf(bridge);
        bridges[bridge].burnerParams.maxLimit = limit;
        bridges[bridge].burnerParams.currentLimit = _calculateNewCurrentLimit(limit, _oldLimit, _currentLimit);
        bridges[bridge].burnerParams.ratePerSecond = limit / _DURATION;
        bridges[bridge].burnerParams.timestamp = block.timestamp;
    }

    function _calculateNewCurrentLimit(uint256 limit, uint256 oldLimit, uint256 currentLimit)
        internal
        pure
        returns (uint256 newCurrentLimit)
    {
        uint256 difference;

        if (limit <= oldLimit) {
            difference = oldLimit - limit;
            newCurrentLimit = currentLimit > difference ? currentLimit - difference : 0;
        } else {
            difference = limit - oldLimit;
            newCurrentLimit = currentLimit + difference;
        }
    }

    function _getCurrentLimit(uint256 currentLimit, uint256 maxLimit, uint256 timestamp, uint256 ratePerSecond)
        internal
        view
        returns (uint256 limit)
    {
        limit = currentLimit;
        if (limit == maxLimit) {
            return limit;
        } else if (timestamp + _DURATION <= block.timestamp) {
            // the limit is fully replenished
            limit = maxLimit;
        } else if (timestamp + _DURATION > block.timestamp) {
            // the limit is partially replenished
            uint256 timePassed = block.timestamp - timestamp;
            uint256 calculatedLimit = limit + (timePassed * ratePerSecond);
            limit = calculatedLimit > maxLimit ? maxLimit : calculatedLimit;
        }
    }
}
