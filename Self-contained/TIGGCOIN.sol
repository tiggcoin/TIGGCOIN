// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
  TIGGCOIN ($TIGG) — FINAL (self-contained, no OZ imports)
  - Chain: Binance Smart Chain (EVM compatible)
  - Initial supply: 1,000,000,000 (1B) minted to deployer (msg.sender)
  - Max supply: 10,000,000,000 (10B)
  - Decimals: 18
  - Scheduled mint: +1B on 30 Sep at 00:00:00 UTC every 5 years (first at 2030-09-30)
  - Emergency stop / restart (transfers & minting blocked while emergency)
  - Bridge mint/burn hooks restricted to BRIDGE_ROLE
  - Rescue functions for tokens & native currency (owner-only)
*/

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        require(token.transfer(to, value), "SafeERC20: transfer failed");
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor(address initialOwner) {
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }
    function owner() public view returns (address) {
        return _owner;
    }
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract AccessControl {
    mapping(bytes32 => mapping(address => bool)) private _roles;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "AccessControl: missing role");
        _;
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!hasRole(role, account)) {
            _roles[role][account] = true;
            emit RoleGranted(role, account);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (hasRole(role, account)) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account);
        }
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }
}

contract ERC20 is Context, IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public view returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }

    function allowance(address owner_, address spender) public view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[_msgSender()][spender] = amount;
        emit Approval(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowances[from][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(from, to, amount);
        _allowances[from][_msgSender()] = currentAllowance - amount;
        emit Approval(from, _msgSender(), _allowances[from][_msgSender()]);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: from zero");
        require(to != address(0), "ERC20: to zero");
        _beforeTokenTransfer(from, to, amount);
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer exceeds balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to zero");
        _beforeTokenTransfer(address(0), account, amount);
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from zero");
        _beforeTokenTransfer(account, address(0), amount);
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

contract TIGGCOIN is ERC20, AccessControl, Ownable {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    uint8 private constant _DECIMALS = 18;
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * (10 ** _DECIMALS);
    uint256 public constant TRANCHE_AMOUNT = 1_000_000_000 * (10 ** _DECIMALS);
    uint256 public constant MAX_SUPPLY = 10_000_000_000 * (10 ** _DECIMALS);

    uint256[] public scheduledMints;
    uint256 public nextMintIndex = 0;
    bool public emergencyStopped = false;

    event MintScheduled(uint256 indexed amount, uint256 indexed unlockTime);
    event MintExecuted(address indexed to, uint256 amount, uint256 timestamp, uint256 newTotalSupply);
    event BridgeMint(address indexed to, uint256 amount, address indexed bridge);
    event BridgeBurn(address indexed from, uint256 amount, address indexed bridge);
    event TokenRescued(address indexed token, address indexed to, uint256 amount);
    event NativeRescued(address indexed to, uint256 amount);
    event EmergencyStopped(address indexed by, uint256 timestamp);
    event EmergencyLifted(address indexed by, uint256 timestamp);

    constructor() ERC20("TIGGCOIN", "TIGG", _DECIMALS) Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
        _grantRole(BRIDGE_ROLE, _msgSender());

        _mint(_msgSender(), INITIAL_SUPPLY);

        scheduledMints.push(1916956800);
        scheduledMints.push(2074723200);
        scheduledMints.push(2232576000);
        scheduledMints.push(2390342400);
        scheduledMints.push(2548108800);
        scheduledMints.push(2705875200);
        scheduledMints.push(2863728000);
        scheduledMints.push(3021494400);
        scheduledMints.push(3179260800);

        for (uint256 i = 0; i < scheduledMints.length; i++) {
            emit MintScheduled(TRANCHE_AMOUNT, scheduledMints[i]);
        }
    }

    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }

    function emergencyStop() external onlyOwner {
        emergencyStopped = true;
        emit EmergencyStopped(_msgSender(), block.timestamp);
    }

    function liftEmergencyStop() external onlyOwner {
        emergencyStopped = false;
        emit EmergencyLifted(_msgSender(), block.timestamp);
    }

    function executeScheduledMint() external onlyRole(MINTER_ROLE) {
        require(!emergencyStopped, "TIGG: emergency stopped");
        require(nextMintIndex < scheduledMints.length, "TIGG: no scheduled mints left");

        uint256 unlockTime = scheduledMints[nextMintIndex];
        require(block.timestamp >= unlockTime, "TIGG: scheduled mint not yet available");

        uint256 currentSupply = totalSupply();
        require(currentSupply + TRANCHE_AMOUNT <= MAX_SUPPLY, "TIGG: max supply exceeded");

        _mint(owner(), TRANCHE_AMOUNT);
        emit MintExecuted(owner(), TRANCHE_AMOUNT, block.timestamp, totalSupply());

        nextMintIndex += 1;
    }

    function scheduledMintsRemaining() external view returns (uint256) {
        if (nextMintIndex >= scheduledMints.length) return 0;
        return scheduledMints.length - nextMintIndex;
    }

    function bridgeMint(address to, uint256 amount) external onlyRole(BRIDGE_ROLE) {
        require(!emergencyStopped, "TIGG: emergency stopped");
        require(to != address(0), "TIGG: mint to zero");
        require(totalSupply() + amount <= MAX_SUPPLY, "TIGG: max supply exceeded");

        _mint(to, amount);
        emit BridgeMint(to, amount, _msgSender());
    }

    function bridgeBurn(address from, uint256 amount) external onlyRole(BRIDGE_ROLE) {
        require(!emergencyStopped, "TIGG: emergency stopped");
        require(from != address(0), "TIGG: burn from zero");

        _burn(from, amount);
        emit BridgeBurn(from, amount, _msgSender());
    }

    receive() external payable {}
    fallback() external payable {}

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "TIGG: to zero");
        IERC20(token).safeTransfer(to, amount);
        emit TokenRescued(token, to, amount);
    }

    function rescueAllERC20(address token, address to) external onlyOwner {
        require(to != address(0), "TIGG: to zero");
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "TIGG: zero balance");
        IERC20(token).safeTransfer(to, bal);
        emit TokenRescued(token, to, bal);
    }

    function rescueNative(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "TIGG: to zero");
        require(amount <= address(this).balance, "TIGG: insufficient balance");
        to.transfer(amount);
        emit NativeRescued(to, amount);
    }

    function rescueAllNative(address payable to) external onlyOwner {
        require(to != address(0), "TIGG: to zero");
        uint256 bal = address(this).balance;
        require(bal > 0, "TIGG: zero balance");
        to.transfer(bal);
        emit NativeRescued(to, bal);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        require(!emergencyStopped, "TIGG: emergency stopped");
    }

    function ownerGrantMinter(address account) external onlyOwner { _grantRole(MINTER_ROLE, account); }
    function ownerRevokeMinter(address account) external onlyOwner { _revokeRole(MINTER_ROLE, account); }
    function ownerGrantBridge(address account) external onlyOwner { _grantRole(BRIDGE_ROLE, account); }
    function ownerRevokeBridge(address account) external onlyOwner { _revokeRole(BRIDGE_ROLE, account); }
}
