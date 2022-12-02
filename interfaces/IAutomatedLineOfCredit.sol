// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IProtocolConfig} from "./IProtocolConfig.sol";
import {IPortfolio} from "./IPortfolio.sol";
import {IDepositController} from "./IDepositController.sol";
import {IWithdrawController} from "./IWithdrawController.sol";
import {ITransferController} from "./ITransferController.sol";

enum AutomatedLineOfCreditStatus {
    Open,
    Full,
    Closed
}

interface IAutomatedLineOfCredit is IPortfolio {
    struct InterestRateParameters {
        uint32 minInterestRate;
        uint32 minInterestRateUtilizationThreshold;
        uint32 optimumInterestRate;
        uint32 optimumUtilization;
        uint32 maxInterestRate;
        uint32 maxInterestRateUtilizationThreshold;
    }

    struct Controllers {
        IDepositController depositController;
        IWithdrawController withdrawController;
        ITransferController transferController;
    }

    function initialize(
        IProtocolConfig _protocolConfig,
        uint256 _duration,
        IERC20Metadata _asset,
        address _borrower,
        uint256 _maxSize,
        InterestRateParameters memory _interestRateParameters,
        Controllers memory controllers,
        string memory name,
        string memory symbol
    ) external;

    function borrow(uint256 amount) external;

    function repay(uint256 amount) external;
}
