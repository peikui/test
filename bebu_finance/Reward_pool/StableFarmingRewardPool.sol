// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";
import "../utils/math/SafeMath.sol";

/*
    ____       __              _______
   / __ \___  / /_  __  __    / ____(_)___  ____ _____  ________
  / /_/ / __\/ __ \/ / / /   / /_  / / __ \/ __ `/ __ \/ ___/ _ \
 / /_/ /  __/ /_/ / /_/ /   / __/ / / / / / /_/ / / / / /__/  __/
/_.___/\___/_.___/\____/   /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/

    http://bebu.finance
*/

// Note that this pool has no minter key of Bebu (rewards).
// Instead, the governance will call Bebu distributeReward method and send reward to this pool at the beginning.
contract StableFarmingRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many  tokens the user has provided.
        uint256 TimerStart; // when the user deposit the tokens.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Bebus to distribute per block.
        uint256 lastRewardTime; // Last time that Bebus distribution occurs.
        uint256 accBebuPerShare; // Accumulated Bebus per share, times 1e18. See below.
        bool isStarted; // if lastRewardTime has passed
    }

    struct TwoPoolInfo {
        uint256 pool0;
        uint256 pool1;
    }

    IERC20 public Bebu;

    // Info of each two pool
    TwoPoolInfo[] public twoPoolInfo;

    // Index of TwoPoolInfo;
    uint256 index = 0;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // blacklist
    mapping(address => bool) public blacklist;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when Bebu mining starts.
    uint256 public poolStartTime;

    // The time when Bebu mining ends.
    uint256 public poolEndTime;

    // withdraw and claim reward period
    uint256 public period = 8 hours;
    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    uint256 public BebuPerSecond = 0.0006976 ether; // 42000 Bebu / (365 days * 24h * 60min * 60s)
    uint256 public runningTime = 365 days; // 365 days
    uint256 public constant TOTAL_REWARDS = 22000 ether;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _Bebu,
        uint256 _poolStartTime
    ) public {
        require(block.timestamp < _poolStartTime, "late");
        if (_Bebu != address(0)) Bebu = IERC20(_Bebu);
        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + runningTime;

        withdrawLockupEpochs = 6; // Lock for 6 epochs (48h) before release withdraw
        rewardLockupEpochs = 1; // Lock for 3 epochs (24h) before release claimReward
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "BebuRewardPool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "BebuRewardPool: existing pool?");
        }
    }

    function setPeriod(uint256 _period) external onlyOperator {
        require(_period >= 0 && _period <= 24 hours, "out of range");
        period = _period;
    }

    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        require(_withdrawLockupEpochs >= _rewardLockupEpochs && _withdrawLockupEpochs <= 42, "_withdrawLockupEpochs: out of range"); // <= 2 week
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    function canWithdraw(uint256 _pid, address _user) external view returns (bool) {
        return userInfo[_pid][_user].TimerStart.add(withdrawLockupEpochs.mul(period)) <= block.timestamp;
    }

    function canClaimReward(uint256 _pid, address _user) external view returns (bool) {
        return userInfo[_pid][_user].TimerStart.add(rewardLockupEpochs.mul(period)) <= block.timestamp;
    }

    function addAddressBlacklist(address _address) public onlyOperator returns (bool) {
        require(!blacklist[_address], "address already added");
        blacklist[_address] = true;
        return true;
    }

    function removeAddressBlacklist(address _address) public onlyOperator returns (bool) {
        require(blacklist[_address], "address not existed");
        blacklist[_address] = false;
        return true;
    }
    
    function isAddressBlacklist(address _address) public view returns (bool) {
        return blacklist[_address];
    }

    // Add a new index-token pair to the pool. Can only be called by the owner.
    function addTwoPool(
        uint256 _allocPoint,
        IERC20 _token0,
        IERC20 _token1,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) public onlyOperator {
        require(_allocPoint % 2 == 0, "allocPoint must be even");
        add(_allocPoint.div(2), _token0, _withUpdate, _lastRewardTime);
        add(_allocPoint.div(2), _token1, _withUpdate, _lastRewardTime);
        twoPoolInfo.push(TwoPoolInfo({
            pool0 : index,
            pool1 : index.add(1)
        }));
        index = index.add(2);
    }

    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) internal onlyOperator {
        checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted =
        (_lastRewardTime <= poolStartTime) ||
        (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({
            token : _token,
            allocPoint : _allocPoint,
            lastRewardTime : _lastRewardTime,
            accBebuPerShare : 0,
            isStarted : _isStarted
            }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's Bebu allocation point. Can only be called by the owner.
    function setTwoPool(uint256 _pid, uint256 _allocPoint) public onlyOperator {
        require(_allocPoint % 2 == 0, "allocPoint must be even");
        _allocPoint = _allocPoint.div(2);
        uint256 pool0 = twoPoolInfo[_pid].pool0;  
        uint256 pool1 = twoPoolInfo[_pid].pool1;
        set(pool0, _allocPoint);
        set(pool1, _allocPoint);
    }

    function set(uint256 _pid, uint256 _allocPoint) internal onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(BebuPerSecond);
            return poolEndTime.sub(_fromTime).mul(BebuPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(BebuPerSecond);
            return _toTime.sub(_fromTime).mul(BebuPerSecond);
        }
    }

    // View function to see two pool pending Bebus on frontend.
    function twoPoolPendingShare(uint256 _pid, address _user) public view returns(uint256, uint256) {
        uint256 pool0 = twoPoolInfo[_pid].pool0;  
        uint256 pool1 = twoPoolInfo[_pid].pool1;    
        return (pendingShare(pool0, _user), pendingShare(pool1, _user));
    }

    function pendingShare(uint256 _pid, address _user) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBebuPerShare = pool.accBebuPerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _BebuReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accBebuPerShare = accBebuPerShare.add(_BebuReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accBebuPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _BebuReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accBebuPerShare = pool.accBebuPerShare.add(_BebuReward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    function depositTwoTokens(uint256 _pid, uint256 amount) public {
        require(!isAddressBlacklist(msg.sender), "blacklist");
        uint256 _pool0 = twoPoolInfo[_pid].pool0;
        uint256 _pool1 = twoPoolInfo[_pid].pool1;
        deposit(_pool0, amount);
        deposit(_pool1, amount);
    }
    
    function withdrawTwoTokens(uint256 _pid, uint256 amount) public {
        require(!isAddressBlacklist(msg.sender), "blacklist");
        uint256 _pool0 = twoPoolInfo[_pid].pool0;
        uint256 _pool1 = twoPoolInfo[_pid].pool1;
        withdraw(_pool0, amount);
        withdraw(_pool1, amount);
    }

    // Deposit  tokens.
    function deposit(uint256 _pid, uint256 _amount) internal {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accBebuPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                if (user.TimerStart.add(rewardLockupEpochs.mul(period)) <= block.timestamp) {
                    safeBebuTransfer(_sender, _pending);
                    emit RewardPaid(_sender, _pending);
                }
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.TimerStart = block.timestamp;// reset timer
        user.rewardDebt = user.amount.mul(pool.accBebuPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw  tokens.
    function withdraw(uint256 _pid, uint256 _amount) internal {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accBebuPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            require(user.TimerStart.add(rewardLockupEpochs.mul(period)) <= block.timestamp, "StableFarmingRewardPool: still in reward lockup");
            safeBebuTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            require(user.TimerStart.add(withdrawLockupEpochs.mul(period)) <= block.timestamp, "StableFarmingRewardPool: still in withdraw lockup");
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBebuPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    function claimReward(uint256 _pid) external {
        withdrawTwoTokens(_pid, 0);
    }

    // Safe Bebu transfer function, just in case if rounding error causes pool to not have enough Bebus.
    function safeBebuTransfer(address _to, uint256 _amount) internal {
        uint256 _BebuBal = Bebu.balanceOf(address(this));
        if (_BebuBal > 0) {
            if (_amount > _BebuBal) {
                Bebu.safeTransfer(_to, _BebuBal);
            } else {
                Bebu.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }
    
    function blacklistFundWithdraw(address _address, address _to) external onlyOperator {
        require(isAddressBlacklist(_address), "address not in the blacklist");
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][_address];
            uint256 _amount = user.amount;
            user.amount = 0;
            user.rewardDebt = 0;
            pool.token.safeTransfer(_to, _amount);
        }
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        if (block.timestamp < poolEndTime + 90 days) {
            // do not allow to drain core token (Bebu or lps) if less than 90 days after pool ends
            require(_token != Bebu, "Bebu");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }
}