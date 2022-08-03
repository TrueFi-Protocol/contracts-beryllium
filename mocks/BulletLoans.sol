// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBulletLoans, BulletLoanStatus} from "./interfaces/IBulletLoans.sol";

contract BulletLoans is ERC721Upgradeable, IBulletLoans {
    using SafeERC20 for IERC20;

    uint256 internal nextId;
    mapping(uint256 => LoanMetadata) public override loans;

    event LoanCreated(uint256 indexed instrumentId);

    event LoanRepaid(uint256 indexed instrumentId, uint256 amount);

    event LoanStatusChanged(uint256 indexed instrumentId, BulletLoanStatus newStatus);

    constructor() initializer {
        __ERC721_init("BulletLoans", "BulletLoans");
    }

    function createLoan(
        IERC20 _asset,
        uint256 _principal,
        uint256 _totalDebt,
        uint64 _duration,
        address _recipient
    ) external override returns (uint256) {
        require(_totalDebt >= _principal, "BulletLoans: Total debt cannot be less than principal");
        require(_duration > 0, "BulletLoans: Loan duration must be nonzero");

        uint256 instrumentId = nextId++;
        loans[instrumentId] = LoanMetadata(_asset, BulletLoanStatus.Created, _duration, 0, _recipient, _principal, _totalDebt, 0);
        _safeMint(msg.sender, instrumentId);

        emit LoanCreated(instrumentId);

        return instrumentId;
    }

    function start(uint256 instrumentId) external {
        loans[instrumentId].repaymentDate = uint64(block.timestamp) + loans[instrumentId].duration;
        _changeLoanStatus(instrumentId, BulletLoanStatus.Started);
    }

    function repay(uint256 instrumentId, uint256 amount) external override returns (uint256 principalRepaid, uint256 interestRepaid) {
        require(msg.sender == ownerOf(instrumentId), "BulletLoans: Caller is not the owner of the loan");
        require(getStatus(instrumentId) == BulletLoanStatus.Started, "BulletLoans: Can only repay started loan");
        LoanMetadata storage loan = loans[instrumentId];
        loan.amountRepaid += amount;
        require(loan.totalDebt >= loan.amountRepaid, "BulletLoans: Loan cannot be overpaid");

        if (loan.amountRepaid >= loan.totalDebt) {
            _changeLoanStatus(instrumentId, BulletLoanStatus.FullyRepaid);
        }

        emit LoanRepaid(instrumentId, amount);

        return (amount, 0);
    }

    function markAsDefaulted(uint256 instrumentId) external override {
        require(ownerOf(instrumentId) == msg.sender, "BulletLoans: Caller is not the owner of the loan");
        BulletLoanStatus status = loans[instrumentId].status;
        require(
            status == BulletLoanStatus.Created || status == BulletLoanStatus.Started,
            "BulletLoans: Only created or started loan can be marked as defaulted"
        );
        _changeLoanStatus(instrumentId, BulletLoanStatus.Defaulted);
    }

    function markLoanAsResolved(uint256 instrumentId) external {
        require(ownerOf(instrumentId) == msg.sender, "BulletLoans: Caller is not the owner of the loan");
        require(loans[instrumentId].status == BulletLoanStatus.Defaulted, "BulletLoans: Cannot resolve not defaulted loan");
        _changeLoanStatus(instrumentId, BulletLoanStatus.Resolved);
    }

    function name() public pure override returns (string memory) {
        return "BulletLoans";
    }

    function symbol() public pure override returns (string memory) {
        return "BulletLoans";
    }

    function principal(uint256 instrumentId) external view override returns (uint256) {
        return loans[instrumentId].principal;
    }

    function asset(uint256 instrumentId) external view override returns (IERC20) {
        return loans[instrumentId].asset;
    }

    function recipient(uint256 instrumentId) external view override returns (address) {
        return loans[instrumentId].recipient;
    }

    function endDate(uint256 instrumentId) external view override returns (uint256) {
        return loans[instrumentId].repaymentDate;
    }

    function issueInstrumentSelector() external pure returns (bytes4) {
        return this.createLoan.selector;
    }

    function updateInstrumentSelector() external pure returns (bytes4) {
        return this.updateInstrument.selector;
    }

    function unpaidDebt(uint256 instrumentId) external view returns (uint256) {
        LoanMetadata memory loan = loans[instrumentId];
        return saturatingSub(loan.totalDebt, loan.amountRepaid);
    }

    function getStatus(uint256 instrumentId) public view returns (BulletLoanStatus) {
        require(_exists(instrumentId), "BulletLoans: Cannot get status of non-existent loan");
        return loans[instrumentId].status;
    }

    function _changeLoanStatus(uint256 instrumentId, BulletLoanStatus status) private {
        loans[instrumentId].status = status;
        emit LoanStatusChanged(instrumentId, status);
    }

    function saturatingSub(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function cancel(uint256 instrumentId) external {
        require(msg.sender == ownerOf(instrumentId), "BulletLoans: Caller is not the owner of the loan");
        require(loans[instrumentId].status == BulletLoanStatus.Created, "BulletLoans: Only created loan can be cancelled");
        _changeLoanStatus(instrumentId, BulletLoanStatus.Cancelled);
        emit LoanStatusChanged(instrumentId, BulletLoanStatus.Cancelled);
    }

    function updateInstrument() external {}
}
