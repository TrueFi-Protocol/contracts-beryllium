// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAutomatedLineOfCredit} from "./interfaces/IAutomatedLineOfCredit.sol";
import {PortfolioFactory} from "./PortfolioFactory.sol";
import {ITransferController} from "./interfaces/ITransferController.sol";
import {IDepositController} from "./interfaces/IDepositController.sol";
import {IWithdrawController} from "./interfaces/IWithdrawController.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract AutomatedLineOfCreditFactory is PortfolioFactory {
    using Address for address;

    struct ControllersData {
        /// @dev Implementation of the controller applied when calling deposit-related functions
        address depositControllerImplementation;
        /// @dev Encoded args with initialize method selector from deposit controller
        bytes depositControllerInitData;
        /// @dev Implementation of the controller applied when calling withdraw-related functions
        address withdrawControllerImplementation;
        /// @dev Encoded args with initialize method selector from withdraw controller
        bytes withdrawControllerInitData;
        /// @dev Implementation of the controller used when calling transfer-related functions
        address transferControllerImplementation;
        /// @dev Encoded args with initialize method selector from transfer controller
        bytes transferControllerInitData;
    }

    function createPortfolio(
        uint256 _duration,
        IERC20Metadata _asset,
        uint256 _maxSize,
        IAutomatedLineOfCredit.InterestRateParameters calldata _interestRateParameters,
        ControllersData calldata controllersData,
        string calldata name,
        string calldata symbol
    ) external virtual onlyRole(MANAGER_ROLE) {
        _createPortfolio(_duration, _asset, _maxSize, _interestRateParameters, controllersData, name, symbol);
    }

    function _createPortfolio(
        uint256 _duration,
        IERC20Metadata _asset,
        uint256 _maxSize,
        IAutomatedLineOfCredit.InterestRateParameters calldata _interestRateParameters,
        ControllersData calldata controllersData,
        string calldata name,
        string calldata symbol
    ) internal {
        IAutomatedLineOfCredit.Controllers memory controllers = setupControllers(controllersData);
        bytes memory initCalldata = abi.encodeWithSelector(
            IAutomatedLineOfCredit.initialize.selector,
            protocolConfig,
            _duration,
            _asset,
            msg.sender,
            _maxSize,
            _interestRateParameters,
            controllers,
            name,
            symbol
        );
        _deployPortfolio(initCalldata);
    }

    function setupControllers(ControllersData memory controllersData) internal returns (IAutomatedLineOfCredit.Controllers memory) {
        address depositController = Clones.clone(controllersData.depositControllerImplementation);
        depositController.functionCall(controllersData.depositControllerInitData);

        address withdrawController = Clones.clone(controllersData.withdrawControllerImplementation);
        withdrawController.functionCall(controllersData.withdrawControllerInitData);

        address transferController = Clones.clone(controllersData.transferControllerImplementation);
        transferController.functionCall(controllersData.transferControllerInitData);

        return
            IAutomatedLineOfCredit.Controllers(
                IDepositController(depositController),
                IWithdrawController(withdrawController),
                ITransferController(transferController)
            );
    }
}
