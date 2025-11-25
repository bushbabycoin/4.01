// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// --- OpenZeppelin imports (non-upgradeable) ---
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/access/Ownable.sol";

/**
 * @title BushBabyTokenV4 (BBBY v4 - Non-upgradeable)
 *
 * Features:
 * - Standard ERC20 (no proxy, no upgradeability)
 * - Fixed 50,000,000,000 BBBY supply (18 decimals)
 * - Transfer tax (0–5%) routed to:
 *      - Wealth Fund (treasury)
 *      - Charity Fund
 * - Dedicated founderFund (your free-use wallet)
 * - Anti-whale / anti-bot:
 *      - tradingEnabled flag
 *      - maxTxAmount
 *      - maxWalletAmount
 *      - exclusion list for team / contracts
 *
 * Mint distribution:
 * - founderFund: 5.0% of total supply
 * - wealthFund:  0.1% of total supply
 * - charityFund: 0.1% of total supply
 * - owner_:      94.8% of total supply
 *
 * IMPORTANT:
 * - No mint() function: supply is fixed in the constructor.
 * - Owner is set in the constructor (owner_).
 */
contract BushBabyTokenV4 is ERC20, Ownable {
    // --- Constants ---
    uint16 public constant MAX_TAX_BPS = 500;        // max 5% total tax
    uint16 public constant BPS_DENOMINATOR = 10_000; // 100% in basis points

    // --- Tax + Funds ---
    uint16 public transferTaxBps;              
    uint16 public wealthFundShareOfTaxBps;     
    uint16 public charityFundShareOfTaxBps;    

    address public founderFund;                // renamed from personalFund
    address public wealthFund;
    address public charityFund;

    // --- Trading / Anti-whale ---
    bool public tradingEnabled;
    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;

    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedFromLimits;

    // --- Events ---
    event TransferTaxUpdated(uint16 taxBps);
    event TaxSharesUpdated(uint16 wealthShareBps, uint16 charityShareBps);
    event WealthFundUpdated(address indexed wealthFund);
    event CharityFundUpdated(address indexed charityFund);
    event FounderFundUpdated(address indexed founderFund); // renamed event
    event TradingEnabled(bool enabled);
    event MaxTxAmountUpdated(uint256 maxTxAmount);
    event MaxWalletAmountUpdated(uint256 maxWalletAmount);
    event ExcludedFromFees(address indexed account, bool isExcluded);
    event ExcludedFromLimits(address indexed account, bool isExcluded);

    /**
     * @dev Constructor – runs once at deployment.
     *
     * @param owner_        Owner (ideally a multisig on Base)
     * @param founderFund_  Your personal 5% fund wallet (renamed)
     * @param wealthFund_   Treasury / Wealth Fund address
     * @param charityFund_  Charity address
     */
    constructor(
        address owner_,
        address founderFund_,
        address wealthFund_,
        address charityFund_
    ) ERC20("BushBaby", "BBBY") Ownable(owner_) {
        require(owner_ != address(0), "owner zero");
        require(founderFund_ != address(0), "founderFund zero");
        require(wealthFund_ != address(0), "wealthFund zero");
        require(charityFund_ != address(0), "charityFund zero");

        founderFund = founderFund_;
        wealthFund = wealthFund_;
        charityFund = charityFund_;

        // Default tax config
        transferTaxBps = 0;
        wealthFundShareOfTaxBps = 5_000;
        charityFundShareOfTaxBps = 5_000;

        // 🔥 Fixed supply: 50,000,000,000 BBBY (50 billion)
        uint256 totalSupply_ = 50_000_000_000 * 10 ** decimals();

        // Allocations:
        uint256 founderAmount = (totalSupply_ * 500) / BPS_DENOMINATOR; // 5%
        uint256 wealthAmount  = (totalSupply_ * 10) / BPS_DENOMINATOR;  // 0.1%
        uint256 charityAmount = (totalSupply_ * 10) / BPS_DENOMINATOR;  // 0.1%

        uint256 ownerAmount =
            totalSupply_ - founderAmount - wealthAmount - charityAmount;

        // Mint
        _mint(owner_, ownerAmount);
        _mint(founderFund_, founderAmount);
        _mint(wealthFund_, wealthAmount);
        _mint(charityFund_, charityAmount);

        // Exclusions
        isExcludedFromFees[owner_] = true;
        isExcludedFromFees[founderFund_] = true;
        isExcludedFromFees[wealthFund_] = true;
        isExcludedFromFees[charityFund_] = true;

        isExcludedFromLimits[owner_] = true;
        isExcludedFromLimits[founderFund_] = true;
        isExcludedFromLimits[wealthFund_] = true;
        isExcludedFromLimits[charityFund_] = true;
        isExcludedFromLimits[address(0)] = true;
    }

    // --- Admin setters ---

    function setTransferTaxBps(uint16 _taxBps) external onlyOwner {
        require(_taxBps <= MAX_TAX_BPS, "tax > max");
        transferTaxBps = _taxBps;
        emit TransferTaxUpdated(_taxBps);
    }

    function setTaxShares(uint16 _wealthShareBps, uint16 _charityShareBps)
        external
        onlyOwner
    {
        require(
            _wealthShareBps + _charityShareBps == BPS_DENOMINATOR,
            "shares must sum to 100%"
        );
        wealthFundShareOfTaxBps = _wealthShareBps;
        charityFundShareOfTaxBps = _charityShareBps;
        emit TaxSharesUpdated(_wealthShareBps, _charityShareBps);
    }

    function setWealthFund(address _wealthFund) external onlyOwner {
        require(_wealthFund != address(0), "wealthFund zero");
        wealthFund = _wealthFund;
        emit WealthFundUpdated(_wealthFund);
    }

    function setCharityFund(address _charityFund) external onlyOwner {
        require(_charityFund != address(0), "charityFund zero");
        charityFund = _charityFund;
        emit CharityFundUpdated(_charityFund);
    }

    function setFounderFund(address _founderFund) external onlyOwner {
        require(_founderFund != address(0), "founderFund zero");
        founderFund = _founderFund;
        emit FounderFundUpdated(_founderFund);
    }

    function setTradingEnabled(bool _enabled) external onlyOwner {
        tradingEnabled = _enabled;
        emit TradingEnabled(_enabled);
    }

    function setMaxTxAmount(uint256 _maxTxAmount) external onlyOwner {
        maxTxAmount = _maxTxAmount;
        emit MaxTxAmountUpdated(_maxTxAmount);
    }

    function setMaxWalletAmount(uint256 _maxWalletAmount) external onlyOwner {
        maxWalletAmount = _maxWalletAmount;
        emit MaxWalletAmountUpdated(_maxWalletAmount);
    }

    function setExcludedFromFees(address account, bool excluded)
        external
        onlyOwner
    {
        isExcludedFromFees[account] = excluded;
        emit ExcludedFromFees(account, excluded);
    }

    function setExcludedFromLimits(address account, bool excluded)
        external
        onlyOwner
    {
        isExcludedFromLimits[account] = excluded;
        emit ExcludedFromLimits(account, excluded);
    }

    // --- Core hook: enforce tax + limits ---
    function _update(address from, address to, uint256 value)
        internal
        override
    {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        if (!tradingEnabled) {
            require(
                isExcludedFromLimits[from] || isExcludedFromLimits[to],
                "trading not enabled"
            );
        }

        if (
            maxTxAmount > 0 &&
            !isExcludedFromLimits[from] &&
            !isExcludedFromLimits[to]
        ) {
            require(value <= maxTxAmount, "max tx exceeded");
        }

        uint256 sendAmount = value;
        uint256 taxAmount = 0;

        if (
            transferTaxBps > 0 &&
            !isExcludedFromFees[from] &&
            !isExcludedFromFees[to]
        ) {
            taxAmount = (value * transferTaxBps) / BPS_DENOMINATOR;
            sendAmount = value - taxAmount;

            uint256 wealthAmount =
                (taxAmount * wealthFundShareOfTaxBps) / BPS_DENOMINATOR;
            uint256 charityAmount = taxAmount - wealthAmount;

            if (wealthAmount > 0) {
                super._update(from, wealthFund, wealthAmount);
            }
            if (charityAmount > 0) {
                super._update(from, charityFund, charityAmount);
            }
        }

        if (
            maxWalletAmount > 0 &&
            !isExcludedFromLimits[to]
        ) {
            uint256 newBalance = balanceOf(to) + sendAmount;
            require(newBalance <= maxWalletAmount, "max wallet exceeded");
        }

        super._update(from, to, sendAmount);
    }
}
