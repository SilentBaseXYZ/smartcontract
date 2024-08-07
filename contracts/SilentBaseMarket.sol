// SPDX-License-Identifier: MIT
// Example of creating a pair:
// Source = ETH,
// Destination = DAI,
// Pair = DAI/ETH
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./lib/ABDKMath64x64.sol";
import "./lib/SafeMath.sol";

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract OrderBook is ReentrancyGuard {
    using ABDKMath64x64 for int128;
    using SafeMath for uint256;

    enum Side {
        BUY,
        SELL
    }

    struct Pair {
        string source_name;
        string destination_name;
        address source_contract;
        address destination_contract;
        uint256 created_at;
    }

    struct Order {
        uint256 price;
        uint256 quantity;
        address trader;
        uint256 created_at;
    }

    struct Trade {
        uint256 price;
        uint256 quantity;
        uint256 created_at;
    }

    struct Token {
        string symbol;
        address token_address;
    }

    address public immutable admin;
    
    Token[] public tokenData;
    string[] private listTicker;
    string[] private inActiveTicker;
    mapping(string => bool) private tickerExists;
    mapping(string => bool) private tokenExists;
    mapping(address => mapping(address => uint256)) public traderBalances;
    mapping(address => mapping(address => uint256)) public frozenBalances;
    mapping(string => Pair) public pairData;
    mapping(string => Trade[]) private tradeData;
    mapping(string => Order[]) public bids;
    mapping(string => Order[]) public asks;

    modifier onlyAdmin() {
        require(msg.sender == admin, 'only admin');
        _;
    }
    
    modifier requireActive(string memory ticker) {
        require(!_isInactive(ticker), "Ticker is inactive");
        _;
    }


    event OrderCreated(string ticker, uint256 price, uint256 quantity, Side side, address trader);
    event OrderCancelled(string ticker, uint256 price, uint256 quantity, Side side, address trader);
    event TradeExecuted(uint256 price, uint256 quantity);

    constructor() {
        admin = msg.sender;
    }

    function hasSufficientBalance(string memory ticker, uint256 amount, uint256 price, Side side) internal view {
        address source_contract = pairData[ticker].source_contract;
        address destination_contract = pairData[ticker].destination_contract;
        uint256 requiredAmount;

        if (side == Side.BUY) {
            // Convert price to 64.64 fixed point
            int128 price64x64 = ABDKMath64x64.divu(price, 1 ether);
            // Calculate requiredAmount in ether
            requiredAmount = ABDKMath64x64.mulu(price64x64, amount);
            require(
                traderBalances[msg.sender][source_contract].sub(frozenBalances[msg.sender][source_contract]) >= requiredAmount,
                "Insufficient balance for buy order"
            );
        } else { 
            requiredAmount = amount;
            require(
                traderBalances[msg.sender][destination_contract].sub(frozenBalances[msg.sender][destination_contract]) >= requiredAmount,
                "Insufficient balance for sell order"
            );
        }
    }


    function addToInactive(string memory ticker) public onlyAdmin() {
        require(!_isInactive(ticker), "Ticker already inactive");
        inActiveTicker.push(ticker);
    }

    function removeFromInactive(string memory ticker) public onlyAdmin() {
        uint256 index = _getInactiveIndex(ticker);
        require(index < inActiveTicker.length, "Ticker not found in inactive list");
        inActiveTicker[index] = inActiveTicker[inActiveTicker.length - 1];
        inActiveTicker.pop();
    }

    function _isInactive(string memory ticker) internal view returns (bool) {
        uint256 length = inActiveTicker.length;
        for (uint256 i = 0; i < length; i++) {
            if (keccak256(abi.encodePacked(inActiveTicker[i])) == keccak256(abi.encodePacked(ticker))) {
                return true;
            }
        }
        return false;
    }

    function _getInactiveIndex(string memory ticker) internal view returns (uint) {
        uint256 length = inActiveTicker.length;
        for (uint256 i = 0; i < length; i++) {
            if (keccak256(abi.encodePacked(inActiveTicker[i])) == keccak256(abi.encodePacked(ticker))) {
                return i;
            }
        }
        return inActiveTicker.length;
    }

    function addPair(string memory ticker, address tokenA, address tokenB) onlyAdmin() external {
        string memory source_name;
        string memory destination_name;
        if(tokenA == address(0)){
            source_name = "ETH";
        } else {
            IERC20 a = IERC20(tokenA);
            source_name = a.symbol();
        }
        if(tokenB == address(0)){
            destination_name = "ETH";
        } else {
            IERC20 b = IERC20(tokenB);
            destination_name = b.symbol();
        }

        pairData[ticker] = Pair(source_name, destination_name, tokenA, tokenB, block.timestamp);
        if(!tickerExists[ticker]){
            listTicker.push(ticker);
            tickerExists[ticker] = true;
        }
        if(!tokenExists[source_name]){
            tokenData.push(Token(source_name, tokenA));
            tokenExists[source_name] = true;
        }
        if(!tokenExists[destination_name]){
            tokenData.push(Token(destination_name, tokenB));
            tokenExists[destination_name] = true;
        }
    }

    function deposit(uint256 amount, address tokenContract) external payable nonReentrant {
        uint256 tokenBalance = traderBalances[msg.sender][tokenContract];
        uint256 frozenBalance = frozenBalances[msg.sender][tokenContract];
        if (tokenContract == address(0)) {
            require(msg.value == amount, "Incorrect Ether amount");
            traderBalances[msg.sender][tokenContract] = tokenBalance.add(amount);
            frozenBalances[msg.sender][tokenContract] = frozenBalance.add(0);
        } else {
            traderBalances[msg.sender][tokenContract] += tokenBalance.add(amount);
            frozenBalances[msg.sender][tokenContract] = frozenBalance.add(0);
            require(IERC20(tokenContract).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        }
    }
    
    function withdraw(uint256 amount, address tokenContract) external nonReentrant {
        require(
            (traderBalances[msg.sender][tokenContract].sub(frozenBalances[msg.sender][tokenContract])) >= amount,
            'balance too low'
        ); 
        traderBalances[msg.sender][tokenContract] = traderBalances[msg.sender][tokenContract].sub(amount);
         if(tokenContract == address(0)){
            payable(msg.sender).transfer(amount);
        } else {
            require(IERC20(tokenContract).transfer(msg.sender, amount), "Transfer failed");
        }
    }

    function createLimitOrder(string memory ticker, uint256 amount, uint256 price, Side side) external {
        hasSufficientBalance(ticker, amount, price, side);
        if(side == Side.SELL) {
            addAsk(ticker, price, amount, msg.sender);
        } else {
            addBid(ticker, price, amount, msg.sender);
        }
        freezeBalance(ticker, price, amount, msg.sender, side);
        emit OrderCreated(ticker, price, amount, side, msg.sender);
    }

    function createMarketOrder(string memory ticker, uint256 amount, Side side) external {
        uint256 readyBuyPrice;
        uint256 readySellPrice;
        if(side == Side.SELL) {
            require(bids[ticker].length > 0, "No buy orders available");
            readyBuyPrice = bids[ticker][0].price;
            hasSufficientBalance(ticker, amount, readyBuyPrice, side);
            addAsk(ticker, readyBuyPrice, amount, msg.sender);
            freezeBalance(ticker, readyBuyPrice, amount, msg.sender, side);
            emit OrderCreated(ticker, readyBuyPrice, amount, side, msg.sender);
        } else {
            require(asks[ticker].length > 0, "No sell orders available");
            readySellPrice = asks[ticker][0].price;
            hasSufficientBalance(ticker, amount, readySellPrice, side);
            addBid(ticker, readySellPrice, amount, msg.sender);
            freezeBalance(ticker, readySellPrice, amount, msg.sender, Side.SELL);
            emit OrderCreated(ticker, readySellPrice, amount, side, msg.sender);
        }
        matchOrders(ticker);
    }

    function freezeBalance(string memory ticker, uint256 price, uint256 quantity, address trader, Side side) internal {
        address source_contract = pairData[ticker].source_contract;
        address destination_contract = pairData[ticker].destination_contract;
        if(side == Side.SELL){
            frozenBalances[trader][destination_contract] = frozenBalances[trader][destination_contract].add(quantity);
        } else {
            int128 price64x64 = ABDKMath64x64.fromUInt(price / 1 ether);
            uint256 totalCost = ABDKMath64x64.mulu(price64x64, (quantity / 1 ether)) * 1 ether;
            frozenBalances[trader][source_contract] = frozenBalances[trader][source_contract].add(totalCost);
        }
    }

    function unfreezeBalance(string memory ticker, uint256 price, uint256 quantity, address trader, Side side) internal {
        address source_contract = pairData[ticker].source_contract;
        address destination_contract = pairData[ticker].destination_contract;
        if(side == Side.SELL){
            frozenBalances[trader][destination_contract] = frozenBalances[trader][destination_contract].sub(quantity);
        } else {
            int128 price64x64 = ABDKMath64x64.fromUInt(price / 1 ether);
            uint256 totalCost = ABDKMath64x64.mulu(price64x64, (quantity / 1 ether)) * 1 ether;
            frozenBalances[trader][source_contract] = frozenBalances[trader][source_contract].sub(totalCost);
        }
    }

    // Add a new bid
    function addBid(string memory ticker, uint256 price, uint256 quantity, address trader) internal requireActive(ticker) {
        bids[ticker].push(Order(price, quantity, trader, block.timestamp));
        sortBids(ticker); // Sort bids by descending price
    }

    // Add a new ask
    function addAsk(string memory ticker, uint256 price, uint256 quantity, address trader) internal requireActive(ticker) {
        asks[ticker].push(Order(price, quantity, trader, block.timestamp));
        sortAsks(ticker); // Sort asks by ascending price
    }

    // Sort bids in descending order
    function sortBids(string memory ticker) internal {
        for (uint256 i = 0; i < bids[ticker].length; i++) {
            for (uint256 j = i + 1; j < bids[ticker].length; j++) {
                if (bids[ticker][i].price < bids[ticker][j].price) {
                    (bids[ticker][i], bids[ticker][j]) = (bids[ticker][j], bids[ticker][i]);
                }
            }
        }
    }

    // Sort asks in ascending order
    function sortAsks(string memory ticker) internal {
        for (uint256 i = 0; i < asks[ticker].length; i++) {
            for (uint256 j = i + 1; j < asks[ticker].length; j++) {
                if (asks[ticker][i].price > asks[ticker][j].price) {
                    (asks[ticker][i], asks[ticker][j]) = (asks[ticker][j], asks[ticker][i]);
                }
            }
        }
    }

    // Match orders
    function matchOrders(string memory ticker) requireActive(ticker) public {
        while (bids[ticker].length > 0 && asks[ticker].length > 0) {
            Order storage highestBid = bids[ticker][0];
            Order storage lowestAsk = asks[ticker][0];

            if (highestBid.price >= lowestAsk.price) {
                uint256 tradeQuantity = min(highestBid.quantity, lowestAsk.quantity);

                // Emit trade event
                emit TradeExecuted(lowestAsk.price, tradeQuantity);
                tradeData[ticker].push(Trade(lowestAsk.price, tradeQuantity, block.timestamp));

                // Update quantities
                highestBid.quantity = highestBid.quantity.sub(tradeQuantity);
                lowestAsk.quantity = lowestAsk.quantity.sub(tradeQuantity);

                // Update trader balances
                updateTraderBalances(ticker, highestBid.trader, lowestAsk.trader, lowestAsk.price, tradeQuantity);

                // Unfreeze balances
                unfreezeBalance(ticker, lowestAsk.price, tradeQuantity, lowestAsk.trader, Side.SELL);
                unfreezeBalance(ticker, highestBid.price, tradeQuantity, highestBid.trader, Side.BUY);

                // Remove fully filled orders
                if (highestBid.quantity == 0) {
                    removeBid(ticker, 0);
                }
                if (lowestAsk.quantity == 0) {
                    removeAsk(ticker, 0);
                }
            } else {
                break; // No more matching possible
            }
        }
    }

    // Cancel an order by ID (created_at)
    function cancelOrderById(string memory ticker, Side side, uint256 orderId) external {
        require(!_isInactive(ticker), "Ticker is inactive");
        Order[] storage orders = side == Side.BUY ? bids[ticker] : asks[ticker];
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].created_at == orderId && orders[i].trader == msg.sender) {
                emit OrderCancelled(ticker, orders[i].price, orders[i].quantity, side, msg.sender);
                unfreezeBalance(ticker, orders[i].price, orders[i].quantity, msg.sender, side);
                removeOrder(ticker, side, i);
                break;
            }
        }
    }

    // Remove bid at index
    function removeBid(string memory ticker, uint256 index) internal {
        require(index < bids[ticker].length, "Index out of bounds");
        for (uint256 i = index; i < bids[ticker].length - 1; i++) {
            bids[ticker][i] = bids[ticker][i + 1];
        }
        bids[ticker].pop();
    }

    // Remove ask at index
    function removeAsk(string memory ticker, uint256 index) internal {
        require(index < asks[ticker].length, "Index out of bounds");
        for (uint256 i = index; i < asks[ticker].length - 1; i++) {
            asks[ticker][i] = asks[ticker][i + 1];
        }
        asks[ticker].pop();
    }

    // Remove an order by index
    function removeOrder(string memory ticker, Side side, uint256 index) internal {
        if (side == Side.BUY) {
            bids[ticker][index] = bids[ticker][bids[ticker].length - 1];
            bids[ticker].pop();
        } else {
            asks[ticker][index] = asks[ticker][asks[ticker].length - 1];
            asks[ticker].pop();
        }
    }

    // Get minimum of two values
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function updateTraderBalances(string memory ticker, address buyer, address seller, uint256 price, uint256 quantity) internal {
        address source_contract = pairData[ticker].source_contract;
        address destination_contract = pairData[ticker].destination_contract;
        uint256 totalDestinationAmount = quantity;
        int128 price64x64 = ABDKMath64x64.fromUInt(price / 1 ether);
        uint256 totalSourceAmount = ABDKMath64x64.mulu(price64x64, (quantity / 1 ether)) * 1 ether;
        traderBalances[buyer][source_contract] = traderBalances[buyer][source_contract].sub(totalSourceAmount);
        traderBalances[buyer][destination_contract] = traderBalances[buyer][destination_contract].add(totalDestinationAmount);
        traderBalances[seller][source_contract] = traderBalances[seller][source_contract].add(totalSourceAmount);
        traderBalances[seller][destination_contract] = traderBalances[seller][destination_contract].sub(totalDestinationAmount);
    }

    function getTradeStats(string memory ticker, uint256 startTimestamp, uint256 endTimestamp) public view returns (uint256 averagePrice, uint256 totalVolume, uint256 lowPrice, uint256 highPrice) {
        uint256 sumPrice = 0;
        uint256 count = 0;
        lowPrice = type(uint256).max;
        highPrice = 0;

        for (uint256 i = 0; i < tradeData[ticker].length; i++) {
            Trade memory trade = tradeData[ticker][i];
            if (trade.created_at >= startTimestamp && trade.created_at <= endTimestamp) {
                sumPrice +=  ABDKMath64x64.mulu(ABDKMath64x64.fromUInt(trade.price / 1 ether), (trade.quantity / 1 ether)) * 1 ether;
                totalVolume += trade.quantity;
                if (trade.price < lowPrice) {
                    lowPrice = trade.price;
                }
                if (trade.price > highPrice) {
                    highPrice = trade.price;
                }
                count++;
            }
        }

        if (count > 0) {
            averagePrice = sumPrice / totalVolume;
        } else {
            averagePrice = 0;
            lowPrice = 0;
            highPrice = 0;
        }
    }

    function getCurrentPrice(string memory ticker, Side side) public view returns (uint256) {
        if (side == Side.BUY) {
            if (bids[ticker].length > 0) {
                return bids[ticker][0].price;
            } else {
                return 0; // No bids available
            }
        } else if (side == Side.SELL) {
            if (asks[ticker].length > 0) {
                return asks[ticker][0].price;
            } else {
                return 0; // No asks available
            }
        } else {
            revert("Invalid side");
        }
    }

    function lastPrice(string memory ticker) external view requireActive(ticker) returns (uint256) {
        require(tradeData[ticker].length > 0, "No trades found for ticker");
        return tradeData[ticker][tradeData[ticker].length.sub(1)].price;
    }

    function getBids(string memory ticker) public view returns (Order[] memory) {
        return bids[ticker];
    }

    function getAsks(string memory ticker) public view returns (Order[] memory) {
        return asks[ticker];
    }

    function tradeHistory(string memory ticker) external view returns (Trade[] memory) {
        return tradeData[ticker];
    }

    function listTokens() external view returns (Token[] memory) {
        return tokenData;
    }

    function listPairs() external view returns (string[] memory) {
        return listTicker;
    }

    fallback() external payable {}

    receive() external payable {}
}
