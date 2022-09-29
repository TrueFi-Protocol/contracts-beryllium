// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDebtInstrument} from "../../interfaces/IDebtInstrument.sol";

enum BulletLoanStatus {
    Created,
    Started,
    FullyRepaid,
    Defaulted,
    Resolved,
    Cancelled
}

interface IBulletLoans is IDebtInstrument {
    struct LoanMetadata {
        IERC20Metadata asset;
        BulletLoanStatus status;
        uint64 duration;
        uint64 repaymentDate;
        address recipient;
        uint256 principal;
        uint256 totalDebt;
        uint256 amountRepaid;
    }

    function loans(uint256 id)
        external
        view
        returns (
            IERC20Metadata,
            BulletLoanStatus,
            uint64,
            uint64,
            address,
            uint256,
            uint256,
            uint256
        );

    function createLoan(
        IERC20Metadata _asset,
        uint256 principal,
        uint256 totalDebt,
        uint64 duration,
        address recipient
    ) external returns (uint256);

    function markLoanAsResolved(uint256 instrumentId) external;

    function getStatus(uint256 instrumentId) external view returns (BulletLoanStatus);

    function updateInstrument() external;
}
