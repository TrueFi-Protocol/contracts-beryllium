// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IValuationStrategy} from "../interfaces/IValuationStrategy.sol";
import {IDebtInstrument} from "../interfaces/IDebtInstrument.sol";
import {IBulletLoans, BulletLoanStatus} from "./interfaces/IBulletLoans.sol";
import {IProtocolConfig} from "../interfaces/IProtocolConfig.sol";
import {Upgradeable} from "../access/Upgradeable.sol";
import {IBasePortfolio} from "../interfaces/IBasePortfolio.sol";

contract BulletLoansValuationStrategy is Upgradeable, IValuationStrategy {
    address public parentStrategy;
    IBulletLoans public bulletLoansAddress;
    mapping(IBasePortfolio => uint256[]) public bulletLoans;

    event InstrumentAdded(IBasePortfolio indexed portfolio, IDebtInstrument indexed instrument, uint256 indexed instrumentId);
    event InstrumentRemoved(IBasePortfolio indexed portfolio, IDebtInstrument indexed instrument, uint256 indexed instrumentId);

    modifier onlyPortfolioOrParentStrategy(IBasePortfolio portfolio) {
        require(
            msg.sender == address(portfolio) || msg.sender == parentStrategy,
            "BulletLoansValuationStrategy: Only portfolio or parent strategy"
        );
        _;
    }

    function initialize(
        IProtocolConfig _protocolConfig,
        IBulletLoans _bulletLoans,
        address _parentStrategy
    ) external initializer {
        __Upgradeable_init(msg.sender, _protocolConfig.pauserAddress());
        bulletLoansAddress = _bulletLoans;
        parentStrategy = _parentStrategy;
    }

    function onInstrumentFunded(
        IBasePortfolio portfolio,
        IDebtInstrument instrument,
        uint256 instrumentId
    ) external onlyPortfolioOrParentStrategy(portfolio) {
        require(instrument == bulletLoansAddress, "BulletLoansValuationStrategy: Unexpected instrument");

        bulletLoans[portfolio].push(instrumentId);
        emit InstrumentAdded(portfolio, instrument, instrumentId);
    }

    function getBulletLoans(IBasePortfolio portfolio) public view returns (uint256[] memory) {
        return bulletLoans[portfolio];
    }

    function onInstrumentUpdated(
        IBasePortfolio portfolio,
        IDebtInstrument instrument,
        uint256 instrumentId
    ) external {
        BulletLoanStatus status = bulletLoansAddress.getStatus(instrumentId);
        if (status == BulletLoanStatus.Started) {
            return;
        }

        uint256[] storage loans = bulletLoans[portfolio];
        for (uint256 i; i < loans.length; i++) {
            if (loans[i] == instrumentId) {
                loans[i] = loans[loans.length - 1];
                loans.pop();
                emit InstrumentRemoved(portfolio, instrument, instrumentId);
                return;
            }
        }
    }

    function calculateValue(IBasePortfolio portfolio) public view returns (uint256) {
        uint256 _value = 0;
        for (uint256 i = 0; i < bulletLoans[portfolio].length; i++) {
            (
                ,
                BulletLoanStatus status,
                uint64 duration,
                uint64 repaymentDate,
                ,
                uint256 principal,
                uint256 totalDebt,
                uint256 amountRepaid
            ) = bulletLoansAddress.loans(bulletLoans[portfolio][i]);
            if (status != BulletLoanStatus.Started) {
                continue;
            }
            if (repaymentDate <= block.timestamp) {
                _value += totalDebt - amountRepaid;
            } else {
                _value +=
                    ((totalDebt - principal) * (block.timestamp + duration - repaymentDate)) /
                    duration +
                    principal -
                    amountRepaid;
            }
        }
        return _value;
    }
}
