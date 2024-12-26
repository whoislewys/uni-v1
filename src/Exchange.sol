// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./Factory.sol";
// Allow swaps between ether <-> token1

contract Exchange is ERC20 {
    address public tokenAddress;
    address public factoryAddress; // link back to factory
    uint16 public DECIMALS = 1000;

    constructor(address _token) ERC20("Uniswap-V1", "UNI-V1") {
        require(_token != address(0), "invalid tok (0 address)");

        tokenAddress = _token;
        factoryAddress = msg.sender;
    }

    function getReserve() public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    // Get current exchange rate, assuming no slippage
    function getPriceV2(uint256 inputReserve, uint256 outputReserve) public view returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "invalid reserves");

        // multiply quote by DECIMALS to get enough precision for division
        // frontends would want to divide result by DECIMALS to display it correctly
        return inputReserve * DECIMALS / outputReserve;
    }

    /*
    _____                _              _   
    / ___|___  _ __  ___| |_ __ _ _ __ | |_ 
    | |   / _ \| '_ \/ __| __/ _` | '_ \| __|
    | |__| (_) | | | \__ \ || (_| | | | | |_ 
    \____\___/|_| |_|___/\__\__,_|_| |_|\__|
                                                
    ____                _            _   
    |  _ \ _ __ ___   __| |_   _  ___| |_ 
    | |_) | '__/ _ \ / _` | | | |/ __| __|
    |  __/| | | (_) | (_| | |_| | (__| |_ 
    |_|   |_|  \___/ \__,_|\__,_|\___|\__|
                                      
    Constant product pricing
    k = x * y
    k (liquidity) remains constant no matter what reserves of x and y are
    *every* trade will increase reserves of of either ether or token, or decrease reserve of either token or ether, and
    added liquidity can never be fully drained by trading.

    formula:
    (x + Δx)(y - Δy) = xy

    Δx is amount in, Δy amount out
    now we can find Δy:

    Δy = y*Δx / x + Δx

    let's code this up. note that we're now dealing with amounts to respond to a trade, not prices. we can come up with
    pricing function later after ensuring we can hold our constant product invariant.
    */

    // Note that because each trade decreases reserves of one token and increases reserves of the other, reserves are
    // infinite! They never get depleted by trading. The tradeoff is that there is now slippage with every trade.
    // function getAmountOg(
    //     uint256 inputAmount,
    //     uint256 inputReserve,
    //     uint256 outputReserve
    // )
    //     private
    //     pure
    //     returns (uint256)
    // {
    //     require(inputReserve > 0 && outputReserve > 0, "invalid reserves");

    //     return (outputReserve * inputAmount) / (inputReserve + inputAmount);
    // }

    function getAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    )
        private
        pure
        returns (uint256)
    {
        require(inputReserve > 0 && outputReserve > 0, "invalid reserves");

        // take 1 pct fee by subtracting from input amount.
        // in another environment, could do inputAmount * .99
        // but since solidity doesn't support fp division, have to multiply numerator and denominator by a power of 10.
        // Like 100, to get into percentage precision
        // so instead, inputAmountWithFee will be: inputAmount * .99 * 100 / 100
        // and the full swap formula:
        // outputReserve * (inputAmount * (100 - 1)) / inputReserve * 100 + (inputAmount * (100 - 1))

        uint256 inputAmountWithFee = inputAmount * 99;
        // uint256 numerator = inputAmountWithFee * outputReserve;

        return (outputReserve * inputAmountWithFee) / ((inputReserve * 100) + inputAmountWithFee);
    }

    // helper functions to simplify calcs
    function getTokenAmount(uint256 _ethSold) public view returns (uint256) {
        require(_ethSold > 0, "ethSold is too small");

        // could call getReserve for tok reserve too
        // return getAmount(_ethSold, address(this).balance, IERC20(tokenAddress).balanceOf(address(this)));
        return getAmount(_ethSold, address(this).balance, getReserve());
    }

    function getEthAmount(uint256 _tokenSold) public view returns (uint256) {
        require(_tokenSold > 0, "token sold too smol");

        return getAmount(_tokenSold, getReserve(), address(this).balance);
    }

    //
    // ______        ___    ____
    // / ___\ \      / / \  |  _ \
    // \___ \\ \ /\ / / _ \ | |_) |
    // ___) |\ V  V / ___ \|  __/
    // |____/  \_/\_/_/   \_\_|
    // let's get to swapping

    // Since we're going to use getAmount instead of getPrice to calculate how many tokens to send out in response to a
    // certain amount of tokens in (to implement a constant product invariant rather than constant sum invariant, which
    // keeps pools reserves from getting drained by swaps), we should create a function to swap which allows users to
    // specify a minimum amount of tokens out to receive, to avoid them getting surprised by the constant product mm's
    // slippage.
    //
    // Fees! ...
    //
    function ethToToken(uint256 _minTokens, address recipient) private {
        // user is sending in eth. get them a quote for tokens out, minus the eth sent in this call
        uint256 tokensToBuy = getAmount(msg.value, address(this).balance - msg.value, getReserve());

        require(tokensToBuy > _minTokens, "insufficient output amt");

        IERC20(tokenAddress).transfer(recipient, tokensToBuy);
    }

    function ethToTokenSwap(uint256 _minTokens) public payable {
        ethToToken(_minTokens, msg.sender);
    }

    function ethToTokenSwapWRecipient(uint256 _minTokens, address _recipient) public payable {
        ethToToken(_minTokens, _recipient);
    }

    function tokenToEthSwap(uint256 tokensToSell, uint256 _minEthOut) public {
        uint256 ethToBuy = getAmount(tokensToSell, getReserve(), address(this).balance);

        require(ethToBuy > _minEthOut, "insufficient output amt");

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), tokensToSell);
        // address(msg.sender).call{ value: ethToBuy }(""); // my vsn. solc lint complains tho
        payable(msg.sender).transfer(ethToBuy); // jeiwan vsn
    }

    //
    ////   _    ____  ____    _     ___ ___
    ////  / \  |  _ \|  _ \  | |   |_ _/ _ \
    //// / _ \ | | | | | | | | |    | | | | |
    /// / ___ \| |_| | |_| | | |___ | | |_| |
    // /_/   \_\____/|____/  |_____|___\__\_\
    // If there is already liquidity,
    // must ensure liquidity is added in the same ratio as current reserve,
    // so as to avoid disturbing current exchange rate. Otherwise, you'd create
    // a huge arb opportunity.

    // After adding liq, also issue LP tokens.
    // LP Tokens = shares of liquidity
    // Used to calculate proportions of fees each LP should earn.
    // Best design is to have infinite supply so that that as more people LP,
    // you can simply issue more tokens without having to recalculate balances of previously issued LP tokens.
    // Infinite supply of LP tokens is fine because each LP token would be backed by the exact amount of liquidity which
    // was LPd.
    // How to calculate liquidity shares aka LP balance to mint? Needs to be some proportion of eth, or token, or both?
    // Uni v1 does it in proporiton to eth deposited, like:
    // amountMinted = totalSupply * ethDeposited/ethReserve
    function addLiquidity(uint256 _tokenAmount) public payable returns (uint256) {
        if (getReserve() == 0) {
            // If no liquidity, allow initializing reserves to whatever the initializer wants

            // eth balance goes up automatically

            // transfer to move erc20 into pool
            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), _tokenAmount);

            uint256 liquidity = address(this).balance;
            _mint(msg.sender, liquidity);
            return liquidity;
        } else {
            uint256 ethReserve = address(this).balance - msg.value;
            uint256 tokenReserve = getReserve();

            // calculate tokenAmount - portion of input _tokenAmount to transfer to this exchange to maintain reserve
            // ratio exactly

            // Adding liquidity adds tokens (ΔT) and eth (ΔE).
            // Write formula so liq ratio of T/E is the same before and after adding liquidity:
            // (T + ΔT) / (E + ΔE) = T/E
            // Solving for ΔT, to figure out how much of _tokenAmount to use (can't use all or it might disturb the liq
            // ratio), results in
            // ΔT = (T * ΔE)/E
            uint256 dt = (tokenReserve * msg.value) / ethReserve;
            // Ensure user passed in enough tokens for calculated dt which preserves the liq ratio
            require(_tokenAmount >= dt, "insufficient token amount");

            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), dt);

            // mint LP tokens proportionally to amount of ETH deposited
            uint256 liquidity = totalSupply() * msg.value / ethReserve;
            _mint(msg.sender, liquidity);
            return liquidity;
        }
    }

    // Since shares of liquidity are accurately kept track of with LP tokens, we can easily determine how much liquidity
    // to remove when an LP wants to withdraw.
    // Of course, since the price is likely different than the time of deposit, and therefore the ratio of token / eth
    // reserves is likely different, the ratio of tokens in the removed liquidity will likely be different than the
    // ratio the LPer deposited.
    // Calculating removed amounts with lp shares supply of sender looks like:
    // removedAmount = reserve * amountLP / totalAmountLP
    // eth_reserve is used because LP shares are minted based on amounts of eth deposited
    // This includes fees, since inputAmount was subtracted from in the swap function, leading to increases in reserves
    function removeLiquidity(uint256 _amount) public returns (uint256 ethAmount, uint256 tokenAmount) {
        require(_amount > 0, "must remove more than 0 liquidity");

        ethAmount = address(this).balance * _amount / totalSupply();
        tokenAmount = getReserve() * _amount / totalSupply();

        _burn(msg.sender, _amount);

        payable(msg.sender).transfer(ethAmount);

        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
    }

    // 1. Start token -> eth swap
    // 2. instead of sending eth, look at the factory to find an Exchange for the desired output token
    // 3. If exchange exists, send eth to exchange, send received token back to user (kinda sucks for swapper that they
    // pay double fees but whateva). If no exchange exists, revert since output token can't be received
    // 4. Return swapped toks to user.
    function tokenToTokenSwap(uint256 _tokensSold, uint256 _minOut, address _tokenAddress) public {
        address outputTokenExchange = IFactory(factoryAddress).getExchange(_tokenAddress);

        require(outputTokenExchange != address(this), "desired output token is same as input token");
        require(outputTokenExchange != address(0), "exchange for output token does not exist");

        // start standard token -> eth swap with user's input tokens
        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(_tokensSold, tokenReserve, address(this).balance);

        // take user's tokens
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), _tokensSold);

        // take the eth and try to swap with output exchange for output token
        // Exchange(outputTokenExchange).ethToTokenSwap{ value: ethBought }(_minOut); // SIKE. this would rug the user,
        // sending desired output tokens to this Exchange contract.

        Exchange(outputTokenExchange).ethToTokenSwapWRecipient{ value: ethBought }(_minOut, msg.sender); // SIKE. this
            // would rug the user,
            // So, can transfer the tokens out of the Exchange contract back to the user. However, there's a better
            // solution.
    }
}
