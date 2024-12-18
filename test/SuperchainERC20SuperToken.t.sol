// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Testing utilities
import {Test} from "forge-std/Test.sol";

// Libraries
import {Predeploys} from "@contracts-bedrock/libraries/Predeploys.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperfluidFrameworkDeployer} from
    "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import {ERC1820RegistryCompiled} from
    "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";

// Target contract
import {SuperchainERC20SuperTokenProxy, SuperchainERC20SuperToken, IERC20} from "../src/SuperchainERC20SuperToken.sol";
import {IERC7802} from "@contracts-bedrock/L2/interfaces/IERC7802.sol";
import {ISuperchainERC20} from "@contracts-bedrock/L2/interfaces/ISuperchainERC20.sol";
// import {L2NativeSuperchainERC20} from "src/L2NativeSuperchainERC20.sol";

contract SuperchainERC20SuperTokenTest is Test {
    address internal _owner = address(0x42);
    address internal constant ZERO_ADDRESS = address(0);
    address internal constant SUPERCHAIN_TOKEN_BRIDGE = Predeploys.SUPERCHAIN_TOKEN_BRIDGE;
    address internal constant MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    SuperchainERC20SuperTokenProxy internal _superTokenProxy;
    SuperfluidFrameworkDeployer.Framework internal _sf;

    SuperchainERC20SuperToken internal _superToken;

    function _deployToken(address owner) internal virtual {
        _superTokenProxy = new SuperchainERC20SuperTokenProxy();

        _superTokenProxy.initialize(_sf.superTokenFactory, "TestToken", "TST", owner);

        _superToken = SuperchainERC20SuperToken(address(_superTokenProxy));
    }

    function setUp() public {
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        SuperfluidFrameworkDeployer sfDeployer = new SuperfluidFrameworkDeployer();
        sfDeployer.deployTestFramework();
        _sf = sfDeployer.getFramework();

        _deployToken(_owner);
    }

    function testDeploy() public {
        _superTokenProxy = new SuperchainERC20SuperTokenProxy();
        assert(address(_superTokenProxy) != address(0));
    }

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @notice Tests the `mint` function reverts when the caller is not the bridge.
    function testFuzz_crosschainMint_callerNotBridge_reverts(address _caller, address _to, uint256 _amount) public {
        // Ensure the caller is not the bridge
        vm.assume(_caller != SUPERCHAIN_TOKEN_BRIDGE);

        // Expect the revert with `Unauthorized` selector
        vm.expectRevert(ISuperchainERC20.Unauthorized.selector);

        // Call the `mint` function with the non-bridge caller
        vm.prank(_caller);
        _superToken.crosschainMint(_to, _amount);
    }

    /// @notice Tests the `mint` succeeds and emits the `Mint` event.
    function testFuzz_crosschainMint_succeeds(address _to, uint256 _amount) public {
        // Ensure `_amount` fits in int256
        vm.assume(int256(_amount) > 0);

        // Ensure `_to` is not the zero address
        vm.assume(_to != ZERO_ADDRESS);

        // Get the total supply and balance of `_to` before the mint to compare later on the assertions
        uint256 _totalSupplyBefore = _superToken.totalSupply();
        uint256 _toBalanceBefore = _superToken.balanceOf(_to);

        // Look for the emit of the `CrosschainMint` event
        vm.expectEmit(address(_superToken));
        emit IERC7802.CrosschainMint(_to, _amount);

        // Call the `mint` function with the bridge caller
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _superToken.crosschainMint(_to, _amount);

        // Check the total supply and balance of `_to` after the mint were updated correctly
        assertEq(_superToken.totalSupply(), _totalSupplyBefore + _amount);
        assertEq(_superToken.balanceOf(_to), _toBalanceBefore + _amount);
    }

    /// @notice Tests the `burn` function reverts when the caller is not the bridge.
    function testFuzz_crosschainBurn_callerNotBridge_reverts(address _caller, address _from, uint256 _amount) public {
        // Ensure the caller is not the bridge
        vm.assume(_caller != SUPERCHAIN_TOKEN_BRIDGE);

        // Expect the revert with `Unauthorized` selector
        vm.expectRevert(ISuperchainERC20.Unauthorized.selector);

        // Call the `burn` function with the non-bridge caller
        vm.prank(_caller);
        _superToken.crosschainBurn(_from, _amount);
    }

    /// @notice Tests the `burn` burns the amount and emits the `CrosschainBurn` event.
    function testFuzz_crosschainBurn_succeeds(address _from, uint256 _amount) public {
        // Ensure `_amount` fits in int256
        vm.assume(int256(_amount) > 0);

        // Ensure `_from` is not the zero address
        vm.assume(_from != ZERO_ADDRESS);

        // Mint some tokens to `_from` so then they can be burned
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _superToken.crosschainMint(_from, _amount);

        // Get the total supply and balance of `_from` before the burn to compare later on the assertions
        uint256 _totalSupplyBefore = _superToken.totalSupply();
        uint256 _fromBalanceBefore = _superToken.balanceOf(_from);

        // Look for the emit of the `CrosschainBurn` event
        vm.expectEmit(address(_superToken));
        emit IERC7802.CrosschainBurn(_from, _amount);

        // Call the `burn` function with the bridge caller
        vm.prank(SUPERCHAIN_TOKEN_BRIDGE);
        _superToken.crosschainBurn(_from, _amount);

        // Check the total supply and balance of `_from` after the burn were updated correctly
        assertEq(_superToken.totalSupply(), _totalSupplyBefore - _amount);
        assertEq(_superToken.balanceOf(_from), _fromBalanceBefore - _amount);
    }
}
