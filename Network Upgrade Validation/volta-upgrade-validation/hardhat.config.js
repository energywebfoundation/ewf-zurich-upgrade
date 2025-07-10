require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { VOLTA_RPC } = process.env;

module.exports = {
  solidity: "0.8.23",
  networks: {
    volta: { url: VOLTA_RPC},
  },
};
