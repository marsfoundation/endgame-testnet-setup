# Endgame Testnet Setup

A single script which will setup all contracts on Mainnet and Base from forks to deliver the latest available production setup for the Endgame along with critical Spark infrastructure.

Deploys and configures:

 * Allocation System Core
 * Spark ALM Controller
 * Farms on Mainnet/Base (SPK-USDS, SKY-SPK, SPK-SKY)
 * Sky L2 Cross-chain Governance
 * L2 Token Bridge
 * L2 sUSDS Exchange Rate Oracle
 * L2 PSM with Native USDC, USDS and sUSDS swaps supported


Contracts will be kept in line with latest available, so new mainnet fork testnets can be spun up easily.

## Usage

The script will use environment variables for RPC settings.

Example for local Anvil nodes:

```
export MAINNET_RPC_URL=http://127.0.0.1:8545
export BASE_RPC_URL=http://127.0.0.1:8546
```

Please note all setup scripts need to be run as the owner of the MCD Pause Proxy at address: `0xbE286431454714F511008713973d3B053A2d38f3`. Most forking setups have a way to impersonate accounts. This account also needs ETH.

Example Preparation (Anvil):

```
cast rpc --rpc-url="$MAINNET_RPC_URL" anvil_setBalance 0xbE286431454714F511008713973d3B053A2d38f3 `cast to-wei 1000 | cast to-hex`
cast rpc --rpc-url="$MAINNET_RPC_URL" anvil_impersonateAccount 0xbE286431454714F511008713973d3B053A2d38f3
cast rpc --rpc-url="$BASE_RPC_URL" anvil_setBalance 0xbE286431454714F511008713973d3B053A2d38f3 `cast to-wei 1000 | cast to-hex`
cast rpc --rpc-url="$BASE_RPC_URL" anvil_impersonateAccount 0xbE286431454714F511008713973d3B053A2d38f3
```

Deploy: `forge script script/SetupAll.s.sol:SetupAll --broadcast --multi --slow --unlocked --sender 0xbE286431454714F511008713973d3B053A2d38f3`  
Test: `forge test`  
