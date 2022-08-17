from brownie import accounts, Contract
import time

operator_wallet = accounts.add(config['PRIVATE_KEY_OPERATOR'])
test_wallet = accounts.add(config['PRIVATE_KEY_TEST'])

usdc = '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'
dao_fund = '0x0514925143fE17d7b2631E08937F3952ae785D80'
dev_fund = '0x2BBaC681adB2C90bfa1e82e3770dFAC6Af8093Df'
#   operator_wallet = '0xb2F8F0A7aa1567Dd5DcDBa22D9Be73684152E9Cb'
#   test_wallet = '0x269ad1a2dB6a883De0Da386710c301A86A67A277'
zhangjie_test_wallet = '0x10A2A9905E97789074E51c79800747b6960e1131'

OneEther = 1000000000000000000
OneUsdc = 1000000
fee = 200
uint256_max = 115792089237316195423570985008687907853269984665640564039457584007913129639935
tx_config = {'from': operator_wallet, 'gas': '10000000',
             'priority_fee': '40 gwei', 'max_fee': '70 gwei', 'allow_revert': True}

current_time = int(time.time())
print("current unix time:", current_time)
period = input("set oracle period:")
treasury_start_time = int(input("set treasury start time:")) + current_time
oracle_start_time = int(input("set oracle start time:")) + current_time
bebu_start_time = int(input("set bebu start time:")) + current_time
reward_pool_start_time = int(input("set reward_pool start time:")) + current_time
stable_farming_reward_pool_start_time = int(input("set stable_farming_reward_pool start time:")) + current_time

quickswap_router = Contract.from_explorer('0xa5e0829caced8ffdd4de3c43696c57f7d7a678ff')
bebu = Bebu.deploy(bebu_start_time, dao_fund, dev_fund, tx_config)
bebuRewardPool = BebuRewardPool.deploy(bebu, reward_pool_start_time, tx_config)
stableFarmingRewardPool = StableFarmingRewardPool.deploy(bebu, stable_farming_reward_pool_start_time, tx_config)
bebu.distributeReward(bebuRewardPool, stableFarmingRewardPool, tx_config)

#   ------------------------------------------------- BULLETH1X---------------------------------------------------------

token1 = BULLETH1X.deploy(tx_config)

boardroom1 = Boardroom.deploy(tx_config)
treasury1 = BULLETH1X_Treasury.deploy(tx_config)
token1.enableTransaction(tx_config)
token1.approve(quickswap_router, uint256_max, tx_config)
#    tx = quickswap_router.addLiquidity(token1, usdc, OneEther / 10, OneUsdc, OneEther / 10, OneUsdc, operator_wallet, int(time.time()) + 120, tx_config)
#    lp_pair1 = tx.new_contracts[0]
token1.mint(test_wallet, OneEther * 1000, tx_config)
token1.mint(zhangjie_test_wallet, OneEther * 1000, tx_config)
token1.mint(operator_wallet, OneEther * 1000, tx_config)
quickswap_router.addLiquidity(token1, usdc, OneEther * 10, OneUsdc * 100, OneEther * 10, OneUsdc * 100, operator_wallet,
                              int(time.time()) + 120, tx_config)
lp_pair1 = input("input lp pair address:")
lp_pair1 = Contract.from_explorer(lp_pair1)
oracle1 = Oracle.deploy(lp_pair1, period, oracle_start_time, tx_config)
boardroom1.initialize(token1, bebu, treasury1, fee, tx_config)
boardroom1.setOperator(treasury1, tx_config)
oracle1.transferOperator(treasury1, tx_config)

#   treasury1.initialize(token1, bebu, oracle1, boardroom1, treasury1_start_time, tx_config)
treasury1.setExtraFunds(dao_fund, 1500, dev_fund, 500, tx_config)
#   token1.excludeAddress(boardroom1, tx_config)
#   token1.excludeAddress(dao_fund, tx_config)
#   token1.excludeAddress(dev_fund, tx_config)

token1.setPair(lp_pair1, tx_config)
token1.setRouter(quickswap_router, tx_config)
token1.setTokenOracle(oracle1, tx_config)
token1.setTreasury(treasury1, tx_config)
token1.transferOperator(treasury1, tx_config)

bebu.approve(boardroom1, uint256_max, tx_config)
boardroom1.stake(OneEther * 0.01, tx_config)
allocPoint = input("input allocPoint for BULLETH1X:")
bebuRewardPool.add(allocPoint, lp_pair1, False, 0, tx_config)

print("----------BULLETH1X address----------:")
print("token:", token1)
print("boardroom:", boardroom1)
print("treasury:", treasury1)
print("oracle:", oracle1)
print("lp_pair:", lp_pair1)
print("bebu:", bebu)
print("bebuRewardPool:", bebuRewardPool)
print("stableFarmingRewardPool:", stableFarmingRewardPool)
print("----------BULLETH1X address----------:\n\n\n")

#   ------------------------------------------------- BEARETH1X---------------------------------------------------------
token2 = BEARETH1X.deploy(tx_config)

boardroom2 = Boardroom.deploy(tx_config)
treasury2 = BEARETH1X_Treasury.deploy(tx_config)
token2.enableTransaction(tx_config)
token2.approve(quickswap_router, uint256_max, tx_config)
#    tx = quickswap_router.addLiquidity(token2, usdc, OneEther / 10, OneUsdc, OneEther / 10, OneUsdc, operator_wallet, int(time.time()) + 120, tx_config)
#    lp_pair2 = tx.new_contracts[0]
token2.mint(test_wallet, OneEther * 10, tx_config)
token2.mint(zhangjie_test_wallet, OneEther * 10, tx_config)
token2.mint(operator_wallet, OneEther * 10, tx_config)
quickswap_router.addLiquidity(token2, usdc, OneEther * 10, OneUsdc * 100, OneEther * 10, OneUsdc * 100, operator_wallet,
                              int(time.time()) + 120, tx_config)
lp_pair2 = input("input lp pair address:")
lp_pair2 = Contract.from_explorer(lp_pair2)
oracle2 = Oracle.deploy(lp_pair2, period, oracle_start_time, tx_config)
boardroom2.initialize(token2, bebu, treasury2, fee, tx_config)
boardroom2.setOperator(treasury2, tx_config)
oracle2.transferOperator(treasury2, tx_config)

treasury_operator = TreasuryOperator.deploy(tx_config)
treasury_operator.doubleInitialize(treasury1, treasury2, token1, token2, oracle1, oracle2, boardroom1, boar
droom2, bebu, treasury_start_time, tx_config)

#   treasury2.initialize(token2, bebu, oracle2, boardroom2, treasury_start_time, tx_config)
treasury2.setExtraFunds(dao_fund, 1500, dev_fund, 500, tx_config)
token2.setPair(lp_pair2, tx_config)
token2.setRouter(quickswap_router, tx_config)
token2.setTokenOracle(oracle2, tx_config)
token2.setTreasury(treasury2, tx_config)
token2.transferOperator(treasury2, tx_config)

bebu.approve(boardroom2, uint256_max, tx_config)
boardroom2.stake(OneEther * 0.01, tx_config)
allocPoint = input("input allocPoint for BEARETH1X:")
bebuRewardPool.add(allocPoint, lp_pair2, False, 0, tx_config)

print("----------BEARETH1X address----------:")
print("token:", token2)
print("boardroom:", boardroom2)
print("treasury:", treasury2)
print("oracle:", oracle2)
print("lp_pair:", lp_pair2)
print("bebu:", bebu)
print("bebuRewardPool:", bebuRewardPool)
print("stableFarmingRewardPool:", stableFarmingRewardPool)
print("----------BEARETH1X address----------:\n\n\n")

# ------------------------------------------------------- interaction------------------------------------------------

token1.enableAutoCalculateReward(tx_config)
token1.enableAutoCalculateTax(tx_config)
quickswap_router.swapExactTokensForTokens(OneUsdc * 2, 0, [usdc, token1], operator_wallet, int(time.time()) + 60,
                                          tx_config)
treasury1.allocateSeigniorage(tx_config)
quickswap_router.swapExactTokensForTokensSupportingFeeOnTransferTokens(OneEther * 1, 0, [token1, usdc],
                                                                       operator_wallet, int(time.time()) + 60,
                                                                       tx_config)
quickswap_router.swapExactTokensForTokens(OneUsdc * 2, 0, [usdc, token1], operator_wallet, int(time.time()) + 60,
                                          tx_config)

token2.enableAutoCalculateReward(tx_config)
token2.enableAutoCalculateTax(tx_config)
quickswap_router.swapExactTokensForTokens(OneUsdc * 2, 0, [usdc, token2], operator_wallet, int(time.time()) + 60,
                                          tx_config)
treasury2.allocateSeigniorage(tx_config)
quickswap_router.swapExactTokensForTokensSupportingFeeOnTransferTokens(OneEther * 1, 0, [token2, usdc],
                                                                       operator_wallet, int(time.time()) + 60,
                                                                       tx_config)
quickswap_router.swapExactTokensForTokens(OneUsdc * 2, 0, [usdc, token2], operator_wallet, int(time.time()) + 60,
                                          tx_config)



''''
reward取完
bebu分奖励一次性
treasury1同时部署
dao fund 控盘缴税
'''
