const SBTToken = artifacts.require("SBTToken");
const { expectRevert, expectEvent } = require('@openzeppelin/test-helpers');

contract("SBTToken", accounts => {
  const [admin, user, other] = accounts;
  let token;

  beforeEach(async () => {
    const federationAddress = admin;
    token = await SBTToken.new(federationAddress);
  });

  it("should deploy the contract and check initial values", async () => {
    const name = await token.name();
    const symbol = await token.symbol();
    assert.equal(name, "Silent Base Token", "Token name should be 'Silent Base Token'");
    assert.equal(symbol, "SBT", "Token symbol should be 'SBT'");
  });

  it("should mint tokens and transfer them", async () => {
    await token.assignRole(web3.utils.keccak256("MINTER"), admin);
    await token.mintTokens(user, web3.utils.toWei('100', 'ether'));

    const balance = await token.balanceOf(user);
    assert.equal(balance.toString(), web3.utils.toWei('100', 'ether'), "User should have 100 tokens");
  });

  it("should assign and revoke roles", async () => {
    await token.assignRole(web3.utils.keccak256("TEST_ROLE"), user);
    let hasRole = await token.hasRole(web3.utils.keccak256("TEST_ROLE"), user);
    assert.equal(hasRole, true, "User should have TEST_ROLE");

    await token.revokeRole(web3.utils.keccak256("TEST_ROLE"), user);
    hasRole = await token.hasRole(web3.utils.keccak256("TEST_ROLE"), user);
    assert.equal(hasRole, false, "User should not have TEST_ROLE anymore");
  });

  it("should allow users to deposit and claim tokens", async () => {
    // Mock token transfer for the test
    await token.mintTokens(user, web3.utils.toWei('100', 'ether'));
    await token.approve(token.address, web3.utils.toWei('100', 'ether'), { from: user });
    await token.depositTokens(token.address, web3.utils.toWei('50', 'ether'), Math.floor(Date.now() / 1000), { from: user });
 
    const dataPack = web3.utils.soliditySha3(
      { type: 'string', value: 'BRIDGEX-' + user.toLowerCase() },
      { type: 'string', value: 'sourceChainID' },
      { type: 'string', value: 'target_chainID' },
      { type: 'string', value: 'sourceContract' },
      { type: 'string', value: 'targetContract' },
      { type: 'string', value: 'SBT' },
      { type: 'string', value: '18' },
      { type: 'string', value: '50' },
      { type: 'string', value: Math.floor(Date.now() / 1000).toString() }
    );

    const signature = await web3.eth.sign(dataPack, admin);
    await token.claimTokens(
      'sourceChainID',
      'sourceContract',
      'targetContract',
      'SBT',
      '18',
      '50',
      Math.floor(Date.now() / 1000).toString(),
      signature,
      { from: user }
    );

    const newBalance = await token.balanceOf(user);
    assert.equal(newBalance.toString(), web3.utils.toWei('50', 'ether'), "User should have received 50 tokens");
  });
});
