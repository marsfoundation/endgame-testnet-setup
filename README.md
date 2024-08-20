# Simulator Scripts

Scripts for setting up the environment of the simulator.

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

Deploy: `forge script script/SetupAll.s.sol:SetupAll --broadcast --multi --unlocked --sender 0xbE286431454714F511008713973d3B053A2d38f3`
