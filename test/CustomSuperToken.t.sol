// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperfluidFrameworkDeployer} from
    "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import {ERC1820RegistryCompiled} from
    "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import {CustomSuperTokenProxy, CustomSuperToken} from "../src/CustomSuperToken.sol";

contract CustomSuperTokenProxyTest is Test {
    address internal _owner = address(0x42);
    address internal _user = address(0x43);
    address internal _minter = address(0x44);
    address internal constant ZERO_ADDRESS = address(0);

    CustomSuperToken internal _superToken;

    CustomSuperTokenProxy internal _superTokenProxy;
    SuperfluidFrameworkDeployer.Framework internal _sf;

    function _deployToken(address owner) internal virtual {
        _superTokenProxy = new CustomSuperTokenProxy();

        _superTokenProxy.initialize(_sf.superTokenFactory, "TestToken", "TST", owner);

        _superToken = CustomSuperToken(address(_superTokenProxy));
    }

    function setUp() public {
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        SuperfluidFrameworkDeployer sfDeployer = new SuperfluidFrameworkDeployer();
        sfDeployer.deployTestFramework();
        _sf = sfDeployer.getFramework();

        _deployToken(_owner);
    }

    function testDeploy() public {
        _superTokenProxy = new CustomSuperTokenProxy();
        assert(address(_superTokenProxy) != address(0));
    }

    function testSuperTokenAdmin() public {
        _superTokenProxy = new CustomSuperTokenProxy();
        _superTokenProxy.initialize(_sf.superTokenFactory, "TestToken", "TST", _owner);
        ISuperToken superToken = ISuperToken(address(_superTokenProxy));
        address admin = superToken.getAdmin();
        assert(admin == _owner);
    }

    /// @notice Tests the `mint` function reverts when the caller is not the bridge.
    function testFuzz_adminMint_callerNotAdmin_reverts(address _caller, address _to, uint256 _amount) public {
        // Ensure the caller is not the admin
        vm.assume(_caller != _owner);

        // Expect the revert
        vm.expectRevert(ISuperToken.SUPER_TOKEN_ONLY_ADMIN.selector);

        // Call the `mint` function with the non-admin caller
        vm.prank(_caller);
        _superToken.adminMint(_to, _amount);
    }

    /// @notice Tests the `mint` succeeds and emits the `Mint` event.
    function testFuzz_adminMint_succeeds(address _to, uint256 _amount) public {
        // Ensure `_amount` fits in int256
        vm.assume(int256(_amount) > 0);

        // Ensure `_to` is not the zero address
        vm.assume(_to != ZERO_ADDRESS);

        // Get the total supply and balance of `_to` before the mint to compare later on the assertions
        uint256 _totalSupplyBefore = _superToken.totalSupply();
        uint256 _toBalanceBefore = _superToken.balanceOf(_to);

        // Call the `adminMint` function with the admin caller
        vm.prank(_owner);
        _superToken.adminMint(_to, _amount);

        // Check the total supply and balance of `_to` after the mint were updated correctly
        assertEq(_superToken.totalSupply(), _totalSupplyBefore + _amount);
        assertEq(_superToken.balanceOf(_to), _toBalanceBefore + _amount);
    }
}
