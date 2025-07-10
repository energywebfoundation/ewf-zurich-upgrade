## High Level Hard Fork (HF) Procedure

1. Determine suitable version of the clients for OE / Nethermind (3.3.5 for OE, 1.31.12 for Nethermind).
2. Determine upgrade procedure.
3. Conduct extensive local tests – shadowfork tests conducted over Volta shadowfork ([reference](https://nethermind.notion.site/AuRA-Rewards-Contract-Shadowfork-1e5360fc38d0806ba6b6fb8c7531421c)).
4. Determine disaster recovery procedure.
5. Conduct Volta HF (EWC Testnet, following upgrade procedure).
6. Conduct EWC HF following upgrade procedure.

------------------------------------------

## Upgrade Procedure

### Shadowfork

1. Creation of new version of system contract.
2. Setting up Volta Shadowfork with both new versions of Nethermind and OE.
3. Execution of HF with new system contract assuming happy path (all validators comply).
4. Definition of tests for post-HF validation.
5. Executing tests against Volta Shadowfork.
6. Execution of HF with new system contract assuming unhappy path (not all validators comply).
7. Formulation of disaster recovery plan.

### Volta

1. Adjustment of tests for post-Shadowfork chain HF validation (if applicable).
2. Initial communication with validators about upcoming HF actions and the need for their node rectification.
3. New chainspec release ([Volta.json](https://github.com/energywebfoundation/ewf-chainspec/blob/master/Volta.json)).
4. Creation of dedicated upgrade manual with both automated and manual upgrade procedures ([repository](https://github.com/energywebfoundation/ewf-zurich-upgrade)).
5. Testing of new chainspec and new versions in the EW Volta environment.
6. Determining transition block number (for Volta, at least 1 week in the future).
7. Releasing communication of Volta upgrade to validators.
8. Creating backups of archive/fast node DBs for both Nethermind and OE in case of disaster recovery needs.
9. Temporary removal of non-operational/non-traceable nodes right before the fork block.
10. Secure monitoring of the chain around the fork block time.
11. Execution of predefined tests against Volta.
12. Re-initiation of fixed validator nodes.

### EWC

1. Adjustment of tests for post-Volta chain HF validation (if applicable).
2. Initial communication with validators about upcoming HF actions.
3. New chainspec release ([EnergyWebChain.json](https://github.com/energywebfoundation/ewf-chainspec/blob/master/EnergyWebChain.json)).
4. Creation of dedicated upgrade manual with both automated and manual upgrade procedures ([repository](https://github.com/energywebfoundation/ewf-zurich-upgrade)).
5. Testing of new chainspec and new versions in the EW EWC environment.
6. Determining transition block number (for EWC, at least 1 week in the future).
7. Releasing communication of EWC upgrade to validators.
8. Creating backups of archive/fast node DBs for both Nethermind and OE in case of disaster recovery needs.
9. Temporary removal of non-operational/non-traceable nodes right before the fork block.
10. Secure monitoring of the chain around the fork block time.
11. Execution of predefined tests against EWC.
12. Re-initiation of fixed validator nodes.

------------------------------------------

## Validations

Validation results and validation scripts will be stored in this repository.