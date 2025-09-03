require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { EWC_RPC } = process.env;

module.exports = {
  solidity: "0.8.23",
  networks: {
    ewc: { url: EWC_RPC},
  },
};
