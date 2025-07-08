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

const BLOCK_REWARD_STOP = BN(32597900);
const BLOCK_BEFORE_REWARD_STOP = BN(32597899);

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
    e?.message?.includes("VM execution error");

/* ------------------------------------------------------------------------ */
/* Test Suite                                                               */
/* ------------------------------------------------------------------------ */
describe("VOLTA SHADOW-FORK VALIDATION TESTS :", function () {
    let provider;

    before(() => {
        provider = ethers.provider; // This is the provider created by Hardhat (in hardhat.config) for --network volta
    });

    describe("\n- Operational/Config checks", function () {

        it("\x1b[34m Validator set in contract is unchanged after the fork \x1b[0m", async function () {
            try {
                const latest = await provider.getBlock("latest");

                const [pre, post] = await Promise.all([
                    provider.call(
                        { to: VALIDATORS_CONTRACT, data: GET_VALIDATORS_SIG },
                        // toHex(BLOCK_BEFORE_VALIDATOR_SWITCH)
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

        it("\x1b[34m Rewards contract byte-code changes on the fork block (31824620) ", async function () {
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

        it("\x1b[34m Rejects replay of a pre-fork transaction on the upgraded chain \x1b[0m", async () => {

            const CHAIN_ID = 73799;
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

        it("\x1b[34m Deploys and interacts with a simple Counter contract on the upgraded chain \x1b[0m", async function () {

            try {
                const DEPLOY_PK = process.env.DEPLOY_PK;
                if (!DEPLOY_PK) throw new Error("Set DEPLOY_PK to run this test");

                const deployer = new ethers.Wallet(DEPLOY_PK, provider);

                const deployerAddress = await deployer.getAddress();

                const nonce = await provider.getTransactionCount(deployerAddress);

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
        const nbOfBlocksToCheck = 10n; // Number of blocks to check before and after the fork

        const abi = ["function mintedTotally() view returns (uint256)"];

        it(`\x1b[34m Before fork, minted Totally increases on ${currentChain}  \x1b[0m`, async () => {
            let lastMintedAmount = 0n;
            console.log(`\n \x1b[33m [${currentChain}] MintedTotally: (Checking ${nbOfBlocksToCheck} blocks before fork):\n \x1b[0m`);

            const contract = new ethers.Contract(REWARDS_CONTRACT, abi, provider);
            for (let i = BLOCK_REWARD_STOP - nbOfBlocksToCheck; i < BLOCK_REWARD_STOP; i++) {

                const totalMinted = BN(await contract.mintedTotally({ blockTag: i }));

                console.log(`\t* On block ${String(i)}: ${ethers.formatEther(String(totalMinted))} EWT`);

                expect(totalMinted).to.be.gte(lastMintedAmount, `${currentChain} mintedTotally at block ${String(i)} is ${String(totalMinted)}; should be > ${String(lastMintedAmount)}`);
                lastMintedAmount = totalMinted;
            }
        });

        it("\x1b[34m Before fork, minted Totally increases on forked chain\x1b[0m", async () => {
            console.log(`\n \x1b[33m [Fork] MintedTotally: (Checking ${nbOfBlocksToCheck} blocks before fork):\n \x1b[0m`);

            let lastMintedAmount = 0n;
            const contract = new ethers.Contract(REWARDS_CONTRACT, abi, provider);

            for (let i = BLOCK_REWARD_STOP - nbOfBlocksToCheck; i < BLOCK_REWARD_STOP; i++) {

                const totalMinted = await contract.mintedTotally({ blockTag: i });

                const forkMinted = BN(totalMinted);

                console.log(`\t* On block ${String(i)}: ${ethers.formatEther(String(forkMinted))} EWT`);

                expect(forkMinted).to.be.gte(lastMintedAmount, `Volta mintedTotally at block ${String(i)} is ${String(forkMinted)}; should be > ${String(lastMintedAmount)}`);

                lastMintedAmount = forkMinted;
            }
        });

        it("\x1b[34m After fork, mintedTotally still increases on Volta \x1b[0m", async () => {
            let lastMintedAmount = 0n;
            console.log(`\n\x1b[33m[Volta] MintedTotally: (Checking ${nbOfBlocksToCheck} blocks after fork):\n \x1b[0m`);

            const contract = new ethers.Contract(REWARDS_CONTRACT, abi, provider);
            for (let i = BLOCK_REWARD_STOP; i < BLOCK_REWARD_STOP + nbOfBlocksToCheck; i++) {

                const totalMinted = await contract.mintedTotally({ blockTag: i });

                const voltaMinted = BN(totalMinted);

                console.log(`\t* On block ${String(i)}: ${ethers.formatEther(String(voltaMinted))} EWT`);

                expect(voltaMinted).to.be.gte(lastMintedAmount, `Volta mintedTotally at block ${String(i)} should be > ${String(lastMintedAmount)}`);
                lastMintedAmount = voltaMinted;
            }
        });

        it("\x1b[34m After fork, mintedTotally \x1b[32mDOES NOT INCREASE\x1b \x1b[34m on Shadow Fork \x1b[0m", async () => {

            console.log(`\n\x1b[33m [Fork] MintedTotally: (Checking ${nbOfBlocksToCheck} blocks after fork):\n \x1b[0m`);
            const contract = new ethers.Contract(REWARDS_CONTRACT, abi, provider);
            let lastMintedAmount = await contract.mintedTotally({ blockTag: BLOCK_REWARD_STOP - 1n });
            for (let i = BLOCK_REWARD_STOP; i < BLOCK_REWARD_STOP + nbOfBlocksToCheck; i++) {

                const totalMinted = await contract.mintedTotally({ blockTag: i });
                const forkMinted = BN(totalMinted);

                console.log(`\t* On block ${String(i)}: ${ethers.formatEther(String(forkMinted))} EWT`);

                expect(forkMinted).to.be.eq(lastMintedAmount, `Fork mintedTotally at block ${String(i)} should be == ${String(lastMintedAmount)}`);
                lastMintedAmount = forkMinted;
            }
        });
    });

    describe("\n- Bridge contract state validation", function () {
        const BLOCK_FORK = BN(31824620);
        const BLOCK_PRE_FORK = BN(31824619);
        const BLOCK_POST_FORK = BLOCK_FORK;
        const bridgeABI = [
            "function owner() view returns (address)",
            "function liftingEnabled() view returns (bool)",
            "function loweringEnabled() view returns (bool)",
        ];
        const PEX_BRIDGE_CONTRACT = process.env.PEX_BRIDGE_CONTRACT;
        if (!PEX_BRIDGE_CONTRACT) {
            throw new Error("Set BRIDGE_CONTRACT in your .env file");
        }

        let bridgeContract;

        before(() => {
            bridgeContract = new ethers.Contract(PEX_BRIDGE_CONTRACT, bridgeABI, provider);
        });

        it("The bridge contract owner is the same before and after the fork", async function () {
            const contractOwnerPre = await bridgeContract.owner({ blockTag: BLOCK_PRE_FORK });
            const contractOwnerPost = await bridgeContract.owner({ blockTag: BLOCK_POST_FORK });

            console.log(`\n\x1b[36m[Bridge owner]\x1b[0m`);

            console.log(`\t\x1b[33mVolta\x1b[0m
                - Pre-fork: \x1b[32m${contractOwnerPre}\x1b[0m,
                - Post-fork: \x1b[32m${contractOwnerPost}\x1b[0m

            `);

            expect(contractOwnerPre).to.equal(contractOwnerPost, "Volta owner changed across fork");
        });

        it("The bridge contract liftingEnabled is the same on both Volta and Shadow Fork before and after the fork", async function () {
            const liftingVoltaPre = await bridgeContract.liftingEnabled({ blockTag: BLOCK_PRE_FORK });
            const liftingVoltaPost = await bridgeContract.liftingEnabled({ blockTag: BLOCK_POST_FORK });

            console.log(`\n\x1b[36m[Bridge liftingEnabled]\x1b[0m`);

            console.log(`\t\x1b[33mVolta\x1b[0m
                - Pre-fork: \x1b[32m${liftingVoltaPre}\x1b[0m,
                - Post-fork: \x1b[32m${liftingVoltaPost}\x1b[0m
            `);

            expect(liftingVoltaPre).to.equal(liftingVoltaPost, "Volta liftingEnabled changed across fork");
        });

        it("The bridge contract loweringEnabled is the same after the fork", async function () {
            const loweringVoltaPre = await bridgeContract.loweringEnabled({ blockTag: BLOCK_PRE_FORK });
            const loweringVoltaPost = await bridgeContract.loweringEnabled({ blockTag: BLOCK_POST_FORK });

            console.log(`\n\x1b[36m[Bridge loweringEnabled]\x1b[0m`);

            console.log(`\t\x1b[33mVolta\x1b[0m
                - Pre-fork: \x1b[32m${loweringVoltaPre}\x1b[0m,
                - Post-fork: \x1b[32m${loweringVoltaPost}\x1b[0m
            `);

            expect(loweringVoltaPre).to.equal(loweringVoltaPost, "Volta loweringEnabled changed across fork");
        });
    });

})
