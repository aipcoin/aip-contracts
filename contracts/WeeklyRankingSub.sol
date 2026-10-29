/* ============================================================================
 *  WeeklyRankingSub.sol --- AIP ---------------Weekly Ranking------------------ BondingCurve.sol ---------------------
 * ----------------------------------------------------------------------------
 *  ---------------------------------------
 *    --------- BondingCurve.sol --------------------------- EIP-170 ------------------------24,576 ------------
 *    ---------------"------------------"---------change-id: split-peripheral-subcontracts---------------------
 *    ------------------------ FinalePoolSub ---------------------------------------------"------------------"---------
 *    ------------------------------ / ------------------------------------------------------------ 1,800 ------
 *    --------- processWeekBoundary --------- 1,226B ---------------------------------------------------
 *    ------------------------------------------------------------------
 *
 *  ------------------
 *    ------------------"------------ USDT ---------"------------ Top3 ------------
 *      1. ---------registerWeeklyRanking------------ weeklyRanking ------------------------------------------
 *         ------ Top3 --------------------- + ------------------ volume ------------
 *      2. ---------_processWeekBoundary--------------------------------------------------- / ------ / ---------------
 *         --------------------------------------- Top3 ------ --- --------------------------- --- --------------- 1/2
 *         ------------------ 0.3% --- Top3 --- ------------------ --- ------ Top3 --- ------------------
 *      3. ---------claimWeeklyRankingReward---------------------------------------------------------------
 *         ---------+------------------------------------------------------------
 *      4. ---------------onPoolPurchase---------------------------------------------------------------------------------
 *         ------------ USDT ---------------------------------------------------------------------------------------------------
 *      5. ------------------ migrate --------------------- 500,000 AIP---receivePoolFunding------------
 *         ------------ depositWeeklyPool ------------------------------ depositToPool(poolType=1) ------------
 *
 *  ------------------------------------------------------------------
 *    - ---------------AIPToken --- 20,000,000 AIP ------------------------owner --- setStakingPoolAllocation
 *      ------------------------ weeklyPool = 500,000 AIP--------- 10M + ------ 9M + ------ 0.5M + ------ 0.5M------
 *    - ---------owner ------------ migratePoolsToSubs------ 500,000 AIP ------------------------------------
 *      ------ safeTransfer --- receivePoolFunding ---------------------------------------2000 ------------------
 *      ------ 0.5M ------------------------------
 *    - --------------------------- AIP ---------------------------------------------------------------------
 *    - ---------------depositWeeklyPool ------------------ transferFrom ------------------
 *
 *  ---------------------------------
 *    ------------------------------------------------------------ IWeeklyRankingMainView(main) ------------------------
 *    ------------------------------ 2 --- getter------------------------------spec ------ ---4------
 *      - getTotalUsdtVolume()            --- --------------------- USDT ------------slot 7------------------
 *        ---------2,000 USDT------------ _updateWeeklyVolume ------------------
 *      - hasAppAccessById(user, appId)   --- ---------------------------------------------/------------------
 *        weeklyRanking ------------------------------------------------------------------
 *
 *  ------------------
 *    - ------ OpenZeppelin Ownable---v5------------------ Ownable(msg.sender)--------------- owner---
 *      ------------------------------------------------ EOA ------ --- owner ------------ FloorPlanSub ---------------
 *    - onPoolPurchase / receivePoolFunding ---------------------onlyMain ---------------
 *      msg.sender == main------------------------------------------
 *    - depositWeeklyPool --------------------------------------------- depositToPool ---------------------
 *
 *  ---------------------------------------------------------------------------------------
 *    1. USDT --- 2. BondingCurve --------- --- 3. AIPToken--------------- 20M AIP ---------------
 *    --- 4. WeeklyRankingSub--------------------- AIP ---------------------------
 *    --- 5. FinalePoolSub------------------------------
 *    --- 6. owner ------------ setStakingPoolAllocation()---------------------------
 *    --- 7. owner ------------ migratePoolsToSubs(---------, ------------)------------------ 0.5M + 0.5M---
 *    ------migrate ------------------------------------------------------------------------------------------------------
 *
 *  ------------------------------ hardhat_setStorageAt ---------------------------------
 *    slot 0: _owner------------ Ownable ------------------------------------ slot 1 ------------------
 *    slot 1: weeklyPool
 *    slot 2-7:  weeklyTop3[3]---WeeklyTopUser{address,uint256} --------- 2 --- -- 3 = 6 ------
 *    slot 8-16: pendingWeeklyRewards[3]---WeeklyWinnerReward{address,uint256,bool} ---------
 *              3 --- -- 3 = 9 ------
 *    slot 17: pendingWeeklyWinnerCount---slot 18: pendingWeekStart---slot 19: pendingClaimDeadline
 *    slot 20: weekNumber---slot 21: currentWeekStart---slot 22: WEEKLY_RANKING_START_TIME
 *    slot 23: weeklyVolume---mapping ------------slot 24: userWeekNumber---mapping ---------
 *    slot 25: paused---------------------------------------bool ------------------------------ 0-24 ---------------
 *    --------------------------- slot 46-69 ---------------------------------------aip/main --- immutable ------------
 *
 *  ---------------------------------
 *    - ------ BPS / PRECISION / WEEKLY_RANKING_APP_ID / WEEKLY_RANKING_REWARD_BPS / WEEK_SECONDS /
 *      WEEKLY_RANKING_RATIO / WEEKLY_RANKING_VOLUME_THRESHOLD ------------------------------------
 *      ------------------------------------------------------------------------------------------------------------------
 *    - ------------------------------custom error---------------------------------------------------------------------------------
 *      ---------------totalUsdtVolume ------------------------"------------"---------------------------------------------------
 *
 *  ------------------------ // --- /\* *\/ ------------ Solidity --------------------------------- bytecode --- Gas---
 * ============================================================================
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24; // Solidity ---------0.8.24 ------------------------------------------------------------------------

// ------ OpenZeppelin --- Ownable--------- owner ------------------------------------------
import "@openzeppelin/contracts/access/Ownable.sol";
// ------ ERC20 --------------------------- aip ------------
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// ------ SafeERC20 ------------------------ transfer/transferFrom------------------------------------
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * IWeeklyRankingMainView --- ------------BondingCurve---------------------------
 * ----------------------------------------------------------------------------
 * ------------------------------"WeeklyRanking"------------------------------------------------------------
 *   --------------- FinalePoolSub --------------------- import------------------------------------
 *   FloorPlanSub --------------------------- IBondingCurveView------------------------------------------------------
 * --------------------------------------------------------------------------------------------- 2 ------------------ view------
 *   1. getTotalUsdtVolume------------------------ USDT ------------------------ 7------------------------------------
 *      ------ 2,000 USDT ---------/------/------------
 *   2. hasAppAccessById--------------------------------------------------------------------- WEEKLY_RANKING_APP_ID---
 *      ------------------------------------------------------------------------------------------------
 * ------------------------------------------------------------------------------------------------------------------------------
 * ------------main --- immutable---------------------------------------------------------------------------------
 */
interface IWeeklyRankingMainView {
    // ------------ USDT --------------------- slot 7------------------------------------------------------------
    function getTotalUsdtVolume() external view returns (uint256);
    // ---------------------user --------------- appId ---------------true = ---------------------/---------
    function hasAppAccessById(address user, bytes32 appId) external view returns (bool);
}

// --------------------------------- Ownable---------/------------------------------------------------------------
contract WeeklyRankingSub is Ownable {
    // --- SafeERC20 ------------ IERC20 ------------ IERC20 --------------- .safeTransfer/.safeTransferFrom------------------------
    using SafeERC20 for IERC20;

    // ======================= ------------------------------------------------------------ =======================
    // ---------------100% = 10000 bps------------------------------------------------------ 0.3% = 30/10000---
    uint256 private constant BPS = 10_000;
    // ---------------1e18------------ 1.0 ---------------------------------------------
    uint256 private constant PRECISION = 1e18;

    // ======================= ---------Weekly Ranking--------------------------------------------------------------- =======================
    // ------ App ID---keccak256("weeklyRanking")------------/---------------------------------------------------
    bytes32 private constant WEEKLY_RANKING_APP_ID = keccak256("weeklyRanking");
    // ---------------------------------30 bps = 0.3%--------------- 0.3% --- Top3 ---------
    uint256 private constant WEEKLY_RANKING_REWARD_BPS = 30; // ------------------------ 0.3%
    // ---------------7 ---------------------------------
    uint256 private constant WEEK_SECONDS = 7 days;
    // ---------------------------1/2---1e18 --------------------------------------- 1/2
    uint256 private constant WEEKLY_RANKING_RATIO = 500_000_000_000_000_000; // 1/2 (0.5) in 1e18 precision
    // ------------------------------------------ 2,000 USDT ------------------------------------------------------
    uint256 public constant WEEKLY_RANKING_VOLUME_THRESHOLD = 2_000e18;

    // ======================= ------------------immutable--------------------------------------------------------------- =======================
    // AIP ------------------------------------------------------------------------
    IERC20 public immutable aip;
    // ------------BondingCurve------------------------------------------------------------------ IWeeklyRankingMainView------
    // --------- onlyMain ---------------------------------------------------------------------------
    IWeeklyRankingMainView public immutable main;

    // ======================= ------------------------------------ slot 1 ------------ =======================
    // --------------- 11 ------------ BondingCurve ------------------------------------------ 46-69--------- weeklyPool
    //       ------------------------------------ migrate ---------------------------------------------------------------------------
    //       --- Ownable._owner --- slot 0------------------ slot 1 ------------------------------------------------------
    // ------------------ AIP--------------------- migrate --------------- 500,000 AIP--------------- 0.3%
    uint256 private weeklyPool;
    // ------ Top3 ------------ volume ---------------------------------
    WeeklyTopUser[3] private weeklyTop3;
    // --------------- Top3 ------------------------------------ 1 ------------------------------------------------------
    WeeklyWinnerReward[3] private pendingWeeklyRewards;
    // ---------------------------0 ~ 3
    uint256 private pendingWeeklyWinnerCount;
    // ------------------------------------
    uint256 private pendingWeekStart;
    // ---------------------------= pendingWeekStart + 2 -- WEEK_SECONDS---------------------------------
    uint256 private pendingClaimDeadline;
    // --------------------- 0 ------------
    uint256 private weekNumber;
    // ------------------------
    uint256 private currentWeekStart;
    // ------------------------------------ _processWeekBoundary --------------------- UTC ------ 00:00 ---------------
    uint256 private WEEKLY_RANKING_START_TIME;
    // ------------------ USDT ---------------=------------------ weekNumber ------
    mapping(address => uint256) private weeklyVolume;
    // ------------------------ volume ------------------------------------ weeklyVolume
    mapping(address => uint256) private userWeekNumber;

    // ======================= ------------------------------------------ =======================
    // --------------------------------------------------------------------- slot 25--------------- 0-24 ------------------
    //   hardhat_setStorageAt ---------------------------------------------------
    //   true = ------------------------------------------------registerWeeklyRanking------------
    //   ---depositWeeklyPool------------------------claimWeeklyRankingReward---------------------
    //   ---------------------------------------------------------------
    //   ------------ setPaused ---------------onlyMain------------------------ pause ---------
    //   ------------------------------------------------------------------"------------------------------"------------------
    bool private paused; // ------ 25---bool ------------------------ setPaused ---------------

    // ======================= struct ------------------------------------ =======================
    /**
     * WeeklyTopUser --- ------ Top3 ------------
     * --------- weeklyTop3 --------------- volume ---------------
     * @param user ------------
     * @param volume ------------------ USDT ------------------------_refreshTop3Volumes ------------
     */
    struct WeeklyTopUser {
        address user;
        uint256 volume;
    }
    /**
     * WeeklyWinnerReward --- ---------------------------
     * --------- pendingWeeklyRewards --------------------------------------- 1 ------------------------------------------------------------------------
     * @param user ---------------
     * @param amount ------ AIP ------
     * @param claimed ------------------------------------
     */
    struct WeeklyWinnerReward {
        address user;
        uint256 amount;
        bool claimed;
    }

    // ======================= ------------------------------------------------------------ =======================
    // ------------------------------ depositWeeklyPool------------------------------------------------------
    // setStakingPoolAllocation------------------------ depositToPool ---------------------------------
    event WeeklyRankingPoolUpdated(uint256 newPoolAmount, address contributor, uint256 contribution);
    // --------------------------------------- _processWeekBoundary ---------------totalReward=------------weekStart=---------
    event WeeklyRankingWinnersSet(uint256 totalReward, uint256 weekStart);
    // ------------------------------ claimWeeklyRankingReward
    event WeeklyRankingRewardClaimed(address winner, uint256 amount, uint256 weekStart);
    // ------------------------ registerWeeklyRanking---volume=------------------weekNumber=---------
    event WeeklyRankingRegistered(address indexed user, uint256 volume, uint256 weekNumber);
    // ======================= --------------------------------------------------------- =======================
    // ------------------------------------ setPaused------------ pause/unpause ------------------
    //   paused=------------------by=------------------------------------onlyMain ---------
    event SubPausedChanged(bool paused, address indexed by);
    // ------------------------------ migrateOut---owner ------------ forwardSubCall ---------------
    //   to=---------------------------------------------amount=--------------------- AIP ------
    event MigratedOut(address indexed to, uint256 amount);

    // ======================= ------ error---------------------------------revert --------------- =======================
    // ---------------------claimWeeklyRankingReward --------- pendingWeeklyRewards ------
    error NotWeeklyRankingWinner();
    // ------------------------------ WEEKLY_RANKING_APP_ID --------------------------------------- false---
    error RankingAccessDenied();
    // ------------------------pendingWeeklyRewards[i].claimed == true
    error RankingRewardAlreadyClaimed();
    // ---------------------block.timestamp >= pendingClaimDeadline--------------------------------------- 1 ---------------------------------------------
    error RankingRewardExpired();
    // ------------------------pendingWeeklyWinnerCount == 0------------------------------ error------------------
    error NoPendingRankingReward();
    // ---------------------registerWeeklyRanking --- weeklyVolume --- 0
    error RankingMetricZero();
    // ------------------------------------------ < WEEKLY_RANKING_VOLUME_THRESHOLD
    error WeeklyRankingNotActivated();
    // --------- 0---depositWeeklyPool --------- < 1 AIP ------------------------ depositToPool ------------
    error ZeroAmount();
    // ---------------------------AIP/------------------------ address(0) ------------------------------
    error ZeroAddress();
    // ---------------------onPoolPurchase / receivePoolFunding ---------------------------------------------
    error OnlyMain();
    // ======================= ------------------ error =======================
    // ------------------------------------------------/------------------------------------------------------------------
    error ContractPaused();

    /**
     * --------- onlyMain --- ---------------------
     * ----------------------------------------------------------------------------
     * ------------onPoolPurchase--------------------- receivePoolFunding---migrate ------------------
     *   ------------------------------------------------------------------------------ 0.5M ---------------------------------
     *   ------------------------------------"------"---------------------------------------------------------------
     * ------------msg.sender --------------------------------- main --------------- revert OnlyMain---
     */
    modifier onlyMain() {
        if (msg.sender != address(main)) revert OnlyMain(); // ------------
        _;
    }

    /**
     * --------------------- AIP / ------------------------ owner
     * ----------------------------------------------------------------------------
     * ---------------------------------------------------------------------------------------owner = ---------
     * ------------Ownable(msg.sender)--------------- owner------------------------------------ EOA ---------
     *         ------------ owner ------------ owner --------------------- FloorPlanSub ------------
     * ------------_aip=AIP ---------------_main=BondingCurve ---------------
     * --------------------------- address(0) --- revert ZeroAddress------------------------------------------
     */
    constructor(address _aip, address _main) Ownable(msg.sender) {
        if (_aip == address(0)) revert ZeroAddress(); // AIP --------- 0
        if (_main == address(0)) revert ZeroAddress(); // ------------------ 0
        aip = IERC20(_aip); // ------ AIP ---------immutable---
        main = IWeeklyRankingMainView(_main); // ------------------------------------immutable---
    }

    // ======================= ------------------------onlyMain--- =======================

    /**
     * onPoolPurchase --- --------------------------------- + ---------------------------------------
     * ----------------------------------------------------------------------------
     * --------------------- buyFromPool ------------------------------------------------ USDT/--- AIP/------
     *   totalUsdtVolume ---------------------------------------------------------------------------------
     *     -- _processWeekBoundary()---------------------------------------------------------
     *     -- _updateWeeklyVolume(user, usdtCost)---------------------------------------------------------
     *   --------------------------------------------------------------------------- volume ---------------------------
     * ---------------------------onlyMain------------------------------------------------------------------------
     * ------------user=------------------------ msg.sender------usdtAmount=--------------- USDT ------
     *   --------------- _updateWeeklyVolume --- usdtCost ---------------------
     * ------------------
     *   1. _processWeekBoundary------------------------------------------------------ Top3------------------------
     *   2. _updateWeeklyVolume------ weekNumber --------------- weeklyVolume[user] += usdtAmount---
     * ------------------------------------------------------------------------ < 2,000 USDT ---------------------
     *   ------------------------------------------------------------------ migrate ---------------------------
     */
    function onPoolPurchase(address user, uint256 usdtAmount) external onlyMain {
        _processWeekBoundary(); // ---------------------------------------------------------------------------------------------
        _updateWeeklyVolume(user, usdtAmount); // ---------------------------------------------------------------------
    }

    /**
     * receivePoolFunding --- ------------------------------migrate ---------
     * ----------------------------------------------------------------------------
     * --------------------- migratePoolsToSubs ------ AIP safeTransfer ------------------------------------
     *   ------------------------------------------weeklyPool += amount------------------------------------------------
     *   ---------------------"------------------"---"------------------"---
     * ---------------------------onlyMain------0.5M ------------------------------------------
     * ------------amount=--------------- AIP ---------migrate ------ weeklyPool --------------- 500,000 AIP---
     * ------------------AIP ------------------------------------------------------------------------------
     */
    function receivePoolFunding(uint256 amount) external onlyMain {
        weeklyPool += amount; // ---------------------------AIP ---------------------------
    }

    // ======================= --------------------------------------------------- =======================

    /**
     * setPaused --- ---------------------------------------------------
     * ----------------------------------------------------------------------------
     * --------------------- pause()/unpause() ------------------------------------------------------------
     *   ------------------------ + ------ + ------ + ---------------------------------------------------------------
     * ---------------------------onlyMain--------------------- onlyOwner--------------------------- owner ---
     *   ------------------------ owner ------------------------------------------------------------ main
     *   ---immutable ------------------------------------------ owner ------------------------------ EOA---
     *   ------------------------------------------------------------------------
     * ------------------------------------ pause ---------------------------------------------------
     * ------------_paused=true ---------------/---------------/ false ------------------------
     * ------------SubPausedChanged(_paused, msg.sender)
     */
    function setPaused(bool _paused) external onlyMain {
        paused = _paused; // ------------------------
        emit SubPausedChanged(_paused, msg.sender); // ---------------by=------------------
    }

    /**
     * migrateOut --- --------------------------------------- AIP ------------------------------------------------
     * ----------------------------------------------------------------------------
     * ------------------------------------------ bug --------------------------------------------------------- AIP
     *   --------------------------------------------------------------------------- owner ---------------------
     * --------------- owner---onlyOwner------------------------------ owner=------------------------------------
     *   --- owner ------------ forwardSubCall --------------------------------- EOA ---------------
     * ------------------AIP--------------------------- --- to---------------------------------------------------------------
     * ------------------weeklyPool --- 0--------------------------- view ---------------------------------
     *   ---------------------------------------------------------------pendingWeeklyRewards---------------
     *   ---------------------------------------------------------------------------------
     * ------------to == address(0) --- ZeroAddress---------------------
     * ------------MigratedOut(to, ------------)
     */
    function migrateOut(address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress(); // ------------ 0---------------------
        uint256 bal = aip.balanceOf(address(this)); // ------------------------------------------------------------------------
        weeklyPool = 0; // ------------------------------------------------------------
        aip.safeTransfer(to, bal); // ---------------bal=0 --- safeTransfer ---------------------------------------------
        emit MigratedOut(to, bal); // ------------------------------
    }

    // ======================= ------------------------------ depositToPool(poolType=1)--- =======================

    /**
     * depositWeeklyPool --- ------------------------------------
     * ----------------------------------------------------------------------------
     * ------------------------ depositToPool(poolType=1) ---------------------------------------------------------------
     *   --------------------------------------------------------------- poolType=1 --- migrate --- revert
     *   PoolMigratedToSub ------------------------------
     * ------------------------------------ external------------------------------------------------ approve ---------
     * ------------amount=------------------ wei ------------------ 1e18 = 1 AIP--------- revert ZeroAmount---
     * ------------amount < 1e18 --- ZeroAmount------------------------------------------------------
     * ------------------AIP------------------ --- ------------------------------------------ approve ---------
     * ---------------weeklyPool += amount--------------------- 0.3% ---------------
     * ------------WeeklyRankingPoolUpdated(newPoolAmount=---------------, contributor=---------, contribution=amount)
     */
    function depositWeeklyPool(uint256 amount) external {
        if (paused) revert ContractPaused(); // ------------------------------------------------------------------------------------------
        // --------------------- 1 AIP------------------------------------------------ depositToPool ------------------------
        if (amount < 1e18) revert ZeroAmount();
        // ------------------ AIP ------------------------------------------------ aip.approve(---------, amount)
        // ------ safeTransferFrom ------ transferFrom------------------------ revert---------------------------
        aip.safeTransferFrom(msg.sender, address(this), amount);
        weeklyPool += amount; // ------------------------
        // ------------------------------newPoolAmount=------------------contributor=------------contribution=---------------
        emit WeeklyRankingPoolUpdated(weeklyPool, msg.sender, amount);
    }

    // ======================= ------------------------------------------ =======================

    /**
     * registerWeeklyRanking --- --------------------------------------------------------- Top3---
     * ----------------------------------------------------------------------------
     * --------------------------------------------- weeklyTop3 ---------_updateWeeklyTop3 ---------------
     * ---------------------------------------------------------------------------------------------------------------
     *   - main.getTotalUsdtVolume() >= WEEKLY_RANKING_VOLUME_THRESHOLD---WeeklyRankingNotActivated---
     *   - main.hasAppAccessById(msg.sender, WEEKLY_RANKING_APP_ID)---RankingAccessDenied---
     *   - weeklyVolume[msg.sender] != 0---RankingMetricZero---
     * ------------_processWeekBoundary--------------------- _updateWeeklyTop3---------/------------ ------------
     * ------------WeeklyRankingRegistered(msg.sender, userVolume, weekNumber)
     */
    function registerWeeklyRanking() external {
        if (paused) revert ContractPaused(); // ------------------------------------------------------------------------------------------------------
        if (IWeeklyRankingMainView(main).getTotalUsdtVolume() < WEEKLY_RANKING_VOLUME_THRESHOLD) revert WeeklyRankingNotActivated(); // --------------------- 2,000 USDT------------------
        if (!IWeeklyRankingMainView(main).hasAppAccessById(msg.sender, WEEKLY_RANKING_APP_ID)) revert RankingAccessDenied(); // ---------------------
        uint256 userVolume = weeklyVolume[msg.sender]; // ---------------------
        if (userVolume == 0) revert RankingMetricZero(); // ------------------ 0
        _processWeekBoundary(); // --------------------------- pending ---------
        _updateWeeklyTop3(msg.sender, userVolume); // --------------- Top3
        emit WeeklyRankingRegistered(msg.sender, userVolume, weekNumber);
    }

    /**
     * claimWeeklyRankingReward --- ---------------------------------------------------
     * ----------------------------------------------------------------------------
     * --------------------------------------- _processWeekBoundary --------------------------------- pending ------
     * ---------------------------------------------------------------------+---------------------
     * ---------------------------------------------------------
     *   - pendingWeeklyWinnerCount != 0---NoPendingRankingReward---
     *   - main.hasAppAccessById(msg.sender, WEEKLY_RANKING_APP_ID)---RankingAccessDenied---
     *   - block.timestamp < pendingClaimDeadline---RankingRewardExpired--------------------------------------- 1 ------
     *   - --------- pendingWeeklyRewards --------- msg.sender---NotWeeklyRankingWinner---
     *   - ---------------RankingRewardAlreadyClaimed---
     * ------------------ pendingWeeklyRewards --------------- --- ------ claimed --- --- AIP --- ------------
     * ------------------AIP--------------- --- ------------------------------------------------------------------------
     * ------------WeeklyRankingRewardClaimed(msg.sender, amount, pendingWeekStart)
     */
    function claimWeeklyRankingReward() external {
        // ---------------------------------------------------------------------------------------------
        // --------------------------------- pendingWeeklyRewards + ------ pendingClaimDeadline------
        // ------------------------------------------------------------------+------
        _processWeekBoundary(); // ------------------------------ pending ---------
        if (pendingWeeklyWinnerCount == 0) revert NoPendingRankingReward(); // ---------------
        if (!IWeeklyRankingMainView(main).hasAppAccessById(msg.sender, WEEKLY_RANKING_APP_ID)) revert RankingAccessDenied(); // ---------------------
        if (block.timestamp >= pendingClaimDeadline) revert RankingRewardExpired(); // ------------------------------------------------ 1 ------

        bool found = false;
        for (uint256 i = 0; i < pendingWeeklyWinnerCount; i++) { // ------------------
            if (pendingWeeklyRewards[i].user == msg.sender) { // ---------------
                if (pendingWeeklyRewards[i].claimed) revert RankingRewardAlreadyClaimed(); // ---------
                pendingWeeklyRewards[i].claimed = true; // ------------
                uint256 amount = pendingWeeklyRewards[i].amount;
                aip.safeTransfer(msg.sender, amount); // --- AIP ------------------------------------------------------------
                emit WeeklyRankingRewardClaimed(msg.sender, amount, pendingWeekStart);
                found = true;
                break;
            }
        }
        if (!found) revert NotWeeklyRankingWinner(); // ---------------------------
    }

    // ======================= ------------------------------------------ =======================

    /**
     * getWeeklyRankingFullInfo --- ---------------------------8 ---------------
     * ----------------------------------------------------------------------------
     * ------------------------------------------------------------------------------------------------------------Top3 ------------------
     * ------------
     *   - _weeklyPool---weeklyPool--------------- AIP ---------
     *   - _weekNumber---weekNumber---------------------
     *   - _currentWeekStart---currentWeekStart---------------------------
     *   - _pendingWinnerCount---pendingWeeklyWinnerCount------------------------------
     *   - _pendingClaimDeadline---pendingClaimDeadline---------------------------
     *   - _totalPendingReward------------------------------ pendingWeeklyRewards ------------------------
     *   - _top3Users---weeklyTop3 ---------------------3 ------
     *   - _top3Volumes---weeklyTop3 ------------------3 ------------------
     */
    function getWeeklyRankingFullInfo() external view returns (
        uint256 _weeklyPool,
        uint256 _weekNumber,
        uint256 _currentWeekStart,
        uint256 _pendingWinnerCount,
        uint256 _pendingClaimDeadline,
        uint256 _totalPendingReward,
        address[3] memory _top3Users,
        uint256[3] memory _top3Volumes
    ) {
        uint256 totalPending = 0;
        for (uint256 i = 0; i < pendingWeeklyWinnerCount; i++) { // ------------------
            if (!pendingWeeklyRewards[i].claimed) {
                totalPending += pendingWeeklyRewards[i].amount;
            }
        }
        for (uint256 i = 0; i < 3; i++) { // ------ Top3
            _top3Users[i] = weeklyTop3[i].user;
            _top3Volumes[i] = weeklyTop3[i].volume;
        }
        return (
            weeklyPool,
            weekNumber,
            currentWeekStart,
            pendingWeeklyWinnerCount,
            pendingClaimDeadline,
            totalPending,
            _top3Users,
            _top3Volumes
        );
    }

    /**
     * getWeeklyTop3Fresh --- ------ Top3 ------------------------------ getWeeklyRankingFullInfo ---------------
     * ----------------------------------------------------------------------------
     * ------------------ weeklyTop3 --------------------------------- weeklyVolume--------- top3[].volume ---------
     * ------------_users=Top3 ---------------------_volumes=---------------------------
     * ------------------------------------------------------
     */
    function getWeeklyTop3Fresh() external view returns (address[3] memory _users, uint256[3] memory _volumes) {
        for (uint256 i = 0; i < 3; i++) { // ------ Top3
            _users[i] = weeklyTop3[i].user;
            _volumes[i] = weeklyVolume[weeklyTop3[i].user]; // ------------------------------------------
        }
    }

    /**
     * getWeeklyWinner --- ------------------------------------------
     * ----------------------------------------------------------------------------
     * --------------- index ------ pendingWeeklyRewards[index] ------------------
     * ------------index=---------------0-based---
     * ------------_user=------------------_amount=---------------_claimed=---------------
     */
    function getWeeklyWinner(uint256 index) external view returns (
        address _user,
        uint256 _amount,
        bool _claimed
    ) {
        return (pendingWeeklyRewards[index].user, pendingWeeklyRewards[index].amount, pendingWeeklyRewards[index].claimed);
    }

    /**
     * getWeeklyVolume --- ---------------------------------------
     * ----------------------------------------------------------------------------
     * ------------------------------------ weeklyVolume--------------- 0---
     * ------------user=------------
     * ------------uint256------------------------USDT --------------------- 0
     */
    function getWeeklyVolume(address user) external view returns (uint256) {
        if (userWeekNumber[user] != weekNumber) return 0; // ------------ 0
        return weeklyVolume[user];
    }

    // ======================= --------------------------------------------------------------- =======================

    /**
     * _processWeekBoundary --- ------------------------------------
     * ----------------------------------------------------------------------------
     * --------------------------- Top3--------------------------------------------------------------- Top3------------------
     * ------------
     *   1. ------------------------ WEEKLY_RANKING_START_TIME --------- UTC ------ 00:00 ---------------
     *   2. ------------------------
     *   3. --------------- Top3 volume --- --------------------------- --- ------------------ ---
     *      --------------- 1/2 ------ 0.3% ------ --- ------ Top3 --- --------------- --- ---------------
     * ------------------weights[0]=1, weights[i]=weights[i-1]--1/2--------------- 3 ---------
     * --------------------- 1 ------------------------------------------------------------------------------------------------
     *       pendingClaimDeadline = currentWeekStart + 2 -- WEEK_SECONDS ------------------------------------------------ 2 ---
     * ------------------------------------------ < WEEKLY_RANKING_VOLUME_THRESHOLD --------- return------------------------------
     * ---------------------------totalUsdtVolume ------------------------------------------------------------------------
     */
    function _processWeekBoundary() internal {
        if (IWeeklyRankingMainView(main).getTotalUsdtVolume() < WEEKLY_RANKING_VOLUME_THRESHOLD) return; // --------------------- 2,000 USDT------------------
        if (WEEKLY_RANKING_START_TIME == 0) { // ---------------------
            // --------------- UTC ------ 00:00---Unix ---------1970-01-01---------------(ts / 7---) -- 7--- ---------------
            // --------------------------------------------------- 4 ---------------------------------------------------------------------
            // ------------------ 00:00 UTC --- ---------------------------------------------/---------------------------2026 ---
            // ------------ 4 ------------------------------------------------------------------------------------------------------------
            WEEKLY_RANKING_START_TIME = ((block.timestamp - 4 days) / WEEK_SECONDS) * WEEK_SECONDS + 4 days; // --------- UTC ------ 00:00 ------
            weekNumber = 0;
            currentWeekStart = WEEKLY_RANKING_START_TIME;
            return;
        }

        if (block.timestamp < currentWeekStart + WEEK_SECONDS) return; // ------------------------

        // ------ Top3 --------- real-time ------------ C------ registerWeeklyRanking ---------------
        _refreshTop3Volumes();

        // Roll back unclaimed rewards --- ---------------------------------------
        for (uint256 i = 0; i < pendingWeeklyWinnerCount; i++) {
            if (!pendingWeeklyRewards[i].claimed && pendingWeeklyRewards[i].amount > 0) {
                weeklyPool += pendingWeeklyRewards[i].amount; // ---------------
            }
            pendingWeeklyRewards[i] = WeeklyWinnerReward(address(0), 0, false); // ------------
        }
        pendingWeeklyWinnerCount = 0;

        // Count winners from completed week --- ------------ Top3 ------------
        uint256 count = 0;
        for (uint256 i = 0; i < 3; i++) {
            if (weeklyTop3[i].user != address(0)) {
                count++;
            } else {
                break; // ------------------
            }
        }

        // Distribute rewards if there were winners --- ---------------------
        if (count > 0) {
            uint256 totalReward = weeklyPool * WEEKLY_RANKING_REWARD_BPS / BPS; // 0.3% ------
            if (totalReward > 0) {
                weeklyPool -= totalReward; // ---------------

                // Calculate geometric weights (ratio = 1/2) --- always use full 3 slots --- --------------------- 3 ---
                uint256[3] memory weights;
                weights[0] = PRECISION; // --- 1 --------- = 1.0
                uint256 totalWeight = weights[0];
                for (uint256 i = 1; i < 3; i++) { // ------------ 2 ---------
                    weights[i] = weights[i - 1] * WEEKLY_RANKING_RATIO / PRECISION; // ------------ -- 1/2
                    totalWeight += weights[i];
                }

                // Distribute --- ------------------ Top3
                uint256 distributed = 0;
                for (uint256 i = 0; i < count; i++) {
                    uint256 amount = totalReward * weights[i] / totalWeight; // ---------------
                    pendingWeeklyRewards[i] = WeeklyWinnerReward(weeklyTop3[i].user, amount, false); // ------------
                    distributed += amount;
                }
                // Undistributed remainder rolls back to pool --- ------------------------------------
                weeklyPool += totalReward - distributed;

                pendingWeeklyWinnerCount = count;
                pendingWeekStart = currentWeekStart; // ---------------
                pendingClaimDeadline = currentWeekStart + 2 * WEEK_SECONDS; // ------------------------------------ 1 ---------------------------------------------

                emit WeeklyRankingWinnersSet(totalReward, currentWeekStart);
            }
        }

        // Reset top3 for new week --- ------ Top3 ------
        for (uint256 i = 0; i < 3; i++) {
            weeklyTop3[i] = WeeklyTopUser(address(0), 0);
        }

        weekNumber++; // --------- +1
        currentWeekStart = WEEKLY_RANKING_START_TIME + weekNumber * WEEK_SECONDS; // ---------------

        // If still behind current week, skip to current (no rewards for skipped weeks) --- ------------------
        if (block.timestamp >= currentWeekStart + WEEK_SECONDS) {
            weekNumber = (block.timestamp - WEEKLY_RANKING_START_TIME) / WEEK_SECONDS;
            currentWeekStart = WEEKLY_RANKING_START_TIME + weekNumber * WEEK_SECONDS;
        }
    }

    /**
     * _updateWeeklyTop3 --- ------------ Top3---------------------------
     * ----------------------------------------------------------------------------
     * --------------------------------------------- Top3 --------- volume ------------------------------------ 3 ---------------------
     * ------------user=---------------userVolume=---------------------
     * --------------- volume ------------------------------ 3 ------------
     */
    function _updateWeeklyTop3(address user, uint256 userVolume) internal {
        // Find if user is already in top3 --- ------------------------ Top3
        uint256 userIndex = 3;
        for (uint256 i = 0; i < 3; i++) {
            if (weeklyTop3[i].user == user) {
                userIndex = i;
                break;
            }
        }

        if (userIndex < 3) { // ------ Top3--------- volume ---------------
            // User already in top3, update volume and bubble up
            weeklyTop3[userIndex].volume = userVolume;
            while (userIndex > 0 && weeklyVolume[weeklyTop3[userIndex - 1].user] < userVolume) { // ------------------------
                WeeklyTopUser memory temp = weeklyTop3[userIndex];
                weeklyTop3[userIndex] = weeklyTop3[userIndex - 1];
                weeklyTop3[userIndex - 1] = temp;
                userIndex--;
            }
        } else { // ------ Top3------------------------ 3 ---
            // User not in top3, check if qualifies
            if (userVolume > weeklyVolume[weeklyTop3[2].user]) { // --------- 3 ---------------------
                weeklyTop3[2] = WeeklyTopUser(user, userVolume);
                uint256 idx = 2;
                while (idx > 0 && weeklyVolume[weeklyTop3[idx - 1].user] < userVolume) {
                    WeeklyTopUser memory temp = weeklyTop3[idx];
                    weeklyTop3[idx] = weeklyTop3[idx - 1];
                    weeklyTop3[idx - 1] = temp;
                    idx--;
                }
            }
        }
    }

    /**
     * _refreshTop3Volumes --- ------ Top3 ------ volume ---------------------
     * ----------------------------------------------------------------------------
     * --------------------------------- Top3 ------------------ volume ------------------------------------------------
     * ------------_processWeekBoundary ------
     */
    function _refreshTop3Volumes() internal {
        // Refresh volumes for all existing top3 users --- ------ Top3 --- volume ------------
        for (uint256 i = 0; i < 3; i++) {
            address u = weeklyTop3[i].user;
            if (u == address(0)) continue; // ------------
            uint256 latestVolume = weeklyVolume[u];
            if (weeklyTop3[i].volume != latestVolume) { // ------------------
                weeklyTop3[i].volume = latestVolume;
            }
        }
        // Full bubble sort (descending by volume) --- ------------------------------
        for (uint256 i = 1; i < 3; i++) {
            if (weeklyTop3[i].user == address(0)) break; // ---------------
            uint256 j = i;
            while (j > 0 && weeklyTop3[j - 1].volume < weeklyTop3[j].volume) { // ---------------------
                WeeklyTopUser memory temp = weeklyTop3[j];
                weeklyTop3[j] = weeklyTop3[j - 1];
                weeklyTop3[j - 1] = temp;
                j--;
            }
        }
    }

    /**
     * _updateWeeklyVolume --- ---------------------------
     * ----------------------------------------------------------------------------
     * --------------- weekNumber ------ weeklyVolume------------------------------
     * ------------user=---------------usdtCost=------------ USDT ------
     * ------------------------------------------ < WEEKLY_RANKING_VOLUME_THRESHOLD --------- return---------------------------
     * ---------------------------totalUsdtVolume ------------------------------------------------------------------------
     */
    function _updateWeeklyVolume(address user, uint256 usdtCost) internal {
        if (IWeeklyRankingMainView(main).getTotalUsdtVolume() < WEEKLY_RANKING_VOLUME_THRESHOLD) return; // --------------------- 2,000 USDT------------------
        if (userWeekNumber[user] != weekNumber) { // ---------------
            userWeekNumber[user] = weekNumber;
            weeklyVolume[user] = 0;
        }
        weeklyVolume[user] += usdtCost; // ---------------------
    }
}
