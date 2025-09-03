/* eslint-env mocha */
const { expect } = require("chai");
const { ethers, hardhatArguments } = require("hardhat");
const { getAddress, toQuantity } = require("ethers");
const dotenv = require("dotenv");
dotenv.config();

/* ------------------------------------------------------------------------ */
/* Constants                                                                */
/* ------------------------------------------------------------------------ */
const BN = (n) => BigInt(n);

// EWC hardfork block number
// const BLOCK_REWARD_STOP = BN(36683760);
// const BLOCK_REWARD_STOP = BN(36761500);
const BLOCK_REWARD_STOP = BN(36871000);
const BLOCK_BEFORE_REWARD_STOP = BLOCK_REWARD_STOP - 1n;

const NEW_VALIDATOR_RAW = "0x14747a698ec1227e6753026c08b29b4d5d3bc484";
const NEW_VALIDATOR = getAddress(NEW_VALIDATOR_RAW);

const GET_VALIDATORS_SIG = "0xb7ab4db5";                   // bytes4(keccak256("getValidators()"))
const VALIDATORS_CONTRACT = "0x1204700000000000000000000000000000000000";
const REWARDS_CONTRACT = "0x1204700000000000000000000000000000000002";

const currentChain = hardhatArguments.network;

/* ------------------------------------------------------------------------ */
/* Helpers                                                                  */
/* ------------------------------------------------------------------------ */
const toHex = (n) => toQuantity(n); // bigint -> "0x…"

const providerError = (e) =>
    e?.code === "SERVER_ERROR" ||
    e?.code === "CALL_EXCEPTION" ||
    e?.code === -32000 || // Missing state / generic Ethereum JSON-RPC server error
    e?.message?.includes("VM execution error") ||
    e?.message?.includes("No state available");


/* ------------------------------------------------------------------------ */
/* Check functions                                                          */
/* ------------------------------------------------------------------------ */

/**
 * Checks the mintedTotally amounts before the fork block.
 * @param {*} rewardContract - The reward contract instance.
 * @param {*} nbOfBlocksToCheck - Number of blocks to check before the fork.
 */
const checkMintedAmountsBeforeFork = async (rewardContract, nbOfBlocksToCheck) => {
    let lastMintedAmount = 0n;

    for (let i = BLOCK_REWARD_STOP - nbOfBlocksToCheck; i < BLOCK_REWARD_STOP; i++) {

        const totalMinted = BN(await rewardContract.mintedTotally({ blockTag: i }));

        console.log(`\t* On block ${String(i)}: ${ethers.formatEther(String(totalMinted))} EWT`);

        expect(totalMinted).to.be.gte(lastMintedAmount, `${currentChain} mintedTotally at block ${String(i)} is ${String(totalMinted)}; should be > ${String(lastMintedAmount)}`);
        lastMintedAmount = totalMinted;
    }

}

/**
 * Checks the mintedTotally amounts after the fork block.
 * @param {*} rewardContract - The reward contract instance.
 * @param {*} nbOfBlocksToCheck - Number of blocks to check after the fork.
 */
const checkMintedAmountsAfterFork = async (rewardContract, nbOfBlocksToCheck) => {
    let lastMintedAmount = await rewardContract.mintedTotally({ blockTag: BLOCK_REWARD_STOP - 1n });

    for (let i = BLOCK_REWARD_STOP; i < BLOCK_REWARD_STOP + nbOfBlocksToCheck; i++) {

        const totalMinted = await rewardContract.mintedTotally({ blockTag: i });
        const forkMinted = BN(totalMinted);

        console.log(`\t* On block ${String(i)}: ${ethers.formatEther(String(forkMinted))} EWT`);

        expect(forkMinted).to.be.eq(lastMintedAmount, `Fork mintedTotally at block ${String(i)} should be == ${String(lastMintedAmount)}`);
        lastMintedAmount = forkMinted;
    }
}

/* ------------------------------------------------------------------------ */
/* Test Suite                                                               */
/* ------------------------------------------------------------------------ */
describe(`${currentChain.toUpperCase()} FORK VALIDATION TESTS (Block ${BLOCK_REWARD_STOP}):`, function () {
    let provider;

    before(async () => {
        // On hardhat (forking), historical eth_call with blockTag before the fork block may be proxied to the upstream
        // node, which can fail if it's not configured with hardfork activation history. Use a direct RPC provider instead.
        const networkName = (hardhatArguments && hardhatArguments.network) || "hardhat";
        if (networkName === "hardhat") {
            const url = process.env.SFORK_RPC_EWC || process.env.EWC_RPC;
            if (!url) throw new Error("Set SFORK_RPC_EWC or EWC_RPC in your .env for historical reads");
            provider = new ethers.JsonRpcProvider(url);
        } else {
            provider = ethers.provider; // Provided by Hardhat for non-hardhat networks
        }
    });

    describe("\n- Operational/Config checks", function () {

        it("\x1b[34m Validator set in contract is unchanged after the fork \x1b[0m", async function () {
            try {
                const latest = await provider.getBlock("latest");

                const [pre, post] = await Promise.all([
                    provider.call(
                        { to: VALIDATORS_CONTRACT, data: GET_VALIDATORS_SIG },
                        toHex(BLOCK_BEFORE_REWARD_STOP)
                    ),
                    provider.call(
                        { to: VALIDATORS_CONTRACT, data: GET_VALIDATORS_SIG },
                        toHex(latest.number)
                    )
                ]);

                expect(pre.toLowerCase()).to.not.include(
                    NEW_VALIDATOR.slice(2).toLowerCase()
                );
                expect(post.toLowerCase()).to.equal(pre.toLowerCase());
                expect(post).to.not.equal("0x"); // set must be non-empty
            } catch (e) {
                if (providerError(e)) this.skip();   // node is not archive-enabled - historical state unavailable
                else throw e;
            }
        });

        it(`\x1b[34m Rewards contract byte-code changes on the fork block (${BLOCK_REWARD_STOP}) `, async function () {
            try {
                const [codePre, codePost] = await Promise.all([
                    provider.getCode(REWARDS_CONTRACT, toHex(BLOCK_BEFORE_REWARD_STOP)),
                    provider.getCode(REWARDS_CONTRACT, toHex(BLOCK_REWARD_STOP))
                ]);
                expect(codePre).to.not.equal(codePost);
            } catch (e) {
                if (providerError(e)) this.skip();   // node is not archive-enabled - historical state unavailable
                else throw e;
            }
        });

        // This is skipped since it requires a funded account on the mainnedt
        xit("\x1b[34m Rejects replay of a pre-fork transaction on the upgraded chain \x1b[0m", async () => {

            const CHAIN_ID = 246; // EWC Chain ID
            const OLD_TO = process.env.OLD_TO;
            const OLD_NONCE = process.env.OLD_NONCE;
            const OLD_VALUE = ethers.parseEther(process.env.OLD_VALUE);
            const REPLAY_PK = process.env.REPLAY_PK;
            const OLD_GAS_PRICE = ethers.parseUnits(process.env.OLD_GAS_PRICE_IN_GWEI, "gwei");

            if (!REPLAY_PK)
                throw new Error("Set REPLAY_PK or provide RAW_SIGNED_TX to run replay test");

            const wallet = new ethers.Wallet(REPLAY_PK);
            const rawTx = await wallet.signTransaction({
                nonce: OLD_NONCE,
                gasPrice: OLD_GAS_PRICE,
                gasLimit: 21000n,
                to: OLD_TO,
                value: OLD_VALUE,
                data: "0x",
                chainId: CHAIN_ID
            });

            await expect(
                provider.send("eth_sendRawTransaction", [rawTx])
            ).to.be.rejectedWith(/nonce|known|already|underpriced/i);
        });

        it("\x1b[34m Correctly deploys and interacts with a simple Counter contract on the upgraded chain \x1b[0m", async function () {

            try {
                const DEPLOY_PK = process.env.DEPLOY_PK;
                if (!DEPLOY_PK) throw new Error("Set DEPLOY_PK to run this test");

                const deployer = new ethers.Wallet(DEPLOY_PK, provider);

                const CounterFactory = await ethers.getContractFactory("Counter", deployer);

                const counter = await CounterFactory.deploy();

                await counter.deploymentTransaction().wait();

                const counterAddress = await counter.getAddress();
                const code = await provider.getCode(counterAddress);

                if (code === "0x") {
                    throw new Error("Deployment failed: No bytecode at contract address");
                }
                expect(code).to.not.equal("0x");

                const tx = await counter.inc();

                await tx.wait();

                const value = await counter.x();

                expect(value).to.equal(1n);
            } catch (error) {
                console.error("Test failed with error:", error.message);
                if (error.code) console.error("Error code:", error.code);
                if (error.receipt) console.error("Transaction receipt:", error.receipt);
                throw error;
            }
        });
    });


    describe("\n- State consistency validation", function () {

        console.log(`\n\x1b[36m[ Forking block ${BLOCK_REWARD_STOP}]\x1b[0m`);

        const abi = ["function mintedTotally() view returns (uint256)"];
        const nbOfBlocksToCheck = 10n; // Number of blocks to check before and after the fork

        it(`\x1b[34m Before fork, minted Totally increases on ${currentChain}  \x1b[0m`, async () => {
            console.log(`\n \x1b[33m [${currentChain}] MintedTotally: (Checking ${nbOfBlocksToCheck} blocks before fork):\n \x1b[0m`);

            const rewardContract = new ethers.Contract(REWARDS_CONTRACT, abi, provider);
            await checkMintedAmountsBeforeFork(rewardContract, nbOfBlocksToCheck);
        });

        it(`\x1b[34m After fork, mintedTotally \x1b[32mDOES NOT INCREASE\x1b \x1b[34m on ${currentChain} \x1b[0m`, async () => {

            console.log(`\n\x1b[33m [Upgraded ${currentChain}] MintedTotally: (Checking ${nbOfBlocksToCheck} blocks after fork):\n \x1b[0m`);

            const rewardContract = new ethers.Contract(REWARDS_CONTRACT, abi, provider);

            await checkMintedAmountsAfterFork(rewardContract, nbOfBlocksToCheck)
        });
    });

    describe("\n- Bridge contract state validation", function () {
        // For EWC, we'll use the same fork block for bridge validation
        const BLOCK_FORK = BLOCK_REWARD_STOP;
        const BLOCK_PRE_FORK = BLOCK_BEFORE_REWARD_STOP;
        const BLOCK_POST_FORK = BLOCK_FORK;
        
        const bridgeABI = [
            "function owner() view returns (address)",
            "function liftingEnabled() view returns (bool)",
            "function loweringEnabled() view returns (bool)",
        ];
        
        // Use EWC bridge contract address from environment
        const EWC_BRIDGE_CONTRACT = process.env.EWC_BRIDGE_CONTRACT;
        if (!EWC_BRIDGE_CONTRACT) {
            throw new Error("Set EWC_BRIDGE_CONTRACT in your .env file");
        }

        let bridgeContract;

        before(() => {
            bridgeContract = new ethers.Contract(EWC_BRIDGE_CONTRACT, bridgeABI, provider);
        });

        it("The bridge contract owner is the same before and after the fork", async function () {
            try {
                const contractOwnerPre = await bridgeContract.owner({ blockTag: BLOCK_PRE_FORK });
                const contractOwnerPost = await bridgeContract.owner({ blockTag: BLOCK_POST_FORK });

                console.log(`\n\x1b[36m[Bridge owner]\x1b[0m`);

                console.log(`\t\x1b[33m${currentChain}\x1b[0m
                    - Pre-fork: \x1b[32m${contractOwnerPre}\x1b[0m,
                    - Post-fork: \x1b[32m${contractOwnerPost}\x1b[0m

                `);

                expect(contractOwnerPre).to.equal(contractOwnerPost, `${currentChain} owner changed across fork`);
            } catch (e) {
                if (providerError(e)) this.skip();   // node is not archive-enabled - historical state unavailable
                else throw e;
            }
        });

        it(`The bridge contract liftingEnabled is the same on ${currentChain} before and after the fork`, async function () {
            try {
                const liftingPrefork = await bridgeContract.liftingEnabled({ blockTag: BLOCK_PRE_FORK });
                const liftingPostfork = await bridgeContract.liftingEnabled({ blockTag: BLOCK_POST_FORK });

                console.log(`\n\x1b[36m[Bridge liftingEnabled]\x1b[0m`);

                console.log(`\t\x1b[33m${currentChain}\x1b[0m
                    - Pre-fork: \x1b[32m${liftingPrefork}\x1b[0m,
                    - Post-fork: \x1b[32m${liftingPostfork}\x1b[0m
                `);

                expect(liftingPrefork).to.equal(liftingPostfork, `${currentChain} liftingEnabled changed across fork`);
            } catch (e) {
                if (providerError(e)) this.skip();   // node is not archive-enabled - historical state unavailable
                else throw e;
            }
        });

        it("The bridge contract loweringEnabled is the same before and after the fork", async function () {
            try {
                const loweringPrefork = await bridgeContract.loweringEnabled({ blockTag: BLOCK_PRE_FORK });
                const loweringPostfork = await bridgeContract.loweringEnabled({ blockTag: BLOCK_POST_FORK });

                console.log(`\n\x1b[36m[Bridge loweringEnabled]\x1b[0m`);

                console.log(`\t\x1b[33m${currentChain}\x1b[0m
                    - Pre-fork: \x1b[32m${loweringPrefork}\x1b[0m,
                    - Post-fork: \x1b[32m${loweringPostfork}\x1b[0m
                `);

                expect(loweringPrefork).to.equal(loweringPostfork, `${currentChain} loweringEnabled changed across fork`);
            } catch (e) {
                if (providerError(e)) this.skip();   // node is not archive-enabled - historical state unavailable
                else throw e;
            }
        });
    });

})
