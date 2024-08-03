const OrderBook = artifacts.require("OrderBook");
const { expectRevert, expectEvent } = require('@openzeppelin/test-helpers');

contract('OrderBook', accounts => {
  const [admin, trader1, trader2] = accounts;
  let orderBook;

  beforeEach(async () => {
    orderBook = await OrderBook.new({ from: admin });
  });

  it('should deploy the contract and set admin correctly', async () => {
    const adminAddress = await orderBook.admin();
    assert.equal(adminAddress, admin, 'Admin address should be the deployer address');
  });

  it('should allow admin to add a pair', async () => {
    const tokenA = '0x0000000000000000000000000000000000000000';
    const tokenB = '0x0000000000000000000000000000000000000002';
    const ticker = 'ETH/USDT';

    await orderBook.addPair(ticker, tokenA, tokenB, { from: admin });

    const pair = await orderBook.pairs(ticker);
    assert.equal(pair.source_contract, tokenA, 'Source contract address should match');
    assert.equal(pair.destination_contract, tokenB, 'Destination contract address should match');
  });

  it('should allow trader to deposit and withdraw ETH', async () => {
    const depositAmount = web3.utils.toWei('1', 'ether');
    
    // Deposit ETH
    await orderBook.deposit(depositAmount, '0x0000000000000000000000000000000000000000', { from: trader1, value: depositAmount });
    
    const balance = await orderBook.traderBalances(trader1, '0x0000000000000000000000000000000000000000');
    assert.equal(balance.toString(), depositAmount, 'Trader balance should be equal to deposit amount');

    // Withdraw ETH
    await orderBook.withdraw(depositAmount, '0x0000000000000000000000000000000000000000', { from: trader1 });
    
    const newBalance = await orderBook.traderBalances(trader1, '0x0000000000000000000000000000000000000000');
    assert.equal(newBalance.toString(), '0', 'Trader balance should be zero after withdrawal');
  });

  it('should allow trader to create and cancel orders', async () => {
    const ticker = 'ETH/USDT';
    const price = web3.utils.toWei('2000', 'ether');
    const quantity = web3.utils.toWei('1', 'ether');

    // Add a pair
    const tokenA = '0x0000000000000000000000000000000000000001';
    const tokenB = '0x0000000000000000000000000000000000000002';
    await orderBook.addPair(ticker, tokenA, tokenB, { from: admin });

    // Create a limit order
    await orderBook.createLimitOrder(ticker, quantity, price, 0, { from: trader1 });

    // Check if the order is created
    const bids = await orderBook.getBids(ticker);
    assert.equal(bids.length, 1, 'There should be one bid order');
    
    // Cancel order
    await orderBook.cancelOrderById(ticker, 0, bids[0].created_at, { from: trader1 });
    
    const updatedBids = await orderBook.getBids(ticker);
    assert.equal(updatedBids.length, 0, 'There should be no bid orders left after cancellation');
  });

  it('should execute a trade between matching bids and asks', async () => {
    const ticker = 'ETH/USDT';
    const price = web3.utils.toWei('2000', 'ether');
    const quantity = web3.utils.toWei('1', 'ether');

    // Add a pair
    const tokenA = '0x0000000000000000000000000000000000000001';
    const tokenB = '0x0000000000000000000000000000000000000002';
    await orderBook.addPair(ticker, tokenA, tokenB, { from: admin });

    // Create bid and ask orders
    await orderBook.createLimitOrder(ticker, quantity, price, 0, { from: trader1 });
    await orderBook.createLimitOrder(ticker, quantity, price, 1, { from: trader2 });

    // Match orders
    await orderBook.matchOrders(ticker);

    // Check trade data
    const trades = await orderBook.tradeData(ticker);
    assert.equal(trades.length, 1, 'There should be one trade executed');
    assert.equal(trades[0].price, price, 'Trade price should match');
    assert.equal(trades[0].quantity, quantity, 'Trade quantity should match');
  });
});
