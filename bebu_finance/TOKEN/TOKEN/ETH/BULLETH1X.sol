// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../../../utils/Address.sol";
import "../../../utils/library/UniswapV2Library.sol";
import "../../../utils/access/Operator.sol";

import "../../../utils/math/SafeMath8.sol";
import "../../../utils/math/Babylonian.sol";
import "../../../utils/math/Math.sol";

import "../../../utils/interfaces/IOracle.sol";
import "../../../utils/interfaces/IUniswapV2Pair.sol";
import "../../../utils/interfaces/IUniswapV2Router01.sol";
import "../../../utils/interfaces/ITreasury.sol";
import "../../../utils/token/ERC20Burnable.sol";

/*
    ____       __              _______
   / __ \___  / /_  __  __    / ____(_)___  ____ _____  ________
  / /_/ / __\/ __ \/ / / /   / /_  / / __ \/ __ `/ __ \/ ___/ _ \
 / /_/ /  __/ /_/ / /_/ /   / __/ / / / / / /_/ / / / / /__/  __/
/_.___/\___/_.___/\____/   /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/

    http://bebu.finance
*/
contract BULLETH1X is ERC20Burnable, Operator {

    using SafeMath for uint256;
    using SafeMath8 for uint8;
    using Address for address;

    // Initial distribution for the first 24h genesis pools
    uint256 public constant INITIAL_GENESIS_POOL_DISTRIBUTION = 11000 ether;
    // Initial distribution for the day 2-5 token-WFTM LP -> token pool
    uint256 public constant INITIAL_token_POOL_DISTRIBUTION = 140000 ether;
    // Distribution for airdrops wallet
    uint256 public constant INITIAL_AIRDROP_WALLET_DISTRIBUTION = 9000 ether;

    // Address of the router & pair
    address public router;
    address public pair;

    // Address of the Treasury
    address public treasury;

    // Address of the Oracle
    address public tokenOracle;

    // transaction trigger
    bool public transactionOn = false;

    // tax trigger
    bool public autoCalculateTax = false;

    //reward trigger
    bool public autoCalculateReward = false;
    
    //forbid sell
    bool public forbidSellWithLowPrice = false;

    //tax threshold
    uint256 public taxThreshold = 9900;

    //tax coefficient
    uint256 public taxCoefficient = 10000;

    //reward threshold
    uint256 public rewardThreshold = 9900;

    //reward coefficient
    uint256 public rewardCoefficient = 5000;

    // tokens burn rate of tax  when open the tax
    uint256 public burnRate = 8000;

    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;

    // Sender addresses excluded from Tax
    mapping(address => bool) public excludedAddressesTax;

    // receiptor addresses excluded from Reward
    mapping(address => bool) public excludedAddressesReward;

    // blacklist
    mapping(address => bool) public blacklist;

    // AMM pair addresses
    mapping(address => uint) public automatedMarketMakerPairs;

    modifier isPair(address _recipient) {
        {
            uint256 size;
            assembly {
                size := extcodesize(_recipient)
            }
            if (size > 0) {
                uint256 recipientTier = automatedMarketMakerPairs[_recipient];
                if (recipientTier == 0) {
                    try IUniswapV2Router01(_recipient).factory() returns (address factory) {
                        automatedMarketMakerPairs[_recipient] = 2;
                    } catch {
                        automatedMarketMakerPairs[_recipient] = 1;
                    }
                }
            }
        }

        _;
    }

    /**
     * @notice Constructs the token ERC-20 contract.
     */
    constructor() public ERC20("BULLETH1X", "BULLETH1X") {
        // Mints 1 token to contract creator for initial pool setup

        excludeAddressTax(address(this));

        _mint(msg.sender, 1 ether);

    }

    function enableTransaction() external onlyOwner {
        require(!transactionOn, "alredy enabled");
        transactionOn = true;
    }

    function disableTransaction() external onlyOwner {
        require(transactionOn, "alredy disabled");
        transactionOn = false;
    }

    function disableSell() external onlyOwner {
        require(!forbidSellWithLowPrice, "alredy disabled");
        forbidSellWithLowPrice = true;
    }

    function enableSell() external onlyOwner {
        require(forbidSellWithLowPrice, "alredy enabled");
        forbidSellWithLowPrice = false;
    }
    
    function _isContract(address _address) public view returns (bool) {
        return _address.isContract();
    }

    function isAutomatedMarketMakerPair(address _address) public view returns (bool) {
        if (_isContract(_address)) {
            return automatedMarketMakerPairs[_address] == 2;
        }
        return false;
    }

    /* ================= blacklist =============== */

    function addAddressBlacklist(address _address) public onlyOwner returns (bool) {
        require(!blacklist[_address], "address already added");
        blacklist[_address] = true;
        return true;
    }

    function removeAddressBlacklist(address _address) public onlyOwner returns (bool) {
        require(blacklist[_address], "address not existed");
        blacklist[_address] = false;
        return true;
    }
    
    function isAddressBlacklist(address _address) public view returns (bool) {
        return blacklist[_address];
    }

    /* ================= Tax list =============== */

    function excludeAddressTax(address _address) public onlyOwner returns (bool) {
        require(!excludedAddressesTax[_address], "address can't be excluded");
        excludedAddressesTax[_address] = true;
        return true;
    }

    function includeAddressTax(address _address) public onlyOwner returns (bool) {
        require(excludedAddressesTax[_address], "address can't be included");
        excludedAddressesTax[_address] = false;
        return true;
    }
    
    function isAddressExcludedTax(address _address) public view returns (bool) {
        return excludedAddressesTax[_address];
    }
    
    function setTaxCoefficient(uint256 _taxCoefficient) external onlyOwner {
        require(_taxCoefficient >= 0 && _taxCoefficient <= 20000, "out of range");
        taxCoefficient = _taxCoefficient;
    }

    /* ================= Reward list =============== */

    function excludeAddressReward(address _address) public onlyOwner returns (bool) {
        require(!excludedAddressesReward[_address], "address can't be excluded");
        excludedAddressesReward[_address] = true;
        return true;
    }

    function includeAddressReward(address _address) public onlyOwner returns (bool) {
        require(excludedAddressesReward[_address], "address can't be included");
        excludedAddressesReward[_address] = false;
        return true;
    }
    
    function isAddressExcludedReward(address _address) public view returns (bool) {
        return excludedAddressesReward[_address];
    }

    function setRewardCoefficient(uint256 _rewardCoefficient) external onlyOwner {
        require(_rewardCoefficient >= 0 && _rewardCoefficient <= 20000, "out of range");
        rewardCoefficient = _rewardCoefficient;
    }

    /* ================= Oracle =============== */

    function _gettokenPrice() public view returns (uint256 _tokenPrice) {
        try IOracle(tokenOracle).consult(address(this), 1e18) returns (uint144 _price) {
            return uint256(_price);
        } catch {
            revert("token: failed to fetch token price from Oracle");
        }
    }

    function _getTokenTwapPrice() public view returns (uint256 _tokenPrice) {
        try IOracle(tokenOracle).twap(address(this), 1e18) returns (uint144 _price) {
            return uint256(_price);
        } catch {
            revert("token: failed to fetch token price from Oracle");
        }
    }

    function _getTokenRealtimeIndexPrice() public view returns (uint) {
        return ITreasury(treasury).getRealtimeTokenIndexPrice();
    }

    function _getTokenRealtimePrice() public view returns (uint) {
        (uint256 amount0, uint256 amount1, ) = IUniswapV2Pair(pair).getReserves();
        return amount0.mul(1e18).div(amount1);
    }

    // token price right after user executed token ==> usdc swap
    function _getAfterSwapPrice(uint amountIn) public view returns (uint) {
        (uint256 amount0, uint256 amount1, ) = IUniswapV2Pair(pair).getReserves();
        uint256 amountOut = IUniswapV2Router01(router).getAmountOut(amountIn, amount1, amount0);
        return (amount0 - amountOut).mul(1e18).div(amount1 + amountIn);
    }

    /* ================= configuration =============== */
    function setTokenOracle(address _tokenOracle) external onlyOwner {
        require(_tokenOracle != address(0), "oracle address cannot be 0 address");
        tokenOracle = _tokenOracle;
    }
        
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "zero");
        treasury = _treasury;
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "zero");
        router = _router;
    }

    function setPair(address _pair) external onlyOwner {
        require(_pair != address(0), "zero");
        pair = _pair;
    }

    function setTaxThreshold(uint256 _TaxThreshold) external onlyOwner {
        require(_TaxThreshold >= 0 && _TaxThreshold <= 10000, "out of range");//[0, 100%]
        taxThreshold = _TaxThreshold;
    }

    function setRewardThreshold(uint256 _RewardThreshold) external onlyOwner {
        require(_RewardThreshold >= 0 && _RewardThreshold <= 10000, "out of range");//[0, 100%]
        rewardThreshold = _RewardThreshold;
    }

    function setBurnRate(uint256 _burnRate) external onlyOwner {
        require(_burnRate >= 0 && _burnRate <= 10000, "out of range");//[0, 100%]
        burnRate = _burnRate;
    }

    /* ================= Taxation =============== */

    function enableAutoCalculateTax() external onlyOwner {
        autoCalculateTax = true;
    }

    function disableAutoCalculateTax() external onlyOwner {
        autoCalculateTax = false;
    }

    function calculateTax(uint amount) public view returns (uint tax) {
        uint256 AfterSwapPrice = _getAfterSwapPrice(amount);
        uint256 IndexPrice = _getTokenRealtimeIndexPrice();
        if (AfterSwapPrice < IndexPrice.mul(taxThreshold).div(10000)) {
            if (forbidSellWithLowPrice) {
                require(AfterSwapPrice.mul(2) > IndexPrice, "price too low");
            }
            tax = _calculateTax(amount, AfterSwapPrice, IndexPrice);
        } else {
            tax = 0;
        }
    }

    //calculate tax 
    function _calculateTax(uint amount, uint _AfterSwapPrice, uint _IndexPrice) internal view returns (uint tax) {
        uint diff = _IndexPrice - _AfterSwapPrice;
        uint numerator = diff.mul(2);
        uint denominator = Babylonian.sqrt(diff.mul(diff).mul(16) + _IndexPrice.mul(_IndexPrice));
        tax = amount.mul(numerator).div(denominator).mul(taxCoefficient).div(10000);
    }

    /* ================= Reward =============== */

    function enableAutoCalculateReward() external onlyOwner {
        autoCalculateReward = true;
    }

    function disableAutoCalculateReward() external onlyOwner {
        autoCalculateReward = false;
    }

    function calculateReward(uint amount) public view returns (uint reward) {
        uint256 RealtimePrice = _getTokenRealtimePrice();
        uint256 IndexPrice = _getTokenRealtimeIndexPrice();
        if (RealtimePrice < IndexPrice.mul(rewardThreshold).div(10000)) {
            reward = _calculateReward(amount, RealtimePrice, IndexPrice);
        } else {
            reward = 0;
        }
    }

    //calculate reward
    function _calculateReward(uint amount, uint _RealtimePrice, uint _IndexPrice) internal view returns (uint reward) {
        uint diff = _IndexPrice - _RealtimePrice;
        uint numerator = diff.mul(2);
        uint denominator = Babylonian.sqrt(diff.mul(diff).mul(16) + _IndexPrice.mul(_IndexPrice));
        reward = amount.mul(numerator).div(denominator).mul(rewardCoefficient).div(10000);
    }

    // View function to see usdc amount out on frontend.
    function getUSDCAmountOut(uint amountIn) public view returns (uint amountOut) {
        uint tax = calculateTax(amountIn);
        amountIn = amountIn.sub(tax);
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        amountOut = IUniswapV2Router01(router).getAmountOut(amountIn, reserve1, reserve0);
    }

    // View function to see token amount out on frontend.
    function getTokenAmountOut(uint amountIn) public view returns (uint amountOut) {
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        amountOut = IUniswapV2Router01(router).getAmountOut(amountIn, reserve0, reserve1);
    }

    /**
     * @notice Operator mints token to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of token to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOperator {
        super.burnFrom(account, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal override isPair(to) {
        require(transactionOn == true, "can not transfer");
        require(from != address(0), "ERC20: transfer from the zero address");
        require(!isAddressBlacklist(from), "ERC20: transfer from the blacklist");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!isAddressBlacklist(to), "ERC20: transfer to the blacklist");

        // tokens transfered from pair address to EOA 
        if (from == pair && !_isContract(to)) {
            if (autoCalculateReward && !isAddressExcludedReward(to)) {
                uint256 reward = calculateReward(amount);
                if (reward > 0) {
                    super._mint(to, reward);
                }
            }
        }
        
        // tokens transfered to amm pair addresses
        if (isAutomatedMarketMakerPair(to)) {
            if (autoCalculateTax && !isAddressExcludedTax(to)) {
                uint256 tax = calculateTax(amount);
                if (tax > 0) {
                    amount = amount.sub(tax);
                    uint256 burnAmount = tax.mul(burnRate).div(10000);
                    _burn(from, burnAmount);
                    tax = tax.sub(burnAmount);
                    super._transfer(from, treasury, tax);
                }
            }
        }
        super._transfer(from, to, amount);
    }

    
    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(
        address _genesisPool,
        address _tokenPool,
        address _airdropWallet
    ) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_genesisPool != address(0), "!_genesisPool");
        require(_tokenPool != address(0), "!_tokenPool");
        require(_airdropWallet != address(0), "!_airdropWallet");
        rewardPoolDistributed = true;
        _mint(_genesisPool, INITIAL_GENESIS_POOL_DISTRIBUTION);
        _mint(_tokenPool, INITIAL_token_POOL_DISTRIBUTION);
        _mint(_airdropWallet, INITIAL_AIRDROP_WALLET_DISTRIBUTION);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        _token.transfer(_to, _amount);
    }
}