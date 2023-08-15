import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-ethers"
import "hardhat-deploy"
import "hardhat-deploy-ethers"
import "dotenv/config"
import importToml from "import-toml"
import { HardhatUserConfig } from "hardhat/config"

const foundryConfig = importToml.sync('foundry.toml')

const PRIVATE_KEY = process.env.PRIVATE_KEY
const ETHEREUM_RPC = process.env.ETHEREUM_RPC
const ETHEREUM_SEPOLIA_RPC = process.env.ETHEREUM_SEPOLIA_RPC
const POLYGON_MAINNET_RPC = "https://rpc-mainnet.maticvigil.com"
const POLYGON_MUMBAI_RPC = "https://rpc-mumbai.maticvigil.com/"
const POLYGON_ZKEVM_TESTNET_RPC = "https://rpc.public.zkevm-test.net"
const POLYGON_ZKEVM_RPC = "https://zkevm-rpc.com"
const AVALANCHE_C_CHAIN_RPC = "https://api.avax.network/ext/bc/C/rpc"
const AVALANCHE_FUJI_RPC = "https://api.avax-test.network/ext/bc/C/rpc"
const ARBITRUM_ONE_RPC = "https://arb1.arbitrum.io/rpc"
const ARBITRUM_TESTNET_RPC = "https://goerli-rollup.arbitrum.io/rpc"

const config: HardhatUserConfig = {
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
    },
    networks: {
        ethereum: {
            url: ETHEREUM_RPC,
            chainId: 1,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        sepolia: {
            url: ETHEREUM_SEPOLIA_RPC,
            chainId: 11155111,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        polygon: {
            url: POLYGON_MAINNET_RPC,
            chainId: 137,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        mumbai: {
            url: POLYGON_MUMBAI_RPC,
            chainId: 80001,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [PRIVATE_KEY],
        },
        avalanche: {
            url: AVALANCHE_C_CHAIN_RPC,
            chainId: 43114,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        fuji: {
            url: AVALANCHE_FUJI_RPC,
            chainId: 43113,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        zkevm: {
            url: POLYGON_ZKEVM_RPC,
            chainId: 1101,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        zkevm_testnet: {
            url: POLYGON_ZKEVM_TESTNET_RPC,
            chainId: 1442,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [PRIVATE_KEY],
        },
        arbitrum: {
            url: ARBITRUM_ONE_RPC,
            chainId: 42161,
            live: true,
            saveDeployments: true,
            accounts: [PRIVATE_KEY],
        },
        arbi_testnet: {
            url: ARBITRUM_TESTNET_RPC,
            chainId: 421611,
            live: true,
            saveDeployments: true,
            gasMultiplier: 2,
            accounts: [PRIVATE_KEY],
        },
    },
    solidity: {
        version: foundryConfig.profile.default.solc_version,
        settings: {
            viaIR: foundryConfig.profile.default.via_ir,
            optimizer: {
                enabled: true,
                runs: foundryConfig.profile.default.optimizer_runs,
            },
        },
    },
}

export default config
