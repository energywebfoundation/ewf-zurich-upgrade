require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { VOLTA_RPC, SFORK_RPC_OPEN_ETHEREUM, SFORK_RPC_NEVERMIND } = process.env;

module.exports = {
  solidity: "0.8.23",
  networks: {
    volta:      { url: VOLTA_RPC},
    shadowfork: { url: SFORK_RPC_OPEN_ETHEREUM  || SFORK_RPC_NEVERMIND},
    shadowforkOE: { url: SFORK_RPC_OPEN_ETHEREUM },
    shadowforkNM: { url: SFORK_RPC_NEVERMIND }
  },
};
