// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../../utils/math/Math.sol";
import "../../utils/token/IERC20.sol";
import "../../utils/token/SafeERC20.sol";
import "../../utils/token/ERC20Burnable.sol";
import "../../utils/security/ReentrancyGuard.sol";

import "../../utils/math/Babylonian.sol";
import "../../utils/access/Operator.sol";
import "../../utils/security/ContractGuard.sol";
import "../../utils/interfaces/IBasisAsset.sol";
import "../../utils/interfaces/IOracle.sol";
import "../../utils/interfaces/IBoardroom.sol";

import "../../utils/interfaces/AggregatorV3Interface.sol";

/*
    ____       __              _______
   / __ \___  / /_  __  __    / ____(_)___  ____ _____  ________
  / /_/ / __\/ __ \/ / / /   / /_  / / __ \/ __ `/ __ \/ ___/ _ \
 / /_/ /  __/ /_/ / /_/ /   / __/ / / / / / /_/ / / / / /__/  __/
/_.___/\___/_.___/\____/   /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/

    http://bebu.finance
*/

contract BULLETH1X_Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // period
    uint256 public period = 8 hours;

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;

    // core components
    address public token;
    address public share;

    address public boardroom;
    address public tokenOracle;

    // price
    uint256 public tokenPriceCeiling;

    uint256 public maxSupplyExpansionPercent;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    //eth price oracle
    AggregatorV3Interface internal priceFeed = AggregatorV3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945);

    /* =================== Added variables =================== */
    uint256 public initialEpochEthPrice;
    uint256 public currentEpochEthPrice;
    uint256 public initialEpochTokenIndexPrice;
    uint256 public currentEpochTokenIndexPrice;
    uint256 public previousEpochTokenTwapPrice;

    address public daoFund;
    uint256 public daoFundSharedPercent;

    address public devFund;
    uint256 public devFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition {
        require(now >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch {
        require(now >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
    }

    modifier checkOperator {
        require(
            IBasisAsset(token).operator() == address(this) &&
            Operator(boardroom).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    constructor() public {
        operator = msg.sender;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(period));
    }

    // oracle,decimals: 6
    function getTokenPrice() public view returns (uint256 tokenPrice) {
        try IOracle(tokenOracle).consult(token, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult token price from the oracle");
        }
    }

    function getTokenUpdatedPrice() public view returns (uint256 _tokenPrice) {
        try IOracle(tokenOracle).twap(token, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult token price from the oracle");
        }
        
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _token,
        address _share,
        address _tokenOracle,
        address _boardroom,
        uint256 _startTime
    ) public notInitialized {
        token = _token;
        share = _share;
        tokenOracle = _tokenOracle;
        boardroom = _boardroom;
        startTime = _startTime;

        tokenPriceCeiling = 10100;

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 500000 ether, 1000000 ether, 1500000 ether, 2000000 ether, 5000000 ether, 10000000 ether, 20000000 ether, 50000000 ether];
        maxExpansionTiers = [450, 400, 350, 300, 250, 200, 150, 125, 100];

        initialized = true;
        initialEpochEthPrice = uint256(getLatestEthPrice());
        _updateTokenPrice();
        initialEpochTokenIndexPrice = getTokenPrice();

        emit Initialized(msg.sender, block.number);
    }

    function setPeriod(uint256 _period) external onlyOperator {
        period = _period;
        IOracle(tokenOracle).setPeriod(_period);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setBoardroom(address _boardroom) external onlyOperator {
        boardroom = _boardroom;
    }

    function setTokenOracle(address _tokenOracle) external onlyOperator {
        tokenOracle = _tokenOracle;
    }

    function setTokenPriceCeiling(uint256 _tokenPriceCeiling) external onlyOperator {
        require(_tokenPriceCeiling >= 10000 && _tokenPriceCeiling <= 12000, "out of range"); // [$1.0, $1.2]
        tokenPriceCeiling = _tokenPriceCeiling;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 3000, "out of range"); // <= 30%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 1000, "out of range"); // <= 10%
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < 8) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 1000, "_value: out of range"); // [0.1%, 10%]
        maxExpansionTiers[_index] = _value;
        return true;
    }


    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateTokenPrice() internal {
   //     try IOracle(tokenOracle).update() {} catch {}
        IOracle(tokenOracle).update();
    }

    function getTokenCirculatingSupply() public view returns (uint256) { 
        return IERC20(token).totalSupply();
    }

    function _sendToBoardroom(uint256 _amount) internal {
        IBasisAsset(token).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(token).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(now, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(token).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(now, _devFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);

        IERC20(token).safeApprove(boardroom, 0);
        IERC20(token).safeApprove(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(now, _amount);
    }

    /**
     * Returns the latest eth price,decimals: 8
     */
    function getLatestEthPrice() public view returns (int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return price;
    }

    function getIndexPrice(uint _currentEthPrice, uint _initialEpochEthPrice, uint _initialTokenIndexPrice) public pure returns (uint) {
        uint IndexPrice = _currentEthPrice.mul(_initialTokenIndexPrice).div(_initialEpochEthPrice);
        return IndexPrice;
    }

    function getRealtimeTokenIndexPrice() public view returns (uint256) {
        uint256 RealtimeEthPrice = uint256(getLatestEthPrice());
        uint256 RealtimeTokenIndexPrice = getIndexPrice(RealtimeEthPrice, initialEpochEthPrice, initialEpochTokenIndexPrice);
        return RealtimeTokenIndexPrice;
    }  

    function _calculateMaxSupplyExpansionPercent(uint256 _tokenSupply) internal returns (uint256) {
        for (uint8 tierId = 8; tierId >= 0; --tierId) {
            if (_tokenSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateTokenPrice();
        previousEpochTokenTwapPrice = getTokenPrice();
        currentEpochEthPrice = uint256(getLatestEthPrice());
        currentEpochTokenIndexPrice = getRealtimeTokenIndexPrice();
        if(currentEpochTokenIndexPrice <= 1e6 || currentEpochTokenIndexPrice >= 1e8){
            currentEpochTokenIndexPrice = 1e7;
        }
        uint256 tokenSupply = getTokenCirculatingSupply();
        if (previousEpochTokenTwapPrice > currentEpochTokenIndexPrice.mul(tokenPriceCeiling).div(10000)) {
            uint256 _percentage = previousEpochTokenTwapPrice - currentEpochTokenIndexPrice.mul(tokenPriceCeiling).div(10000);
            uint256 _mse = _calculateMaxSupplyExpansionPercent(tokenSupply).mul(currentEpochTokenIndexPrice).div(10000);
            if (_percentage > _mse) {
                _percentage = _mse;
            }
            uint256 _savedForBoardroom = tokenSupply.mul(_percentage).div(currentEpochTokenIndexPrice);
            if (_savedForBoardroom > 0) {
                _sendToBoardroom(_savedForBoardroom);
            }
        }
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.safeTransfer(_to, _amount);
    }

    function boardroomSetOperator(address _operator) external onlyOperator {
        IBoardroom(boardroom).setOperator(_operator);
    }

    function boardroomSetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IBoardroom(boardroom).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function boardroomSetFee(uint _fee) external onlyOperator {
        IBoardroom(boardroom).setFee(_fee);
    }

    function boardroomAllocateSeigniorage(uint256 amount) external onlyOperator {
        IBoardroom(boardroom).allocateSeigniorage(amount);
    }

    function boardroomGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IBoardroom(boardroom).governanceRecoverUnsupported(_token, _amount, _to);
    }

    function burnTreasuryToken(uint256 amount) external onlyOperator {
        ERC20Burnable(token).burn(amount);
    }
}