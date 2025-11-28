// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/*
  TIGGsale (fixed)
  - Sale contract holds TIGG inventory (owner deposits tokens)
  - Price denominated with 18 decimals (like ether). Ensure USDT used here is 18-decimals,
    or set price accordingly if USDT has different decimals.
  - Linear daily increase applied in O(1) to avoid gas-heavy loops.
  - SafeERC20 wrapper for non-standard tokens included.
  - NonReentrant guard included.
*/

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

library SafeERC20 {
    function _callOptionalReturn(address token, bytes memory data) private {
        (bool success, bytes memory returndata) = token.call(data);
        require(success, "SafeERC20: call failed");
        if (returndata.length > 0) { // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: operation failed");
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

contract TIGGsale {
    using SafeERC20 for IERC20;

    // Ownership
    address public owner;

    // Tokens
    address public usdt; // stablecoin used to buy TIGG (assumed 18 decimals unless you adapt)
    address public tigg; // TIGG token contract

    // Pricing (all values use 18-decimal fixed-point)
    uint256 public basePrice;           // price per 1 TIGG in USDT (18 decimals)
    uint256 public autoIncreasePercent; // integer percent per day (e.g., 1 = 1%)
    uint256 public lastIncrease;        // timestamp of last applied increase (seconds)

    // Sale timing & limits (TIGG amounts in token base units, usually 18 decimals)
    uint256 public saleStart;
    uint256 public minBuy;
    uint256 public maxBuy;

    // Stats
    uint256 public totalSold;
    uint256 public manualPrice; // if >0 overrides automatic pricing

    // Reentrancy guard
    uint8 private _locked;

    // Events
    event Bought(address indexed buyer, uint256 usdtAmount, uint256 tiggAmount, uint256 timestamp);
    event PriceUpdated(uint256 newPrice, uint256 timestamp);
    event ManualPriceSet(uint256 price, uint256 timestamp);
    event DepositTIGG(address indexed from, uint256 amount);
    event WithdrawTIGG(address indexed to, uint256 amount);
    event WithdrawUSDT(address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        owner = msg.sender;
        saleStart = 1734048000; // default, change via setter if needed
        basePrice = 10 ether;   // price uses 18-decimal scale; set appropriately
        autoIncreasePercent = 1; // 1% per day by default (linear)
        lastIncrease = saleStart;
        minBuy = 1 ether; // in TIGG units (18 decimals)
        maxBuy = 100_000_000 ether;
        _locked = 1; // unlocked state = 1
        emit OwnershipTransferred(address(0), owner);
    }

    /* -------------------
       Modifiers
       ------------------- */
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(_locked == 1, "Reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }

    /* -------------------
       Owner / admin setters
       ------------------- */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setUSDT(address a) external onlyOwner { usdt = a; }
    function setTIGG(address a) external onlyOwner { tigg = a; }
    function setSaleStart(uint256 ts) external onlyOwner { saleStart = ts; }
    function setAutoIncreasePercent(uint256 p) external onlyOwner { autoIncreasePercent = p; }
    function setMinMax(uint256 minAmount, uint256 maxAmount) external onlyOwner { minBuy = minAmount; maxBuy = maxAmount; }

    // Set base price directly (resets lastIncrease to now)
    function setBasePrice(uint256 p) external onlyOwner {
        basePrice = p;
        lastIncrease = block.timestamp;
        emit PriceUpdated(p, block.timestamp);
    }

    // Manual override price (if >0 this price is returned by getPrice)
    function setManualPrice(uint256 p) external onlyOwner {
        manualPrice = p;
        emit ManualPriceSet(p, block.timestamp);
    }

    /* -------------------
       Inventory management (owner deposits TIGG tokens into this contract)
       ------------------- */
    // Owner deposits TIGG tokens into the sale contract inventory.
    function depositTIGG(uint256 amount) external onlyOwner {
        require(tigg != address(0), "TIGG not set");
        IERC20(tigg).safeTransferFrom(msg.sender, address(this), amount);
        emit DepositTIGG(msg.sender, amount);
    }

    // Owner withdraws unsold TIGG from contract
    function withdrawTIGG(uint256 amount) external onlyOwner {
        require(tigg != address(0), "TIGG not set");
        IERC20(tigg).safeTransfer(owner, amount);
        emit WithdrawTIGG(owner, amount);
    }

    // Owner withdraws accumulated USDT from sales (from contract; if you forward to owner at each sale this may be unused)
    function withdrawUSDT(uint256 amount) external onlyOwner {
        require(usdt != address(0), "USDT not set");
        IERC20(usdt).safeTransfer(owner, amount);
        emit WithdrawUSDT(owner, amount);
    }

    /* -------------------
       Pricing helpers
       - getPrice(): view, does not change state
       - applyPriceUpdate(): internal, updates basePrice & lastIncrease in O(1)
       Note: Linear approximation is used for daily percent increases:
         multiplier = 1 + daysPassed * autoIncreasePercent / 100
       If you require exact compounding, replace with a fixed-point pow implementation.
       ------------------- */

    // Compute the current price without mutating state
    function getPrice() public view returns (uint256) {
        if (manualPrice > 0) return manualPrice;
        if (block.timestamp <= saleStart) return basePrice;
        if (block.timestamp < lastIncrease + 1 days) return basePrice;

        uint256 daysPassed = (block.timestamp - lastIncrease) / 1 days;
        // linear multiplier (1 + p * days)
        uint256 multiplierNumerator = 100 + (autoIncreasePercent * daysPassed);
        // newPrice = basePrice * multiplierNumerator / 100
        return (basePrice * multiplierNumerator) / 100;
    }

    // Persist price updates in O(1). Returns the new price after update.
    function applyPriceUpdate() internal returns (uint256) {
        if (manualPrice > 0) return manualPrice;
        if (block.timestamp <= saleStart) return basePrice;
        if (block.timestamp < lastIncrease + 1 days) return basePrice;

        uint256 daysPassed = (block.timestamp - lastIncrease) / 1 days;
        // linear update (safe under typical percent/days values)
        uint256 multiplierNumerator = 100 + (autoIncreasePercent * daysPassed);
        uint256 newPrice = (basePrice * multiplierNumerator) / 100;
        basePrice = newPrice;
        lastIncrease = lastIncrease + daysPassed * 1 days;
        emit PriceUpdated(newPrice, block.timestamp);
        return newPrice;
    }

    /* -------------------
       Buy function
       - buyer pays USDT (specified stablecoin)
       - contract transfers TIGG from contract inventory to buyer
       - uses SafeERC20 and nonReentrant
       ------------------- */
    function buy(uint256 tiggAmount) external nonReentrant {
        require(tigg != address(0), "TIGG not set");
        require(usdt != address(0), "USDT not set");
        require(block.timestamp >= saleStart, "Sale not started");
        require(tiggAmount >= minBuy, "Too small");
        require(tiggAmount <= maxBuy, "Too large");

        // Update price (persist new basePrice if days passed)
        uint256 price = applyPriceUpdate();

        // price is price per 1 TIGG (18 decimals). cost in USDT (18 decimals)
        uint256 cost = (tiggAmount * price) / 1 ether;

        // Check inventory
        uint256 contractBal = IERC20(tigg).balanceOf(address(this));
        require(contractBal >= tiggAmount, "Not enough inventory");

        // Transfer USDT from buyer to owner (or to contract if you prefer)
        IERC20(usdt).safeTransferFrom(msg.sender, owner, cost);

        // Transfer TIGG from contract to buyer
        IERC20(tigg).safeTransfer(msg.sender, tiggAmount);

        totalSold += tiggAmount;

        emit Bought(msg.sender, cost, tiggAmount, block.timestamp);
    }
}
