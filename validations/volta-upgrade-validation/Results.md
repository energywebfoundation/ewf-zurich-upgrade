# Shadow-Fork validation test results

## Overview
Tests in "test/shadowForkValidation.js" validate the fork behavior by ensuring:
- Validator set remains consistent before and after the fork.
- Rewards contract bytecode changes exactly at the fork block.
- Replayed pre-fork transactions are correctly rejected.
- The Counter contract deploys and functions properly on the upgraded chain.
- State consistency is maintained with accurate minted rewards comparisons between before and after the fork.

## 1. Operational/Config checks
These tests verify the integrity of the system configurations and smart contract behaviors after the fork.
```bash
  // Operational/Config Checks
  VOLTA FORK VALIDATION TESTS :
    
- Operational/Config checks
      ✔ Validator set in contract is unchanged after the fork
      ✔ Rewards contract byte-code changes on the fork block (32597900)
      ✔ Rejects replay of a pre-fork transaction on the shadow-fork
      ✔ Deploys and interacts with a simple Counter contract on the shadow-fork
```

## 2. State consistency validation
This part checks the consistency of state elements, such as block hashes, before and after the fork.
```bash
  // State Consistency Validation
- State Consistency validation
      ✔ Forked block before validator rotation matches Volta
      ✔ Forked block after validator rotation diverges from Volta
```

## 3. MintedTotally Results - Pre-fork analysis
Comparison of minted rewards before the fork

This section confirms that the minted rewards increase as expected on the Volta network before the fork.
```bash
  // [Volta] MintedTotally: (Checking 10 blocks before fork)
 
	* On block 32597890: 28029660.923425516104817536 EWT
	* On block 32597891: 28029661.673947082202257536 EWT
	* On block 32597892: 28029662.424468648299697536 EWT
	* On block 32597893: 28029663.174990214397137536 EWT
	* On block 32597894: 28029663.925511780494577536 EWT
	* On block 32597895: 28029664.676033346592017536 EWT
	* On block 32597896: 28029665.426554912689457536 EWT
	* On block 32597897: 28029666.177076478786897536 EWT
	* On block 32597898: 28029666.927598044884337536 EWT
	* On block 32597899: 28029667.678119610981777536 EWT
    ✔ Before fork, minted Totally increases on Volta
```

## 4. MintedTotally results - Post-fork analysis

By verifying the constant reward amount accros blocks on the upgraded chain, we confirmed that no rewards are minted after the fork.
```bash
  // [Upgraded volta] MintedTotally: (Checking 10 blocks after fork):

	* On block 32597900: 28029667.678119610981777536 EWT
	* On block 32597901: 28029667.678119610981777536 EWT
	* On block 32597902: 28029667.678119610981777536 EWT
	* On block 32597903: 28029667.678119610981777536 EWT
	* On block 32597904: 28029667.678119610981777536 EWT
	* On block 32597905: 28029667.678119610981777536 EWT
	* On block 32597906: 28029667.678119610981777536 EWT
	* On block 32597907: 28029667.678119610981777536 EWT
	* On block 32597908: 28029667.678119610981777536 EWT
	* On block 32597909: 28029667.678119610981777536 EWT
	✔ After fork, mintedTotally DOES NOT INCREASE on Volta
```

## 5. Bridge contract state validation
These tests query key properties of the bridge contract—namely, the owner, liftingEnabled, and loweringEnabled states—both before and after the fork on Volta.
- The "owner" test verifies that the contract owner remains identical both before and after the fork.

```bash
[Bridge owner]
	Volta
        - Pre-fork: 0xcE104CADBbF6E5DB3779F5E0921753Ff1e7d2de2,
        - Post-fork: 0xcE104CADBbF6E5DB3779F5E0921753Ff1e7d2de2
✔ The bridge contract owner is the same before and after the fork
```

- The "liftingEnabled" test checks that the lifting functionality status does not change across the fork and is consistent on Volta.

```bash
[Bridge liftingEnabled]
	Volta
        - Pre-fork: true,
        - Post-fork: true

✔ The bridge contract liftingEnabled is the same before and after the fork
```

- Similarly, the "loweringEnabled" test ensures that the lowering functionality status is unchanged by the fork.
This comprehensive validation confirms that the expected static properties of the bridge contract remain unaffected by the upgrade.

```bash

[Bridge loweringEnabled]
	Volta
        - Pre-fork: true,
        - Post-fork: true

 ✔ The bridge contract loweringEnabled is the same before and after the fork
```
