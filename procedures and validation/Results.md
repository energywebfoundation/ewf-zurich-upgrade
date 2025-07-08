# Shadow-Fork validation test results

## Overview
Tests in "test/shadowForkValidation.js" validate the shadow-fork behavior by ensuring:
- Validator set remains consistent before and after the fork.
- Rewards contract bytecode changes exactly at the fork block.
- Replayed pre-fork transactions are correctly rejected.
- The Counter contract deploys and functions properly on the shadow-fork.
- State consistency is maintained with accurate block hashes and minted rewards comparisons between Volta and shadow-fork networks.

## 1. Operational/Config checks
These tests verify the integrity of the system configurations and smart contract behaviors after the fork.
```bash
  // Operational/Config Checks
  VOLTA SHADOW-FORK VALIDATION TESTS :
    
- Operational/Config checks
      ✔ Validator set in contract is unchanged after the fork (812ms)
      ✔ Rewards contract byte-code changes on the fork block (31824620)  (374ms)
      ✔ Rejects replay of a pre-fork transaction on the shadow-fork (155ms)
      ✔ Deploys and interacts with a simple Counter contract on the shadow-fork (10710ms)
```

## 2. State consistency validation
This part checks the consistency of state elements, such as block hashes, before and after the fork.
```bash
  // State Consistency Validation
- State Consistency validation
      ✔ Forked block before validator rotation matches Volta (832ms)
      ✔ Forked block after validator rotation diverges from Volta (801ms)
```

## 3. MintedTotally Results - Pre-fork analysis
Comparison of minted rewards before the fork, on both Volta and the forked network
### 3.1 Volta Network
This section confirms that the minted rewards increase as expected on the Volta network before the fork.
```bash
  // [Volta] MintedTotally: (Pre-fork 10 blocks)
 
	* On block 31824610: 27444074.899417296433777536 EWT
	* On block 31824611: 27444075.660435461189777536 EWT
	* On block 31824612: 27444076.421453625945777536 EWT
	* On block 31824613: 27444077.182471790701777536 EWT
	* On block 31824614: 27444077.943489955457777536 EWT
	* On block 31824615: 27444078.704508120213777536 EWT
	* On block 31824616: 27444079.465526284969777536 EWT
	* On block 31824617: 27444080.226544449725777536 EWT
	* On block 31824618: 27444080.987562614481777536 EWT
	* On block 31824619: 27444081.748580779237777536 EWT
      ✔ Before fork, minted Totally increases on Volta (7678ms)
```
### 3.2 Shadow fork network
This section checks that rewards are correctly minted on the shadow-fork network before the fork.
```bash
  // [Fork] MintedTotally: (Pre-fork 10 blocks)
 
	* On block 31824610: 27444074.899417296433777536 EWT
	* On block 31824611: 27444075.660435461189777536 EWT
	* On block 31824612: 27444076.421453625945777536 EWT
	* On block 31824613: 27444077.182471790701777536 EWT
	* On block 31824614: 27444077.943489955457777536 EWT
	* On block 31824615: 27444078.704508120213777536 EWT
	* On block 31824616: 27444079.465526284969777536 EWT
	* On block 31824617: 27444080.226544449725777536 EWT
	* On block 31824618: 27444080.987562614481777536 EWT
	* On block 31824619: 27444081.748580779237777536 EWT
      ✔ Before fork, minted Totally increases on Shadow For (2743ms)
```

## 4. MintedTotally results - Post-fork analysis
After the fork, the tests examine whether the minted rewards continue to increase on Volta, while remaining constant on the shadow fork.
### 4.1 Volta network
On Volta, minted rewards correctly continue to increase after the fork.
```bash
  // [Volta] MintedTotally: (Post-fork 10 blocks)

	* On block 31824620: 27444082.509598943993777536 EWT
	* On block 31824621: 27444083.270617108749777536 EWT
	* On block 31824622: 27444084.031635273505777536 EWT
	* On block 31824623: 27444084.792653438261777536 EWT
	* On block 31824624: 27444085.553671603017777536 EWT
	* On block 31824625: 27444086.314689767773777536 EWT
	* On block 31824626: 27444087.075707932529777536 EWT
	* On block 31824627: 27444087.836726097285777536 EWT
	* On block 31824628: 27444088.597744262041777536 EWT
	* On block 31824629: 27444089.358762426797777536 EWT
      ✔ After fork, mintedTotally still increases on Volta (8149ms)
```
### 4.2 Shadow fork network
Conversely, by verifying the constant reward amount accros blocks on the shadow-fork network, we confirmed that no rewards are minted after the fork.
```bash
  // [Fork] MintedTotally: (Post-fork 10 blocks)

	* On block 31824620: 27444081.748580779237777536 EWT
	* On block 31824621: 27444081.748580779237777536 EWT
	* On block 31824622: 27444081.748580779237777536 EWT
	* On block 31824623: 27444081.748580779237777536 EWT
	* On block 31824624: 27444081.748580779237777536 EWT
	* On block 31824625: 27444081.748580779237777536 EWT
	* On block 31824626: 27444081.748580779237777536 EWT
	* On block 31824627: 27444081.748580779237777536 EWT
	* On block 31824628: 27444081.748580779237777536 EWT
	* On block 31824629: 27444081.748580779237777536 EWT
      ✔ After fork, mintedTotally DOES NOT INCREASE on Shadow Fork (2859ms)
```

## 5. Bridge contract state validation
These tests query key properties of the bridge contract—namely, the owner, liftingEnabled, and loweringEnabled states—both before and after the fork on Volta and Shadow Fork networks.
- The "owner" test verifies that the contract owner remains identical on both networks before and after the fork.

```bash
[Bridge owner]
	Volta
        - Pre-fork: 0xcE104CADBbF6E5DB3779F5E0921753Ff1e7d2de2,
        - Post-fork: 0xcE104CADBbF6E5DB3779F5E0921753Ff1e7d2de2
	Shadow
        - Pre-fork: 0xcE104CADBbF6E5DB3779F5E0921753Ff1e7d2de2,
        - Post-fork: 0xcE104CADBbF6E5DB3779F5E0921753Ff1e7d2de2
✔ The bridge contract owner is the same on both Volta and Shadow Fork before and after the fork (1607ms)
```

- The "liftingEnabled" test checks that the lifting functionality status does not change across the fork and is consistent between Volta and Shadow Fork.

```bash
[Bridge liftingEnabled]
	Volta
        - Pre-fork: true,
        - Post-fork: true
	Shadow
        - Pre-fork: true,
        - Post-fork: true
✔ The bridge contract liftingEnabled is the same on both Volta and Shadow Fork before and after the fork (978ms)
```

- Similarly, the "loweringEnabled" test ensures that the lowering functionality status is unchanged by the fork and matches on both networks.
This comprehensive validation confirms that the expected static properties of the bridge contract remain unaffected by the fork in both environments.

```bash

[Bridge loweringEnabled]
	Volta
        - Pre-fork: true,
        - Post-fork: true
	Shadow
        - Pre-fork: true,
        - Post-fork: true
 ✔ The bridge contract loweringEnabled is the same on both Volta and Shadow Fork before and after the fork (1565ms)
```
