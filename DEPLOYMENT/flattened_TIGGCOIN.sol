// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  Flattened TIGGCOIN.sol
  - For Remix / BscScan verification
  - Compiler: 0.8.24 (Cancun)
  - OpenZeppelin v5.0.0 style inlined contracts:
    * IERC20
    * Address (partial)
    * Context
    * ERC20 (v5-style with _update hook)
    * SafeERC20
    * AccessControl
    * Ownable (v5-style Ownable(msg.sender) constructor)
  - Then TIGGCOIN contract.
*/

/* ========== Minimal Address utils ========== */
library Address {
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call(data);
        if (success) return returndata;
        else {
            // bubble revert reason
            if (returndata.length > 0) {
                /// @solidity memory-safe-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

/* ========== IERC20 ========== */
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/* ========== Context (minimal) ========== */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/* ========== ERC20 (v5-style simplified, includes _update hook) ========== */
abstract contract ERC20 is Context, IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimalsInternal = 18;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimalsInternal;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _update(_msgSender(), to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        uint256 currentAllowance = _allowances[from][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(from, _msgSender(), currentAllowance - amount);
        }
        _update(from, to, amount);
        return true;
    }

    // Internal: updates balances and emits Transfer; hook named _update per v5 patterns
    function _update(address from, address to, uint256 amount) internal virtual {
        // When from == address(0) => mint
        if (from == address(0)) {
            _totalSupply += amount;
            _balances[to] += amount;
            emit Transfer(address(0), to, amount);
            return;
        }

        // When to == address(0) => burn
        if (to == address(0)) {
            uint256 fromBalance = _balances[from];
            require(fromBalance >= amount, "ERC20: burn amount exceeds balance");
            unchecked {
                _balances[from] = fromBalance - amount;
                _totalSupply -= amount;
            }
            emit Transfer(from, address(0), amount);
            return;
        }

        // Normal transfer
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    // Internal mint
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to zero address");
        _update(address(0), account, amount);
    }

    // Internal burn
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from zero address");
        _update(account, address(0), amount);
    }

    // Internal approve (sets allowance and emits Approval)
    function _approve(address owner_, address spender, uint256 amount) internal virtual {
        require(owner_ != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    // Utilities for setting decimals
    function _setupDecimals(uint8 decimals_) internal virtual {
        _decimalsInternal = decimals_;
    }
}

/* ========== SafeERC20 ========== */
library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. Use increase/decrease otherwise.
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        bytes memory returndata = Address.functionCall(address(token), data);
        if (returndata.length > 0) { // Return data is optional
            // abi.decode will revert on failure
            require(abi.decode(returndata, (bool)), "SafeERC20: operation did not succeed");
        }
    }
}

/* ========== AccessControl (v5-style simplified) ========== */
abstract contract AccessControl is Context {
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _roles[role].members[account];
    }

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, _msgSender()), "AccessControl: sender requires role");
        _;
    }

    function getRoleAdmin(bytes32 role) public view virtual returns (bytes32) {
        return _roles[role].adminRole;
    }

    function grantRole(bytes32 role, address account) public virtual {
        require(hasRole(getRoleAdmin(role), _msgSender()), "AccessControl: must be admin to grant");
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual {
        require(hasRole(getRoleAdmin(role), _msgSender()), "AccessControl: must be admin to revoke");
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) public virtual {
        require(account == _msgSender(), "AccessControl: can only renounce for self");
        _revokeRole(role, account);
    }

    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
        if (_roles[role].adminRole == bytes32(0)) {
            _roles[role].adminRole = DEFAULT_ADMIN_ROLE;
        }
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = _roles[role].adminRole;
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    function _grantRole(bytes32 role, address account) internal virtual {
        if (!_roles[role].members[account]) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) internal virtual {
        if (_roles[role].members[account]) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
}

/* ========== Ownable (v5-style) ========== */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Note: v5 pattern allows Ownable(msg.sender) in constructor style; we implement constructor-like initializer.
    constructor(address initialOwner) {
        _transferOwnership(initialOwner == address(0) ? _msgSender() : initialOwner);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/* ========== TIGGCOIN Contract (original content inlined) ========== */
contract TIGGCOIN is ERC20, AccessControl, Ownable {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    uint8 private constant _DECIMALS = 18;

    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * (10 ** uint256(_DECIMALS)); // 1B
    uint256 public constant TRANCHE_AMOUNT = 1_000_000_000 * (10 ** uint256(_DECIMALS)); // 1B each tranche
    uint256 public constant MAX_SUPPLY = 10_000_000_000 * (10 ** uint256(_DECIMALS)); // 10B

    // Hardcoded scheduled mint timestamps (30 Sep 00:00:00 UTC every 5 years starting 2030)
    // These are UNIX timestamps (seconds since 1970-01-01 UTC)
    uint256[] public scheduledMints;
    uint256 public nextMintIndex = 0; // index for next scheduled mint

    // Emergency circuit breaker
    bool public emergencyStopped = false;

    // Events
    event MintScheduled(uint256 indexed amount, uint256 indexed unlockTime);
    event MintExecuted(address indexed to, uint256 amount, uint256 timestamp, uint256 newTotalSupply);
    event BridgeMint(address indexed to, uint256 amount, address indexed bridge);
    event BridgeBurn(address indexed from, uint256 amount, address indexed bridge);
    event TokenRescued(address indexed token, address indexed to, uint256 amount);
    event NativeRescued(address indexed to, uint256 amount);
    event EmergencyStopped(address indexed by, uint256 timestamp);
    event EmergencyLifted(address indexed by, uint256 timestamp);

    constructor() ERC20("TIGGCOIN", "TIGG") Ownable(msg.sender) {
        // Grant roles to deployer (OpenZeppelin v5 style)
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
        _grantRole(BRIDGE_ROLE, _msgSender());

        // Mint initial supply to deployer
        _mint(_msgSender(), INITIAL_SUPPLY);

        // Populate scheduled mint timestamps (30 Sep 00:00:00 UTC every 5 years starting 2030)
        // Note: timestamps are in seconds UTC
        // 2030-09-30 00:00:00 UTC
        scheduledMints.push(1916956800);
        // 2035-09-30
        scheduledMints.push(2074723200);
        // 2040-09-30
        scheduledMints.push(2232576000);
        // 2045-09-30
        scheduledMints.push(2390342400);
        // 2050-09-30
        scheduledMints.push(2548108800);
        // 2055-09-30
        scheduledMints.push(2705875200);
        // 2060-09-30
        scheduledMints.push(2863728000);
        // 2065-09-30
        scheduledMints.push(3021494400);
        // 2070-09-30
        scheduledMints.push(3179260800);

        // Emit schedule events for on-chain transparency
        for (uint256 i = 0; i < scheduledMints.length; i++) {
            emit MintScheduled(TRANCHE_AMOUNT, scheduledMints[i]);
        }
        // Set decimals explicitly (ERC20 default already 18, but we keep pattern)
        _setupDecimals(_DECIMALS);
    }

    // override decimals
    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }

    // ----------------------
    // Emergency controls
    // ----------------------
    function emergencyStop() external onlyOwner {
        emergencyStopped = true;
        emit EmergencyStopped(_msgSender(), block.timestamp);
    }

    function liftEmergencyStop() external onlyOwner {
        emergencyStopped = false;
        emit EmergencyLifted(_msgSender(), block.timestamp);
    }

    // ----------------------
    // Scheduled mint: execute next tranche
    // only callable by MINTER_ROLE, and blocked during emergency.
    // ----------------------
    function executeScheduledMint() external onlyRole(MINTER_ROLE) {
        require(!emergencyStopped, "TIGG: emergency stopped");
        require(nextMintIndex < scheduledMints.length, "TIGG: no scheduled mints left");

        uint256 unlockTime = scheduledMints[nextMintIndex];
        require(block.timestamp >= unlockTime, "TIGG: scheduled mint not yet available");

        uint256 currentSupply = totalSupply();
        require(currentSupply + TRANCHE_AMOUNT <= MAX_SUPPLY, "TIGG: max supply exceeded");

        // Mint tranche to owner for distribution/treasury control
        _mint(owner(), TRANCHE_AMOUNT);

        emit MintExecuted(owner(), TRANCHE_AMOUNT, block.timestamp, totalSupply());

        // advance index
        nextMintIndex += 1;
    }

    function scheduledMintsRemaining() external view returns (uint256) {
        if (nextMintIndex >= scheduledMints.length) return 0;
        return scheduledMints.length - nextMintIndex;
    }

    // ----------------------
    // Bridge functions (only BRIDGE_ROLE)
    // ----------------------
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

    // ----------------------
    // Accept native currency (BNB) and fallback
    // ----------------------
    receive() external payable {}
    fallback() external payable {}

    // ----------------------
    // Rescue / sweep functions (owner-only)
    // ----------------------
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

    // ----------------------
    // OpenZeppelin v5 transfer hook: block transfers during emergency
    // ----------------------
    function _update(address from, address to, uint256 amount) internal override {
        require(!emergencyStopped, "TIGG: emergency stopped");
        super._update(from, to, amount);
    }

    // ----------------------
    // Owner convenience role helpers
    // ----------------------
    function ownerGrantMinter(address account) external onlyOwner { _grantRole(MINTER_ROLE, account); }
    function ownerRevokeMinter(address account) external onlyOwner { revokeRole(MINTER_ROLE, account); }
    function ownerGrantBridge(address account) external onlyOwner { _grantRole(BRIDGE_ROLE, account); }
    function ownerRevokeBridge(address account) external onlyOwner { revokeRole(BRIDGE_ROLE, account); }
}
