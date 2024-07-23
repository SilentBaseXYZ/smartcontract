// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract SBTToken is ERC20Upgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address payable;
    using SafeMathUpgradeable for uint256;

    uint256 private TOTAL_SUPPLY;
    uint256 private LIQUIDITY_ALOCATION;

    // Arrays to store token pairs and keys
    address[] public tokenPairKeys;
    mapping(address => address) public tokenPairs;

    // Marketing and team wallet addresses
    address public marketingAddress;
    address public teamAddress;

    // Public variables for the token
    // Uniswap router, factory and weth addresses
    IUniswapV2Router02 public uniswapRouter;
    address public uniswapFactory;
    address private bether;

    // Role management mapping
    mapping(bytes32 => mapping(address => bool)) private roles;

    // Event declarations for role creation and role removal
    event RoleCreated(bytes32 role, address indexed account);
    event RoleRemoved(bytes32 role, address indexed account);

    /**
     * @dev     Modifier to restrict access to specific roles, ensuring only authorized accounts can execute the function.
     * @param   role  Role to be checked
     */
    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "Unauthorized");
        _;
    }

    /**
     * @dev     Initializes the contract.
     * @param   _router  Router address.
     */
    function initialize(address _router) initializer public {
        TOTAL_SUPPLY = 10 ** 9 * 10**decimals();
        LIQUIDITY_ALOCATION  = TOTAL_SUPPLY.mul(25).div(100);
     
        __UUPSUpgradeable_init();
        __ERC20_init("Silent Base Token", "SBT");
        roles[keccak256("ADMIN")][msg.sender] = true;
        emit RoleCreated(keccak256("ADMIN"), msg.sender);
        _mint(address(this), TOTAL_SUPPLY);
        uniswapRouter = IUniswapV2Router02(_router);
        uniswapFactory = uniswapRouter.factory();
        bether = uniswapRouter.WETH();
        address pairAddress = IUniswapV2Factory(uniswapFactory).createPair(address(this), uniswapRouter.WETH());
        tokenPairs[address(this)] = pairAddress;
        tokenPairKeys.push(address(this));
    }

    function _authorizeUpgrade(address) internal override onlyRole(keccak256("ADMIN")) {} 

    /**
     * @dev Mints the specified amount of tokens to the recipient address.
     * @param _to The address of the recipient.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) public onlyRole(keccak256("MINTER")) {
        super._transfer(address(this), _to, _amount);
    }
    
    /**
     * @dev     Creates a new role.
     * @param   role  User role type to be created.
     * @param   account  Address of the account that will be given the role.
     */
    function createRole(bytes32 role, address account) external onlyRole(keccak256("ADMIN")) {
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
    function removeRole(bytes32 role, address account) external onlyRole(keccak256("ADMIN")) {
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
    * @dev     Update the Uniswap router address.
    * @param   _newRouter  The new address for the Uniswap router.
    */
    function updateRouter(address _newRouter) external onlyRole(keccak256("ADMIN")) {
        require(_newRouter != address(0), "Invalid address");
        uniswapRouter = IUniswapV2Router02(_newRouter);
        uniswapFactory = uniswapRouter.factory();
        bether = uniswapRouter.WETH();
    }


    /**
     * @dev     Create a new UniswapV2 pair for trading, requiring the address of the token pair to be provided.
     * @param   tokenPair  Token pair address.
     */
    function createPair(address tokenPair) external onlyRole(keccak256("ADMIN")) {
        IUniswapV2Factory factory = IUniswapV2Factory(uniswapFactory);
        address pairAddress = factory.createPair(address(this), tokenPair);
        tokenPairs[tokenPair] = pairAddress;
        tokenPairKeys.push(tokenPair);
    }

    /**
     * @dev     Admin allows to withdraw ether from the contract.
     */
    function reallocationEther() public onlyRole(keccak256("ADMIN")){
        address payable to = payable(msg.sender);
        to.transfer(address(this).balance);
    } 

    fallback() external payable {}

    receive() external payable {}
}
