// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "../src/NFTAuction.sol";

/**
 * @title DeployNFTAuction
 * @dev 使用UUPS代理模式部署NFT拍卖合约
 *
 * 使用方法：
 * forge script script/DeployNFTAuction.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify
 */
contract DeployNFTAuction is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // 从环境变量读取配置
        address ethUsdPriceFeed = vm.envAddress("ETH_USD_PRICE_FEED");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        console.log("=== Deploying NFTAuction with UUPS Proxy ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("ETH/USD Price Feed:", ethUsdPriceFeed);
        console.log("Fee Recipient:", feeRecipient);

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署实现合约
        NFTAuction implementation = new NFTAuction();
        console.log("Implementation deployed at:", address(implementation));

        // 2. 编码初始化数据
        bytes memory initData = abi.encodeCall(
            NFTAuction.initialize,
            (ethUsdPriceFeed, feeRecipient)
        );

        // 3. 部署ERC1967代理
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Proxy Address (use this for interactions):", address(proxy));
        console.log("Implementation Address:", address(implementation));

        console.log("\n=== Next Steps ===");
        console.log("1. Verify implementation on Etherscan");
        console.log("2. Add supported ERC20 tokens using addSupportedToken()");
        console.log("3. Update frontend with proxy address");
    }
}

//ERC1967Proxy: 简化实现，用于部署脚本
//在生产环境中，建议使用OpenZeppelin的ERC1967Proxy
contract ERC1967Proxy {
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation, bytes memory _data) {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, implementation)
        }
        if (_data.length > 0) {
            (bool success, ) = implementation.delegatecall(_data);
            require(success, "Proxy: initialization failed");
        }
    }

    fallback() external payable {
        _delegate();
    }

    receive() external payable {
        _delegate();
    }

    function _delegate() internal {
        address impl;
        assembly {
            impl := sload(_IMPLEMENTATION_SLOT)
        }
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
