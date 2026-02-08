// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import {IERC20} from "../src/interfaces/IERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {IAaveV3Adapter} from "../src/adapters/interfaces/IAaveV3Adapter.sol";
import {AaveV3Adapter} from "../src/adapters/AaveV3Adapter.sol";
import {AaveV3AdapterFactory} from "../src/adapters/AaveV3AdapterFactory.sol";
import {IAaveV3AdapterFactory} from "../src/adapters/interfaces/IAaveV3AdapterFactory.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

/// @notice Mock Aave V3 Pool for testing
contract AaveV3PoolMock {
    mapping(address => address) public aTokens;

    function setAToken(address asset, address aToken) external {
        aTokens[asset] = aToken;
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        // Transfer asset from caller
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        // Mint aTokens to onBehalfOf
        ATokenMock(aTokens[asset]).mint(onBehalfOf, amount);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        // Burn aTokens from caller
        ATokenMock(aTokens[asset]).burn(msg.sender, amount);
        // Transfer asset to recipient
        IERC20(asset).transfer(to, amount);
        return amount;
    }
}

/// @notice Mock aToken for testing
contract ATokenMock is ERC20Mock {
    address public UNDERLYING_ASSET_ADDRESS;

    constructor() ERC20Mock(18) {}

    function setUnderlyingAsset(address _asset) external {
        UNDERLYING_ASSET_ADDRESS = _asset;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    // Simulate interest accrual by increasing balance
    function accrueInterest(address account, uint256 interest) external {
        _mint(account, interest);
    }
}

contract AaveV3AdapterTest is Test {
    using MathLib for uint256;

    IERC20 internal asset;
    IERC20 internal rewardToken;
    VaultV2Mock internal parentVault;
    AaveV3PoolMock internal aavePool;
    ATokenMock internal aToken;
    IAaveV3AdapterFactory internal factory;
    IAaveV3Adapter internal adapter;
    address internal owner;
    address internal recipient;
    bytes32[] internal expectedIds;

    uint256 internal constant MAX_TEST_ASSETS = 1e36;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");

        asset = IERC20(address(new ERC20Mock(18)));
        rewardToken = IERC20(address(new ERC20Mock(18)));
        aToken = new ATokenMock();
        aToken.setUnderlyingAsset(address(asset));
        aavePool = new AaveV3PoolMock();
        aavePool.setAToken(address(asset), address(aToken));

        parentVault = new VaultV2Mock(address(asset), owner, address(0), address(0), address(0));

        factory = new AaveV3AdapterFactory(address(aavePool));
        adapter = IAaveV3Adapter(factory.createAaveV3Adapter(address(parentVault), address(aToken)));

        deal(address(asset), address(this), type(uint256).max);
        // Transfer assets to pool for withdraw operations
        IERC20(asset).transfer(address(aavePool), type(uint128).max);

        expectedIds = new bytes32[](1);
        expectedIds[0] = keccak256(abi.encode("this", address(adapter)));
    }

    function testFactoryAndParentVaultAndAssetSet() public view {
        assertEq(adapter.factory(), address(factory), "Incorrect factory set");
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.aavePool(), address(aavePool), "Incorrect aavePool set");
        assertEq(adapter.aToken(), address(aToken), "Incorrect aToken set");
        assertEq(adapter.asset(), address(asset), "Incorrect asset set");
    }

    function testAllocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(IAaveV3Adapter.NotAuthorized.selector);
        adapter.allocate(hex"", assets, bytes4(0), address(0));
    }

    function testDeallocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(IAaveV3Adapter.NotAuthorized.selector);
        adapter.deallocate(hex"", assets, bytes4(0), address(0));
    }

    function testAllocate(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        deal(address(asset), address(adapter), assets);

        (bytes32[] memory ids, int256 change) = parentVault.allocateMocked(address(adapter), hex"", assets);

        uint256 adapterATokenBalance = aToken.balanceOf(address(adapter));
        assertEq(adapterATokenBalance, assets, "Incorrect aToken balance after supply");
        assertEq(asset.balanceOf(address(adapter)), 0, "Underlying tokens not transferred to pool");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(change, int256(assets), "Incorrect change returned");
    }

    function testDeallocate(uint256 initialAssets, uint256 withdrawAssets) public {
        initialAssets = bound(initialAssets, 0, MAX_TEST_ASSETS);
        withdrawAssets = bound(withdrawAssets, 0, initialAssets);

        deal(address(asset), address(adapter), initialAssets);
        parentVault.allocateMocked(address(adapter), hex"", initialAssets);

        uint256 beforeATokenBalance = aToken.balanceOf(address(adapter));
        assertEq(beforeATokenBalance, initialAssets, "Precondition failed: aToken balance not set");

        (bytes32[] memory ids, int256 change) = parentVault.deallocateMocked(address(adapter), hex"", withdrawAssets);

        assertEq(adapter.allocation(), initialAssets - withdrawAssets, "incorrect allocation");
        uint256 afterATokenBalance = aToken.balanceOf(address(adapter));
        assertEq(afterATokenBalance, initialAssets - withdrawAssets, "aToken balance not decreased correctly");

        uint256 adapterBalance = asset.balanceOf(address(adapter));
        assertEq(adapterBalance, withdrawAssets, "Adapter did not receive withdrawn tokens");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        assertEq(change, -int256(withdrawAssets), "Incorrect change returned");
    }

    function testFactoryCreateAdapter() public {
        VaultV2Mock newParentVault = new VaultV2Mock(address(asset), owner, address(0), address(0), address(0));
        ATokenMock newAToken = new ATokenMock();
        newAToken.setUnderlyingAsset(address(asset));

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(AaveV3Adapter).creationCode,
                abi.encode(address(newParentVault), address(aavePool), address(newAToken))
            )
        );
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));

        vm.expectEmit();
        emit IAaveV3AdapterFactory.CreateAaveV3Adapter(address(newParentVault), address(newAToken), expectedNewAdapter);

        address newAdapter = factory.createAaveV3Adapter(address(newParentVault), address(newAToken));

        expectedIds[0] = keccak256(abi.encode("this", address(newAdapter)));

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(IAaveV3Adapter(newAdapter).factory(), address(factory), "Incorrect factory");
        assertEq(IAaveV3Adapter(newAdapter).parentVault(), address(newParentVault), "Incorrect parent vault");
        assertEq(IAaveV3Adapter(newAdapter).aToken(), address(newAToken), "Incorrect aToken");
        assertEq(IAaveV3Adapter(newAdapter).adapterId(), expectedIds[0], "Incorrect adapterId");
        assertEq(
            factory.aaveV3Adapter(address(newParentVault), address(newAToken)),
            newAdapter,
            "Adapter not tracked correctly"
        );
        assertTrue(factory.isAaveV3Adapter(newAdapter), "Adapter not tracked correctly");
    }

    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);

        // Access control
        vm.prank(caller);
        vm.expectRevert(IAaveV3Adapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit IAaveV3Adapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);
        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        ERC20Mock token = new ERC20Mock(18);

        // Setup
        vm.prank(owner);
        adapter.setSkimRecipient(recipient);
        deal(address(token), address(adapter), assets);
        assertEq(token.balanceOf(address(adapter)), assets, "Adapter did not receive tokens");

        // Normal path
        vm.expectEmit();
        emit IAaveV3Adapter.Skim(address(token), assets);
        vm.prank(recipient);
        adapter.skim(address(token));
        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), assets, "Recipient did not receive tokens");

        // Access control
        vm.expectRevert(IAaveV3Adapter.NotAuthorized.selector);
        adapter.skim(address(token));

        // Can't skim aToken
        vm.expectRevert(IAaveV3Adapter.CannotSkimAToken.selector);
        vm.prank(recipient);
        adapter.skim(address(aToken));
    }

    function testIds() public view {
        assertEq(adapter.ids(), expectedIds);
    }

    function testInvalidData(bytes memory data) public {
        vm.assume(data.length > 0);

        vm.expectRevert(IAaveV3Adapter.InvalidData.selector);
        adapter.allocate(data, 0, bytes4(0), address(0));

        vm.expectRevert(IAaveV3Adapter.InvalidData.selector);
        adapter.deallocate(data, 0, bytes4(0), address(0));
    }

    function testInterest(uint256 deposit, uint256 interest) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, deposit);

        deal(address(asset), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), hex"", deposit);

        // Simulate interest accrual in aToken
        aToken.accrueInterest(address(adapter), interest);

        assertEq(adapter.realAssets(), deposit + interest, "realAssets should include interest");
    }

    function testRealAssetsZeroWhenNoAllocation() public view {
        assertEq(adapter.realAssets(), 0, "realAssets should be 0 when no allocation");
    }
}
