// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SoulinXPool
/// @notice Credit-based P2P lending pool for AI agents on X Layer.
///         Credit scores determine collateral ratios. OKB collateral, USDG loans.
///         "Your reputation is your oracle."
contract SoulinXPool {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdg;
    address public immutable operator;
    address public immutable feeRecipient;
    uint256 public constant FEE_BPS = 100; // 1%

    // ═══ Credit Oracle ═══
    mapping(address => uint256) public creditScores;

    // ═══ Pool ═══
    mapping(address => uint256) public lenderDeposits;
    mapping(address => uint256) public lenderEarned;
    uint256 public totalDeposits;
    uint256 public totalBorrowed;

    // ═══ Collateral ═══
    mapping(address => uint256) public okbCollateral;

    // ═══ Loans ═══
    enum Status { None, Active, Repaid, Defaulted }

    struct Loan {
        address borrower;
        uint256 amount;
        uint256 collateral;
        uint256 repayAmount;
        uint256 dueAt;
        Status status;
    }

    mapping(bytes32 => Loan) public loans;
    mapping(address => bytes32) public activeLoanId;

    // ═══ Events ═══
    event CreditUpdated(address indexed agent, uint256 score);
    event Deposited(address indexed lender, uint256 amount);
    event Withdrawn(address indexed lender, uint256 total);
    event CollateralLocked(address indexed borrower, uint256 okbAmount);
    event LoanApproved(bytes32 indexed id, address indexed borrower, uint256 amount, uint256 collateral, uint256 score);
    event LoanRepaid(bytes32 indexed id, address indexed borrower);
    event LoanDefaulted(bytes32 indexed id, address indexed borrower, uint256 seized);

    modifier onlyOperator() {
        require(msg.sender == operator, "Not operator");
        _;
    }

    constructor(address _usdg, address _operator, address _feeRecipient) {
        usdg = IERC20(_usdg);
        operator = _operator;
        feeRecipient = _feeRecipient;
    }

    // ═══════════════════════════════════════
    // CREDIT ORACLE
    // ═══════════════════════════════════════

    function updateCredit(address agent, uint256 score) external onlyOperator {
        require(score <= 100, "Max 100");
        creditScores[agent] = score;
        emit CreditUpdated(agent, score);
    }

    function updateCreditBatch(
        address[] calldata agents, uint256[] calldata scores
    ) external onlyOperator {
        require(agents.length == scores.length, "Mismatch");
        for (uint256 i = 0; i < agents.length; i++) {
            require(scores[i] <= 100, "Max 100");
            creditScores[agents[i]] = scores[i];
            emit CreditUpdated(agents[i], scores[i]);
        }
    }

    function getCollateralPct(uint256 score) public pure returns (uint256) {
        if (score >= 90) return 0;
        if (score >= 80) return 20;
        if (score >= 70) return 50;
        if (score >= 50) return 100;
        revert("Credit too low");
    }

    function getInterestPct(uint256 score) public pure returns (uint256) {
        if (score >= 90) return 1;
        if (score >= 80) return 2;
        if (score >= 70) return 5;
        return 10;
    }

    function getDuration(uint256 score) public pure returns (uint256) {
        if (score >= 90) return 7 days;
        if (score >= 80) return 3 days;
        if (score >= 70) return 2 days;
        return 1 days;
    }

    // ═══════════════════════════════════════
    // LENDER (direct)
    // ═══════════════════════════════════════

    function deposit(uint256 amount) external {
        require(amount > 0, "Zero");
        usdg.safeTransferFrom(msg.sender, address(this), amount);
        lenderDeposits[msg.sender] += amount;
        totalDeposits += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw() external {
        uint256 principal = lenderDeposits[msg.sender];
        require(principal > 0, "No deposit");
        uint256 earned = lenderEarned[msg.sender];
        uint256 total = principal + earned;
        lenderDeposits[msg.sender] = 0;
        lenderEarned[msg.sender] = 0;
        totalDeposits -= principal;
        usdg.safeTransfer(msg.sender, total);
        emit Withdrawn(msg.sender, total);
    }

    // ═══════════════════════════════════════
    // OPERATOR PROXY (for x402 flow: operator receives USDG via x402, then calls these)
    // ═══════════════════════════════════════

    /// @notice Operator deposits USDG on behalf of a lender (USDG already in operator wallet from x402)
    function depositFor(address lender, uint256 amount) external onlyOperator {
        require(amount > 0, "Zero");
        usdg.safeTransferFrom(msg.sender, address(this), amount);
        lenderDeposits[lender] += amount;
        totalDeposits += amount;
        emit Deposited(lender, amount);
    }

    /// @notice Operator withdraws on behalf of a lender, sends USDG to lender address
    function withdrawFor(address lender) external onlyOperator {
        uint256 principal = lenderDeposits[lender];
        require(principal > 0, "No deposit");
        uint256 earned = lenderEarned[lender];
        uint256 total = principal + earned;
        lenderDeposits[lender] = 0;
        lenderEarned[lender] = 0;
        totalDeposits -= principal;
        usdg.safeTransfer(lender, total);
        emit Withdrawn(lender, total);
    }

    /// @notice Operator repays on behalf of borrower (USDG already in operator wallet from x402)
    function repayFor(bytes32 loanId, address borrower) external onlyOperator {
        Loan storage loan = loans[loanId];
        require(loan.status == Status.Active, "Not active");
        require(loan.borrower == borrower, "Not borrower");

        usdg.safeTransferFrom(msg.sender, address(this), loan.repayAmount);

        totalBorrowed -= loan.amount;
        loan.status = Status.Repaid;
        delete activeLoanId[borrower];

        uint256 collateral = loan.collateral;
        okbCollateral[borrower] -= collateral;
        if (collateral > 0) {
            (bool ok,) = borrower.call{value: collateral}("");
            require(ok, "OKB return failed");
        }

        emit LoanRepaid(loanId, borrower);
    }

    // ═══════════════════════════════════════
    // BORROWER
    // ═══════════════════════════════════════

    /// @notice Lock OKB as collateral before borrowing
    function lockCollateral() external payable {
        require(msg.value > 0, "No OKB");
        okbCollateral[msg.sender] += msg.value;
        emit CollateralLocked(msg.sender, msg.value);
    }

    /// @notice Withdraw OKB collateral not locked in an active loan
    function withdrawExcessCollateral(uint256 amount) external {
        bytes32 loanId = activeLoanId[msg.sender];
        uint256 locked = 0;
        if (loanId != bytes32(0) && loans[loanId].status == Status.Active) {
            locked = loans[loanId].collateral;
        }
        uint256 excess = okbCollateral[msg.sender] - locked;
        require(amount <= excess, "Exceeds withdrawable");
        okbCollateral[msg.sender] -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    /// @notice Repay loan — borrower calls directly, contract releases OKB
    function repay(bytes32 loanId) external {
        Loan storage loan = loans[loanId];
        require(loan.status == Status.Active, "Not active");
        require(loan.borrower == msg.sender, "Not borrower");

        usdg.safeTransferFrom(msg.sender, address(this), loan.repayAmount);

        totalBorrowed -= loan.amount;
        loan.status = Status.Repaid;
        delete activeLoanId[msg.sender];

        uint256 collateral = loan.collateral;
        okbCollateral[msg.sender] -= collateral;
        if (collateral > 0) {
            (bool ok,) = msg.sender.call{value: collateral}("");
            require(ok, "OKB return failed");
        }

        emit LoanRepaid(loanId, msg.sender);
    }

    // ═══════════════════════════════════════
    // OPERATOR
    // ═══════════════════════════════════════

    /// @notice Approve loan — contract derives collateral & duration from on-chain credit score
    function approveLoan(
        bytes32 loanId,
        address borrower,
        uint256 amount,
        uint256 okbPriceX18
    ) external onlyOperator {
        require(loans[loanId].status == Status.None, "Loan exists");
        require(activeLoanId[borrower] == bytes32(0), "Active loan");

        uint256 score = creditScores[borrower];
        require(score >= 50, "Credit too low");

        uint256 collateralPct = getCollateralPct(score);
        uint256 duration = getDuration(score);

        uint256 requiredOkb = 0;
        if (collateralPct > 0) {
            requiredOkb = (amount * collateralPct * 1e18) / (100 * okbPriceX18);
        }

        require(okbCollateral[borrower] >= requiredOkb, "Insufficient collateral");

        uint256 avail = totalDeposits - totalBorrowed;
        require(amount <= avail, "Insufficient liquidity");

        uint256 interestPct = getInterestPct(score);
        uint256 repayAmount = amount + (amount * interestPct / 100);

        loans[loanId] = Loan({
            borrower: borrower,
            amount: amount,
            collateral: requiredOkb,
            repayAmount: repayAmount,
            dueAt: block.timestamp + duration,
            status: Status.Active
        });
        activeLoanId[borrower] = loanId;
        totalBorrowed += amount;

        uint256 fee = amount * FEE_BPS / 10000;
        usdg.safeTransfer(borrower, amount - fee);
        if (fee > 0) usdg.safeTransfer(feeRecipient, fee);

        emit LoanApproved(loanId, borrower, amount, requiredOkb, score);
    }

    /// @notice Mark overdue loan as defaulted, seize OKB collateral
    function defaultLoan(bytes32 loanId) external onlyOperator {
        Loan storage loan = loans[loanId];
        require(loan.status == Status.Active, "Not active");
        require(block.timestamp > loan.dueAt, "Not yet due");

        uint256 seized = loan.collateral;
        loan.status = Status.Defaulted;
        totalBorrowed -= loan.amount;
        okbCollateral[loan.borrower] -= seized;
        delete activeLoanId[loan.borrower];

        emit LoanDefaulted(loanId, loan.borrower, seized);
    }

    /// @notice Distribute interest to a lender (called after repayment)
    function distributeInterest(
        address lender, uint256 amount
    ) external onlyOperator {
        require(lenderDeposits[lender] > 0, "Not a lender");
        lenderEarned[lender] += amount;
    }

    /// @notice Withdraw seized OKB (from defaults)
    function withdrawSeizedOkb(address to, uint256 amount) external onlyOperator {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    // ═══════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════

    function available() external view returns (uint256) {
        return totalDeposits - totalBorrowed;
    }

    receive() external payable {
        okbCollateral[msg.sender] += msg.value;
        emit CollateralLocked(msg.sender, msg.value);
    }
}
