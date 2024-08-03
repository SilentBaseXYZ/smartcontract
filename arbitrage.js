const { ethers } = require('ethers');

// Define the contract ABI
const IUniswapV2PairABI = [
    "function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)"
];

const USDC_DECIMAL = BigInt(1_000_000); // 6 decimals for USDC
const ETH_DECIMAL = BigInt(1_000_000_000_000_000_000); // 18 decimals for ETH

// Initialize provider
const provider = new ethers.JsonRpcProvider("https://eth.llamarpc.com");

// Function to create a Uniswap pair
const createPair = (address) => {
    return new ethers.Contract(address, IUniswapV2PairABI, provider);
};

// Function to print reserves
const printReserves = async (pair, name) => {
    const [reserve0, reserve1, blockTimestampLast] = await pair.getReserves();
    console.log(`Reserves in ${name} (Token1, Token2): ${reserve0}, ${reserve1}`);
    return { reserve0: BigInt(reserve0), reserve1: BigInt(reserve1) };
};

// Function to calculate price
const calculatePrice = (reservesUSDC, reservesWETH) => {
    return Number(reservesUSDC) / Number(USDC_DECIMAL) / (Number(reservesWETH) / Number(ETH_DECIMAL));
};

const main = async () => {
    try {
        const uniswapPair = createPair("0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc");
        const sushiswapPair = createPair("0x397ff1542f962076d0bfe58ea045ffa2d347aca0");

        const { reserve0: reservesUSDCUniswap, reserve1: reservesWETHUniswap } = await printReserves(uniswapPair, "Uniswap");
        const { reserve0: reservesUSDCSushiswap, reserve1: reservesWETHSushiswap } = await printReserves(sushiswapPair, "Sushiswap");

        const uniswapPrice = calculatePrice(reservesUSDCUniswap, reservesWETHUniswap);
        const sushiswapPrice = calculatePrice(reservesUSDCSushiswap, reservesWETHSushiswap);
        console.log(`Uniswap WETH price: ${uniswapPrice} USDC \nSushiswap WETH price: ${sushiswapPrice} USDC`);

        const feeRatio = 0.997; // Uniswap-Sushiswap fixed %0.3 fee (1-r)
        if (uniswapPrice < sushiswapPrice) {
            const exchangeAmountUniswap = Number(reservesWETHUniswap) * Number(reservesUSDCSushiswap) / (Number(reservesUSDCSushiswap) * feeRatio + Number(reservesUSDCUniswap));
            const exchangeAmountSushiswap = Number(reservesUSDCUniswap) * Number(reservesWETHSushiswap) / (Number(reservesUSDCSushiswap) + Number(reservesUSDCUniswap) * feeRatio);

            const optimalDelta = Math.sqrt(exchangeAmountSushiswap * exchangeAmountUniswap * feeRatio) - exchangeAmountSushiswap;
            console.log(`Optimal Delta (Buy Uniswap, sell Sushiswap): ${optimalDelta / Number(ETH_DECIMAL)} WETH`);
        } else {
            const exchangeAmountSushiswap = Number(reservesWETHSushiswap) * Number(reservesUSDCUniswap) / (Number(reservesUSDCUniswap) * feeRatio + Number(reservesUSDCSushiswap));
            const exchangeAmountUniswap = Number(reservesUSDCSushiswap) * Number(reservesWETHUniswap) / (Number(reservesUSDCUniswap) + Number(reservesUSDCSushiswap) * feeRatio);

            const optimalDelta = Math.sqrt(exchangeAmountUniswap * exchangeAmountSushiswap * feeRatio) - exchangeAmountUniswap;
            console.log(`Optimal Delta (Buy Sushiswap, sell Uniswap): ${optimalDelta / Number(ETH_DECIMAL)} WETH`);
        }
    } catch (error) {
        console.error("Error:", error);
    }
};

main();
