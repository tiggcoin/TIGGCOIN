pragma solidity 0.8.27;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IRouter {
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
}

contract TIGGsale {
    address public owner;
    address public usdt;
    address public tigg;
    uint256 public basePrice;
    uint256 public autoIncreasePercent;
    uint256 public lastIncrease;
    uint256 public saleStart;
    uint256 public minBuy;
    uint256 public maxBuy;
    uint256 public totalSold;
    uint256 public manualPrice;

    event Bought(address buyer, uint256 usdtAmount, uint256 tiggAmount, uint256 timestamp);
    event PriceUpdated(uint256 newPrice, uint256 timestamp);

    constructor() {
        owner = msg.sender;
        saleStart = 1734048000;
        basePrice = 10 ether;
        autoIncreasePercent = 1;
        lastIncrease = saleStart;
        minBuy = 1 ether;
        maxBuy = 100000000 ether;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function setUSDT(address a) external onlyOwner {
        usdt = a;
    }

    function setTIGG(address a) external onlyOwner {
        tigg = a;
    }

    function setManualPrice(uint256 p) external onlyOwner {
        manualPrice = p;
        emit PriceUpdated(p, block.timestamp);
    }

    function currentPrice() public returns (uint256) {
        if (manualPrice > 0) return manualPrice;
        if (block.timestamp <= saleStart) return basePrice;
        if (block.timestamp >= lastIncrease + 1 days) {
            uint256 daysPassed = (block.timestamp - lastIncrease) / 1 days;
            for (uint256 i = 0; i < daysPassed; i++) {
                basePrice = basePrice + ((basePrice * autoIncreasePercent) / 100);
            }
            lastIncrease = lastIncrease + (daysPassed * 1 days);
        }
        return basePrice;
    }

    function buy(uint256 tiggAmount) external {
        require(tigg != address(0), "TIGG not set");
        require(usdt != address(0), "USDT not set");
        require(block.timestamp >= saleStart, "Sale not started");
        require(tiggAmount >= minBuy, "Too small");
        require(tiggAmount <= maxBuy, "Too large");

        uint256 price = currentPrice();
        uint256 cost = (tiggAmount * price) / 1 ether;

        require(IERC20(usdt).transferFrom(msg.sender, owner, cost), "USDT transfer fail");
        require(IERC20(tigg).transferFrom(owner, msg.sender, tiggAmount), "TIGG transfer fail");

        totalSold += tiggAmount;

        emit Bought(msg.sender, cost, tiggAmount, block.timestamp);
    }

    function withdrawTIGG(uint256 amount) external onlyOwner {
        IERC20(tigg).transfer(owner, amount);
    }

    function withdrawUSDT(uint256 amount) external onlyOwner {
        IERC20(usdt).transfer(owner, amount);
    }
}
