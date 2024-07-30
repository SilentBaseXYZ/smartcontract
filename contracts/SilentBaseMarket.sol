// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

contract OrderBook {
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
        uint256 updated_at;
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

    address public admin;
    
    Token[] public listToken;
    string[] private listTicker;
    string[] private inActiveTicker;
    mapping(string => bool) private tickerExists;
    mapping(string => bool) private tokenExists;
    mapping(address => mapping(address => uint256)) public traderBalances;
    mapping(string => Pair) public pairs;
    mapping(string => Trade[]) public trade_data;
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

    event TradeExecuted(uint256 price, uint256 quantity);

    constructor() {
        admin = msg.sender;
    }

    function addToInactive(string memory ticker) public onlyAdmin() {
        require(!_isInactive(ticker), "Ticker already inactive");
        inActiveTicker.push(ticker);
    }

    function removeFromInactive(string memory ticker) public onlyAdmin() {
        uint index = _getInactiveIndex(ticker);
        require(index < inActiveTicker.length, "Ticker not found in inactive list");
        inActiveTicker[index] = inActiveTicker[inActiveTicker.length - 1];
        inActiveTicker.pop();
    }

    function _isInactive(string memory ticker) internal view returns (bool) {
        for (uint i = 0; i < inActiveTicker.length; i++) {
            if (keccak256(abi.encodePacked(inActiveTicker[i])) == keccak256(abi.encodePacked(ticker))) {
                return true;
            }
        }
        return false;
    }

    function _getInactiveIndex(string memory ticker) internal view returns (uint) {
        for (uint i = 0; i < inActiveTicker.length; i++) {
            if (keccak256(abi.encodePacked(inActiveTicker[i])) == keccak256(abi.encodePacked(ticker))) {
                return i;
            }
        }
        return inActiveTicker.length;
    }

    function addPairs(string memory ticker, address token_a, address token_b) onlyAdmin() external {
        string memory source_name;
        string memory destination_name;
        if(token_a == address(0)){
            source_name = "ETH";
        } else {
            IERC20 a = IERC20(token_a);
            source_name = a.symbol();
        }
        if(token_b == address(0)){
            destination_name = "ETH";
        } else {
            IERC20 b = IERC20(token_a);
            destination_name = b.symbol();
        }

    
        pairs[ticker] = Pair(source_name, destination_name, token_a, token_b, block.timestamp);
        if(!tickerExists[ticker]){
            listTicker.push(ticker);
            tickerExists[ticker] = true;
        }
        if(!tokenExists[source_name]){
            listToken.push(Token(source_name, token_a));
            tokenExists[source_name] = true;
        }
        if(!tokenExists[destination_name]){
            listToken.push(Token(destination_name, token_b));
            tokenExists[destination_name] = true;
        }
    }

    function deposit(uint amount, address token_contract) external payable {
        if(token_contract == address(0)){
           require(msg.value == amount, "Incorrect Ether amount");
        } else {
            IERC20(token_contract).transferFrom(
                msg.sender,
                address(this),
                amount
            );
        }
        traderBalances[msg.sender][token_contract] += amount;
    }
    
    function withdraw(uint amount, address token_contract) external {
        require(
            traderBalances[msg.sender][token_contract] >= amount,
            'balance too low'
        ); 
        traderBalances[msg.sender][token_contract] -= amount;
         if(token_contract == address(0)){
             payable(msg.sender).transfer(amount);
        } else {
            IERC20(token_contract).transfer(msg.sender, amount);
        }
    }

    function createLimitOrder(string memory ticker, uint256 amount, uint256 price, Side side) external {
        if(side == Side.SELL) {
            addAsk(ticker, price, amount, msg.sender);
         } else {
            addBid(ticker, price, amount, msg.sender);
         }
    }

    function createMarketOrder(string memory ticker, uint256 amount, Side side) external {
        uint256 readyBuyPrice;
        uint256 readySellPrice;
         if(side == Side.SELL) {
            require(bids[ticker].length > 0, "No buy orders available");
            readyBuyPrice = bids[ticker][0].price;
            addAsk(ticker, readyBuyPrice, amount, msg.sender);
         } else {
            require(asks[ticker].length > 0, "No sell orders available");
            readySellPrice = asks[ticker][0].price;
            addBid(ticker, readySellPrice, amount, msg.sender);
         }
        matchOrders(ticker);
    }

    // Add a new bid
    function addBid(string memory ticker, uint256 price, uint256 quantity, address trader) internal requireActive(ticker) {
        bids[ticker].push(Order(price, quantity, trader, block.timestamp, 0));
        sortBids(ticker); // Sort bids by descending price
    }

    // Add a new ask
    function addAsk(string memory ticker, uint256 price, uint256 quantity, address trader) internal requireActive(ticker) {
        asks[ticker].push(Order(price, quantity, trader, block.timestamp, 0));
        sortAsks(ticker); // Sort asks by ascending price
    }

    // Sort bids in descending order
    function sortBids(string memory ticker) internal {
        for (uint i = 0; i < bids[ticker].length; i++) {
            for (uint j = i + 1; j < bids[ticker].length; j++) {
                if (bids[ticker][i].price < bids[ticker][j].price) {
                    (bids[ticker][i], bids[ticker][j]) = (bids[ticker][j], bids[ticker][i]);
                }
            }
        }
    }

    // Sort asks in ascending order
    function sortAsks(string memory ticker) internal {
        for (uint i = 0; i < asks[ticker].length; i++) {
            for (uint j = i + 1; j < asks[ticker].length; j++) {
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
                trade_data[ticker].push(Trade(lowestAsk.price, tradeQuantity, block.timestamp));

                // Update quantities
                highestBid.quantity -= tradeQuantity;
                lowestAsk.quantity -= tradeQuantity;

                // Update trader balances
                updateTraderBalances(ticker, highestBid.trader, lowestAsk.trader, lowestAsk.price, tradeQuantity);

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

    // Remove bid at index
    function removeBid(string memory ticker, uint256 index) internal {
        require(index < bids[ticker].length, "Index out of bounds");
        for (uint i = index; i < bids[ticker].length - 1; i++) {
            bids[ticker][i] = bids[ticker][i + 1];
        }
        bids[ticker].pop();
    }

    // Remove ask at index
    function removeAsk(string memory ticker, uint256 index) internal {
        require(index < asks[ticker].length, "Index out of bounds");
        for (uint i = index; i < asks[ticker].length - 1; i++) {
            asks[ticker][i] = asks[ticker][i + 1];
        }
        asks[ticker].pop();
    }

    // Get minimum of two values
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function updateTraderBalances(string memory ticker, address buyer, address seller, uint256 price, uint256 quantity) internal {
        address source_contract = pairs[ticker].source_contract;
        address destination_contract = pairs[ticker].destination_contract;
        
        uint256 totalDestinationAmount = quantity;
        uint256 totalSourceAmount = price * quantity;

        traderBalances[buyer][source_contract] -= totalSourceAmount;
        traderBalances[seller][destination_contract] += totalDestinationAmount;
 
    }

    function getTradeStats(string memory ticker, uint256 startTimestamp, uint256 endTimestamp) public view returns (uint256 averagePrice, uint256 totalVolume, uint256 lowPrice, uint256 highPrice) {
        uint256 sumPrice = 0;
        uint256 count = 0;
        lowPrice = type(uint256).max;  // Initialize to maximum possible value
        highPrice = 0;

        for (uint i = 0; i < trade_data[ticker].length; i++) {
            Trade memory trade = trade_data[ticker][i];
            if (trade.created_at >= startTimestamp && trade.created_at <= endTimestamp) {
                sumPrice += trade.price * trade.quantity;
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
        require(trade_data[ticker].length > 0, "No trades found for ticker");
        return trade_data[ticker][trade_data[ticker].length - 1].price;
    }

    function getBids(string memory ticker) public view returns (Order[] memory) {
        return bids[ticker];
    }

    function getAsks(string memory ticker) public view returns (Order[] memory) {
        return asks[ticker];
    }

    receive() external payable {}
}
