const SBTToken = artifacts.require("SBTToken");
require('dotenv').config();

module.exports = function (deployer) {
  const federationAddress = process.env.FEDERATION_ADDRESS;
  if (!federationAddress) {
    throw new Error("FEDERATION_ADDRESS not found in .env file");
  }

  deployer.deploy(SBTToken, federationAddress);
};
