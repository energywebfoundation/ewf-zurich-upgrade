# EWC upgrade validation test results

## Overview
Tests in "test/ewcValidation.js" validate the fork behavior by ensuring:
- Validator set remains consistent before and after the fork.
- Rewards contract bytecode changes exactly at the fork block.
- Replayed pre-fork transactions are correctly rejected.
- The Counter contract deploys and functions properly on the upgraded chain.
- State consistency is maintained with accurate minted rewards comparisons between before and after the fork.

## 1. Operational/Config checks
These tests verify the integrity of the system configurations and smart contract behaviors after the fork.
```bash
  // Operational/Config Checks
  EWC FORK VALIDATION TESTS (Block 36871000) :
    
- Operational/Config checks
      ✔ Validator set in contract is unchanged after the fork
      ✔ Rewards contract byte-code changes on the fork block (32597900)
      ✔ Rejects replay of a pre-fork transaction on the shadow-fork
      ✔ Deploys and interacts with a simple Counter contract on the shadow-fork
```

## 2. State consistency validation

```bash
  // State consistency validation
- State Consistency validation
```

## 3. MintedTotally Results - Pre-fork analysis
Comparison of minted rewards before the fork

This section confirms that the minted rewards increase as expected on the Energy Web chain before the fork.
```bash
  // [ewc] MintedTotally: (Checking 10 blocks before fork):
 
	* On block 36870990: 31161022.897411239777777536 EWT
	* On block 36870991: 31161023.609504580277777536 EWT
	* On block 36870992: 31161024.321597920777777536 EWT
	* On block 36870993: 31161025.033691261277777536 EWT
	* On block 36870994: 31161025.745784601777777536 EWT
	* On block 36870995: 31161026.457877942277777536 EWT
	* On block 36870996: 31161027.169971282777777536 EWT
	* On block 36870997: 31161027.882064623277777536 EWT
	* On block 36870998: 31161028.594157963777777536 EWT
	* On block 36870999: 31161029.306251304277777536 EWT
    ✔ Before fork, minted Totally increases on ewc   (4190ms)
```

## 4. MintedTotally results - Post-fork analysis

By verifying the constant reward amount accros blocks on the upgraded chain, we confirmed that no rewards are minted after the fork.
```bash
  // [Upgraded ewc] MintedTotally: (Checking 10 blocks after fork):

	* On block 36871000: 31161029.306251304277777536 EWT
	* On block 36871001: 31161029.306251304277777536 EWT
	* On block 36871002: 31161029.306251304277777536 EWT
	* On block 36871003: 31161029.306251304277777536 EWT
	* On block 36871004: 31161029.306251304277777536 EWT
	* On block 36871005: 31161029.306251304277777536 EWT
	* On block 36871006: 31161029.306251304277777536 EWT
	* On block 36871007: 31161029.306251304277777536 EWT
	* On block 36871008: 31161029.306251304277777536 EWT
	* On block 36871009: 31161029.306251304277777536 EWT
    ✔ After fork, mintedTotally DOES NOT INCREASE on ewc  (4586ms)
```

## 5. Bridge contract state validation
These tests query key properties of the bridge contract—namely, the owner, liftingEnabled, and loweringEnabled states—both before and after the fork on EWC.
- The "owner" test verifies that the contract owner remains identical both before and after the fork.

```bash
[Bridge owner]
	ewc
        - Pre-fork: 0xd1baa2b805e9DA76D2ea7b0b812Afe9DB328F850,
        - Post-fork: 0xd1baa2b805e9DA76D2ea7b0b812Afe9DB328F850
✔ The bridge contract owner is the same before and after the fork
```

- The "liftingEnabled" test checks that the lifting functionality status does not change across the fork and is consistent on EWC.

```bash
[Bridge liftingEnabled]
	ewc
        - Pre-fork: true,
        - Post-fork: true

✔ The bridge contract liftingEnabled is the same before and after the fork
```
