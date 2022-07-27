# Rocket Pool Bridge

rETH has a transfer delay of 5760 blocks. This delay will be removed in the next release codenamed Redstone.

## Testing

Clone the Rocket Pool repo

```
git clone -b v1.1 https://github.com/rocket-pool/rocketpool.git
cd rocketpool
npm install
```

Edit `migrations/2_deploy_contracts.js` and add this after `await addABIs();`

```js
const settingName = (namespace, name) => $web3.utils.soliditySha3($web3.utils.soliditySha3(namespace), name);
const setSettingBool = async (namespace, name, value) => await rocketStorageInstance.setBool(settingName(namespace, name), value);
const setSettingUint = async (namespace, name, value) => await rocketStorageInstance.setUint(settingName(namespace, name), value);

await setSettingBool('dao.protocol.setting.deposit', 'deposit.enabled', true);
await setSettingBool('dao.protocol.setting.deposit', 'deposit.assign.enabled', true);
await setSettingUint('dao.protocol.setting.deposit', 'deposit.pool.maximum', '2000' + '0'.repeat(18));
await setSettingUint('dao.protocol.setting.deposit', 'deposit.assign.maximum', 2);
//await setSettingUint('dao.protocol.setting.network', 'network.reth.deposit.delay', 0);
await setSettingBool('dao.protocol.setting.node', 'node.registration.enabled', true);
await setSettingBool('dao.protocol.setting.node', 'node.deposit.enabled', true);
await setSettingUint('dao.protocol.setting.minipool', 'minipool.maximum.count', 1000000);
```

also enable executing contract upgrades

```js
// Perform distributor upgrade if we are not running in test environment
// if (network !== 'development') {
  console.log('Executing upgrade to v1.1');
  const RocketUpgradeOneDotOne = artifacts.require('RocketUpgradeOneDotOne');
  const rocketUpgradeOneDotOne = await RocketUpgradeOneDotOne.deployed();
  await rocketUpgradeOneDotOne.execute({ from: accounts[0] });
// }
```

Fork mainnet

```
npx ganache-cli --fork https://mainnet.infura.io/v3/9928b52099854248b3a096be07a6b23c -l 12450000 -a 1 -s 123
```

Deploy Rocket Pool

```
npx truffle migrate --skip-dry-run --network development
```

Storage address is `0x4169D71D56563eA9FDE76D92185bEB7aa1Da6fB8`

Run tests

```
$ forge test --fork-url http://localhost:8545 --match-contract RocketPoolBridgeTest
...

Running 4 tests for src/test/bridges/rocketpool/RocketPoolBridge.t.sol:RocketPoolBridgeTest
[PASS] testDepositThenBurnAll() (gas: 625403)
[PASS] testDepositThenMultipleBurns() (gas: 846033)
[PASS] testErrorCodes() (gas: 39323)
[PASS] testMultipleDepositsThenBurnAll() (gas: 830960)
Test result: ok. 4 passed; 0 failed; finished in 337.08ms
```

Run this for debugging

```
forge test --fork-url http://localhost:8545 --match-contract RocketPoolBridgeTest -vvv
```
