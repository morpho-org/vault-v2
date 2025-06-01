import {Script} from "../lib/forge-std/src/Script.sol";
import {VaultV2Factory} from "../src/VaultV2Factory.sol";
import {MetaMorphoAdapter} from "../src/adapters/MetaMorphoAdapter.sol";
import {VaultV2} from "../src/VaultV2.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {MetaMorphoAdapterFactory} from "../src/adapters/MetaMorphoAdapterFactory.sol";
import {ManualVicFactory} from "../src/vic/ManualVicFactory.sol";
import {ManualVic} from "../src/vic/ManualVic.sol";

contract Deploy is Script {
    address ME = address(0x19aC47293DDeA675E73FeebeAC52eB6f14ba756f);
    address USDC = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    address metaMorpho = address(0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca);

    // Deployed addresses
    VaultV2Factory FACTORY = VaultV2Factory(0x007eC984a7CC7DB7345D65A1f91869396eaCBB1d);
    MetaMorphoAdapterFactory MM_ADAPTER_FACTORY = MetaMorphoAdapterFactory(0x5D7D38df44C2f3667C87537321B03b11a1578a00);
    ManualVic vic = ManualVic(0x6aBC9EDA1669F06C222742eA33785050a3a24826);

    VaultV2 VAULT = VaultV2(0xD0AcE37EB059437254a9bf45C16B346a7565Aa08);
    function run() external {
        vm.startBroadcast();

        setManualVic(VAULT, vic);



        vm.stopBroadcast();
    }

    function setManualVic(VaultV2 vault, ManualVic manualVic) private {
        bytes memory setVicData = abi.encodeCall(IVaultV2.setVic, (address(manualVic)));
        vault.submit(setVicData);
        vault.setVic(address(manualVic));
    }

    function createManualVic(VaultV2 vault) private {


        ManualVicFactory manualVicFactory = new ManualVicFactory();
        ManualVic manualVic = ManualVic(manualVicFactory.createManualVic(address(vault)));
    }


    function deployVault() private {
        VaultV2Factory vaultFactory = new VaultV2Factory();

        new MetaMorphoAdapterFactory();

        VaultV2 vault = VaultV2(vaultFactory.createVaultV2(ME, USDC, "Test USDC Vault", "USDCTestV2", bytes32(0)));

    }

    function setAdapter(VaultV2 vault, MetaMorphoAdapterFactory mmAdapterFactory) private {
        vault.setCurator(ME);

        MetaMorphoAdapter mmAdapter =
            MetaMorphoAdapter(mmAdapterFactory.createMetaMorphoAdapter(address(vault), metaMorpho));

        bytes memory idData = abi.encode("adapter", address(mmAdapter));

        bytes memory isAllocatorData = abi.encodeCall(IVaultV2.setIsAllocator, (ME, true));
        vault.submit(isAllocatorData);
        vault.setIsAllocator(ME, true);

        uint256 cap = 10000e6;
        bytes memory setCapData = abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, cap));

        vault.submit(setCapData);
        vault.increaseAbsoluteCap(idData, cap);

        bytes memory setRelativeCapData = abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18));
        vault.submit(setRelativeCapData);
        vault.increaseRelativeCap(idData, 1e18);

        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(mmAdapter), true)));
        vault.setIsAdapter(address(mmAdapter), true);

        vault.submit(abi.encodeCall(IVaultV2.setLiquidityAdapter, (address(mmAdapter))));
        vault.setLiquidityAdapter(address(mmAdapter));
    }
}
