// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import "./Exchange.sol";

interface IFactory {
    function getExchange(address _tokenAddress) external returns (address);
}

contract Factory is IFactory {
    mapping(address => address) public tokenToExchange;

    // create new Exchange contracts
    function createExchange(address _tokenAddress) public returns (address) {
        require(_tokenAddress != address(0), "real token needed");

        Exchange exchange = new Exchange(_tokenAddress);

        tokenToExchange[_tokenAddress] = address(exchange);

        return address(exchange);
    }

    function getExchange(address _tokenAddress) public view returns (address) {
        return tokenToExchange[_tokenAddress];
    }
}
