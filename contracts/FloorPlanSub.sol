/* ============================================================================
 *  FloorPlanSub.sol --- AIP ---------------Floor Plan------------------ BondingCurve.sol ---------------------
 * ----------------------------------------------------------------------------
 *  ---------------------------------------
 *    --------- BondingCurve.sol --------------------- 27,655 --------------- EIP-170 ------------------------------
 *    ---24,576 ---------3,079 ------------------------------------------------------------"------------------"------
 *    ---change-id: split-peripheral-subcontracts---------------------------------------------------------------
 *    ---------------------------------------------------------------------------------------------------------------------------
 *    ------------------------------------------------------------------------------------------
 *
 *  ------------------
 *    ---------------Floor Plan--------------------------------- 1000 ---------------------------------------------
 *      1. ---------lockFloorPlan------------------------------------------ 10000 AIP ---------------------
 *      2. ---------claimFloorPlan---------------------INITIAL_SALE_END_TIME = 1830556800---
 *         --- 2028-01-04 00:00:00 UTC------------------------------FLOOR_PLAN_CLAIM_DEADLINE =
 *         1862179200------ 2029-01-04 00:00:00 UTC---------------------------------------------------
 *         200 USDT ------------------------ 10000 AIP ------ owner------------------------
 *         ------------------200 USDT ------------------10000 AIP ------------------------------------
 *      3. ---------unlockFloorPlan------------------------------------ AIP---------------------------------forfeit------
 *      4. ---------manageFloorPlanUsdt------owner ---------------------/------ USDT------------ 200 USDT---
 *         1000 ------------ --- ------------ 200,000 USDT------------------------------------
 *      5. ---------------------------------------------staking/weeklyRanking/referral ---------------------
 *         ------------/---------------"---------------------------------------------"---
 *
 * ---------------------------------------------------------------------------------------------------
 *    - ------ AIP--------- lockFloorPlan ------------------------------------------------------------------------
 *    - USDT ------------owner --------------- USDT ------------------------------------------------------------
 *      manageFloorPlanUsdt(isDeposit=true) ------------------------------------------------
 *      --------------- manageFloorPlanUsdt(isDeposit=false) ------------------------owner ---
 *      withdrawTokens ------------
 *    - ---------------10000 AIP ------------------ owner---200 USDT ------------------------------
 *    - ---------------------------"------------"------ --- ------------------------------------------ AIP---
 *      --------- withdrawTokens --- available --------------------- floorPlanLockedAipTotal ---------
 *
 *  ---------------------------------------------
 *    "--------------------------- / ------------ / ------ AIP ------"------------------------------------------------------
 *    ------------------ IBondingCurveView(main) ------------------------------------------------------ 2 --- getter---
 *    ---------------------------spec ------ ---4------
 *      - initialShareProfile(user) --- (------------------------, ---------------, ------ AIP ------)
 *      - hasUnlockedAnyApp(user)   --- ------------------------------------------------------------------------ appList---
 *
 *  ------------------
 *    - ------ OpenZeppelin Ownable---v5------------------ Ownable(msg.sender)--------------- owner---
 *    - --------------- 5.6 ------------------ owner ---------------------transferOwnership(bondingCurve)------
 *      ---------/------------------"--- owner ------------"--------- manageFloorPlanUsdt ------------
 *      forwardSubCall ---------------claimFloorPlan --- 10000 AIP --------------- owner()=---------
 *      ---------AIP ------------------------------------------------"--------------- owner"--------------------------- owner ------------
 *    - manageFloorPlanUsdt --- owner --------------- msg.sender != owner() ---------------------------------------
 *    - ---------------------setPaused ---------------------onlyMain---------------------------------------------
 *      migrateOut --- owner ------------------------------------------------------------------------
 *
 *  ---------------------------------------------------------------------------------------
 *    1. USDT--------- ERC20------ 2. BondingCurve --------- --- 3. AIPToken--------------- 20M AIP ---------------
 *    --- 4. FloorPlanSub--------------------- AIP ---------USDT ---------------------------
 *    ---------------------------/--------------------------------------------------------- AIP ---------owner USDT ------------
 *
 *  ------------------------------ hardhat_setStorageAt ---------------------------------
 *    slot 0: _owner------------ Ownable ------------------------------------ slot 1 ------------------
 *    slot 1: floorPlanClaimed---slot 2: floorPlanClaimedCount---slot 3: floorPlanUsdtPool---
 *    slot 4: floorPlanLocked---slot 5: floorPlanForfeited---slot 6: floorPlanLockedAipTotal
 *    slot 7: paused---------------------------------------bool ------------------------------ 0-6 ---------------
 *    --------------------------- slot 76-81 --------------------- immutable ---------------------------------------------
 *
 *  ---------------------------------
 *    - ------ FLOOR_PLAN_MAX_CLAIMS / SHARE_PRICE / TOKENS_PER_SHARE / INITIAL_SALE_END_TIME
 *      ---------------------------------------------------SHARE_PRICE/TOKENS_PER_SHARE/INITIAL_SALE_* ------------------------------
 *    - INITIAL_SALE_START_TIME ---------------------"--------------- + 3 ------------------------ UTC 0 ---"---------
 *      ---------------------------------------------------------------------------------------------------------------
 *      INITIAL_SALE_END_TIME ------------------------------------------------------------------
 *    - ------------------------------custom error---------------------------------------------------------------------------------
 *
 *  ------------------------ // --- /\* *\/ ------------ Solidity --------------------------------- bytecode --- Gas---
 * ============================================================================
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24; // Solidity ---------0.8.24 ------------------------------------------------------------------------

// ------ OpenZeppelin --- Ownable--------- owner --------------- onlyOwner ------------------------------------
import "@openzeppelin/contracts/access/Ownable.sol";
// ------ ERC20 --------------------------- aip --- usdt ------------------
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// ------ SafeERC20 ------------------------ transfer/transferFrom--------- USDT ------------------------------
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * IBondingCurveView --- ------------BondingCurve---------------------------
 * ----------------------------------------------------------------------------
 * --------------------------------------------------------------------------------------------- 3 ------------------ view------
 *   1. initialShareProfile--------------------------------------------------- / ------------ / ------ AIP ------------
 *      --------------------- 39---hasBoughtInitialShare---/ 74---initialShareBuyTime---/ 75---initialShareAipAmount------
 *   2. hasUnlockedAnyApp------------------ appList ---------------------------------------------------------------------
 *   3. owner---------------------------Ownable ---------------------------------------------------------
 *      ------------"------------"------------ owner = ------------------------------ forwardSubCall ---------------
 *      msg.sender ------------------------ USDT ------ msg.sender ------------------------------------------------
 *      USDT ------------------------------------------------ owner()------------------------------------ EOA---------
 *      ---------------------------------------------------------
 * ------------------------------------------------------------------------------------------------------------------------------
 * ------------main --- immutable---------------------------------------------------------------------------------
 */
interface IBondingCurveView {
    // ---------------------------_bought=---------------------------_buyTime=------------------_aipAmount=------ AIP ------
    function initialShareProfile(address user) external view returns (bool _bought, uint256 _buyTime, uint256 _aipAmount);
    // ---------------------------------------------------------------------true = ---------------------/------------
    function hasUnlockedAnyApp(address user) external view returns (bool);
    // --------------------------------------------------------------------------------- 3---
    function owner() external view returns (address);
}

// ------------------------------ Ownable---owner --------------------------- lock/unlock/claim ------------
contract FloorPlanSub is Ownable {
    // --- SafeERC20 ------------ IERC20 ------------ IERC20 --------------- .safeTransfer/.safeTransferFrom------------------------
    using SafeERC20 for IERC20;

    // ======================= Floor Plan------------------------------------------------------------------ =======================
    // ---------------------------------1000------------ 1000 --------------------------------------------- 1000 ---------------------
    uint256 private constant FLOOR_PLAN_MAX_CLAIMS = 1000;
    // ------------------------------200 USDT------ 18 ------------------------------------------------------ SHARE_PRICE ---------
    uint256 private constant SHARE_PRICE = 200e18;
    // ------------------ AIP ---------10000 --------- 18 --------------------------------------------- TOKENS_PER_SHARE ---------
    uint256 private constant TOKENS_PER_SHARE = 10000e18;
    // ---------------------------2028-01-04 00:00:00 UTC------------------------ 19 --------1---3------------------------
    // ------------------------------ 2028-01-03 --------------- 2026-10-13 --------- 2027-01-04 ------------------
    // --------------------------------------------------------- lock/unlock--------------- claim
    uint256 public constant INITIAL_SALE_END_TIME = 1830556800;
    // ---------------------------2029-01-04 00:00:00 UTC---= INITIAL_SALE_END_TIME + 366 days---
    // 2028 --------- 366 --------------------------------------------- 2029-01-03 ---------------------------------
    // ------------------------------------ 2026-10-15 ------------------
    // ---------------------claim --------------------------------------------------------- 10000 AIP---------------------------
    //   --- 200 USDT------------------------------owner ---------------------------------------------
    //   200 USDT ------------------------------ owner ------------------10000 AIP ---------------------------
    //   ------------ claimFloorPlan ---------------------------------------------------------------------------------
    //   ------------------manageFloorPlanUsdt------------------------owner ------------------------------
    uint256 public constant FLOOR_PLAN_CLAIM_DEADLINE = INITIAL_SALE_END_TIME + 366 days;

    // ======================= ------------------immutable--------------------------------------------------------------- =======================
    // AIP ---------------------------------/------------------ AIP --- owner ------------------
    IERC20 public immutable aip;
    // USDT ------------------------------------/------------------ 200 USDT ---------------------------
    IERC20 public immutable usdt;
    // ------------BondingCurve------------------------------------------------------------------------ IBondingCurveView---
    IBondingCurveView public immutable main;

    // ======================= Floor Plan------------------------------------------------ slot 1 ------------ =======================
    // --------------- 6 ------------ BondingCurve ------------------------------------------ 76-81------------------------------
    //       ------------------------------------ Ownable._owner --- slot 0------------------ slot 1 ---------------
    //       slot 1: floorPlanClaimed---slot 2: floorPlanClaimedCount---slot 3: floorPlanUsdtPool---
    //       slot 4: floorPlanLocked---slot 5: floorPlanForfeited---slot 6: floorPlanLockedAipTotal
    // --------------------- Floor Plan------------------
    mapping(address => bool) private floorPlanClaimed;
    // --------- Floor Plan --------------------- 1000
    uint256 private floorPlanClaimedCount;
    // Floor Plan USDT --------------- owner ------ manageFloorPlanUsdt --------------------- 200 USDT
    uint256 private floorPlanUsdtPool;
    // --------------------- Floor Plan--------- 10000 AIP ------------------------
    mapping(address => bool) private floorPlanLocked;
    // --------------------- Floor Plan---unlockFloorPlan ---------------------------
    mapping(address => bool) private floorPlanForfeited;
    // ------ Floor Plan ------ AIP ------------------------------------------"------------ AIP"--------------- 10000 AIP---
    uint256 private floorPlanLockedAipTotal;

    // ======================= ------------------------------------------ =======================
    // --------------------------------------------------------------------- slot 7--------------- 0-6 ------------------
    //   hardhat_setStorageAt ---------------------------------------------------
    //   true = ---------------------------------------------------lockFloorPlan---------------
    //   ------/---------unlockFloorPlan/claimFloorPlan------------------------------------------------------------------------------------
    //   ------------ setPaused ---------------onlyMain------------------------ pause ---------
    //   ------------------------------------------------------------------"------------------------------"------------------
    bool private paused; // ------ 7---bool ------------------------ setPaused ---------------

    // ======================= ------------------------------------------------------------ =======================
    // Floor Plan USDT ------------------ manageFloorPlanUsdt(isDeposit=true)
    event FloorPlanUsdtDeposited(address indexed owner, uint256 amount);
    // Floor Plan USDT ------------------ manageFloorPlanUsdt(isDeposit=false)
    event FloorPlanUsdtWithdrawn(address indexed owner, uint256 amount);
    // Floor Plan ------------------ claimFloorPlan---aipAmount=10000 AIP --- owner---usdtAmount=200 USDT ------------
    event FloorPlanClaimed(address indexed user, uint256 aipAmount, uint256 usdtAmount);
    // Floor Plan ------------------ lockFloorPlan--------------- 10000 AIP ---------------------
    event FloorPlanLocked(address indexed user);
    // Floor Plan ------------------------------ unlockFloorPlan--------------- AIP ---------------------
    event FloorPlanUnlocked(address indexed user);
    // ------------------------------------------------ claimFloorPlan ---------------------------------------------------------
    // 200 USDT ------------------------------ 10000 AIP --------------------------------- claimFloorPlan ---------
    event FloorPlanForfeitedByUnlock(address indexed user, uint256 aipAmount);
    // ======================= --------------------------------------------------------- =======================
    // ------------------------------------ setPaused------------ pause/unpause ------------------
    //   paused=------------------by=------------------------------------onlyMain ---------
    event SubPausedChanged(bool paused, address indexed by);
    // ------------------------------ migrateOut---owner ------------ forwardSubCall ---------------
    //   tokenType=0 --- AIP------------------/ 1 --- USDT------------------to=---------------------------------amount=------------------
    event MigratedOut(uint8 indexed tokenType, address indexed to, uint256 amount);

    // ======================= ------ error---------------------------------revert --------------- =======================
    // ---------------------------Floor Plan ------ hasBoughtInitialShare ------------------------------
    error NotInitialSaleParticipant();
    // Floor Plan ---------------------------
    error FloorPlanAlreadyClaimed();
    // Floor Plan ---------------claimFloorPlan --- block.timestamp < INITIAL_SALE_END_TIME
    error FloorPlanLockNotExpired();
    // Floor Plan ---------------floorPlanClaimedCount >= 1000
    error FloorPlanMaxClaimsReached();
    // Floor Plan USDT ---------floorPlanUsdtPool < 200 USDT
    error InsufficientFloorPlanUsdt();
    // --------- Floor Plan ------ App---staking/weeklyRanking/referral---------------/--- Floor Plan
    error FloorPlanAppUnlocked();
    // Floor Plan ------------lockFloorPlan ---------------
    error FloorPlanAlreadyLocked();
    // Floor Plan ---------------unlockFloorPlan --- block.timestamp >= INITIAL_SALE_END_TIME
    error FloorPlanLockExpired();
    // Floor Plan ------------unlockFloorPlan ---------
    error FloorPlanNotLocked();
    // Floor Plan ------------unlockFloorPlan ---------------
    error FloorPlanAlreadyForfeited();
    // ---------------------------AIP/USDT/------------------------ address(0) ------------------------------
    error ZeroAddress();
    // ---------------------setPaused ------------------------------------------------------------------------------------------------
    error OnlyMain();
    // ======================= ------------------ error =======================
    // ---------------------------------------------------------------------/------------------------------------------------
    error ContractPaused();
    // ---------------------migrateOut --- tokenType --------- 0---AIP------ 1---USDT---------------------------------
    error InvalidTokenType();

    /**
     * --------- onlyMain --- ---------------------
     * ----------------------------------------------------------------------------
     * ------------setPaused---------------------------------------------------------------------------------------
     *   ------------------------------------ pause --------------------- + ------------------------------
     *   ---------------------------------------------/---------------------------"------------------------------"
     *   ------------------------------------------
     * ------------msg.sender --------------------------------- main --------------- revert OnlyMain---
     *   ---------------------------------------------------main ------------------------------------------------
     *   ---------/------"--------------- onlyMain"---------------------------------------------------
     */
    modifier onlyMain() {
        if (msg.sender != address(main)) revert OnlyMain(); // ------------
        _;
    }

    /**
     * --------------------- AIP / USDT / ------------------------ owner
     * ----------------------------------------------------------------------------
     * ---------------------------------------------------------------------------------------owner = ---------
     * ------------Ownable(msg.sender)--------------- owner------------------------------------ EOA ---------
     *         ------------ owner ------------ owner ------------------claimFloorPlan --- AIP ---------------------
     * ------------_aip=AIP ---------------_usdt=USDT ---------------_main=BondingCurve ---------------
     * --------------------------- address(0) --- revert ZeroAddress------------------------------------------
     */
    constructor(address _aip, address _usdt, address _main) Ownable(msg.sender) {
        if (_aip == address(0)) revert ZeroAddress(); // AIP --------- 0
        if (_usdt == address(0)) revert ZeroAddress(); // USDT --------- 0
        if (_main == address(0)) revert ZeroAddress(); // ------------------ 0
        aip = IERC20(_aip); // ------ AIP ---------immutable---
        usdt = IERC20(_usdt); // ------ USDT ---------immutable---
        main = IBondingCurveView(_main); // ------------------------------------immutable---
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
     * ------------_paused=true ---------------------------/ false ------------------------
     * ------------SubPausedChanged(_paused, msg.sender)
     */
    function setPaused(bool _paused) external onlyMain {
        paused = _paused; // ------------------------
        emit SubPausedChanged(_paused, msg.sender); // ---------------by=------------------
    }

    /**
     * migrateOut --- --------------------------------- AIP --- USDT ------------------------------------------------------
     * ----------------------------------------------------------------------------
     * ------------------------------------------ bug ------------------------------------------------------------------
     *   ---------------------------------------------0=------------ AIP---1=USDT ---------------------------------
     *   owner ------------------------------------------------------ owner ------------------
     * --------------- owner---onlyOwner------------------------------ owner=------------------------------------
     *   --- owner ------------ forwardSubCall --------------------------------- EOA ---------------
     * ------------tokenType=0 ------ AIP------------------------/ 1 ------ USDT------------------------
     *   to=------------------------------------------------------------------------
     * ------------------------------------------------------------------ --- to
     * ------------------tokenType=0 --- floorPlanLockedAipTotal --- 0 / tokenType=1 ---
     *   floorPlanUsdtPool --- 0--------------------------- view ------------------------------------------------------
     *   ---------------------------------floorPlanLocked ---------------------------------------------------------
     *   ---------------------------------------------
     * ------------to == address(0) --- ZeroAddress------------------------tokenType --- {0,1} --- InvalidTokenType
     * ------------MigratedOut(tokenType, to, ------------)
     */
    function migrateOut(uint8 tokenType, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress(); // ------------ 0---------------------
        if (tokenType == 0) { // ------------------ AIP---floorPlanLockedAipTotal ---------
            uint256 bal = aip.balanceOf(address(this)); // ------------------ AIP ---------------------------------------
            floorPlanLockedAipTotal = 0; // ------------------------------------------------------------------------
            aip.safeTransfer(to, bal); // ---------------bal=0 --- safeTransfer ---------------------------------------------
            emit MigratedOut(tokenType, to, bal); // ------------------------------
        } else if (tokenType == 1) { // ------ USDT ------------floorPlanUsdtPool ---------
            uint256 bal = usdt.balanceOf(address(this)); // ------------------ USDT ------------
            floorPlanUsdtPool = 0; // ---------------------------------------------------------------------
            usdt.safeTransfer(to, bal); // ---------------bal=0 --- safeTransfer ---------------------------------------------
            emit MigratedOut(tokenType, to, bal); // ------------------------------
        } else {
            revert InvalidTokenType(); // --------------------------------- 0=AIP / 1=USDT---
        }
    }

    /**
     * lockFloorPlan --- --------------------------- Floor Plan------------------------------ 10000 AIP---
     * ----------------------------------------------------------------------------
     * --------------------- INITIAL_SALE_END_TIME --------- 10000 AIP---TOKENS_PER_SHARE------------------ 200 USDT ---------------
     * ------------------AIP--------------- --- --------------------------- AIP ------ approve ------------------
     * ---------------------------------------------------------
     *   - initialShareProfile(msg.sender)._bought---NotInitialSaleParticipant------------------------------------
     *   - !floorPlanLocked[msg.sender]---FloorPlanAlreadyLocked------------------
     *   - !floorPlanForfeited[msg.sender]---FloorPlanAlreadyForfeited------ forfeit ------------------
     *   - block.timestamp < INITIAL_SALE_END_TIME---FloorPlanLockExpired---------------------
     *   - !hasUnlockedAnyApp(msg.sender)---FloorPlanAppUnlocked------------------------------------------------------------
     * ---------------------------------------------"---------/---------------"---A ---------------------------------------------
     *   ---------unlockFloorPlan---------------claimFloorPlan------------------------------------
     * ------------------ TOKENS_PER_SHARE AIP --- ------ floorPlanLocked --- ------ floorPlanLockedAipTotal --- ------------
     * ------------FloorPlanLocked(msg.sender)
     */
    function lockFloorPlan() external {
        if (paused) revert ContractPaused(); // ---------------------------------------/---------------------------------------------/---------------------
        // ---------------------------------------------------------------------------------------------
        // ------ (------------, ------------, ------ AIP ------)------------------------ _bought
        (bool bought, , ) = IBondingCurveView(main).initialShareProfile(msg.sender);
        if (!bought) revert NotInitialSaleParticipant(); // ------------------------
        if (floorPlanLocked[msg.sender]) revert FloorPlanAlreadyLocked(); // ------------
        if (floorPlanForfeited[msg.sender]) revert FloorPlanAlreadyForfeited(); // --- forfeit ------------
        if (block.timestamp >= INITIAL_SALE_END_TIME) revert FloorPlanLockExpired(); // ---------------
        if (IBondingCurveView(main).hasUnlockedAnyApp(msg.sender)) revert FloorPlanAppUnlocked(); // ------------------------------

        aip.safeTransferFrom(msg.sender, address(this), TOKENS_PER_SHARE); // ------ 10000 AIP------------------------------------
        floorPlanLocked[msg.sender] = true; // ------------
        floorPlanLockedAipTotal += TOKENS_PER_SHARE; // ------------------
        emit FloorPlanLocked(msg.sender);
    }

    /**
     * unlockFloorPlan --- --------- INITIAL_SALE_END_TIME --------------- Floor Plan---forfeit --------------------- AIP---
     * ----------------------------------------------------------------------------
     * ------------------------------ Floor Plan ------------------------------ 10000 AIP------------ forfeited------------------
     * ------------------AIP--------------- --- ------------
     * ---------------------------------------------------------
     *   - floorPlanLocked[msg.sender]---FloorPlanNotLocked------------------
     *   - !floorPlanClaimed[msg.sender]---FloorPlanAlreadyClaimed------------------------------
     *   - block.timestamp >= INITIAL_SALE_END_TIME---FloorPlanLockExpired------------------------------ claim---
     *     ------------ FLOOR_PLAN_CLAIM_DEADLINE --- claim ------------------ 200 USDT---
     * ------------------ floorPlanLocked --- ------ floorPlanLockedAipTotal --- ------ floorPlanForfeited --- ------ AIP --- ------------
     * ---------------floorPlanForfeited = true--------------------- Floor Plan---
     * ------------FloorPlanUnlocked(msg.sender)
     */
    function unlockFloorPlan() external {
        if (!floorPlanLocked[msg.sender]) revert FloorPlanNotLocked(); // ------------
        if (floorPlanClaimed[msg.sender]) revert FloorPlanAlreadyClaimed(); // ------------------
        if (block.timestamp >= INITIAL_SALE_END_TIME) revert FloorPlanLockExpired(); // ------------ claim

        floorPlanLocked[msg.sender] = false; // ------------------
        floorPlanLockedAipTotal -= TOKENS_PER_SHARE; // ------------------
        floorPlanForfeited[msg.sender] = true; // ------ forfeit------------------
        aip.safeTransfer(msg.sender, TOKENS_PER_SHARE); // ------ 10000 AIP---------------------------------
        emit FloorPlanUnlocked(msg.sender);
    }

    /**
     * claimFloorPlan --- --------------------------- Floor Plan ---------200 USDT ------ + 10000 AIP --- owner---
     * ----------------------------------------------------------------------------
     * ------------INITIAL_SALE_END_TIME ------FLOOR_PLAN_CLAIM_DEADLINE---2029-01-04 00:00 UTC---
     *   ------------------------------------------------ 200 USDT ------------------------ 10000 AIP ------ owner---
     *   --------->= FLOOR_PLAN_CLAIM_DEADLINE---------------200 USDT ------------------------------ owner
     *   ------------------10000 AIP ------------------------------------------------
     * ------------------AIP--------------- --- owner------------------------USDT--------------- --- ------------------------
     * ------------------------------------------------------------------------------------------
     *   - initialShareProfile(msg.sender)._bought---NotInitialSaleParticipant---
     *   - floorPlanLocked[msg.sender]---FloorPlanNotLocked------------------
     *   - !floorPlanClaimed[msg.sender]---FloorPlanAlreadyClaimed------------------
     *   - block.timestamp >= INITIAL_SALE_END_TIME---FloorPlanLockNotExpired------------------------------
     *   - ------------------hasUnlockedAnyApp(msg.sender) = true --------- FLOOR_PLAN_CLAIM_DEADLINE
     *     --- ------------ + 10000 AIP --------------------- revert---------------------------------------------
     *     --------------- USDT ------------------------------------------------------
     *   - floorPlanClaimedCount < FLOOR_PLAN_MAX_CLAIMS---FloorPlanMaxClaimsReached---1000 ---------------
     *   - floorPlanUsdtPool >= SHARE_PRICE---InsufficientFloorPlanUsdt---USDT --------- 200 USDT---
     * ---------------CEI ------------------------------------
     *   ---------------1. floorPlanLocked = false  2. floorPlanLockedAipTotal -= 10000e18
     *             3. floorPlanForfeited = true  4. ------ 10000 AIP ---------  5. --------------- return
     *   ---------------1. ------ floorPlanClaimed = true
     *   2. floorPlanClaimedCount++
     *   3. floorPlanUsdtPool -= SHARE_PRICE---200 USDT---
     *   4. floorPlanLockedAipTotal -= TOKENS_PER_SHARE
     *   5. --- 10000 AIP --- owner---AIP ------ lockFloorPlan ------------------------------------ 5.6 ---
     *      owner --------- owner=------------------AIP ------------------------------------------------------------
     *   6. --- 200 USDT ---------
     *   7. ------------
     * ------------FloorPlanClaimed(msg.sender, aipAmount, usdtAmount)---------------------
     *   FloorPlanForfeitedByUnlock(msg.sender, aipAmount)
     */
    function claimFloorPlan() external {
        // ------------------------------------------------------------------------------------------------------------------ _bought
        (bool bought, , ) = IBondingCurveView(main).initialShareProfile(msg.sender);
        if (!bought) revert NotInitialSaleParticipant(); // ------------------------
        if (!floorPlanLocked[msg.sender]) revert FloorPlanNotLocked(); // ------------
        if (floorPlanClaimed[msg.sender]) revert FloorPlanAlreadyClaimed(); // ------------

        if (block.timestamp < INITIAL_SALE_END_TIME) revert FloorPlanLockNotExpired(); // ---------------

        // ===== ------------/---------------------2026-10-09 ---------2026-10-15 ---------------------=====
        // ------------------ revert FloorPlanAppUnlocked------------------ unlockFloorPlan---L346------------------
        // --------- 10000 AIP ------------------ 200 USDT ------------------------------------------------------------------
        // owner ------------------10000 AIP --- owner ------------------ claim ---------
        // --------------------------------------- = ------------------------------"---------------------------------------------"
        // ------------------200 USDT --------------------------------------------------------- 10000 AIP ---------
        // forfeited------ unlockFloorPlan ---------------------------------------
        // ---2026-10-15 -----------------------------------------claim ---------------------------------------------------
        //   ------ 10000 AIP --- 200 USDT ---------------owner ------------------------------------
        //   FLOOR_PLAN_CLAIM_DEADLINE---2029-01-04 00:00 UTC---------------------------------
        //   --------------- = 200 USDT ------------------------------ owner ------------------10000 AIP ---------
        //   ------------------------------------------------------------------------------------------------------------
        //   --------------------------------------------- 2028-01-04 --- 2029-01-03---claim ---------------------
        // --------- 1000 ------------------------------------------------------------------------------ USDT ------------------
        if (block.timestamp >= FLOOR_PLAN_CLAIM_DEADLINE || IBondingCurveView(main).hasUnlockedAnyApp(msg.sender)) {
            floorPlanLocked[msg.sender] = false; // ------------------
            floorPlanLockedAipTotal -= TOKENS_PER_SHARE; // ------------------
            floorPlanForfeited[msg.sender] = true; // ------ forfeit------------------------------------------
            aip.safeTransfer(msg.sender, TOKENS_PER_SHARE); // 10000 AIP ------------------------
            emit FloorPlanForfeitedByUnlock(msg.sender, TOKENS_PER_SHARE);
            return;
        }

        if (floorPlanClaimedCount >= FLOOR_PLAN_MAX_CLAIMS) revert FloorPlanMaxClaimsReached(); // 1000 ------------

        uint256 aipAmount = TOKENS_PER_SHARE; // 10000 AIP

        uint256 usdtAmount = SHARE_PRICE; // 200 USDT
        if (floorPlanUsdtPool < usdtAmount) revert InsufficientFloorPlanUsdt(); // USDT ---------

        // CEI: ---------------
        floorPlanClaimed[msg.sender] = true; // ------------
        floorPlanClaimedCount++; // ------------ +1
        floorPlanUsdtPool -= usdtAmount; // USDT ---------
        floorPlanLockedAipTotal -= TOKENS_PER_SHARE; // ------------------

        // ------------AIP ------ lockFloorPlan ---------------------------
        aip.safeTransfer(owner(), aipAmount); // 10000 AIP --- owner------------ 5.6 ------ owner=------------------AIP ------------------------
        usdt.safeTransfer(msg.sender, usdtAmount); // 200 USDT ------------

        emit FloorPlanClaimed(msg.sender, aipAmount, usdtAmount);
    }

    /**
     * manageFloorPlanUsdt --- owner ------ Floor Plan USDT ------------------------------
     * ----------------------------------------------------------------------------
     * --------------- owner--------- msg.sender != owner() ---------revert OwnableUnauthorizedAccount---
     *         ---------------------------------------------OwnableUnauthorizedAccount --------- Ownable ------------
     *         owner ------------------------------ 5.6 ------------------------------------ forwardSubCall ------------
     * ------------amount=USDT ---------isDeposit=true ------ / false ------
     * ---isDeposit=true ------------------------------------------------------------------------------"------------"------
     *   --- 1 ------owner --- USDT --------------------- ERC20 transfer---------------------------------------------------
     *   --- 2 ------------------------------------------floorPlanUsdtPool += amount--------- FloorPlanUsdtDeposited---
     *   --------------------------- usdt.safeTransferFrom(msg.sender, ...) ------------------------owner ---------
     *   --------------- msg.sender ------------------------------------------------ USDT ------------------------
     *   ------------------ approve ---------forwardSubCall ------------------------------------------------------
     *   ------------------ revert------------------------------------------------------------------------------------------
     *   ------------------------------ < ------+amount --- revert---------------------------------------------
     *   ------"------"---------------------------------------------floorPlanUsdtPool --- --------- USDT ---------------------
     * ---isDeposit=false --------------------- amount <= floorPlanUsdtPool---InsufficientFloorPlanUsdt------
     *   floorPlanUsdtPool -= amount---USDT--------------- --- --------- owner() ------------------------------
     *   ------------------------------------ msg.sender --------------------------- msg.sender ------------------------
     *   --------------------------------------- owner() ---------------renounce------ revert ZeroAddress ------------
     *   ------ FloorPlanUsdtWithdrawn---indexed ---------------------------
     * ------------owner --------------------- USDT ------ claimFloorPlan ------------------ 200 USDT -- 1000 = 200,000 USDT---
     */
    function manageFloorPlanUsdt(uint256 amount, bool isDeposit) external {
        if (msg.sender != owner()) revert OwnableUnauthorizedAccount(msg.sender); // --- owner
        if (isDeposit) { // ---------------------------USDT ------ owner ---------------------------------------------
            // ------------------------------ USDT ---------------------------------------------------------------
            //   ------------ claimFloorPlan --- 200 USDT ------------------------------
            if (usdt.balanceOf(address(this)) < floorPlanUsdtPool + amount) revert InsufficientFloorPlanUsdt();
            floorPlanUsdtPool += amount; // ---------------------
            emit FloorPlanUsdtDeposited(msg.sender, amount);
        } else { // ------
            if (amount > floorPlanUsdtPool) revert InsufficientFloorPlanUsdt(); // ------------
            floorPlanUsdtPool -= amount; // ---------------------
            address recipient = main.owner(); // ------------------------ owner()--------- EOA------------------------------
            if (recipient == address(0)) revert ZeroAddress(); // ------------------------renounce---------------------------------------
            usdt.safeTransfer(recipient, amount); // USDT--------------- --- ------------------------------------------------
            emit FloorPlanUsdtWithdrawn(recipient, amount); // ------ indexed ---------------------
        }
    }

    /**
     * getFloorPlanFullInfo --- ------ Floor Plan ---------------13 ---------------
     * ----------------------------------------------------------------------------
     * ------------------ Floor Plan ------------------------------------------ view------------ Gas---------------------------
     * ------------user=------------
     * ------------
     *   - _claimedCount---floorPlanClaimedCount---------------------
     *   - _maxClaims---FLOOR_PLAN_MAX_CLAIMS---1000 ---------------
     *   - _usdtPool---floorPlanUsdtPool---USDT ------------------
     *   - _isEligible---hasInitial && !hasUnlockedAnyApp(user)------------------------------------------------------------------------------
     *   - _buyTime---initialShareProfile(user)._buyTime---------------------------------------------------------
     *   - _isClaimed---floorPlanClaimed[user]---------------------
     *   - _unlockTime---INITIAL_SALE_END_TIME---------------------------
     *   - _initialShareAipAmount---initialShareProfile(user)._aipAmount--------------- AIP ------------------------------------
     *   - _currentBalance---aip.balanceOf(user)--------------- AIP ---------
     *   - _isPioneer---hasInitial && !floorPlanClaimed[user]------------------------------------------------------
     *   - _isForfeited---hasInitial && floorPlanClaimed[user]------------ forfeit------------------------------------
     *   - _isLocked---floorPlanLocked[user]------------------ Floor Plan---
     *   - _isLockForfeited---floorPlanForfeited[user]---------------------------------
     */
    function getFloorPlanFullInfo(address user) external view returns (
        uint256 _claimedCount,
        uint256 _maxClaims,
        uint256 _usdtPool,
        bool _isEligible,
        uint256 _buyTime,
        bool _isClaimed,
        uint256 _unlockTime,
        uint256 _initialShareAipAmount,
        uint256 _currentBalance,
        bool _isPioneer,
        bool _isForfeited,
        bool _isLocked,
        bool _isLockForfeited
    ) {
        // --------------------------------------------------- / ------------ / ------ AIP ---------------------------------------
        (bool hasInitial, uint256 buyTime, uint256 initialAipAmount) = IBondingCurveView(main).initialShareProfile(user);
        // ------------------------------------------------------------------------------------
        bool appUnlocked = IBondingCurveView(main).hasUnlockedAnyApp(user);
        return (
            floorPlanClaimedCount,
            FLOOR_PLAN_MAX_CLAIMS,
            floorPlanUsdtPool,
            hasInitial && !appUnlocked, // ---------------------------------------------------------------
            buyTime,
            floorPlanClaimed[user],
            INITIAL_SALE_END_TIME,
            initialAipAmount,
            aip.balanceOf(user),
            hasInitial && !floorPlanClaimed[user], // ---------------------------------------
            hasInitial && floorPlanClaimed[user], // --- forfeit---------------------------------
            floorPlanLocked[user],
            floorPlanForfeited[user]
        );
    }

    /**
     * getFloorPlanPoolStats --- ------ Floor Plan ------------4 ---------------
     * ----------------------------------------------------------------------------
     * ------------------ Floor Plan ------/--------------- USDT ------------------------------ owner ------ USDT ------------
     * ------------------------ view------------ Gas---------------------------
     * ------------
     *   - _lockedCount---floorPlanLockedAipTotal / TOKENS_PER_SHARE------------------ Floor Plan ------------------------------------ 10000 AIP---
     *   - _claimedCount---floorPlanClaimedCount------------ 200 USDT ------------------------
     *   - _usdtPool---floorPlanUsdtPool---USDT ------------------------owner ------ manageFloorPlanUsdt ------/---------
     *   - _pendingUsdt---_lockedCount -- SHARE_PRICE--------------- = ------------ -- 200 USDT---
     * ---owner --------------- _pendingUsdt --- _usdtPool--------------------------- USDT ------------------ 200 USDT---
     */
    function getFloorPlanPoolStats() external view returns (
        uint256 _lockedCount,
        uint256 _claimedCount,
        uint256 _usdtPool,
        uint256 _pendingUsdt
    ) {
        _lockedCount = floorPlanLockedAipTotal / TOKENS_PER_SHARE; // ------ = ------ AIP ------ / 10000 AIP
        return (
            _lockedCount,
            floorPlanClaimedCount,
            floorPlanUsdtPool,
            _lockedCount * SHARE_PRICE // ------ = ------ -- 200 USDT
        );
    }
}
