// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {Upgradeable} from "./access/Upgradeable.sol";

contract ProtocolConfig is Upgradeable, IProtocolConfig {
    uint256 public protocolFeeRate;
    address public protocolAddress;
    address public pauserAddress;

    event ProtocolFeeRateChanged(uint256 newProtocolFeeRate);
    event ProtocolAddressChanged(address indexed newProtocolAddress);
    event PauserAddressChanged(address indexed newPauserAddress);

    function initialize(
        uint256 _protocolFeeRate,
        address _protocolAddress,
        address _pauserAddress
    ) external initializer {
        __Upgradeable_init(msg.sender, _pauserAddress);
        protocolFeeRate = _protocolFeeRate;
        protocolAddress = _protocolAddress;
        pauserAddress = _pauserAddress;
    }

    function setProtocolFeeRate(uint256 newFeeRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFeeRate != protocolFeeRate, "ProtocolConfig: New fee needs to be different");
        protocolFeeRate = newFeeRate;
        emit ProtocolFeeRateChanged(newFeeRate);
    }

    function setProtocolAddress(address newProtocolAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newProtocolAddress != protocolAddress, "ProtocolConfig: New protocol address needs to be different");
        protocolAddress = newProtocolAddress;
        emit ProtocolAddressChanged(newProtocolAddress);
    }

    function setPauserAddress(address newPauserAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newPauserAddress != pauserAddress, "ProtocolConfig: New pauser address needs to be different");
        pauserAddress = newPauserAddress;
        emit PauserAddressChanged(newPauserAddress);
    }
}
