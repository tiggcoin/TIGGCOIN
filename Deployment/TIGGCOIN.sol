// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

library SafeERC20 {
    function _callOptionalReturn(address token, bytes memory data) private {
        (bool success, bytes memory returndata) = token.call(data);
        require(success, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(address(token), abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(address(token), abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        _callOptionalReturn(address(token), abi.encodeWithSelector(token.approve.selector, spender, value));
    }
}

contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Ownable: zero owner");
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero new owner");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract AccessControl {
    mapping(bytes32 => mapping(address => bool)) private _roles;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "AccessControl: missing role");
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function _grantRole(bytes32 role, address account) internal virtual {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal virtual {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function revokeRole(bytes32 role, address account) public virtual {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "AccessControl: sender must be admin to revoke");
        _revokeRole(role, account);
    }
}

contract ERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner_, address spender) public view virtual returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(from, msg.sender, currentAllowance - amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");

        _update(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _update(address from, address to, uint256 amount) internal virtual {
        // Hook for overrides (e.g., emergency stop)
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to zero");
        _update(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from zero");
        _update(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal virtual {
        require(owner_ != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }
}

contract TIGGCOIN is ERC20, AccessControl, Ownable {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    uint8 private constant _DECIMALS = 18;

    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * (10 ** uint256(_DECIMALS));
    uint256 public constant TRANCHE_AMOUNT = 1_000_000_000 * (10 ** uint256(_DECIMALS));
    uint256 public constant MAX_SUPPLY = 10_000_000_000 * (10 ** uint256(_DECIMALS));

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

    constructor() ERC20("TIGGCOIN", "TIGG") Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
        _grantRole(BRIDGE_ROLE, _msgSender());

        _mint(_msgSender(), INITIAL_SUPPLY);

        scheduledMints.push(1916956800); // 2030-09-30 00:00:00 UTC
        scheduledMints.push(2074723200); // 2035-09-30
        scheduledMints.push(2232576000); // 2040-09-30
        scheduledMints.push(2390342400); // 2045-09-30
        scheduledMints.push(2548108800); // 2050-09-30
        scheduledMints.push(2705875200); // 2055-09-30
        scheduledMints.push(2863728000); // 2060-09-30
        scheduledMints.push(3021494400); // 2065-09-30
        scheduledMints.push(3179260800); // 2070-09-30

        for (uint256 i = 0; i < scheduledMints.length; i++) {
            emit MintScheduled(TRANCHE_AMOUNT, scheduledMints[i]);
        }
    }

    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }

    function _msgSender() internal view returns (address) {
        return msg.sender;
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
        (bool success, ) = to.call{value: amount}("");
        require(success, "TIGG: native transfer failed");
        emit NativeRescued(to, amount);
    }

    function rescueAllNative(address payable to) external onlyOwner {
        require(to != address(0), "TIGG: to zero");
        uint256 bal = address(this).balance;
        require(bal > 0, "TIGG: zero balance");
        (bool success, ) = to.call{value: bal}("");
        require(success, "TIGG: native transfer failed");
        emit NativeRescued(to, bal);
    }

    function _update(address from, address to, uint256 amount) internal override {
        require(!emergencyStopped, "TIGG: emergency stopped");
        super._update(from, to, amount);
    }

    function ownerGrantMinter(address account) external onlyOwner { _grantRole(MINTER_ROLE, account); }
    function ownerRevokeMinter(address account) external onlyOwner { revokeRole(MINTER_ROLE, account); }
    function ownerGrantBridge(address account) external onlyOwner { _grantRole(BRIDGE_ROLE, account); }
    function ownerRevokeBridge(address account) external onlyOwner { revokeRole(BRIDGE_ROLE, account); }

    function isMinter(address account) external view returns (bool) { return hasRole(MINTER_ROLE, account); }
    function isBridge(address account) external view returns (bool) { return hasRole(BRIDGE_ROLE, account); }
}