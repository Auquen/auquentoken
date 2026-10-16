// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IPancakeRouter02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

contract AUQUEN is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant MAX_FEE = 10;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    IPancakeRouter02 public immutable router;
    address public immutable pair;

    uint256 public buyFee = 3;
    uint256 public sellFee = 3;
    uint256 public swapThreshold = TOTAL_SUPPLY / 2000;
    bool public swapEnabled = true;
    bool public tradingEnabled;

    mapping(address => bool) public isFeeExempt;

    bool private _inSwap;

    event TradingEnabled();
    event FeesUpdated(uint256 buyFee, uint256 sellFee);
    event SwapThresholdUpdated(uint256 amount);
    event SwapEnabledUpdated(bool enabled);
    event FeeExemptUpdated(address indexed account, bool exempt);
    event AutoLiquidity(uint256 tokensSwapped, uint256 bnbAdded, uint256 tokensAdded);

    modifier lockSwap() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    constructor(address _router) ERC20("AUQUEN", "AQN") Ownable(msg.sender) {
        require(_router != address(0), "router=0");

        router = IPancakeRouter02(_router);
        pair = IPancakeFactory(router.factory()).createPair(address(this), router.WETH());

        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[DEAD] = true;

        _mint(msg.sender, TOTAL_SUPPLY);
    }

    receive() external payable {}

    function _update(address from, address to, uint256 value) internal override {
        if (
            from == address(0) || to == address(0) || _inSwap ||
            isFeeExempt[from] || isFeeExempt[to]
        ) {
            super._update(from, to, value);
            return;
        }

        require(tradingEnabled, "trading not enabled");

        bool isBuy = from == pair;
        bool isSell = to == pair;

        if (isSell && swapEnabled && balanceOf(address(this)) >= swapThreshold) {
            _swapAndLiquify(swapThreshold);
        }

        uint256 fee = 0;
        if (isBuy && buyFee > 0) fee = (value * buyFee) / 100;
        else if (isSell && sellFee > 0) fee = (value * sellFee) / 100;

        if (fee > 0) {
            super._update(from, address(this), fee);
            value -= fee;
        }
        super._update(from, to, value);
    }

    function _swapAndLiquify(uint256 amount) private lockSwap {
        uint256 half = amount / 2;
        uint256 otherHalf = amount - half;

        uint256 bnbBefore = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), amount);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            half, 0, path, address(this), block.timestamp
        );

        uint256 bnbGained = address(this).balance - bnbBefore;

        router.addLiquidityETH{value: bnbGained}(
            address(this), otherHalf, 0, 0, DEAD, block.timestamp
        );

        emit AutoLiquidity(half, bnbGained, otherHalf);
    }

    function setFees(uint256 _buyFee, uint256 _sellFee) external onlyOwner {
        require(_buyFee <= MAX_FEE && _sellFee <= MAX_FEE, "fee > max");
        buyFee = _buyFee;
        sellFee = _sellFee;
        emit FeesUpdated(_buyFee, _sellFee);
    }

    function setSwapThreshold(uint256 amount) external onlyOwner {
        require(amount >= TOTAL_SUPPLY / 100000 && amount <= TOTAL_SUPPLY / 100, "bad threshold");
        swapThreshold = amount;
        emit SwapThresholdUpdated(amount);
    }

    function setSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
        emit SwapEnabledUpdated(enabled);
    }

    function setFeeExempt(address account, bool exempt) external onlyOwner {
        isFeeExempt[account] = exempt;
        emit FeeExemptUpdated(account, exempt);
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "already enabled");
        tradingEnabled = true;
        emit TradingEnabled();
    }

    function manualSwapAndLiquify() external onlyOwner {
        uint256 bal = balanceOf(address(this));
        require(bal > 0, "nothing to swap");
        _swapAndLiquify(bal);
    }
}
