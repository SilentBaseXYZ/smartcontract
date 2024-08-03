// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
    function toLowerCase(string memory str) internal pure returns (string memory) {
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
    function bytes32ToHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);

        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[1 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }

        return string(str);
    }

    /**
     * @dev Converts a string to its corresponding uint256 value.
     * The input string should represent an integer number in base 10. If any of the characters in the string do not represent valid digits (from '0' to '9'), the function will return 0.
     *
     * @param str The original string to be converted into a uint256 value.
     * @return A uint256 value that is equivalent to the input string, or 0 if the string does not represent a valid number.
     */
    function stringToUint256(string memory str) public pure returns (uint) {
        bytes memory b = bytes(str);
        uint num = 0;
        
        for (uint i = 0; i < b.length; i++) {
            uint8 char = uint8(b[i]);
            require(char >= 48 && char <= 57, "Invalid character");
            num = num * 10 + (char - 48);
        }
        
        return num;
    }
}

contract SBTToken is ERC20, ReentrancyGuard {
    using ECDSA for bytes32;
    using Address for address;
    using MessageHashUtils for bytes32;
    using StringsUtil for string;
    using StringsUtil for bytes32;
    using Address for address payable;

    address private immutable federationAddress;
    address private immutable developerAddress;
    uint256 private immutable circulatingSupply;
    uint256 private immutable liquidityAlocation;
    IERC20 private targetBridge;

    mapping(bytes32 => bool) public claimedTransactions;
    mapping(bytes => bool) public usedSignatures;
    mapping(address => mapping(uint256 => uint256)) public shares;
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

    constructor(address _federationAddress)
        ERC20("Silent Base Token", "SBT")
    {
        require(_federationAddress != address(0), "Invalid address");
        federationAddress = _federationAddress;
        developerAddress = msg.sender;
        circulatingSupply = 10**9 * 10**decimals();
        liquidityAlocation = circulatingSupply * 25 / 100;

        roles[keccak256("ADMIN")][msg.sender] = true;
        emit RoleCreated(keccak256("ADMIN"), msg.sender);
        _mint(address(this), circulatingSupply);
    }

    /**
     * @dev mintTokenss the specified amount of tokens to the recipient address.
     * @param to The address of the recipient.
     * @param amount The amount of tokens to mintTokens.
     */
    function mintTokens(address to, uint256 amount)
        public
        onlyRole(keccak256("mintTokensER"))
    {
        super._transfer(address(this), to, amount);
    }

    /**
     * @dev     Creates a new role.
     * @param   role  User role type to be created.
     * @param   account  Address of the account that will be given the role.
     */
    function assignRole(bytes32 role, address account)
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
    function revokeRole(bytes32 role, address account)
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
     * @dev Admin allows to withdraw ether from the contract.
     */
    function withdrawEther() public onlyRole(keccak256("ADMIN")) nonReentrant {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No Ether to transfer");

        address payable to = payable(msg.sender);
        require(to != address(0), "Invalid address");

        Address.sendValue(to, contractBalance);
    }

    
    /**
     * @notice This function allows an admin to check the request of a specific user for a certain timestamp.
     * It returns the amount of tokens that were requested by the user at the given timestamp.
     * @dev Requires the caller to have ADMIN role.
     * @param userBridge The address of the user whose requests are being checked.
     * @param requestAt The timestamp for which the request is being checked.
     * @return uint256 The amount of tokens requested by the user at the given timestamp.
     */
    function getRequestAmount(address userBridge, uint256 requestAt)
        external
        view
        returns (uint256)
    {
        return shares[userBridge][requestAt];
    }

    /**
     * @notice This function allows a user to deposit tokens into this contract from another chain or contract.
     * The function takes several parameters including source_contract (the address on the original chain where the tokens were mintTokensed or transferred), amount of tokens, and request_at which represents when the deposit was requested.
     * It checks if the sender has approved this contract to move its balance, and if it does, it initiates a transfer of tokens from the source contract to this contract's address on the current chain. 
     * The function emits an InputBridge event with details about this deposit.
     *
     * @dev Requires that the sender has approved the contract to move its balance.
     *
     * @param sourceContract The address of the originating contract where tokens were mintTokensed or transferred.
     * @param amount The total number of tokens to transfer.
     * @param requestAt A timestamp when this deposit was requested.
     * 
     * @return success Returns true if all conditions are met, otherwise false.
     */
    function depositTokens(address sourceContract, uint256 amount, uint256 requestAt) external nonReentrant returns (bool success) {
        address user_bridge = msg.sender;

        require(
            IERC20(sourceContract).balanceOf(user_bridge) >= amount,
            "Low balance"
        );
        require(
            IERC20(sourceContract).allowance(user_bridge, address(this)) >=
                amount,
            "Check token allowance"
        );
        
        shares[user_bridge][requestAt] = amount;
        emit InputBridge(user_bridge, amount, requestAt);
        // Perform the external call
        require(
            IERC20(sourceContract).transferFrom(
                user_bridge,
                address(this),
                amount
            ),
            "Failed to send token to destination."
        );

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
     * @param sourceChainID The ID of the originating blockchain where tokens were originally mintTokensed or transferred.
     * @param sourceContract The address on the original chain from which the tokens were taken.
     * @param targetContract The address on this chain to which the tokens should be sent after being claimed.
     * @param tokenSymbol The symbol of the token being transferred (e.g., "SBT").
     * @param decimal The number of decimal places for the token amount.
     * @param amount The total number of tokens to transfer.
     * @param signAt A timestamp when this claim was requested.
     * @param signature A digital signature by the federation administrator confirming that the request is valid and must be fulfilled.
     *
     * @return Returns true if all conditions are met, otherwise false.
     */
    function claimTokens(
        string memory sourceChainID,
        string memory sourceContract,
        string memory targetContract,
        string memory tokenSymbol,
        string memory decimal,
        string memory amount,
        string memory signAt,
        bytes memory signature
    ) external nonReentrant returns (bool) {
        string memory target_chainID = Strings.toString(block.chainid);
        string memory user_bridge = Strings.toHexString(
            uint256(uint160(msg.sender)),
            20
        );

        string memory dataPack = string
            .concat(
                "BRIDGEX-",
                user_bridge,
                sourceChainID,
                target_chainID,
                sourceContract,
                targetContract,
                tokenSymbol, // Menggunakan 'tokenSymbol' di sini
                decimal,
                amount,
                signAt
            )
            .toLowerCase();

        bytes32 transaction = keccak256(abi.encodePacked(dataPack));

        require(!usedSignatures[signature], "Signature already used!");
        require(
            !claimedTransactions[transaction],
            "Transaction already claimed!"
        );
        require(
            isSignatureValid(transaction, federationAddress, signature),
            string.concat(
                "Failed claim token: ",
                dataPack,
                "[",
                transaction.bytes32ToHexString(),
                "]"
            )
        );

        // Update state before making the external call
        claimedTransactions[transaction] = true;
        usedSignatures[signature] = true;

        targetBridge = IERC20(address(this));
        emit OutputBridge(msg.sender, amount.stringToUint256(), signAt);
        require(targetBridge.transfer(msg.sender, amount.stringToUint256()), "Transfer failed");

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
    function isSignatureValid(
        bytes32 message,
        address signer,
        bytes memory signature
    ) public pure returns (bool) {
        bytes32 hash = message.toEthSignedMessageHash();
        address recoveredSigner = hash.recover(signature);
        return signer == recoveredSigner;
    }

    

    fallback() external payable {}

    receive() external payable {}
}
