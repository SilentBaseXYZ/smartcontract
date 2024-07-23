// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

library StringsUtil {
    /**
     * @notice Converts a string to lowercase.
     *
     * This function iterates over each character of the input string and checks if it falls within the ASCII range
     * for uppercase letters (from 0x41 ('A') to 0x5A ('Z')). If it does, it converts that character to lowercase by adding 32.
     * The result is then returned as a new string.
     *
     * @param str The input string to be converted to lowercase.
     *
     * @return A new string with all uppercase characters in the original string replaced with their corresponding lowercase counterparts.
     */
    function toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);

        for (uint256 i = 0; i < bStr.length; i++) {
            if ((bStr[i] >= 0x41) && (bStr[i] <= 0x5A)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }

        return string(bLower);
    }

    /**
     * @notice Converts a bytes32 data value into hexadecimal string format.
     *
     * This function iterates over each byte of the input `bytes32` and converts it to its corresponding two-digit hexadecimal representation. The result is then returned as a new string.
     *
     * @param data The bytes32 value to be converted to hexadecimal format.
     *
     * @return A string with the hexadecimal representation of the input `bytes32` data.
     */
    function toHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);

        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[1 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }

        return string(str);
    }
}

contract SBTToken is ERC20, ReentrancyGuard {
    using ECDSA for bytes32;
    using Address for address;
    using MessageHashUtils for bytes32;
    using StringsUtil for string;
    using StringsUtil for bytes32;
    using SafeMath for uint256;
    using Address for address payable;

    address private FEDERATION_ADDRESS;
    address private DEVELOPER_ADDRESS;
    uint256 private TOTAL_SUPPLY;
    uint256 private LIQUIDITY_ALOCATION;
    IERC20 private TARGET_BRIDGE;

    IUniswapV3Pool public pool;
    IUniswapV3Factory public factory;

    mapping(bytes32 => bool) public claimedTransactions;
    mapping(bytes => bool) public usedSignatures;
    mapping(address => mapping(uint256 => uint256)) public _shares;
    mapping(bytes32 => mapping(address => bool)) private roles;

    event OutputBridge(
        address indexed to,
        uint256 indexed amount,
        string indexed sign_at
    );
    event InputBridge(
        address indexed from,
        uint256 indexed amount,
        uint256 indexed request_at
    );
    event RoleCreated(bytes32 role, address indexed account);
    event RoleRemoved(bytes32 role, address indexed account);

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "Unauthorized");
        _;
    }

    constructor(address _factory, address _federationAddress)
        ERC20("Silent Base Token", "SBT")
    {
        FEDERATION_ADDRESS = _federationAddress;
        DEVELOPER_ADDRESS = msg.sender;
        TOTAL_SUPPLY = 10**9 * 10**decimals();
        LIQUIDITY_ALOCATION = TOTAL_SUPPLY.mul(25).div(100);

        roles[keccak256("ADMIN")][msg.sender] = true;
        emit RoleCreated(keccak256("ADMIN"), msg.sender);
        _mint(address(this), TOTAL_SUPPLY);
        factory = IUniswapV3Factory(_factory);
    }

    /**
     * @dev Mints the specified amount of tokens to the recipient address.
     * @param _to The address of the recipient.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount)
        public
        onlyRole(keccak256("MINTER"))
    {
        super._transfer(address(this), _to, _amount);
    }

    /**
     * @dev     Creates a new role.
     * @param   role  User role type to be created.
     * @param   account  Address of the account that will be given the role.
     */
    function createRole(bytes32 role, address account)
        external
        onlyRole(keccak256("ADMIN"))
    {
        require(account != address(0), "Invalid account address");
        require(!hasRole(role, account), "Role already exists");

        roles[role][account] = true;
        emit RoleCreated(role, account);
    }

    /**
     * @dev     Removes a role.
     * @param   role  User role type to be removed.
     * @param   account  Account address to be removed from the role.
     */
    function removeRole(bytes32 role, address account)
        external
        onlyRole(keccak256("ADMIN"))
    {
        require(hasRole(role, account), "Role does not exist");
        roles[role][account] = false;
        emit RoleRemoved(role, account);
    }

    /**
     * @dev     Checks if an account has a role.
     * @param   role  Role to be checked.
     * @param   account  Specific account address to be checked.
     * @return  bool  Whether the account has the role or not.
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return roles[role][account];
    }

    /**
     * @dev This function allows an admin to update the Uniswap pool address.
     *
     * Requirements:
     * - The caller must have the ADMIN role.
     *
     * @param _newAddress The new address of the Uniswap V3 Pool.
     */
    function setPool(IUniswapV3Pool _newAddress)
        external
        onlyRole(keccak256("ADMIN"))
    {
        pool = _newAddress;
    }

    /**
     * @notice Creates a new Uniswap V3 pool with this contract as one of the tokens, and initializes it with the provided parameters.
     * @dev Requires the caller to have ADMIN role.
     * @param _tokenB The address of the second token in the pool.
     * @param _fee The fee tier of the pool.
     * @param _sqrtPriceX96 The initial sqrt price of the pool as a Q64.x value.
     */
    function createNewPool(
        address _tokenB,
        uint24 _fee,
        uint160 _sqrtPriceX96
    ) external onlyRole(keccak256("ADMIN")) {
        address newPool = factory.createPool(address(this), _tokenB, _fee);
        pool = IUniswapV3Pool(newPool);
        pool.initialize(_sqrtPriceX96);
    }

    /**
     * @notice Adds liquidity to a Uniswap V3 pool.
     * Liquidity is added by minting tokens representing this contract's share in the pool.
     * The range of ticks from `_tickLower` to `_tickUpper` is covered by the new liquidity.
     *
     * Requirements:
     * - The caller must have admin role.
     *
     * @param _tickLower The lower tick of the range in which liquidity should be added.
     * @param _tickUpper The upper tick of the range in which liquidity should be added.
     * @param _amount The amount of liquidity to add.
     */
    function addLiquidity(
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _amount
    ) external onlyRole(keccak256("ADMIN")) {
        pool.mint(address(this), _tickLower, _tickUpper, _amount, "");
    }

    /**
     * @dev Burn liquidity from Uniswap pool.
     *
     * Requirements:
     * - The caller must have admin role.
     *
     * @param _tickLower The lower tick of the range from which liquidity should be burned.
     * @param _tickUpper The upper tick of the range from which liquidity should be burned.
     * @param _amount The amount of liquidity to burn.
     */
    function burnLiquidity(
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _amount
    ) external onlyRole(keccak256("ADMIN")) {
        pool.burn(_tickLower, _tickUpper, _amount);
    }

    /**
     * @dev This function allows an admin to collect fees from the Uniswap pool.
     *
     * @param _tickLower The lower tick of the range from which fees should be collected.
     * @param _tickUpper The upper tick of the range from which fees should be collected.
     */
    function collectFee(int24 _tickLower, int24 _tickUpper)
        external
        onlyRole(keccak256("ADMIN"))
    {
        pool.collect(
            DEVELOPER_ADDRESS,
            _tickLower,
            _tickUpper,
            type(uint128).max,
            type(uint128).max
        );
    }

    /**
     * @dev Admin allows to withdraw ether from the contract.
     */
    function reallocationEther() public onlyRole(keccak256("ADMIN")) {
        address payable to = payable(msg.sender);
        to.transfer(address(this).balance);
    }
    
    /**
     * @notice This function allows an admin to check the request of a specific user for a certain timestamp.
     * It returns the amount of tokens that were requested by the user at the given timestamp.
     * @dev Requires the caller to have ADMIN role.
     * @param user_bridge The address of the user whose requests are being checked.
     * @param request_at The timestamp for which the request is being checked.
     * @return uint256 The amount of tokens requested by the user at the given timestamp.
     */
    function checkRequest(address user_bridge, uint256 request_at)
        external
        view
        returns (uint256)
    {
        return _shares[user_bridge][request_at];
    }

    /*
     * @notice This function allows a user to deposit tokens into this contract from another chain or contract.
     * The function takes several parameters including source_contract (the address on the original chain where the tokens were minted or transferred), amount of tokens, and request_at which represents when the deposit was requested.
     * It checks if the sender has approved this contract to move its balance, and if it does, it initiates a transfer of tokens from the source contract to this contract's address on the current chain. 
     * The function emits an InputBridge event with details about this deposit.
     *
     * @dev Requires that the sender has approved the contract to move its balance.
     *
     * @param source_contract The address of the originating contract where tokens were minted or transferred.
     * @param amount The total number of tokens to transfer.
     * @param request_at A timestamp when this deposit was requested.
     * 
     * @return Returns true if all conditions are met, otherwise false.
     */
    function depositToken(
        address source_contract,
        uint256 amount,
        uint256 request_at
    ) external returns (bool success) {
        address user_bridge = msg.sender;

        require(
            IERC20(source_contract).balanceOf(user_bridge) >= amount,
            "Low balance"
        );
        require(
            IERC20(source_contract).allowance(user_bridge, address(this)) >=
                amount,
            "Check token allowance"
        );
        require(
            IERC20(source_contract).transferFrom(
                user_bridge,
                address(this),
                amount
            ),
            "Failed to send token to destination."
        );
        _shares[user_bridge][request_at] = amount;
        emit InputBridge(user_bridge, amount, request_at);

        return true;
    }

    /**
     * @notice This function allows a user to claim tokens from another chain or contract by providing the required parameters and signature.
     *
     * The function takes several string arguments that represent details about the transfer, including source chain ID, target chain ID, source contract address, target contract address, symbol of the token, number of decimal places, amount of tokens to be transferred, and a timestamp when the request was made (sign_at). These details are hashed together with the user's bridge address. The hash is then signed by the federation administrator using their private key.
     *
     * The function checks if the provided signature is valid for the given message (the transaction data), and if this matches the expected signer (the federation administrator). If both conditions are met, it verifies that the claimed token hasn't been already used or requested by anyone else. If all these conditions pass, it initiates a transfer of tokens from the source contract to the user's bridge address on the current chain and emits an OutputBridge event with details about this transfer.
     *
     * @dev Requires that the sender has approved the contract to move its balance.
     *
     * @param source_chainID The ID of the originating blockchain where tokens were originally minted or transferred.
     * @param source_contract The address on the original chain from which the tokens were taken.
     * @param target_contract The address on this chain to which the tokens should be sent after being claimed.
     * @param symbol The symbol of the token being transferred (e.g., "SBT").
     * @param decimal The number of decimal places for the token amount.
     * @param amount The total number of tokens to transfer.
     * @param sign_at A timestamp when this claim was requested.
     * @param signature A digital signature by the federation administrator confirming that the request is valid and must be fulfilled.
     *
     * @return Returns true if all conditions are met, otherwise false.
     */
    function claimToken(
        string memory source_chainID,
        string memory source_contract,
        string memory target_contract,
        string memory symbol,
        string memory decimal,
        string memory amount,
        string memory sign_at,
        bytes memory signature
    ) external returns (bool) {
        string memory target_chainID = Strings.toString(block.chainid);
        string memory user_bridge = Strings.toHexString(
            uint256(uint160(msg.sender)),
            20
        );

        string memory dataPack = string
            .concat(
                "BRIDGEX-",
                user_bridge,
                source_chainID,
                target_chainID,
                source_contract,
                target_contract,
                symbol,
                decimal,
                amount,
                sign_at
            )
            .toLower();

        bytes32 transaction = keccak256(abi.encodePacked(dataPack));

        require(!usedSignatures[signature], "Signature already used!");
        require(
            !claimedTransactions[transaction],
            "Transaction already claimed!"
        );
        require(
            verifySignature(transaction, FEDERATION_ADDRESS, signature),
            string.concat(
                "Failed claim token: ",
                dataPack,
                "[",
                transaction.toHexString(),
                "]"
            )
        );

        TARGET_BRIDGE = IERC20(address(this));
        emit OutputBridge(msg.sender, stringToUint(amount), sign_at);
        TARGET_BRIDGE.transfer(msg.sender, stringToUint(amount));
        claimedTransactions[transaction] = true;
        usedSignatures[signature] = true;
        return true;
    }

    /**
     * @notice Verifies that a given signature is valid for a specific message, signed by an address derived from a given signer.
     * @dev The function uses the ECDSA (Elliptic Curve Digital Signature Algorithm) to verify the provided signature against the hashed version of the input message. It also checks if the recovered address matches the expected signer's address.
     *
     * @param message A bytes32 hash of a message that was signed by the given signer. This is typically generated from a call to `keccak256` on your original message data.
     * @param signer The Ethereum address that should have signed the provided message.
     * @param signature An array of bytes representing the digital signature created by the signer. It's usually 65 bytes long, but can vary depending on the ECDSA library used.
     *
     * @return bool Returns true if the recovered address matches the expected signer and the signature is valid for the given message, otherwise it returns false.
     */
    function verifySignature(
        bytes32 message,
        address signer,
        bytes memory signature
    ) public pure returns (bool) {
        bytes32 hash = message.toEthSignedMessageHash();
        address recoveredSigner = hash.recover(signature);
        return signer == recoveredSigner;
    }

    /**
     * @dev Converts a string to its corresponding uint256 value.
     * The input string should represent an integer number in base 10. If any of the characters in the string do not represent valid digits (from '0' to '9'), the function will return 0.
     *
     * @param _str The original string to be converted into a uint256 value.
     * @return res A uint256 value that is equivalent to the input string, or 0 if the string does not represent a valid number.
     */
    function stringToUint(string memory _str)
        public
        pure
        returns (uint256 res)
    {
        for (uint256 i = 0; i < bytes(_str).length; i++) {
            if (
                (uint8(bytes(_str)[i]) - 48) < 0 ||
                (uint8(bytes(_str)[i]) - 48) > 9
            ) {
                return 0;
            }
            res +=
                (uint8(bytes(_str)[i]) - 48) *
                10**(bytes(_str).length - i - 1);
        }

        return res;
    }

    /**
     * @notice Removes the '0x' prefix from a hexadecimal string if it exists.
     *
     * This function checks if the input string starts with "0x" or "0X". If it does, the function will remove this prefix and return the rest of the original string as the new value. Otherwise, it simply returns the original string. The function uses case-insensitive comparison to determine whether the prefix exists.
     *
     * @param _hexString The input hexadecimal string from which to remove '0x' prefix.
     *
     * @return A new string that is a part of the original string after removing the '0x' prefix (if it exists). If the input string does not start with "0x", this will be an empty string.
     */
    function remove0xPrefix(string memory _hexString)
        internal
        pure
        returns (string memory)
    {
        if (
            bytes(_hexString).length >= 2 &&
            bytes(_hexString)[0] == "0" &&
            (bytes(_hexString)[1] == "x" || bytes(_hexString)[1] == "X")
        ) {
            return substring(_hexString, 2, bytes(_hexString).length);
        }
        return _hexString;
    }

    /**
     * @notice This function returns a part of string from start index to end index.
     *
     * The function takes three parameters, a string and two indices (start and end). It creates a new string containing characters between the start index and the end index in the original string. If the input string is empty or if either of the indices are out of range, an empty string will be returned.
     *
     * @param _str The original string to extract substring from.
     * @param _start The starting index for the substring (0-indexed).
     * @param _end The ending index for the substring (non-inclusive, 0-indexed).
     *
     * @return A new string that is a part of the original string between start and end indices. If either of the input parameters are out of range or if the string is empty, an empty string will be returned.
     */
    function substring(
        string memory _str,
        uint256 _start,
        uint256 _end
    ) internal pure returns (string memory) {
        bytes memory _strBytes = bytes(_str);
        bytes memory _result = new bytes(_end - _start);
        for (uint256 i = _start; i < _end; i++) {
            _result[i - _start] = _strBytes[i];
        }
        return string(_result);
    }

    /**
     * @notice Converts a hexadecimal string to its corresponding bytes20 value.
     *
     * This function takes a hexadecimal string, parses it into individual characters (each representing two digits of the original data), and converts these characters back into their uint8 representations. The results are then combined together to form a bytes20 output. If the input string is not exactly 40 characters long, or if any of the characters do not represent valid hexadecimal values, the function will revert with an error message.
     *
     * @param _hexString The input hexadecimal string to be converted into bytes20 format.
     *
     * @return A bytes20 value that is equivalent to the input hexadecimal string.
     */
    function parseHexStringToBytes20(string memory _hexString)
        internal
        pure
        returns (bytes20)
    {
        bytes memory _bytesString = bytes(_hexString);
        uint160 _parsedBytes = 0;
        for (uint256 i = 0; i < _bytesString.length; i += 2) {
            _parsedBytes *= 256;
            uint8 _byteValue = parseByteToUint8(_bytesString[i]);
            _byteValue *= 16;
            _byteValue += parseByteToUint8(_bytesString[i + 1]);
            _parsedBytes += _byteValue;
        }
        return bytes20(_parsedBytes);
    }

    /**
     * @dev Parses an individual byte into its corresponding uint8 value.
     * The byte can represent a number from 0-9 (ASCII values 48-57), or an uppercase letter A-F (ASCII values 65-70) or lowercase letters a-f (ASCII values 97-102).
     * If the byte does not represent one of these characters, the function will revert with an error message.
     *
     * @param _byte The byte to be parsed into its uint8 value.
     * @return The uint8 representation of the input byte.
     */
    function parseByteToUint8(bytes1 _byte) internal pure returns (uint8) {
        if (uint8(_byte) >= 48 && uint8(_byte) <= 57) {
            return uint8(_byte) - 48;
        } else if (uint8(_byte) >= 65 && uint8(_byte) <= 70) {
            return uint8(_byte) - 55;
        } else if (uint8(_byte) >= 97 && uint8(_byte) <= 102) {
            return uint8(_byte) - 87;
        } else {
            revert(string(abi.encodePacked("Invalid byte value: ", _byte)));
        }
    }

    fallback() external payable {}

    receive() external payable {}
}
