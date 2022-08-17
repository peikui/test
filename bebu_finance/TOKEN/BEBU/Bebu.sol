// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../../utils/math/SafeMath.sol";
import "../../utils/token/ERC20Burnable.sol";

import "../../utils/access/Operator.sol";

/*
    ____       __              _______
   / __ \___  / /_  __  __    / ____(_)___  ____ _____  ________
  / /_/ / __\/ __ \/ / / /   / /_  / / __ \/ __ `/ __ \/ ___/ _ \
 / /_/ /  __/ /_/ / /_/ /   / __/ / / / / / /_/ / / / / /__/  __/
/_.___/\___/_.___/\____/   /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/

    http://bebu.finance
*/

contract Bebu is ERC20Burnable, Operator {
    using SafeMath for uint256;

    // TOTAL MAX SUPPLY = 70,000 tSHAREs
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 20000 ether;
    uint256 public constant STABLE_FARMING_POOL_REWARD_ALLOCATION = 22000 ether;
    uint256 public constant COMMUNITY_FUND_POOL_ALLOCATION = 6000 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 2000 ether;

    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public startTime;
    uint256 public endTime;

    uint256 public communityFundRewardRate;
    uint256 public devFundRewardRate;

    address public communityFund;
    address public devFund;

    uint256 public communityFundLastClaimed;
    uint256 public devFundLastClaimed;

    bool public rewardPoolDistributed = false;

    // blacklist
    mapping(address => bool) public blacklist;

    constructor(uint256 _startTime, address _communityFund, address _devFund) public ERC20("BEBU", "BEBU") {
        _mint(msg.sender, 10 ether); // mint 1 bebu for initial pools deployment

        startTime = _startTime;
        endTime = startTime + VESTING_DURATION;

        communityFundLastClaimed = startTime;
        devFundLastClaimed = startTime;

        communityFundRewardRate = COMMUNITY_FUND_POOL_ALLOCATION.div(VESTING_DURATION);
        devFundRewardRate = DEV_FUND_POOL_ALLOCATION.div(VESTING_DURATION);

        require(_devFund != address(0), "Address cannot be 0");
        devFund = _devFund;

        require(_communityFund != address(0), "Address cannot be 0");
        communityFund = _communityFund;
    }

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

    function setTreasuryFund(address _communityFund) external {
        require(msg.sender == devFund, "!dev");
        communityFund = _communityFund;
    }

    function setDevFund(address _devFund) external {
        require(msg.sender == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function unclaimedTreasuryFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (communityFundLastClaimed >= _now) return 0;
        _pending = _now.sub(communityFundLastClaimed).mul(communityFundRewardRate);
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to community and dev fund
     */
    function claimRewards() external {
        uint256 _pending = unclaimedTreasuryFund();
        if (_pending > 0 && communityFund != address(0)) {
            _mint(communityFund, _pending);
            communityFundLastClaimed = block.timestamp;
        }
        _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    function distributeReward(address _farmingIncentiveFund, address _stableFarmingIncentiveFund) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        require(_stableFarmingIncentiveFund != address(0), "!_stableFarmingIncentiveFund");
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
        _mint(_stableFarmingIncentiveFund, STABLE_FARMING_POOL_REWARD_ALLOCATION);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(!isAddressBlacklist(from), "ERC20: transfer from the blacklist");
        require(!isAddressBlacklist(to), "ERC20: transfer to the blacklist");
        super._transfer(from, to, amount);
    }


    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}