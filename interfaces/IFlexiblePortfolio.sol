// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20WithDecimals} from "./IERC20WithDecimals.sol";
import {IBasePortfolio} from "./IBasePortfolio.sol";
import {IProtocolConfig} from "./IProtocolConfig.sol";
import {IDebtInstrument} from "./IDebtInstrument.sol";
import {IDepositStrategy} from "./IDepositStrategy.sol";
import {IWithdrawStrategy} from "./IWithdrawStrategy.sol";
import {IValuationStrategy} from "./IValuationStrategy.sol";
import {ITransferStrategy} from "./ITransferStrategy.sol";
import {IERC4626} from "./IERC4626.sol";

interface IFlexiblePortfolio is IERC4626 {
    struct ERC20Metadata {
        string name;
        string symbol;
    }

    struct Strategies {
        IDepositStrategy depositStrategy;
        IWithdrawStrategy withdrawStrategy;
        ITransferStrategy transferStrategy;
        IValuationStrategy valuationStrategy;
    }

    function initialize(
        IProtocolConfig _protocolConfig,
        uint256 _duration,
        IERC20WithDecimals _asset,
        address _manager,
        uint256 _maxSize,
        Strategies calldata _strategies,
        IDebtInstrument[] calldata _allowedInstruments,
        ERC20Metadata calldata tokenMetadata
    ) external;

    function fundInstrument(IDebtInstrument loans, uint256 instrumentId) external;

    function repay(
        IDebtInstrument loans,
        uint256 instrumentId,
        uint256 amount
    ) external;
}
